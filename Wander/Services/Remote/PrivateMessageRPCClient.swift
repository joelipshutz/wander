import Foundation

/// Messaging bypasses the general RPC client's diagnostic response logging and
/// shared URL cache. No request/response bodies or raw backend errors are logged.
@MainActor
final class PrivateMessageRPCClient: RemoteProcedureCalling {
    private let configuration: WanderBackendConfiguration
    private let authSession: any AuthSessionProviding
    private let headersClient: WanderSupabaseClient
    private let session: URLSession

    init(configuration: WanderBackendConfiguration, authSession: any AuthSessionProviding,
         protocolClasses: [AnyClass]? = nil) {
        self.configuration = configuration
        self.authSession = authSession
        let session = URLSession(configuration: Self.makeSessionConfiguration(protocolClasses: protocolClasses))
        self.session = session
        headersClient = WanderSupabaseClient(configuration: configuration, authSession: authSession, urlSession: session)
    }

    /// Protocol injection keeps transport tests offline while exercising the
    /// same ephemeral configuration used by the production initializer.
    static func makeSessionConfiguration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.timeoutIntervalForRequest = 20
        sessionConfiguration.timeoutIntervalForResource = 30
        if let protocolClasses { sessionConfiguration.protocolClasses = protocolClasses }
        return sessionConfiguration
    }

    deinit { session.invalidateAndCancel() }

    func call<Value: Decodable, Params: Encodable>(
        _ name: String, params: Params, decoder: JSONDecoder
    ) async throws -> Value {
        guard Self.allowedRPCs.contains(name), let baseURL = configuration.supabaseURL,
              case .signedIn(let identity) = authSession.state else { throw PrivateMessageError.unavailable }
        let expectedUserID = identity.userID
        let body = try WanderSupabaseClient.encodeRequestBody(params)
        for attempt in 0...1 {
            try Task.checkCancellation()
            try validateAccount(expectedUserID)
            let headers = try await headersClient.authenticatedHeaders(forceTokenRefresh: attempt == 1)
            try Task.checkCancellation()
            try validateAccount(expectedUserID)
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc").appendingPathComponent(name))
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.httpBody = body
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            try validateAccount(expectedUserID)
            guard let response = response as? HTTPURLResponse else { throw PrivateMessageError.unavailable }
            if response.statusCode == 401, attempt == 0 { continue }
            guard (200..<300).contains(response.statusCode) else {
                let code = (try? JSONDecoder().decode(ErrorCode.self, from: data))?.message
                switch code {
                case "private_message_invalid_body": throw PrivateMessageError.invalidBody
                case "private_message_rate_limited": throw PrivateMessageError.rateLimited
                case "private_message_invalid_cursor": throw PrivateMessageError.invalidCursor
                case "private_message_idempotency_conflict": throw PrivateMessageError.idempotencyConflict
                default: throw PrivateMessageError.unavailable
                }
            }
            // Decode errors intentionally leave this boundary as a generic state.
            do { return try decoder.decode(Value.self, from: data) }
            catch { throw PrivateMessageError.unavailable }
        }
        throw PrivateMessageError.unavailable
    }

    private func validateAccount(_ expected: String) throws {
        guard case .signedIn(let identity) = authSession.state, identity.userID == expected else {
            throw PrivateMessageError.unavailable
        }
    }

    private struct ErrorCode: Decodable { let message: String }
    private static let allowedRPCs: Set<String> = [
        "private_message_inbox", "private_message_conversation", "private_message_start",
        "private_message_history", "private_message_send", "private_message_mark_read"
    ]
}
