import Foundation

/// Immutable activity kinds emitted by the Feed database contract.
///
/// A Feed card must describe the action that happened at `occurredAt`, rather
/// than infer an action from the source row's current mutable status.
enum FeedActivityKind: String, Codable, CaseIterable, Equatable {
    case placeSaved = "place_saved"
    case placeBeen = "place_been"
    case placeWannaGo = "place_want_to_go"
    case listCreated = "list_created"
    case listItemAdded = "list_item_added"

    var isPlaceActivity: Bool {
        switch self {
        case .placeSaved, .placeBeen, .placeWannaGo, .listItemAdded:
            true
        case .listCreated:
            false
        }
    }

    var supportsRating: Bool {
        switch self {
        case .placeBeen, .listItemAdded:
            true
        case .placeSaved, .placeWannaGo, .listCreated:
            false
        }
    }
}

struct FeedMediaPreview: Identifiable, Equatable {
    let id: String
    let urlString: String?
    let accessibilityLabel: String

    init(id: String, urlString: String? = nil, accessibilityLabel: String) {
        self.id = id
        self.urlString = urlString
        self.accessibilityLabel = accessibilityLabel
    }
}

/// An event envelope resolved through the viewer's current visibility rules.
/// `place` and `list` are intentionally optional: source data can disappear
/// between an event being committed and a later page refresh.
struct FeedActivity: Identifiable {
    let id: String
    let kind: FeedActivityKind
    let actor: ProfileShell
    let place: VisiblePlace?
    let list: LocalPlaceList?
    let occurredAt: Date
    let note: String?
    let rating: Double?
    let media: [FeedMediaPreview]

    init(
        id: String,
        kind: FeedActivityKind,
        actor: ProfileShell,
        place: VisiblePlace? = nil,
        list: LocalPlaceList? = nil,
        occurredAt: Date,
        note: String? = nil,
        rating: Double? = nil,
        media: [FeedMediaPreview] = []
    ) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.place = place
        self.list = list
        self.occurredAt = occurredAt
        self.note = note
        self.rating = kind.supportsRating ? rating : nil
        self.media = media
    }
}

struct FeedFeaturedPlace: Identifiable {
    let visiblePlace: VisiblePlace
    let reason: String

    var id: String { visiblePlace.id }
}

struct FollowedFeedPage {
    let activity: [FeedActivity]
    let featuredPlaces: [FeedFeaturedPlace]
    let nextCursor: String?
    let fetchedAt: Date
}

enum FeedLoadState: Equatable {
    case idle
    case loading
    case loaded
    case stale
    case failed
}

enum FeedPresentation {
    private static let futureClockSkewTolerance: TimeInterval = 5 * 60

    static func newestFirst(
        _ activity: [FeedActivity],
        relativeTo now: Date = .now
    ) -> [FeedActivity] {
        activity.sorted { lhs, rhs in
            let lhsDate = safeSortDate(lhs.occurredAt, relativeTo: now)
            let rhsDate = safeSortDate(rhs.occurredAt, relativeTo: now)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }
    }

    static func featuredPlaces(
        from activity: [FeedActivity],
        currentUserPlaceIDs: Set<String>,
        limit: Int = 8,
        relativeTo now: Date = .now
    ) -> [FeedFeaturedPlace] {
        struct FeaturedCandidate {
            let place: VisiblePlace
            let latestActor: ProfileShell
            var supporterIDs: Set<String>
        }

        var orderedPlaceIDs: [String] = []
        var candidatesByPlaceID: [String: FeaturedCandidate] = [:]

        for event in newestFirst(activity, relativeTo: now) {
            guard let place = event.place,
                  !currentUserPlaceIDs.contains(place.place.id)
            else {
                continue
            }

            if var existing = candidatesByPlaceID[place.place.id] {
                existing.supporterIDs.insert(event.actor.id)
                candidatesByPlaceID[place.place.id] = existing
            } else {
                orderedPlaceIDs.append(place.place.id)
                candidatesByPlaceID[place.place.id] = FeaturedCandidate(
                    place: place,
                    latestActor: event.actor,
                    supporterIDs: [event.actor.id]
                )
            }
        }

        return orderedPlaceIDs.prefix(max(0, limit)).compactMap { placeID in
            guard let candidate = candidatesByPlaceID[placeID] else { return nil }
            return FeedFeaturedPlace(
                visiblePlace: candidate.place,
                reason: featuredReason(
                    primaryActorName: candidate.latestActor.displayName,
                    supporterCount: candidate.supporterIDs.count
                )
            )
        }
    }

    static func featuredReason(primaryActorName: String, supporterCount: Int) -> String {
        let otherCount = max(0, supporterCount - 1)
        guard otherCount > 0 else { return "Saved by \(primaryActorName)" }
        let otherLabel = otherCount == 1 ? "other" : "others"
        return "Saved by \(primaryActorName) and \(otherCount) \(otherLabel)"
    }

    static func timestampText(
        for occurredAt: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        DiscoverLatestActivityPresentation.timestampText(
            for: occurredAt,
            relativeTo: now,
            calendar: calendar
        )
    }

    private static func safeSortDate(_ date: Date, relativeTo now: Date) -> Date {
        date.timeIntervalSince(now) > futureClockSkewTolerance ? .distantPast : min(date, now)
    }
}
