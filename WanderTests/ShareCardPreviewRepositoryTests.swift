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

    func testCanonicalPlaceStillPublishesItsArtworkAndExactTarget() async throws {
        let transport = CardTransport()
        let id = UUID().uuidString
        let content = try XCTUnwrap(WanderShareContent.place(serverID: id, name: "Sample place", message: ""))
        var renderCount = 0
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: repository(transport)) {
            renderCount += 1
            return self.png
        }
        XCTAssertEqual(renderCount, 1)
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
            XCTAssertTrue(transport.deleted)
        }
        transport.fail = false
        let shared = try await ShareCardLinkPreparation.prepare(content: content, repository: repo) { self.png }
        XCTAssertNotEqual(shared.item, content.item)
    }

    func testArtworkFailureNeverUploadsAndRetainsItsSpecificError() async throws {
        let transport = CardTransport()
        let content = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!
        do {
            _ = try await ShareCardLinkPreparation.prepare(content: content, repository: repository(transport)) {
                throw ShareCardPreparationError.artwork
            }
            XCTFail("Expected rendering failure")
        } catch { XCTAssertEqual(error as? ShareCardPreparationError, .artwork) }
        XCTAssertTrue(transport.path.isEmpty)
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

    func testCancellationDuringArtworkNeverPublishes() async {
        let transport = CardTransport()
        do {
            _ = try await ShareCardLinkPreparation.prepare(
                content: .profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!,
                repository: repository(transport)
            ) { throw CancellationError() }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(transport.path.isEmpty)
    }

    func testCancelledArtworkDoesNotBecomeAVisibleRenderingFailure() async {
        let transport = CardTransport()
        let task = Task {
            try await ShareCardLinkPreparation.prepare(
                content: .profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!,
                repository: repository(transport)
            ) {
                withUnsafeCurrentTask { $0?.cancel() }
                throw ShareCardPreparationError.artwork
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
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
            XCTAssertEqual(shared.path, "/cards" + original.path)
            // Website-only wrapper; the recipient card opens the original route.
            XCTAssertNil(WanderDeepLinkRoute.parse(shared))
            var inbox = WanderDeepLinkInbox()
            inbox.receive(original)
            XCTAssertNil(inbox.request(ifSessionValidated: false))
            XCTAssertEqual(inbox.request(ifSessionValidated: true)?.route, route)
            for query in ["card=x", "card=\(token)&card=\(token)", "card=\(token)&edit=true"] {
                XCTAssertNil(WanderDeepLinkRoute.parse(URL(string: original.absoluteString + "?" + query)!))
            }
        }
    }

    func testPublicationUploadsOnceAndReturnsOneURLWithoutPromotionalTextOrAttachment() async throws {
        let transport = CardTransport()
        let repo = repository(transport)
        let original = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan Example", handle: "ryan")!
        let shared = try await repo.publish(content: original, previewPNG: png)
        XCTAssertEqual(transport.bucket, "share-card-previews")
        XCTAssertTrue(transport.path.hasPrefix("user_ryan/"))
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

    func testFailedPublicationCleansUpArtworkAndNeverReturnsGenericURL() async {
        let transport = CardTransport()
        transport.fail = true
        do {
            _ = try await repository(transport).publish(content: .profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!, previewPNG: png)
            XCTFail("Publication must fail")
        } catch { XCTAssertTrue(transport.deleted) }
    }

    func testInvalidTokenCleansUpAndInvalidImageNeverUploads() async {
        let transport = CardTransport()
        transport.token = "../evil"
        let content = WanderShareContent.profile(serverID: "user_ryan", displayName: "Ryan", handle: "ryan")!
        do { _ = try await repository(transport).publish(content: content, previewPNG: png); XCTFail() }
        catch { XCTAssertTrue(transport.deleted) }
        let invalid = CardTransport()
        do { _ = try await repository(invalid).publish(content: content, previewPNG: Data()); XCTFail() }
        catch { XCTAssertTrue(invalid.path.isEmpty) }
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
