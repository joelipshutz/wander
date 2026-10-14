import XCTest
import SwiftUI
import PostHog
@testable import Wander

/// Exercises the pinned SDK's real screenshot path, entirely offline with fictional data.
final class ReplayMaskingTests: XCTestCase {
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

        // Stop driving layouts and allow any pending SDK capture work to finish.
        // Keep the fixture and SDK alive, and yield the main actor during the bounded wait.
        let driveEndDiagnostics = frames.diagnosticSummary
        let drainStartedAt = ProcessInfo.processInfo.systemUptime
        let drainDeadline = drainStartedAt + 30
        while frames.image == nil {
            let remaining = drainDeadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            try await Task.sleep(for: .seconds(min(0.1, remaining)))
        }
        let drainElapsed = ProcessInfo.processInfo.systemUptime - drainStartedAt
        let drainEndDiagnostics = frames.diagnosticSummary
        let replayImage = frames.image
        let captureDiagnostics = "drive end [\(driveEndDiagnostics)]; drain elapsed: \(String(format: "%.3f", drainElapsed))s; drain end [\(drainEndDiagnostics)]"
        let diagnosticsAttachment = XCTAttachment(string: captureDiagnostics)
        diagnosticsAttachment.name = "Replay capture aggregate timing diagnostics"
        diagnosticsAttachment.lifetime = .keepAlways
        add(diagnosticsAttachment)

        let baseline = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let baselineAttachment = XCTAttachment(image: baseline)
        baselineAttachment.name = "Fictional fixture before replay masking"
        baselineAttachment.lifetime = .keepAlways
        add(baselineAttachment)
        XCTAssertTrue(sdk.isSessionReplayActive())
        let image = try XCTUnwrap(replayImage,
            "The SDK must produce an actual replay frame (foreground: \(scene.activationState == .foregroundActive), fixture key: \(scene.keyWindow === window), \(captureDiagnostics))")
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
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var latest: UIImage?
    private var snapshotEventCount = 0
    private var wireframeCount = 0
    private var encodedImageCount = 0
    private var decodedImageCount = 0
    private var firstSnapshotElapsed: TimeInterval?
    private var firstDecodedImageElapsed: TimeInterval?
    var image: UIImage? { lock.lock(); defer { lock.unlock() }; return latest }
    var diagnosticSummary: String {
        lock.lock()
        defer { lock.unlock() }
        let firstSnapshot = firstSnapshotElapsed.map { String(format: "%.3fs", $0) } ?? "none"
        let firstDecodedImage = firstDecodedImageElapsed.map { String(format: "%.3fs", $0) } ?? "none"
        return "snapshot events: \(snapshotEventCount), wireframes: \(wireframeCount), encoded images: \(encodedImageCount), decoded images: \(decodedImageCount), first snapshot after: \(firstSnapshot), first decoded image after: \(firstDecodedImage)"
    }

    func receive(_ event: PostHogEvent) {
        guard event.event == "$snapshot" else { return }
        lock.lock()
        snapshotEventCount += 1
        if firstSnapshotElapsed == nil {
            firstSnapshotElapsed = ProcessInfo.processInfo.systemUptime - startedAt
        }
        lock.unlock()
        var receivedWireframes = 0
        var receivedImages = 0
        var decodedImages = 0
        var newestImage: UIImage?
        defer {
            lock.lock()
            wireframeCount += receivedWireframes
            encodedImageCount += receivedImages
            decodedImageCount += decodedImages
            if let newestImage {
                latest = newestImage
                if firstDecodedImageElapsed == nil {
                    firstDecodedImageElapsed = ProcessInfo.processInfo.systemUptime - startedAt
                }
            }
            lock.unlock()
        }
        guard let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] else { return }
        for snapshot in snapshots {
            guard let data = snapshot["data"] as? [String: Any], let frames = data["wireframes"] as? [[String: Any]] else { continue }
            receivedWireframes += frames.count
            for frame in frames {
                guard let raw = frame["base64"] as? String else { continue }
                receivedImages += 1
                guard let data = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")),
                      let image = UIImage(data: data) else { continue }
                decodedImages += 1
                newestImage = image
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
