import Foundation
import XCTest
@testable import Wander

@MainActor
final class RemoteSnapshotDecoderTests: XCTestCase {
    func testWorkerMatchesLegacyDatesJSONValuesAndArrayOrder() async throws {
        let data = Data(#"{"dates":["2026-07-21T21:10:46.447909+00:00","2026-07-21T14:10:46-07:00","1970-01-01T00:00:00Z","1969-12-31T23:59:59.123Z"],"optional":null,"value":{"text":"é 🗺️","rows":[null,true,-0.0,12.25,"repeat","repeat"]}}"#.utf8)
        let expected = try RemoteDecoding.decoder.decode(DateProbe.self, from: data)
        let worker = RemoteSnapshotDecoder()
        for _ in 0..<3 {
            let actual = try await worker.decode(DateProbe.self, from: data)
            XCTAssertEqual(actual, expected)
            if case .object(let object) = actual.value, let rowValue = object["rows"], case .array(let rows) = rowValue,
               case .number(let value) = rows[2] {
                XCTAssertEqual(value.bitPattern, (-0.0 as Double).bitPattern)
            } else { XCTFail("Expected the complete nested JSON value") }
        }
    }

    func testWorkerPreservesMalformedPayloadErrorPathsAndDescriptions() async {
        let worker = RemoteSnapshotDecoder()
        for json in [
            #"{"dates":["not-a-date"],"value":null}"#,
            #"{"dates":[123],"value":null}"#,
            #"{"value":null}"#,
            #"{"dates":[],"value":null"#
        ] {
            let data = Data(json.utf8)
            let expected: String
            do {
                _ = try RemoteDecoding.decoder.decode(DateProbe.self, from: data)
                XCTFail("Legacy decoder unexpectedly accepted malformed input")
                continue
            } catch { expected = errorIdentity(error) }
            do {
                _ = try await worker.decode(DateProbe.self, from: data)
                XCTFail("Worker unexpectedly accepted malformed input")
            } catch { XCTAssertEqual(errorIdentity(error), expected) }
        }
    }

    func testWorkerDecodesOffMainThreadAndSupportsConcurrentCallers() async throws {
        let worker = RemoteSnapshotDecoder()
        let results = try await withThrowingTaskGroup(of: ExecutionProbe.self) { group in
            for index in 0..<24 {
                let data = Data("{\"value\":\(index)}".utf8)
                group.addTask { try await worker.decode(ExecutionProbe.self, from: data) }
            }
            var values: [ExecutionProbe] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.map(\.value).sorted(), Array(0..<24))
        XCTAssertTrue(results.allSatisfy { !$0.decodedOnMainThread })
    }

    func testLegacyCustomDecoderAndNonSendableResultRemainOnOriginalPath() async throws {
        let worker = CountingSnapshotDecoder()
        let (client, _, session) = makeClient(responses: [(200, Data(#"{"date":1234}"#.utf8))], decoder: worker)
        defer { session.invalidateAndCancel() }
        let custom = JSONDecoder()
        custom.dateDecodingStrategy = .secondsSince1970
        let value: LegacyReferenceProbe = try await client.call("custom", params: Parameters(), decoder: custom)
        XCTAssertEqual(value.date, Date(timeIntervalSince1970: 1234))
        let count = await worker.count
        XCTAssertEqual(count, 0)
    }

    func testProtocolFallbackKeepsExistingFakesCompatible() async throws {
        let rpc = LegacyOnlyRPC()
        let value: ValueProbe = try await rpc.callSnapshot("snapshot", params: Parameters())
        XCTAssertEqual(value.value, "ok")
        XCTAssertEqual(rpc.calls, ["snapshot"])
    }

    func testOnlyListAndCalendarRepositoriesOptIntoSnapshotDecoder() async throws {
        let rpc = SnapshotRouteRPC()
        let repository = SupabaseSurfaceSnapshotRepository(rpc: rpc)
        let lists = try await repository.placeListsSnapshot()
        let calendar = try await repository.currentUserCalendarSnapshot()
        _ = try await repository.socialSurfaceSnapshot(in: MapViewport(
            minLatitude: 34, minLongitude: -119, maxLatitude: 35, maxLongitude: -118
        ))
        XCTAssertTrue(lists.summaries.isEmpty && lists.details.isEmpty && lists.visiblePlacesByOwnerID.isEmpty)
        XCTAssertTrue(calendar.visiblePlaces.isEmpty && calendar.visits.isEmpty)
        XCTAssertEqual(rpc.snapshotCalls, ["visible_place_lists_snapshot", "current_user_calendar_snapshot"])
        XCTAssertEqual(rpc.legacyCalls, ["social_surface_snapshot"])
    }

    func testSnapshotRPCRetriesOnceWithExactBodyAndFreshToken() async throws {
        let worker = CountingSnapshotDecoder()
        let (client, auth, session) = makeClient(responses: [
            (401, Data("expired".utf8)), (200, Data(#"{"value":"ok"}"#.utf8))
        ], decoder: worker)
        defer { session.invalidateAndCancel() }
        let value: ValueProbe = try await client.callSnapshot("visible_place_lists_snapshot", params: Parameters())
        XCTAssertEqual(value.value, "ok")
        XCTAssertEqual(auth.tokenRequests, 1)
        XCTAssertEqual(auth.refreshRequests, 1)
        XCTAssertEqual(SnapshotURLProtocol.headers, ["Bearer old-token", "Bearer new-token"])
        XCTAssertEqual(SnapshotURLProtocol.bodies.count, 2)
        XCTAssertEqual(SnapshotURLProtocol.bodies.first, SnapshotURLProtocol.bodies.last)
        let count = await worker.count
        XCTAssertEqual(count, 1)
    }

    func testSnapshotRPCSecondAuthorizationFailureDoesNotDecodeOrRetryAgain() async {
        let worker = CountingSnapshotDecoder()
        let (client, auth, session) = makeClient(responses: [(403, Data()), (401, Data())], decoder: worker)
        defer { session.invalidateAndCancel() }
        do {
            let _: ValueProbe = try await client.callSnapshot("visible_place_lists_snapshot", params: Parameters())
            XCTFail("Expected authentication failure")
        } catch { XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated) }
        XCTAssertEqual(auth.refreshRequests, 1)
        XCTAssertEqual(SnapshotURLProtocol.headers.count, 2)
        let count = await worker.count
        XCTAssertEqual(count, 0)
    }

    func testSnapshotResponseValidationRetainsEmptyHTTPAndPrivateErrorSemantics() async throws {
        for (name, status, data, expected) in [
            ("snapshot", 200, Data(), WanderRemoteError.invalidResponse("RPC snapshot returned no data")),
            ("snapshot", 500, Data("synthetic failure".utf8), .invalidResponse("RPC snapshot failed with 500: synthetic failure")),
            ("own_account_contact_details", 500, Data("synthetic private content".utf8), .invalidResponse("RPC own_account_contact_details failed with 500: private account details request failed")),
            ("own_account_contact_details", 200, Data("synthetic malformed content".utf8), .invalidResponse("Invalid private account details response"))
        ] {
            let (client, _, session) = makeClient(responses: [(status, data)])
            do {
                let _: ValueProbe = try await client.callSnapshot(name, params: Parameters())
                XCTFail("Expected validation failure")
            } catch { XCTAssertEqual(error as? WanderRemoteError, expected) }
            session.invalidateAndCancel()
        }
        let worker = CountingSnapshotDecoder()
        let (client, _, session) = makeClient(responses: [(204, Data())], decoder: worker)
        defer { session.invalidateAndCancel() }
        let _: EmptyRPCResponse = try await client.callSnapshot("snapshot", params: Parameters())
        let count = await worker.count
        XCTAssertEqual(count, 0)
    }

    func testAccountSwitchDuringSuccessfulOrFailedDecodeDiscardsBothOutcomes() async {
        for fails in [false, true] {
            let started = XCTestExpectation(description: "worker entered")
            let worker = HeldSnapshotDecoder(started: started, fails: fails)
            let (client, auth, session) = makeClient(responses: [(200, Data(#"{"value":"ok"}"#.utf8))], decoder: worker)
            let task = Task { try await client.callSnapshot("snapshot", params: Parameters()) as ValueProbe }
            await fulfillment(of: [started], timeout: 2)
            auth.state = .signedIn(AuthSession(userID: "other", displayName: "Other", handle: "other"))
            await worker.release()
            do { _ = try await task.value; XCTFail("Expected stale-account rejection") }
            catch { XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated) }
            session.invalidateAndCancel()
        }
    }

    func testCancellationDuringSuccessfulOrFailedDecodeStaysCancellation() async {
        for fails in [false, true] {
            let started = XCTestExpectation(description: "worker entered")
            let worker = HeldSnapshotDecoder(started: started, fails: fails)
            let (client, _, session) = makeClient(responses: [(200, Data(#"{"value":"ok"}"#.utf8))], decoder: worker)
            let task = Task { try await client.callSnapshot("snapshot", params: Parameters()) as ValueProbe }
            await fulfillment(of: [started], timeout: 2)
            task.cancel()
            await worker.release()
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            session.invalidateAndCancel()
        }
    }

    func testSameAccountSessionRefreshDuringDecodePreservesResultAndWorkerError() async {
        for fails in [false, true] {
            let started = XCTestExpectation(description: "worker entered")
            let worker = HeldSnapshotDecoder(started: started, fails: fails)
            let (client, auth, session) = makeClient(responses: [(200, Data(#"{"value":"ok"}"#.utf8))], decoder: worker)
            let task = Task { try await client.callSnapshot("snapshot", params: Parameters()) as ValueProbe }
            await fulfillment(of: [started], timeout: 2)
            auth.state = .signedIn(AuthSession(userID: "owner", displayName: "Updated", handle: "updated"))
            await worker.release()
            do {
                let result = try await task.value
                XCTAssertFalse(fails)
                XCTAssertEqual(result.value, "ok")
            } catch {
                XCTAssertTrue(fails)
                XCTAssertEqual(error as? WanderRemoteError, .invalidResponse("controlled decode failure"))
            }
            session.invalidateAndCancel()
        }
    }

    private func makeClient(
        responses: [(Int, Data)], decoder: any RemoteSnapshotDecoding = RemoteSnapshotDecoder()
    ) -> (WanderSupabaseClient, SnapshotAuthSession, URLSession) {
        SnapshotURLProtocol.reset(responses)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SnapshotURLProtocol.self]
        let session = URLSession(configuration: config)
        let auth = SnapshotAuthSession()
        let client = WanderSupabaseClient(configuration: WanderBackendConfiguration(
            clerkPublishableKey: "pk_test_mock", clerkFrontendAPI: "mock.clerk.accounts.dev",
            supabaseURL: URL(string: "https://example.supabase.co"), supabasePublishableKey: "test-key"
        ), authSession: auth, urlSession: session, snapshotDecoder: decoder)
        return (client, auth, session)
    }

    private func errorIdentity(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context): return "corrupted:\(context.codingPath.map(\.stringValue)):\(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context): return "key:\(key.stringValue):\(context.codingPath.map(\.stringValue)):\(context.debugDescription)"
        case DecodingError.typeMismatch(let type, let context): return "type:\(type):\(context.codingPath.map(\.stringValue)):\(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context): return "value:\(type):\(context.codingPath.map(\.stringValue)):\(context.debugDescription)"
        default: return String(describing: error)
        }
    }
}

private struct Parameters: Encodable { let input = "unchanged" }
private struct ValueProbe: Decodable, Sendable { let value: String }
private struct DateProbe: Decodable, Equatable, Sendable {
    let dates: [Date]
    let optional: Date?
    let value: JSONValue
}
private final class LegacyReferenceProbe: Decodable { let date: Date }
private struct ExecutionProbe: Decodable, Sendable {
    let value: Int
    let decodedOnMainThread: Bool
    enum CodingKeys: CodingKey { case value }
    init(from decoder: Decoder) throws {
        value = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .value)
        decodedOnMainThread = Thread.isMainThread
    }
}

private actor CountingSnapshotDecoder: RemoteSnapshotDecoding {
    private(set) var count = 0
    private let worker = RemoteSnapshotDecoder()
    func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) async throws -> Value {
        count += 1
        return try await worker.decode(type, from: data)
    }
}

private actor HeldSnapshotDecoder: RemoteSnapshotDecoding {
    private let started: XCTestExpectation
    private let fails: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(started: XCTestExpectation, fails: Bool) { self.started = started; self.fails = fails }
    func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) async throws -> Value {
        await withCheckedContinuation { continuation in
            if released { continuation.resume() }
            else { self.continuation = continuation }
            started.fulfill()
        }
        if fails { throw WanderRemoteError.invalidResponse("controlled decode failure") }
        // Deliberately ignore cancellation here: the client must fence either
        // outcome even when a decoder implementation doesn't cooperate.
        return try JSONDecoder().decode(type, from: data)
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor
private final class SnapshotAuthSession: AuthSessionProviding {
    var state: AuthState = .signedIn(AuthSession(userID: "owner", displayName: "Owner", handle: "owner"))
    let canPresentNativeAuth = false
    private(set) var tokenRequests = 0
    private(set) var refreshRequests = 0
    func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func refreshSession() async {}
    func signOut() async throws { state = .signedOut }
    func deleteAccount() async throws {}
    func supabaseAccessToken() async throws -> String { tokenRequests += 1; return "old-token" }
    func refreshSupabaseAccessToken() async throws -> String { refreshRequests += 1; return "new-token" }
}

@MainActor
private final class LegacyOnlyRPC: RemoteProcedureCalling {
    var calls: [String] = []
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        calls.append(name)
        return try decoder.decode(Value.self, from: Data(#"{"value":"ok"}"#.utf8))
    }
}

@MainActor
private final class SnapshotRouteRPC: RemoteProcedureCalling {
    var snapshotCalls: [String] = []
    var legacyCalls: [String] = []
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        legacyCalls.append(name)
        return try decoder.decode(Value.self, from: Data(#"{"following":[],"followers":[],"viewport_places":[],"wanna_go_plans":[],"followed_places":[],"relationships":[]}"#.utf8))
    }
    func callSnapshot<Value: Decodable & Sendable, Params: Encodable>(_ name: String, params: Params) async throws -> Value {
        snapshotCalls.append(name)
        let json = name == "visible_place_lists_snapshot"
            ? #"{"summaries":[],"details":[],"owner_places":[],"relationships":[]}"#
            : #"{"places":[],"visits":[]}"#
        return try RemoteDecoding.decoder.decode(Value.self, from: Data(json.utf8))
    }
}

private final class SnapshotURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [(Int, Data)] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var recordedBodies: [Data] = []
    static func reset(_ values: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        responses = values; requests = []; recordedBodies = []
    }
    static var headers: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }
    static var bodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return recordedBodies
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.lock.lock()
        Self.requests.append(request)
        if let body { Self.recordedBodies.append(body) }
        let response = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()
        guard let response, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.0, httpVersion: nil, headerFields: nil)
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        var body = Data()
        while true {
            let count = stream.read(buffer, maxLength: 4096)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }
}
