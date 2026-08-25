import XCTest
@testable import Wander

final class PlacePhotoGalleryTests: XCTestCase {
    func testSharedPreviewSourcesDoNotRenderGooglePhotoWatermarks() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = try [
            "Wander/Features/Feed/FeedScreen.swift",
            "Wander/Features/Lists/ListsScreen.swift",
            "Wander/Features/Profile/ProfileImportViews.swift",
            "Wander/Features/Map/PlaceProfileMapSurface.swift",
            "Wander/Features/Map/PlacePhotoCarouselMockups.swift"
        ].map {
            try String(
                contentsOf: projectRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }

        for source in sources {
            XCTAssertFalse(source.contains("Text(\"Google Maps\")"))
            XCTAssertFalse(source.contains("Text(\"Google\")"))
            XCTAssertFalse(source.contains("Google Maps place photo"))
        }

        let mapSource = sources[3]
        XCTAssertTrue(sources[0].contains("backend.visibleUserPlacePhoto"))
        XCTAssertFalse(sources[0].contains("backend.placePhoto("))
        XCTAssertFalse(sources[2].contains("backend.placePhoto("))
        XCTAssertFalse(mapSource.contains("reloadProviderPhoto"))
        XCTAssertFalse(mapSource.contains("Image(\"BrandGoogleMaps\")"))
    }

    func testSharedPreviewPhotoKindsAllowOnlyUserVisitPhotos() {
        XCTAssertTrue(photo(provider: "visit_photo", id: "user").isUserVisitPhoto)
        XCTAssertFalse(photo(provider: "google_places", id: "provider").isUserVisitPhoto)
    }

    func testProviderPhotosAreExcludedFromPlaceProfileGallery() {
        let providerPhoto = photo(provider: "google_places", id: "provider")
        let providerItem = PlacePhotoGalleryItem(
            photo: providerPhoto,
            contributor: PlacePhotoContributor(
                userID: "provider",
                displayName: "Provider",
                handle: "provider",
                avatarURLString: nil
            ),
            capturedAt: nil,
            status: nil
        )
        let userPhoto = userItem(id: "user-photo", userID: "viewer", handle: "viewer")
        let items = PlacePhotoGalleryPresenter.items(
            userPhotos: [providerItem, userPhoto]
        )

        XCTAssertEqual(items.map(\.id), ["visit_photo|user-photo"])
    }

    func testUserGalleryCanProduceHeaderContent() {
        let userPhoto = userItem(id: "user-photo", userID: "viewer", handle: "viewer")

        let userOnlyItems = PlacePhotoGalleryPresenter.items(
            userPhotos: [userPhoto]
        )

        XCTAssertEqual(userOnlyItems.map(\.id), ["visit_photo|user-photo"])
    }

    func testPresenterPreservesServerRankingAndDeduplicatesUserPhotos() {
        let mine = userItem(id: "mine-1", userID: "viewer", handle: "viewer")
        let followed = userItem(id: "followed-1", userID: "maya", handle: "mayap")
        let popular = userItem(id: "popular-1", userID: "andrew", handle: "andrewc")
        let duplicateFollowed = userItem(id: "followed-1", userID: "maya", handle: "mayap")

        let items = PlacePhotoGalleryPresenter.items(
            userPhotos: [mine, followed, popular, duplicateFollowed]
        )

        XCTAssertEqual(items.map(\.id), [
            "visit_photo|mine-1",
            "visit_photo|followed-1",
            "visit_photo|popular-1"
        ])
    }

    func testPresenterExcludesUnattributedUserFallback() {
        let unattributedFallback = photo(provider: "visit_photo", id: "fallback")

        let items = PlacePhotoGalleryPresenter.items(userPhotos: [
            PlacePhotoGalleryItem(
                photo: unattributedFallback,
                contributor: nil,
                capturedAt: nil,
                status: nil
            )
        ])

        XCTAssertTrue(items.isEmpty)
    }

    func testPresenterExcludesLocallyDeletedUserPhotosFromStaleRemotePage() {
        let deleted = userItem(id: "deleted-photo", userID: "viewer", handle: "viewer")
        let remaining = userItem(id: "remaining-photo", userID: "maya", handle: "mayap")

        let items = PlacePhotoGalleryPresenter.items(
            userPhotos: [deleted, remaining],
            excludingUserPhotoIDs: ["deleted-photo"]
        )

        XCTAssertEqual(items.map(\.photo.providerPlaceID), ["remaining-photo"])
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
