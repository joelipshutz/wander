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
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
        XCTAssertEqual(repository.metadataCalls, [])
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
    }

    @MainActor
    func testResolverUsesLocalFileWithoutRepositoryImageRequest() async throws {
        let localPhotoID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000113")
        )
        let localAssetRef = try XCTUnwrap(
            VisitPhotoLocalFileStore.save(
                data: try imageData(),
                id: localPhotoID,
                contentType: "image/png"
            )
        )
        let userPhoto = photo(
            provider: "visit_photo",
            id: "local-user-photo",
            localAssetRef: localAssetRef
        )
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [:]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: userPhoto,
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
        XCTAssertNotNil(resolved?.image)
        XCTAssertEqual(repository.metadataCalls, [])
        XCTAssertEqual(repository.imageRequests, [])
    }

    @MainActor
    func testResolverFallsBackToRemoteDataWhenLocalFileIsMissing() async throws {
        let userPhoto = photo(
            provider: "visit_photo",
            id: "missing-local-user-photo",
            localAssetRef: "visit-photos/missing-rec113.png"
        )
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: userPhoto,
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
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
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
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
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, googlePhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser, .provider])
        XCTAssertEqual(repository.imageRequests, [googlePhoto.providerPlaceID])
    }

    @MainActor
    func testResolverScopesUserPhotoLookupToEligibleListContributors() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "collaborator-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            eligibleUserIDs: ["user_owner", "user_collaborator"],
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, userPhoto)
        XCTAssertEqual(
            repository.metadataCalls,
            [.scopedVisibleUser(["user_collaborator", "user_owner"])]
        )
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
    }

    @MainActor
    func testResolverSkipsUserPhotoLookupWhenListHasNoEligibleContributors() async throws {
        let googlePhoto = photo(
            provider: "google_places",
            id: "empty-contributors-google-photo"
        )
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .success(googlePhoto),
            imageDataByPhotoID: [googlePhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            eligibleUserIDs: [],
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertEqual(resolved?.photo, googlePhoto)
        XCTAssertEqual(repository.metadataCalls, [.provider])
        XCTAssertEqual(repository.imageRequests, [googlePhoto.providerPlaceID])
    }

    @MainActor
    func testResolverFallsBackToGoogleMapsWhenUserPhotoCannotRender() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "broken-user-photo")
        let googlePhoto = photo(provider: "google_places", id: "fallback-google-photo")
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
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
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
    func testResolverStopsAfterCancellationInsteadOfRequestingProviderFallback() async {
        let googlePhoto = photo(provider: "google_places", id: "google-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(CancellationError()),
            providerResult: .success(googlePhoto),
            imageDataByPhotoID: [:]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser])
        XCTAssertEqual(repository.imageRequests, [])
    }

    @MainActor
    func testResolverReturnsNilAfterTerminalProviderFailure() async {
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [:]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 128,
            backend: backend
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser, .provider])
        XCTAssertEqual(repository.imageRequests, [])
    }

    @MainActor
    func testResolverDownsamplesRemoteImageToRequestedPixelSize() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "large-user-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .failure(TestError.missing),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [
                userPhoto.providerPlaceID: try imageData(
                    size: CGSize(width: 512, height: 384)
                )
            ]
        )
        let backend = WanderBackend(placePhotoRepository: repository)

        let resolved = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: userPhoto,
            authorizationScopeKey: "test-authorization",
            targetPixelSize: 64,
            backend: backend
        )

        let image = try XCTUnwrap(resolved?.image.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 64)
    }

    @MainActor
    func testResolverCoalescesConcurrentVisibleUserMetadataRequests() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "coalesced-user-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()],
            visibleUserDelayNanoseconds: 25_000_000,
            imageDelayNanoseconds: 25_000_000
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let photoRequest = request

        let firstTask = Task { @MainActor in
            await ListPlacePhotoResolver.resolve(
                request: photoRequest,
                preferredUserPhoto: nil,
                authorizationScopeKey: "shared-authorization",
                targetPixelSize: 128,
                backend: backend
            )
        }
        let secondTask = Task { @MainActor in
            await ListPlacePhotoResolver.resolve(
                request: photoRequest,
                preferredUserPhoto: nil,
                authorizationScopeKey: "shared-authorization",
                targetPixelSize: 128,
                backend: backend
            )
        }
        let results = await (firstTask.value, secondTask.value)

        XCTAssertEqual(results.0?.photo, userPhoto)
        XCTAssertEqual(results.1?.photo, userPhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser])
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
    }

    @MainActor
    func testResolverBatchesDifferentVisibleListPlacesIntoOneMetadataRequest() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "batched-user-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let firstRequest = request
        let secondRequest = PlacePhotoRequest(
            placeID: "00000000-0000-0000-0000-000000000114",
            name: "Maru Coffee",
            address: "Los Angeles, CA",
            latitude: 34.06,
            longitude: -118.24,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "google-maru"
        )

        let firstTask = Task { @MainActor in
            await ListPlacePhotoResolver.resolve(
                request: firstRequest,
                preferredUserPhoto: nil,
                authorizationScopeKey: "two-place-batch",
                targetPixelSize: 128,
                backend: backend
            )
        }
        let secondTask = Task { @MainActor in
            await ListPlacePhotoResolver.resolve(
                request: secondRequest,
                preferredUserPhoto: nil,
                authorizationScopeKey: "two-place-batch",
                targetPixelSize: 128,
                backend: backend
            )
        }
        let results = await (firstTask.value, secondTask.value)

        XCTAssertEqual(results.0?.photo, userPhoto)
        XCTAssertEqual(results.1?.photo, userPhoto)
        XCTAssertEqual(repository.visibleUserBatchRequests.count, 1)
        XCTAssertEqual(
            Set(repository.visibleUserBatchRequests[0].map(\.canonicalPhotoCacheKey)),
            Set([firstRequest, secondRequest].map(\.canonicalPhotoCacheKey))
        )
        XCTAssertTrue(repository.providerBatchRequests.isEmpty)
    }

    @MainActor
    func testResolverRevisitUsesBoundedSelectionAndDecodedCachesWithoutReloading() async throws {
        let userPhoto = photo(provider: "visit_photo", id: "revisited-user-photo")
        let repository = RecordingListPlacePhotoRepository(
            visibleUserResult: .success(userPhoto),
            providerResult: .failure(TestError.missing),
            imageDataByPhotoID: [userPhoto.providerPlaceID: try imageData()]
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let selectionCache = ListPlacePhotoSelectionCache(countLimit: 4)

        let first = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            authorizationScopeKey: "revisit-authorization",
            targetPixelSize: 128,
            backend: backend,
            selectionCache: selectionCache
        )
        let second = await ListPlacePhotoResolver.resolve(
            request: request,
            preferredUserPhoto: nil,
            authorizationScopeKey: "revisit-authorization",
            targetPixelSize: 128,
            backend: backend,
            selectionCache: selectionCache
        )

        XCTAssertEqual(first?.photo, userPhoto)
        XCTAssertEqual(second?.photo, userPhoto)
        XCTAssertEqual(repository.metadataCalls, [.visibleUser])
        XCTAssertEqual(repository.imageRequests, [userPhoto.providerPlaceID])
        XCTAssertEqual(selectionCache.entryCount, 1)
    }

    @MainActor
    func testImagePipelineScopesSamePhotoIdentityToCanonicalPlace() async throws {
        let pipeline = PlacePhotoImagePipeline(countLimit: 4, totalCostLimit: 1_024 * 1_024)
        let data = try imageData()

        let first = await pipeline.image(
            from: data,
            canonicalPlaceKey: "place:first",
            photoKey: "shared-photo-key",
            targetPixelSize: 128
        )
        let wrongPlaceLookup = pipeline.cachedImage(
            canonicalPlaceKey: "place:second",
            photoKey: "shared-photo-key",
            targetPixelSize: 128
        )
        let second = await pipeline.image(
            from: data,
            canonicalPlaceKey: "place:second",
            photoKey: "shared-photo-key",
            targetPixelSize: 128
        )

        XCTAssertNotNil(first)
        XCTAssertNil(wrongPlaceLookup)
        XCTAssertNotNil(second)
        XCTAssertEqual(pipeline.cacheMetrics().entryCount, 2)
    }

    @MainActor
    func testSelectionCacheEvictsLeastRecentlyUsedPhoto() {
        let cache = ListPlacePhotoSelectionCache(countLimit: 2)
        let scopeID = UUID()
        let firstKey = selectionCacheKey("first", scopeID: scopeID)
        let secondKey = selectionCacheKey("second", scopeID: scopeID)
        let thirdKey = selectionCacheKey("third", scopeID: scopeID)
        let firstPhoto = photo(provider: "visit_photo", id: "first-photo")
        let secondPhoto = photo(provider: "visit_photo", id: "second-photo")
        let thirdPhoto = photo(provider: "visit_photo", id: "third-photo")

        cache.insert(firstPhoto, for: firstKey)
        cache.insert(secondPhoto, for: secondKey)
        XCTAssertEqual(cache.photo(for: firstKey), firstPhoto)
        cache.insert(thirdPhoto, for: thirdKey)

        XCTAssertEqual(cache.photo(for: firstKey), firstPhoto)
        XCTAssertNil(cache.photo(for: secondKey))
        XCTAssertEqual(cache.photo(for: thirdKey), thirdPhoto)
        XCTAssertEqual(cache.entryCount, 2)
    }

    @MainActor
    func testDecodedImageCacheEvictsLeastRecentlyUsedImage() async throws {
        let pipeline = PlacePhotoImagePipeline(
            countLimit: 2,
            totalCostLimit: 1_024 * 1_024
        )
        let data = try imageData()

        for key in ["first", "second"] {
            let decoded = await pipeline.image(
                from: data,
                canonicalPlaceKey: "place:\(key)",
                photoKey: "photo:\(key)",
                targetPixelSize: 128
            )
            XCTAssertNotNil(decoded)
        }
        XCTAssertNotNil(
            pipeline.cachedImage(
                canonicalPlaceKey: "place:first",
                photoKey: "photo:first",
                targetPixelSize: 128
            )
        )
        let third = await pipeline.image(
            from: data,
            canonicalPlaceKey: "place:third",
            photoKey: "photo:third",
            targetPixelSize: 128
        )
        XCTAssertNotNil(third)

        XCTAssertNotNil(
            pipeline.cachedImage(
                canonicalPlaceKey: "place:first",
                photoKey: "photo:first",
                targetPixelSize: 128
            )
        )
        XCTAssertNil(
            pipeline.cachedImage(
                canonicalPlaceKey: "place:second",
                photoKey: "photo:second",
                targetPixelSize: 128
            )
        )
        XCTAssertNotNil(
            pipeline.cachedImage(
                canonicalPlaceKey: "place:third",
                photoKey: "photo:third",
                targetPixelSize: 128
            )
        )
    }

    func testProjectionCacheBuildsOncePerStableRevisionKey() {
        let cache = ListsProjectionCache<String, Int>()

        XCTAssertEqual(cache.value(for: "revision-1") { 10 }, 10)
        XCTAssertEqual(cache.value(for: "revision-1") { 20 }, 10)
        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(cache.value(for: "revision-2") { 30 }, 30)
        XCTAssertEqual(cache.buildCount, 2)
    }

    @MainActor
    func testPreviewSelectorReturnsAtMostFourDistinctPlacesInListOrder() {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let placeA = place(id: "place-a")
        let placeB = place(id: "place-b")
        let placeC = place(id: "place-c")
        let placeD = place(id: "place-d")
        let placeE = place(id: "place-e")
        let visiblePlaces = [
            visiblePlace(id: "save-a-1", place: placeA, owner: owner),
            visiblePlace(id: "save-a-2", place: placeA, owner: owner),
            visiblePlace(id: "save-b", place: placeB, owner: owner),
            visiblePlace(id: "save-c", place: placeC, owner: owner),
            visiblePlace(id: "save-d", place: placeD, owner: owner),
            visiblePlace(id: "save-e", place: placeE, owner: owner)
        ]

        let selected = ListPreviewPlaceSelector.distinctPrefix(visiblePlaces, limit: 4)

        XCTAssertEqual(selected.map(\.place.id), ["place-a", "place-b", "place-c", "place-d"])
    }

    @MainActor
    func testPreviewSelectorReturnsEmptyForNonPositiveLimit() {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let visiblePlaces = [
            visiblePlace(id: "save-a", place: place(id: "place-a"), owner: owner)
        ]

        XCTAssertTrue(ListPreviewPlaceSelector.distinctPrefix(visiblePlaces, limit: 0).isEmpty)
        XCTAssertTrue(ListPreviewPlaceSelector.distinctPrefix(visiblePlaces, limit: -1).isEmpty)
    }

    @MainActor
    func testLocalVisitPhotoMappingPreservesEveryImageSource() {
        let localPhoto = LocalVisitPhoto(
            localID: "local-photo",
            serverID: "server-photo",
            visitID: "visit",
            storageBucket: "visit-photos",
            storagePath: "user/visit/photo.jpg",
            localAssetRef: "visit-photos/local-photo.jpg",
            remoteURLString: "https://example.com/photo.jpg",
            width: 640,
            height: 480
        )

        let mapped = PlacePhoto(localVisitPhoto: localPhoto)

        XCTAssertEqual(mapped.providerPlaceID, "server-photo")
        XCTAssertEqual(mapped.photoURLString, "https://example.com/photo.jpg")
        XCTAssertEqual(mapped.storageBucket, "visit-photos")
        XCTAssertEqual(mapped.storagePath, "user/visit/photo.jpg")
        XCTAssertEqual(mapped.localAssetRef, "visit-photos/local-photo.jpg")
        XCTAssertEqual(mapped.width, 640)
        XCTAssertEqual(mapped.height, 480)
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

    private func photo(
        provider: String,
        id: String,
        localAssetRef: String? = nil
    ) -> PlacePhoto {
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
            localAssetRef: localAssetRef
        )
    }

    private func imageData(size: CGSize = CGSize(width: 2, height: 2)) throws -> Data {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func selectionCacheKey(
        _ placeKey: String,
        scopeID: UUID
    ) -> ListPlacePhotoSelectionCache.Key {
        ListPlacePhotoSelectionCache.Key(
            backendScopeID: scopeID,
            canonicalPlaceKey: placeKey,
            preferredPhotoKey: "none",
            eligibleUserIDs: nil,
            authorizationScopeKey: "authorization"
        )
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
        case scopedVisibleUser([String])
        case provider
    }

    let visibleUserResult: Result<PlacePhoto, Error>
    let providerResult: Result<PlacePhoto, Error>
    let imageDataByPhotoID: [String: Data]
    let visibleUserDelayNanoseconds: UInt64
    let imageDelayNanoseconds: UInt64
    private(set) var metadataCalls: [MetadataCall] = []
    private(set) var imageRequests: [String] = []
    private(set) var providerBatchRequests: [[PlacePhotoRequest]] = []
    private(set) var visibleUserBatchRequests: [[PlacePhotoRequest]] = []

    init(
        visibleUserResult: Result<PlacePhoto, Error>,
        providerResult: Result<PlacePhoto, Error>,
        imageDataByPhotoID: [String: Data],
        visibleUserDelayNanoseconds: UInt64 = 0,
        imageDelayNanoseconds: UInt64 = 0
    ) {
        self.visibleUserResult = visibleUserResult
        self.providerResult = providerResult
        self.imageDataByPhotoID = imageDataByPhotoID
        self.visibleUserDelayNanoseconds = visibleUserDelayNanoseconds
        self.imageDelayNanoseconds = imageDelayNanoseconds
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataCalls.append(.provider)
        return try providerResult.get()
    }

    func photos(for requests: [PlacePhotoRequest]) async throws -> [PlacePhotoBatchResult] {
        providerBatchRequests.append(requests)
        var results: [PlacePhotoBatchResult] = []
        for request in requests {
            do {
                let photo = try await photo(for: request)
                results.append(
                    PlacePhotoBatchResult(
                        canonicalPlaceKey: request.canonicalPhotoCacheKey,
                        photo: photo
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return results
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        if let userIDs = request.eligibleUserIDs {
            metadataCalls.append(.scopedVisibleUser(userIDs))
        } else {
            metadataCalls.append(.visibleUser)
        }
        if visibleUserDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: visibleUserDelayNanoseconds)
        }
        return try visibleUserResult.get()
    }

    func visibleUserPhotos(
        for requests: [PlacePhotoRequest]
    ) async throws -> [PlacePhotoBatchResult] {
        visibleUserBatchRequests.append(requests)
        var results: [PlacePhotoBatchResult] = []
        for request in requests {
            do {
                let photo = try await visibleUserPhoto(for: request)
                results.append(
                    PlacePhotoBatchResult(
                        canonicalPlaceKey: request.canonicalPhotoCacheKey,
                        photo: photo
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return results
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        imageRequests.append(photo.providerPlaceID)
        if imageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: imageDelayNanoseconds)
        }
        guard let data = imageDataByPhotoID[photo.providerPlaceID] else {
            throw TestError.missing
        }
        return data
    }
}

private enum TestError: Error {
    case missing
}
