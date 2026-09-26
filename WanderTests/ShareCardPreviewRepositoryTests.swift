import XCTest
import UIKit
@testable import Wander

@MainActor
final class ShareCardPreviewRepositoryTests: XCTestCase {
    func testExternalPlaceLinkSkipsArtworkAndPublicationEvenWithoutARepository() async throws {
        let url = try XCTUnwrap(PlaceExternalLinks.directionsAction(
            placeName: "Sample place", latitude: 0, longitude: 0)?.url)
        let content = WanderShareContent.place(item: url, name: "Sample place", message: "Unused caption")
        // This is the URL supplied by the unsaved-place screen. It cannot be
        // sent to the Astir card publisher because it has no Astir entity ID.
        XCTAssertNil(ShareCardLinkTarget(url: url))
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: nil) {
            XCTFail("Copying a Maps link must not depend on rendering an image")
            throw ShareCardPreparationError.artwork
        }
        XCTAssertEqual(shared.items, [url])
        XCTAssertEqual(shared.messageBody, url.absoluteString)
        XCTAssertEqual(shared.message, "")
    }

    func testCanonicalLinkPublishesExactTargetWithoutRenderingPrivateArtwork() async throws {
        let transport = CardTransport()
        let id = UUID().uuidString
        let content = try XCTUnwrap(WanderShareContent.place(serverID: id, name: "Sample place", message: ""))
        var renderCount = 0
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: repository(transport)) {
            renderCount += 1
            return self.png
        }
        XCTAssertEqual(renderCount, 0)
        XCTAssertEqual(transport.params["input_kind"], "place")
        XCTAssertEqual(transport.params["input_identifier"]?.lowercased(), id.lowercased())
        XCTAssertEqual(shared.items.count, 1)
        XCTAssertEqual(shared.item.path, "/cards" + content.item.path)
    }

    func testPublicationFailureIsNotAnArtworkErrorAndCanBeRetried() async throws {
        let transport = CardTransport()
        transport.fail = true
        let repo = repository(transport)
        let content = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!
        do {
            _ = try await ShareCardLinkPreparation.prepare(content: content, repository: repo) { self.png }
            XCTFail("A canonical link must not silently fall back to a generic URL")
        } catch {
            XCTAssertEqual(error as? ShareCardPreparationError, .session)
            XCTAssertFalse(transport.deleted)
        }
        transport.fail = false
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: repo) { self.png }
        XCTAssertNotEqual(shared.item, content.item)
    }

    func testLinkPublicationNeverExecutesThePrivateArtworkClosure() async throws {
        let transport = CardTransport()
        let content = WanderShareContent.profile(serverID: "user_ryan", displayName: "Private name", handle: "private")!
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: repository(transport)) {
            XCTFail("Protected artwork must stay local")
            throw ShareCardPreparationError.artwork
        }
        XCTAssertTrue(transport.path.isEmpty)
        XCTAssertEqual(transport.params["input_title"], "Shared on Astir")
        XCTAssertEqual(shared.subject, "Shared on Astir")
    }

    func testMissingPublisherAndUnsupportedURLsFailBeforeRendering() async {
        for (url, expected): (URL, ShareCardPreparationError) in [
            (WanderDeepLinkRoute.sharedProfile(profileID: "user_ryan").url!, .configuration),
            (URL(string: "https://www.google.com.evil.example/maps/dir/?api=1")!, .unavailable),
            (URL(string: "https://www.google.com/unrelated")!, .unavailable),
            (URL(string: "http://www.google.com/maps/dir/")!, .unavailable)
        ] {
            do {
                _ = try await ShareCardLinkPreparation.prepare(
                    content: .place(item: url, name: "Sample", message: ""), repository: nil
                ) {
                    XCTFail("Invalid or unconfigured publication must not render")
                    return self.png
                }
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? ShareCardPreparationError, expected) }
        }
    }

    func testCancelledPublicationDoesNotPublishOrUploadArtwork() async {
        let transport = CardTransport()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ShareCardLinkPreparation.prepare(
                content: .profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!,
                repository: repository(transport)
            ) { XCTFail("Cancelled work must not render"); return self.png }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(transport.params.isEmpty)
        XCTAssertTrue(transport.path.isEmpty)
    }

    func testPublicationMessagesClassifyFailuresWithoutExposingRawPayloads() {
        XCTAssertEqual(ShareCardPreparationError.publicationFailure(URLError(.notConnectedToInternet)), .connection)
        XCTAssertEqual(ShareCardPreparationError.publicationFailure(WanderRemoteError.notAuthenticated), .session)
        XCTAssertEqual(ShareCardPreparationError.publicationFailure(WanderRemoteError.notConfigured), .configuration)
        let failure = ShareCardPreparationError.publicationFailure(WanderRemoteError.invalidResponse("private response"))
        XCTAssertEqual(failure, .publication)
        XCTAssertFalse(failure.message.contains("private response"))
        XCTAssertNotEqual(failure.title, ShareCardPreparationError.artwork.title)
    }

    func testPublishedLinksPreserveEveryExactDestinationAndRejectOtherQueries() throws {
        let uuid = UUID().uuidString
        let token = String(repeating: "a", count: 48)
        let routes: [WanderDeepLinkRoute] = [.sharedProfile(profileID: "user_ryan"), .sharedPlace(placeID: uuid),
            .sharedList(listID: uuid), .sharedActivity(activityID: uuid), .listInvite(token: token)]
        for route in routes {
            let original = try XCTUnwrap(route.url)
            let shared = try XCTUnwrap(ShareCardLinkTarget.link(original, token: token))
            XCTAssertEqual(shared.host, "astirmovement.com")
            XCTAssertEqual(shared.path, "/cards" + original.path)
            XCTAssertEqual(WanderDeepLinkRoute.parse(shared), route)
            XCTAssertNil(ShareCardLinkTarget(url: shared), "A published wrapper must not be published again")
            var inbox = WanderDeepLinkInbox()
            inbox.receive(shared)
            XCTAssertNil(inbox.request(ifSessionValidated: false))
            let request = try XCTUnwrap(inbox.request(ifSessionValidated: true))
            XCTAssertEqual(request.route, route)
            XCTAssertEqual(request.route.url, original, "The preview token must not enter native navigation")
            inbox.consume(request.id)
            XCTAssertNil(inbox.pendingRequest)
            for query in ["card=x", "card=\(token)&card=\(token)", "card=\(token)&edit=true"] {
                XCTAssertNil(WanderDeepLinkRoute.parse(URL(string: original.absoluteString + "?" + query)!))
                XCTAssertNil(WanderDeepLinkRoute.parse(URL(string: "https://astirmovement.com/cards" + original.path + "?" + query)!))
            }
        }
    }

    func testLegacyAndWWWTargetsPublishCanonicalAstirLinksWithoutChangingEncodedIdentity() throws {
        let token = String(repeating: "a", count: 48)
        for host in ["getrec.me", "astirmovement.com", "www.astirmovement.com"] {
            let original = try XCTUnwrap(URL(string: "https://\(host)/profiles/user%2F%E6%9D%B1%E4%BA%AC"))
            XCTAssertEqual(ShareCardLinkTarget(url: original)?.identifier, "user/東京")
            let shared = try XCTUnwrap(ShareCardLinkTarget.link(original, token: token))
            XCTAssertEqual(shared.absoluteString,
                           "https://astirmovement.com/cards/profiles/user%2F%E6%9D%B1%E4%BA%AC?card=\(token)")
            let legacy = try XCTUnwrap(URL(string: shared.absoluteString.replacingOccurrences(
                of: "https://astirmovement.com", with: "https://getrec.me")))
            XCTAssertEqual(WanderDeepLinkRoute.parse(legacy), .sharedProfile(profileID: "user/東京"))
        }
    }

    func testPublisherRejectsUnsupportedHostsAndAlreadyPublishedLinks() throws {
        let token = String(repeating: "a", count: 48)
        for raw in ["https://astirmovement.com.evil.example/profiles/user",
                    "https://getrec.me.evil.example/profiles/user",
                    "https://user@astirmovement.com/profiles/user",
                    "https://astirmovement.com:8443/profiles/user",
                    "https://astirmovement.com/profiles/user?private=yes",
                    "https://astirmovement.com/cards/profiles/user?card=\(token)"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(ShareCardLinkTarget(url: url))
            XCTAssertNil(ShareCardLinkTarget.link(url, token: token))
        }
    }

    func testCardLinksRejectMalformedRoutesAndKeepPendingValidDestination() throws {
        let id = "40000000-0000-0000-0000-000000000001"
        let token = String(repeating: "a", count: 48)
        let base = "https://astirmovement.com/cards/places/\(id)"
        let valid = try XCTUnwrap(URL(string: base + "?card=" + token))
        var inbox = WanderDeepLinkInbox()
        inbox.receive(valid)
        let request = try XCTUnwrap(inbox.pendingRequest)
        for raw in [
            base, base + "?", base + "?card=", base + "?card=" + String(token.dropLast()),
            base + "?card=" + token + "%0A",
            base + "?card=" + token.uppercased(), base + "?card=" + token + "#extra",
            base + "/?card=" + token, base + "/extra?card=" + token,
            "https://astirmovement.com/cards/places/not-a-uuid?card=" + token,
            "https://astirmovement.com/cards/plans/\(token)?card=" + token,
            "https://astirmovement.com/cards/unknown/\(id)?card=" + token,
            "https://astirmovement.com/cards/cards/places/\(id)?card=" + token,
            "https://astirmovement.com.evil.example/cards/places/\(id)?card=" + token,
            "https://astirmovement.com:8443/cards/places/\(id)?card=" + token,
            "https://user@getrec.me/cards/places/\(id)?card=" + token,
            "http://getrec.me/cards/places/\(id)?card=" + token,
            "recme://cards/places/\(id)?card=" + token
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(WanderDeepLinkRoute.parse(url), raw)
            inbox.receive(url)
            XCTAssertEqual(inbox.pendingRequest, request)
        }
    }

    func testCardLinkAnalyticsKeepCanonicalCategoryWithoutPreviewTokenOrIdentity() throws {
        let id = "40000000-0000-0000-0000-000000000001"
        let token = String(repeating: "a", count: 48)
        let original = try XCTUnwrap(WanderDeepLinkRoute.sharedPlace(placeID: id).url)
        let shared = try XCTUnwrap(ShareCardLinkTarget.link(original, token: token))
        let properties = try XCTUnwrap(AcquisitionAttribution(url: shared)).properties
        XCTAssertEqual(properties, ["route": "place", "has_campaign": "false"])
        XCTAssertFalse(properties.values.contains { $0.contains(id) || $0.contains(token) })
    }

    func testPublicationNeverUploadsAndReturnsOneURLWithoutPrivateTextOrAttachment() async throws {
        let transport = CardTransport()
        let repo = repository(transport)
        let original = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan Example", handle: "ryan")!
        let shared = try await repo.publish(content: original, previewPNG: png)
        XCTAssertTrue(transport.bucket.isEmpty)
        XCTAssertTrue(transport.path.isEmpty)
        XCTAssertEqual(transport.params["input_image_path"], "")
        XCTAssertEqual(shared.subject, "Shared on Astir")
        XCTAssertEqual(transport.params["input_kind"], "profile")
        XCTAssertEqual(transport.params["input_identifier"], "user_ryan")
        XCTAssertEqual(shared.items, [shared.item])
        XCTAssertEqual(shared.messageBody, shared.item.absoluteString)
        XCTAssertEqual(shared.message, "")
        XCTAssertTrue(shared.item.absoluteString.contains("?card="))
        let source = WanderShareActivityItemSource(url: shared.item, subject: shared.subject)
        let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)
        XCTAssertEqual(source.activityViewController(controller, itemForActivityType: .message) as? URL, shared.item)
        XCTAssertFalse(transport.deleted)
    }

    func testFailedAuthorizationNeverReturnsAShareLink() async {
        let transport = CardTransport()
        transport.fail = true
        do {
            _ = try await repository(transport).publish(content: .profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!, previewPNG: png)
            XCTFail("Publication must fail")
        } catch { XCTAssertFalse(transport.deleted) }
    }

    func testInvalidTokenIsRejectedAndArtworkIsNeverUploaded() async {
        let transport = CardTransport()
        transport.token = "../evil"
        let content = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!
        do { _ = try await repository(transport).publish(content: content, previewPNG: png); XCTFail() }
        catch { XCTAssertFalse(transport.deleted) }
        let invalid = CardTransport()
        do { _ = try await repository(invalid).publish(content: content, previewPNG: Data()) }
        catch { XCTFail("Generic links need no image: \(error)") }
        XCTAssertTrue(invalid.path.isEmpty)
    }

    private var png: Data { UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.pngData()! }
    private func repository(_ transport: CardTransport) -> SupabaseShareCardPreviewRepository {
        SupabaseShareCardPreviewRepository(rpc: transport, storage: transport,
            authSession: PreviewAuthSessionProvider(state: .signedIn(AuthSession(userID: "user_ryan", displayName: "Ryan", handle: "ryan"))))
    }
}

@MainActor private final class CardTransport: RemoteProcedureCalling, RemoteStorageCalling {
    var bucket = ""
    var path = ""
    var params: [String: String] = [:]
    var fail = false
    var deleted = false
    var token = String(repeating: "a", count: 48)
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        XCTAssertEqual(name, "create_share_card_preview")
        self.params = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(params))
        if fail { throw WanderRemoteError.notAuthenticated }
        return try decoder.decode(Value.self, from: JSONEncoder().encode(["token": token]))
    }
    func uploadObject(bucket: String, path: String, data: Data, contentType: String, upsert: Bool) async throws {
        self.bucket = bucket; self.path = path
        XCTAssertFalse(upsert); XCTAssertEqual(contentType, "image/png")
    }
    func deleteObject(bucket: String, path: String) async throws { deleted = true; XCTAssertEqual(path, self.path) }
    func downloadObject(bucket: String, path: String) async throws -> Data { throw WanderRemoteError.notConfigured }
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL { throw WanderRemoteError.notConfigured }
}
