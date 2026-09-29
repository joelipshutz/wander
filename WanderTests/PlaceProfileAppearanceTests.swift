import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class PlaceProfileAppearanceTests: XCTestCase {
    func testCancelledProfileViewportRequestDoesNotReportRemoteError() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let store = WanderStore(fixtures: .empty())
            let backend = WanderBackend(placeRepository: AppearancePlaceRepository(error: error))
            let viewport = MapViewport(minLatitude: 33, minLongitude: -119,
                                       maxLatitude: 34, maxLongitude: -118)
            let places = await store.fetchRemoteViewportPlaces(in: viewport, backend: backend)
            XCTAssertNil(places)
            XCTAssertFalse(Task.isCancelled)
            XCTAssertNil(store.lastRemoteError, "An interrupted viewport must not become a history error.")
        }
    }

    func testGlassSurfaceMatchesFreshAppearanceAfterRepeatedLiveSwitches() async throws {
        let host = UIHostingController(rootView: GlassAppearanceProbe().astirAdaptiveBrandMode())
        let window = try makeTestWindow(size: CGSize(width: 320, height: 480))
        window.overrideUserInterfaceStyle = .light
        let previousWindow = window.windowScene?.windows.first(where: \.isKeyWindow)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }

        func capture(_ style: UIUserInterfaceStyle) async throws -> [UInt8] {
            window.overrideUserInterfaceStyle = style
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(700))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Glass appearance \(style.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let cgImage = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: 32 * 48 * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: 32, height: 48,
                    bitsPerComponent: 8, bytesPerRow: 32 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 48))
            }
            return pixels
        }
        let light = try await capture(.light)
        let dark = try await capture(.dark)
        XCTAssertGreaterThan(pixelDifference(light, dark), 50,
                             "The probe must actually render different appearances.")
        for _ in 0..<2 {
            let switchedLight = try await capture(.light)
            XCTAssertLessThan(pixelDifference(light, switchedLight), 5,
                              "Returning to Light must match a fresh Light surface.")
            let switchedDark = try await capture(.dark)
            XCTAssertLessThan(pixelDifference(dark, switchedDark), 5,
                              "Returning to Dark must match the original Dark surface.")
        }
    }

    private func makeTestWindow(size: CGSize) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        return window
    }

    private func pixelDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        zip(lhs, rhs).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(lhs.count)
    }

    func testCancelledHistoryRequestsKeepCachedVisitsWithoutReportingRemoteError() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let store = WanderStore(fixtures: .empty())
            let repository = AppearanceVisitRepository()
            let backend = WanderBackend(visitRepository: repository)
            let ids = [AppearanceVisitRepository.parentID]
            let initial = await store.refreshRemotePlaceActivity(userPlaceIDs: ids, backend: backend)
            XCTAssertTrue(initial)
            repository.error = error

            let outcome = await store.refreshRemotePlaceActivityOutcome(userPlaceIDs: ids, backend: backend)

            XCTAssertEqual(outcome, .cancelled)
            XCTAssertFalse(Task.isCancelled, "The repository may cancel independently of its caller.")
            XCTAssertNil(store.lastRemoteError, "Cancellation is not a remote history failure.")
            XCTAssertEqual(store.visits(for: ids[0]).map(\.id), [AppearanceVisitRepository.visitID])
        }
    }

    func testCancelledPhotoReadPreservesCachedHistoryAndPhotos() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let store = WanderStore(fixtures: .empty())
            let repository = AppearanceVisitRepository()
            let backend = WanderBackend(visitRepository: repository)
            let ids = [AppearanceVisitRepository.parentID]
            _ = await store.refreshRemotePlaceActivity(userPlaceIDs: ids, backend: backend)
            repository.photoError = error
            repository.rating = 1

            let outcome = await store.refreshRemotePlaceActivityOutcome(userPlaceIDs: ids, backend: backend)

            XCTAssertEqual(outcome, .cancelled)
            XCTAssertNil(store.lastRemoteError)
            XCTAssertEqual(store.visits(for: ids[0]).first?.ratingScore, 4,
                           "Cancellation must not apply an incomplete history snapshot.")
            XCTAssertEqual(store.photos(for: AppearanceVisitRepository.visitID).map(\.id),
                           [AppearanceVisitRepository.photoID])
        }
    }

    func testRealHistoryFailurePreservesCacheAndSuccessfulRetryClearsError() async {
        let store = WanderStore(fixtures: .empty())
        let repository = AppearanceVisitRepository()
        let backend = WanderBackend(visitRepository: repository)
        let ids = [AppearanceVisitRepository.parentID]
        _ = await store.refreshRemotePlaceActivity(userPlaceIDs: ids, backend: backend)
        repository.error = URLError(.notConnectedToInternet)

        let failed = await store.refreshRemotePlaceActivityOutcome(userPlaceIDs: ids, backend: backend)
        XCTAssertEqual(failed, .failed)
        XCTAssertNotNil(store.lastRemoteError)
        XCTAssertEqual(store.visits(for: ids[0]).map(\.id), [AppearanceVisitRepository.visitID])

        repository.error = nil
        let retried = await store.refreshRemotePlaceActivityOutcome(userPlaceIDs: ids, backend: backend)
        XCTAssertEqual(retried, .refreshed)
        XCTAssertNil(store.lastRemoteError)
    }

    func testViewportResultDistinguishesCancellationFromRealFailure() async {
        let viewport = MapViewport(minLatitude: 33, minLongitude: -119,
                                   maxLatitude: 34, maxLongitude: -118)
        for error: Error in [CancellationError(), URLError(.cancelled), URLError(.timedOut)] {
            let store = WanderStore(fixtures: .empty())
            let backend = WanderBackend(placeRepository: AppearancePlaceRepository(error: error))
            let result = await store.fetchRemoteViewportPlacesResult(in: viewport, backend: backend)
            guard case .failure(let reported) = result else {
                XCTFail("The failing repository must not report a successful read.")
                continue
            }
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            XCTAssertEqual(reported is CancellationError, cancelled)
            XCTAssertEqual(store.lastRemoteError == nil, cancelled)
        }
    }

    func testNativeProfileHostTracksLiveAppearanceWithoutReplacingContentState() async throws {
        let observations = AppearanceObservations()
        let host = UIHostingController(rootView:
            PlaceProfileVerticalContainer(isPresented: true) {
                AppearanceProbe(observations: observations)
            }
            .astirAdaptiveBrandMode()
        )
        let window = try makeTestWindow(size: CGSize(width: 393, height: 852))
        window.overrideUserInterfaceStyle = .dark
        let previousWindow = window.windowScene?.windows.first(where: \.isKeyWindow)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }

        for style in [UIUserInterfaceStyle.dark, .light, .dark, .light] {
            window.overrideUserInterfaceStyle = style
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // Allow traits and deferred hosting updates to settle without
            // reconstructing the host or depending on a single frame's timing.
            for _ in 0..<40 {
                if let value = observations.values.last,
                   value.scheme == (style == .dark ? .dark : .light),
                   value.brand == (style == .dark ? .editorial : .editorialLight) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let latest = try XCTUnwrap(observations.values.last)
            XCTAssertEqual(latest.scheme, style == .dark ? .dark : .light)
            XCTAssertEqual(latest.brand, style == .dark ? .editorial : .editorialLight)
        }
        XCTAssertEqual(Set(observations.values.map(\.identity)).count, 1,
                       "Changing appearance must retain the mounted profile's state.")
    }
}

@MainActor
private final class AppearancePlaceRepository: PlaceRepository {
    let error: Error
    init(error: Error) { self.error = error }
    func places(in viewport: MapViewport) async throws -> [VisiblePlace] { throw error }
    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { [] }
}

private struct GlassAppearanceProbe: View {
    @Environment(\.astirBrandMode) private var brand

    var body: some View {
        VStack {
            Text("Checked in")
                .foregroundStyle(brand.primaryText)
            Text("History details remain readable")
                .foregroundStyle(brand.secondaryText)
        }
        .padding(24)
        .frame(width: 280, height: 280)
        .astirGlassSurface(cornerRadius: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(brand.background)
    }
}

@MainActor
private final class AppearanceVisitRepository: VisitRepository {
    static let parentID = "b6e0413b-a4dd-4d6b-8281-f0ac0157f134"
    static let visitID = "5f97f1ee-05a5-4e84-a480-6c5325e9c241"
    static let photoID = "1694ec30-0289-49a3-a370-c31befb2ef0c"
    var error: Error?
    var photoError: Error?
    var rating: Double = 4

    func visits(for userPlaceID: String) async throws -> [PlaceVisitResult] {
        if let error { throw error }
        return [PlaceVisitResult(visitID: Self.visitID, userPlaceID: userPlaceID,
                                visitedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                note: nil, ratingScore: rating, tags: [], backfilledFromUserPlace: false)]
    }

    func photos(for visitID: String) async throws -> [VisitPhotoResult] {
        if let photoError { throw photoError }
        return [VisitPhotoResult(photoID: Self.photoID, visitID: visitID,
                                 storageBucket: "test", storagePath: "appearance.jpg",
                                 remoteURLString: nil, contentType: "image/jpeg", byteSize: 100,
                                 width: 10, height: 10, capturedAt: nil, sortOrder: 0,
                                 uploadState: .uploaded)]
    }
    func upsertVisit(_ draft: PlaceVisitDraft) async throws -> PlaceVisitResult {
        throw WanderRemoteError.notConfigured
    }
    func deleteVisit(visitID: String) async throws { throw WanderRemoteError.notConfigured }
    func upsertPhotoMetadata(_ draft: VisitPhotoDraft) async throws -> VisitPhotoResult {
        throw WanderRemoteError.notConfigured
    }
    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        throw WanderRemoteError.notConfigured
    }
    func deletePhoto(photoID: String, bucket: String, path: String) async throws {
        throw WanderRemoteError.notConfigured
    }
}

@MainActor
private final class AppearanceObservations {
    struct Value {
        let scheme: ColorScheme
        let brand: AstirBrandMode
        let identity: UUID
    }
    var values: [Value] = []
}

private struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.astirBrandMode) private var brand
    @State private var identity = UUID()
    let observations: AppearanceObservations

    var body: some View {
        Color.clear
            .onAppear(perform: record)
            .onChange(of: scheme) { record() }
            .onChange(of: brand) { record() }
    }

    private func record() {
        observations.values.append(.init(scheme: scheme, brand: brand, identity: identity))
    }
}
