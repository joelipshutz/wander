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

    func testGenericCardDoesNotGrantPrivateActivityAccess() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/cards/activities/00000000-0000-0000-0000-000000000408?card=" + String(repeating: "a", count: 48))!))
        var calls: [String] = []
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            let method = request.url!.lastPathComponent; calls.append(method)
            if method == "share_card_preview" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-public-key")
                return self.response(request, body: "{\"preview_mode\":\"generic\"}")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            return self.response(request, status: 403, body: "{\"message\":\"private backend content\"}")
        })
        do { _ = try await service.preview(route, authenticated: true); XCTFail("A generic card is not an access grant") }
        catch { XCTAssertEqual(error as? ClipError, .unavailable) }
        XCTAssertEqual(calls, ["share_card_preview", "activity_detail"])
    }

    func testGenericCardsOpenEveryLinkKindWithoutAnonymousProtectedReads() async throws {
        let auth = ClipTestAuth()
        let place = ClipTestService().place
        let token = String(repeating: "a", count: 48)
        let cases: [(String, String, [String], Bool)] = [
            ("places/\(place.id)", place.title, ["share_card_preview", "public_web_preview"], false),
            ("lists/00000000-0000-0000-0000-000000000408", "Shared list", ["share_card_preview"], true),
            ("activities/00000000-0000-0000-0000-000000000408", "Shared activity", ["share_card_preview"], true),
            ("profiles/fixture_user", "Shared map", ["share_card_preview", "public_web_preview"], true),
            ("invites/\(token)", "You’re invited to a list on Astir", ["share_card_preview", "public_web_preview"], false)
        ]
        for (path, title, expectedCalls, needsSignIn) in cases {
            let route = try XCTUnwrap(AppClipRoute(url: URL(string: "https://astirmovement.com/cards/\(path)?card=\(token)")!))
            var calls: [String] = []
            let service = ClipService(configuration: configuration, auth: auth, transport: { request in
                let method = request.url!.lastPathComponent; calls.append(method)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-public-key")
                if method == "share_card_preview" {
                    // Legacy fields must not override the current authorized source.
                    return self.response(request, body: """
                        {"preview_mode":"generic","title":"Retired title","image_path":"fixture/00000000-0000-0000-0000-000000000408/preview.png"}
                        """)
                }
                XCTAssertEqual(method, "public_web_preview")
                if route.kind == .place {
                    return self.response(request, body: """
                        {"is_available":true,"place_id":"\(place.id)","title":"Demo Coffee","latitude":0,"longitude":0}
                        """)
                }
                // A private profile/invitation must not reveal source metadata.
                return self.response(request, body: "{\"is_available\":false}")
            })
            let preview = try await service.preview(route, authenticated: false)
            XCTAssertEqual(preview.title, title)
            XCTAssertNil(preview.imageURL)
            XCTAssertNil(preview.subtitle?.range(of: "Retired"))
            XCTAssertEqual(preview.needsSignIn, needsSignIn)
            XCTAssertEqual(preview.places, route.kind == .place ? [place] : [])
            XCTAssertEqual(calls, expectedCalls)
        }
    }

    func testInvalidOrRetiredCardPayloadDoesNotReadProtectedSource() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/cards/activities/00000000-0000-0000-0000-000000000408?card=" + String(repeating: "a", count: 48))!))
        for body in ["null", "{}", "{\"preview_mode\":\"unknown\"}",
                     "{\"title\":\"Retired title\",\"image_path\":\"fixture/00000000-0000-0000-0000-000000000408/preview.png\"}"] {
            var calls: [String] = []
            let service = ClipService(configuration: configuration, auth: auth, transport: { request in
                calls.append(request.url!.lastPathComponent)
                return self.response(request, body: body)
            })
            do { _ = try await service.preview(route, authenticated: true); XCTFail("Invalid cards must be unavailable") }
            catch { XCTAssertEqual(error as? ClipError, .unavailable) }
            XCTAssertEqual(calls, ["share_card_preview"])
        }
    }

    func testGenericActivityCardUsesCurrentAuthorizedPlaceAndNote() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let place = ClipTestService().place
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/cards/activities/00000000-0000-0000-0000-000000000408?card=" + String(repeating: "a", count: 48))!))
        var calls: [String] = []
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            let method = request.url!.lastPathComponent; calls.append(method)
            if method == "share_card_preview" {
                return self.response(request, body: "{\"preview_mode\":\"generic\"}")
            }
            XCTAssertEqual(method, "activity_detail")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            return self.response(request, body: """
                {"note":"Authorized note","place":{"place_id":"\(place.id)","canonical_name":"Demo Coffee","latitude":0,"longitude":0}}
                """)
        })
        let preview = try await service.preview(route, authenticated: true)
        XCTAssertEqual(preview.title, place.title)
        XCTAssertEqual(preview.subtitle, "Authorized note")
        XCTAssertEqual(preview.places, [place])
        XCTAssertNil(preview.imageURL)
        XCTAssertFalse(preview.needsSignIn)
        XCTAssertEqual(calls, ["share_card_preview", "activity_detail"])
    }

    func testListCreatedActivityLoadsAuthorizedListPlaces() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let activityID = "00000000-0000-0000-0000-000000000408"
        let listID = "00000000-0000-0000-0000-000000000409"
        let place = ClipTestService().place
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/cards/activities/\(activityID)?card=" + String(repeating: "a", count: 48))!))
        var calls: [String] = []
        let service = ClipService(configuration: configuration, auth: auth, transport: { request in
            let method = request.url!.lastPathComponent; calls.append(method)
            let parameters = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            switch method {
            case "share_card_preview":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-public-key")
                return self.response(request, body: """
                    {"preview_mode":"generic"}
                    """)
            case "activity_detail":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
                XCTAssertEqual(parameters, ["input_activity_id": activityID])
                return self.response(request, body: """
                    {"event_type":"list_created","place":null,"list":{"id":"\(listID)","name":"Activity snapshot"}}
                    """)
            case "place_list_detail":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
                XCTAssertEqual(parameters, ["input_list_id": listID])
                return self.response(request, body: """
                    {"list":{"id":"\(listID)","name":"Weekend favorites","description":"Places to try"},"items":[{"place_id":"\(place.id)"},{"place_id":"\(place.id)"}]}
                    """)
            case "public_web_preview":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-public-key")
                XCTAssertEqual(parameters, ["input_kind": "place", "input_identifier": place.id])
                return self.response(request, body: """
                    {"is_available":true,"place_id":"\(place.id)","title":"Demo Coffee","latitude":0,"longitude":0}
                    """)
            default:
                XCTFail("Unexpected RPC: \(method)")
                return self.response(request, status: 400, body: "{}")
            }
        })
        let preview = try await service.preview(route, authenticated: true)
        XCTAssertEqual(preview.title, "Weekend favorites")
        XCTAssertEqual(preview.subtitle, "Places to try")
        XCTAssertEqual(preview.places, [place])
        XCTAssertNil(preview.imageURL)
        XCTAssertFalse(preview.needsSignIn)
        XCTAssertEqual(calls, ["share_card_preview", "activity_detail", "place_list_detail", "public_web_preview"])
    }

    func testListCreatedActivityCannotReadUnauthorizedList() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/activities/00000000-0000-0000-0000-000000000408")!))
        // Permission can disappear after activity_detail succeeds. A denied or
        // RLS-filtered list must never fall back to the activity's projection.
        for (status, body) in [(403, "{\"message\":\"private backend content\"}"), (200, "null")] {
            var calls: [String] = []
            let service = ClipService(configuration: configuration, auth: auth, transport: { request in
                let method = request.url!.lastPathComponent; calls.append(method)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
                if method == "activity_detail" {
                    return self.response(request, body: """
                        {"event_type":"list_created","place":null,"list":{"id":"00000000-0000-0000-0000-000000000409","name":"Hidden list"}}
                        """)
                }
                XCTAssertEqual(method, "place_list_detail")
                return self.response(request, status: status, body: body)
            })
            do { _ = try await service.preview(route, authenticated: true); XCTFail("List access must be authorized separately") }
            catch { XCTAssertEqual(error as? ClipError, .unavailable) }
            XCTAssertEqual(calls, ["activity_detail", "place_list_detail"])
        }
    }

    func testMalformedListCreatedActivityDoesNotRequestList() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let route = try XCTUnwrap(AppClipRoute(url: URL(string:
            "https://astirmovement.com/activities/00000000-0000-0000-0000-000000000408")!))
        let list = "{\"id\":\"00000000-0000-0000-0000-000000000409\"}"
        for body in [
            "null",
            "{\"event_type\":\"list_created\",\"place\":null,\"list\":null}",
            "{\"event_type\":\"list_created\",\"place\":null,\"list\":{\"id\":\"invalid\"}}",
            "{\"event_type\":\"place_been\",\"place\":null,\"list\":\(list)}",
            "{\"event_type\":\"list_created\",\"place\":{},\"list\":\(list)}"
        ] {
            var calls: [String] = []
            let service = ClipService(configuration: configuration, auth: auth, transport: { request in
                calls.append(request.url!.lastPathComponent)
                return self.response(request, body: body)
            })
            do { _ = try await service.preview(route, authenticated: true); XCTFail("Malformed activity must not resolve a list") }
            catch { XCTAssertEqual(error as? ClipError, .unavailable) }
            XCTAssertEqual(calls, ["activity_detail"])
        }
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
