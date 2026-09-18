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

    var supportsRating: Bool {
        switch self {
        case .placeBeen, .listItemAdded:
            true
        case .placeSaved, .placeWannaGo, .listCreated:
            false
        }
    }

    var ticketKind: FeedTicketKind {
        switch self {
        case .placeBeen:
            .checkIn
        case .placeWannaGo:
            .wanna
        case .listCreated, .listItemAdded:
            .list
        case .placeSaved:
            .saved
        }
    }
}

enum FeedTicketKind: Equatable {
    case checkIn
    case wanna
    case list
    case saved
}

struct FeedMediaPreview: Identifiable, Equatable, Sendable {
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

    /// `place_saved` is the legacy event name for saving from another person's
    /// map. Provenance is not a distinct place status, so render the ticket as
    /// the Been or Wanna action the person actually chose.
    var resolvedTicketKind: FeedTicketKind {
        guard kind == .placeSaved else { return kind.ticketKind }
        guard let place else { return .saved }
        return place.userPlace.status == .been ? .checkIn : .wanna
    }
}

struct FeedFeaturedPlace: Identifiable {
    let visiblePlace: VisiblePlace
    let actor: ProfileShell
    let reason: String

    var id: String { visiblePlace.id }
}

/// A display-only collection of already-authorized events. Original event IDs
/// remain the targets for likes, comments, sharing, and notification links.
struct FeedActivityGroup: Identifiable {
    let firstActivity: FeedActivity
    private(set) var activities: [FeedActivity]

    init(_ activity: FeedActivity) {
        firstActivity = activity
        activities = [activity]
    }

    var id: String { firstActivity.id }
    var occurredAt: Date { firstActivity.occurredAt }
    var isCombined: Bool { activities.count > 1 }

    var primaryActivity: FeedActivity {
        activities.dropFirst().reduce(firstActivity) { primary, candidate in
            candidate.kind.groupingPriority > primary.kind.groupingPriority ? candidate : primary
        }
    }

    var lists: [LocalPlaceList] {
        var seen = Set<String>()
        return activities.compactMap { activity in
            guard activity.kind == .listItemAdded, let list = activity.list,
                  seen.insert(list.id).inserted else { return nil }
            return list
        }
    }

    fileprivate mutating func append(_ activity: FeedActivity) {
        activities.append(activity)
    }
}

private extension FeedActivityKind {
    var groupingPriority: Int {
        switch self {
        case .placeBeen: 3
        case .placeWannaGo: 2
        case .listItemAdded: 1
        case .placeSaved, .listCreated: 0
        }
    }
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

enum FeedRefreshPolicy {
    static let maximumAge: TimeInterval = 60

    static func isFresh(completedAt: Date?, now: Date = .now) -> Bool {
        guard let completedAt else { return false }
        let age = now.timeIntervalSince(completedAt)
        return age >= 0 && age < maximumAge
    }
}

enum FeedPresentation {
    // Keep the Featured implementation available for a future layout change.
    // This choice controls both the top rail and the work requested from the server.
    static let showsFeaturedPlaces = false

    private static let futureClockSkewTolerance: TimeInterval = 5 * 60
    static let activityGroupingWindow: TimeInterval = 30 * 60

    /// Visible events -> chronological groups -> newest moment first.
    /// The window never slides, and a second check-in starts a new moment.
    /// Grouping uses place identity, never a name or a mutable save status.
    static func groupedActivity(
        _ activity: [FeedActivity],
        relativeTo now: Date = .now
    ) -> [FeedActivityGroup] {
        struct Key: Hashable {
            let actorID: String
            let placeID: String
        }
        var seen = Set<String>()
        let chronological = activity.filter { seen.insert($0.id).inserted }.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id < $1.id
        }
        var groups: [FeedActivityGroup] = []
        var latestGroup: [Key: Int] = [:]

        for event in chronological {
            // Legacy social saves infer their ticket from mutable status; they
            // cannot safely stand in for a specific immutable Wanna or visit.
            guard event.kind != .placeSaved, event.kind != .listCreated,
                  let place = event.place,
                  !place.place.id.isEmpty,
                  event.occurredAt > .distantPast,
                  event.occurredAt.timeIntervalSince(now) <= futureClockSkewTolerance
            else {
                groups.append(FeedActivityGroup(event))
                continue
            }
            let key = Key(actorID: event.actor.id, placeID: place.place.id)
            if let index = latestGroup[key],
               event.occurredAt.timeIntervalSince(groups[index].occurredAt) <= activityGroupingWindow,
               !(event.kind == .placeBeen && groups[index].activities.contains { $0.kind == .placeBeen }) {
                groups[index].append(event)
            } else {
                latestGroup[key] = groups.count
                groups.append(FeedActivityGroup(event))
            }
        }

        return groups.sorted {
            let lhs = safeSortDate($0.occurredAt, relativeTo: now)
            let rhs = safeSortDate($1.occurredAt, relativeTo: now)
            if lhs != rhs { return lhs > rhs }
            return $0.id < $1.id
        }
    }

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
        var seenPlaceIDs = Set<String>()
        var results: [FeedFeaturedPlace] = []

        for event in newestFirst(activity, relativeTo: now) {
            guard let place = event.place,
                  !currentUserPlaceIDs.contains(place.place.id),
                  seenPlaceIDs.insert(place.place.id).inserted
            else {
                continue
            }

            results.append(
                FeedFeaturedPlace(
                    visiblePlace: place,
                    actor: event.actor,
                    reason: place.userPlace.status == .been
                        ? "Checked in by \(event.actor.displayName)"
                        : "Wanna by \(event.actor.displayName)"
                )
            )
            if results.count == max(0, limit) { break }
        }

        return results
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
