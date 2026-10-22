import SwiftUI
import MapKit

struct LiveMapRequest: Equatable {
    let userID: String
    let audience: FeedAudience
    let query: LiveFeedQuery
    let featured: Bool
    let viewport: MapViewport?
    let refresh: UInt64
}

enum LiveMapPaging {
    @MainActor
    static func readAll(page: (String?) async throws -> FollowedFeedPage,
                        receive: ([FeedActivity], Bool) -> Void) async throws {
        var cursor: String?, requested = Set<String>(), seen = Set<String>()
        var accumulated: [FeedActivity] = []
        repeat {
            try Task.checkCancellation()
            if let cursor, !requested.insert(cursor).inserted {
                throw WanderRemoteError.invalidResponse("Map pagination did not advance")
            }
            let next = try await page(cursor)
            try Task.checkCancellation()
            accumulated.append(contentsOf: next.activity.filter { seen.insert($0.id).inserted })
            cursor = next.nextCursor
            receive(accumulated, cursor == nil)
            await Task.yield()
        } while cursor != nil
    }

    static func countText(_ count: Int, complete: Bool) -> String {
        let count = max(0, count)
        if count >= 100 { return "100+ activities" }
        if !complete && count == 0 { return "Finding activities…" }
        return "\(count)\(complete ? "" : "+") \(count == 1 && complete ? "activity" : "activities")"
    }
}

/// A map snapshot is independent of the Feed's visible tile window. It changes
/// on page/query/authorization updates, never on a drawer animation frame.
@MainActor
final class LiveMapResults: ObservableObject {
    @Published private(set) var activities: [FeedActivity] = []
    @Published private(set) var featuredPlaces: [VisiblePlace] = []
    @Published private(set) var complete = false
    @Published private(set) var error = false
    @Published private(set) var revision: UInt64 = 0
    private var requestID = UUID()
    private var lease = LiveFeedDisplayLease()
    private var expiryTask: Task<Void, Never>?

    func load(request: LiveMapRequest, repository: (any FeedRepository)?,
              fixture: [FeedActivity], featured: () async -> [VisiblePlace],
              permits: @escaping (FeedActivity) -> Bool) async {
        let token = UUID(); requestID = token
        expiryTask?.cancel(); lease = LiveFeedDisplayLease()
        activities = []; featuredPlaces = []; complete = false; error = false; revision &+= 1
        do {
            if let repository {
                var processedCount = 0
                var accumulated: [FeedActivity] = []
                var lastPublishedCount = 0
                try await LiveMapPaging.readAll(page: { cursor in
                    try await repository.liveMapActivity(audience: request.audience, query: request.query,
                                                         before: cursor, limit: 50)
                }, receive: { [weak self] rows, exhausted in
                    guard let self, self.requestID == token, !Task.isCancelled else { return }
                    let now = ContinuousClock.now
                    let incoming = rows.dropFirst(processedCount).filter { request.query.includes($0) && permits($0) }
                    processedCount = rows.count
                    accumulated.append(contentsOf: incoming)
                    self.lease.accept(activityIDs: incoming.map(\.id), at: now, replacing: false)
                    // Publish early feedback, then coalesce large city histories.
                    // Count formatting is bounded; the final pin snapshot is not.
                    if exhausted || accumulated.count <= 100 || accumulated.count - lastPublishedCount >= 250 {
                        self.activities = accumulated.filter { permits($0) && self.lease.permits(
                            activityID: $0.id, isOwn: $0.actor.id == request.userID, at: now) }
                        lastPublishedCount = accumulated.count
                        self.complete = exhausted
                        self.revision &+= 1
                    }
                    self.scheduleExpiry(userID: request.userID, token: token)
                })
            } else {
                activities = fixture.filter { request.query.includes($0) && permits($0) }
                lease.accept(activityIDs: activities.map(\.id), at: .now, replacing: true)
                complete = true
            }
            let candidates = await featured()
            guard requestID == token, !Task.isCancelled else { return }
            featuredPlaces = candidates
            revision &+= 1
            scheduleExpiry(userID: request.userID, token: token)
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            self.error = true; complete = false; revision &+= 1
            scheduleExpiry(userID: request.userID, token: token)
        }
    }

    func revalidate(userID: String, permits: (FeedActivity) -> Bool) {
        let now = ContinuousClock.now
        activities.removeAll { !permits($0) || !lease.permits(activityID: $0.id, isOwn: $0.actor.id == userID, at: now) }
        revision &+= 1
    }

    private func scheduleExpiry(userID: String, token: UUID) {
        expiryTask?.cancel()
        guard let expiry = lease.nextExpiry(after: .now) else { return }
        expiryTask = Task { @MainActor [weak self] in
            do { try await ContinuousClock().sleep(until: expiry) } catch { return }
            guard let self, self.requestID == token else { return }
            self.revalidate(userID: userID, permits: { _ in true })
            self.featuredPlaces = []
            self.complete = false
            self.error = true
            self.scheduleExpiry(userID: userID, token: token)
        }
    }
}

struct LivePlacePin: Identifiable {
    let id: String
    let place: VisiblePlace
    let activities: [FeedActivity]
    var kind: LivePinKind {
        if activities.isEmpty || activities.contains(where: { $0.resolvedTicketKind == .checkIn }) { return .checkIn }
        if activities.contains(where: { $0.resolvedTicketKind == .wanna }) { return .wanna }
        return .list
    }
    var accessibilityLabel: String {
        guard let latest = activities.first else { return "\(place.place.canonicalName), Featured" }
        let summary = "\(latest.actor.displayName), \(LiveActivityPresentation.title(for: latest)), \(FeedPresentation.timestampText(for: latest.occurredAt))"
        return "\(place.place.canonicalName), \(summary)"
    }
}

enum LiveMapProjection {
    static func pins(activities: [FeedActivity], featured: [VisiblePlace]) -> [LivePlacePin] {
        let groups = Dictionary(grouping: activities.filter { $0.place != nil }) { $0.place!.place.id }
        var result = groups.compactMap { id, events -> LivePlacePin? in
            guard let place = events.first?.place,
                  CLLocationCoordinate2DIsValid(.init(latitude: place.place.latitude, longitude: place.place.longitude)) else { return nil }
            return LivePlacePin(id: id, place: place, activities: FeedPresentation.newestFirst(events))
        }
        var seen = Set(result.map(\.id))
        for place in featured where CLLocationCoordinate2DIsValid(.init(latitude: place.place.latitude, longitude: place.place.longitude)) && seen.insert(place.place.id).inserted {
            result.append(LivePlacePin(id: place.place.id, place: place, activities: []))
        }
        return result.sorted { $0.id < $1.id }
    }
}
