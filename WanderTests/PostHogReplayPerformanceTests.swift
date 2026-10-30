import XCTest
import SwiftUI
@preconcurrency @testable import PostHog
@testable import Wander

/// Portable across the old and fixed SDKs. All views and SDK responses are fictional.
final class PostHogReplayPerformanceTests: XCTestCase {
    @MainActor
    func testPerformanceActualSDKLayoutCallbacksInsideThrottleWindow() async throws {
        let callback = PostHogThrottledMulticastCallback<Int>()
        let received = ReplayPerformanceCounter()
        // A long test window prevents a slow simulator from changing this CPU workload.
        let token = callback.subscribe(throttle: 60) { _ in received.increment() }
        callback.invoke(0)
        try await waitForCount(received, minimum: 1)
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            for value in 0..<20_000 { callback.invoke(value) }
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            // Allow queued work to progress between identical enqueue-CPU samples.
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertEqual(received.value, 1)
        withExtendedLifetime(token) {}
        record("layout_callbacks", "callbacks_per_sample=20000 samples_ms=\(samples) median_ms=\(samples.sorted()[2])")
    }

    @MainActor
    func testActualSDKThrottleCoalescesConcurrentBurstsAndAdmitsNewSubscriber() async throws {
        for _ in 0..<10 {
            let callback = PostHogThrottledMulticastCallback<Int>()
            let invoker = ReplayPerformanceInvoker(callback)
            let first = ReplayPerformanceCounter()
            let late = ReplayPerformanceCounter()
            var firstToken: RegistrationToken? = callback.subscribe(throttle: 60) { _ in first.increment() }
            DispatchQueue.concurrentPerform(iterations: 2_000) { value in invoker.invoke(value) }
            try await waitForCount(first, minimum: 1)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(first.value, 1, "One burst must not schedule duplicate captures inside the throttle window")

            let lateToken = callback.subscribe(throttle: 60) { _ in late.increment() }
            callback.invoke(2_001)
            try await waitForCount(late, minimum: 1)
            XCTAssertEqual(first.value, 1)
            XCTAssertEqual(late.value, 1, "A fresh subscriber must not inherit another subscriber's throttle window")
            firstToken = nil
            callback.invoke(2_002)
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(first.value, 1)
            withExtendedLifetime((firstToken, lateToken)) {}
        }
    }

    @MainActor
    func testPerformanceActualReplayMaskedScroll() async throws {
        #if DEBUG && targetEnvironment(simulator)
        guard await admitReplayFixtureHostIfRequested() else { return }
        #endif
        var foregroundScene: UIWindowScene?
        for _ in 0..<100 {
            foregroundScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if foregroundScene != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(foregroundScene)
        let originalWindow = try XCTUnwrap(scene.keyWindow)
        let originalRoot = try XCTUnwrap(originalWindow.rootViewController)
        let originalHidden = originalWindow.isHidden
        let originalKey = originalWindow.isKeyWindow
        let window = ReplayPerformanceWindow(windowScene: scene)
        let host = UIHostingController(rootView: ReplayPerformanceRows())
        window.rootViewController = host
        window.makeKeyAndVisible()
        originalWindow.isHidden = true
        originalWindow.rootViewController = nil
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalWindow.rootViewController = originalRoot
            originalWindow.isHidden = originalHidden
            if originalKey { originalWindow.makeKey() }
        }
        _ = host.sizeThatFits(in: window.bounds.size)
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(findScrollView(in: host.view))
        let layoutDeadline = ProcessInfo.processInfo.systemUptime + 5
        while scroll.contentSize.height <= scroll.bounds.height,
              ProcessInfo.processInfo.systemUptime < layoutDeadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        // Let SwiftUI's mounted hierarchy and Core Animation commit before the
        // recorder's first native draw. These setup turns are outside timing.
        for _ in 0..<3 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            window.layer.setNeedsLayout()
            window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }

        let frames = ReplayPerformanceCounter()
        let windowID = window.hash
        let config = PostHogAnalyticsClient.sdkConfiguration(
            projectToken: "fictional_replay_performance_\(UUID().uuidString)", host: "https://replay.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ReplayPerformanceOfflineProtocol.self]
        config.urlSessionConfiguration = session
        config.preloadFeatureFlags = false
        XCTAssertEqual(config.sessionReplayConfig.throttleDelay, 1)
        XCTAssertTrue(config.sessionReplayConfig.screenshotMode)
        XCTAssertFalse(config.sessionReplayConfig.screenshotModeBackgroundCapture)
        config.setBeforeSend { event in
            if event.event == "$snapshot",
               let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] {
                for snapshot in snapshots {
                    guard let data = snapshot["data"] as? [String: Any],
                          let wireframes = data["wireframes"] as? [[String: Any]] else { continue }
                    for frame in wireframes {
                        guard frame["id"] as? Int == windowID,
                              let raw = frame["base64"] as? String,
                              let imageData = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")),
                              let image = UIImage(data: imageData),
                              image.size.width > 0, image.size.height > 0 else { continue }
                        frames.increment()
                    }
                }
            }
            // Exercise capture and encoding; no synthetic screenshot is persisted or sent.
            return nil
        }
        let sdk = PostHogSDK.with(config)
        defer { sdk.close() }
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 30
        while (frames.value == 0 || window.successfulDraws == 0),
              ProcessInfo.processInfo.systemUptime < readyDeadline {
            window.layer.setNeedsLayout()
            window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        record("masked_scroll_ready", "native_draws=\(window.drawDurations.count) successful_native_draws=\(window.successfulDraws) encoded_frames=\(frames.value)")
        XCTAssertTrue(sdk.isSessionReplayActive())
        XCTAssertGreaterThan(window.drawDurations.count, 0, "The real native screenshot renderer must run")
        XCTAssertGreaterThan(window.successfulDraws, 0, "The fixture must render successfully")
        XCTAssertGreaterThan(frames.value, 0, "An encoded SDK image must reach the offline collector")
        guard frames.value > 0, window.successfulDraws > 0 else { return }

        for sample in 0..<3 {
            let firstDraw = window.drawDurations.count
            let firstFrame = frames.value
            let start = ProcessInfo.processInfo.systemUptime
            var previousTick = start
            var maxTickGap = 0.0
            var layoutMS = 0.0
            for step in 0..<180 {
                let now = ProcessInfo.processInfo.systemUptime
                maxTickGap = max(maxTickGap, now - previousTick)
                previousTick = now
                // Continuous native scrolling realizes/recycles the real masked SwiftUI rows.
                let range = max(1, scroll.contentSize.height - scroll.bounds.height)
                let offset = CGFloat((sample * 180 + step) * 28).truncatingRemainder(dividingBy: range)
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                window.setNeedsLayout()
                window.layoutIfNeeded()
                layoutMS += (ProcessInfo.processInfo.systemUptime - now) * 1_000
                try await Task.sleep(for: .milliseconds(16))
            }
            let elapsedMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            let draws = Array(window.drawDurations.dropFirst(firstDraw))
            XCTAssertFalse(draws.isEmpty, "Scrolling must exercise production-cadence native captures")
            // Encoding runs on the SDK's serial utility queue. Confirm delivery
            // separately after freezing the scroll timings; never weaken the
            // encoded-image requirement or include drain waiting in those timings.
            let drainStart = ProcessInfo.processInfo.systemUptime
            while frames.value <= firstFrame, ProcessInfo.processInfo.systemUptime - drainStart < 10 {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertGreaterThan(frames.value, firstFrame, "An encoded fixture-window image must arrive for every scroll sample")
            let drainMS = (ProcessInfo.processInfo.systemUptime - drainStart) * 1_000
            record("masked_scroll", "sample=\(sample) rows=200 steps=180 elapsed_ms=\(elapsedMS) layout_ms=\(layoutMS) max_tick_gap_ms=\(maxTickGap * 1_000) native_draws=\(draws.count) native_draw_ms=\(draws) encoded_frames=\(frames.value - firstFrame) encoding_drain_ms=\(drainMS)")
        }
        XCTAssertTrue(scene.keyWindow === window)
        XCTAssertTrue(originalWindow.isHidden)
    }

    @MainActor
    private func waitForCount(_ counter: ReplayPerformanceCounter, minimum: Int) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while counter.value < minimum, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertGreaterThanOrEqual(counter.value, minimum)
    }

    @MainActor
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScrollView(in: child) { return scroll }
        }
        return nil
    }

    private func record(_ workload: String, _ measurements: String) {
        let attachment = XCTAttachment(string: "REC675 posthog_\(workload) sdk=\(postHogVersion) \(measurements)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct ReplayPerformanceRows: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<200, id: \.self) { index in
                    HStack {
                        Text("Fictional private row \(index)").sessionReplayMasked()
                        Spacer()
                        Text("Public \(index)")
                    }
                    .frame(height: 52)
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(Color.white)
    }
}

@MainActor
private final class ReplayPerformanceWindow: UIWindow {
    var drawDurations: [Double] = []
    var successfulDraws = 0
    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        let start = ProcessInfo.processInfo.systemUptime
        let result = super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
        if !afterUpdates {
            drawDurations.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            if result { successfulDraws += 1 }
        }
        return result
    }
}

private final class ReplayPerformanceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// The SDK callback's public-to-the-module contract permits calls from multiple threads.
private final class ReplayPerformanceInvoker: @unchecked Sendable {
    private let callback: PostHogThrottledMulticastCallback<Int>
    init(_ callback: PostHogThrottledMulticastCallback<Int>) { self.callback = callback }
    func invoke(_ value: Int) { callback.invoke(value) }
}

private final class ReplayPerformanceOfflineProtocol: URLProtocol, @unchecked Sendable {
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
