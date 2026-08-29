import CoreLocation
import Darwin
import Foundation
import MapKit

private struct BatchRequest: Decodable {
    let requests: [HintRequest]
    let geographyProbes: [GeographyProbe]?
    let rankingProbes: [RankingProbe]?
    let queryLimitProbes: [QueryLimitProbe]?
}

private struct HintRequest: Decodable {
    let id: String
    let name: String
    let area: String?
    let allowNearSpellingMatch: Bool?
}

private struct BatchResponse: Encodable {
    let resolver: String
    let results: [HintResult]
    let geographyProbes: [GeographyProbeResult]?
    let rankingProbes: [RankingProbeResult]?
    let queryLimitProbes: [QueryLimitProbeResult]?
}

fileprivate struct GeographyProbe: Decodable {
    let id: String
    let area: String
}

fileprivate struct GeographyProbeResult: Encodable {
    let id: String
    let stateCode: String?
    let hasSearchRegion: Bool
    let localityText: String?
}

fileprivate struct RankingProbe: Decodable {
    let id: String
    let items: [RankingProbeItem]
}

fileprivate struct RankingProbeItem: Decodable {
    let id: String
    let hasPointOfInterestCategory: Bool
    let isPark: Bool
    let hasPrimaryCategory: Bool
}

fileprivate struct RankingProbeResult: Encodable {
    let id: String
    let orderedItemIDs: [String]
}

fileprivate struct QueryLimitProbe: Decodable {
    let id: String
    let perQueryLimit: Int
    let queryItemIDs: [[String]]
}

fileprivate struct QueryLimitProbeResult: Encodable {
    let id: String
    let accumulatedItemIDs: [String]
}

private struct HintResult: Encodable {
    let id: String
    let queryVariants: [String]
    let candidates: [Candidate]
    let selectedCandidateID: String?
    let bestScore: Double
    let error: ResolverError?
}

private struct ResolverError: Encodable {
    let code: String
    let message: String
}

private struct Candidate: Encodable {
    let id: String
    let name: String
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let category: String?
    let sourceProvider: String
    let score: Double
}

private struct ScoredCandidate {
    let candidate: Candidate
    let equivalentName: Bool
    let nearSpellingName: Bool
    let originalIndex: Int
}

private struct SearchRegion {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let latitudeDelta: CLLocationDegrees
    let longitudeDelta: CLLocationDegrees
}

/// Evaluation-only copy of the production `ManualPlaceSearchPlan` contract.
/// Keep changes here paired with `MapKitPlaceResolver.swift` and its tests.
private struct SearchPlan {
    let queries: [String]
    let coordinateHint: CLLocationCoordinate2D?
    let regionHint: SearchRegion?

    init(name: String, areaHint: String?) {
        let coordinate = Resolver.coordinate(from: areaHint)
        let region = coordinate == nil ? Resolver.searchRegion(for: areaHint) : nil
        let queryArea: String?
        if coordinate != nil {
            queryArea = nil
        } else if region != nil {
            queryArea = Resolver.localityText(in: areaHint)
        } else {
            queryArea = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        queries = Resolver.providerNameVariants(for: name).map { searchName in
            [searchName, queryArea]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " ")
        }
        coordinateHint = coordinate
        regionHint = region
    }
}

private enum Resolver {
    private static let minimumSearchInterval: TimeInterval = 0.6
    @MainActor private static var lastSearchStartedAt = Date.distantPast

    @MainActor
    static func resolve(_ input: HintRequest) async -> HintResult {
        let plan = SearchPlan(name: input.name, areaHint: input.area)
        var mapItems: [MKMapItem] = []
        var seen = Set<String>()
        var lastError: Error?
        let perQueryLimit = max(1, 8 / plan.queries.count)

        for query in plan.queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .address]
            if let coordinate = plan.coordinateHint {
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_500,
                    longitudinalMeters: 1_500
                )
            } else if let region = plan.regionHint {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: region.latitude,
                        longitude: region.longitude
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: region.latitudeDelta,
                        longitudeDelta: region.longitudeDelta
                    )
                )
            }
            do {
                let response = try await pacedSearch(request)
                var queryItems: [MKMapItem] = []
                var querySeen = Set<String>()
                for item in rankedMapItems(response.mapItems) {
                    guard CLLocationCoordinate2DIsValid(item.placemark.coordinate),
                          item.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    else { continue }
                    let key = mapItemKey(item)
                    guard querySeen.insert(key).inserted else { continue }
                    queryItems.append(item)
                    if queryItems.count >= perQueryLimit { break }
                }
                for item in queryItems where seen.insert(mapItemKey(item)).inserted {
                    mapItems.append(item)
                }
            } catch {
                lastError = error
            }
        }

        if mapItems.isEmpty, let lastError {
            return HintResult(
                id: input.id,
                queryVariants: plan.queries,
                candidates: [],
                selectedCandidateID: nil,
                bestScore: 0,
                error: ResolverError(
                    code: "mapkit_search_failed",
                    message: lastError.localizedDescription
                )
            )
        }

        let countryCompatible = candidatesCompatibleWithExactCountry(
            mapItems,
            areaHint: input.area
        )
        let eligible = countryCompatible.filter {
            !candidateConflictsWithArea($0, areaHint: input.area)
        }
        let scored = eligible.enumerated().compactMap { index, item -> ScoredCandidate? in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }
            let placemark = item.placemark
            let coordinate = placemark.coordinate
            let score = candidateScore(
                name: name,
                address: address(for: placemark),
                locality: placemark.locality,
                region: placemark.administrativeArea,
                country: placemark.isoCountryCode,
                nameHint: input.name,
                areaHint: input.area
            )
            let id = [
                canonicalKey(name),
                String(format: "%.6f", coordinate.latitude),
                String(format: "%.6f", coordinate.longitude)
            ].joined(separator: ":")
            return ScoredCandidate(
                candidate: Candidate(
                    id: id,
                    name: name,
                    address: address(for: placemark),
                    locality: placemark.locality,
                    region: placemark.administrativeArea,
                    country: placemark.isoCountryCode,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    category: item.pointOfInterestCategory?.rawValue,
                    sourceProvider: "mapkit",
                    score: score
                ),
                equivalentName: namesAreEquivalent(name, input.name),
                nearSpellingName: (input.allowNearSpellingMatch ?? false)
                    && isNearSpellingMatch(name, input.name),
                originalIndex: index
            )
        }
        .sorted { lhs, rhs in
            if lhs.candidate.score == rhs.candidate.score {
                return lhs.originalIndex < rhs.originalIndex
            }
            return lhs.candidate.score > rhs.candidate.score
        }

        guard let best = scored.first else {
            return HintResult(
                id: input.id,
                queryVariants: plan.queries,
                candidates: [],
                selectedCandidateID: nil,
                bestScore: 0,
                error: nil
            )
        }

        let runnerUpScore = scored.dropFirst().first?.candidate.score ?? 0
        let exactEquivalentCount = scored.filter {
            $0.equivalentName || $0.nearSpellingName
        }.count
        let hasClearLead = best.candidate.score - runnerUpScore >= 0.08
        let uniqueExact = (best.equivalentName || best.nearSpellingName)
            && exactEquivalentCount == 1
        let selectedID = uniqueExact || (best.candidate.score >= 0.82 && hasClearLead)
            ? best.candidate.id
            : nil

        return HintResult(
            id: input.id,
            queryVariants: plan.queries,
            candidates: Array(scored.prefix(8).map(\.candidate)),
            selectedCandidateID: selectedID,
            bestScore: best.candidate.score,
            error: nil
        )
    }

    /// The evaluator can replay far more hints back-to-back than the app's
    /// interactive flow. Pace those requests and retry only MapKit's transient
    /// server/throttling failures so batch pressure is not misreported as
    /// candidate-quality loss. Ranking and selection remain production mirrors.
    @MainActor
    private static func pacedSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        let backoffSeconds: [TimeInterval] = [1.5, 4.0]
        var attempt = 0
        while true {
            let elapsed = Date().timeIntervalSince(lastSearchStartedAt)
            let remaining = minimumSearchInterval - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            lastSearchStartedAt = Date()
            do {
                return try await MKLocalSearch(request: request).start()
            } catch {
                guard isRetryableMapKitError(error), attempt < backoffSeconds.count else {
                    throw error
                }
                let delay = backoffSeconds[attempt]
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func isRetryableMapKitError(_ error: Error) -> Bool {
        let providerError = error as NSError
        guard providerError.domain == MKErrorDomain,
              let code = MKError.Code(rawValue: UInt(providerError.code))
        else { return false }
        return code == .serverFailure || code == .loadingThrottled
    }

    fileprivate static func providerNameVariants(for name: String) -> [String] {
        let folded = normalizedWords(name).joined(separator: " ")
        var variants = [name]
        if folded.contains("gorge"), !folded.contains("reservoir") {
            variants.append("\(name) Reservoir")
        }
        if folded.contains("overlook"), !folded.contains("interpretive site") {
            variants.append("\(name) Interpretive Site")
        }
        return variants
    }

    /// Mirrors the ranking pass used by production `MapKitPlaceResolver`
    /// before its per-query limit is applied. MapKit POIs outrank address-only
    /// results, known place categories receive the same secondary boost, and
    /// parks retain production's additional preference.
    private static func rankedMapItems(_ items: [MKMapItem]) -> [MKMapItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = productionRankingScore(for: lhs.element)
                let right = productionRankingScore(for: rhs.element)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }

    private static func mapItemKey(_ item: MKMapItem) -> String {
        let coordinate = item.placemark.coordinate
        return [
            item.name?.lowercased() ?? "",
            String(format: "%.6f", coordinate.latitude),
            String(format: "%.6f", coordinate.longitude)
        ].joined(separator: "|")
    }

    private static func productionRankingScore(for item: MKMapItem) -> Double {
        let pointCategory = item.pointOfInterestCategory
        return productionRankingScore(
            hasPointOfInterestCategory: pointCategory != nil,
            isPark: pointCategory == .park || pointCategory == .nationalPark,
            hasPrimaryCategory: pointCategory != nil || hasNameBasedPrimaryCategory(item.name)
        )
    }

    private static func productionRankingScore(
        hasPointOfInterestCategory: Bool,
        isPark: Bool,
        hasPrimaryCategory: Bool
    ) -> Double {
        var score = 0.0
        if hasPointOfInterestCategory {
            score += 500
            if isPark { score += 70 }
        }
        if hasPrimaryCategory { score += 120 }
        return score
    }

    private static func hasNameBasedPrimaryCategory(_ name: String?) -> Bool {
        guard let name else { return false }
        let value = " " + normalizedWords(name).joined(separator: " ") + " "
        let phrases = [
            "veterinary", "veterinarian", " vet ", "animal hospital", "pet hospital",
            "pet clinic", "dog dental", "cat clinic", "optometrist", "ophthalmologist",
            "eye doctor", "eye care", "vision center", "optical", "temple", "shrine",
            "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue",
            "hospital", "medical center", "health center", "urgent care", "pharmacy",
            "drugstore", "dermatology", "pediatrics", "physical therapy", "chiropractor",
            "wellness studio", "spa", "pilates", "plankhaus", "lagree", "reformer",
            " gym ", "fitness", "training", "strength", "workout", "nail salon",
            "nails", "manicure", "pedicure", "hair salon", "barbershop", "barber shop",
            "barber", "tattoo"
        ]
        return phrases.contains { phrase in
            let normalized = " " + normalizedWords(phrase).joined(separator: " ") + " "
            return value.contains(normalized)
        }
    }

    fileprivate static func coordinate(from value: String?) -> CLLocationCoordinate2D? {
        guard let value else { return nil }
        let pattern = #"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$"#
        guard let match = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let parts = value[match].split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let latitude = CLLocationDegrees(parts[0]),
              let longitude = CLLocationDegrees(parts[1])
        else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    fileprivate static func searchRegion(for area: String?) -> SearchRegion? {
        guard let code = areaStateCode(in: area), let center = stateCenters[code] else {
            return nil
        }
        let span: (Double, Double)
        switch code {
        case "AK": span = (24, 50)
        case "HI": span = (8, 14)
        default: span = (12, 18)
        }
        return SearchRegion(
            latitude: center.latitude,
            longitude: center.longitude,
            latitudeDelta: span.0,
            longitudeDelta: span.1
        )
    }

    fileprivate static func localityText(in area: String?) -> String? {
        guard let area = area?.trimmingCharacters(in: .whitespacesAndNewlines),
              !area.isEmpty,
              let code = areaStateCode(in: area)
        else {
            let trimmed = area?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        if let explicitSuffix = explicitStateSuffix(in: area), explicitSuffix.code == code {
            var locality = area
            locality.removeSubrange(explicitSuffix.range)
            locality = locality.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: ",;")
                )
            )
            return locality.isEmpty ? nil : locality
        }

        var rawWords = area.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var foldedWords = rawWords.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
        }

        let countryWords: Set<String> = ["america", "states", "united", "us", "usa"]
        for index in foldedWords.indices.reversed() where countryWords.contains(foldedWords[index]) {
            rawWords.remove(at: index)
            foldedWords.remove(at: index)
        }

        if let stateName = canonicalStateName(for: code) {
            let stateWords = normalizedWords(stateName)
            if foldedWords.count >= stateWords.count,
               foldedWords.suffix(stateWords.count).elementsEqual(stateWords) {
                rawWords.removeLast(stateWords.count)
                foldedWords.removeLast(stateWords.count)
            }
        }

        let locality = rawWords.joined(separator: " ")
        return locality.isEmpty ? nil : locality
    }

    private static func candidatesCompatibleWithExactCountry(
        _ items: [MKMapItem],
        areaHint: String?
    ) -> [MKMapItem] {
        guard let area = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !area.isEmpty,
              !area.contains(","),
              stateCode(in: area) == nil,
              normalizedCountryKey(area) != "georgia",
              let expectedCode = countryCode(for: area)
        else { return items }
        return items.filter { item in
            guard let candidateCode = item.placemark.isoCountryCode?.uppercased() else {
                return false
            }
            return candidateCode == expectedCode
        }
    }

    private static func countryCode(for value: String) -> String? {
        let key = normalizedCountryKey(value)
        if let alias = countryAliases[key] { return alias }
        let locale = Locale(identifier: "en_US_POSIX")
        return Locale.Region.isoRegions.first { region in
            guard let name = locale.localizedString(forRegionCode: region.identifier) else {
                return false
            }
            return normalizedCountryKey(name) == key
                || normalizedCountryKey(region.identifier) == key
        }?.identifier
    }

    private static func normalizedCountryKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }

    private static func candidateScore(
        name: String,
        address: String?,
        locality: String?,
        region: String?,
        country: String?,
        nameHint: String,
        areaHint: String?
    ) -> Double {
        let hintKey = canonicalKey(nameHint)
        let candidateKey = canonicalKey(name)
        let hintTokens = Set(normalizedWords(nameHint))
        let candidateTokens = Set(normalizedWords(name))
        let hintCore = coreTokens(nameHint)
        let candidateCore = coreTokens(name)

        var score: Double
        if hintKey == candidateKey {
            score = 0.82
        } else if !hintCore.isEmpty, hintCore == candidateCore {
            score = 0.8
        } else if min(hintKey.count, candidateKey.count) >= 5,
                  hintKey.contains(candidateKey) || candidateKey.contains(hintKey) {
            score = 0.72
        } else {
            let intersection = hintTokens.intersection(candidateTokens).count
            let union = hintTokens.union(candidateTokens).count
            score = union == 0 ? 0 : Double(intersection) / Double(union) * 0.68
        }

        if let areaHint = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !areaHint.isEmpty {
            let requested = areaTokens(areaHint)
            let candidateArea = [address, locality, region, country]
                .compactMap { $0 }
                .joined(separator: " ")
            let actual = areaTokens(candidateArea)
            let overlap = requested.intersection(actual).count
            if overlap > 0 {
                let denominator = max(1, min(requested.count, actual.count))
                score += min(0.1, Double(overlap) / Double(denominator) * 0.1)
            }
        }

        if hasUnrequestedStreetDesignator(name, comparedWith: nameHint) {
            score = min(score, 0.45)
        }
        return max(0, min(1, score))
    }

    private static func namesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if canonicalKey(lhs) == canonicalKey(rhs) {
            return true
        }
        let lhsCore = coreTokens(lhs)
        let rhsCore = coreTokens(rhs)
        return !lhsCore.isEmpty && lhsCore == rhsCore
    }

    private static func normalizedWords(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0 == "merc" ? "mercantile" : $0 }
    }

    private static func canonicalKey(_ value: String) -> String {
        normalizedWords(value).joined()
    }

    private static func coreTokens(_ value: String) -> Set<String> {
        Set(normalizedWords(value)).subtracting([
            "the", "restaurant", "restaurants", "eatery", "company", "co",
            "inc", "llc", "reservoir"
        ])
    }

    private static func areaTokens(_ value: String) -> Set<String> {
        var result = Set(normalizedWords(value))
        if let stateCode = areaStateCode(in: value) {
            result.insert(stateCode.lowercased())
            if let name = canonicalStateName(for: stateCode) {
                result.formUnion(normalizedWords(name))
            }
        }
        return result
    }

    private static func candidateConflictsWithArea(
        _ item: MKMapItem,
        areaHint: String?
    ) -> Bool {
        guard let requested = areaStateCode(in: areaHint),
              let candidate = stateCode(
                in: item.placemark.administrativeArea
              )
        else { return false }
        return requested != candidate
    }

    private static func stateCode(in value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        if let explicitSuffix = explicitStateSuffix(in: value) {
            return explicitSuffix.code
        }

        var words = normalizedWords(value)
        while let last = words.last, Int(last) != nil {
            words.removeLast()
        }
        for countrySuffix in [["united", "states", "of", "america"], ["united", "states"], ["usa"], ["us"]]
            where words.count >= countrySuffix.count
                && words.suffix(countrySuffix.count).elementsEqual(countrySuffix) {
            words.removeLast(countrySuffix.count)
            break
        }

        let namedCodes = Set(stateCodes.compactMap { name, code -> String? in
            let stateWords = normalizedWords(name)
            return words.count >= stateWords.count
                && words.suffix(stateWords.count).elementsEqual(stateWords)
                ? code
                : nil
        })
        return namedCodes.count == 1 ? namedCodes.first : nil
    }

    private static func areaStateCode(in value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let code = stateCode(in: value)
        else { return nil }

        if code == "GA" {
            if explicitStateSuffix(in: value)?.code == "GA" {
                return code
            }
            return isUnambiguousUSGeorgia(in: value) ? code : nil
        }

        guard code == "LA", !contains(normalizedWords(value), sequence: ["louisiana"]) else {
            return code
        }
        let louisianaSuffix = #"(?i),\s*l\.?\s*a\.?(?:\s+\d{5}(?:-\d{4})?)?(?:\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))?\s*$"#
        return value.range(of: louisianaSuffix, options: .regularExpression) == nil ? nil : code
    }

    private static func canonicalStateName(for code: String) -> String? {
        stateCodes.first(where: { $0.value == code.uppercased() })?.key
    }

    private static func isUnambiguousUSGeorgia(in value: String) -> Bool {
        let pattern = #"(?i)(?:\bstate\s+of\s+georgia\b|\bgeorgia\b\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func contains(_ words: [String], sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= words.count else { return false }
        if sequence.count == 1 {
            return words.contains(sequence[0])
        }
        return (0...(words.count - sequence.count)).contains { index in
            Array(words[index..<(index + sequence.count)]) == sequence
        }
    }

    private static func explicitStateSuffix(
        in value: String
    ) -> (code: String, range: Range<String.Index>)? {
        let pattern = #"(?i)(?:^|[,\s])([a-z]\.?\s*[a-z]\.?)"#
            + #"(?:\s+\d{5}(?:-\d{4})?)?"#
            + #"(?:\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let searchRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: searchRange),
              let codeRange = Range(match.range(at: 1), in: value),
              let fullRange = Range(match.range, in: value)
        else { return nil }

        let code = value[codeRange]
            .filter { $0.isLetter }
            .uppercased()
        guard stateCodes.values.contains(code) else { return nil }
        return (code, fullRange)
    }

    fileprivate static func inspectGeography(_ probe: GeographyProbe) -> GeographyProbeResult {
        GeographyProbeResult(
            id: probe.id,
            stateCode: areaStateCode(in: probe.area),
            hasSearchRegion: searchRegion(for: probe.area) != nil,
            localityText: localityText(in: probe.area)
        )
    }

    fileprivate static func inspectRanking(_ probe: RankingProbe) -> RankingProbeResult {
        let ordered = probe.items.enumerated().sorted { lhs, rhs in
            let left = productionRankingScore(
                hasPointOfInterestCategory: lhs.element.hasPointOfInterestCategory,
                isPark: lhs.element.isPark,
                hasPrimaryCategory: lhs.element.hasPrimaryCategory
            )
            let right = productionRankingScore(
                hasPointOfInterestCategory: rhs.element.hasPointOfInterestCategory,
                isPark: rhs.element.isPark,
                hasPrimaryCategory: rhs.element.hasPrimaryCategory
            )
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        return RankingProbeResult(id: probe.id, orderedItemIDs: ordered.map(\.element.id))
    }

    fileprivate static func inspectQueryLimit(_ probe: QueryLimitProbe) -> QueryLimitProbeResult {
        let perQueryLimit = max(1, probe.perQueryLimit)
        var accumulated: [String] = []
        var accumulatedIDs = Set<String>()
        for queryItemIDs in probe.queryItemIDs {
            var limited: [String] = []
            var queryIDs = Set<String>()
            for itemID in queryItemIDs where queryIDs.insert(itemID).inserted {
                limited.append(itemID)
                if limited.count >= perQueryLimit { break }
            }
            for itemID in limited where accumulatedIDs.insert(itemID).inserted {
                accumulated.append(itemID)
            }
        }
        return QueryLimitProbeResult(id: probe.id, accumulatedItemIDs: accumulated)
    }

    private static func hasUnrequestedStreetDesignator(
        _ candidate: String,
        comparedWith hint: String
    ) -> Bool {
        let streetDesignators: Set<String> = [
            "avenue", "ave", "boulevard", "blvd", "court", "ct", "highway",
            "hwy", "lane", "ln", "parkway", "pkwy", "road", "rd", "street",
            "st", "way"
        ]
        let candidateDesignators = Set(normalizedWords(candidate)).intersection(streetDesignators)
        guard !candidateDesignators.isEmpty else { return false }
        return Set(normalizedWords(hint)).intersection(candidateDesignators).isEmpty
    }

    private static func isNearSpellingMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(canonicalKey(lhs))
        let right = Array(canonicalKey(rhs))
        guard min(left.count, right.count) >= 8, abs(left.count - right.count) <= 1 else {
            return false
        }
        var leftIndex = 0
        var rightIndex = 0
        var edits = 0
        while leftIndex < left.count, rightIndex < right.count {
            if left[leftIndex] == right[rightIndex] {
                leftIndex += 1
                rightIndex += 1
                continue
            }
            edits += 1
            guard edits <= 1 else { return false }
            if left.count > right.count {
                leftIndex += 1
            } else if right.count > left.count {
                rightIndex += 1
            } else {
                leftIndex += 1
                rightIndex += 1
            }
        }
        if leftIndex < left.count || rightIndex < right.count {
            edits += 1
        }
        return edits == 1
    }

    private static func address(for placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let value = [
            street.isEmpty ? nil : street,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.isoCountryCode
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        return value.isEmpty ? nil : value
    }

    private static let stateCodes: [String: String] = [
        "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
        "California": "CA", "Colorado": "CO", "Connecticut": "CT",
        "Delaware": "DE", "District of Columbia": "DC", "Florida": "FL",
        "Georgia": "GA", "Hawaii": "HI",
        "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
        "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME",
        "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI",
        "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT",
        "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH",
        "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
        "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
        "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA",
        "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
        "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT",
        "Virginia": "VA", "Washington": "WA", "West Virginia": "WV",
        "Wisconsin": "WI", "Wyoming": "WY"
    ]

    private static let stateCenters: [String: (latitude: Double, longitude: Double)] = [
        "AL": (32.8067, -86.7911), "AK": (61.3707, -152.4044),
        "AZ": (33.7298, -111.4312), "AR": (34.9697, -92.3731),
        "CA": (36.1162, -119.6816), "CO": (39.0598, -105.3111),
        "CT": (41.5978, -72.7554), "DE": (39.3185, -75.5071),
        "DC": (38.9072, -77.0369), "FL": (27.7663, -81.6868),
        "GA": (33.0406, -83.6431),
        "HI": (21.0943, -157.4983), "ID": (44.2405, -114.4788),
        "IL": (40.3495, -88.9861), "IN": (39.8494, -86.2583),
        "IA": (42.0115, -93.2105), "KS": (38.5266, -96.7265),
        "KY": (37.6681, -84.6701), "LA": (31.1695, -91.8678),
        "ME": (44.6939, -69.3819), "MD": (39.0639, -76.8021),
        "MA": (42.2302, -71.5301), "MI": (43.3266, -84.5361),
        "MN": (45.6945, -93.9002), "MS": (32.7416, -89.6787),
        "MO": (38.4561, -92.2884), "MT": (46.9219, -110.4544),
        "NE": (41.1254, -98.2681), "NV": (38.3135, -117.0554),
        "NH": (43.4525, -71.5639), "NJ": (40.2989, -74.5210),
        "NM": (34.8405, -106.2485), "NY": (42.1657, -74.9481),
        "NC": (35.6301, -79.8064), "ND": (47.5289, -99.7840),
        "OH": (40.3888, -82.7649), "OK": (35.5653, -96.9289),
        "OR": (44.5720, -122.0709), "PA": (40.5908, -77.2098),
        "RI": (41.6809, -71.5118), "SC": (33.8569, -80.9450),
        "SD": (44.2998, -99.4388), "TN": (35.7478, -86.6923),
        "TX": (31.0545, -97.5635), "UT": (40.1500, -111.8624),
        "VT": (44.0459, -72.7107), "VA": (37.7693, -78.1700),
        "WA": (47.4009, -121.4905), "WV": (38.4912, -80.9545),
        "WI": (44.2685, -89.6165), "WY": (42.7560, -107.3025)
    ]

    private static let countryAliases: [String: String] = [
        "usa": "US", "unitedstatesofamerica": "US", "uae": "AE",
        "thephilippines": "PH", "southkorea": "KR", "czechrepublic": "CZ",
        "turkey": "TR", "vietnam": "VN", "capeverde": "CV",
        "ivorycoast": "CI"
    ]
}

@main
private struct Main {
    @MainActor
    static func main() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(BatchRequest.self, from: data)
            var results: [HintResult] = []
            for hint in request.requests {
                results.append(await Resolver.resolve(hint))
            }
            let response = BatchResponse(
                resolver: "mapkit-production-query-ranking-and-threshold-mirror-v4",
                results: results,
                geographyProbes: request.geographyProbes?.map(Resolver.inspectGeography),
                rankingProbes: request.rankingProbes?.map(Resolver.inspectRanking),
                queryLimitProbes: request.queryLimitProbes?.map(Resolver.inspectQueryLimit)
            )
            let encoded = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(encoded)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            let response = [
                "resolver": "mapkit-production-query-ranking-and-threshold-mirror-v4",
                "fatalError": error.localizedDescription
            ]
            let encoded = try? JSONSerialization.data(withJSONObject: response)
            if let encoded {
                FileHandle.standardOutput.write(encoded)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
            Darwin.exit(1)
        }
    }
}
