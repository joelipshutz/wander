import XCTest
@testable import Wander

@MainActor final class LivePlacePreviewPresentationTests: XCTestCase {
    func testPreviewUsesOnlySelectedPlaceDeduplicatesAndOrdersByRecency() {
        let selectedPlace = place("selected")
        let followed = event("followed", place: selectedPlace, relationship: .follower, age: 300)
        let mutual = event("mutual", place: selectedPlace, relationship: .mutual, age: 200)
        let recent = event("recent", place: selectedPlace, relationship: .nonFollower, age: 0)
        let old = event("old", place: selectedPlace, relationship: .nonFollower, age: 100)
        let unrelated = event("other-place", place: place("other"), relationship: .mutual, age: 0)
        let result = LivePlacePreviewPresentation.recentActivity(
            [recent, old, followed, unrelated, mutual, followed], placeID: "selected"
        )
        XCTAssertEqual(result.map(\.id), ["recent", "old", "mutual"])
    }

    func testEqualTimeActivitiesFollowServerKeysetOrderBeforeTakingThree() {
        let selected = place("selected")
        let rows = ["a", "d", "b", "c"].map {
            event($0, place: selected, relationship: .nonFollower, age: 0)
        }
        XCTAssertEqual(LivePlacePreviewPresentation.recentActivity(rows, placeID: "selected").map(\.id),
                       ["d", "c", "b"])
    }

    func testListActivityKeepsItsIdentityEvenWhenCompanionSaveIsWanna() {
        let activity = event("list", place: place("selected"), relationship: .follower, age: 0,
                             kind: .listItemAdded)
        XCTAssertEqual(LivePlacePreviewPresentation.emoji(for: activity), "📋")
        XCTAssertEqual(LivePlacePreviewPresentation.actionLabel(for: activity), "Added To A List")
        XCTAssertNotEqual(LivePlacePreviewPresentation.highlight(for: activity), "Wanna")
    }

    func testNoteHighlightKeepsActivityNoteWithoutSubstitutingCurrentMutableSave() {
        let selectedPlace = place("selected")
        selectedPlace.userPlace.note = "A later edited save"
        let activity = event("visit", place: selectedPlace, relationship: .mutual, age: 0,
                             kind: .placeBeen, note: "  Original visit\nwith friends  ")
        XCTAssertEqual(LivePlacePreviewPresentation.highlight(for: activity), "Original visit with friends")
    }

    func testProviderHoursAndRatingSurviveImageFallbackWithoutInventingMissingFacts() {
        var details = LivePlacePreviewProviderDetails()
        XCTAssertNil(details.hours)
        XCTAssertNil(details.photo)
        let provider = previewPhoto(provider: "google_places", open: true, rating: 4.7)
        details.receive(provider)
        XCTAssertEqual(details.hours?.statusText, "Open")
        XCTAssertEqual(details.photo?.providerRating, 4.7)

        details.receive(previewPhoto(provider: "visit_photo", open: nil, rating: nil))
        XCTAssertEqual(details.hours?.statusText, "Open", "An image fallback cannot erase provider facts.")
        XCTAssertEqual(details.photo?.providerRating, 4.7)
        details = LivePlacePreviewProviderDetails()
        details.receive(previewPhoto(provider: "visit_photo", open: nil, rating: nil))
        XCTAssertNil(details.hours, "A different place or account starts without inherited facts.")
        XCTAssertNil(details.photo)
    }

    private func previewPhoto(provider: String, open: Bool?, rating: Double?) -> PlacePhoto {
        PlacePhoto(provider: provider, providerPlaceID: "preview-photo", providerRating: rating,
            providerOpenNow: open, photoURLString: "", width: nil, height: nil, authorName: nil,
            authorProfileURLString: nil, authorAvatarURLString: nil, sourcePhotoURLString: nil,
            flagContentURLString: nil, storageBucket: nil, storagePath: nil, localAssetRef: nil)
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
