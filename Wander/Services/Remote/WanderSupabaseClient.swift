import Foundation
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

enum RemoteDecoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
final class WanderSupabaseClient: RemoteProcedureCalling, RemoteFunctionCalling {
    let configuration: WanderBackendConfiguration
    private let authSession: AuthSessionProviding
    private let urlSession: URLSession

    init(configuration: WanderBackendConfiguration, authSession: AuthSessionProviding, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.authSession = authSession
        self.urlSession = urlSession
    }

    var isConfigured: Bool {
        self.configuration.isSupabaseConfigured
    }

    func authenticatedHeaders() async throws -> [String: String] {
        guard self.configuration.isSupabaseConfigured else {
            #if DEBUG
            WanderDebugLog.remote.error("auth headers failed reason=not_configured")
            #endif
            throw WanderRemoteError.notConfigured
        }

        let token: String
        do {
            token = try await self.authSession.supabaseAccessToken()
            #if DEBUG
            WanderDebugLog.remote.debug("auth headers ready supabase_url_configured=\((self.configuration.supabaseURL != nil), privacy: .public)")
            #endif
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("auth headers failed reason=token_fetch_error error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            throw error
        }

        return [
            "apikey": self.configuration.supabasePublishableKey ?? "",
            "Authorization": "Bearer \(token)"
        ]
    }

    func call<Value: Decodable, Params: Encodable>(
        _ name: String,
        params: Params,
        decoder: JSONDecoder = RemoteDecoding.decoder
    ) async throws -> Value {
        guard let supabaseURL = self.configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("rpc skipped name=\(name, privacy: .public) reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }

        #if DEBUG
        WanderDebugLog.remote.debug("rpc preparing name=\(name, privacy: .public)")
        #endif
        let headers = try await authenticatedHeaders()
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("rpc")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(params)

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

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("rpc invalid response name=\(name, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for \(name)")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("rpc failed name=\(name, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("RPC \(name) failed with \(httpResponse.statusCode): \(body)")
        }

        #if DEBUG
        WanderDebugLog.remote.debug("rpc success name=\(name, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
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
        guard let supabaseURL = self.configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("function skipped name=\(name, privacy: .public) reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }

        #if DEBUG
        WanderDebugLog.remote.debug("function preparing name=\(name, privacy: .public)")
        #endif
        let headers = try await authenticatedHeaders()
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

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

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            WanderDebugLog.remote.error("function invalid response name=\(name, privacy: .public) reason=missing_http_response")
            #endif
            throw WanderRemoteError.invalidResponse("Missing HTTP response for function \(name)")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("function failed name=\(name, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("Function \(name) failed with \(httpResponse.statusCode): \(body)")
        }

        #if DEBUG
        WanderDebugLog.remote.debug("function success name=\(name, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
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
}
