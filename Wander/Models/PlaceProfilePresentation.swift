import Foundation

struct PlaceSaveSummary: Identifiable {
    let visiblePlace: VisiblePlace
    let attributes: [LocalPlaceAttribute]
    let viewerFollowsOwner: Bool
    let displayNoteOverride: String?

    init(
        visiblePlace: VisiblePlace,
        attributes: [LocalPlaceAttribute],
        viewerFollowsOwner: Bool = false,
        displayNoteOverride: String? = nil
    ) {
        self.visiblePlace = visiblePlace
        self.attributes = attributes
        self.viewerFollowsOwner = viewerFollowsOwner
        self.displayNoteOverride = displayNoteOverride
    }

    var id: String { visiblePlace.userPlace.id }
}

struct PlaceActualRating: Equatable {
    enum Source: Equatable {
        case own
        case friends
        case community
    }

    let score: Double
    let count: Int
    let source: Source

    var displayScore: String {
        PlaceRating.averageDisplay(score)
    }

    var title: String {
        switch source {
        case .own:
            "Your rating"
        case .friends:
            "Friends rating"
        case .community:
            "rec.me rating"
        }
    }

    var subtitle: String {
        switch source {
        case .own:
            CheckInCopy.count(count)
        case .friends:
            count == 1 ? "1 person you follow" : "\(count) people you follow"
        case .community:
            count == 1 ? "1 community rating" : "\(count) community ratings"
        }
    }
}

struct PlaceCommonTag: Identifiable, Equatable {
    let title: String
    let supportCount: Int
    let hasOwnSupport: Bool

    var id: String { title.lowercased() }
}

struct PlaceFitRating: Equatable {
    let score: Double
    let reasons: [String]

    var displayScore: String {
        let rounded = (score * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

struct PlaceProfilePresentation: Equatable {
    let overallRating: PlaceActualRating?
    let ownRating: PlaceActualRating?
    let fitRating: PlaceFitRating?
    let commonTags: [PlaceCommonTag]

    var whyItFits: [String] {
        fitRating?.reasons ?? []
    }
}

enum PlaceProfilePresenter {
    static func presentation(
        placeID: String,
        category: String,
        saves: [PlaceSaveSummary],
        tasteSaves: [PlaceSaveSummary],
        currentUserID: String
    ) -> PlaceProfilePresentation {
        let commonTags = commonTags(from: saves, currentUserID: currentUserID)
        let overallRating = overallRating(from: saves, currentUserID: currentUserID)
        let ownRating = ownRating(from: saves, currentUserID: currentUserID)
        let fitRating = fitRating(
            placeID: placeID,
            category: category,
            commonTags: commonTags,
            ratingEvidence: ownRating ?? overallRating,
            saves: saves,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID
        )

        return PlaceProfilePresentation(
            overallRating: overallRating,
            ownRating: ownRating,
            fitRating: fitRating,
            commonTags: commonTags
        )
    }

    static func ownRating(
        from saves: [PlaceSaveSummary],
        currentUserID: String
    ) -> PlaceActualRating? {
        let ownAggregates = saves
            .filter {
                $0.visiblePlace.owner.id == currentUserID
                    && $0.visiblePlace.userPlace.status == .been
            }
            .compactMap { summary -> (score: Double, count: Int)? in
                guard let score = summary.visiblePlace.userPlace.ratingScore else { return nil }
                return (score, max(summary.visiblePlace.userPlace.recommendedCount, 1))
            }

        let count = ownAggregates.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }
        let average = ownAggregates.reduce(0) { $0 + ($1.score * Double($1.count)) } / Double(count)
        return PlaceActualRating(score: average, count: count, source: .own)
    }

    static func overallRating(
        from saves: [PlaceSaveSummary],
        currentUserID: String
    ) -> PlaceActualRating? {
        let followedRatings = saves
            .filter {
                $0.visiblePlace.owner.id != currentUserID
                    && $0.viewerFollowsOwner
                    && $0.visiblePlace.userPlace.status == .been
            }
            .compactMap { summary -> (ownerID: String, score: Double)? in
                guard let score = summary.visiblePlace.userPlace.ratingScore else { return nil }
                return (summary.visiblePlace.owner.id, score)
            }

        if !followedRatings.isEmpty {
            let ratingsByOwner = Dictionary(grouping: followedRatings) { $0.ownerID }
            let personAverages = ratingsByOwner.values.map { ratings in
                ratings.reduce(0) { $0 + $1.score } / Double(ratings.count)
            }
            let average = personAverages.reduce(0, +) / Double(personAverages.count)
            return PlaceActualRating(score: average, count: personAverages.count, source: .friends)
        }

        guard let aggregateSource = saves.first(where: {
            $0.visiblePlace.userPlace.recommendedScore != nil
                && $0.visiblePlace.userPlace.recommendedCount > 0
        }),
              let score = aggregateSource.visiblePlace.userPlace.recommendedScore
        else {
            return nil
        }

        return PlaceActualRating(
            score: score,
            count: aggregateSource.visiblePlace.userPlace.recommendedCount,
            source: .community
        )
    }

    static func commonTags(
        from saves: [PlaceSaveSummary],
        currentUserID: String,
        limit: Int = 8
    ) -> [PlaceCommonTag] {
        var supportByTag: [String: TagSupport] = [:]

        for summary in saves {
            let ownerID = summary.visiblePlace.owner.id
            let tags = Set(summary.attributes.flatMap(PlaceProfileTagParser.tags(from:)))

            for tag in tags {
                var support = supportByTag[tag.normalized] ?? TagSupport(title: tag.displayTitle)
                support.ownerIDs.insert(ownerID)
                if ownerID == currentUserID {
                    support.hasOwnSupport = true
                }
                supportByTag[tag.normalized] = support
            }
        }

        return supportByTag.values
            .filter { support in
                let trustedSupportCount = support.ownerIDs.count - (support.hasOwnSupport ? 1 : 0)
                return (support.hasOwnSupport && trustedSupportCount >= 1) || trustedSupportCount >= 2
            }
            .sorted { lhs, rhs in
                if lhs.hasOwnSupport != rhs.hasOwnSupport {
                    return lhs.hasOwnSupport
                }
                if lhs.ownerIDs.count != rhs.ownerIDs.count {
                    return lhs.ownerIDs.count > rhs.ownerIDs.count
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map { support in
                PlaceCommonTag(
                    title: support.title,
                    supportCount: support.ownerIDs.count,
                    hasOwnSupport: support.hasOwnSupport
                )
            }
    }

    static func fitRating(
        placeID: String,
        category: String,
        commonTags: [PlaceCommonTag],
        ratingEvidence: PlaceActualRating?,
        saves: [PlaceSaveSummary],
        tasteSaves: [PlaceSaveSummary],
        currentUserID: String
    ) -> PlaceFitRating? {
        var weightedTotal = 0.0
        var totalWeight = 0.0
        var evidence = 0
        var reasons: [String] = []

        if let ratingEvidence {
            let ratingFit = min(10, max(0, ratingEvidence.score * 2))
            let weight = ratingEvidence.source == .own ? 0.42 : 0.30
            weightedTotal += ratingFit * weight
            totalWeight += weight
            evidence += ratingEvidence.source == .own ? 2 : 1
            reasons.append(ratingEvidence.source == .own ? "You rated this \(ratingEvidence.displayScore)/5." : "\(ratingEvidence.subtitle) average \(ratingEvidence.displayScore)/5.")
        }

        let tasteProfile = TasteProfile(
            selectedPlaceID: placeID,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID
        )

        if let categoryAffinity = tasteProfile.categoryAffinity(for: category) {
            weightedTotal += categoryAffinity.score * 0.26
            totalWeight += 0.26
            evidence += 1
            reasons.append(categoryAffinity.reason)
        }

        let selectedTags = commonTags.map(\.title)
        if let tagAffinity = tasteProfile.tagAffinity(for: selectedTags) {
            weightedTotal += tagAffinity.score * 0.22
            totalWeight += 0.22
            evidence += 1
            reasons.append(tagAffinity.reason)
        }

        let trustedSaveCount = saves.filter { $0.visiblePlace.owner.id != currentUserID }.count
        if trustedSaveCount >= 2 {
            let socialFit = min(10, 6.5 + Double(trustedSaveCount) * 0.5)
            weightedTotal += socialFit * 0.10
            totalWeight += 0.10
            evidence += 1
            reasons.append("\(trustedSaveCount) trusted people saved it.")
        }

        guard totalWeight > 0, evidence >= 2 else { return nil }
        let score = max(0, min(10, weightedTotal / totalWeight))

        return PlaceFitRating(
            score: (score * 10).rounded() / 10,
            reasons: Array(reasons.prefix(3))
        )
    }
}

private struct TagSupport {
    var title: String
    var ownerIDs: Set<String> = []
    var hasOwnSupport = false
}

struct ParsedTag: Hashable {
    let normalized: String
    let displayTitle: String
}

enum PlaceProfileTagParser {
    static func tags(from attribute: LocalPlaceAttribute) -> [ParsedTag] {
        guard shouldSurface(attribute.questionKey) else { return [] }
        return PlaceAttributeValuePresentation.strings(from: attribute.valueJSON).compactMap(parsedTag)
    }

    private static func shouldSurface(_ questionKey: String) -> Bool {
        switch questionKey {
        case "interest_signal", "rating_signal", PlaceMemoryAttributeKeys.restaurantCuisine:
            return false
        default:
            return true
        }
    }

    private static func parsedTag(_ value: String) -> ParsedTag? {
        let display = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !display.isEmpty else { return nil }
        return ParsedTag(normalized: display.lowercased(), displayTitle: display)
    }

}

private struct TasteProfile {
    private let categoryCounts: [String: Int]
    private let tagCounts: [String: Int]
    private let tagTitles: [String: String]
    private let likedSaveCount: Int

    init(
        selectedPlaceID: String,
        tasteSaves: [PlaceSaveSummary],
        currentUserID: String
    ) {
        let likedSaves = tasteSaves.filter { summary in
            guard summary.visiblePlace.owner.id == currentUserID,
                  summary.visiblePlace.place.id != selectedPlaceID
            else {
                return false
            }

            if let ratingScore = summary.visiblePlace.userPlace.ratingScore {
                return ratingScore >= 4
            }

            return summary.visiblePlace.userPlace.status == .wannaGo
        }

        var categoryCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var tagTitles: [String: String] = [:]

        for summary in likedSaves {
            let category = summary.visiblePlace.effectiveCategory.lowercased()
            categoryCounts[category, default: 0] += 1

            for tag in Set(summary.attributes.flatMap(PlaceProfileTagParser.tags(from:))) {
                tagCounts[tag.normalized, default: 0] += 1
                tagTitles[tag.normalized] = tag.displayTitle
            }
        }

        self.categoryCounts = categoryCounts
        self.tagCounts = tagCounts
        self.tagTitles = tagTitles
        self.likedSaveCount = likedSaves.count
    }

    func categoryAffinity(for category: String) -> (score: Double, reason: String)? {
        guard likedSaveCount > 0 else { return nil }
        let normalizedCategory = category.lowercased()
        let count = categoryCounts[normalizedCategory, default: 0]
        guard count > 0 else { return nil }

        let affinity = Double(count) / Double(likedSaveCount)
        let score = 6.5 + min(1, affinity) * 3.5
        let displayCategory = WanderPlaceCategory.broadCategory(for: normalizedCategory).lowercased()
        let label = normalizedCategory == "place" ? "places like this" : "\(displayCategory) places"
        return (score, "Matches \(label) you save.")
    }

    func tagAffinity(for selectedTags: [String]) -> (score: Double, reason: String)? {
        let matches = selectedTags.compactMap { title -> String? in
            let normalized = title.lowercased()
            guard tagCounts[normalized, default: 0] > 0 else { return nil }
            return tagTitles[normalized] ?? title
        }

        guard !matches.isEmpty else { return nil }
        let score = 7.0 + min(1, Double(matches.count) / 3.0) * 3.0
        let display = matches.prefix(2).joined(separator: " + ")
        return (score, "Matches your \(display) saves.")
    }
}
