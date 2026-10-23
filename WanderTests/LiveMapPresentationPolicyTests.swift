import MapKit
import UIKit
import XCTest
@testable import Wander

final class LiveMapPresentationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testOverlappingPinsBecomeIndividualDotsWhileSelectedPinStaysExpanded() {
        let points: [(id: String, point: CGPoint)] = [
            ("a", .init(x: 100, y: 100)), ("b", .init(x: 104, y: 105)),
            ("selected", .init(x: 102, y: 102)), ("distant", .init(x: 240, y: 240))
        ]
        XCTAssertEqual(LivePinDensity.compactIDs(points: points, selectedID: "selected"), ["a", "b"])
        XCTAssertEqual(LivePinDensity.compactIDs(points: Array(points.reversed()), selectedID: "selected"), ["a", "b"],
                       "Network page ordering must not change which pin wins an overlapping position.")
    }

    func testSpatialBucketsMatchGreedyDensityAcrossNegativeBoundariesAndSelectedPriority() {
        var points: [(id: String, point: CGPoint)] = []
        for x in -5...5 {
            for y in -5...5 {
                let offset: CGFloat = (x + y).isMultiple(of: 2) ? -0.001 : 0.001
                points.append(("grid-\(x)-\(y)", CGPoint(x: CGFloat(x) * 38 + offset,
                                                        y: CGFloat(y) * 38 - offset)))
            }
        }
        for index in 0..<80 {
            points.append(("dense-\(index)", CGPoint(x: -38 + CGFloat(index % 8) / 10,
                                                   y: 38 + CGFloat(index / 8) / 10)))
        }
        points += [("boundary-origin", .zero), ("boundary-exact", CGPoint(x: 38, y: 0)),
                   ("boundary-inside", CGPoint(x: 37.999, y: 0)),
                   ("z-selected", CGPoint(x: -38, y: 38))]

        // Keep a simple reference scan: this verifies the optimization without
        // copying its spatial indexing or depending on network arrival order.
        func greedy(_ input: [(id: String, point: CGPoint)], selected: String?, spacing: CGFloat) -> Set<String> {
            let sorted = input.sorted {
                if ($0.id == selected) != ($1.id == selected) { return $0.id == selected }
                return $0.id < $1.id
            }
            var expanded: [CGPoint] = [], compact = Set<String>()
            for entry in sorted {
                if entry.id != selected && expanded.contains(where: {
                    hypot($0.x - entry.point.x, $0.y - entry.point.y) < spacing
                }) { compact.insert(entry.id) }
                else { expanded.append(entry.point) }
            }
            return compact
        }
        let selectedIDs: [String?] = [nil, "z-selected", "grid--3--2"]
        for spacing in [CGFloat(1), 17, 38, 76] {
            for selected in selectedIDs {
                let expected = greedy(points, selected: selected, spacing: spacing)
                XCTAssertEqual(LivePinDensity.compactIDs(points: points, selectedID: selected, minimumSpacing: spacing), expected)
                XCTAssertEqual(LivePinDensity.compactIDs(points: Array(points.reversed()), selectedID: selected,
                                                        minimumSpacing: spacing), expected)
                if let selected { XCTAssertFalse(expected.contains(selected)) }
            }
        }
        XCTAssertTrue(LivePinDensity.compactIDs(points: [("a", .zero), ("b", CGPoint(x: 38, y: 0))],
                                                selectedID: nil).isEmpty, "Exactly spaced pins remain full size.")
    }

    func testZoomingApartRestoresFullPinsWithoutCombiningTheirIdentities() {
        let dense: [(id: String, point: CGPoint)] = [
            ("a", .init(x: 100, y: 100)), ("b", .init(x: 110, y: 110)), ("c", .init(x: 120, y: 120))
        ]
        XCTAssertEqual(LivePinDensity.compactIDs(points: dense, selectedID: nil), ["b", "c"])
        let zoomed = dense.map { (id: $0.id, point: CGPoint(x: $0.point.x * 4, y: $0.point.y * 4)) }
        XCTAssertTrue(LivePinDensity.compactIDs(points: zoomed, selectedID: nil).isEmpty)
        XCTAssertTrue(LivePinDensity.compactIDs(points: [("missing", CGPoint(x: CGFloat.infinity, y: 20))],
                                                selectedID: nil).isEmpty)
    }

    func testViewedPinFadesForTwentyFourHoursWithoutAcceptingFutureTimestamps() {
        let dates = ["new": now, "last-second": now.addingTimeInterval(-86_399),
                     "expired": now.addingTimeInterval(-86_400), "future": now.addingTimeInterval(1)]
        XCTAssertTrue(LiveViewedPinHistory.isViewed("new", dates: dates, now: now))
        XCTAssertTrue(LiveViewedPinHistory.isViewed("last-second", dates: dates, now: now))
        XCTAssertFalse(LiveViewedPinHistory.isViewed("expired", dates: dates, now: now))
        XCTAssertFalse(LiveViewedPinHistory.isViewed("future", dates: dates, now: now))
        XCTAssertFalse(LiveViewedPinHistory.isViewed("unknown", dates: dates, now: now))
    }

    func testViewedPinPersistenceIsAccountScopedAndDropsExpiredHistory() throws {
        let suite = "LiveMapPresentationPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LiveViewedPinHistory.save(["seen": now, "old": now.addingTimeInterval(-86_400)],
                                  userID: "account-a", defaults: defaults, now: now)
        XCTAssertEqual(LiveViewedPinHistory.load(userID: "account-a", defaults: defaults, now: now), ["seen": now])
        XCTAssertTrue(LiveViewedPinHistory.load(userID: "account-b", defaults: defaults, now: now).isEmpty)
        LiveViewedPinHistory.save(["other": now], userID: "account-b", defaults: defaults, now: now)
        XCTAssertEqual(LiveViewedPinHistory.load(userID: "account-a", defaults: defaults, now: now), ["seen": now])
        XCTAssertEqual(LiveViewedPinHistory.load(userID: "account-b", defaults: defaults, now: now), ["other": now])
        XCTAssertTrue(LiveViewedPinHistory.load(userID: "account-a", defaults: defaults,
                                                now: now.addingTimeInterval(86_400)).isEmpty)
    }

    func testViewedHistoryRetainsMostRecentEntriesWithinBoundedStorage() throws {
        let suite = "LiveMapPresentationPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dates = Dictionary(uniqueKeysWithValues: (0..<520).map { ("pin-\($0)", now.addingTimeInterval(-Double($0))) })
        LiveViewedPinHistory.save(dates, userID: "account", defaults: defaults, now: now)
        let loaded = LiveViewedPinHistory.load(userID: "account", defaults: defaults, now: now)
        XCTAssertEqual(loaded.count, 512)
        XCTAssertNotNil(loaded["pin-0"])
        XCTAssertNotNil(loaded["pin-511"])
        XCTAssertNil(loaded["pin-512"])
    }

    func testFeedReturnRequiresActualScrollAndExpiresAfterThirtyMinutes() {
        XCTAssertFalse(LiveReviewContinuity.keepsFeedPosition(scrolled: false, departedAt: now, now: now))
        XCTAssertFalse(LiveReviewContinuity.keepsFeedPosition(scrolled: true, departedAt: nil, now: now))
        XCTAssertFalse(LiveReviewContinuity.keepsFeedPosition(scrolled: true, departedAt: now.addingTimeInterval(1), now: now))
        XCTAssertTrue(LiveReviewContinuity.keepsFeedPosition(scrolled: true, departedAt: now, now: now.addingTimeInterval(1_800)))
        XCTAssertFalse(LiveReviewContinuity.keepsFeedPosition(scrolled: true, departedAt: now, now: now.addingTimeInterval(1_801)))
    }

    func testHalfSheetFitsTheSameFootprintAndClosingRestoresOriginalFocus() throws {
        let size = CGSize(width: 390, height: 780)
        let full = CGRect(x: 0, y: 120, width: 390, height: 590)
        let half = CGRect(x: 0, y: 120, width: 390, height: 290)
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 34, longitude: -118))
        let initial = MKCoordinateRegion(MKMapRect(x: center.x - 40_000, y: center.y - 80_000,
                                                  width: 80_000, height: 160_000))
        let adjusted = try XCTUnwrap(LiveMapViewportPolicy.fittedRegion(initial, size: size, from: full, to: half))
        XCTAssertGreaterThan(adjusted.span.longitudeDelta, initial.span.longitudeDelta)
        let originalFocus = mapPoint(at: CGPoint(x: full.midX, y: full.midY), region: initial, size: size)
        let nextFocus = screenPoint(originalFocus, region: adjusted, size: size)
        XCTAssertEqual(nextFocus.x, half.midX, accuracy: 0.1)
        XCTAssertEqual(nextFocus.y, half.midY, accuracy: 0.1)
        for point in [CGPoint(x: full.minX, y: full.minY), CGPoint(x: full.maxX, y: full.maxY)] {
            let projected = screenPoint(mapPoint(at: point, region: initial, size: size), region: adjusted, size: size)
            XCTAssertGreaterThanOrEqual(projected.x, half.minX - 0.1)
            XCTAssertLessThanOrEqual(projected.x, half.maxX + 0.1)
            XCTAssertGreaterThanOrEqual(projected.y, half.minY - 0.1)
            XCTAssertLessThanOrEqual(projected.y, half.maxY + 0.1)
        }
        let restored = try XCTUnwrap(LiveMapViewportPolicy.fittedRegion(adjusted, size: size, from: half, to: full))
        let restoredFocus = screenPoint(originalFocus, region: restored, size: size)
        XCTAssertEqual(restoredFocus.x, full.midX, accuracy: 0.1)
        XCTAssertEqual(restoredFocus.y, full.midY, accuracy: 0.1)
        XCTAssertEqual(restored.span.longitudeDelta, initial.span.longitudeDelta, accuracy: 0.000_01)
    }

    func testPinRevealMovesOnlyCoveredPinsByTheMinimumAmount() {
        let exposed = CGRect(x: 0, y: 100, width: 390, height: 300)
        XCTAssertEqual(LiveMapViewportPolicy.revealOffset(pin: CGPoint(x: 195, y: 200), exposedRect: exposed), .zero)
        XCTAssertEqual(LiveMapViewportPolicy.revealOffset(pin: CGPoint(x: 195, y: 110), exposedRect: exposed), .zero,
                       "A card opening must not recenter an already visible pin near the top.")
        let hidden = CGPoint(x: 195, y: 500)
        let offset = LiveMapViewportPolicy.revealOffset(pin: hidden, exposedRect: exposed)
        XCTAssertEqual(offset.width, 0)
        XCTAssertEqual(offset.height, 124)
        XCTAssertEqual(hidden.y - offset.height, exposed.maxY - 24)
        let edge = LiveMapViewportPolicy.revealOffset(pin: CGPoint(x: 386, y: 500), exposedRect: exposed)
        XCTAssertEqual(edge.width, 20)
        XCTAssertEqual(edge.height, 124)
    }

    func testTransientOrInvalidMapGeometryDoesNotCreateInvalidCamera() {
        let region = MKCoordinateRegion(center: .init(latitude: 34, longitude: -118),
                                        span: .init(latitudeDelta: 0.1, longitudeDelta: 0.1))
        let size = CGSize(width: 390, height: 780)
        let full = CGRect(x: 0, y: 120, width: 390, height: 590)
        for invalid in [CGRect(x: 0, y: 120, width: 0, height: 290),
                        CGRect(x: 0, y: 120, width: 390, height: 0),
                        CGRect(x: CGFloat.infinity, y: 120, width: 390, height: 290)] {
            XCTAssertNil(LiveMapViewportPolicy.fittedRegion(region, size: size, from: full, to: invalid))
        }
        XCTAssertNil(LiveMapViewportPolicy.fittedRegion(region, size: .zero, from: full, to: full))
        XCTAssertNil(LiveMapViewportPolicy.fittedRegion(region, size: CGSize(width: CGFloat.infinity, height: 780),
                                                        from: full, to: full))
    }

    private func mapPoint(at point: CGPoint, region: MKCoordinateRegion, size: CGSize) -> MKMapPoint {
        let center = MKMapPoint(region.center)
        let scale = region.span.longitudeDelta / 360 * MKMapRect.world.width / size.width
        return MKMapPoint(x: center.x + (point.x - size.width / 2) * scale,
                          y: center.y + (point.y - size.height / 2) * scale)
    }

    private func screenPoint(_ point: MKMapPoint, region: MKCoordinateRegion, size: CGSize) -> CGPoint {
        let center = MKMapPoint(region.center)
        let scale = region.span.longitudeDelta / 360 * MKMapRect.world.width / size.width
        return CGPoint(x: size.width / 2 + (point.x - center.x) / scale,
                       y: size.height / 2 + (point.y - center.y) / scale)
    }
}

@MainActor
final class LivePinPhotoResolverTests: XCTestCase {
    func testExpandedPinsBatchBeyondTwentyAndRetryOnlyMissingProviderPhotos() async {
        let repository = LivePinPhotoTestRepository()
        let backend = WanderBackend(placePhotoRepository: repository)
        let batcher = ListPlacePhotoBatcher()
        let requests = (0..<45).map { request("pin-\($0)") }
        let tasks = requests.map { request in
            Task { @MainActor in
                await LivePinPhotoResolver.resolve(request: request, authorizationScopeKey: "viewer",
                    backend: backend, batcher: batcher, retryDelayNanoseconds: 0)
            }
        }
        var resolved = 0
        for task in tasks {
            if await task.value != nil { resolved += 1 }
        }
        XCTAssertEqual(resolved, 45, "Expanded pins must not stop after the first successful photos.")
        XCTAssertLessThan(repository.batches.count, 10, "Use batched metadata, not one request per pin.")
        XCTAssertEqual(Set(repository.attempts.keys), Set(requests.map(\.canonicalPhotoCacheKey)))
        for request in requests {
            let expected = request.name == "pin-0" ? 1 : 2
            XCTAssertEqual(repository.attempts[request.canonicalPhotoCacheKey], expected)
        }
        XCTAssertEqual(repository.visibleUserRequests, 0, "Available provider photos remain the primary pin image.")
    }

    func testUnavailablePhotoStopsAfterOneRetryAndKeepsAnHonestEmptyResult() async {
        let repository = LivePinPhotoTestRepository()
        repository.alwaysMissing = true
        let backend = WanderBackend(placePhotoRepository: repository)
        let request = request("missing")
        let photo = await LivePinPhotoResolver.resolve(request: request, authorizationScopeKey: "viewer",
            backend: backend, batcher: ListPlacePhotoBatcher(debounceNanoseconds: 0), retryDelayNanoseconds: 0)
        XCTAssertNil(photo)
        XCTAssertEqual(repository.attempts[request.canonicalPhotoCacheKey], 2)
        XCTAssertEqual(repository.visibleUserRequests, 1)
    }

    func testTransientImageDownloadRetriesOnceBeforeUsingFallback() async {
        let repository = LivePinPhotoTestRepository()
        repository.metadataImmediatelyAvailable = true
        repository.transientImageFailures = 1
        repository.imagePayload = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let backend = WanderBackend(placePhotoRepository: repository)
        let image = await LivePinPhotoResolver.resolveImage(request: request("bytes-\(UUID())"),
            authorizationScopeKey: "viewer", backend: backend, targetPixelSize: 34,
            batcher: ListPlacePhotoBatcher(debounceNanoseconds: 0), retryDelayNanoseconds: 0)
        XCTAssertNotNil(image)
        XCTAssertEqual(repository.imageRequests, 2)
        XCTAssertEqual(repository.visibleUserRequests, 0)
    }

    func testPersistentTransientImageFailureStopsAfterOneRetry() async {
        let repository = LivePinPhotoTestRepository()
        repository.metadataImmediatelyAvailable = true
        repository.transientImageFailures = 3
        let image = await LivePinPhotoResolver.resolveImage(request: request("failed-bytes-\(UUID())"),
            authorizationScopeKey: "viewer", backend: WanderBackend(placePhotoRepository: repository),
            targetPixelSize: 34, batcher: ListPlacePhotoBatcher(debounceNanoseconds: 0), retryDelayNanoseconds: 0)
        XCTAssertNil(image)
        XCTAssertEqual(repository.imageRequests, 2)
        XCTAssertEqual(repository.visibleUserRequests, 1)
    }

    func testCancellationDoesNotRetryImageOrRequestAnotherPhoto() async {
        let repository = LivePinPhotoTestRepository()
        repository.metadataImmediatelyAvailable = true
        repository.imageError = CancellationError()
        let image = await LivePinPhotoResolver.resolveImage(request: request("cancelled-bytes-\(UUID())"),
            authorizationScopeKey: "viewer", backend: WanderBackend(placePhotoRepository: repository),
            targetPixelSize: 34, batcher: ListPlacePhotoBatcher(debounceNanoseconds: 0), retryDelayNanoseconds: 0)
        XCTAssertNil(image)
        XCTAssertEqual(repository.imageRequests, 1)
        XCTAssertEqual(repository.visibleUserRequests, 0)
    }

    func testImageRetryClassifierAcceptsOnlyTransportAndExactPublicDownloadFailures() {
        XCTAssertTrue(LivePinPhotoResolver.isTransientImageError(URLError(.networkConnectionLost)))
        XCTAssertTrue(LivePinPhotoResolver.isTransientImageError(
            WanderRemoteError.invalidResponse("Place photo download failed")))
        let permanentErrors: [Error] = [
            WanderRemoteError.notAuthenticated,
            WanderRemoteError.notConfigured,
            WanderRemoteError.invalidResponse("photo_not_visible"),
            WanderRemoteError.invalidResponse("Place photo has no readable source"),
            WanderRemoteError.invalidResponse("Place photo download failed: unauthorized"),
            URLError(.userAuthenticationRequired),
            CancellationError(),
            NSError(domain: "test", code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Place photo download failed"])
        ]
        for error in permanentErrors {
            XCTAssertFalse(LivePinPhotoResolver.isTransientImageError(error))
        }
    }

    func testPermanentImageFailureIsNotRetried() async {
        let repository = LivePinPhotoTestRepository()
        repository.metadataImmediatelyAvailable = true
        repository.imageError = WanderRemoteError.invalidResponse("photo_not_visible")
        let image = await LivePinPhotoResolver.resolveImage(request: request("denied-bytes-\(UUID())"),
            authorizationScopeKey: "viewer", backend: WanderBackend(placePhotoRepository: repository),
            targetPixelSize: 34, batcher: ListPlacePhotoBatcher(debounceNanoseconds: 0), retryDelayNanoseconds: 0)
        XCTAssertNil(image)
        XCTAssertEqual(repository.imageRequests, 1)
        XCTAssertEqual(repository.visibleUserRequests, 1)
    }

    private func request(_ id: String) -> PlacePhotoRequest {
        PlacePhotoRequest(placeID: id, name: id, address: nil, latitude: 34, longitude: -118,
                          sourceProvider: "google", sourceProviderPlaceID: id, renderVariant: .listThumbnail)
    }
}

@MainActor
private final class LivePinPhotoTestRepository: PlacePhotoRepository {
    var batches: [[PlacePhotoRequest]] = []
    var attempts: [String: Int] = [:]
    var visibleUserRequests = 0
    var alwaysMissing = false
    var metadataImmediatelyAvailable = false
    var imagePayload: Data?
    var imageRequests = 0
    var transientImageFailures = 0
    var imageError: Error?

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        XCTFail("Expanded pin metadata should use the batch path.")
        throw WanderRemoteError.invalidResponse("missing_test_photo")
    }

    func photos(for requests: [PlacePhotoRequest]) async throws -> [PlacePhotoBatchResult] {
        batches.append(requests)
        return requests.compactMap { request in
            let key = request.canonicalPhotoCacheKey
            attempts[key, default: 0] += 1
            guard !alwaysMissing, metadataImmediatelyAvailable || request.name == "pin-0" || attempts[key] == 2 else { return nil }
            let photo = PlacePhoto(provider: "google_places", providerPlaceID: request.name,
                photoURLString: "", width: nil, height: nil, authorName: nil, authorProfileURLString: nil,
                authorAvatarURLString: nil, sourcePhotoURLString: nil, flagContentURLString: nil,
                storageBucket: nil, storagePath: nil, localAssetRef: nil)
            return PlacePhotoBatchResult(canonicalPlaceKey: key, photo: photo)
        }
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        visibleUserRequests += 1
        throw WanderRemoteError.invalidResponse("missing_test_photo")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        imageRequests += 1
        if transientImageFailures > 0 {
            transientImageFailures -= 1
            throw URLError(.networkConnectionLost)
        }
        if let imageError { throw imageError }
        guard let imagePayload else {
            XCTFail("Metadata resolution must not download image data.")
            throw WanderRemoteError.invalidResponse("missing_test_photo")
        }
        return imagePayload
    }
}
