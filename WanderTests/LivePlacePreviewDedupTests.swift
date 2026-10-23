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
                       actorID: String = "actor", age: TimeInterval = 0, note: String? = nil,
                       listID: String? = nil, mediaIDs: [String] = []) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
            actor: ProfileShell(id: actorID, handle: actorID, displayName: actorID,
                avatarURL: nil, bio: nil, relationship: .follower), place: source,
            list: listID.map { LocalPlaceList(localID: $0, ownerUserID: actorID, name: $0, description: "") },
            occurredAt: Date(timeIntervalSince1970: 2_000_000_000 - age), note: note,
            media: mediaIDs.map { FeedMediaPreview(id: $0, accessibilityLabel: "Photo") })
    }
}
