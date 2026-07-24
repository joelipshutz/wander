import XCTest
@testable import Wander

final class PlacePhotoGalleryTests: XCTestCase {
    func testPresenterKeepsGoogleFirstPreservesServerRankingAndDeduplicatesUserPhotos() {
        let google = photo(provider: "google_places", id: "google")
        let mine = userItem(id: "mine-1", userID: "viewer", handle: "viewer")
        let followed = userItem(id: "followed-1", userID: "maya", handle: "mayap")
        let popular = userItem(id: "popular-1", userID: "andrew", handle: "andrewc")
        let duplicateFollowed = userItem(id: "followed-1", userID: "maya", handle: "mayap")

        let items = PlacePhotoGalleryPresenter.items(
            providerPhoto: google,
            userPhotos: [mine, followed, popular, duplicateFollowed]
        )

        XCTAssertEqual(items.map(\.id), [
            "google_places|google",
            "visit_photo|mine-1",
            "visit_photo|followed-1",
            "visit_photo|popular-1"
        ])
        XCTAssertTrue(items[0].isGooglePlacesPhoto)
    }

    func testPresenterDoesNotPromoteUnattributedUserFallbackToGoogleSlot() {
        let unattributedFallback = photo(provider: "visit_photo", id: "fallback")

        let items = PlacePhotoGalleryPresenter.items(
            providerPhoto: unattributedFallback,
            userPhotos: []
        )

        XCTAssertTrue(items.isEmpty)
    }

    func testPresenterMergesPagesWithoutRepeatingRows() {
        let first = userItem(id: "one", userID: "maya", handle: "mayap")
        let duplicate = userItem(id: "one", userID: "maya", handle: "mayap")
        let second = userItem(id: "two", userID: "andrew", handle: "andrewc")

        let merged = PlacePhotoGalleryPresenter.merging(
            existing: [first],
            incoming: [duplicate, second]
        )

        XCTAssertEqual(merged.map(\.photo.providerPlaceID), ["one", "two"])
    }

    func testPresenterLoadsMoreNearEndOfLargeGallery() {
        let items = (0..<100).map {
            userItem(id: "photo-\($0)", userID: "maya", handle: "mayap")
        }

        XCTAssertFalse(
            PlacePhotoGalleryPresenter.shouldLoadMore(
                visibleItemID: items[50].id,
                items: items
            )
        )
        XCTAssertTrue(
            PlacePhotoGalleryPresenter.shouldLoadMore(
                visibleItemID: items[94].id,
                items: items
            )
        )
        XCTAssertEqual(
            PlacePhotoGalleryPresenter.positionLabel(
                selectedID: items[99].id,
                items: items
            ),
            "100 of 100"
        )
    }

    private func userItem(
        id: String,
        userID: String,
        handle: String
    ) -> PlacePhotoGalleryItem {
        PlacePhotoGalleryItem(
            photo: photo(provider: "visit_photo", id: id),
            contributor: PlacePhotoContributor(
                userID: userID,
                displayName: handle.capitalized,
                handle: handle,
                avatarURLString: nil
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .been
        )
    }

    private func photo(provider: String, id: String) -> PlacePhoto {
        PlacePhoto(
            provider: provider,
            providerPlaceID: id,
            photoURLString: "https://example.com/\(id).jpg",
            width: 1200,
            height: 900,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: provider == "visit_photo" ? "visit-photos" : nil,
            storagePath: provider == "visit_photo" ? "owner/visit/\(id).jpg" : nil,
            localAssetRef: nil
        )
    }
}
