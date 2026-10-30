#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit
import XCTest
@preconcurrency @testable import PostHog
@testable import Wander

/// Portable baseline/candidate workload. Mounts the production embedded Feed,
/// with its ordinary cards, photo pipeline, pagination observers and layout.
@MainActor
final class FeedScreenScrollingPerformanceTests: XCTestCase {
    func testPerformanceMountedFeedScrollWith600Events() async throws {
        try await runMountedFeed(replay: false)
    }

    func testPerformanceMountedFeedScrollWith600EventsAndActualReplay() async throws {
        try await runMountedFeed(replay: true)
    }

    private func runMountedFeed(replay: Bool) async throws {
        let scene = try await foregroundScene()
        let originalWindow = try XCTUnwrap(scene.keyWindow)
        let originalRoot = try XCTUnwrap(originalWindow.rootViewController)
        let wasHidden = originalWindow.isHidden
        let wasKey = originalWindow.isKeyWindow
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let suite = "rec675-mounted-feed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WanderStore(fixtures: .performanceScale())
        let followed = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
        let page = store.livePerformanceFixtureFeedPage(from: followed, relativeTo: .now)
        XCTAssertEqual(page.activity.count, 600)
        XCTAssertEqual(Set(page.activity.map(\.id)).count, 600)
        let expectedPageIDs = page.activity.map(\.id)
        let backend = WanderBackend(feedRepository: MountedFeedRepository(page: page),
            placePhotoRepository: MapCapturePlacePhotoRepository(launchArguments: []),
            placePhotoDataDiskCache: .disabled)
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedIn(
            AuthSession(userID: store.currentUser.id, displayName: store.currentUser.displayName,
                        handle: store.currentUser.handle))))
        await auth.refreshSession()
        XCTAssertTrue(auth.isSessionValidated)
        store.selectLiveFeedQuery(LiveFeedQuery())
        let loaded = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(loaded)
        // Existing production focus behavior makes the complete fixture visible;
        // no benchmark-only row cap or replacement card implementation is used.
        store.revealFeedActivity(try XCTUnwrap(expectedPageIDs.last))
        let expectedGroupIDs = store.visibleLiveFeedSections.flatMap(\.groups).map(\.id)
        let expectedVisibleEventIDs = store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id)
        XCTAssertEqual(expectedGroupIDs.count, 600)
        XCTAssertEqual(Set(expectedVisibleEventIDs), Set(expectedPageIDs))

        let mount = MountedFeedState()
        let root = FeedScreen(isFeedTabActive: true, isEmbedded: true, showsInviteEntry: false,
            isEmbeddedFeedVisible: true, filteredActivityIDs: Set(expectedPageIDs))
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(PushNotificationManager(userDefaults: defaults))
            .environmentObject(FirstVisitWalkthroughCoordinator(isEnabled: false))
            .environmentObject(ActivityNavigationCoordinator())
            .environmentObject(PlacePlanInvitationInbox())
            .environmentObject(NotificationBadgeStore(defaults: defaults))
            .environmentObject(FollowNotificationInbox())
            .environmentObject(ActivityNotificationInbox())
            .environmentObject(PlaceSaveDraftStore(persistence: .ephemeral))
            .environmentObject(ProductUpsellCoordinator(userDefaults: defaults))
            .environment(\.scenePhase, .active)
            .dynamicTypeSize(.large)
            .onAppear { mount.didAppear = true }
        let host = UIHostingController(rootView: root)
        let window: UIWindow = replay
            ? MountedFeedReplayWindow(windowScene: scene)
            : UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        originalWindow.isHidden = true
        originalWindow.rootViewController = nil
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalWindow.rootViewController = originalRoot
            originalWindow.isHidden = wasHidden
            if wasKey { originalWindow.makeKey() }
        }
        host.view.frame = bounds
        _ = host.sizeThatFits(in: bounds.size)
        window.layoutIfNeeded()
        var mountedScroll: UIScrollView?
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while ProcessInfo.processInfo.systemUptime < deadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            mountedScroll = verticalScroll(in: host.view)
            if mount.didAppear, let scroll = mountedScroll,
               scroll.contentSize.height > scroll.bounds.height * 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let scroll = try XCTUnwrap(mountedScroll)
        XCTAssertTrue(mount.didAppear)
        XCTAssertGreaterThan(scroll.bounds.height, 300)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height * 3)
        // Mount/photo completion and initial SwiftUI tasks are outside timing.
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), expectedPageIDs)
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).map(\.id), expectedGroupIDs)

        // Replay is an additional workload, never a different Feed or scroll
        // driver. Preserve production masking, resolution and one-second cadence.
        let replayFrames = MountedFeedReplayFrames(windowID: window.hash)
        let replayWindow = window as? MountedFeedReplayWindow
        var replaySDK: PostHogSDK?
        defer { replaySDK?.close() }
        if replay {
            let config = PostHogAnalyticsClient.sdkConfiguration(
                projectToken: "fictional_mounted_feed_\(UUID().uuidString)", host: "https://replay.invalid")
            let session = URLSessionConfiguration.ephemeral
            session.protocolClasses = [MountedFeedReplayOfflineProtocol.self]
            config.urlSessionConfiguration = session
            config.preloadFeatureFlags = false
            XCTAssertEqual(config.sessionReplayConfig.throttleDelay, 1)
            XCTAssertTrue(config.sessionReplayConfig.screenshotMode)
            XCTAssertFalse(config.sessionReplayConfig.screenshotModeBackgroundCapture)
            XCTAssertFalse(config.sessionReplayConfig.maskAllTextInputs)
            XCTAssertFalse(config.sessionReplayConfig.maskAllImages)
            XCTAssertTrue(config.sessionReplayConfig.maskAllSandboxedViews)
            XCTAssertFalse(config.sessionReplayConfig.captureLogs)
            XCTAssertFalse(config.sessionReplayConfig.captureNetworkTelemetry)
            config.setBeforeSend { event in
                replayFrames.receive(event)
                // No event or synthetic image may enter the SDK event queue,
                // persistent storage, or transport. Decode-and-count only.
                return nil
            }
            let sdk = PostHogSDK.with(config)
            replaySDK = sdk
            let readyDeadline = ProcessInfo.processInfo.systemUptime + 30
            while (replayFrames.count == 0 || replayWindow?.successfulDraws == 0),
                  ProcessInfo.processInfo.systemUptime < readyDeadline {
                window.layer.setNeedsLayout()
                window.layer.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(sdk.isSessionReplayActive())
            XCTAssertGreaterThan(replayWindow?.successfulDraws ?? 0, 0,
                                 "The real SDK must successfully render this Feed window before timing.")
            XCTAssertGreaterThan(replayFrames.count, 0,
                                 "A decoded SDK image of this Feed window must reach the offline collector.")
            guard replayFrames.count > 0, (replayWindow?.successfulDraws ?? 0) > 0 else { return }
        }

        var elapsed: [Double] = []
        var layouts: [Double] = []
        for sample in 0..<3 {
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let firstNativeDraw = replayWindow?.drawDurations.count ?? 0
            let firstSuccessfulDraw = replayWindow?.successfulDraws ?? 0
            let firstEncodedFrame = replayFrames.count
            let driver = MountedFeedScrollDriver(scroll: scroll, window: window)
            let result = await driver.run(frameCount: 180, timeout: replay ? .seconds(120) : .seconds(30))
            XCTAssertFalse(result.timedOut, "The foreground display link must deliver every measured frame.")
            guard !result.timedOut else { return }
            elapsed.append(result.elapsedMS)
            layouts.append(result.layoutMS)
            XCTAssertEqual(result.frames, 180)
            XCTAssertEqual(result.movedFrames, 179, "Every nonzero native offset step must move the real scroll view.")
            XCTAssertGreaterThan(result.maximumOffset - result.minimumOffset, 4_000)
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height * 3)
            XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), expectedPageIDs)
            XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).map(\.id), expectedGroupIDs)
            XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id),
                expectedVisibleEventIDs, "Scrolling must retain all authorized rows and their presentation order.")
            if let replayWindow, let replaySDK {
                let draws = Array(replayWindow.drawDurations.dropFirst(firstNativeDraw))
                XCTAssertTrue(replaySDK.isSessionReplayActive())
                XCTAssertGreaterThan(replayWindow.successfulDraws, firstSuccessfulDraw,
                                     "Every measured sample must successfully draw the actual Feed through the SDK.")
                XCTAssertFalse(draws.isEmpty)
                // Capture/encoding is asynchronous. Freeze scroll timing first,
                // then require delivery without including the drain in timings.
                let drainStart = ProcessInfo.processInfo.systemUptime
                while replayFrames.count <= firstEncodedFrame,
                      ProcessInfo.processInfo.systemUptime - drainStart < 10 {
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertGreaterThan(replayFrames.count, firstEncodedFrame,
                                     "Every scroll sample must deliver a decoded fixture-window SDK image.")
                record("replay=true sample=\(sample) sdk=\(postHogVersion) "
                    + "native_draws=\(draws.count) successful_native_draws=\(replayWindow.successfulDraws - firstSuccessfulDraw) "
                    + "native_draw_ms=\(draws) decoded_frames=\(replayFrames.count - firstEncodedFrame) "
                    + "encoding_drain_ms=\((ProcessInfo.processInfo.systemUptime - drainStart) * 1_000)")
            }
            record("replay=\(replay) sample=\(sample) events=600 frames=\(result.frames) host_viewport=393x852 "
                + "scroll_viewport=\(scroll.bounds.width)x\(scroll.bounds.height) "
                + "elapsed_ms=\(result.elapsedMS) layout_ms=\(result.layoutMS) max_tick_gap_ms=\(result.maximumGapMS) "
                + "moved_frames=\(result.movedFrames) min_offset=\(result.minimumOffset) max_offset=\(result.maximumOffset)")
        }
        record("replay=\(replay) events=600 samples=3 median_elapsed_ms=\(elapsed.sorted()[1]) median_layout_ms=\(layouts.sorted()[1])")
        XCTAssertTrue(scene.keyWindow === window)
        XCTAssertTrue(originalWindow.isHidden)
        XCTAssertNil(originalWindow.rootViewController)
    }

    private func foregroundScene() async throws -> UIWindowScene {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) { return scene }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive },
            "A foreground simulator window is required for the mounted Feed benchmark")
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ current: UIView) {
            if let scroll = current as? UIScrollView,
               scroll.bounds.height > 300,
               scroll.contentSize.height > scroll.bounds.height { candidates.append(scroll) }
            current.subviews.forEach(visit)
        }
        visit(view)
        return candidates.max { $0.bounds.height < $1.bounds.height }
    }

    private func record(_ summary: String) {
        let attachment = XCTAttachment(string: "REC675 mounted_feed_scroll \(summary)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class MountedFeedRepository: FeedRepository {
    let page: FollowedFeedPage
    init(page: FollowedFeedPage) { self.page = page }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage { page }
    func liveFeed(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        onContent(page)
        return page
    }
}

@MainActor
private final class MountedFeedState { var didAppear = false }

@MainActor
private final class MountedFeedScrollDriver: NSObject {
    struct Result {
        let frames: Int
        let elapsedMS: Double
        let layoutMS: Double
        let maximumGapMS: Double
        let movedFrames: Int
        let minimumOffset: CGFloat
        let maximumOffset: CGFloat
        let timedOut: Bool
    }
    private let scroll: UIScrollView
    private let window: UIWindow
    private var displayLink: CADisplayLink?
    private var continuation: CheckedContinuation<Result, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var frameCount = 0
    private var frames = 0
    private var beganAt = 0.0
    private var previousTick = 0.0
    private var layoutMS = 0.0
    private var maximumGapMS = 0.0
    private var movedFrames = 0
    private var minimumOffset: CGFloat = .greatestFiniteMagnitude
    private var maximumOffset: CGFloat = -.greatestFiniteMagnitude

    init(scroll: UIScrollView, window: UIWindow) { self.scroll = scroll; self.window = window }

    func run(frameCount: Int, timeout: Duration = .seconds(30)) async -> Result {
        self.frameCount = frameCount
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            beganAt = ProcessInfo.processInfo.systemUptime
            previousTick = beganAt
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            displayLink = link
            link.add(to: .main, forMode: .common)
            timeoutTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                self?.finish(at: ProcessInfo.processInfo.systemUptime, timedOut: true)
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        maximumGapMS = max(maximumGapMS, (now - previousTick) * 1_000)
        previousTick = now
        guard frames < frameCount else {
            finish(at: now, timedOut: false)
            return
        }
        // Down then up at 64pt per display frame. Identical native offsets are
        // used on both builds; neither AX snapshots nor store projections run
        // inside this measured callback.
        let half = frameCount / 2
        let step = frames <= half ? frames : frameCount - frames
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let target = min(bottom, top + CGFloat(step) * 64)
        let previousOffset = scroll.contentOffset.y
        scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        let actualOffset = scroll.contentOffset.y
        if abs(actualOffset - previousOffset) > 1 { movedFrames += 1 }
        minimumOffset = min(minimumOffset, actualOffset)
        maximumOffset = max(maximumOffset, actualOffset)
        layoutMS += (ProcessInfo.processInfo.systemUptime - now) * 1_000
        frames += 1
    }

    private func finish(at now: TimeInterval, timedOut: Bool) {
        guard let completion = continuation else { return }
        continuation = nil
        displayLink?.invalidate()
        displayLink = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completion.resume(returning: Result(frames: frames, elapsedMS: (now - beganAt) * 1_000,
            layoutMS: layoutMS, maximumGapMS: maximumGapMS, movedFrames: movedFrames,
            minimumOffset: minimumOffset, maximumOffset: maximumOffset, timedOut: timedOut))
    }
}

/// Only the replay variant records native screenshot work. The ordinary variant
/// continues to mount UIWindow and uses the identical original scroll driver.
@MainActor
private final class MountedFeedReplayWindow: UIWindow {
    var drawDurations: [Double] = []
    var successfulDraws = 0

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        let success = super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
        if !afterUpdates {
            drawDurations.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            if success { successfulDraws += 1 }
        }
        return success
    }
}

/// Counts only decoded images belonging to the isolated synthetic Feed window.
/// No raw image, encoded frame, or SDK event is retained or attached to results.
private final class MountedFeedReplayFrames: @unchecked Sendable {
    private let windowID: Int
    private let lock = NSLock()
    private var decodedCount = 0
    var count: Int { lock.withLock { decodedCount } }

    init(windowID: Int) { self.windowID = windowID }

    func receive(_ event: PostHogEvent) {
        guard event.event == "$snapshot",
              let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] else { return }
        var decoded = 0
        for snapshot in snapshots {
            guard let data = snapshot["data"] as? [String: Any],
                  let wireframes = data["wireframes"] as? [[String: Any]] else { continue }
            for frame in wireframes {
                guard frame["id"] as? Int == windowID,
                      let raw = frame["base64"] as? String,
                      let imageData = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")),
                      let image = UIImage(data: imageData),
                      image.size.width > 0, image.size.height > 0 else { continue }
                decoded += 1
            }
        }
        if decoded > 0 { lock.withLock { decodedCount += decoded } }
    }
}

/// All SDK HTTP requests are answered locally, including replay activation.
/// Returning nil before send separately prevents snapshots from being queued.
private final class MountedFeedReplayOfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"sessionRecording":true,"featureFlags":{},"featureFlagPayloads":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
