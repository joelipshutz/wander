import XCTest
@testable import Wander

@MainActor
final class LivePlaceFullProfilePresentationTests: XCTestCase {
    func testDirectProfileKeepsMatchingCanonicalSavesOnceWithViewerFirst() {
        let mine = row("mine", ownerID: "viewer")
        let selected = row("selected", ownerID: "friend")
        let otherFriend = row("other-friend", ownerID: "another")
        let unrelated = row("unrelated", ownerID: "viewer", providerID: "another-place")
        let removed = row("removed", ownerID: "friend")
        removed.userPlace.deletedAt = .now
        let result = LivePlaceFullProfilePresentation.matchingSaves(selected: selected,
            authorizedPlaces: [otherFriend, selected, mine, selected, unrelated, removed], viewerID: "viewer")
        XCTAssertEqual(result.map(\.id), [mine.id, selected.id, otherFriend.id])
    }

    func testDeletedOwnerCannotAppearInDirectProfileSummary() {
        let selected = row("selected", ownerID: "friend")
        let deleted = row("deleted-owner", ownerID: "removed")
        deleted.owner.deletedAt = .now
        let result = LivePlaceFullProfilePresentation.matchingSaves(selected: selected,
            authorizedPlaces: [deleted, selected], viewerID: "viewer")
        XCTAssertEqual(result.map(\.id), [selected.id])
    }

    func testPrivateForeignSaveAndMismatchedOwnerCannotBorrowSelectedPlaceAccess() {
        let selected = row("selected", ownerID: "friend")
        let privateSave = row("private", ownerID: "friend")
        privateSave.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        let mismatched = row("mismatched", ownerID: "friend")
        mismatched.userPlace.userID = "different-owner"
        let mine = row("mine", ownerID: "viewer")
        mine.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        let result = LivePlaceFullProfilePresentation.matchingSaves(selected: selected,
            authorizedPlaces: [selected, privateSave, mismatched, mine], viewerID: "viewer")
        XCTAssertEqual(result.map(\.id), [mine.id, selected.id])
    }

    private func row(_ id: String, ownerID: String, providerID: String = "shared-cafe") -> VisiblePlace {
        let owner = LocalProfile(localID: "local-\(ownerID)", serverID: ownerID, handle: ownerID, displayName: ownerID)
        let place = LocalPlace(localID: "local-place-\(id)", serverID: "place-\(id)", canonicalName: providerID,
            category: "coffee", address: "\(providerID) street", locality: "Los Angeles", latitude: 34, longitude: -118,
            sourceProvider: "google", sourceProviderPlaceID: providerID)
        let save = LocalUserPlace(localID: "local-save-\(id)", serverID: id, userID: owner.id, placeID: place.id,
            status: .wannaGo, visibility: .followers, sourceType: "test")
        return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
    }
}
