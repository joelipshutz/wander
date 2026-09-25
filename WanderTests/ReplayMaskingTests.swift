import XCTest
import SwiftUI
import PostHog
@testable import Wander

/// Exercises the pinned SDK's real screenshot path, entirely offline with fictional data.
final class ReplayMaskingTests: XCTestCase {
    @MainActor
    func testReadableContentAndCredentialMaskingInActualReplayImage() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ReplayPrivacyFixture())
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            originalWindow?.makeKeyAndVisible()
        }

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
        let image = try XCTUnwrap(frames.image, "The SDK must produce an actual replay frame")
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
    private var latest: UIImage?
    var image: UIImage? { lock.lock(); defer { lock.unlock() }; return latest }

    func receive(_ event: PostHogEvent) {
        guard event.event == "$snapshot", let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] else { return }
        for snapshot in snapshots {
            guard let data = snapshot["data"] as? [String: Any], let frames = data["wireframes"] as? [[String: Any]] else { continue }
            for frame in frames {
                guard let raw = frame["base64"] as? String,
                      let data = Data(base64Encoded: String(raw.split(separator: ",").last ?? "")),
                      let image = UIImage(data: data) else { continue }
                lock.lock(); latest = image; lock.unlock()
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
