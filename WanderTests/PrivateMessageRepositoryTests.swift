import XCTest
@testable import Wander

@MainActor
final class PrivateMessageRepositoryTests: XCTestCase {
    func testRetryKeepsClientIdentityAndOnlyAcknowledgmentProducesMessage() async throws {
        let transport = PrivateMessageTestTransport()
        let repository = SupabasePrivateMessageRepository(rpc: transport)
        let conversation = UUID(), client = UUID(), message = UUID(), contextID = UUID()
        transport.response = try messageResponse(id: message, conversation: conversation, client: client)
        let context = PrivateMessageContext(kind: .activity, id: contextID.uuidString, title: "Client title is not trusted")
        transport.failure = URLError(.timedOut)
        do {
            _ = try await repository.send(conversationID: conversation, body: "  Hello  ", clientID: client, context: context)
            XCTFail("A timeout must not return a sent message")
        } catch { XCTAssertEqual(error as? PrivateMessageError, .unavailable) }
        let original = try XCTUnwrap(transport.parameters)
        transport.failure = nil
        let sent = try await repository.send(conversationID: conversation, body: "  Hello  ", clientID: client, context: context)
        XCTAssertEqual(sent.id, message)
        XCTAssertEqual(sent.senderID, "authenticated_sender")
        XCTAssertEqual(sent.conversationID, conversation)
        XCTAssertEqual(sent.clientID, client)
        XCTAssertEqual(transport.parameters?["input_client_id"] as? String, original["input_client_id"] as? String)
        XCTAssertEqual(transport.parameters?["input_body"] as? String, "Hello")
        XCTAssertNil(transport.parameters?["sender_id"])
        XCTAssertNil(transport.parameters?["title"])
        XCTAssertEqual(transport.parameters?.count, 5)
    }

    func testPaginationPreservesMicrosecondsAndClampsRequests() async throws {
        let transport = PrivateMessageTestTransport()
        let repository = SupabasePrivateMessageRepository(rpc: transport)
        let id = UUID()
        transport.response = Data("{\"items\":[],\"nextCursor\":{\"timestamp\":\"2026-10-10T12:13:14.123456+00:00\",\"id\":\"\(id)\"}}".utf8)
        let page = try await repository.messages(conversationID: UUID(), before: nil, limit: 500)
        XCTAssertEqual(transport.parameters?["input_limit"] as? Int, 50)
        XCTAssertEqual(page.nextCursor?.timestamp, "2026-10-10T12:13:14.123456+00:00")
        _ = try await repository.messages(conversationID: UUID(), before: page.nextCursor, limit: 0)
        XCTAssertEqual(transport.parameters?["input_before_at"] as? String, "2026-10-10T12:13:14.123456+00:00")
        XCTAssertEqual(transport.parameters?["input_before_id"] as? String, id.uuidString)
        XCTAssertEqual(transport.parameters?["input_limit"] as? Int, 1)
        let inbox = try await repository.inbox(before: nil, limit: 20)
        XCTAssertEqual(inbox.nextCursor?.id, id)
        _ = try await repository.inbox(before: inbox.nextCursor, limit: 20)
        XCTAssertEqual(transport.procedure, "private_message_inbox")
        XCTAssertEqual(transport.parameters?["input_before_at"] as? String, page.nextCursor?.timestamp)
    }

    func testBodyValidationMatchesPostgresScalarsBeforeNetwork() async throws {
        let transport = PrivateMessageTestTransport()
        let repository = SupabasePrivateMessageRepository(rpc: transport)
        for invalid in [" \n\t ", String(repeating: "a", count: 2_001), String(repeating: "e\u{301}", count: 1_001), "hello\0"] {
            do {
                _ = try await repository.send(conversationID: UUID(), body: invalid, clientID: UUID(), context: nil)
                XCTFail("Invalid body must fail before transport")
            } catch { XCTAssertEqual(error as? PrivateMessageError, .invalidBody) }
        }
        XCTAssertEqual(transport.callCount, 0)
        transport.response = try messageResponse(id: UUID(), conversation: UUID(), client: UUID())
        _ = try await repository.send(conversationID: UUID(), body: String(repeating: "e\u{301}", count: 1_000), clientID: UUID(), context: nil)
        XCTAssertEqual(transport.callCount, 1)
    }

    func testContextContainsOnlyReferenceAndReadReceiptUsesVisibleTarget() async throws {
        let transport = PrivateMessageTestTransport()
        let repository = SupabasePrivateMessageRepository(rpc: transport)
        let conversation = UUID(), source = UUID(), message = UUID()
        transport.response = Data("{\"id\":\"\(conversation)\",\"participant\":{\"id\":\"friend\",\"displayName\":\"Friend\",\"handle\":\"friend\",\"avatarURL\":null},\"updatedAt\":\"2026-10-10T00:00:00Z\",\"unreadCount\":0,\"lastMessageAt\":null,\"lastMessagePreview\":null}".utf8)
        let summary = try await repository.startReply(recipientID: "friend", context: .init(kind: .place, id: source.uuidString, title: "Private local title"))
        XCTAssertEqual(summary.id, conversation)
        XCTAssertEqual(transport.parameters?.count, 3)
        XCTAssertEqual(transport.parameters?["input_context_id"] as? String, source.uuidString)
        XCTAssertEqual(transport.parameters?["input_context_kind"] as? String, "place")
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: transport.parameters ?? [:]), encoding: .utf8)?.contains("Private local title") ?? true)
        transport.response = Data("{}".utf8)
        try await repository.markRead(conversationID: conversation, throughMessageID: message)
        XCTAssertEqual(transport.procedure, "private_message_mark_read")
        XCTAssertEqual(transport.parameters?["input_conversation_id"] as? String, conversation.uuidString)
        XCTAssertEqual(transport.parameters?["input_through_message_id"] as? String, message.uuidString)
    }

    func testErrorsAreSafeAndCancellationIsPreserved() async throws {
        let transport = PrivateMessageTestTransport()
        let repository = SupabasePrivateMessageRepository(rpc: transport)
        transport.failure = WanderRemoteError.invalidResponse("private backend payload")
        do { _ = try await repository.inbox(before: nil, limit: 20); XCTFail() }
        catch { XCTAssertEqual(error as? PrivateMessageError, .unavailable) }
        transport.failure = PrivateMessageError.rateLimited
        do { _ = try await repository.inbox(before: nil, limit: 20); XCTFail() }
        catch { XCTAssertEqual(error as? PrivateMessageError, .rateLimited) }
        transport.failure = CancellationError()
        do { _ = try await repository.inbox(before: nil, limit: 20); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func messageResponse(id: UUID, conversation: UUID, client: UUID) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "conversationID": conversation.uuidString,
            "senderID": "authenticated_sender", "clientID": client.uuidString,
            "body": "Hello", "sentAt": "2026-10-10T12:13:14.123456Z",
            "context": NSNull(), "recipientReadAt": NSNull()
        ])
    }
}

@MainActor
private final class PrivateMessageTestTransport: RemoteProcedureCalling {
    var procedure = ""
    var parameters: [String: Any]?
    var response = Data()
    var failure: (any Error)?
    var callCount = 0

    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        callCount += 1
        procedure = name
        parameters = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
        if let failure { throw failure }
        return try decoder.decode(Value.self, from: response)
    }
}
