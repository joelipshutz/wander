import XCTest
@testable import Wander

@MainActor
final class LivePlacePreviewDedupTests: XCTestCase {
    func testRepeatedListNotesKeepNewestOriginalEventBeforePreviewLimit() {
        let source = place()
        let oldest = event("list-old", source: source, age: 30, note: "Same note", listID: "first-list")
        let newest = event("list-new", source: source, age: 0, note: " Same\n note ", listID: "second-list")
        let third = event("list-third", source: source, age: 10, note: "Same\t note", listID: "third-list")
        let other = event("other", source: source, age: 40, note: "Different note")
        let final = event("final", source: source, age: 50, note: "Another note")
        let rows = recent([oldest, third, other, newest, final, newest])
        XCTAssertEqual(rows.map(\.id), [newest.id, other.id, final.id])
        XCTAssertEqual(rows.first?.list?.id, "second-list")
        XCTAssertEqual(rows.first?.occurredAt, newest.occurredAt)
        XCTAssertEqual(rows.first?.note, newest.note, "Presentation must retain the original event payload")
    }

    func testListEchoCannotReplaceDistinctSameNoteVisitsOrWannas() {
        let source = place()
        let firstVisit = event("visit-one", source: source, kind: .placeBeen, age: 30, note: "Same note")
        let secondVisit = event("visit-two", source: source, kind: .placeBeen, age: 20, note: "Same note")
        let wanna = event("wanna", source: source, kind: .placeWannaGo, age: 10, note: "Same note")
        let list = event("list", source: source, age: 0, note: "Same note")
        XCTAssertEqual(recent([list, firstVisit, secondVisit, wanna]).map(\.id),
                       [wanna.id, secondVisit.id, firstVisit.id])
    }

    func testLegacySaveSuppressesOnlyItsMatchingListEchoWithoutMergingVisits() {
        let source = place()
        source.userPlace.statusRaw = PlaceStatus.been.rawValue
        let legacy = event("legacy", source: source, kind: .placeSaved, age: 10, note: "Same note")
        let list = event("list", source: source, age: 0, note: "Same note")
        let visit = event("visit", source: source, kind: .placeBeen, age: 20, note: "Same note")
        XCTAssertEqual(recent([list, legacy, visit]).map(\.id), [legacy.id, visit.id])
        XCTAssertEqual(recent([legacy, visit]).first?.kind, .placeSaved)
    }

    func testDifferentActorsSourcesNotesAndMediaKeepIndependentListRows() {
        let source = place()
        let base = event("base", source: source, note: "Same note", mediaIDs: ["a", "b"])
        let variants = [
            event("actor", source: source, actorID: "other-actor", note: "Same note", mediaIDs: ["a", "b"]),
            event("source", source: place(sourceID: "other-source"), note: "Same note", mediaIDs: ["a", "b"]),
            event("note", source: source, note: "same note", mediaIDs: ["a", "b"]),
            event("media", source: source, note: "Same note", mediaIDs: ["a", "different"])
        ]
        for variant in variants {
            XCTAssertEqual(Set(recent([base, variant]).map(\.id)), Set([base.id, variant.id]), variant.id)
        }
        let reordered = event("reordered", source: source, age: 10, note: "Same note", mediaIDs: ["b", "a"])
        XCTAssertEqual(recent([base, reordered]).map(\.id), [base.id])
    }

    func testListWithUniqueMediaSurvivesMatchingVisitNote() {
        let source = place()
        let visit = event("visit", source: source, kind: .placeBeen, note: "Same note", mediaIDs: ["visit-photo"])
        let list = event("list", source: source, note: "Same note", mediaIDs: ["list-photo"])
        XCTAssertEqual(Set(recent([visit, list]).map(\.id)), Set([visit.id, list.id]))
    }

    func testNoNoteListRowsRetainTheirListNames() {
        let source = place()
        let first = event("first", source: source, age: 0, listID: "First list")
        let second = event("second", source: source, age: 1, note: " \n ", listID: "Second list")
        let rows = recent([first, second])
        XCTAssertEqual(rows.map(\.id), [first.id, second.id])
        XCTAssertEqual(rows.map(LivePlacePreviewPresentation.highlight), ["First list", "Second list"])
    }

    func testHydrationRevealsDuplicateNotesAndRefillsThreeDistinctRows() async {
        let source = place()
        let candidates = (0..<5).map { event("row-\($0)", source: source, age: Double($0)) }
        var requested: [String] = []
        let rows = await LivePlacePreviewPresentation.hydrateRecentActivity(
            candidates, placeID: "selected-place", isCurrent: { true }, resolve: { candidate in
                requested.append(candidate.id)
                let index = Int(candidate.id.dropFirst(4))!
                return self.event(candidate.id, source: source, age: Double(index),
                    note: index < 2 ? "Same note" : "Note \(index)")
            })
        XCTAssertEqual(requested, ["row-0", "row-1", "row-2", "row-3"])
        XCTAssertEqual(rows.map(\.id), ["row-0", "row-2", "row-3"])
        XCTAssertEqual(rows.map(\.note), ["Same note", "Note 2", "Note 3"])
    }

    func testInitiallyEmptyMediaDoesNotDiscardRowsWithDistinctHydratedPhotos() async {
        let source = place()
        let candidates = (0..<4).map { event("row-\($0)", source: source, age: Double($0), note: "Same note") }
        XCTAssertEqual(recent(candidates).count, 1, "Empty map media is not proof that the originals share photos")
        var requested: [String] = []
        let rows = await LivePlacePreviewPresentation.hydrateRecentActivity(
            candidates, placeID: "selected-place", isCurrent: { true }, resolve: { candidate in
                requested.append(candidate.id)
                let index = Int(candidate.id.dropFirst(4))!
                return self.event(candidate.id, source: source, age: Double(index),
                    note: "Same note", mediaIDs: ["photo-\(index)"])
            })
        XCTAssertEqual(requested, ["row-0", "row-1", "row-2"])
        XCTAssertEqual(rows.map(\.id), requested)
        XCTAssertEqual(rows.flatMap(\.media).map(\.id), ["photo-0", "photo-1", "photo-2"])
        XCTAssertEqual(LivePlacePreviewPresentation.hydrationCandidates(candidates, placeID: "selected-place").map(\.id),
            candidates.map(\.id), "Hydrated content must not alter the candidate/task identity")
    }

    func testHydrationRefillsAfterRejectedForeignAndCanonicalDuplicateCandidates() async {
        let source = place()
        let foreign = place(placeID: "another-place")
        let candidates = (0..<7).map { event("row-\($0)", source: source, age: Double($0)) }
        var requested: [String] = []
        let rows = await LivePlacePreviewPresentation.hydrateRecentActivity(
            candidates, placeID: "selected-place", isCurrent: { true }, resolve: { candidate in
                requested.append(candidate.id)
                switch candidate.id {
                case "row-0": return nil
                case "row-1": return self.event(candidate.id, source: foreign)
                case "row-2", "row-3": return self.event("canonical", source: source, kind: .placeBeen, age: 2)
                default: return self.event(candidate.id, source: source, kind: .placeBeen,
                    age: Double(Int(candidate.id.dropFirst(4))!))
                }
            })
        XCTAssertEqual(requested, ["row-0", "row-1", "row-2", "row-3", "row-4", "row-5"])
        XCTAssertEqual(rows.map(\.id), ["canonical", "row-4", "row-5"])
    }

    func testHydrationBoundsSortedUniqueCandidatesWithoutContentDedup() async {
        let source = place()
        let candidates = (0..<25).map { event("row-\($0)", source: source, age: Double($0), note: "Same note") }
        let input = Array(candidates.reversed()) + [candidates[0], candidates[1]]
        let selected = LivePlacePreviewPresentation.hydrationCandidates(input, placeID: "selected-place")
        XCTAssertEqual(selected.map(\.id), candidates.prefix(20).map(\.id))
        var requested: [String] = []
        let rows = await LivePlacePreviewPresentation.hydrateRecentActivity(
            input, placeID: "selected-place", isCurrent: { true }, resolve: { candidate in
                requested.append(candidate.id)
                return nil
            })
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(requested, selected.map(\.id))
        XCTAssertEqual(requested.count, LivePlacePreviewPresentation.maximumHydrationCandidates)
    }

    func testNewestCanonicalPlaceRowsIgnoreActorRelationshipAndActivityType() {
        let selected = place()
        selected.place.sourceProviderPlaceID = "shared-venue"
        let alias = place(sourceID: "other-save", placeID: "provider-alias")
        alias.place.sourceProviderPlaceID = "shared-venue"
        let unrelated = place(placeID: "unrelated")
        let identity = LivePlaceIdentity(places: [selected.place])
        let oldFollowed = event("old-followed", source: selected, kind: .placeBeen,
            relationship: .mutual, age: 40, note: "Same note")
        let visit = event("new-visit", source: alias, kind: .placeBeen, actorID: "visitor",
            relationship: .nonFollower, age: 0, note: "Same note")
        let wanna = event("new-wanna", source: selected, kind: .placeWannaGo, actorID: "planner",
            relationship: .nonFollower, age: 1, note: "Same note")
        let list = event("new-list", source: alias, actorID: "curator",
            relationship: .nonFollower, age: 2, note: "Same note")
        let foreign = event("foreign", source: unrelated, age: 0)
        let rows = LivePlacePreviewPresentation.recentActivity(
            [oldFollowed, list, foreign, wanna, visit], placeID: selected.place.id, identity: identity)
        XCTAssertEqual(rows.map(\.id), [visit.id, wanna.id, list.id])
        XCTAssertEqual(rows.map(\.kind), [.placeBeen, .placeWannaGo, .listItemAdded])
    }

    func testHydrationRetainsAuthorizedCanonicalAliasAndRejectsUnrelatedPlace() async {
        let selected = place()
        let persistedID = "A47D41F7-52B4-4875-96A5-507F6793909A"
        selected.place.sourceProviderPlaceID = persistedID
        let alias = place(sourceID: "remote-save", placeID: persistedID.lowercased())
        let unrelated = place(placeID: "unrelated")
        let identity = LivePlaceIdentity(places: [selected.place])
        let candidates = (0..<4).map { event("row-\($0)", source: selected, kind: .placeBeen, age: Double($0)) }
        var requested: [String] = []
        let rows = await LivePlacePreviewPresentation.hydrateRecentActivity(
            candidates, placeID: selected.place.id, identity: identity,
            isCurrent: { true }, resolve: { candidate in
                requested.append(candidate.id)
                return self.event(candidate.id, source: candidate.id == "row-0" ? unrelated : alias,
                    kind: .placeBeen, age: Double(Int(candidate.id.dropFirst(4))!))
            })
        XCTAssertEqual(requested, candidates.map(\.id))
        XCTAssertEqual(rows.map(\.id), ["row-1", "row-2", "row-3"])
    }

    func testPlaceHistoryRefillsFromNextPageAfterRepeatedListEchoes() async throws {
        let source = place()
        let identity = LivePlaceIdentity(places: [source.place])
        let firstPage = (0..<20).map { event("list-\($0)", source: source, age: Double($0), note: "Echo") }
        let secondPage = [
            event("other-visit", source: source, kind: .placeBeen, actorID: "other",
                relationship: .nonFollower, age: 20, note: "Another visit"),
            event("other-wanna", source: source, kind: .placeWannaGo, actorID: "third",
                relationship: .nonFollower, age: 21, note: "Another Wanna")
        ]
        var cursors: [String?] = []
        let rows = try await LivePlacePreviewPresentation.loadRecentActivity(
            placeID: source.place.id, identity: identity, isCurrent: { true }, loadPage: { cursor in
                cursors.append(cursor)
                return FollowedFeedPage(activity: cursor == nil ? firstPage : secondPage,
                    featuredPlaces: [], nextCursor: cursor == nil ? "older" : nil, fetchedAt: .now)
            }, resolve: { $0 })
        XCTAssertEqual(cursors, [nil, "older"])
        XCTAssertEqual(rows.map(\.id), ["list-0", "other-visit", "other-wanna"])
    }

    func testPlaceHistoryStopsAfterThreeNewestAuthorizedDistinctRows() async throws {
        let source = place()
        let input = (0..<20).map { event("visit-\($0)", source: source, kind: .placeBeen, age: Double($0)) }
        var pageReads = 0
        var resolved: [String] = []
        let rows = try await LivePlacePreviewPresentation.loadRecentActivity(
            placeID: source.place.id, identity: LivePlaceIdentity(places: [source.place]),
            isCurrent: { true }, loadPage: { _ in
                pageReads += 1
                return FollowedFeedPage(activity: input, featuredPlaces: [], nextCursor: "older", fetchedAt: .now)
            }, resolve: { candidate in resolved.append(candidate.id); return candidate })
        XCTAssertEqual(pageReads, 1)
        XCTAssertEqual(resolved, ["visit-0", "visit-1", "visit-2"])
        XCTAssertEqual(rows.map(\.id), resolved)
    }

    func testPlaceHistoryDoesNotPublishAfterAccountOrSelectionChangesDuringRead() async throws {
        let source = place()
        var current = true
        var resolutions = 0
        var updates = 0
        let rows = try await LivePlacePreviewPresentation.loadRecentActivity(
            placeID: source.place.id, identity: LivePlaceIdentity(places: [source.place]),
            isCurrent: { current }, loadPage: { _ in
                current = false
                return FollowedFeedPage(activity: [self.event("late", source: source)],
                    featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
            }, resolve: { candidate in resolutions += 1; return candidate }, onUpdate: { _ in updates += 1 })
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(updates, 0)
    }

    func testScopedHistoryAcceptsServerResolvedAliasButNeverRetargetedHydration() async throws {
        let selected = place()
        let serverAlias = place(sourceID: "server-save", placeID: "server-transitive-alias")
        let unrelated = place(placeID: "different-venue")
        let candidates = (0..<5).map {
            event("remote-\($0)", source: serverAlias, kind: .placeBeen, age: Double($0))
        }
        let rows = try await LivePlacePreviewPresentation.loadRecentActivity(
            placeID: selected.place.id, identity: LivePlaceIdentity(places: [selected.place]),
            isCurrent: { true }, loadPage: { _ in
                FollowedFeedPage(activity: candidates, featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
            }, resolve: { candidate in
                if candidate.id == "remote-0" {
                    return self.event(candidate.id, source: unrelated, kind: .placeBeen)
                }
                if candidate.id == "remote-1" {
                    return self.event("another-event", source: serverAlias, kind: .placeBeen)
                }
                return candidate
            })
        XCTAssertEqual(rows.map(\.id), ["remote-2", "remote-3", "remote-4"])
        XCTAssertTrue(rows.allSatisfy { $0.place?.place.id == serverAlias.place.id })
    }

    func testPlaceHistoryReadFailureDoesNotPublishUnverifiedRows() async {
        let source = place()
        var updates = 0
        do {
            _ = try await LivePlacePreviewPresentation.loadRecentActivity(
                placeID: source.place.id, identity: LivePlaceIdentity(places: [source.place]),
                isCurrent: { true }, loadPage: { _ in throw URLError(.notConnectedToInternet) },
                resolve: { $0 }, onUpdate: { _ in updates += 1 })
            XCTFail("A failed scoped read must remain available for explicit retry")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(updates, 0)
    }

    func testPlaceHistoryBoundsPagesAndHydrationWhenRowsAreRejected() async throws {
        let source = place()
        var pages = 0
        var resolutions = 0
        let rows = try await LivePlacePreviewPresentation.loadRecentActivity(
            placeID: source.place.id, identity: LivePlaceIdentity(places: [source.place]),
            isCurrent: { true }, loadPage: { _ in
                pages += 1
                let input = (0..<25).map {
                    self.event("page-\(pages)-row-\($0)", source: source, kind: .placeBeen, age: Double($0))
                }
                return FollowedFeedPage(activity: input, featuredPlaces: [], nextCursor: "page-\(pages)", fetchedAt: .now)
            }, resolve: { _ in resolutions += 1; return nil })
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(pages, LivePlacePreviewPresentation.maximumHistoryPages)
        XCTAssertEqual(resolutions, 60)
    }

    func testHydratedOtherPeopleExpireOfflineWithoutRenewalFromSiblingPublication() async {
        let source = place()
        let older = event("earlier-authorization", source: source, kind: .placeBeen, actorID: "friend")
        let newer = event("later-authorization", source: source, kind: .placeBeen, actorID: "another")
        let own = event("own", source: source, kind: .placeBeen, actorID: "viewer")
        let unverified = event("unverified", source: source, kind: .placeBeen, actorID: "friend")
        let start = ContinuousClock.now
        var lease = LiveFeedDisplayLease()
        lease.accept(activityIDs: [older.id], at: start, replacing: true)
        lease.accept(activityIDs: [newer.id], at: start.advanced(by: .seconds(800)), replacing: false)
        let cachedRows = [older, newer, own, unverified]
        XCTAssertEqual(LivePlacePreviewPresentation.displayableActivity(cachedRows, viewerID: "viewer", lease: lease,
            at: start.advanced(by: .milliseconds(899_999))).map(\.id), [older.id, newer.id, own.id])
        XCTAssertEqual(LivePlacePreviewPresentation.displayableActivity(cachedRows, viewerID: "viewer", lease: lease,
            at: start.advanced(by: .seconds(900))).map(\.id), [newer.id, own.id])
        var resolutions = 0
        var updates = 0
        do {
            try await LivePlacePreviewPresentation.loadRecentActivity(placeID: source.place.id,
                identity: LivePlaceIdentity(places: [source.place]), isCurrent: { true },
                loadPage: { _ in throw URLError(.notConnectedToInternet) },
                resolve: { row in
                    resolutions += 1
                    lease.accept(activityIDs: [row.id], at: start.advanced(by: .seconds(900)), replacing: false)
                    return row
                }, onUpdate: { _ in updates += 1 })
            XCTFail("An offline refresh must not grant new authorization")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(LivePlacePreviewPresentation.displayableActivity(cachedRows, viewerID: "viewer", lease: lease,
            at: start.advanced(by: .seconds(1_700))).map(\.id), [own.id],
            "Repeated cached rendering or device suspension cannot retain other people's rows beyond their receipts.")
    }

    private func recent(_ activities: [FeedActivity]) -> [FeedActivity] {
        LivePlacePreviewPresentation.recentActivity(activities, placeID: "selected-place")
    }

    private func place(sourceID: String = "source", placeID: String = "selected-place") -> VisiblePlace {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let place = LocalPlace(localID: placeID, canonicalName: "Selected place", category: "Coffee",
            latitude: 34, longitude: -118)
        let parent = LocalUserPlace(localID: sourceID, userID: owner.id, placeID: place.id,
            status: .wannaGo, visibility: .followers, sourceType: "manual")
        return VisiblePlace(id: parent.id, place: place, userPlace: parent, owner: owner)
    }

    private func event(_ id: String, source: VisiblePlace, kind: FeedActivityKind = .listItemAdded,
                       actorID: String = "actor", relationship: ViewerRelationship = .follower, age: TimeInterval = 0, note: String? = nil,
                       listID: String? = nil, mediaIDs: [String] = []) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
            actor: ProfileShell(id: actorID, handle: actorID, displayName: actorID,
                avatarURL: nil, bio: nil, relationship: relationship), place: source,
            list: listID.map { LocalPlaceList(localID: $0, ownerUserID: actorID, name: $0, description: "") },
            occurredAt: Date(timeIntervalSince1970: 2_000_000_000 - age), note: note,
            media: mediaIDs.map { FeedMediaPreview(id: $0, accessibilityLabel: "Photo") })
    }
}
