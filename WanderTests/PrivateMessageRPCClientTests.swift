import Foundation
import XCTest
@testable import Wander

/// Exercises the real URLSession transport with synthetic, entirely offline HTTP
/// responses. Each test has a unique host and isolated protocol scenario.
@MainActor
final class PrivateMessageRPCClientTests: XCTestCase {
    func testAccountSwitchDuringSuspendedTokenFetchNeverStartsHTTP() async throws {
        let fixture = Fixture(responses: [.ok])
        defer { fixture.close() }
        fixture.auth.suspendCachedToken = true
        let request = Task { try await fixture.fetch() }
        try await waitUntil { fixture.auth.tokenContinuation != nil }
        fixture.auth.switchAccount()
        fixture.auth.releaseToken()
        await assertUnavailable(request)
        XCTAssertTrue(fixture.scenario.requests.isEmpty)
    }

    func testAccountSwitchDuringForcedRefreshNeverSendsReplacementToken() async throws {
        let fixture = Fixture(responses: [.unauthorized, .ok])
        defer { fixture.close() }
        fixture.auth.suspendForcedToken = true
        let request = Task { try await fixture.fetch() }
        try await waitUntil { fixture.auth.tokenContinuation != nil }
        fixture.auth.switchAccount()
        fixture.auth.releaseToken()
        await assertUnavailable(request)
        XCTAssertEqual(fixture.scenario.requests.count, 1)
        XCTAssertEqual(fixture.auth.forcedTokenRequests, 1)
    }

    func testAccountSwitchDiscardsSuspendedSuccessfulResponse() async throws {
        let fixture = Fixture(responses: [.ok], heldIndices: [0])
        defer { fixture.close() }
        let request = Task { try await fixture.fetch() }
        try await waitUntil { fixture.scenario.heldCount == 1 }
        fixture.auth.switchAccount()
        fixture.scenario.releaseResponses()
        await assertUnavailable(request)
        XCTAssertEqual(fixture.scenario.requests.count, 1)
    }

    func testUnauthorizedRefreshesOnceWithIdenticalSendPayload() async throws {
        let fixture = Fixture(responses: [.unauthorized, .ok])
        defer { fixture.close() }
        let response = try await fixture.fetch()
        XCTAssertEqual(response.value, "synthetic-response")
        XCTAssertEqual(fixture.auth.cachedTokenRequests, 1)
        XCTAssertEqual(fixture.auth.forcedTokenRequests, 1)
        let requests = fixture.scenario.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer synthetic-cached", "Bearer synthetic-refreshed"])
        XCTAssertEqual(requests.map { $0.url?.path }, Array(repeating: "/rest/v1/rpc/private_message_send", count: 2))
        let bodies = fixture.scenario.bodies
        XCTAssertEqual(bodies.count, 2)
        XCTAssertFalse(bodies[0].isEmpty)
        XCTAssertEqual(bodies[0], bodies[1], "A token refresh must preserve the idempotency UUID and exact body")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: String])
        XCTAssertEqual(payload["input_client_id"], Fixture.clientID.uuidString)
        XCTAssertEqual(payload["input_body"], "Synthetic transport fixture")
    }

    func testSecondUnauthorizedResponseStopsWithoutAnotherRefresh() async throws {
        let fixture = Fixture(responses: [.unauthorized, .unauthorized, .ok])
        defer { fixture.close() }
        let request = Task { try await fixture.fetch() }
        await assertUnavailable(request)
        XCTAssertEqual(fixture.scenario.requests.count, 2)
        XCTAssertEqual(fixture.auth.cachedTokenRequests, 1)
        XCTAssertEqual(fixture.auth.forcedTokenRequests, 1)
    }

    func testCancellationDuringTokenFetchDoesNotStartHTTP() async throws {
        let fixture = Fixture(responses: [.ok])
        defer { fixture.close() }
        fixture.auth.suspendCachedToken = true
        let request = Task { try await fixture.fetch() }
        try await waitUntil { fixture.auth.tokenContinuation != nil }
        request.cancel()
        fixture.auth.releaseToken()
        await assertCancelled(request)
        XCTAssertTrue(fixture.scenario.requests.isEmpty)
    }

    func testCancellationStopsSuspendedHTTPWithoutRetry() async throws {
        let fixture = Fixture(responses: [.ok], heldIndices: [0])
        defer { fixture.close() }
        let request = Task { try await fixture.fetch() }
        try await waitUntil { fixture.scenario.heldCount == 1 }
        request.cancel()
        await assertCancelled(request)
        try await waitUntil { fixture.scenario.stoppedCount == 1 }
        fixture.scenario.releaseResponses()
        XCTAssertEqual(fixture.scenario.requests.count, 1)
        XCTAssertEqual(fixture.auth.forcedTokenRequests, 0)
    }

    func testProductionConfigurationAndHTTPNeverUseCookiesOrResponseCache() async throws {
        let configuration = PrivateMessageRPCClient.makeSessionConfiguration()
        XCTAssertNil(configuration.identifier)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)

        // Even a cacheable response offering a cookie must not affect the next
        // request. Do not read or modify the machine's shared cookie/cache stores.
        let fixture = Fixture(responses: [.cacheable, .cacheable])
        defer { fixture.close() }
        _ = try await fixture.fetch()
        _ = try await fixture.fetch()
        let requests = fixture.scenario.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Synthetic transport did not reach its expected suspension point")
        throw URLError(.timedOut)
    }

    private func assertUnavailable(_ task: Task<Probe, any Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("A stale or unauthorized response must not be published", file: file, line: line) }
        catch {
            // The headers helper can reject the changed identity before the
            // messaging client's own account fence. The repository normalizes it.
            XCTAssertTrue((error as? PrivateMessageError) == .unavailable || (error as? WanderRemoteError) == .notAuthenticated,
                          "Expected an authorization failure", file: file, line: line)
        }
    }

    private func assertCancelled(_ task: Task<Probe, any Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("Cancelled transport must not publish a body", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled, file: file, line: line) }
    }

    private struct Probe: Decodable, Sendable { let value: String }
    private struct Parameters: Encodable {
        let input_client_id: UUID
        let input_body = "Synthetic transport fixture"
    }

    @MainActor
    private final class Fixture {
        static let clientID = UUID(uuidString: "63600000-0000-0000-0000-000000000042")!
        let host = "messaging-\(UUID().uuidString.lowercased()).invalid"
        let auth = MessagingTransportAuth()
        let scenario: MessagingTransportScenario
        let client: PrivateMessageRPCClient

        init(responses: [MessagingTransportScenario.Response], heldIndices: Set<Int> = []) {
            scenario = MessagingTransportScenario(responses: responses, heldIndices: heldIndices)
            MessagingTransportURLProtocol.register(scenario, for: host)
            client = PrivateMessageRPCClient(configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_synthetic", clerkFrontendAPI: "synthetic.invalid",
                supabaseURL: URL(string: "https://\(host)"), supabasePublishableKey: "synthetic-public-key"),
                authSession: auth, protocolClasses: [MessagingTransportURLProtocol.self])
        }

        func fetch() async throws -> Probe {
            try await client.call("private_message_send", params: Parameters(input_client_id: Self.clientID))
        }
        func close() {
            auth.releaseToken()
            scenario.releaseResponses()
            MessagingTransportURLProtocol.unregister(host)
        }
    }
}

@MainActor
private final class MessagingTransportAuth: AuthSessionProviding {
    var state: AuthState = .signedIn(.init(userID: "synthetic-account-a", displayName: nil, handle: nil))
    let canPresentNativeAuth = false
    var suspendCachedToken = false
    var suspendForcedToken = false
    var cachedTokenRequests = 0
    var forcedTokenRequests = 0
    var tokenContinuation: CheckedContinuation<String, any Error>?
    func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func refreshSession() async {}
    func signOut() async throws { state = .signedOut }
    func supabaseAccessToken() async throws -> String {
        cachedTokenRequests += 1
        if suspendCachedToken { return try await withCheckedThrowingContinuation { tokenContinuation = $0 } }
        return "synthetic-cached"
    }
    func refreshSupabaseAccessToken() async throws -> String {
        forcedTokenRequests += 1
        if suspendForcedToken { return try await withCheckedThrowingContinuation { tokenContinuation = $0 } }
        return "synthetic-refreshed"
    }
    func switchAccount() { state = .signedIn(.init(userID: "synthetic-account-b", displayName: nil, handle: nil)) }
    func releaseToken() {
        let continuation = tokenContinuation; tokenContinuation = nil
        continuation?.resume(returning: "synthetic-released")
    }
}

private final class MessagingTransportScenario: @unchecked Sendable {
    struct Response: Sendable {
        let status: Int
        let body: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
        static let ok = Response(status: 200, body: Data(#"{"value":"synthetic-response"}"#.utf8))
        static let unauthorized = Response(status: 401, body: Data(#"{"message":"synthetic unauthorized"}"#.utf8))
        static let cacheable = Response(status: 200, body: ok.body,
            headers: ["Content-Type": "application/json", "Cache-Control": "public, max-age=86400", "Set-Cookie": "synthetic=fixture; Path=/; Secure"])
    }
    private let lock = NSLock()
    private var responses: [Response]
    private let heldIndices: Set<Int>
    private var recordedRequests: [URLRequest] = []
    private var recordedBodies: [Data] = []
    private var held: [(MessagingTransportURLProtocol, Response)] = []
    private var stopped = 0
    init(responses: [Response], heldIndices: Set<Int>) { self.responses = responses; self.heldIndices = heldIndices }
    var requests: [URLRequest] { lock.withLock { recordedRequests } }
    var bodies: [Data] { lock.withLock { recordedBodies } }
    var heldCount: Int { lock.withLock { held.count } }
    var stoppedCount: Int { lock.withLock { stopped } }
    func start(_ loader: MessagingTransportURLProtocol) {
        let body = Self.readBody(loader.request)
        let response: Response? = lock.withLock {
            let index = recordedRequests.count
            recordedRequests.append(loader.request); recordedBodies.append(body)
            guard !responses.isEmpty else {
                // An unexpected extra request fails immediately instead of
                // reaching the network or waiting for the transport timeout.
                return Response(status: 500, body: Data(#"{"message":"synthetic unexpected request"}"#.utf8))
            }
            let response = responses.removeFirst()
            if heldIndices.contains(index) { held.append((loader, response)); return nil }
            return response
        }
        if let response { loader.deliver(response) }
    }
    func didStop() { lock.withLock { stopped += 1 } }
    func releaseResponses() {
        let pending = lock.withLock { let pending = held; held = []; return pending }
        for (loader, response) in pending { loader.deliver(response) }
    }
    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { return result }
            result.append(contentsOf: bytes.prefix(count))
        }
    }
}

private final class MessagingTransportURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var scenarios: [String: MessagingTransportScenario] = [:]
    private let deliveryLock = NSRecursiveLock()
    private var stopped = false
    private var scenario: MessagingTransportScenario?
    static func register(_ scenario: MessagingTransportScenario, for host: String) { registryLock.withLock { scenarios[host] = scenario } }
    static func unregister(_ host: String) { _ = registryLock.withLock { scenarios.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = Self.registryLock.withLock { Self.scenarios[request.url?.host ?? ""] }
        deliveryLock.withLock { self.scenario = scenario }
        guard let scenario else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        scenario.start(self)
    }
    func deliver(_ response: MessagingTransportScenario.Response) {
        deliveryLock.withLock {
            guard !stopped, let url = request.url,
                  let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: response.headers) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        deliveryLock.withLock { stopped = true; scenario?.didStop() }
    }
}
