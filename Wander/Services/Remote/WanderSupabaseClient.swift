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
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL
}

@MainActor
protocol RemoteUserPlaceDeleting {
    func deleteUserPlace(userPlaceID: String) async throws
}

enum RemoteDecoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
final class WanderSupabaseClient: RemoteProcedureCalling, RemoteFunctionCalling, RemoteStorageCalling, RemoteUserPlaceDeleting {
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

    func deleteUserPlace(userPlaceID: String) async throws {
        guard let supabaseURL = configuration.supabaseURL else {
            #if DEBUG
            WanderDebugLog.remote.error("delete user_place skipped reason=missing_supabase_url")
            #endif
            throw WanderRemoteError.notConfigured
        }
        guard UUID(uuidString: userPlaceID) != nil else {
            throw WanderRemoteError.invalidResponse("Invalid remote user place id")
        }

        let headers = try await authenticatedHeaders()
        let endpoint = supabaseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("user_places")

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WanderRemoteError.invalidResponse("Invalid Supabase user_places endpoint")
        }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userPlaceID)")]
        guard let url = components.url else {
            throw WanderRemoteError.invalidResponse("Invalid Supabase user_places delete URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("delete user_place transport failed error=\(WanderDebugLog.clean(String(describing: error)), privacy: .public)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WanderRemoteError.invalidResponse("Missing HTTP response for user_places delete")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unreadable response"
            #if DEBUG
            WanderDebugLog.remote.error("delete user_place failed status=\(httpResponse.statusCode, privacy: .public) body=\(WanderDebugLog.clean(body), privacy: .public)")
            #endif
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw WanderRemoteError.notAuthenticated
            }
            throw WanderRemoteError.invalidResponse("Delete user_place failed with \(httpResponse.statusCode): \(body)")
        }
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
