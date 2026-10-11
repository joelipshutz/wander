import XCTest
import SwiftUI
import PostHog
import Vision
@testable import Wander

/// Exercises the pinned SDK's real screenshot path, entirely offline with fictional data.
final class ReplayMaskingTests: XCTestCase {
    @MainActor
    func testPrivateMessageContentIsMaskedInActualReplayImage() async throws {
        var foregroundScene: UIWindowScene?
        for _ in 0..<100 {
            foregroundScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if foregroundScene != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(foregroundScene)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        // The SDK can conservatively mask the entire SwiftUI hosting surface
        // on iOS 26. A native sibling proves capture is live without weakening
        // the privacy assertion or requiring the private heading to be readable.
        let container = UIViewController()
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

        let frames = ReplayFrameCollector()
        let config = PostHogAnalyticsClient.sdkConfiguration(projectToken: "replay_fixture_\(UUID().uuidString)", host: "https://replay.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ReplayOfflineProtocol.self]
        config.urlSessionConfiguration = session
        config.preloadFeatureFlags = false
        config.sessionReplayConfig.throttleDelay = 0.1
        config.setBeforeSend { event in frames.receive(event); return nil }
        let sdk = PostHogSDK.with(config)
        defer { sdk.close() }

        // Require the recorder to produce a frame before creating any private
        // view. Never reset the collector: first presentation is part of the proof.
        var recorderReady = false
        for _ in 0..<60 {
            container.view.setNeedsLayout(); container.view.layoutIfNeeded()
            window.layer.setNeedsLayout(); window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            if sdk.isSessionReplayActive(), let frame = frames.image,
               try recognizedText(frame).contains("replay ready") {
                recorderReady = true
                break
            }
        }
        XCTAssertTrue(recorderReady, "An actual public frame must precede first private presentation.")
        guard recorderReady else { return }
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
            container.view.setNeedsLayout(); container.view.layoutIfNeeded()
            window.layer.setNeedsLayout(); window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            baseline = capture
            baselineText = try recognizedText(capture)
            if baselineText.contains("maya chen"), baselineText.contains("patio") { break }
        }
        XCTAssertTrue(baselineText.contains("maya chen"), "Baseline must contain the actual fictional participant.")
        XCTAssertTrue(baselineText.contains("patio"), "Baseline must contain the loaded message, not an empty screen.")
        let before = XCTAttachment(image: try XCTUnwrap(baseline))
        before.name = "Private thread — fictional baseline"; before.lifetime = .keepAlways; add(before)

        // A distinct post-hydration control rules out passing on only an old
        // public frame or a loading placeholder from the transition.
        let preLoadedControlFrameCount = frames.images.count
        control.text = "Replay loaded"
        // Commit the changed native sentinel before the SDK's own
        // drawHierarchy(afterScreenUpdates: false) screenshot path runs.
        // Layout alone can leave the label's previously rendered pixels intact.
        let loadedBaseline = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(try recognizedText(loadedBaseline).contains("replay loaded"),
                      "The native post-load control must be rendered before observing SDK frames.")
        var replay: UIImage?
        for _ in 0..<60 {
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            window.layer.setNeedsLayout(); window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            if let frame = frames.image, try recognizedText(frame).contains("replay loaded") {
                replay = frame
                break
            }
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
            let text = try recognizedText(frame)
            for privateToken in ["maya", "chen", "patio", "lovely", "sunny", "afternoon"] {
                XCTAssertFalse(text.contains(privateToken), "Private content must not appear in any captured frame, including startup.")
            }
        }
        XCTAssertTrue(sdk.isSessionReplayActive())
        let loadedReplay = try XCTUnwrap(replay, "Pinned SDK must supply a frame after private content has loaded.")
        let attachment = XCTAttachment(image: loadedReplay)
        attachment.name = "Private thread — actual offline SDK replay"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func recognizedText(_ image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
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

        let frames = ReplayFrameCollector()
        let config = PostHogAnalyticsClient.sdkConfiguration(projectToken: "replay_fixture_\(UUID().uuidString)", host: "https://replay.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ReplayOfflineProtocol.self]
        config.urlSessionConfiguration = session
        config.preloadFeatureFlags = false
        config.sessionReplayConfig.throttleDelay = 0.1
        config.setBeforeSend { event in
            frames.receive(event)
            return nil // Never enqueue or transmit fixture events or images.
        }
        let sdk = PostHogSDK.with(config)
        defer { sdk.close() }

        // Drive genuine layout notifications, which trigger the SDK screenshot recorder.
        for attempt in 0..<60 {
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            // The pinned SDK observes UIView.layoutSublayers(of:).
            window.layer.setNeedsLayout()
            window.layer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            if attempt >= 20, frames.image != nil { break }
        }
        let baseline = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let baselineAttachment = XCTAttachment(image: baseline)
        baselineAttachment.name = "Fictional fixture before replay masking"
        baselineAttachment.lifetime = .keepAlways
        add(baselineAttachment)
        XCTAssertTrue(sdk.isSessionReplayActive())
        let image = try XCTUnwrap(frames.image,
            "The SDK must produce an actual replay frame (foreground: \(scene.activationState == .foregroundActive), fixture key: \(scene.keyWindow === window))")
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

private final class ReplayFrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [UIImage] = []
    var image: UIImage? { lock.lock(); defer { lock.unlock() }; return captured.last }
    var images: [UIImage] { lock.lock(); defer { lock.unlock() }; return captured }

    func receive(_ event: PostHogEvent) {
        guard event.event == "$snapshot", let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] else { return }
        for snapshot in snapshots {
            guard let data = snapshot["data"] as? [String: Any], let frames = data["wireframes"] as? [[String: Any]] else { continue }
            for frame in frames {
                guard let raw = frame["base64"] as? String,
                      let data = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")),
                      let image = UIImage(data: data) else { continue }
                lock.lock(); captured.append(image); lock.unlock()
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
