import XCTest
@testable import Wander

@MainActor final class PlacePlanInvitationTests: XCTestCase {
    func testInvitationLinksRouteToPlansAndSurviveColdStart() throws {
        let token = String(repeating: "ab", count: 24)
        let route = WanderDeepLinkRoute.placePlanInvitation(token: token)
        for raw in ["https://getrec.me/plans/\(token)", "recme://plans/\(token)"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
            var inbox = WanderDeepLinkInbox()
            inbox.receive(url)
            XCTAssertNil(inbox.request(ifSessionValidated: false))
            XCTAssertEqual(inbox.request(ifSessionValidated: true)?.route, route)
        }
        XCTAssertEqual(route.url?.absoluteString, "https://getrec.me/plans/\(token)")
        for raw in ["https://getrec.me/plans/bad", "https://getrec.me/plans/\(token)/extra",
                    "https://getrec.me/plans/\(token)?edit=true", "https://getrec.me/plans/\(token)#edit",
                    "https://elsewhere.example/plans/\(token)", "recme://plans/\(token.uppercased())"] {
            XCTAssertNil(WanderDeepLinkRoute.parse(try XCTUnwrap(URL(string: raw))))
        }
    }

    func testResolverUsesInvitationRPCAndPreservesSharedSnapshot() async throws {
        let transport = InvitationReadTransport()
        let repository = SupabasePlacePlanInvitationRepository(rpc: transport, storage: transport)
        let token = String(repeating: "a", count: 48)
        let resolved = try await repository.invitation(token: token)
        let invitation = try XCTUnwrap(resolved)
        XCTAssertEqual(transport.procedure, "place_plan_preview")
        XCTAssertEqual(transport.token, token)
        XCTAssertEqual(invitation.payload.title, "Let’s go to Smoke Park together")
        XCTAssertEqual(invitation.payload.message, "Coffee on Saturday?")
        XCTAssertEqual(invitation.payload.connection, "Alex’s been and you wanna go")
        XCTAssertEqual(invitation.payload.dateLabel, "Sep 20, 2026 at 10 AM")
        XCTAssertEqual(transport.bucket, "place-plan-previews")
        XCTAssertTrue(invitation.artworkURL.path.hasSuffix("/preview.png"))
    }

    func testUnavailableAndInvalidLinksCannotBecomePlaceProfiles() async throws {
        let transport = InvitationReadTransport()
        let repository = SupabasePlacePlanInvitationRepository(rpc: transport, storage: transport)
        let invalid = try await repository.invitation(token: "bad")
        XCTAssertNil(invalid)
        XCTAssertTrue(transport.procedure.isEmpty)
        transport.response = Data("null".utf8)
        let unavailable = try await repository.invitation(token: String(repeating: "a", count: 48))
        XCTAssertNil(unavailable)
    }

    func testResolverRejectsArtworkOutsideInvitationBucket() async throws {
        let transport = InvitationReadTransport()
        transport.response = Data(String(decoding: transport.response, as: UTF8.self)
            .replacingOccurrences(of: "user_fixture/11111111-2222-4333-8444-555555555555/preview.png", with: "../private/photo.png").utf8)
        let repository = SupabasePlacePlanInvitationRepository(rpc: transport, storage: transport)
        do {
            _ = try await repository.invitation(token: String(repeating: "a", count: 48))
            XCTFail("Invalid attachment path should fail")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .invalidResponse("invalid_plan_artwork"))
        }
        XCTAssertTrue(transport.bucket.isEmpty)
    }
}

@MainActor private final class InvitationReadTransport: RemoteProcedureCalling, RemoteStorageCalling {
    var procedure = ""
    var token = ""
    var bucket = ""
    var response = Data(#"{"title":"Let’s go to Smoke Park together","place_name":"Smoke Park","location":"Los Angeles","sender_name":"Alex","sender_avatar_url":null,"message":"Coffee on Saturday?","connection":"Alex’s been and you wanna go","date_label":"Sep 20, 2026 at 10 AM","image_path":"user_fixture/11111111-2222-4333-8444-555555555555/preview.png"}"#.utf8)
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        procedure = name
        let values = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(params))
        token = values["input_token"] ?? ""
        return try decoder.decode(Value.self, from: response)
    }
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL {
        self.bucket = bucket
        return URL(string: "https://example.test/storage/v1/object/public/\(bucket)/\(path)")!
    }
    func uploadObject(bucket: String, path: String, data: Data, contentType: String, upsert: Bool) async throws { throw WanderRemoteError.notImplemented("read only") }
    func deleteObject(bucket: String, path: String) async throws { throw WanderRemoteError.notImplemented("read only") }
    func downloadObject(bucket: String, path: String) async throws -> Data { throw WanderRemoteError.notImplemented("read only") }
}
