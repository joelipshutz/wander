import UIKit
import XCTest
@testable import Wander

final class ListPlacePhotoTests: XCTestCase {
    @MainActor
    func testResolverUsesPreloadedUserPhotoWithoutMetadataLookup() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "user-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: userPhoto,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
        XCTAssertEqual(repository.metadataCalls, [])
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
    }

    @MainActor
    func testResolverPrefersVisibleUserPhotoOverGoogleMapsPhoto() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "visible-user-photo")
        let googlePhoto = photo(provider: "google_places", id: "google-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .success(googlePhoto),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser])
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
    }

    @MainActor
    func testResolverFallsBackToGoogleMapsWhenNoUserPhotoExists() async throws {
        let googlePhoto = photo(provider: "google_places", id: "google-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .success(googlePhoto),
            imageDataByPhotoID: [googlePhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, googlePhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser, .provider])
        XCTAssertEqual(repository.imageRequests, [googlePhoto.providerPlaceID])
    }

    @MainActor
    func testResolverFallsBackToGoogleMapsWhenUserPhotoCannotRender() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "broken-user-photo")
        let googlePhoto = photo(provider: "google_places", id: "google-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .success(googlePhoto),
            imageDataByPhotoID: [
                userPhoto.providerPlaceID: Data([0x00, 0x01]),
                googlePhoto.providerPlaceID: try imageData()
            ]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, googlePhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser, .provider])
        XCTAssertEqual(
            repository.imageRequests,
            [userPhoto.providerPlaceID, googlePhoto.providerPlaceID]
        )
    }

    @MainActor
    func testPreviewSelectorReturnsAtMostFourDistinctPlacesInListOrder() {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let placeA = place(id: "place-a")
        let placeB = place(id: "place-b")
        let placeC = place(id: "place-c")
        let visiblePlaces = [
            visiblePlace(id: "save-a-1", place: placeA, owner: owner),
            visiblePlace(id: "save-a-2", place: placeA, owner: owner),
            visiblePlace(id: "save-b", place: placeB, owner: owner),
            visiblePlace(id: "save-c", place: placeC, owner: owner),
            visiblePlace(id: "save-a-3", place: placeA, owner: owner)
        ]

        let selected = ListPreviewPlaceSelector.distinctPrefix(visiblePlaces, limit: 4)

        XCTAssertEqual(selected.map(\.place.id), ["place-a", "place-b", "place-c"])
    }

    private var request: PlacePhotoRequest {
        PlacePhotoRequest(
            placeID: "00000000-0000-0000-0000-000000000113",
            name: "RVR",
            address: "Los Angeles, CA",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "google-rvr"
        )
    }

    private func photo(provider: String, id: String) -> PlacePhoto {
        PlacePhoto(
            provider: provider,
            providerPlaceID: id,
            photoURLString: "https://example.com/\(id).jpg",
            width: 400,
            height: 300,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: provider == "google_places" ? "https://maps.google.com/\(id)" : nil,
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
    }

    private func imageData() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try XCTUnwrap(image.pngData())
    }

    @MainActor
    private func place(id: String) -> LocalPlace {
        LocalPlace(
            localID: id,
            canonicalName: id,
            category: "restaurant",
            latitude: 34.05,
            longitude: -118.25
        )
    }

    @MainActor
    private func visiblePlace(
        id: String,
        place: LocalPlace,
        owner: LocalProfile
    ) -> VisiblePlace {
        VisiblePlace(
            id: id,
            place: place,
            userPlace: LocalUserPlace(
                localID: id,
                userID: owner.id,
                placeID: place.id,
                status: .been,
                visibility: .followers,
                sourceType: "test"
            ),
            owner: owner
        )
    }
}

@MainActor
private final class RecordingListPlacePhotoRepository: PlacePhotoRepository {
    enum MetadataCall: Equatable {
        case visibleUser
        case provider
    }

    let visibleUserResult: Result<PlacePhoto, Error>
    let providerResult: Result<PlacePhoto, Error>
    let imageDataByPhotoID: [String: Data]
    private(set) var metadataCalls: [MetadataCall] = []
    private(set) var imageRequests: [String] = []

    init(
        visibleUserResult: Result<PlacePhoto, Error>,
        providerResult: Result<PlacePhoto, Error>,
        imageDataByPhotoID: [String: Data]
    ) {
        self.visibleUserResult = visibleUserResult
        self.providerResult = providerResult
        self.imageDataByPhotoID = imageDataByPhotoID
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataCalls.append(.provider)
        return try providerResult.get()
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataCalls.append(.visibleUser)
        return try visibleUserResult.get()
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        imageRequests.append(photo.providerPlaceID)
        guard let data = imageDataByPhotoID[photo.providerPlaceID] else {
            throw TestError.missing
        }
        return data
    }
}

private enum TestError: Error {
    case missing
}
