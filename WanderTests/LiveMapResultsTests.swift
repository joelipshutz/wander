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

    func testCanonicalPinCombinesAllActorsAndKindsBeforeDensityWithoutChangingActivityCount() throws {
        let source = place("canonical"), alias = place("alias"), third = place("third")
        for value in [source, alias, third] {
            value.place.sourceProvider = "mapkit"
            value.place.sourceProviderPlaceID = "same-venue"
            value.userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        }
        let visit = groupedEvent("visit", place: source, actorID: "alex", kind: .placeBeen)
        let wanna = groupedEvent("wanna", place: alias, actorID: "sam", kind: .placeWannaGo)
        let list = groupedEvent("list", place: third, actorID: "pat", kind: .listItemAdded)
        let rows = [visit, wanna, list]
        let pins = LiveMapProjection.pins(activities: rows, featured: [alias, third])
        let pin = try XCTUnwrap(pins.first)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(Set(pin.activities.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(Set(pin.activities.map { $0.actor.id }), ["alex", "sam", "pat"])
        XCTAssertEqual(pin.kind, .checkIn)
        XCTAssertEqual(LiveMapPaging.countText(rows.count, complete: true), "3 activities")
        XCTAssertTrue(LivePinDensity.compactIDs(points: pins.map { ($0.id, CGPoint(x: 10, y: 10)) }, selectedID: nil).isEmpty,
            "Several records for one venue must not leave a second density dot.")
    }

    func testExplicitCanonicalUUIDReferencesJoinTransitivelyAcrossHistoricalPlaceRows() throws {
        let source = place("97000000-0000-4000-8000-000000000001")
        let alias = place("97000000-0000-4000-8000-000000000002")
        let third = place("97000000-0000-4000-8000-000000000003")
        for value in [source, alias, third] { value.place.canonicalName = "Coffee House" }
        source.place.sourceProvider = "mapkit"; source.place.sourceProviderPlaceID = "native-venue"
        alias.place.sourceProvider = "mapkit"; alias.place.sourceProviderPlaceID = source.place.id
        third.place.sourceProvider = "mapkit"; third.place.sourceProviderPlaceID = alias.place.id
        let rows = [source, alias, third].enumerated().map {
            groupedEvent("event-\($0.offset)", place: $0.element, actorID: "person-\($0.offset)", kind: .placeBeen)
        }
        let pins = LiveMapProjection.pins(activities: rows, featured: [source])
        let pin = try XCTUnwrap(pins.first)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pin.activities.count, 3)
        XCTAssertEqual(pin.identity.persistedPlaceIDs, [source.place.id, alias.place.id, third.place.id])
        XCTAssertEqual(pin.identity.cacheKey, LivePlaceIdentity(places: [third.place, source.place, alias.place]).cacheKey)
        for value in [source, alias, third] { XCTAssertTrue(pin.identity.matches(value.place)) }
        let reversed = try XCTUnwrap(LiveMapProjection.pins(activities: Array(rows.reversed()), featured: [third]).first)
        XCTAssertEqual(pin.id, reversed.id)
        XCTAssertEqual(pin.identity, reversed.identity)
        XCTAssertEqual(pin.activities.map(\.id), reversed.activities.map(\.id))
    }

    func testCanonicalNameStreetAliasesJoinButCoincidentDifferentVenuesStaySeparate() {
        let first = place("one"), second = place("two"), otherBranch = place("branch"), otherVenue = place("other")
        first.place.canonicalName = "Example Café"; first.place.address = "10 Main Street"
        second.place.canonicalName = "example cafe"; second.place.address = "10 Main St"
        otherBranch.place.canonicalName = "Example Café"; otherBranch.place.address = "12 Main Street"
        otherVenue.place.canonicalName = "Another business"; otherVenue.place.address = "10 Main Street"
        let rows = [first, second, otherBranch, otherVenue].enumerated().map {
            groupedEvent("event-\($0.offset)", place: $0.element, actorID: "person", kind: .placeWannaGo)
        }
        let pins = LiveMapProjection.pins(activities: rows, featured: [])
        XCTAssertEqual(pins.count, 3)
        XCTAssertEqual(pins.first { $0.identity.matches(first.place) }?.activities.count, 2)
        first.place.address = nil; second.place.address = nil
        XCTAssertEqual(LiveMapProjection.pins(activities: Array(rows.prefix(2)), featured: []).count, 2,
            "Same-name coordinates alone are not canonical identity evidence.")
    }

    func testExistingSelectedPinAndViewedAliasSurviveLaterCanonicalPage() throws {
        let original = place("z-original"), later = place("a-later")
        for value in [original, later] {
            value.place.sourceProvider = "mapkit"; value.place.sourceProviderPlaceID = "canonical"
        }
        let originalEvent = groupedEvent("original", place: original, actorID: "alex", kind: .placeBeen)
        let laterEvent = groupedEvent("later", place: later, actorID: "sam", kind: .placeWannaGo)
        let old = LiveMapProjection.pins(activities: [originalEvent], featured: [])
        let pin = try XCTUnwrap(LiveMapProjection.pins(activities: [laterEvent, originalEvent], featured: [], previousPins: old).first)
        XCTAssertEqual(pin.id, old.first?.id, "Pagination must preserve the mounted selection.")
        XCTAssertTrue(pin.isViewed(dates: [original.place.id: now], now: now))
        XCTAssertTrue(pin.isViewed(dates: [later.place.id: now], now: now))
        XCTAssertFalse(pin.isViewed(dates: [original.place.id: now.addingTimeInterval(-86_400)], now: now))
        let afterRevocation = LiveMapProjection.pins(activities: [laterEvent], featured: [], previousPins: [pin])
        XCTAssertEqual(afterRevocation.first?.id, pin.id,
            "Selection survives when the old representative disappears but a valid alias remains.")
        XCTAssertEqual(afterRevocation.first?.place.place.id, later.place.id)
        XCTAssertFalse(afterRevocation.first?.identity.placeIDs.contains(original.place.id) == true)
        XCTAssertEqual(afterRevocation.first?.activities.map(\.id), [laterEvent.id],
            "Retaining a pin ID must never retain a revoked actor's activity.")
        XCTAssertTrue(LiveMapProjection.pins(activities: [], featured: [], previousPins: [pin]).isEmpty)
    }

    func testCanonicalProjectionUsesValidCoordinateAndRetainsEveryAuthorizedOriginal() throws {
        let missing = place("a-missing"), valid = place("z-valid")
        for value in [missing, valid] {
            value.place.sourceProvider = "mapkit"; value.place.sourceProviderPlaceID = "same-place"
        }
        missing.place.latitude = .nan
        let rows = [groupedEvent("one", place: missing, actorID: "alex", kind: .placeBeen),
                    groupedEvent("two", place: valid, actorID: "sam", kind: .placeWannaGo)]
        let pins = LiveMapProjection.pins(activities: rows, featured: [])
        XCTAssertEqual(pins.count, 1)
        let pin = try XCTUnwrap(pins.first)
        XCTAssertEqual(pin.place.place.id, valid.place.id)
        XCTAssertEqual(Set(pin.activities.map(\.id)), ["one", "two"])
    }

    func testMergedPinSplittingAfterAliasCorrectionCannotReuseOneIdentifierTwice() {
        let first = place("first"), second = place("second")
        for value in [first, second] {
            value.place.sourceProvider = "mapkit"; value.place.sourceProviderPlaceID = "same-place"
        }
        let rows = [groupedEvent("one", place: first, actorID: "alex", kind: .placeBeen),
                    groupedEvent("two", place: second, actorID: "sam", kind: .placeWannaGo)]
        let old = LiveMapProjection.pins(activities: rows, featured: [])
        second.place.sourceProviderPlaceID = "corrected-separate-place"
        let refreshed = LiveMapProjection.pins(activities: rows, featured: [], previousPins: old)
        XCTAssertEqual(refreshed.count, 2)
        XCTAssertEqual(Set(refreshed.map(\.id)).count, 2)
        XCTAssertEqual(Set(refreshed.flatMap(\.activities).map(\.id)), ["one", "two"])
    }

    func testServerAndLocalIdentityAliasesRemainOnePinWithoutSendingLocalFixtureIDs() throws {
        let synced = place("local-original"), remote = place("98000000-0000-4000-8000-000000000001")
        synced.place.serverID = remote.place.id
        let rows = [groupedEvent("one", place: synced, actorID: "alex", kind: .placeBeen),
                    groupedEvent("two", place: remote, actorID: "sam", kind: .placeWannaGo)]
        let pins = LiveMapProjection.pins(activities: rows, featured: [])
        XCTAssertEqual(pins.count, 1)
        let identity = try XCTUnwrap(pins.first?.identity)
        XCTAssertEqual(identity.persistedPlaceIDs, [remote.place.id])
        XCTAssertTrue(identity.placeIDs.contains("local-original"))
        XCTAssertTrue(identity.matches(synced.place))
        XCTAssertTrue(identity.matches(remote.place))
    }

    func testOpaqueProviderIDsKeepCaseWhileProviderNamespacesNormalize() {
        let upper = place("upper"), same = place("same"), lower = place("lower")
        upper.place.sourceProvider = "mapkit"; upper.place.sourceProviderPlaceID = "PlaceTokenA"
        same.place.sourceProvider = " MAPKIT "; same.place.sourceProviderPlaceID = "PlaceTokenA"
        lower.place.sourceProvider = "mapkit"; lower.place.sourceProviderPlaceID = "placetokena"
        let identity = LivePlaceIdentity(places: [upper.place])
        XCTAssertTrue(identity.matches(same.place))
        XCTAssertTrue(identity.intersects(LivePlaceIdentity(places: [same.place])))
        XCTAssertFalse(identity.matches(lower.place))
        XCTAssertFalse(identity.intersects(LivePlaceIdentity(places: [lower.place])))
        let rows = [upper, same, lower].enumerated().map {
            groupedEvent("case-\($0.offset)", place: $0.element, actorID: "person", kind: .placeBeen)
        }
        XCTAssertEqual(LiveMapProjection.pins(activities: rows, featured: []).count, 2)
    }

    func testWeakStreetIdentityRequiresNonblankLocalityAndNearbyCoordinates() {
        let first = place("first"), second = place("second")
        for value in [first, second] {
            value.place.canonicalName = "Coffee House"; value.place.address = "10 Main Street"
        }
        second.place.address = "10 Main St."
        let identity = LivePlaceIdentity(places: [first.place])
        XCTAssertTrue(identity.matches(second.place))
        second.place.locality = nil
        XCTAssertFalse(identity.matches(second.place))
        second.place.locality = "Sampleton"; second.place.latitude += 0.01
        XCTAssertFalse(identity.matches(second.place), "Same name/street/locality across town is insufficient")
        second.place.latitude = first.place.latitude + 0.0004
        XCTAssertTrue(identity.matches(second.place))
        second.place.region = "Other Region"
        XCTAssertFalse(identity.matches(second.place))
        first.place.locality = nil; second.place.locality = nil; second.place.region = "CA"
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
    }

    func testUUIDReferenceRequiresNearbyNameOrStreetEvidenceAndCannotSeedAnUnverifiedTarget() {
        let target = place("97000000-0000-4000-8000-000000000021")
        let alias = place("97000000-0000-4000-8000-000000000022")
        target.place.canonicalName = "Coffee House"
        alias.place.sourceProviderPlaceID = target.place.id.uppercased()
        let initial = LivePlaceIdentity(places: [alias.place])
        XCTAssertEqual(initial.persistedPlaceIDs, [alias.place.id])
        XCTAssertFalse(initial.matches(target.place), "A nearby UUID reference with unrelated metadata is insufficient")
        alias.place.canonicalName = target.place.canonicalName
        XCTAssertTrue(LivePlaceIdentity(places: [alias.place]).matches(target.place))
        alias.place.latitude += 0.01
        XCTAssertFalse(LivePlaceIdentity(places: [alias.place]).matches(target.place))
        alias.place.latitude = target.place.latitude
        alias.place.canonicalName = "Renamed Coffee House"
        target.place.address = "10 Main Street"; alias.place.address = "10 Main St"
        XCTAssertTrue(LivePlaceIdentity(places: [alias.place]).matches(target.place))
        alias.place.locality = nil
        XCTAssertFalse(LivePlaceIdentity(places: [alias.place]).matches(target.place))
    }

    func testSharedUUIDProviderTokenCannotBypassLocationCorroboration() {
        let first = place("first"), second = place("second")
        for value in [first, second] {
            value.place.canonicalName = "Coffee House"
            value.place.sourceProviderPlaceID = "97000000-0000-4000-8000-000000000031"
        }
        second.place.latitude += 0.01
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
        second.place.latitude = first.place.latitude
        XCTAssertTrue(LivePlaceIdentity(places: [first.place]).matches(second.place))
        second.place.sourceProvider = "another-provider"
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
    }

    func testRemovedRepresentativeAndLaterSplitRetainOneSelectionWithoutRevokedPayload() throws {
        let original = place("a-original"), second = place("b-second"), third = place("c-third")
        for value in [original, second, third] { value.place.sourceProviderPlaceID = "same-venue" }
        let rows = [original, second, third].enumerated().map {
            groupedEvent("split-\($0.offset)", place: $0.element, actorID: "person-\($0.offset)", kind: .placeBeen)
        }
        let previous = LiveMapProjection.pins(activities: rows, featured: [])
        let old = try XCTUnwrap(previous.first)
        let oldKey = old.identity.cacheKey
        second.place.sourceProviderPlaceID = "corrected-second"
        third.place.sourceProviderPlaceID = "corrected-third"
        XCTAssertEqual(old.identity.cacheKey, oldKey, "Previous identity must be immutable evidence")
        let current = LiveMapProjection.pins(activities: Array(rows.dropFirst()), featured: [], previousPins: previous)
        XCTAssertEqual(current.count, 2)
        XCTAssertEqual(Set(current.map(\.id)).count, 2)
        XCTAssertEqual(current.filter { $0.id == old.id }.count, 1)
        XCTAssertEqual(Set(current.flatMap(\.activities).map(\.id)), ["split-1", "split-2"])
        XCTAssertTrue(current.allSatisfy { $0.place.place.id != original.place.id })
        XCTAssertTrue(current.allSatisfy { !$0.identity.placeIDs.contains(original.place.id) })
        let reversed = LiveMapProjection.pins(activities: Array(rows.dropFirst().reversed()), featured: [], previousPins: previous)
        XCTAssertEqual(current.map(\.id), reversed.map(\.id))
    }

    func testFiveAndThirtySecondWarmReturnsReuseTheSnapshot() async {
        let start = ContinuousClock.now
        var instant = start
        let model = LiveMapResults(clock: { instant })
        let repository = MapPageTestRepository { _ in self.page([self.event(1)], next: nil) }
        for seconds in [0, 5, 30] {
            instant = start.advanced(by: .seconds(seconds))
            await model.load(request: request(), repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
            XCTAssertEqual(model.activities.map(\.id), [event(1).id])
        }
        XCTAssertEqual(repository.requests.count, 1)
    }

    func testTwoMinuteRefreshRetainsRowsAndLoadsFeaturedBeforeSlowHistory() async {
        var instant = ContinuousClock.now
        let model = LiveMapResults(clock: { instant }), gate = MapPageGate()
        let original = event(1), replacement = event(2)
        await model.load(request: request(), repository: nil, fixture: [original], featured: { [] }, permits: { _ in true })
        instant = instant.advanced(by: .seconds(120))
        let repository = MapPageTestRepository { _ in await gate.wait() }
        let task = Task { await model.load(request: self.request(), repository: repository, fixture: [],
            featured: { [self.place("independent")] }, permits: { _ in true }) }
        await gate.waitUntilRequested()
        for _ in 0..<100 where model.featuredPlaces.isEmpty { await Task.yield() }
        XCTAssertEqual(model.activities.map(\.id), [original.id], "A pending replacement must not blank the map")
        XCTAssertEqual(model.featuredPlaces.map { $0.place.id }, ["independent"])
        gate.resume(page([replacement], next: nil))
        await task.value
        XCTAssertEqual(model.activities.map(\.id), [replacement.id], "Successful complete results remove missing rows")
    }

    func testWarmCacheDoesNotRenewSocialAuthorization() async {
        let start = ContinuousClock.now
        var instant = start
        let model = LiveMapResults(clock: { instant })
        await model.load(request: request(), repository: nil, fixture: [event(1)], featured: { [self.place("featured")] }, permits: { _ in true })
        instant = start.advanced(by: .seconds(30))
        await model.load(request: request(), repository: nil, fixture: [], featured: { [] }, permits: { _ in true })
        XCTAssertEqual(model.activities.count, 1)
        instant = start.advanced(by: .seconds(900))
        model.revalidate(userID: "viewer", permits: { _ in true })
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertTrue(model.featuredPlaces.isEmpty)
    }

    func testReturningToCachedQueryKeepsOriginalReceiptAndRejectsRevocation() async {
        let model = LiveMapResults()
        let first = request()
        let second = LiveMapRequest(userID: "viewer", audience: .everyone,
            query: LiveFeedQuery(activityType: .wannas), featured: false, viewport: nil, refresh: 0)
        var calls = 0
        let repository = MapPageTestRepository { _ in calls += 1; return self.page([self.event(1)], next: nil) }
        await model.load(request: first, repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
        await model.load(request: second, repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
        await model.load(request: first, repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.activities.count, 1)
        model.revalidate(userID: "viewer", permits: { _ in false })
        await model.load(request: second, repository: repository, fixture: [], featured: { [] }, permits: { _ in false })
        await model.load(request: first, repository: repository, fixture: [], featured: { [] }, permits: { _ in false })
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testForcedRefreshCoalescesAndRetainsContentUntilCancelledResponse() async {
        let model = LiveMapResults(), gate = MapPageGate()
        await model.load(request: request(), repository: nil, fixture: [event(1)], featured: { [] }, permits: { _ in true })
        let initial = request()
        let forced = LiveMapRequest(userID: initial.userID, audience: initial.audience, query: initial.query,
                                    featured: initial.featured, viewport: nil, refresh: 1)
        let repository = MapPageTestRepository { _ in await gate.wait() }
        let task = Task { await model.load(request: forced, repository: repository, fixture: [], featured: { [] }, permits: { _ in true }) }
        await gate.waitUntilRequested()
        await model.load(request: forced, repository: repository, fixture: [], featured: { [] }, permits: { _ in true })
        XCTAssertEqual(repository.requests.count, 1)
        XCTAssertEqual(model.activities.count, 1)
        task.cancel(); gate.resume(page([event(2)], next: nil)); await task.value
        XCTAssertEqual(model.activities.map(\.id), [event(1).id])
    }

    func testCacheHitRetiresOlderLoadingOwnershipSoThatScopeCanLoadAgain() async {
        let model = LiveMapResults(), gate = MapPageGate()
        let cached = request()
        let pending = LiveMapRequest(userID: "viewer", audience: .everyone,
            query: .init(activityType: .lists), featured: false, viewport: nil, refresh: 0)
        await model.load(request: cached, repository: nil, fixture: [event(1)], featured: { [] }, permits: { _ in true })
        let repository = MapPageTestRepository { _ in await gate.wait() }
        let old = Task { await model.load(request: pending, repository: repository, fixture: [], featured: { [] }, permits: { _ in true }) }
        await gate.waitUntilRequested()
        await model.load(request: cached, repository: nil, fixture: [], featured: { [] }, permits: { _ in true })
        gate.resume(page([], next: nil)); await old.value
        var called = false
        await model.load(request: pending, repository: nil, fixture: [], featured: { called = true; return [] }, permits: { _ in true })
        XCTAssertTrue(called, "A completed obsolete load cannot poison future loads of its scope")
    }

    func testAccountRevalidationImmediatelyRemovesFeaturedAndSocialSnapshots() async {
        let model = LiveMapResults()
        await model.load(request: request(), repository: nil, fixture: [event(1)], featured: { [self.place("featured")] }, permits: { _ in true })
        model.revalidate(userID: "other", permits: { _ in true })
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertTrue(model.featuredPlaces.isEmpty)
    }

    func testOfflineRefreshRetainsAuthorizedRowsButDeniedReadClearsThem() async {
        let model = LiveMapResults()
        let initial = request()
        await model.load(request: initial, repository: nil, fixture: [event(1)], featured: { [] }, permits: { _ in true })
        func forced(_ revision: UInt64) -> LiveMapRequest {
            .init(userID: initial.userID, audience: initial.audience, query: initial.query,
                  featured: true, viewport: nil, refresh: revision)
        }
        let offline = MapPageTestRepository { _ in throw URLError(.notConnectedToInternet) }
        await model.load(request: forced(1), repository: offline, fixture: [], featured: { nil }, permits: { _ in true })
        XCTAssertEqual(model.activities.map(\.id), [event(1).id])
        XCTAssertTrue(model.error)
        let denied = MapPageTestRepository { _ in throw WanderRemoteError.notAuthenticated }
        await model.load(request: forced(2), repository: denied, fixture: [], featured: { [] }, permits: { _ in true })
        XCTAssertTrue(model.activities.isEmpty)
        XCTAssertTrue(model.featuredPlaces.isEmpty)
    }

    func testRevalidationDuringCoalescedPagingKeepsUnpublishedReceipts() async {
        let model = LiveMapResults(), gate = MapPageGate()
        let rows = (0..<170).map { event($0) }
        let repository = MapPageTestRepository { cursor in
            let offset = Int(cursor ?? "0")!
            if offset == 150 { return await gate.wait() }
            return self.page(Array(rows[offset..<(offset+50)]), next: String(offset+50))
        }
        let task = Task { await model.load(request: self.request(), repository: repository, fixture: [], featured: { [] }, permits: { _ in true }) }
        await gate.waitUntilRequested()
        XCTAssertEqual(model.activities.count, 100)
        model.revalidate(userID: "viewer", permits: { _ in true })
        gate.resume(page(Array(rows[150..<170]), next: nil)); await task.value
        XCTAssertEqual(model.activities.count, 170)
        XCTAssertEqual(Set(model.activities.map(\.id)), Set(rows.map(\.id)))
    }

    private func groupedEvent(_ id: String, place: VisiblePlace, actorID: String, kind: FeedActivityKind) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
            actor: ProfileShell(id: actorID, handle: actorID, displayName: actorID, avatarURL: nil, bio: nil, relationship: .mutual),
            place: place, occurredAt: Date(timeIntervalSince1970: 1_700_000_000))
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
        let local = LocalPlace(localID: id, canonicalName: id, category: "coffee", locality: "Sampleton", region: "CA", country: "US",
            latitude: 34.05, longitude: -118.24)
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
    let page: (String?) async throws -> FollowedFeedPage
    init(page: @escaping (String?) async throws -> FollowedFeedPage) { self.page = page }
    func liveMapActivity(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int) async throws -> FollowedFeedPage {
        requests.append(Request(audience: audience, query: query, before: before, limit: limit))
        return try await page(before)
    }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("Map enumeration must use the map endpoint")
        return try await page(before)
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
