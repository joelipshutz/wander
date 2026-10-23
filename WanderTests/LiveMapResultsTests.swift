import XCTest
import CoreGraphics
@testable import Wander

@MainActor
final class LiveMapResultsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAllMapPagesRetainMoreThanOneFeedWindowAndMoreThanOneHundredPins() async throws {
        let rows = (0..<127).map { event($0) }
        var cursors: [String?] = []
        var counts: [Int] = [], completions: [Bool] = []
        var received: [FeedActivity] = []
        try await LiveMapPaging.readAll(page: { cursor in
            cursors.append(cursor)
            let offset = Int(cursor ?? "0")!
            let end = min(offset + 20, rows.count)
            return self.page(Array(rows[offset..<end]), next: end < rows.count ? String(end) : nil)
        }, receive: { activity, complete in
            received = activity; counts.append(activity.count); completions.append(complete)
        })
        XCTAssertEqual(cursors, [nil, "20", "40", "60", "80", "100", "120"])
        XCTAssertEqual(counts, [20, 40, 60, 80, 100, 120, 127])
        XCTAssertEqual(completions, [false, false, false, false, false, false, true])
        XCTAssertEqual(Set(received.map(\.id)), Set(rows.map(\.id)))
        let pins = LiveMapProjection.pins(activities: received, featured: [])
        XCTAssertEqual(pins.count, 127)
        XCTAssertEqual(LiveMapPaging.countText(received.count, complete: true), "100+ activities")
        let compact = LivePinDensity.compactIDs(points: pins.map { ($0.id, CGPoint(x: 100, y: 100)) }, selectedID: nil)
        XCTAssertEqual(compact.count, 126, "Density changes presentation without clipping the complete pin set.")
        XCTAssertEqual(pins.count, 127)
    }

    func testPaginationDeduplicatesBoundaryRowsAndContinuesEmptyAuthorizedPages() async throws {
        let first = event(1), second = event(2)
        var requested: [String?] = [], received: [FeedActivity] = [], exhausted = false
        try await LiveMapPaging.readAll(page: { cursor in
            requested.append(cursor)
            switch cursor {
            case nil: return self.page([first], next: "empty")
            case "empty": return self.page([], next: "last")
            default: return self.page([first, second], next: nil)
            }
        }, receive: { received = $0; exhausted = $1 })
        XCTAssertEqual(requested, [nil, "empty", "last"])
        XCTAssertEqual(received.map(\.id), [first.id, second.id])
        XCTAssertTrue(exhausted)
    }

    func testRepeatedCursorFailsInsteadOfLoopingOrClaimingCompletion() async {
        var calls = 0, completions: [Bool] = []
        do {
            try await LiveMapPaging.readAll(page: { _ in
                calls += 1
                return self.page([self.event(1)], next: "same")
            }, receive: { _, complete in completions.append(complete) })
            XCTFail("A repeated cursor must fail closed")
        } catch {
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(completions, [false, false])
        }
    }

    func testCountDistinguishesLoadingEmptyPartialAndCompleteResults() {
        for (count, complete, text) in [
            (0, false, "Finding activities…"), (0, true, "0 activities"),
            (1, false, "1+ activities"), (1, true, "1 activity"),
            (20, false, "20+ activities"), (20, true, "20 activities"),
            (99, true, "99 activities"), (100, false, "100+ activities"),
            (100, true, "100+ activities"), (127, true, "100+ activities"),
            (-1, true, "0 activities")
        ] { XCTAssertEqual(LiveMapPaging.countText(count, complete: complete), text) }
    }

    func testProjectionGroupsActivityWithoutLosingPlacesOrDuplicatingFeatured() {
        // Projection uses the real clock's future-date protection; keep these
        // ordering fixtures in the past rather than using the query clock.
        let visitTime = Date(timeIntervalSince1970: 1_700_000_000)
        let original = event(1, at: visitTime)
        let newer = event(2, placeID: "place-1", at: visitTime.addingTimeInterval(60))
        let other = event(3, at: visitTime.addingTimeInterval(120))
        let featured = place("featured")
        let pins = LiveMapProjection.pins(activities: [original, newer, other],
            featured: [original.place!, featured, featured])
        XCTAssertEqual(pins.map(\.id), ["featured", "place-1", "place-3"])
        XCTAssertEqual(pins.first { $0.id == "place-1" }?.activities.map(\.id), [newer.id, original.id])
        XCTAssertTrue(pins.first { $0.id == "featured" }?.activities.isEmpty == true)
    }

    func testControllerPublishesEveryPinWhenFinalPageEndsBetweenCoalescedBatches() async {
        for total in [127, 627] {
            let rows = (0..<total).map { event($0, at: now.addingTimeInterval(-Double($0 + 1))) }
            let repository = MapPageTestRepository { cursor in
                let offset = Int(cursor ?? "0")!
                let end = min(offset + 50, total)
                return self.page(Array(rows[offset..<end]), next: end < total ? String(end) : nil)
            }
            let model = LiveMapResults()
            await model.load(request: request(), repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
            XCTAssertTrue(model.complete)
            XCTAssertFalse(model.error)
            XCTAssertEqual(model.activities.count, total)
            XCTAssertEqual(Set(model.activities.map(\.id)), Set(rows.map(\.id)))
            XCTAssertEqual(LiveMapProjection.pins(activities: model.activities, featured: model.featuredPlaces).count, total)
            XCTAssertEqual(LiveMapPaging.countText(model.activities.count, complete: model.complete), "100+ activities")
            XCTAssertEqual(repository.requests.count, (total + 49) / 50)
            XCTAssertTrue(repository.requests.allSatisfy { $0.limit == 50 })
        }
    }

    func testControllerAppliesQueryAndAuthorizationToEveryPage() async {
        let model = LiveMapResults()
        let allowed = event(1), denied = event(2), future = event(3, at: now.addingTimeInterval(1))
        let repository = MapPageTestRepository { cursor in
            cursor == nil ? self.page([allowed], next: "last") : self.page([denied, future], next: nil)
        }
        await model.load(request: request(), repository: repository, fixture: [], featured: { [] }, permits: { $0.id != denied.id })
        XCTAssertEqual(model.activities.map(\.id), [allowed.id])
        XCTAssertTrue(model.complete)
        XCTAssertFalse(model.error)
        XCTAssertEqual(repository.requests.map(\.limit), [50, 50])
        XCTAssertTrue(repository.requests.allSatisfy { $0.query == self.request().query && $0.audience == .everyone })
        model.revalidate(userID: "viewer", permits: { _ in false })
        XCTAssertTrue(model.activities.isEmpty, "Revoked social access must remove loaded pins immediately.")
    }

    func testLateOldRequestCannotReplaceNewAccountResultsOrFeaturedPlaces() async {
        let model = LiveMapResults(), gate = MapPageGate()
        let old = event(1), fresh = event(2)
        let repository = MapPageTestRepository { _ in await gate.wait() }
        let task = Task { @MainActor in
            await model.load(request: self.request(userID: "old-account"), repository: repository, fixture: [],
                featured: { [self.place("old-featured")] }, permits: { _ in true })
        }
        await gate.waitUntilRequested()
        await model.load(request: request(userID: "new-account"), repository: nil, fixture: [fresh],
            featured: { [self.place("new-featured")] }, permits: { _ in true })
        gate.resume(page([old], next: nil))
        await task.value
        XCTAssertEqual(model.activities.map(\.id), [fresh.id])
        XCTAssertEqual(model.featuredPlaces.map { $0.place.id }, ["new-featured"])
        XCTAssertTrue(model.complete)
        XCTAssertFalse(model.error)
    }

    func testCancellationRejectsTheInFlightPageAndStopsFurtherRequests() async {
        let gate = MapPageGate()
        var received = 0, calls = 0
        let task = Task { @MainActor () -> Bool in
            do {
                try await LiveMapPaging.readAll(page: { _ in calls += 1; return await gate.wait() },
                    receive: { _, _ in received += 1 })
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        await gate.waitUntilRequested()
        task.cancel()
        gate.resume(page([event(1)], next: "next"))
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(received, 0)
    }

    func testPinKeepsCheckInBadgeWhenFilteredEventsOnlyContainANewerWannaOrListUpdate() {
        let visited = place("visited")
        let wanna = FeedActivity(id: "wanna", kind: .placeWannaGo,
            actor: ProfileShell(id: "person", handle: "person", displayName: "Person", avatarURL: nil,
                                bio: nil, relationship: .mutual), place: visited, occurredAt: now)
        let list = FeedActivity(id: "list", kind: .listItemAdded, actor: wanna.actor,
            place: visited, occurredAt: now)
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [wanna]).kind, .checkIn)
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [list]).kind, .checkIn)
        XCTAssertEqual(wanna.resolvedTicketKind, .wanna, "The pin badge must not rewrite activity identity.")
        XCTAssertEqual(list.resolvedTicketKind, .list)

        visited.userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        visited.userPlace.visitedAt = now.addingTimeInterval(-86_400)
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [wanna]).kind, .checkIn)
        visited.userPlace.visitedAt = nil
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [wanna]).kind, .wanna)
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [list]).kind, .list)
        visited.userPlace.visitedAt = now.addingTimeInterval(-86_400)
        visited.userPlace.deletedAt = now
        XCTAssertEqual(LivePlacePin(id: visited.place.id, place: visited, activities: [wanna]).kind, .wanna,
                       "Deleted saves cannot supply prior-check-in evidence.")
    }

    func testPriorOwnVisitOnCanonicalDuplicateParentWinsWithoutAddingFilteredActivity() {
        let active = place("active-wanna"), prior = place("old-check-in")
        active.userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        for row in [active, prior] {
            row.place.canonicalName = "Same Cafe"
            row.place.address = "10 Main Street"
            row.place.sourceProviderPlaceID = row.place.id
        }
        let wanna = FeedActivity(id: "current-wanna", kind: .placeWannaGo,
            actor: ProfileShell(id: "person", handle: "person", displayName: "Person", avatarURL: nil,
                                bio: nil, relationship: .mutual), place: active, occurredAt: now)
        let pins = LiveMapProjection.pins(activities: [wanna], featured: [], ownCheckInPlaces: [prior])
        XCTAssertEqual(pins.map(\.id), [active.place.id])
        XCTAssertEqual(pins.first?.activities.map(\.id), [wanna.id])
        XCTAssertEqual(pins.first?.kind, .checkIn)
        XCTAssertEqual(wanna.resolvedTicketKind, .wanna)

        prior.userPlace.deletedAt = now
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .wanna)
        prior.userPlace.deletedAt = nil
        prior.owner.deletedAt = now
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .wanna)
        prior.owner.deletedAt = nil
        prior.userPlace.userID = "unrelated-owner"
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .wanna)
        prior.userPlace.userID = prior.owner.id
        prior.place.address = "20 Main Street"
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .wanna,
            "A nearby same-name branch with a conflicting street is not a prior visit.")
    }

    func testExactProviderCheckInEvidenceSurvivesRenamingWithoutFuzzyMatchingOtherNames() {
        let active = place("active"), prior = place("prior")
        active.userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        active.place.sourceProviderPlaceID = "same-provider-place"
        prior.place.sourceProviderPlaceID = "same-provider-place"
        let wanna = FeedActivity(id: "current-wanna", kind: .placeWannaGo,
            actor: ProfileShell(id: "person", handle: "person", displayName: "Person", avatarURL: nil,
                                bio: nil, relationship: .mutual), place: active, occurredAt: now)
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .checkIn)
        prior.place.sourceProviderPlaceID = "different-provider-place"
        XCTAssertEqual(LiveMapProjection.pins(activities: [wanna], featured: [],
            ownCheckInPlaces: [prior]).first?.kind, .wanna)
    }

    private func request(userID: String = "viewer") -> LiveMapRequest {
        LiveMapRequest(userID: userID, audience: .everyone,
            query: LiveFeedQuery(occurredBefore: now), featured: true, viewport: nil, refresh: 0)
    }
    private func page(_ activity: [FeedActivity], next: String?) -> FollowedFeedPage {
        FollowedFeedPage(activity: activity, featuredPlaces: [], nextCursor: next, fetchedAt: now)
    }
    private func event(_ index: Int, placeID: String? = nil, at date: Date? = nil) -> FeedActivity {
        let visible = place(placeID ?? "place-\(index)")
        return FeedActivity(id: "activity-\(index)", kind: .placeBeen,
            actor: ProfileShell(id: "person", handle: "person", displayName: "Person", avatarURL: nil, bio: nil, relationship: .mutual),
            place: visible, occurredAt: date ?? now.addingTimeInterval(Double(index) - 200))
    }
    private func place(_ id: String) -> VisiblePlace {
        let local = LocalPlace(localID: id, canonicalName: id, category: "coffee", latitude: 34.05, longitude: -118.24)
        let owner = LocalProfile(localID: "person", handle: "person", displayName: "Person")
        let save = LocalUserPlace(localID: "save-\(id)", userID: owner.id, placeID: local.id,
            status: .been, visibility: .mutuals, sourceType: "manual")
        return VisiblePlace(id: save.id, place: local, userPlace: save, owner: owner)
    }
}

@MainActor
private final class MapPageTestRepository: FeedRepository {
    struct Request { let audience: FeedAudience; let query: LiveFeedQuery; let before: String?; let limit: Int }
    var requests: [Request] = []
    let page: (String?) async -> FollowedFeedPage
    init(page: @escaping (String?) async -> FollowedFeedPage) { self.page = page }
    func liveMapActivity(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int) async throws -> FollowedFeedPage {
        requests.append(Request(audience: audience, query: query, before: before, limit: limit))
        return await page(before)
    }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("Map enumeration must use the map endpoint")
        return await page(before)
    }
}

@MainActor
private final class MapPageGate {
    private var result: CheckedContinuation<Void, Never>?
    private var requested: CheckedContinuation<Void, Never>?
    private var page: FollowedFeedPage?
    func wait() async -> FollowedFeedPage {
        await withCheckedContinuation { continuation in
            result = continuation
            requested?.resume(); requested = nil
        }
        // The page stays on MainActor; only the readiness signal crosses the
        // continuation boundary, so its SwiftData-backed values are never sent.
        return page!
    }
    func waitUntilRequested() async {
        if result != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func resume(_ page: FollowedFeedPage) {
        self.page = page
        result?.resume(); result = nil
    }
}
