import Foundation
import XCTest
@testable import Wander

final class PlacePhotoDeliveryTests: XCTestCase {
    func testRenderVariantsKeepEverySurfaceCrispWithoutUpsizingFullscreen() {
        XCTAssertEqual(PlacePhotoRenderVariant.listThumbnail.maximumPixelDimension, 512)
        XCTAssertEqual(PlacePhotoRenderVariant.listThumbnail.deliveryQuality, 84)

        XCTAssertEqual(PlacePhotoRenderVariant.feed.maximumPixelDimension, 1_440)
        XCTAssertEqual(PlacePhotoRenderVariant.feed.deliveryQuality, 90)
        XCTAssertEqual(PlacePhotoRenderVariant.card.maximumPixelDimension, 1_440)
        XCTAssertEqual(PlacePhotoRenderVariant.card.deliveryQuality, 90)

        XCTAssertEqual(PlacePhotoRenderVariant.profile.maximumPixelDimension, 1_800)
        XCTAssertEqual(PlacePhotoRenderVariant.profile.deliveryQuality, 92)

        XCTAssertNil(PlacePhotoRenderVariant.fullscreen.maximumPixelDimension)
        XCTAssertEqual(PlacePhotoRenderVariant.fullscreen.deliveryQuality, 96)
        XCTAssertEqual(PlacePhotoRenderVariant.fullscreen.minimumDecodePixelDimension, 3_200)
    }

    func testRequestVariantChangesDeliveryLookupButNotCanonicalPlaceIdentity() {
        let request = photoRequest
        let listRequest = request.rendering(.listThumbnail)
        let fullscreenRequest = request.rendering(.fullscreen)

        XCTAssertNotEqual(listRequest.lookupKey, fullscreenRequest.lookupKey)
        XCTAssertTrue(listRequest.lookupKey.hasSuffix("variant:list_thumbnail"))
        XCTAssertTrue(fullscreenRequest.lookupKey.hasSuffix("variant:fullscreen"))
        XCTAssertEqual(listRequest.canonicalPhotoCacheKey, fullscreenRequest.canonicalPhotoCacheKey)
    }

    func testMetadataOnlyLookupRemainsIndependentOfRenderVariant() {
        let metadataRequest = PlacePhotoRequest(
            placeID: photoRequest.placeID,
            name: photoRequest.name,
            address: photoRequest.address,
            latitude: photoRequest.latitude,
            longitude: photoRequest.longitude,
            sourceProvider: photoRequest.sourceProvider,
            sourceProviderPlaceID: photoRequest.sourceProviderPlaceID,
            requiresPhoto: false
        )

        XCTAssertEqual(
            metadataRequest.rendering(.listThumbnail).lookupKey,
            metadataRequest.rendering(.fullscreen).lookupKey
        )
        XCTAssertTrue(metadataRequest.lookupKey.hasSuffix("metadata-only"))
    }

    func testPhotoCacheIdentityIgnoresShortLivedSignedURLChurn() {
        let first = photo(url: "https://example.supabase.co/object/sign/a.jpg?token=first")
        let refreshed = photo(url: "https://example.supabase.co/object/sign/a.jpg?token=second")

        XCTAssertEqual(first.cacheKey, refreshed.cacheKey)
    }

    func testDiskCacheSeparatesCanonicalPlaceAndRenderVariant() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PlacePhotoDataDiskCache(directoryURL: directory)
        let listData = Data([0x01, 0x02])
        let fullscreenData = Data([0x03, 0x04, 0x05])

        await cache.insert(
            listData,
            canonicalPlaceKey: "place:first",
            photoKey: "photo:shared",
            variant: .listThumbnail
        )
        await cache.insert(
            fullscreenData,
            canonicalPlaceKey: "place:first",
            photoKey: "photo:shared",
            variant: .fullscreen
        )

        let listHit = await cache.data(
            canonicalPlaceKey: "place:first",
            photoKey: "photo:shared",
            variant: .listThumbnail
        )
        let fullscreenHit = await cache.data(
            canonicalPlaceKey: "place:first",
            photoKey: "photo:shared",
            variant: .fullscreen
        )
        let otherPlaceMiss = await cache.data(
            canonicalPlaceKey: "place:second",
            photoKey: "photo:shared",
            variant: .listThumbnail
        )

        XCTAssertEqual(listHit, listData)
        XCTAssertEqual(fullscreenHit, fullscreenData)
        XCTAssertNil(otherPlaceMiss)
    }

    func testDiskCacheSurvivesASecondCacheInstance() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data(repeating: 0xAB, count: 128)

        let firstCache = PlacePhotoDataDiskCache(directoryURL: directory)
        await firstCache.insert(
            data,
            canonicalPlaceKey: "place:persistent",
            photoKey: "photo:persistent",
            variant: .profile
        )
        let relaunchedCache = PlacePhotoDataDiskCache(directoryURL: directory)

        let restored = await relaunchedCache.data(
            canonicalPlaceKey: "place:persistent",
            photoKey: "photo:persistent",
            variant: .profile
        )
        let metrics = await relaunchedCache.metrics()

        XCTAssertEqual(restored, data)
        XCTAssertEqual(metrics.diskHits, 1)
        XCTAssertEqual(metrics.networkLoads, 0)
        XCTAssertEqual(metrics.entryCount, 1)
    }

    func testRevocationSurvivesImageCacheClearAndRejectsLateAuthorization() async {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PlacePhotoDataDiskCache(directoryURL: directory)
        let revision = await cache.revocationRevision("protected:viewer:photo")
        await cache.recordRevocation("protected:viewer:photo")
        let staleAuthorization = await cache.clearRevocation("protected:viewer:photo", ifRevision: revision)
        XCTAssertFalse(staleAuthorization)
        await cache.removeAll()
        let restarted = PlacePhotoDataDiskCache(directoryURL: directory)
        let stillDenied = await restarted.hasRevocation("protected:viewer:photo")
        XCTAssertTrue(stillDenied, "Evicting image bytes must not erase access revocation")
    }

    func testPendingSharedCopiesCannotUseTheOwnerCaptureOfflineException() throws {
        let copy = LocalVisitPhoto(localID: "copy", visitID: "visit", sourcePhotoID: "source",
            localAssetRef: "local-file", uploadState: .pendingUpload)
        XCTAssertTrue(PlacePhoto(localVisitPhoto: copy).requiresAccessCheck)
        let record = WanderStoreSnapshot.VisitPhotoRecord(copy)
        let restored = try JSONDecoder().decode(WanderStoreSnapshot.VisitPhotoRecord.self,
            from: JSONEncoder().encode(record)).model()
        XCTAssertEqual(restored.sourcePhotoID, "source")
        XCTAssertTrue(PlacePhoto(localVisitPhoto: restored).requiresAccessCheck)
        let legacyCopy = LocalVisitPhoto(localID: "local_photo_shared_fixture", visitID: "visit",
            localAssetRef: "local-file", uploadState: .failed)
        XCTAssertTrue(PlacePhoto(localVisitPhoto: legacyCopy).requiresAccessCheck)
        let ownCapture = LocalVisitPhoto(localID: "capture", visitID: "visit",
            localAssetRef: "local-file", uploadState: .pendingUpload)
        XCTAssertFalse(PlacePhoto(localVisitPhoto: ownCapture).requiresAccessCheck)
    }

    func testDiskCachePrunesToBothEntryAndByteBounds() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PlacePhotoDataDiskCache(
            directoryURL: directory,
            countLimit: 2,
            totalCostLimit: 9
        )

        for index in 0..<4 {
            await cache.insert(
                Data(repeating: UInt8(index), count: 4),
                canonicalPlaceKey: "place:\(index)",
                photoKey: "photo:\(index)",
                variant: .feed
            )
        }

        let metrics = await cache.metrics()
        XCTAssertLessThanOrEqual(metrics.entryCount, 2)
        XCTAssertLessThanOrEqual(metrics.totalByteCost, 9)
    }

    func testPerformanceMonitorAggregatesSamplesWithoutRetainingEveryTiming() async {
        let monitor = PlacePhotoPerformanceMonitor()
        await monitor.reset()

        for _ in 0..<100 {
            await monitor.record(.decode, startedAt: .now)
        }

        let metrics = await monitor.snapshot()[.decode]
        XCTAssertEqual(metrics?.sampleCount, 100)
        XCTAssertGreaterThanOrEqual(metrics?.totalMilliseconds ?? -1, 0)
        XCTAssertGreaterThanOrEqual(metrics?.maximumMilliseconds ?? -1, 0)
    }

    func testOfflineFallbackDoesNotIncludeTimeoutsAuthenticationOrServerErrors() {
        XCTAssertTrue(ProtectedContentCachePolicy.permitsOfflineRead(after: URLError(.notConnectedToInternet)))
        XCTAssertTrue(ProtectedContentCachePolicy.permitsOfflineRead(after: URLError(.networkConnectionLost)))
        XCTAssertFalse(ProtectedContentCachePolicy.permitsOfflineRead(after: URLError(.timedOut)))
        XCTAssertFalse(ProtectedContentCachePolicy.permitsOfflineRead(after: WanderRemoteError.notAuthenticated))
        XCTAssertFalse(ProtectedContentCachePolicy.permitsOfflineRead(after: WanderRemoteError.invalidResponse("denied")))
    }

    @MainActor
    func testProtectedMemoryAndDiskReadsRecheckAccessAndDenialCannotReappearOffline() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PrivacyPhotoRepository()
        let session = PrivacyPhotoSession()
        let cache = PlacePhotoDataDiskCache(directoryURL: directory)
        let backend = WanderBackend(placePhotoRepository: repository, photoAuthSession: session, placePhotoDataDiskCache: cache)
        let protectedPhoto = photo(url: "https://unused.invalid/old-signed-link")
        let initial = try await backend.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
        XCTAssertEqual(initial, Data([1, 2, 3]))
        repository.accessError = URLError(.notConnectedToInternet)
        let offline = try await backend.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "another-surface")
        XCTAssertEqual(offline, initial)
        XCTAssertEqual(repository.downloads, 1)
        repository.accessError = WanderRemoteError.invalidResponse("photo_not_visible")
        do {
            _ = try await backend.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
            XCTFail("A cached image must not bypass denial")
        } catch {}
        repository.accessError = URLError(.notConnectedToInternet)
        // Recreate the backend to prove disk bytes were removed too.
        let restarted = WanderBackend(placePhotoRepository: repository, photoAuthSession: session, placePhotoDataDiskCache: cache)
        do {
            _ = try await restarted.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
            XCTFail("Revoked bytes must not return after restart offline")
        } catch {}
        XCTAssertEqual(repository.downloads, 1)
        XCTAssertEqual(repository.checks, 4)
    }

    @MainActor
    func testProtectedOfflineCacheIsAccountScopedAndSurvivesSameAccountRestart() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PrivacyPhotoRepository()
        let session = PrivacyPhotoSession()
        let cache = PlacePhotoDataDiskCache(directoryURL: directory)
        let backend = WanderBackend(placePhotoRepository: repository, photoAuthSession: session, placePhotoDataDiskCache: cache)
        let protectedPhoto = photo(url: "")
        _ = try await backend.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
        repository.accessError = URLError(.notConnectedToInternet)
        let restarted = WanderBackend(placePhotoRepository: repository, photoAuthSession: session, placePhotoDataDiskCache: cache)
        let restored = try await restarted.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
        XCTAssertEqual(restored, Data([1, 2, 3]))
        session.state = .signedIn(AuthSession(userID: "second", displayName: nil, handle: nil))
        do {
            _ = try await restarted.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
            XCTFail("Another account cannot inherit offline bytes")
        } catch {}
        session.state = .signedOut
        do {
            _ = try await restarted.placePhotoImageData(for: protectedPhoto, canonicalPlaceKey: "place")
            XCTFail("Signed-out users cannot inherit offline bytes")
        } catch {}
    }

    private var photoRequest: PlacePhotoRequest {
        PlacePhotoRequest(
            placeID: "50000000-0000-0000-0000-000000000322",
            name: "Crisp Coffee",
            address: "Los Angeles, CA",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "google-crisp-coffee"
        )
    }

    private func photo(url: String) -> PlacePhoto {
        PlacePhoto(
            provider: "visit_photo",
            providerPlaceID: "55000000-0000-0000-0000-000000000322",
            photoURLString: url,
            width: 4_032,
            height: 3_024,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: "visit-photos",
            storagePath: "user/visit/photo.jpg",
            localAssetRef: nil
        )
    }

    private func temporaryCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "recme-photo-cache-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

@MainActor
private final class PrivacyPhotoRepository: PlacePhotoRepository {
    var accessError: Error?
    var checks = 0
    var downloads = 0
    func validateAccess(to photo: PlacePhoto) async throws {
        checks += 1
        if let accessError { throw accessError }
    }
    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto { throw WanderRemoteError.notConfigured }
    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto { throw WanderRemoteError.notConfigured }
    func imageData(for photo: PlacePhoto) async throws -> Data {
        downloads += 1
        return Data([1, 2, 3])
    }
}

@MainActor
private final class PrivacyPhotoSession: AuthSessionProviding {
    var state: AuthState = .signedIn(AuthSession(userID: "first", displayName: nil, handle: nil))
    let canPresentNativeAuth = false
    func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func refreshSession() async {}
    func signOut() async throws { state = .signedOut }
    func deleteAccount() async throws { state = .signedOut }
    func supabaseAccessToken() async throws -> String { "test" }
    func refreshSupabaseAccessToken() async throws -> String { "test" }
}


@MainActor
final class PlacePhotoManifestTests: XCTestCase {
    func testExpiredManifestRefetchesProviderHours() async throws {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let repository = ManifestTestPhotoRepository()
        let backend = WanderBackend(placePhotoRepository: repository, photoMetadataNow: { now })
        let request = manifestRequest("freshness").metadataOnly()
        let first = try await backend.placePhoto(for: request)
        XCTAssertEqual(first.providerOpenNow, true)
        now.addTimeInterval(299)
        _ = try await backend.placePhoto(for: request)
        XCTAssertEqual(repository.requestCount, 1)
        now.addTimeInterval(1)
        XCTAssertNil(backend.cachedPlacePhoto(for: request))
        repository.openNow = false
        let refreshed = try await backend.placePhoto(for: request)
        XCTAssertEqual(refreshed.providerOpenNow, false)
        XCTAssertEqual(repository.requestCount, 2)
        XCTAssertFalse(PlacePhotoManifestCachePolicy.isFresh(cachedAt: now, now: now.addingTimeInterval(-1)))
    }

    func testHoursLoadWithoutAnyAvailableImage() async throws {
        let repository = ManifestTestPhotoRepository()
        repository.photoMissing = true
        let backend = WanderBackend(placePhotoRepository: repository)
        let request = manifestRequest("no-photo")
        do {
            _ = try await backend.placePhoto(for: request)
            XCTFail("The missing image must remain unavailable")
        } catch {}
        let metadata = try await backend.placePhoto(for: request.metadataOnly())
        var details = LivePlacePreviewProviderDetails()
        details.receive(metadata)
        XCTAssertEqual(details.hours?.statusText, "Open")
        XCTAssertTrue(metadata.photoURLString.isEmpty)
    }

    func testLatePreviousAccountMetadataCannotBePublishedOrCached() async throws {
        let session = PrivacyPhotoSession(), gate = PhotoManifestTestGate()
        let repository = ManifestTestPhotoRepository()
        repository.gate = gate
        let backend = WanderBackend(placePhotoRepository: repository, photoAuthSession: session)
        let request = manifestRequest("account-change")
        let task = Task { @MainActor in try await backend.placePhoto(for: request) }
        await gate.waitUntilStarted()
        session.state = .signedIn(AuthSession(userID: "second", displayName: nil, handle: nil))
        gate.release()
        do { _ = try await task.value; XCTFail("Old account result must be rejected") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertNil(backend.cachedPlacePhoto(for: request))
        repository.gate = nil
        _ = try await backend.placePhoto(for: request)
        XCTAssertEqual(repository.requestCount, 2)
    }

    func testLatePreviousAccountBatchCannotBePublishedOrCached() async throws {
        let session = PrivacyPhotoSession(), gate = PhotoManifestTestGate()
        let repository = ManifestTestPhotoRepository()
        repository.gate = gate
        let backend = WanderBackend(placePhotoRepository: repository, photoAuthSession: session)
        let request = manifestRequest("batch-account-change")
        let task = Task { @MainActor in try await backend.placePhotos(for: [request]) }
        await gate.waitUntilStarted()
        session.state = .signedIn(AuthSession(userID: "second", displayName: nil, handle: nil))
        gate.release()
        do { _ = try await task.value; XCTFail("Old account batch must be rejected") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertNil(backend.cachedPlacePhoto(for: request))
    }

    func testLiveDefaultPublishesReadyPinWhileSlowSiblingWaitsAndRejectsCancelledSubscriber() async {
        let gate = PhotoManifestTestGate(), repository = ManifestTestPhotoRepository()
        repository.gate = gate
        repository.heldName = "slow"
        let backend = WanderBackend(placePhotoRepository: repository)
        let slow = Task { @MainActor in
            await LivePinPhotoResolver.resolve(request: self.manifestRequest("slow"),
                authorizationScopeKey: "viewer", backend: backend, retryDelayNanoseconds: 0)
        }
        var readyFinished = false
        let ready = Task { @MainActor in
            let photo = await LivePinPhotoResolver.resolve(request: self.manifestRequest("ready"),
                authorizationScopeKey: "viewer", backend: backend, retryDelayNanoseconds: 0)
            readyFinished = true
            return photo
        }
        await gate.waitUntilStarted()
        // Both requests enter the production debounce together. Give ready work
        // a bounded window, then release the gate even if independence regresses.
        for _ in 0..<100 {
            if readyFinished { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(readyFinished, "Ready pins must publish before the held pin resumes")
        XCTAssertLessThanOrEqual(repository.maximumActiveBatches, 6)
        XCTAssertTrue(repository.batchSizes.allSatisfy { $0 == 1 })
        slow.cancel()
        gate.release()
        let readyPhoto = await ready.value, cancelledPhoto = await slow.value
        XCTAssertNotNil(readyPhoto)
        XCTAssertNil(cancelledPhoto)
    }

    func testExpiredPreviewHoursClearBeforeAnUnsuccessfulRefresh() async throws {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let repository = ManifestTestPhotoRepository()
        let backend = WanderBackend(placePhotoRepository: repository, photoMetadataNow: { now })
        let request = manifestRequest("preview-freshness").metadataOnly()
        var details = LivePlacePreviewProviderDetails()
        details.receive(try await backend.placePhoto(for: request))
        details.prepareForRefresh(cached: backend.cachedPlacePhoto(for: request))
        XCTAssertEqual(details.hours?.statusText, "Open")
        now.addTimeInterval(300)
        details.prepareForRefresh(cached: backend.cachedPlacePhoto(for: request))
        XCTAssertNil(details.hours, "A failed refresh must not leave expired hours on screen")
    }

    func testBatchConcurrencyStaysBoundedAcrossManyExpandedPins() async {
        let repository = ManifestTestPhotoRepository()
        let backend = WanderBackend(placePhotoRepository: repository)
        let tasks = (0..<15).map { index in
            Task { @MainActor in
                await LivePinPhotoResolver.resolve(request: self.manifestRequest("pin-\(index)"),
                    authorizationScopeKey: "viewer", backend: backend, retryDelayNanoseconds: 0)
            }
        }
        var photos = 0
        for task in tasks { if await task.value != nil { photos += 1 } }
        XCTAssertEqual(photos, 15)
        XCTAssertLessThanOrEqual(repository.maximumActiveBatches, 6)
        XCTAssertTrue(repository.batchSizes.allSatisfy { $0 == 1 })
    }

    private func manifestRequest(_ name: String) -> PlacePhotoRequest {
        PlacePhotoRequest(placeID: name, name: name, address: nil, latitude: 34, longitude: -118,
                          sourceProvider: "google", sourceProviderPlaceID: name, renderVariant: .listThumbnail)
    }
}

@MainActor
private final class ManifestTestPhotoRepository: PlacePhotoRepository {
    var requestCount = 0
    var photoMissing = false
    var openNow = true
    var gate: PhotoManifestTestGate?
    var heldName: String?
    var activeBatches = 0
    var maximumActiveBatches = 0
    var batchSizes: [Int] = []

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        requestCount += 1
        if let gate, heldName == nil || heldName == request.name { await gate.wait() }
        if photoMissing && request.requiresPhoto { throw WanderRemoteError.invalidResponse("photo_not_found") }
        return PlacePhoto(provider: "google_places", providerPlaceID: request.name, providerOpenNow: openNow,
            photoURLString: request.requiresPhoto ? "https://example.com/photo" : "", width: nil, height: nil,
            authorName: nil, authorProfileURLString: nil, authorAvatarURLString: nil,
            sourcePhotoURLString: nil, flagContentURLString: nil, storageBucket: nil, storagePath: nil, localAssetRef: nil)
    }
    func photos(for requests: [PlacePhotoRequest]) async throws -> [PlacePhotoBatchResult] {
        activeBatches += 1
        maximumActiveBatches = max(maximumActiveBatches, activeBatches)
        batchSizes.append(requests.count)
        defer { activeBatches -= 1 }
        await Task.yield()
        var photos: [PlacePhotoBatchResult] = []
        for request in requests {
            photos.append(PlacePhotoBatchResult(canonicalPlaceKey: request.canonicalPhotoCacheKey,
                                               photo: try await photo(for: request)))
        }
        return photos
    }
    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.notConfigured
    }
    func imageData(for photo: PlacePhoto) async throws -> Data { throw WanderRemoteError.notConfigured }
}

@MainActor
private final class PhotoManifestTestGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if waiting != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
}
