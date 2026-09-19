import XCTest
import UIKit
@testable import Wander

@MainActor
final class ShareCardPreviewRepositoryTests: XCTestCase {
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
