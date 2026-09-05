import Foundation

enum TrustedPlaceSearchField: String, CaseIterable, Hashable {
    case name
    case owner
    case category
    case area
    case note
    case attribute
    case status
}

struct TrustedPlaceSearchEvidence: Equatable {
    let field: TrustedPlaceSearchField
    let displayValue: String
    let matchedTokens: [String]
}

struct TrustedPlaceSearchQuery: Equatable {
    let originalText: String
    let normalizedPhrase: String
    let scoringTokens: [String]
    let requiredTokens: [String]
    let consumedTokens: [String]
    fileprivate let scoringPhrase: String
    fileprivate let requiredTokenIndexes: [Int]

    var hasMeaningfulTokens: Bool {
        !scoringTokens.isEmpty
    }

    var allowsConsumedOnlyMatches: Bool {
        requiredTokens.isEmpty && !consumedTokens.isEmpty
    }

    init(_ text: String, consumedPhrases: [String] = []) {
        originalText = text
        let rawTokens = TrustedPlaceSearchText.tokens(in: text)
        normalizedPhrase = rawTokens.joined(separator: " ")

        let consumedIndexes = TrustedPlaceSearchText.consumedTokenIndexes(
            in: rawTokens,
            matching: consumedPhrases
        )
        var scoring: [String] = []
        var required: [String] = []
        var consumed: [String] = []

        for (index, token) in rawTokens.enumerated() where !TrustedPlaceSearchText.stopWords.contains(token) {
            TrustedPlaceSearchText.appendUnique(token, to: &scoring)
            if consumedIndexes.contains(index) {
                TrustedPlaceSearchText.appendUnique(token, to: &consumed)
            } else {
                TrustedPlaceSearchText.appendUnique(token, to: &required)
            }
        }

        scoringTokens = scoring
        requiredTokens = required
        consumedTokens = consumed
        scoringPhrase = scoring.joined(separator: " ")
        requiredTokenIndexes = required.compactMap { scoring.firstIndex(of: $0) }
    }
}

struct TrustedPlaceSearchMatch {
    let place: VisiblePlace
    let score: Int
    let evidence: [TrustedPlaceSearchEvidence]
    let supportingFields: Set<TrustedPlaceSearchField>
    fileprivate let savedAt: Date
    fileprivate let stableID: String

    init(
        place: VisiblePlace,
        score: Int,
        evidence: [TrustedPlaceSearchEvidence],
        supportingFields: Set<TrustedPlaceSearchField>? = nil
    ) {
        self.place = place
        self.score = score
        self.evidence = evidence
        self.supportingFields = supportingFields ?? Set(evidence.map(\.field))
        savedAt = place.userPlace.savedAt
        stableID = place.userPlace.id
    }
}

enum TrustedPlaceSearch {
    private static let documentCache = TrustedPlaceSearchDocumentCache(capacity: 4_096)

    static func matches(
        query text: String,
        in places: [VisiblePlace],
        consumedPhrases: [String] = []
    ) -> [TrustedPlaceSearchMatch] {
        matches(
            query: TrustedPlaceSearchQuery(text, consumedPhrases: consumedPhrases),
            in: places
        )
    }

    static func matches(
        query: TrustedPlaceSearchQuery,
        in places: [VisiblePlace]
    ) -> [TrustedPlaceSearchMatch] {
        guard query.hasMeaningfulTokens else { return [] }

        let documents = documentCache.documents(for: places)
        return zip(places, documents).compactMap { place, document in
            match(query: query, place: place, document: document)
        }
        .sorted(by: isOrderedBefore)
    }

    private static func match(
        query: TrustedPlaceSearchQuery,
        place: VisiblePlace,
        document: TrustedPlaceSearchDocument
    ) -> TrustedPlaceSearchMatch? {
        var tokenMatches: [TrustedPlaceSearchDocument.TokenMatch?] = []
        tokenMatches.reserveCapacity(query.scoringTokens.count)

        for token in query.scoringTokens {
            tokenMatches.append(document.bestMatch(for: token))
        }

        guard query.requiredTokenIndexes.allSatisfy({ tokenMatches[$0] != nil }) else {
            return nil
        }
        guard !query.requiredTokens.isEmpty || query.allowsConsumedOnlyMatches else {
            return nil
        }

        var score = tokenMatches.reduce(0) { $0 + ($1?.score ?? 0) }
        score += document.phraseBonus(for: query.scoringPhrase)

        var evidenceByField: [TrustedPlaceSearchField: (displayValue: String, tokens: [String])] = [:]
        for match in tokenMatches.compactMap({ $0 }) {
            if evidenceByField[match.field] == nil {
                evidenceByField[match.field] = (match.displayValue, [])
            }
            evidenceByField[match.field]?.tokens.append(match.token)
        }
        let evidence = TrustedPlaceSearchField.allCases.compactMap { field in
            evidenceByField[field].map {
                TrustedPlaceSearchEvidence(
                    field: field,
                    displayValue: $0.displayValue,
                    matchedTokens: $0.tokens
                )
            }
        }

        return TrustedPlaceSearchMatch(
            place: place,
            score: score,
            evidence: evidence,
            supportingFields: document.supportingFields(for: query.scoringTokens)
        )
    }

    private static func isOrderedBefore(
        _ lhs: TrustedPlaceSearchMatch,
        _ rhs: TrustedPlaceSearchMatch
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.savedAt != rhs.savedAt {
            return lhs.savedAt > rhs.savedAt
        }
        return lhs.stableID < rhs.stableID
    }
}

struct MapSearchSavedCandidate {
    let group: VisiblePlaceGroup
    let match: TrustedPlaceSearchMatch

    var place: VisiblePlace {
        group.primary
    }
}

enum MapSearchCandidate {
    case saved(MapSearchSavedCandidate)
    case mapKit(PlaceCandidate)
}

enum MapSearchCandidatePolicy {
    enum SavedStrength: Equatable {
        case strong
        case contextual
    }

    static let strongFields: Set<TrustedPlaceSearchField> = [
        .name,
        .category,
        .area
    ]

    static let contextualFields: Set<TrustedPlaceSearchField> = [
        .owner,
        .note,
        .attribute,
        .status
    ]

    static func savedCandidates(
        query text: String,
        in places: [VisiblePlace],
        currentUserID: String
    ) -> [MapSearchSavedCandidate] {
        savedCandidates(
            query: TrustedPlaceSearchQuery(text),
            in: places,
            currentUserID: currentUserID
        )
    }

    static func savedCandidates(
        query: TrustedPlaceSearchQuery,
        in places: [VisiblePlace],
        currentUserID: String
    ) -> [MapSearchSavedCandidate] {
        let matches = TrustedPlaceSearch.matches(query: query, in: places)
        guard !matches.isEmpty else { return [] }

        let groups = VisiblePlaceGrouping.groups(
            from: places,
            currentUserID: currentUserID
        )
        var groupByUserPlaceID: [String: VisiblePlaceGroup] = [:]
        groupByUserPlaceID.reserveCapacity(places.count)
        var groupByKey: [String: VisiblePlaceGroup] = [:]
        groupByKey.reserveCapacity(groups.count)
        for group in groups {
            groupByKey[group.key] = group
            for place in group.places {
                groupByUserPlaceID[place.userPlace.id] = group
            }
        }

        var orderedGroupKeys: [String] = []
        var firstMatchByGroupKey: [String: TrustedPlaceSearchMatch] = [:]
        var supportingFieldsByGroupKey: [String: Set<TrustedPlaceSearchField>] = [:]
        for match in matches {
            guard let group = groupByUserPlaceID[match.place.userPlace.id] else { continue }
            if firstMatchByGroupKey[group.key] == nil {
                orderedGroupKeys.append(group.key)
                firstMatchByGroupKey[group.key] = match
            }
            supportingFieldsByGroupKey[group.key, default: []]
                .formUnion(match.supportingFields)
        }

        return orderedGroupKeys.compactMap { groupKey in
            guard let group = groupByKey[groupKey],
                  let firstMatch = firstMatchByGroupKey[groupKey]
            else { return nil }

            let groupedMatch = TrustedPlaceSearchMatch(
                place: firstMatch.place,
                score: firstMatch.score,
                evidence: firstMatch.evidence,
                supportingFields: supportingFieldsByGroupKey[groupKey, default: []]
            )
            return MapSearchSavedCandidate(group: group, match: groupedMatch)
        }
    }

    static func candidates(
        query: String,
        in places: [VisiblePlace],
        mapKit: [PlaceCandidate],
        currentUserID: String
    ) -> [MapSearchCandidate] {
        orderedCandidates(
            query: query,
            saved: savedCandidates(
                query: query,
                in: places,
                currentUserID: currentUserID
            ),
            mapKit: mapKit
        )
    }

    static func orderedCandidates(
        query: String,
        saved: [MapSearchSavedCandidate],
        mapKit: [PlaceCandidate]
    ) -> [MapSearchCandidate] {
        let queryIntent = MapSearchQueryPolicy.intent(for: query)
        let strongSavedCandidates = saved.filter { strength(of: $0) == .strong }
        let contextualSaved = saved
            .filter { strength(of: $0) == .contextual }
            .map(MapSearchCandidate.saved)

        if queryIntent == .category {
            return strongSavedCandidates.map(MapSearchCandidate.saved)
                + mapKit.map(MapSearchCandidate.mapKit)
                + contextualSaved
        }

        let exactSaved = strongSavedCandidates
            .filter { hasExactNameMatch($0, query: query) }
            .map(MapSearchCandidate.saved)
        let otherStrongSaved = strongSavedCandidates
            .filter { !hasExactNameMatch($0, query: query) }
            .map(MapSearchCandidate.saved)
        let exactMapKit = mapKit
            .filter {
                MapSearchQueryPolicy.isExactNameMatch($0.name, query: query)
            }
            .map(MapSearchCandidate.mapKit)
        let partialMapKit = mapKit
            .filter {
                MapSearchQueryPolicy.hasNameMatch($0.name, query: query)
                    && !MapSearchQueryPolicy.isExactNameMatch($0.name, query: query)
            }
            .map(MapSearchCandidate.mapKit)
        let unrelatedMapKit = mapKit
            .filter {
                !MapSearchQueryPolicy.hasNameMatch($0.name, query: query)
            }
            .map(MapSearchCandidate.mapKit)

        return exactSaved
            + exactMapKit
            + otherStrongSaved
            + partialMapKit
            + contextualSaved
            + unrelatedMapKit
    }

    static func nameLexicalScore(
        of candidate: MapSearchSavedCandidate,
        query: String
    ) -> Double {
        candidate.group.places
            .map {
                MapSearchQueryPolicy.lexicalScore(
                    forName: $0.place.canonicalName,
                    query: query
                )
            }
            .max() ?? 0
    }

    static func hasExactNameMatch(
        _ candidate: MapSearchSavedCandidate,
        query: String
    ) -> Bool {
        candidate.group.places.contains {
            MapSearchQueryPolicy.isExactNameMatch(
                $0.place.canonicalName,
                query: query
            )
        }
    }

    static func strength(of candidate: MapSearchSavedCandidate) -> SavedStrength {
        strength(of: candidate.match)
    }

    static func strength(of match: TrustedPlaceSearchMatch) -> SavedStrength {
        match.supportingFields.isDisjoint(with: strongFields) ? .contextual : .strong
    }

    static func providerSlotCount(in saved: [MapSearchSavedCandidate]) -> Int {
        saved.reduce(into: 0) { count, candidate in
            if strength(of: candidate) == .strong {
                count += 1
            }
        }
    }

    static func contains(
        _ candidate: PlaceCandidate,
        in saved: [MapSearchSavedCandidate]
    ) -> Bool {
        saved.contains { savedCandidate in
            savedCandidate.group.places.contains {
                VisiblePlaceGrouping.matches($0, candidate: candidate)
            }
        }
    }
}

enum DiscoverPlaceSearchCandidate: Identifiable {
    case trusted(VisiblePlaceGroup)
    case recme(PlaceCandidate)
    case external(PlaceCandidate)

    var id: String {
        switch self {
        case .trusted(let group):
            "trusted|\(group.key)"
        case .recme(let candidate):
            "recme|\(candidate.id)"
        case .external(let candidate):
            "external|\(candidate.id)"
        }
    }
}

enum DiscoverExternalPlaceSearchPlanner {
    private static let fallbackQualifierTokens: Set<String> = [
        "best", "cozy", "date", "easy", "favorite", "good", "great", "highly",
        "late", "loved", "night", "pastry", "quiet", "rated", "top",
        "view", "weekend", "wifi", "worth"
    ]

    static func input(query: String, filters: DiscoverFilters) -> ManualPlaceInput? {
        guard filters.relationship == nil,
              filters.ownerQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              filters.statuses.isEmpty || filters.opinion == .favorite
        else {
            return nil
        }

        let queryPlan = TrustedPlaceSearchQuery(
            query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )
        let parsedCategory = filters.categories
            .map(WanderPlaceCategory.normalizedPrimaryCategory)
            .sorted()
            .first
        let inferredCategory = parsedCategory == nil ? inferredCategoryMatch(in: query) : nil
        let category = parsedCategory ?? inferredCategory?.entry.id
        let taxonomyEntry = category.flatMap { category in
            WanderPlaceCategory.taxonomy.first { $0.id == category }
        }
        let providerQueryPlan: TrustedPlaceSearchQuery
        if let inferredCategory {
            var inferredFilters = filters
            inferredFilters.categories.insert(inferredCategory.entry.id)
            providerQueryPlan = TrustedPlaceSearchQuery(
                query,
                consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: inferredFilters)
            )
        } else {
            providerQueryPlan = queryPlan
        }
        let requiredQuery = providerQueryPlan.requiredTokens.joined(separator: " ")
        let matchedCategoryTokens = Set(
            taxonomyEntry
                .flatMap { matchedCategoryTerm(in: query, entry: $0) }
                .map(normalizedTokens) ?? []
        )
        let nonCategoryTokens = normalizedTokens(requiredQuery)
            .filter { !matchedCategoryTokens.contains($0) }
        let usesCategoryFallback = nonCategoryTokens.isEmpty
            || nonCategoryTokens.allSatisfy(fallbackQualifierTokens.contains)
        let providerQuery: String
        if let taxonomyEntry, usesCategoryFallback {
            providerQuery = matchedCategoryTerm(in: query, entry: taxonomyEntry)
                ?? taxonomyEntry.defaultSubcategory
                ?? taxonomyEntry.group
        } else if !requiredQuery.isEmpty {
            providerQuery = requiredQuery
        } else {
            providerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let providerCategory = parsedCategory != nil || usesCategoryFallback
            ? category
            : nil

        guard !providerQuery.isEmpty else { return nil }
        return ManualPlaceInput(
            name: providerQuery,
            areaHint: filters.area,
            category: providerCategory
        )
    }

    private static func inferredCategoryMatch(
        in query: String
    ) -> (entry: PlaceCategoryTaxonomyEntry, term: String)? {
        WanderPlaceCategory.taxonomy
            .compactMap { entry -> (entry: PlaceCategoryTaxonomyEntry, term: String)? in
                guard let term = matchedCategoryTerm(in: query, entry: entry) else { return nil }
                return (entry, term)
            }
            .sorted { lhs, rhs in
                let lhsCount = normalizedTokens(lhs.term).count
                let rhsCount = normalizedTokens(rhs.term).count
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.term.count > rhs.term.count
            }
            .first
    }

    private static func matchedCategoryTerm(
        in query: String,
        entry: PlaceCategoryTaxonomyEntry
    ) -> String? {
        let queryTokens = normalizedTokens(query)
        return ([entry.group, entry.defaultSubcategory].compactMap { $0 }
            + entry.aliases
            + entry.subcategories)
            .filter { term in
                let termTokens = normalizedTokens(term)
                guard !termTokens.isEmpty, termTokens.count <= queryTokens.count else { return false }
                return queryTokens.indices.contains { start in
                    let end = start + termTokens.count
                    guard end <= queryTokens.count else { return false }
                    return Array(queryTokens[start..<end]) == termTokens
                }
            }
            .sorted { lhs, rhs in
                let lhsCount = normalizedTokens(lhs).count
                let rhsCount = normalizedTokens(rhs).count
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.count > rhs.count
            }
            .first
            .map { normalizedTokens($0).joined(separator: " ") }
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { token in
                let value = String(token)
                if value.hasSuffix("ies"), value.count > 3 {
                    return String(value.dropLast(3)) + "y"
                }
                if value.hasSuffix("s"), value.count > 3 {
                    return String(value.dropLast())
                }
                return value
            }
    }
}

enum DiscoverPlaceSearchRankingPolicy {
    static let version = "discover_cross_corpus_v1"

    private struct ScoredCandidate {
        let candidate: DiscoverPlaceSearchCandidate
        let relevance: Int
        let sourcePriority: Int
        let originalIndex: Int
    }

    static func orderedCandidates(
        query: String,
        filters: DiscoverFilters,
        trusted: [VisiblePlaceGroup],
        recme: [PlaceCandidate],
        external: [PlaceCandidate],
        limit: Int = 24
    ) -> [DiscoverPlaceSearchCandidate] {
        guard limit > 0 else { return [] }
        let queryPlan = TrustedPlaceSearchQuery(
            query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )
        let nameQuery = queryPlan.requiredTokens.isEmpty && filters.hasRecognizedFacet
            ? ""
            : (queryPlan.requiredTokens.isEmpty
                ? query
                : queryPlan.requiredTokens.joined(separator: " "))

        var uniqueRecme: [PlaceCandidate] = []
        for candidate in recme {
            guard !trustedContains(candidate, trusted: trusted),
                  !uniqueRecme.contains(where: { matches($0, candidate) })
            else { continue }
            uniqueRecme.append(candidate)
        }

        var uniqueExternal: [PlaceCandidate] = []
        for candidate in external {
            guard !trustedContains(candidate, trusted: trusted),
                  !uniqueRecme.contains(where: { matches($0, candidate) }),
                  !uniqueExternal.contains(where: { matches($0, candidate) })
            else { continue }
            uniqueExternal.append(candidate)
        }

        let scoredTrusted = trusted.enumerated().map { index, group in
            ScoredCandidate(
                candidate: .trusted(group),
                relevance: relevance(
                    names: group.places.map { $0.place.canonicalName },
                    categories: group.places.map { $0.categoryPresentation.assignment.primaryCategory },
                    areaValues: group.places.flatMap {
                        [$0.place.address, $0.place.locality, $0.place.region, $0.place.country].compactMap { $0 }
                    },
                    query: nameQuery,
                    filters: filters
                ),
                sourcePriority: 3,
                originalIndex: index
            )
        }
        let scoredRecme = uniqueRecme.enumerated().map { index, candidate in
            scored(
                .recme(candidate),
                candidate: candidate,
                query: nameQuery,
                filters: filters,
                sourcePriority: 2,
                originalIndex: index
            )
        }
        let scoredExternal = uniqueExternal.enumerated().map { index, candidate in
            scored(
                .external(candidate),
                candidate: candidate,
                query: nameQuery,
                filters: filters,
                sourcePriority: 1,
                originalIndex: index
            )
        }

        return (scoredTrusted + scoredRecme + scoredExternal)
            .sorted { lhs, rhs in
                if lhs.relevance != rhs.relevance {
                    return lhs.relevance > rhs.relevance
                }
                if lhs.sourcePriority != rhs.sourcePriority {
                    return lhs.sourcePriority > rhs.sourcePriority
                }
                if lhs.originalIndex != rhs.originalIndex {
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.candidate.id < rhs.candidate.id
            }
            .prefix(limit)
            .map(\.candidate)
    }

    private static func scored(
        _ result: DiscoverPlaceSearchCandidate,
        candidate: PlaceCandidate,
        query: String,
        filters: DiscoverFilters,
        sourcePriority: Int,
        originalIndex: Int
    ) -> ScoredCandidate {
        ScoredCandidate(
            candidate: result,
            relevance: relevance(
                names: [candidate.name],
                categories: [candidate.primaryCategory],
                areaValues: [candidate.address, candidate.locality, candidate.region, candidate.country]
                    .compactMap { $0 },
                query: query,
                filters: filters
            ),
            sourcePriority: sourcePriority,
            originalIndex: originalIndex
        )
    }

    private static func relevance(
        names: [String],
        categories: [String],
        areaValues: [String],
        query: String,
        filters: DiscoverFilters
    ) -> Int {
        var score = names
            .map { Int(MapSearchQueryPolicy.lexicalScore(forName: $0, query: query)) }
            .max() ?? 0

        let requestedCategories = Set(
            filters.categories.map(WanderPlaceCategory.normalizedPrimaryCategory)
        )
        let candidateCategories = Set(
            categories.map(WanderPlaceCategory.normalizedPrimaryCategory)
        )
        if !requestedCategories.isDisjoint(with: candidateCategories) {
            score = max(score, 360)
        }

        if let area = filters.area,
           areaValues.contains(where: { containsPhrase($0, phrase: area) }) {
            score = max(score, 240)
        }

        // The provider and trusted-memory layers have already applied their own
        // semantic/filter matching. Keep those candidates eligible even when
        // their place name does not contain the natural-language query.
        return max(score, 120)
    }

    private static func trustedContains(
        _ candidate: PlaceCandidate,
        trusted: [VisiblePlaceGroup]
    ) -> Bool {
        trusted.contains { group in
            group.places.contains { VisiblePlaceGrouping.matches($0, candidate: candidate) }
        }
    }

    private static func matches(_ lhs: PlaceCandidate, _ rhs: PlaceCandidate) -> Bool {
        if let lhsProviderID = normalized(lhs.sourceProviderPlaceID),
           let rhsProviderID = normalized(rhs.sourceProviderPlaceID),
           normalized(lhs.sourceProvider) == normalized(rhs.sourceProvider),
           lhsProviderID == rhsProviderID {
            return true
        }

        guard canonicalName(lhs.name) == canonicalName(rhs.name),
              let lhsLatitude = lhs.latitude,
              let lhsLongitude = lhs.longitude,
              let rhsLatitude = rhs.latitude,
              let rhsLongitude = rhs.longitude
        else {
            return false
        }
        return abs(lhsLatitude - rhsLatitude) <= 0.00075
            && abs(lhsLongitude - rhsLongitude) <= 0.00075
    }

    private static func containsPhrase(_ value: String, phrase: String) -> Bool {
        canonicalName(value).contains(canonicalName(phrase))
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}

private final class TrustedPlaceSearchDocumentCache: @unchecked Sendable {
    private struct Revision: Equatable {
        let placeUpdatedAt: Date
        let userPlaceUpdatedAt: Date
        let ownerUpdatedAt: Date
        let attributeSignature: Int

        init(place: VisiblePlace) {
            placeUpdatedAt = place.place.updatedAt
            userPlaceUpdatedAt = place.userPlace.updatedAt
            ownerUpdatedAt = place.owner.updatedAt
            var hasher = Hasher()
            hasher.combine(place.attributes.count)
            for attribute in place.attributes {
                hasher.combine(attribute.id)
                hasher.combine(attribute.updatedAt)
            }
            attributeSignature = hasher.finalize()
        }
    }

    private struct Entry {
        let revision: Revision
        let document: TrustedPlaceSearchDocument
    }

    private let capacity: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func documents(for places: [VisiblePlace]) -> [TrustedPlaceSearchDocument] {
        let revisions = places.map(Revision.init)
        lock.lock()
        var result = Array<TrustedPlaceSearchDocument?>(repeating: nil, count: places.count)
        var missingIndexes: [Int] = []
        missingIndexes.reserveCapacity(places.count)
        for index in places.indices {
            let key = places[index].userPlace.id
            if let entry = entries[key], entry.revision == revisions[index] {
                result[index] = entry.document
            } else {
                missingIndexes.append(index)
            }
        }
        lock.unlock()

        for index in missingIndexes {
            result[index] = TrustedPlaceSearchDocument(place: places[index])
        }

        lock.lock()
        defer { lock.unlock() }
        for index in missingIndexes {
            let key = places[index].userPlace.id
            guard let document = result[index] else { continue }
            if entries[key] == nil {
                insertionOrder.append(key)
            }
            entries[key] = Entry(revision: revisions[index], document: document)
        }
        if entries.count > capacity {
            let overflow = entries.count - capacity
            for key in insertionOrder.prefix(overflow) {
                entries.removeValue(forKey: key)
            }
            insertionOrder.removeFirst(min(overflow, insertionOrder.count))
        }
        return result.compactMap { $0 }
    }
}

enum DiscoverTrustedPlaceSearchPlanner {
    static func consumedPhrases(for filters: DiscoverFilters) -> [String] {
        var phrases: [String] = []

        for category in filters.categories {
            let normalizedCategory = WanderPlaceCategory.normalizedPrimaryCategory(category)
            if let entry = WanderPlaceCategory.taxonomy.first(where: { $0.id == normalizedCategory }) {
                phrases.append(entry.group)
                phrases.append(entry.id.replacingOccurrences(of: "_", with: " "))
                phrases.append(contentsOf: entry.aliases)
                phrases.append(contentsOf: DiscoverCategoryAliasLexicon.aliases[normalizedCategory, default: []])
                if let defaultSubcategory = entry.defaultSubcategory {
                    phrases.append(defaultSubcategory)
                }
            } else {
                phrases.append(category)
            }
        }

        if let area = filters.area {
            phrases.append(area)
            phrases.append(contentsOf: areaAliases(for: area))
        }

        if let ownerQuery = filters.ownerQuery {
            phrases.append(ownerQuery.replacingOccurrences(of: "@", with: ""))
        }

        for status in filters.statuses {
            switch status {
            case .been:
                phrases.append(contentsOf: [
                    "been", "went", "tried", "visited", "checked in", "check in", "check ins", "liked", "recommended"
                ])
            case .wannaGo:
                phrases.append(contentsOf: [
                    "wanna", "wanna go", "want", "want to go", "want to try", "try", "wishlist", "saved", "saved for later"
                ])
            }
        }

        switch filters.relationship {
        case .owner:
            phrases.append(contentsOf: ["mine", "my"])
        case .mutual:
            phrases.append(contentsOf: ["friend", "friends", "mutual", "mutuals"])
        case .follower:
            phrases.append(contentsOf: ["people", "people i follow", "people you follow", "from people", "following"])
        case .nonFollower:
            phrases.append(contentsOf: ["not following", "people i don't follow"])
        case nil:
            break
        }

        if filters.opinion == .favorite {
            phrases.append(contentsOf: [
                "favorite", "favourite", "best", "loved", "highly rated", "worth crossing town for"
            ])
        }

        for tag in filters.tags {
            phrases.append(tag)
            phrases.append(contentsOf: tagAliases(for: tag))
        }

        return TrustedPlaceSearchText.uniqueNormalizedPhrases(phrases)
    }

    private static func areaAliases(for area: String) -> [String] {
        switch TrustedPlaceSearchText.phrase(area) {
        case "la", "los angeles":
            ["la", "los angeles"]
        case "nyc", "new york", "new york city":
            ["nyc", "new york", "new york city"]
        case "sf", "san francisco":
            ["sf", "san francisco"]
        default:
            []
        }
    }

    private static func tagAliases(for tag: String) -> [String] {
        switch TrustedPlaceSearchText.phrase(tag) {
        case "work", "working":
            ["work", "working"]
        case "wifi", "wi fi":
            ["wifi", "wi fi"]
        case "date", "date night":
            ["date", "date night"]
        case "views", "view":
            ["view", "views"]
        default:
            []
        }
    }
}

enum DiscoverRecmePlaceSearchPlanner {
    static func request(
        query: String,
        filters: DiscoverFilters,
        limit: Int = 20
    ) -> RecmePlaceSearchRequest {
        let queryPlan = TrustedPlaceSearchQuery(
            query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )

        return RecmePlaceSearchRequest(
            query: queryPlan.requiredTokens.joined(separator: " "),
            semanticQuery: query,
            categories: filters.categories
                .map(WanderPlaceCategory.normalizedPrimaryCategory)
                .sorted(),
            area: filters.area,
            favoriteOnly: filters.opinion == .favorite,
            scope: scope(for: filters.relationship),
            limit: limit
        )
    }

    private static func scope(for relationship: ViewerRelationship?) -> RecmePlaceSearchScope {
        switch relationship {
        case .owner:
            .mine
        case .mutual:
            .friends
        case .follower:
            .following
        case .nonFollower, nil:
            .everyone
        }
    }
}

private struct TrustedPlaceSearchDocument {
    struct TokenMatch {
        let token: String
        let field: TrustedPlaceSearchField
        let displayValue: String
        let score: Int
    }

    private struct FieldValue {
        let field: TrustedPlaceSearchField
        let displayValue: String
        let normalizedTokens: [String]
        let normalizedPhrase: String
        let weight: Int

    }

    private let fields: [FieldValue]
    private let exactMatches: [String: TokenMatch]
    private let exactSupportingFields: [String: Set<TrustedPlaceSearchField>]

    init(place: VisiblePlace) {
        var values: [FieldValue] = []
        let categoryPresentation = place.categoryPresentation
        let categoryDisplay = categoryPresentation.display

        Self.append(.name, weight: 60, values: [place.place.canonicalName], to: &values)
        Self.append(
            .owner,
            weight: 42,
            values: [place.owner.displayName, place.owner.handle, "@\(place.owner.handle)"],
            to: &values
        )
        Self.append(
            .category,
            weight: 32,
            values: [
                categoryDisplay.category,
                categoryDisplay.subcategory,
                categoryPresentation.compactType,
                categoryPresentation.assignment.primaryCategory,
                categoryPresentation.assignment.subcategory,
                categoryPresentation.restaurantCuisine,
                place.place.category,
                place.place.rawProviderType
            ],
            to: &values
        )
        Self.append(
            .area,
            weight: 24,
            values: [
                place.place.address,
                place.place.locality,
                place.place.region,
                place.place.country
            ],
            to: &values
        )
        Self.append(
            .note,
            weight: 16,
            values: [place.userPlace.note, place.userPlace.historicalWantNote],
            to: &values
        )
        Self.append(
            .attribute,
            weight: 14,
            values: place.attributes.flatMap { attribute in
                PlaceAttributeValuePresentation.strings(from: attribute.valueJSON)
            } + place.userPlace.historicalWantTags,
            to: &values
        )
        Self.append(
            .status,
            weight: 8,
            values: [place.userPlace.status.displayTitle, place.userPlace.status.rawValue, place.userPlace.ratingSignal],
            to: &values
        )

        fields = values
        var matches: [String: TokenMatch] = [:]
        var supportingFields: [String: Set<TrustedPlaceSearchField>] = [:]
        for field in values {
            for token in field.normalizedTokens {
                supportingFields[token, default: []].insert(field.field)
                let candidate = TokenMatch(
                    token: token,
                    field: field.field,
                    displayValue: field.displayValue,
                    score: field.weight
                )
                if let current = matches[token] {
                    if Self.isBetter(candidate, than: current) {
                        matches[token] = candidate
                    }
                } else {
                    matches[token] = candidate
                }
            }
        }
        exactMatches = matches
        exactSupportingFields = supportingFields
    }

    func bestMatch(for queryToken: String) -> TokenMatch? {
        if let exact = exactMatches[queryToken] {
            return exact
        }
        guard queryToken.count >= 3 else { return nil }

        var best: TokenMatch?
        for field in fields {
            guard field.normalizedTokens.contains(where: { $0.hasPrefix(queryToken) }) else { continue }
            let candidate = TokenMatch(
                token: queryToken,
                field: field.field,
                displayValue: field.displayValue,
                score: max(1, field.weight * 4 / 5)
            )
            guard let current = best else {
                best = candidate
                continue
            }
            if Self.isBetter(candidate, than: current) {
                best = candidate
            }
        }
        return best
    }

    func supportingFields(for queryTokens: [String]) -> Set<TrustedPlaceSearchField> {
        var result = Set<TrustedPlaceSearchField>()
        for queryToken in queryTokens {
            if let exactFields = exactSupportingFields[queryToken] {
                result.formUnion(exactFields)
                continue
            }
            guard queryToken.count >= 3 else { continue }
            for field in fields where field.normalizedTokens.contains(where: { $0.hasPrefix(queryToken) }) {
                result.insert(field.field)
            }
        }
        return result
    }

    private static func isBetter(_ candidate: TokenMatch, than current: TokenMatch) -> Bool {
        candidate.score > current.score
            || (candidate.score == current.score && candidate.field.rawValue < current.field.rawValue)
    }

    func phraseBonus(for phrase: String) -> Int {
        guard !phrase.isEmpty else { return 0 }
        var best = 0

        for field in fields {
            let fieldPhrase = field.normalizedPhrase
            let multiplier: Int
            if fieldPhrase == phrase {
                multiplier = 5
            } else if fieldPhrase.hasPrefix(phrase + " ") {
                multiplier = 4
            } else if fieldPhrase.contains(" " + phrase + " ")
                        || fieldPhrase.hasSuffix(" " + phrase) {
                multiplier = 3
            } else {
                continue
            }
            best = max(best, field.weight * multiplier)
        }
        return best
    }

    private static func append(
        _ field: TrustedPlaceSearchField,
        weight: Int,
        values: [String?],
        to result: inout [FieldValue]
    ) {
        append(field, weight: weight, values: values.compactMap { $0 }, to: &result)
    }

    private static func append(
        _ field: TrustedPlaceSearchField,
        weight: Int,
        values: [String],
        to result: inout [FieldValue]
    ) {
        for value in values {
            let tokens = TrustedPlaceSearchText.tokens(in: value)
            guard !tokens.isEmpty else { continue }
            result.append(
                FieldValue(
                    field: field,
                    displayValue: value,
                    normalizedTokens: tokens,
                    normalizedPhrase: tokens.joined(separator: " "),
                    weight: weight
                )
            )
        }
    }
}

private enum TrustedPlaceSearchText {
    static let stopWords: Set<String> = [
        "a", "an", "and", "at", "find", "for", "give", "in", "me", "of", "or",
        "place", "places", "please", "show", "spot", "spots", "that", "the", "to", "with"
    ]

    private static let canonicalAliases: [String: String] = [
        "cafe": "coffee",
        "cafes": "coffee",
        "coffee": "coffee",
        "coffees": "coffee",
        "favourite": "favorite",
        "favorite": "favorite",
        "working": "work",
        "work": "work"
    ]

    static func phrase(_ value: String) -> String {
        tokens(in: value).joined(separator: " ")
    }

    static func tokens(in value: String) -> [String] {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        var result: [String] = []
        var current = ""
        current.reserveCapacity(16)

        func appendCurrentToken() {
            guard !current.isEmpty else { return }
            let value: String
            if current.hasSuffix("'s") {
                value = String(current.dropLast(2))
            } else {
                value = current
            }
            if !value.isEmpty {
                result.append(canonicalAliases[value] ?? value)
            }
            current.removeAll(keepingCapacity: true)
        }

        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "’" {
                current.append("'")
            } else {
                appendCurrentToken()
            }
        }
        appendCurrentToken()
        return result
    }

    static func uniqueNormalizedPhrases(_ phrases: [String]) -> [String] {
        var result: [String] = []
        for phrase in phrases {
            let normalized = self.phrase(phrase)
            guard !normalized.isEmpty, !result.contains(normalized) else { continue }
            result.append(normalized)
        }
        return result
    }

    static func consumedTokenIndexes(
        in queryTokens: [String],
        matching phrases: [String]
    ) -> Set<Int> {
        let candidates = uniqueNormalizedPhrases(phrases)
            .map { $0.split(separator: " ").map(String.init) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.joined(separator: " ") < rhs.joined(separator: " ")
            }

        var consumed = Set<Int>()
        for candidate in candidates where !candidate.isEmpty && candidate.count <= queryTokens.count {
            let finalStart = queryTokens.count - candidate.count
            for start in 0...finalStart {
                let indexes = start..<(start + candidate.count)
                guard indexes.allSatisfy({ !consumed.contains($0) }) else { continue }
                guard Array(queryTokens[indexes]) == candidate else { continue }
                consumed.formUnion(indexes)
            }
        }
        return consumed
    }

    static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }
}
