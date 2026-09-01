import Foundation
import OSLog
#if canImport(Supabase)
import Supabase
#endif

enum WanderRemoteError: Error, Equatable {
    case notConfigured
    case notAuthenticated
    case notImplemented(String)
    case invalidResponse(String)
}

struct EmptyRPCResponse: Codable, Equatable {}

@MainActor
protocol RemoteProcedureCalling {
    func call<Value: Decodable, Params: Encodable>(
        _ name: String,
        params: Params,
        decoder: JSONDecoder
    ) async throws -> Value
}

extension RemoteProcedureCalling {
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params) async throws -> Value {
        try await call(name, params: params, decoder: RemoteDecoding.decoder)
    }
}

@MainActor
protocol RemoteFunctionCalling {
    func invoke<Value: Decodable, Body: Encodable>(
        _ name: String,
        body: Body,
        decoder: JSONDecoder
    ) async throws -> Value
}

extension RemoteFunctionCalling {
    func invoke<Value: Decodable, Body: Encodable>(_ name: String, body: Body) async throws -> Value {
        try await invoke(name, body: body, decoder: RemoteDecoding.decoder)
    }
}

@MainActor
protocol RemoteStorageCalling {
    func uploadObject(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        upsert: Bool
    ) async throws
    func deleteObject(bucket: String, path: String) async throws
    func downloadObject(bucket: String, path: String) async throws -> Data
    func downloadImage(
        bucket: String,
        path: String,
        variant: PlacePhotoRenderVariant
    ) async throws -> Data
    func signedObjectURL(bucket: String, path: String, expiresIn: Int) async throws -> URL
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL
}

extension RemoteStorageCalling {
    func downloadImage(
        bucket: String,
        path: String,
        variant: PlacePhotoRenderVariant
    ) async throws -> Data {
        try await downloadObject(bucket: bucket, path: path)
    }

    func signedObjectURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        throw WanderRemoteError.notImplemented("private storage signed URL")
    }
}

@MainActor
protocol RemoteTableCalling {
    func select<Value: Decodable>(
        table: String,
        queryItems: [URLQueryItem],
        decoder: JSONDecoder
    ) async throws -> Value
    func upsert<Value: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        onConflict: String?,
        decoder: JSONDecoder
    ) async throws -> Value
    func update<Value: Decodable, Body: Encodable>(
        table: String,
        queryItems: [URLQueryItem],
        body: Body,
        decoder: JSONDecoder
    ) async throws -> Value
    func delete(table: String, queryItems: [URLQueryItem]) async throws
}

extension RemoteTableCalling {
    func select<Value: Decodable>(table: String, queryItems: [URLQueryItem]) async throws -> Value {
        try await select(table: table, queryItems: queryItems, decoder: RemoteDecoding.decoder)
    }

    func upsert<Value: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        onConflict: String? = nil
    ) async throws -> Value {
        try await upsert(table: table, body: body, onConflict: onConflict, decoder: RemoteDecoding.decoder)
    }

    func update<Value: Decodable, Body: Encodable>(
        table: String,
        queryItems: [URLQueryItem],
        body: Body
    ) async throws -> Value {
        try await update(table: table, queryItems: queryItems, body: body, decoder: RemoteDecoding.decoder)
    }
}

@MainActor
enum RemoteDecoding {
    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let ISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalISO8601Formatter.date(from: value)
                ?? ISO8601Formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date string."
            )
        }
        return decoder
    }()
}

enum RemoteEncoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private struct SignedStorageURLResponse: Decodable {
    let signedURL: String

    enum CodingKeys: String, CodingKey {
        case signedURL = "signedURL"
    }
}

@MainActor
final class WanderSupabaseClient: RemoteProcedureCalling, RemoteFunctionCalling, RemoteStorageCalling, RemoteTableCalling {
    private static let socialImportUnderstandingTimeout: TimeInterval = 145

    private struct RejectedTokenKey: Hashable {
        let userID: String
        let token: String
    }

    private struct InFlightTokenRefresh {
        let id: UUID
        let task: Task<String, Error>
    }

    let configuration: WanderBackendConfiguration
    private let authSession: AuthSessionProviding
    private let urlSession: URLSession
    private var inFlightTokenRefreshes: [RejectedTokenKey: InFlightTokenRefresh] = [:]
    private var replacementTokens: [RejectedTokenKey: String] = [:]

    init(configuration: WanderBackendConfiguration, authSession: AuthSessionProviding, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.authSession = authSession
        self.urlSession = urlSession
    }

    var isConfigured: Bool {
        self.configuration.isSupabaseConfigured
    }

    static func encodeRequestBody<Value: Encodable>(_ value: Value) throws -> Data {
        try RemoteEncoding.encoder.encode(value)
    }

    func authenticatedHeaders(forceTokenRefresh: Bool = false) async throws -> [String: String] {
        let expectedUserID = try configuredAuthenticatedUserID()
        return try await authenticatedRequestContext(
            expectedUserID: expectedUserID,
            forceTokenRefresh: forceTokenRefresh
        ).headers
    }

    private func authenticatedRequestContext(
        expectedUserID: String,
        forceTokenRefresh: Bool = false,
        rejectedToken: String? = nil
    ) async throws -> (headers: [String: String], token: String) {
        guard self.configuration.isSupabaseConfigured else {
            #if DEBUG
            WanderDebugLog.remote.error("auth headers failed reason=not_configured")
            #endif
            throw WanderRemoteError.notConfigured
        }

        let token: String
        do {
            try validateAuthenticatedUser(expectedUserID)
            if let rejectedToken {
                token = try await replacementToken(
                    for: rejectedToken,
                    expectedUserID: expectedUserID
                )
            } else if forceTokenRefresh {
                token = try await self.authSession.refreshSupabaseAccessToken()
            } else {
                token = try await self.authSession.supabaseAccessToken()
            }
            try validateAuthenticatedUser(expectedUserID)
            #if DEBUG
            WanderDebugLog.remote.debug("auth headers ready supabase_url_configured=\((self.configuration.supabaseURL != nil), privacy: .public) forced_token_refresh=\((forceTokenRefresh || rejectedToken != nil), privacy: .public)")
            #endif
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("auth headers failed reason=token_fetch_error error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            throw error
        }

        return ([
            "apikey": self.configuration.supabasePublishableKey ?? "",
            "Authorization": "Bearer \(token)"
        ], token)
    }

    private func currentAuthenticatedUserID() throws -> String {
        guard case .signedIn(let session) = authSession.state else {
            throw WanderRemoteError.notAuthenticated
        }
        return session.userID
    }

    private func configuredAuthenticatedUserID() throws -> String {
        guard configuration.isSupabaseConfigured else {
            throw WanderRemoteError.notConfigured
        }
        return try currentAuthenticatedUserID()
    }

    private func validateAuthenticatedUser(_ expectedUserID: String) throws {
        guard case .signedIn(let session) = authSession.state,
              session.userID == expectedUserID
        else {
            throw WanderRemoteError.notAuthenticated
        }
    }

    private func replacementToken(
        for rejectedToken: String,
        expectedUserID: String
    ) async throws -> String {
        try Task.checkCancellation()
        try validateAuthenticatedUser(expectedUserID)

        let key = RejectedTokenKey(userID: expectedUserID, token: rejectedToken)
        if let replacementToken = replacementTokens[key] {
            return replacementToken
        }

        let refresh: InFlightTokenRefresh
        if let existingRefresh = inFlightTokenRefreshes[key] {
            refresh = existingRefresh
        } else {
            let authSession = self.authSession
            let newRefresh = InFlightTokenRefresh(
                id: UUID(),
                task: Task { @MainActor in
                    try await authSession.refreshSupabaseAccessToken()
                }
            )
            inFlightTokenRefreshes[key] = newRefresh
            refresh = newRefresh
        }

        do {
            let token = try await refresh.task.value
            try validateAuthenticatedUser(expectedUserID)
            replacementTokens[key] = token
            if replacementTokens.count > 8 {
                replacementTokens = [key: token]
            }
            if inFlightTokenRefreshes[key]?.id == refresh.id {
                inFlightTokenRefreshes[key] = nil
            }
            try Task.checkCancellation()
            return token
        } catch {
            if inFlightTokenRefreshes[key]?.id == refresh.id {
                inFlightTokenRefreshes[key] = nil
            }
            throw error
        }
    }

    private func invalidateReplacementToken(
        for rejectedToken: String,
        replacementToken: String,
        expectedUserID: String
    ) {
        let key = RejectedTokenKey(userID: expectedUserID, token: rejectedToken)
        guard replacementTokens[key] == replacementToken else {
            return
        }
        replacementTokens[key] = nil
    }

    func call<Value: Decodable, Params: Encodable>(
        _ name: String,
        params: Params,
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        let rpcSignpostID = OSSignpostID(log: WanderDebugLog.pointsOfInterest)
        os_signpost(
            .begin,
            log: WanderDebugLog.pointsOfInterest,
            name: "Remote RPC",
            signpostID: rpcSignpostID,
            "name=%{public}@",
            name as NSString
        )
        defer {
            os_signpost(
                .end,
                log: WanderDebugLog.pointsOfInterest,
                name: "Remote RPC",
                signpostID: rpcSignpostID,
                "name=%{public}@",
                name as NSString
            )
        }
        let expectedUserID = try configuredAuthenticatedUserID()
        let initialResponse = try await rpcResponse(
            name,
            params: params,
            expectedUserID: expectedUserID
        )

        if Self.requiresFreshToken(after: initialResponse.response.statusCode) {
            #if DEBUG
            WanderDebugLog.remote.notice("rpc retrying with fresh token name=\(name, privacy: .public) status=\(initialResponse.response.statusCode, privacy: .public)")
            #endif
            try Task.checkCancellation()
            let refreshedResponse = try await rpcResponse(
                name,
                params: params,
                expectedUserID: expectedUserID,
                rejectedToken: initialResponse.requestToken
            )
            return try decodeRPCResponse(
                Value.self,
                data: refreshedResponse.data,
                response: refreshedResponse.response,
                name: name,
                decoder: decoder
            )
        }

        return try decodeRPCResponse(
            Value.self,
            data: initialResponse.data,
            response: initialResponse.response,
            name: name,
            decoder: decoder
        )
    }

    nonisolated static func requiresFreshToken(after statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 403
    }

    nonisolated static func canRetryFunctionAfterAuthorizationFailure(_ name: String) -> Bool {
        name == "place-photo"
            || name == "semantic-place-search"
            || name == "social-import-understand"
    }

    private func rpcResponse<Params: Encodable>(
        _ name: String,
        params: Params,
        expectedUserID: String,
        rejectedToken: String? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse, requestToken: String) {
        guard let supabaseURL = self.configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("rpc skipped name=\(name, privacy: .public) reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }

        #if DEBUG
        WanderDebugLog.remote.debug("rpc preparing name=\(name, privacy: .public)")
        #endif
        let requestContext = try await authenticatedRequestContext(
            expectedUserID: expectedUserID,
            rejectedToken: rejectedToken
        )
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        requestContext.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try Self.encodeRequestBody(params)

        #if DEBUG
        WanderDebugLog.remote.debug("rpc request name=\(name, privacy: .public) path=\(endpoint.path, privacy: .public)")
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.urlSession.data(for: request)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("rpc transport failed name=\(name, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }
        try validateAuthenticatedUser(expectedUserID)

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("rpc invalid response name=\(name, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for \(name)")
        }

        if let rejectedToken,
           Self.requiresFreshToken(after: httpResponse.statusCode) {
            invalidateReplacementToken(
                for: rejectedToken,
                replacementToken: requestContext.token,
                expectedUserID: expectedUserID
            )
        }

        return (data, httpResponse, requestContext.token)
    }

    private func decodeRPCResponse<Value: Decodable>(
        _: Value.Type,
        data: Data,
        response: HTTPURLResponse,
        name: String,
        decoder: JSONDecoder
    ) throws -> Value {
        let decodeSignpostID = OSSignpostID(log: WanderDebugLog.pointsOfInterest)
        os_signpost(
            .begin,
            log: WanderDebugLog.pointsOfInterest,
            name: "RPC Decode",
            signpostID: decodeSignpostID,
            "name=%{public}@ bytes=%{public}d",
            name as NSString,
            data.count
        )
        defer {
            os_signpost(
                .end,
                log: WanderDebugLog.pointsOfInterest,
                name: "RPC Decode",
                signpostID: decodeSignpostID,
                "name=%{public}@ bytes=%{public}d",
                name as NSString,
                data.count
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("rpc failed name=\(name, privacy: .public) status=\(response.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if Self.requiresFreshToken(after: response.statusCode) {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("RPC \(name) failed with \(response.statusCode): \(body)")
        }

        #if DEBUG
        WanderDebugLog.remote.debug("rpc success name=\(name, privacy: .public) status=\(response.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
        #endif

        if Value.self == EmptyRPCResponse.self {
            return EmptyRPCResponse() as! Value
        }

        guard !data.isEmpty else {
            #if DEBUG
            WanderDebugLog.remote.error("rpc invalid response name=\(name, privacy: .public) reason=empty_data")
            #endif
            throw WanderRemoteError.invalidResponse("RPC \(name) returned no data")
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("rpc decode failed name=\(name, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }
    }

    func invoke<Value: Decodable, Body: Encodable>(
        _ name: String,
        body: Body,
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        let expectedUserID = try configuredAuthenticatedUserID()
        let initialResponse = try await functionResponse(
            name,
            body: body,
            expectedUserID: expectedUserID
        )

        if Self.requiresFreshToken(after: initialResponse.response.statusCode),
           Self.canRetryFunctionAfterAuthorizationFailure(name) {
            #if DEBUG
            WanderDebugLog.remote.notice("function retrying with fresh token name=\(name, privacy: .public) status=\(initialResponse.response.statusCode, privacy: .public)")
            #endif
            try Task.checkCancellation()
            let refreshedResponse = try await functionResponse(
                name,
                body: body,
                expectedUserID: expectedUserID,
                rejectedToken: initialResponse.requestToken
            )
            return try decodeFunctionResponse(
                Value.self,
                data: refreshedResponse.data,
                response: refreshedResponse.response,
                name: name,
                decoder: decoder
            )
        }

        return try decodeFunctionResponse(
            Value.self,
            data: initialResponse.data,
            response: initialResponse.response,
            name: name,
            decoder: decoder
        )
    }

    private func functionResponse<Body: Encodable>(
        _ name: String,
        body: Body,
        expectedUserID: String,
        rejectedToken: String? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse, requestToken: String) {
        guard let supabaseURL = self.configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("function skipped name=\(name, privacy: .public) reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }

        #if DEBUG
        WanderDebugLog.remote.debug("function preparing name=\(name, privacy: .public)")
        #endif
        let requestContext = try await authenticatedRequestContext(
            expectedUserID: expectedUserID,
            rejectedToken: rejectedToken
        )
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if name == "social-import-understand" {
            // The server caps the complete authenticated Apify + Gemini +
            // Google Places run at 135 seconds. URLSession's 60-second default
            // would otherwise abandon paid work before the bounded response.
            request.timeoutInterval = Self.socialImportUnderstandingTimeout
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        requestContext.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try Self.encodeRequestBody(body)

        #if DEBUG
        WanderDebugLog.remote.debug("function request name=\(name, privacy: .public) path=\(endpoint.path, privacy: .public)")
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.urlSession.data(for: request)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("function transport failed name=\(name, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }
        try validateAuthenticatedUser(expectedUserID)

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("function invalid response name=\(name, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for function \(name)")
        }

        if let rejectedToken,
           Self.requiresFreshToken(after: httpResponse.statusCode) {
            invalidateReplacementToken(
                for: rejectedToken,
                replacementToken: requestContext.token,
                expectedUserID: expectedUserID
            )
        }

        return (data, httpResponse, requestContext.token)
    }

    private func decodeFunctionResponse<Value: Decodable>(
        _: Value.Type,
        data: Data,
        response: HTTPURLResponse,
        name: String,
        decoder: JSONDecoder
    ) throws -> Value {
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("function failed name=\(name, privacy: .public) status=\(response.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if Self.requiresFreshToken(after: response.statusCode) {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("Function \(name) failed with \(response.statusCode): \(body)")
        }

        #if DEBUG
        WanderDebugLog.remote.debug("function success name=\(name, privacy: .public) status=\(response.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
        #endif

        guard !data.isEmpty else {
            #if DEBUG
            WanderDebugLog.remote.error("function invalid response name=\(name, privacy: .public) reason=empty_data")
            #endif
            throw WanderRemoteError.invalidResponse("Function \(name) returned no data")
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("function decode failed name=\(name, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }
    }

    func select<Value: Decodable>(
        table: String,
        queryItems: [URLQueryItem],
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        var request = try await tableRequest(table: table, queryItems: queryItems)
        request.httpMethod = "GET"
        return try await performTableRequest(request, table: table, decoder: decoder)
    }

    func upsert<Value: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        onConflict: String? = nil,
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        var queryItems: [URLQueryItem] = []
        if let onConflict {
            queryItems.append(URLQueryItem(name: "on_conflict", value: onConflict))
        }

        var request = try await tableRequest(table: table, queryItems: queryItems)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try RemoteEncoding.encoder.encode(body)
        return try await performTableRequest(request, table: table, decoder: decoder)
    }

    func update<Value: Decodable, Body: Encodable>(
        table: String,
        queryItems: [URLQueryItem],
        body: Body,
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        var request = try await tableRequest(table: table, queryItems: queryItems)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try RemoteEncoding.encoder.encode(body)
        return try await performTableRequest(request, table: table, decoder: decoder)
    }

    func delete(table: String, queryItems: [URLQueryItem]) async throws {
        var request = try await tableRequest(table: table, queryItems: queryItems)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let _: EmptyRPCResponse = try await performTableRequest(request, table: table, decoder: RemoteDecoding.decoder)
    }

    private func tableRequest(table: String, queryItems: [URLQueryItem]) async throws -> URLRequest {
        guard let supabaseURL = self.configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("table request skipped table=\(table, privacy: .public) reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }

        var components = URLComponents(
            url: supabaseURL
                .appendingPathComponent("rest")
                .appendingPathComponent("v1")
                .appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let endpoint = components?.url else {
            throw WanderRemoteError.invalidResponse("Invalid table URL for \(table)")
        }

        let headers = try await authenticatedHeaders()
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func performTableRequest<Value: Decodable>(
        _ request: URLRequest,
        table: String,
        decoder: JSONDecoder
    ) async throws -> Value {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.urlSession.data(for: request)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("table transport failed table=\(table, privacy: .public) method=\(request.httpMethod ?? "unknown", privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("table invalid response table=\(table, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for table \(table)")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("table failed table=\(table, privacy: .public) method=\(request.httpMethod ?? "unknown", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("Table \(table) failed with \(httpResponse.statusCode): \(body)")
        }

        if Value.self == EmptyRPCResponse.self {
            return EmptyRPCResponse() as! Value
        }

        guard !data.isEmpty else {
            #if DEBUG
            WanderDebugLog.remote.error("table invalid response table=\(table, privacy: .public) reason=empty_data")
            #endif
            throw WanderRemoteError.invalidResponse("Table \(table) returned no data")
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("table decode failed table=\(table, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }
    }

    func uploadObject(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        upsert: Bool = true
    ) async throws {
        let endpoint = try storageObjectURL(bucket: bucket, path: path, isPublic: false)
        let headers = try await authenticatedHeaders()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("3600", forHTTPHeaderField: "cache-control")
        request.setValue(upsert ? "true" : "false", forHTTPHeaderField: "x-upsert")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = data

        #if DEBUG
        WanderDebugLog.remote.debug("storage upload request bucket=\(bucket, privacy: .public) path=\(path, privacy: .public) bytes=\(data.count, privacy: .public) upsert=\(upsert, privacy: .public)")
        #endif
        try await performStorageRequest(request, operation: "upload", bucket: bucket, path: path)
    }

    func deleteObject(bucket: String, path: String) async throws {
        let endpoint = try storageObjectURL(bucket: bucket, path: path, isPublic: false)
        let headers = try await authenticatedHeaders()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        #if DEBUG
        WanderDebugLog.remote.debug("storage delete request bucket=\(bucket, privacy: .public) path=\(path, privacy: .public)")
        #endif
        try await performStorageRequest(
            request,
            operation: "delete",
            bucket: bucket,
            path: path,
            treatsNotFoundAsSuccess: true
        )
    }

    func downloadObject(bucket: String, path: String) async throws -> Data {
        try await downloadStorageObject(bucket: bucket, path: path, variant: nil)
    }

    func downloadImage(
        bucket: String,
        path: String,
        variant: PlacePhotoRenderVariant
    ) async throws -> Data {
        try await downloadStorageObject(bucket: bucket, path: path, variant: variant)
    }

    private func downloadStorageObject(
        bucket: String,
        path: String,
        variant: PlacePhotoRenderVariant?
    ) async throws -> Data {
        let expectedUserID = try configuredAuthenticatedUserID()
        let initialResponse = try await storageDownloadResponse(
            bucket: bucket,
            path: path,
            expectedUserID: expectedUserID,
            variant: variant
        )

        let response: (data: Data, response: HTTPURLResponse, requestToken: String)
        if Self.requiresFreshToken(after: initialResponse.response.statusCode) {
            #if DEBUG
            WanderDebugLog.remote.notice("storage download retrying with fresh token bucket=\(bucket, privacy: .public) status=\(initialResponse.response.statusCode, privacy: .public)")
            #endif
            try Task.checkCancellation()
            response = try await storageDownloadResponse(
                bucket: bucket,
                path: path,
                expectedUserID: expectedUserID,
                variant: variant,
                rejectedToken: initialResponse.requestToken
            )
        } else {
            response = initialResponse
        }

        guard (200..<300).contains(response.response.statusCode) else {
            if Self.requiresFreshToken(after: response.response.statusCode) {
                throw WanderRemoteError.notAuthenticated
            }
            let body = String(data: response.data, encoding: .utf8) ?? "unreadable response"
            throw WanderRemoteError.invalidResponse("Storage download failed with \(response.response.statusCode): \(body)")
        }
        return response.data
    }

    private func storageDownloadResponse(
        bucket: String,
        path: String,
        expectedUserID: String,
        variant: PlacePhotoRenderVariant?,
        rejectedToken: String? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse, requestToken: String) {
        let endpoint: URL
        if let maximumPixelDimension = variant?.maximumPixelDimension {
            endpoint = try storageImageURL(
                bucket: bucket,
                path: path,
                maximumPixelDimension: maximumPixelDimension,
                quality: variant?.deliveryQuality ?? 90
            )
        } else {
            endpoint = try storageObjectURL(bucket: bucket, path: path, isPublic: false)
        }
        let requestContext = try await authenticatedRequestContext(
            expectedUserID: expectedUserID,
            rejectedToken: rejectedToken
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        requestContext.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await urlSession.data(for: request)
        try validateAuthenticatedUser(expectedUserID)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WanderRemoteError.invalidResponse("Missing HTTP response for storage download")
        }
        if let rejectedToken,
           Self.requiresFreshToken(after: httpResponse.statusCode) {
            invalidateReplacementToken(
                for: rejectedToken,
                replacementToken: requestContext.token,
                expectedUserID: expectedUserID
            )
        }
        return (data, httpResponse, requestContext.token)
    }

    private func storageImageURL(
        bucket: String,
        path: String,
        maximumPixelDimension: Int,
        quality: Int
    ) throws -> URL {
        guard let supabaseURL = configuration.supabaseURL else {
            throw WanderRemoteError.notConfigured
        }
        guard !bucket.isEmpty, !bucket.contains("/") else {
            throw WanderRemoteError.invalidResponse("Invalid storage bucket")
        }
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !pathComponents.isEmpty,
              pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw WanderRemoteError.invalidResponse("Invalid storage path")
        }

        var endpoint = supabaseURL
            .appendingPathComponent("storage")
            .appendingPathComponent("v1")
            .appendingPathComponent("render")
            .appendingPathComponent("image")
            .appendingPathComponent("authenticated")
            .appendingPathComponent(bucket)
        pathComponents.forEach { endpoint.appendPathComponent($0) }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WanderRemoteError.invalidResponse("Invalid transformed storage URL")
        }
        let dimension = max(1, min(maximumPixelDimension, 2_500))
        components.queryItems = [
            URLQueryItem(name: "width", value: String(dimension)),
            URLQueryItem(name: "height", value: String(dimension)),
            URLQueryItem(name: "resize", value: "contain"),
            URLQueryItem(name: "quality", value: String(max(20, min(quality, 100))))
        ]
        guard let url = components.url else {
            throw WanderRemoteError.invalidResponse("Invalid transformed storage URL")
        }
        return url
    }

    func publicObjectURL(bucket: String, path: String, cacheBust: String? = nil) throws -> URL {
        let url = try storageObjectURL(bucket: bucket, path: path, isPublic: true)
        guard let cacheBust, !cacheBust.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WanderRemoteError.invalidResponse("Invalid public storage URL")
        }
        components.queryItems = [URLQueryItem(name: "v", value: cacheBust)]
        guard let versionedURL = components.url else {
            throw WanderRemoteError.invalidResponse("Invalid versioned public storage URL")
        }
        return versionedURL
    }

    func signedObjectURL(bucket: String, path: String, expiresIn: Int = 3600) async throws -> URL {
        guard let supabaseURL = configuration.supabaseURL else {
            throw WanderRemoteError.notConfigured
        }
        let objectURL = try storageObjectURL(bucket: bucket, path: path, isPublic: false)
        guard let objectRange = objectURL.absoluteString.range(of: "/storage/v1/object/") else {
            throw WanderRemoteError.invalidResponse("Invalid private storage URL")
        }
        let objectSuffix = String(objectURL.absoluteString[objectRange.upperBound...])
        let endpoint = supabaseURL
            .appendingPathComponent("storage")
            .appendingPathComponent("v1")
            .appendingPathComponent("object")
            .appendingPathComponent("sign")
            .appendingPathComponent(objectSuffix)
        let headers = try await authenticatedHeaders()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { key, value in request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["expiresIn": max(60, min(expiresIn, 86_400))]
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw WanderRemoteError.invalidResponse("Could not create private storage URL")
        }
        let payload = try JSONDecoder().decode(SignedStorageURLResponse.self, from: data)
        if let absoluteURL = URL(string: payload.signedURL), absoluteURL.scheme != nil {
            return absoluteURL
        }
        let relativePath = payload.signedURL.hasPrefix("/object/")
            ? "/storage/v1\(payload.signedURL)"
            : payload.signedURL
        guard let relativeURL = URL(string: relativePath, relativeTo: supabaseURL)?.absoluteURL else {
            throw WanderRemoteError.invalidResponse("Invalid signed storage URL")
        }
        return relativeURL
    }

    private func storageObjectURL(bucket: String, path: String, isPublic: Bool) throws -> URL {
        guard let supabaseURL = configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("storage skipped reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }
        guard !bucket.isEmpty, !bucket.contains("/") else {
            throw WanderRemoteError.invalidResponse("Invalid storage bucket")
        }

        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !pathComponents.isEmpty,
              pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw WanderRemoteError.invalidResponse("Invalid storage path")
        }

        var url = supabaseURL
            .appendingPathComponent("storage")
            .appendingPathComponent("v1")
            .appendingPathComponent("object")
        if isPublic {
            url = url.appendingPathComponent("public")
        }
        url = url.appendingPathComponent(bucket)
        for component in pathComponents {
            url = url.appendingPathComponent(component)
        }
        return url
    }

    private func performStorageRequest(
        _ request: URLRequest,
        operation: String,
        bucket: String,
        path: String,
        treatsNotFoundAsSuccess: Bool = false
    ) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("storage transport failed operation=\(operation, privacy: .public) bucket=\(bucket, privacy: .public) path=\(path, privacy: .public) error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("storage invalid response operation=\(operation, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for storage \(operation)")
        }

        if treatsNotFoundAsSuccess, httpResponse.statusCode == 404 {
            #if DEBUG
            WanderDebugLog.remote.debug("storage success operation=\(operation, privacy: .public) bucket=\(bucket, privacy: .public) path=\(path, privacy: .public) status=404 treated_as=success")
            #endif
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("storage failed operation=\(operation, privacy: .public) bucket=\(bucket, privacy: .public) path=\(path, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("Storage \(operation) failed with \(httpResponse.statusCode): \(body)")
        }

        #if DEBUG
        WanderDebugLog.remote.debug("storage success operation=\(operation, privacy: .public) bucket=\(bucket, privacy: .public) path=\(path, privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
        #endif
    }
}
