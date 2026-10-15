import XCTest
import SwiftUI
import PostHog
import Vision
@testable import Wander

/// Exercises the pinned SDK's real screenshot path, entirely offline with fictional data.
final class ReplayMaskingTests: XCTestCase {
    @MainActor
    func testPrivateMessageContentIsMaskedInActualReplayImage() async throws {
        let captureTimeline = ReplayCaptureTimeline()
        var foregroundScene: UIWindowScene?
        for _ in 0..<100 {
            foregroundScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if foregroundScene != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(foregroundScene)
        let originalWindow = scene.keyWindow
        let window = ReplayProbeWindow(windowScene: scene)
        window.captureTimeline = captureTimeline
        window.backgroundColor = .white
        // The SDK can conservatively mask the entire SwiftUI hosting surface
        // on iOS 26. A native sibling proves capture is live without weakening
        // the privacy assertion or requiring the private heading to be readable.
        let container = UIViewController()
        container.view.backgroundColor = .white
        let control = UILabel()
        control.text = "Replay ready"; control.textColor = .black
        control.backgroundColor = .green; control.textAlignment = .center
        container.view.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor),
            control.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            control.heightAnchor.constraint(equalToConstant: 54)
        ])
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer { window.isHidden = true; originalWindow?.makeKeyAndVisible() }

        let frames = ReplayFrameCollector(captureTimeline: captureTimeline)
        let config = PostHogAnalyticsClient.sdkConfiguration(projectToken: "replay_fixture_\(UUID().uuidString)", host: "https://replay.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ReplayOfflineProtocol.self]
        config.urlSessionConfiguration = session
        config.preloadFeatureFlags = false
        // Preserve production capture cadence. A faster fixture cadence can
        // enqueue screenshots faster than the pinned SDK's serial encoder,
        // leaving the collector behind the actual presentation.
        XCTAssertEqual(config.sessionReplayConfig.throttleDelay, 1.0)
        config.setBeforeSend { event in frames.receive(event); return nil }
        let sdk = PostHogSDK.with(config)
        captureTimeline.record(.sdkSetupReturned)
        defer { sdk.close() }
        sdk.capture(ReplayFrameCollector.probeEvent)
        XCTAssertEqual(frames.probeCallbackCount, 1, "The offline collector must receive the SDK callback probe.")
        var layoutPump = ReplayLayoutPump(interval: .seconds(config.sessionReplayConfig.throttleDelay),
                                          captureTimeline: captureTimeline)

        // Require the recorder to produce a frame before creating any private
        // view. Never reset the collector: first presentation is part of the proof.
        var recorderReady = false
        var observedReadyFrameCount = 0
        var recordedReplayActivation = false
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(30))
        captureTimeline.record(.readyGateBegan)
        while ContinuousClock.now < readyDeadline {
            // Inactive SDK layouts are discarded. Do not reserve the pump's
            // delivery/backpressure window until the recorder can receive one.
            if sdk.isSessionReplayActive() {
                if !recordedReplayActivation {
                    captureTimeline.record(.replayFirstActive)
                    recordedReplayActivation = true
                }
                layoutPump.requestLayoutWhenReady(window: window, frames: frames)
            } else {
                captureTimeline.record(.readyInactivePoll)
            }
            try await Task.sleep(for: .milliseconds(100))
            let available = frames.images
            // Re-running Vision on the same image competes with the SDK's
            // serial image encoder without adding freshness evidence.
            while observedReadyFrameCount < available.count, ContinuousClock.now < readyDeadline {
                let frame = available[observedReadyFrameCount]
                let text = try await Self.recognizedText(frame)
                observedReadyFrameCount += 1
                if sdk.isSessionReplayActive(), text.contains("replay ready") {
                    recorderReady = true
                    break
                }
            }
            if recorderReady { break }
        }
        captureTimeline.record(.readyGateEnded)
        XCTAssertTrue(recorderReady, "An actual public frame must precede first private presentation.")
        guard recorderReady else {
            let diagnostic = XCTAttachment(string: """
            ready_frame_count=\(frames.images.count)
            replay_active=\(sdk.isSessionReplayActive())
            foreground_active=\(scene.activationState == .foregroundActive)
            fixture_key_window=\(scene.keyWindow === window)
            sdk_style_draws_ready_success=\(window.successfulReadyDraws)
            sdk_style_draws_failed=\(window.failedDraws)
            fixture_frames_delivered=\(frames.imageCount(windowID: window.hash))
            fixture_layout_requests=\(layoutPump.requestCount)
            \(captureTimeline.diagnostics)
            \(frames.diagnostics)
            """)
            diagnostic.name = "Private replay readiness diagnostics"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            if let latest = frames.image {
                let attachment = XCTAttachment(image: latest)
                attachment.name = "Private replay — latest frame before readiness failure"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            return
        }
        let readyFrameCount = frames.images.count

        let repository = try XCTUnwrap(PrivateMessageUITestFixtures.make(
            userID: "user_joe", authenticatedUITest: true, unifiedLiveEnabled: true))
        let conversationID = try XCTUnwrap(UUID(uuidString: "63600000-0000-0000-0000-000000000010"))
        let thread = UIHostingController(rootView: NavigationStack {
            PrivateMessageThreadScreen(userID: "user_joe", repository: repository, target: .conversation(conversationID))
        }.environment(\.scenePhase, .active).dynamicTypeSize(.large))
        container.addChild(thread)
        container.view.addSubview(thread.view)
        thread.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thread.view.topAnchor.constraint(equalTo: control.bottomAnchor),
            thread.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            thread.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            thread.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        thread.didMove(toParent: container)

        var baseline: UIImage?
        var baselineText = ""
        for _ in 0..<60 {
            layoutPump.requestLayoutWhenReady(window: window, frames: frames)
            try await Task.sleep(for: .milliseconds(100))
            let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            baseline = capture
            baselineText = try await Self.recognizedText(capture)
            if baselineText.contains("maya chen"), baselineText.contains("patio") { break }
        }
        XCTAssertTrue(baselineText.contains("maya chen"), "Baseline must contain the actual fictional participant.")
        XCTAssertTrue(baselineText.contains("patio"), "Baseline must contain the loaded message, not an empty screen.")
        let before = XCTAttachment(image: try XCTUnwrap(baseline))
        before.name = "Private thread — fictional baseline"; before.lifetime = .keepAlways; add(before)

        // A distinct post-hydration control rules out passing on only an old
        // public frame or a loading placeholder from the transition.
        let preLoadedControlFrameCount = frames.images.count
        window.capturePhase = "loaded"
        control.text = "Replay loaded"
        // Independently verify the updated native fixture before waiting for
        // the SDK's own screenshot and encoding pipeline to deliver it.
        let loadedBaseline = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let loadedBaselineText = try await Self.recognizedText(loadedBaseline)
        XCTAssertTrue(loadedBaselineText.contains("replay loaded"),
                      "The native post-load control must be rendered before observing SDK frames.")
        var replay: UIImage?
        var observedLoadedFrameCount = preLoadedControlFrameCount
        let loadedDeadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < loadedDeadline {
            layoutPump.requestLayoutWhenReady(window: window, frames: frames)
            try await Task.sleep(for: .milliseconds(100))
            let available = frames.images
            while observedLoadedFrameCount < available.count, ContinuousClock.now < loadedDeadline {
                let frame = available[observedLoadedFrameCount]
                let text = try await Self.recognizedText(frame)
                observedLoadedFrameCount += 1
                if text.contains("replay loaded") {
                    replay = frame
                    break
                }
            }
            if replay != nil { break }
        }
        // Preserve evidence even when the exact post-load control gate fails.
        // A missing gate must not skip checking the frames that were captured.
        let capturedFrames = frames.images
        let diagnostic = XCTAttachment(string: """
        ready_frame_count=\(readyFrameCount)
        pre_loaded_control_frame_count=\(preLoadedControlFrameCount)
        final_frame_count=\(capturedFrames.count)
        replay_active=\(sdk.isSessionReplayActive())
        foreground_active=\(scene.activationState == .foregroundActive)
        fixture_key_window=\(scene.keyWindow === window)
        loaded_control_observed=\(replay != nil)
        sdk_style_draws_ready_success=\(window.successfulReadyDraws)
        sdk_style_draws_loaded_success=\(window.successfulLoadedDraws)
        sdk_style_draws_failed=\(window.failedDraws)
        fixture_frames_delivered=\(frames.imageCount(windowID: window.hash))
        fixture_layout_requests=\(layoutPump.requestCount)
        \(captureTimeline.diagnostics)
        \(frames.diagnostics)
        """)
        diagnostic.name = "Private replay capture diagnostics"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        if let latest = capturedFrames.last {
            let latestAttachment = XCTAttachment(image: latest)
            latestAttachment.name = "Private thread — latest actual SDK frame, including failure"
            latestAttachment.lifetime = .keepAlways
            add(latestAttachment)
        }
        for frame in capturedFrames {
            let text = try await Self.recognizedText(frame)
            for privateToken in ["maya", "chen", "patio", "lovely", "sunny", "afternoon"] {
                XCTAssertFalse(text.contains(privateToken), "Private content must not appear in any captured frame, including startup.")
            }
        }
        XCTAssertTrue(sdk.isSessionReplayActive())
        let loadedReplay = try XCTUnwrap(replay, "Pinned SDK must supply a frame after private content has loaded.")
        let attachment = XCTAttachment(image: loadedReplay)
        attachment.name = "Private thread — actual offline SDK replay"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private nonisolated static func recognizedText(_ image: UIImage) async throws -> String {
        // Vision can take seconds on a hosted simulator. Keep UIKit's main
        // queue available for the SDK's genuine screenshot rendering while
        // inspecting the immutable captured image.
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").lowercased()
        }.value
    }

    @MainActor
    func testReadableContentAndCredentialMaskingInActualReplayImage() async throws {
        // Match the SDK's capture precondition; connected scenes can still be inactive at launch.
        var foregroundScene: UIWindowScene?
        for _ in 0..<100 {
            foregroundScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if foregroundScene != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(foregroundScene, "Replay capture requires a foreground-active scene")
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        // Fixed pixel probes require fixed typography, independent of simulator accessibility settings.
        window.rootViewController = UIHostingController(rootView: ReplayPrivacyFixture().dynamicTypeSize(.large))

        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            originalWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(scene.keyWindow === window, "The SDK must capture the fixture's key window")
        XCTAssertFalse(window.bounds.isEmpty)

        // The SDK captures with afterScreenUpdates: false. Commit this newly mounted
        // SwiftUI fixture before its first capture instead of reading an unfinished frame.
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        var baselineRendered = false
        let baseline = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            baselineRendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let baselineAttachment = XCTAttachment(image: baseline)
        baselineAttachment.name = "Fictional fixture before replay masking"
        baselineAttachment.lifetime = .keepAlways
        add(baselineAttachment)
        XCTAssertTrue(baselineRendered, "The fixture must finish rendering before replay capture starts")
        guard baselineRendered else { return }

        let frames = ReplayFrameCollector()
        let config = PostHogAnalyticsClient.sdkConfiguration(projectToken: "replay_fixture_\(UUID().uuidString)", host: "https://replay.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ReplayOfflineProtocol.self]
        config.urlSessionConfiguration = session
        config.preloadFeatureFlags = false
        XCTAssertEqual(config.sessionReplayConfig.throttleDelay, 1.0)
        config.setBeforeSend { event in
            frames.receive(event)
            return nil // Never enqueue or transmit fixture events or images.
        }
        let sdk = PostHogSDK.with(config)
        defer { sdk.close() }
        sdk.capture(ReplayFrameCollector.probeEvent)
        XCTAssertEqual(frames.probeCallbackCount, 1, "The offline collector must receive the SDK callback probe.")

        // The pinned SDK observes UIView.layoutSublayers(of:). A plain UIView
        // makes that exact base-class callback part of each real layout pulse,
        // independent of UIWindow/UIHostingView layout overrides. It is clear,
        // outside the pixel probes, and does not replace SDK capture or masking.
        let layoutPulse = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        layoutPulse.isUserInteractionEnabled = false
        layoutPulse.accessibilityElementsHidden = true
        window.addSubview(layoutPulse)

        // Replay is inactive until the SDK has processed the asynchronous offline
        // remote-config response. Layouts before that point are discarded, so
        // readiness must not consume the time allowed for a screenshot callback.
        let clock = ContinuousClock()
        let readinessDeadline = clock.now.advanced(by: .seconds(15))
        while !sdk.isSessionReplayActive(), clock.now < readinessDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard sdk.isSessionReplayActive() else {
            XCTFail("The SDK must activate replay after the offline config response (foreground: \(scene.activationState == .foregroundActive), fixture key: \(scene.keyWindow === window), \(frames.diagnostics))")
            return
        }

        // Drive genuine layout notifications until an encoded SDK frame arrives.
        // Layout throttling and image encoding run asynchronously on SDK queues;
        // a fixed number of layout pulses does not establish capture completion.
        let captureStarted = clock.now
        let settledAt = captureStarted.advanced(by: .seconds(2))
        let captureDeadline = captureStarted.advanced(by: .seconds(30))
        repeat {
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            layoutPulse.layer.setNeedsLayout()
            layoutPulse.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < captureDeadline && (clock.now < settledAt || frames.image == nil)
        XCTAssertTrue(sdk.isSessionReplayActive())
        let image = try XCTUnwrap(frames.image,
            "The SDK must produce an actual replay frame within 30 seconds after activation (foreground: \(scene.activationState == .foregroundActive), fixture key: \(scene.keyWindow === window), \(frames.diagnostics))")
        let attachment = XCTAttachment(image: image)
        attachment.name = "Offline replay — readable content and masked credentials"
        attachment.lifetime = .keepAlways
        add(attachment)

        // These points fall inside solid-color fixture backgrounds, away from text edges.
        let publicText = try pixel(image, x: 60, y: 125)
        XCTAssertGreaterThan(publicText.green, 150, "Ordinary text view must remain visible")
        let publicImage = try pixel(image, x: 60, y: 205)
        XCTAssertGreaterThan(publicImage.blue, 150, "Images must remain visible")
        for y in [285, 365] {
            let credential = try pixel(image, x: 150, y: y)
            XCTAssertLessThan(max(credential.red, credential.green, credential.blue), 30, "Password/code must be blacked out")
        }
        let email = try pixel(image, x: 60, y: 445)
        XCTAssertGreaterThan(email.red, 150, "Approved non-credential input must remain visible")
        XCTAssertGreaterThan(email.blue, 150)
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let scale = CGFloat(cg.width) / image.size.width
        let index = (Int(CGFloat(y) * scale) * cg.width + Int(CGFloat(x) * scale)) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2])
    }
}

private struct ReplayPrivacyFixture: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            VStack(spacing: 20) {
                Text("Readable place name").frame(width: 240, height: 60).background(Color.green)
                Image(uiImage: solidImage).resizable().frame(width: 240, height: 60)
                SecureField("Password", text: .constant("fictional-password"))
                    .textContentType(.password).frame(width: 240, height: 60)
                    .background(Color.red).sessionReplayMasked()
                TextField("Code", text: .constant("123456"))
                    .textContentType(.oneTimeCode).frame(width: 240, height: 60)
                    .background(Color.orange).sessionReplayMasked()
                TextField("Email", text: .constant("alex@example.invalid"))
                    .textContentType(.emailAddress).frame(width: 240, height: 60)
                    .background(Color.purple).sessionReplayVisibleInput()
            }.padding(.leading, 40).padding(.top, 100)
        }.ignoresSafeArea()
    }

    private var solidImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 60)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 60))
        }
    }
}

/// Aggregate timings share one monotonic test origin. No event payloads,
/// image data, view content or absolute timestamps enter these diagnostics.
private final class ReplayCaptureTimeline: @unchecked Sendable {
    enum Stage: String, CaseIterable {
        case sdkSetupReturned = "sdk_setup_returned"
        case readyGateBegan = "ready_gate_began"
        case replayFirstActive = "replay_first_active"
        case readyInactivePoll = "ready_inactive_poll"
        case readyGateEnded = "ready_gate_ended"
        case layoutRequest = "layout_request"
        case nativeReadyDrawBegan = "native_ready_draw_began"
        case nativeReadyDrawEnded = "native_ready_draw_ended"
        case nativeLoadedDrawBegan = "native_loaded_draw_began"
        case nativeLoadedDrawEnded = "native_loaded_draw_ended"
        case nativeDrawFailed = "native_draw_failed"
        case snapshotCallback = "snapshot_callback"
        case decodedImage = "decoded_image"
    }

    private struct Sample {
        var count = 0
        var firstMilliseconds: Int64
        var lastMilliseconds: Int64
    }

    private let origin = ContinuousClock.now
    private let lock = NSLock()
    private var samples: [Stage: Sample] = [:]

    func record(_ stage: Stage) {
        lock.lock(); defer { lock.unlock() }
        let elapsed = origin.duration(to: .now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        var sample = samples[stage] ?? Sample(firstMilliseconds: milliseconds, lastMilliseconds: milliseconds)
        sample.count += 1
        sample.lastMilliseconds = milliseconds
        samples[stage] = sample
    }

    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        return (["capture_clock_origin=test_start", "capture_clock_unit=elapsed_ms"] + Stage.allCases.map { stage in
            let sample = samples[stage]
            return "timing_\(stage.rawValue)_count=\(sample?.count ?? 0) "
                + "first_ms=\(sample.map { String($0.firstMilliseconds) } ?? "none") "
                + "last_ms=\(sample.map { String($0.lastMilliseconds) } ?? "none")"
        }).joined(separator: "\n")
    }
}

/// Observes the actual native renderer without replacing its result or pixels.
@MainActor
private final class ReplayProbeWindow: UIWindow {
    var capturePhase = "ready"
    var captureTimeline: ReplayCaptureTimeline?
    private(set) var successfulReadyDraws = 0
    private(set) var successfulLoadedDraws = 0
    private(set) var failedDraws = 0

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        if !afterUpdates {
            captureTimeline?.record(capturePhase == "loaded" ? .nativeLoadedDrawBegan : .nativeReadyDrawBegan)
        }
        let succeeded = super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
        if !afterUpdates {
            captureTimeline?.record(capturePhase == "loaded" ? .nativeLoadedDrawEnded : .nativeReadyDrawEnded)
            if !succeeded { captureTimeline?.record(.nativeDrawFailed) }
            if !succeeded { failedDraws += 1 }
            else if capturePhase == "loaded" { successfulLoadedDraws += 1 }
            else { successfulReadyDraws += 1 }
        }
        return succeeded
    }
}

/// Pace only the test's extra layout requests, never the recorder or native UI.
/// The SDK's render guard ends before its serial mask/WebP encoding completes.
/// Wait for delivery progress before requesting another layout. A renderer or
/// encoder can drop a frame, so retry after ten seconds rather than requiring
/// native draw and delivered image counts to match forever.
@MainActor
private struct ReplayLayoutPump {
    private let interval: Duration
    private let captureTimeline: ReplayCaptureTimeline?
    private var nextRequestAt = ContinuousClock.now
    private var retryAt = ContinuousClock.now
    private var deliveredCountAtRequest: Int?
    private(set) var requestCount = 0

    init(interval: Duration, captureTimeline: ReplayCaptureTimeline? = nil) {
        self.interval = interval
        self.captureTimeline = captureTimeline
    }

    mutating func requestLayoutWhenReady(window: ReplayProbeWindow, frames: ReplayFrameCollector) {
        let now = ContinuousClock.now
        let delivered = frames.imageCount(windowID: window.hash)
        let deliveryAdvanced = deliveredCountAtRequest.map { delivered > $0 } ?? true
        guard now >= nextRequestAt, deliveryAdvanced || now >= retryAt else { return }
        deliveredCountAtRequest = delivered
        nextRequestAt = now.advanced(by: interval)
        retryAt = now.advanced(by: .seconds(10))
        requestCount += 1
        captureTimeline?.record(.layoutRequest)
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        window.layer.setNeedsLayout()
        window.layer.layoutIfNeeded()
    }
}

private final class ReplayFrameCollector: @unchecked Sendable {
    static let probeEvent = "replay_fixture_callback_probe"

    private struct Counts {
        var callbacks = 0
        var probeCallbacks = 0
        var snapshotCallbacks = 0
        var snapshotArrays = 0
        var wireframeArrays = 0
        var wireframes = 0
        var base64Strings = 0
        var dataDecodes = 0
        var imageDecodes = 0
    }

    private let lock = NSLock()
    private let captureTimeline: ReplayCaptureTimeline?
    private var counts = Counts()
    private var captured: [UIImage] = []
    private var windowImageCounts: [Int: Int] = [:]

    init(captureTimeline: ReplayCaptureTimeline? = nil) {
        self.captureTimeline = captureTimeline
    }

    var image: UIImage? { lock.lock(); defer { lock.unlock() }; return captured.last }
    var images: [UIImage] { lock.lock(); defer { lock.unlock() }; return captured }
    var probeCallbackCount: Int { lock.lock(); defer { lock.unlock() }; return counts.probeCallbacks }
    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        return """
        collector_callbacks=\(counts.callbacks)
        collector_probe_callbacks=\(counts.probeCallbacks)
        collector_snapshot_callbacks=\(counts.snapshotCallbacks)
        collector_snapshot_arrays=\(counts.snapshotArrays)
        collector_wireframe_arrays=\(counts.wireframeArrays)
        collector_wireframes=\(counts.wireframes)
        collector_base64_strings=\(counts.base64Strings)
        collector_data_decodes=\(counts.dataDecodes)
        collector_image_decodes=\(counts.imageDecodes)
        """
    }

    func imageCount(windowID: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        return windowImageCounts[windowID, default: 0]
    }

    private func record(_ update: (inout Counts) -> Void) {
        lock.lock(); defer { lock.unlock() }
        update(&counts)
    }

    func receive(_ event: PostHogEvent) {
        record { $0.callbacks += 1 }
        if event.event == Self.probeEvent { record { $0.probeCallbacks += 1 } }
        guard event.event == "$snapshot" else { return }
        captureTimeline?.record(.snapshotCallback)
        record { $0.snapshotCallbacks += 1 }
        guard let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] else { return }
        record { $0.snapshotArrays += 1 }
        for snapshot in snapshots {
            guard let data = snapshot["data"] as? [String: Any], let frames = data["wireframes"] as? [[String: Any]] else { continue }
            record { $0.wireframeArrays += 1 }
            for frame in frames {
                record { $0.wireframes += 1 }
                guard let raw = frame["base64"] as? String else { continue }
                record { $0.base64Strings += 1 }
                guard let data = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")) else { continue }
                record { $0.dataDecodes += 1 }
                guard let image = UIImage(data: data) else { continue }
                captureTimeline?.record(.decodedImage)
                lock.lock()
                counts.imageDecodes += 1
                captured.append(image)
                // The pinned SDK assigns each screenshot wireframe its actual
                // UIWindow hash. Use this only for pacing; freshness still
                // requires the visible post-hydration sentinel in SDK pixels.
                if let windowID = frame["id"] as? Int { windowImageCounts[windowID, default: 0] += 1 }
                lock.unlock()
            }
        }
    }
}

private final class ReplayOfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"sessionRecording":true,"featureFlags":{},"featureFlagPayloads":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
