import XCTest
import PostHog
@testable import AstirClip

@MainActor
final class ClipServiceTests: XCTestCase {
    private let configuration = WanderBackendConfiguration(clerkPublishableKey: nil, clerkFrontendAPI: nil,
        supabaseURL: URL(string: "https://clip-fixture.invalid"), supabasePublishableKey: "synthetic-public-key")

    func testTokenAccountChangePreventsAnyRequest() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        auth.onToken = { auth.state = .signedOut }
        var requests = 0
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            requests += 1
            return self.response(request, body: "{}")
        })
        do { _ = try await service.save(ClipTestService().place); XCTFail("Account drift must reject save") }
        catch { XCTAssertEqual(error as? ClipError, .signIn) }
        XCTAssertEqual(requests, 0)
    }

    func testResponseFromPreviousAccountIsDiscarded() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            auth.state = .signedOut
            return self.response(request, body: "[]")
        })
        do { _ = try await service.profile(); XCTFail("Stale response must be discarded") }
        catch { XCTAssertEqual(error as? ClipError, .signIn) }
    }

    func testPublishedImageDoesNotGrantPrivateActivityAccess() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/cards/activities/00000000-0000-0000-0000-000000000408?card=" + String(repeating: "a", count: 48))!))
        var calls: [String] = []
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            let method = request.url!.lastPathComponent; calls.append(method)
            if method == "share_card_preview" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-public-key")
                return self.response(request, body: "{\"title\":\"Shared preview\",\"image_path\":\"fixture/00000000-0000-0000-0000-000000000408/preview.png\"}")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            return self.response(request, status: 403, body: "{\"message\":\"private backend content\"}")
        })
        do { _ = try await service.preview(route, authenticated: true); XCTFail("Image is not an access grant") }
        catch { XCTAssertEqual(error as? ClipError, .unavailable) }
        XCTAssertEqual(calls, ["share_card_preview", "activity_detail"])
    }

    func testSaveSendsCanonicalIDAndNeverCallerIdentityOrPlaceContent() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let place = ClipTestService().place
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            XCTAssertEqual(request.url!.lastPathComponent, "save_app_clip_place")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String], ["input_place_id": place.id])
            return self.response(request, body: "{\"created\":false}")
        })
        let created = try await service.save(place)
        XCTAssertFalse(created)
    }

    func testClipDisablesReplayAndAutomaticCapture() {
        let config = PostHogAnalyticsClient.sdkConfiguration(projectToken: "synthetic-token",
            host: "https://analytics-fixture.invalid", captureReplay: false)
        XCTAssertFalse(config.sessionReplay)
        XCTAssertFalse(config.enableSwizzling)
        XCTAssertFalse(config.captureScreenViews)
        XCTAssertFalse(config.captureElementInteractions)
        XCTAssertFalse(config.captureApplicationLifecycleEvents)
        XCTAssertFalse(config.surveys)
        XCTAssertFalse(config.errorTrackingConfig.autoCapture)
        XCTAssertFalse(config.setDefaultPersonProperties)
    }

    private func response(_ request: URLRequest, status: Int = 200, body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
