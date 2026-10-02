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

    func testMountedProfileWaitsForValidatedSessionOnEveryForegroundReturn() async throws {
        let store = WanderStore(fixtures: .empty())
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: store.currentUser.id, displayName: nil, handle: nil)),
            token: "appearance-test-token"
        ))
        let repository = AuthenticatedAppearancePlaceRepository(auth: auth)
        let backend = WanderBackend(placeRepository: repository, visitRepository: AppearanceVisitRepository())
        let lifecycle = ProfileAppearanceLifecycle()
        let host = UIHostingController(rootView: AuthenticatedProfileAppearanceProbe(lifecycle: lifecycle)
            .environmentObject(store).environmentObject(auth).environmentObject(backend)
            .environmentObject(PlaceSaveDraftStore())
            .environmentObject(FirstVisitWalkthroughCoordinator(isEnabled: false)))
        let window = try makeTestWindow(size: CGSize(width: 393, height: 852))
        let previous = window.windowScene?.windows.first(where: \.isKeyWindow)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(repository.requests, 0, "Cached signed-in state is not yet permission to fetch history.")
        await auth.refreshSession()
        try await waitUntil { repository.successes > 0 }

        for style in [UIUserInterfaceStyle.dark, .light, .dark, .light] {
            lifecycle.phase = .inactive
            try await Task.sleep(for: .milliseconds(100))
            window.overrideUserInterfaceStyle = style
            auth.beginSessionValidation()
            let previousRequests = repository.requests
            lifecycle.phase = .active
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(repository.requests, previousRequests,
                           "Foreground history must wait while the real token gate is closed.")
            let previousSuccesses = repository.successes
            await auth.refreshSession()
            try await waitUntil { repository.successes > previousSuccesses }
        }
        XCTAssertEqual(repository.rejectedTokens, 0)
        XCTAssertNil(store.lastRemoteError)
    }

    func testValidationFinishingDuringOldRequestQueuesNewRefreshAndIgnoresOldFailure() async throws {
        let state = PlaceProfileHistoryRefreshState()
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "appearance-user", displayName: nil, handle: nil)), token: "test"
        ))
        await auth.refreshSession()
        var continuation: CheckedContinuation<PlaceActivityRefreshOutcome, Never>?
        let old = Task {
            await state.refresh(isReady: { auth.isSessionValidated }) { _ in
                await withCheckedContinuation { continuation = $0 }
            }
        }
        try await waitUntil { continuation != nil }
        auth.beginSessionValidation()
        state.invalidate()
        await state.refresh(isReady: { auth.isSessionValidated }) { _ in
            XCTFail("Must not start a request while validation blocks tokens")
            return .failed
        }
        await auth.refreshSession()
        var retries = 0
        let latest = Task {
            await state.refresh(isReady: { auth.isSessionValidated }) { _ in
                XCTAssertFalse(state.hasFailed, "A stale failure must never flash the banner")
                let token = try? await auth.supabaseAccessToken()
                XCTAssertEqual(token, "test")
                retries += 1
                return .refreshed
            }
        }
        // Let the new request join the existing worker before releasing it.
        for _ in 0..<10 { await Task.yield() }
        continuation?.resume(returning: .failed)
        await old.value
        await latest.value
        XCTAssertEqual(retries, 1)
        XCTAssertFalse(state.hasFailed)
    }

    func testRefreshBannerPreservesGenuineFailureAndClearsOnRetry() async {
        let state = PlaceProfileHistoryRefreshState()
        await state.refresh(isReady: { true }) { _ in .failed }
        XCTAssertTrue(state.hasFailed)
        await state.refresh(isReady: { true }) { _ in .cancelled }
        XCTAssertTrue(state.hasFailed)
        await state.refresh(isReady: { true }) { _ in .refreshed }
        XCTAssertFalse(state.hasFailed)
    }

    func testDisappearingProfileDiscardsFailureAndDoesNotLoseReopenedRefresh() async throws {
        let state = PlaceProfileHistoryRefreshState()
        var continuation: CheckedContinuation<PlaceActivityRefreshOutcome, Never>?
        let old = Task {
            await state.refresh(isReady: { true }) { _ in
                await withCheckedContinuation { continuation = $0 }
            }
        }
        try await waitUntil { continuation != nil }
        state.cancel()
        var refreshed = false
        let reopened = Task {
            await state.refresh(isReady: { true }) { _ in
                XCTAssertFalse(Task.isCancelled)
                refreshed = true
                return .refreshed
            }
        }
        for _ in 0..<10 { await Task.yield() }
        continuation?.resume(returning: .failed)
        await old.value
        await reopened.value
        try await waitUntil { refreshed }
        XCTAssertFalse(state.hasFailed)
    }

    func testWannaStaysLightWithReadableInkInBothAppearances() async throws {
        for selected in [false, true] {
            let host = UIHostingController(rootView: WannaAppearanceProbe(selected: selected)
                .environmentObject(FirstVisitWalkthroughCoordinator(isEnabled: false))
                .astirAdaptiveBrandMode())
            let window = try makeTestWindow(size: UIScreen.main.bounds.size)
            let previous = window.windowScene?.windows.first(where: \.isKeyWindow)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            for style in [UIUserInterfaceStyle.light, .dark, .light] {
                window.overrideUserInterfaceStyle = style
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(700))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Wanna selected=\(selected) appearance=\(style.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let crop = CGRect(x: window.bounds.midX + 8, y: window.bounds.midY - 24, width: 112, height: 48)
                let cgImage = try XCTUnwrap(image.cgImage?.cropping(to: crop.applying(
                    CGAffineTransform(scaleX: image.scale, y: image.scale))))
                var pixels = [UInt8](repeating: 0, count: 112 * 48 * 4)
                try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 112, height: 48,
                        bitsPerComponent: 8, bytesPerRow: 112 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 112, height: 48))
                }
                let levels = stride(from: 0, to: pixels.count, by: 4).map {
                    (Double(pixels[$0]) + Double(pixels[$0 + 1]) + Double(pixels[$0 + 2])) / 3
                }
                XCTAssertGreaterThan(Double(levels.filter { $0 > 180 }.count) / Double(levels.count), 0.55,
                                     "Wanna must keep a white surface in both appearances")
                XCTAssertGreaterThan(Double(levels.filter { $0 < 100 }.count) / Double(levels.count), 0.03,
                                     "Wanna must keep a readable dark label and icon")
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for appearance refresh")
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

@MainActor
private final class ProfileAppearanceLifecycle: ObservableObject {
    @Published var phase: ScenePhase = .active
}

private struct AuthenticatedProfileAppearanceProbe: View {
    @ObservedObject var lifecycle: ProfileAppearanceLifecycle
    @EnvironmentObject private var store: WanderStore

    var body: some View {
        PlaceProfileFullScreen(
            place: PlaceSheetPlace(candidate: PlaceCandidate(id: "appearance-place", name: "Appearance cafe",
                category: "cafe", latitude: 34, longitude: -118, confidence: 1)),
            saves: [], tasteSaves: [], currentUserID: store.currentUser.id,
            action: .none, onBack: {}, onAction: {}
        )
        .environment(\.scenePhase, lifecycle.phase)
        .astirAdaptiveBrandMode()
    }
}

@MainActor
private final class AuthenticatedAppearancePlaceRepository: PlaceRepository {
    let auth: AuthSessionStore
    var requests = 0
    var successes = 0
    var rejectedTokens = 0
    init(auth: AuthSessionStore) { self.auth = auth }
    func places(in viewport: MapViewport) async throws -> [VisiblePlace] {
        requests += 1
        do { _ = try await auth.supabaseAccessToken() }
        catch { rejectedTokens += 1; throw error }
        successes += 1
        return []
    }
    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { [] }
}

private struct WannaAppearanceProbe: View {
    let selected: Bool
    @Environment(\.astirBrandMode) private var brand
    var body: some View {
        PlaceProfileFloatingActions(actions: [
            PlaceProfileSaveAction(kind: .checkIn, title: "Check in", isSelected: false, destinationStatus: .been),
            PlaceProfileSaveAction(kind: .wanna, title: "Wanna", isSelected: selected, destinationStatus: .wannaGo)
        ], variant: .option5, onAction: { _ in })
        .environment(\.placeProfileVisualStyle, .astir)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(brand.background)
        .ignoresSafeArea()
    }
}
