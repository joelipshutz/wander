import Foundation

/// Uses the same RPC authorization as the full app. No service-role credential,
/// user-id parameter, persisted response cache, or token-bearing request logs.
@MainActor
final class ClipService: ClipServing {
    private let configuration: WanderBackendConfiguration
    private let auth: any AuthSessionProviding
    private let session: URLSession
    private let transport: (@MainActor (URLRequest) async throws -> (Data, HTTPURLResponse))?

    init(configuration: WanderBackendConfiguration, auth: any AuthSessionProviding, session: URLSession? = nil,
         transport: (@MainActor (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil) {
        self.configuration = configuration
        self.auth = auth
        self.transport = transport
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 20
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        self.session = session ?? URLSession(configuration: settings, delegate: ClipNoRedirect(), delegateQueue: nil)
    }

    func preview(_ route: AppClipRoute, authenticated: Bool) async throws -> ClipPreview {
        var published: ClipPreview?
        if let token = route.cardToken {
            let response = try await rpc("share_card_preview", ["input_token": token,
                "input_kind": route.kind.rawValue, "input_identifier": route.identifier], authenticated: false)
            guard let card = response as? [String: Any], let title = text(card["title"]),
                  let path = card["image_path"] as? String,
                  path.range(of: "^[A-Za-z0-9_-]+/[a-f0-9-]{36}/preview[.]png$", options: .regularExpression) != nil,
                  let root = configuration.supabaseURL else { throw ClipError.unavailable }
            published = ClipPreview(title: title, subtitle: nil,
                imageURL: root.appendingPathComponent("storage/v1/object/public/share-card-previews/" + path), places: [])
        }

        if route.kind == .place {
            let row = try await publicPreview(kind: .place, id: route.identifier)
            guard let place = place(row) else { throw ClipError.unavailable }
            return ClipPreview(title: published?.title ?? place.title, subtitle: text(row["subtitle"]),
                imageURL: published?.imageURL, places: [place])
        }
        if authenticated, route.kind == .activity {
            guard let row = try await rpc("activity_detail", ["input_activity_id": route.identifier]) as? [String: Any],
                  let projection = row["place"] as? [String: Any], let place = place(projection) else { throw ClipError.unavailable }
            return ClipPreview(title: published?.title ?? place.title, subtitle: text(row["note"]),
                imageURL: published?.imageURL, places: [place])
        }
        if authenticated, route.kind == .list {
            guard let row = try await rpc("place_list_detail", ["input_list_id": route.identifier]) as? [String: Any],
                  let list = row["list"] as? [String: Any], let title = text(list["name"]) else { throw ClipError.unavailable }
            // The list RPC has already authorized every item before exposing IDs.
            let ids = Array(Set((row["items"] as? [[String: Any]] ?? []).compactMap { $0["place_id"] as? String })).sorted()
            var places: [ClipPlace] = []
            for id in ids.prefix(20) {
                try Task.checkCancellation()
                let row = try await publicPreview(kind: .place, id: id)
                if let place = place(row) { places.append(place) }
            }
            let description = text(list["description"])
            let subtitle = ids.count > 20 ? [description, "Showing 20 of \(ids.count) places"].compactMap { $0 }.joined(separator: "\n") : description
            return ClipPreview(title: title, subtitle: subtitle, imageURL: published?.imageURL, places: places)
        }
        if authenticated, route.kind == .profile {
            let response = try await rpc("profile_visible_places", ["profile_id": route.identifier])
            guard let rows = response as? [[String: Any]] else { throw ClipError.unavailable }
            let publicRow = try? await publicPreview(kind: .profile, id: route.identifier)
            return ClipPreview(title: published?.title ?? publicRow.flatMap { text($0["title"]) } ?? "Shared map",
                subtitle: rows.count > 100 ? "Showing 100 of \(rows.count) places visible to your account" : "Places visible to your account", imageURL: published?.imageURL,
                places: rows.prefix(100).compactMap(place))
        }
        if route.kind == .profile || route.kind == .invite {
            if let row = try? await publicPreview(kind: route.kind, id: route.identifier), let title = text(row["title"]) {
                return ClipPreview(title: published?.title ?? title, subtitle: text(row["description"]),
                    imageURL: published?.imageURL ?? safeImage(row["image_url"]), places: [],
                    needsSignIn: route.kind == .profile)
            }
        }
        if let published {
            return ClipPreview(title: published.title, subtitle: nil, imageURL: published.imageURL,
                places: [], needsSignIn: [.list, .activity, .profile].contains(route.kind))
        }
        if [.list, .activity].contains(route.kind), !authenticated {
            return ClipPreview(title: route.kind == .list ? "Shared list" : "Shared activity",
                subtitle: "Sign in to see what's been shared with you.", imageURL: nil, places: [], needsSignIn: true)
        }
        throw ClipError.unavailable
    }

    func profile() async throws -> ClipProfile? {
        let value = try await rpc("current_profile", [:])
        return try decode([ClipProfile].self, value).first
    }

    func updateProfile(name: String, handle: String) async throws -> ClipProfile {
        let value = try await rpc("update_own_profile", ["input_display_name": name,
            "input_handle": handle, "input_mark_onboarding_complete": false])
        return try decode(ClipProfile.self, value)
    }

    func save(_ place: ClipPlace) async throws -> Bool {
        guard let value = try await rpc("save_app_clip_place", ["input_place_id": place.id]) as? [String: Any],
              let created = value["created"] as? Bool else { throw ClipError.server }
        return created
    }

    func join(_ route: AppClipRoute) async throws -> String {
        guard route.kind == .invite else { throw ClipError.unavailable }
        guard let id = try await rpc("accept_place_list_invite", ["input_token": route.identifier]) as? String,
              UUID(uuidString: id) != nil else { throw ClipError.server }
        return id
    }

    private func publicPreview(kind: AppClipRoute.Kind, id: String) async throws -> [String: Any] {
        guard let row = try await rpc("public_web_preview", ["input_kind": kind.rawValue, "input_identifier": id], authenticated: false) as? [String: Any],
              row["is_available"] as? Bool == true else { throw ClipError.unavailable }
        return row
    }

    private func rpc(_ name: String, _ parameters: [String: Any], authenticated: Bool = true) async throws -> Any {
        try Task.checkCancellation()
        guard let root = configuration.supabaseURL, root.scheme == "https",
              let key = configuration.supabasePublishableKey else { throw ClipError.configuration }
        let userID = auth.state.session?.userID
        if authenticated, !auth.state.isSignedIn { throw ClipError.signIn }
        let token = authenticated ? try await auth.supabaseAccessToken() : key
        try Task.checkCancellation()
        if authenticated, userID != auth.state.session?.userID { throw ClipError.signIn }
        var request = URLRequest(url: root.appendingPathComponent("rest/v1/rpc/" + name))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await send(request)
            try Task.checkCancellation()
            if authenticated, userID != auth.state.session?.userID { throw ClipError.signIn }
            guard (200...299).contains(response.statusCode) else {
                if response.statusCode == 401 { throw ClipError.signIn }
                if response.statusCode == 404 { throw ClipError.configuration }
                if response.statusCode == 403 { throw ClipError.unavailable }
                // Whitelist coarse error categories; never display raw server payloads.
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
                if ["handle_taken", "invalid_handle", "invalid_display_name", "profile_not_found"].contains(code) { throw ClipError.profile }
                if code.contains("invite") || code == "activity_not_visible" { throw ClipError.unavailable }
                throw ClipError.server
            }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClipError { throw error }
        catch { throw ClipError.connection }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let transport { return try await transport(request) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClipError.connection }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_097_152 else { throw ClipError.server }
            data.append(byte)
        }
        return (data, response)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }
    private func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = String(value.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func safeImage(_ value: Any?) -> URL? {
        guard let value = value as? String, let url = URL(string: value), url.scheme == "https",
              url.host == configuration.supabaseURL?.host, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private func place(_ row: [String: Any]) -> ClipPlace? {
        guard let id = row["place_id"] as? String,
              let title = text(row["canonical_name"] ?? row["title"]),
              let latitude = row["latitude"] as? Double, let longitude = row["longitude"] as? Double else { return nil }
        return ClipPlace(id: id, title: title, address: text(row["address"]), latitude: latitude, longitude: longitude)
    }
}

private final class ClipNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
