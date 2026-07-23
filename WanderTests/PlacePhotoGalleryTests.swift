import XCTest
@testable import Wander

final class PlacePhotoGalleryTests: XCTestCase {
    func testPresenterKeepsGoogleFirstAndDeduplicatesUserPhotos() {
        let google = photo(provider: "google_places", id: "google")
        let maya = userItem(id: "maya-1", userID: "maya", handle: "mayap")
        let duplicateMaya = userItem(id: "maya-1", userID: "maya", handle: "mayap")
        let andrew = userItem(id: "andrew-1", userID: "andrew", handle: "andrewc")

        let items = PlacePhotoGalleryPresenter.items(
            providerPhoto: google,
            userPhotos: [maya, duplicateMaya, andrew]
        )

        XCTAssertEqual(items.map(\.id), [
            "google_places|google",
            "visit_photo|maya-1",
            "visit_photo|andrew-1"
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
