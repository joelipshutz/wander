import XCTest
@testable import Wander

@MainActor final class LivePlacePreviewPresentationTests: XCTestCase {
    func testPreviewUsesOnlySelectedPlaceDeduplicatesAndPrioritizesFollowedPeople() {
        let selectedPlace = place("selected")
        let followed = event("followed", place: selectedPlace, relationship: .follower, age: 300)
        let mutual = event("mutual", place: selectedPlace, relationship: .mutual, age: 200)
        let recent = event("recent", place: selectedPlace, relationship: .nonFollower, age: 0)
        let old = event("old", place: selectedPlace, relationship: .nonFollower, age: 100)
        let unrelated = event("other-place", place: place("other"), relationship: .mutual, age: 0)
        let result = LivePlacePreviewPresentation.recentActivity(
            [recent, old, followed, unrelated, mutual, followed], placeID: "selected"
        )
        XCTAssertEqual(result.map(\.id), ["mutual", "followed", "recent"])
    }

    func testListActivityKeepsItsIdentityEvenWhenCompanionSaveIsWanna() {
        let activity = event("list", place: place("selected"), relationship: .follower, age: 0,
                             kind: .listItemAdded)
        XCTAssertEqual(LivePlacePreviewPresentation.emoji(for: activity), "📋")
        XCTAssertEqual(LivePlacePreviewPresentation.actionLabel(for: activity), "Added to a list")
        XCTAssertNotEqual(LivePlacePreviewPresentation.highlight(for: activity), "Wanna")
    }

    func testNoteHighlightKeepsActivityNoteWithoutSubstitutingCurrentMutableSave() {
        let selectedPlace = place("selected")
        selectedPlace.userPlace.note = "A later edited save"
        let activity = event("visit", place: selectedPlace, relationship: .mutual, age: 0,
                             kind: .placeBeen, note: "  Original visit\nwith friends  ")
        XCTAssertEqual(LivePlacePreviewPresentation.highlight(for: activity), "Original visit with friends")
    }

    private func place(_ id: String) -> VisiblePlace {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let place = LocalPlace(localID: id, canonicalName: id, category: "Coffee", latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "save-\(id)", userID: owner.id, placeID: id,
                                  status: .wannaGo, visibility: .followers, sourceType: "manual")
        return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
    }

    private func event(_ id: String, place: VisiblePlace, relationship: ViewerRelationship,
                       age: TimeInterval, kind: FeedActivityKind = .placeBeen, note: String? = nil) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
                     actor: ProfileShell(id: id, handle: id, displayName: id, avatarURL: nil,
                                         bio: nil, relationship: relationship),
                     place: place, occurredAt: Date(timeIntervalSince1970: 2_000_000_000 - age), note: note)
    }
}
