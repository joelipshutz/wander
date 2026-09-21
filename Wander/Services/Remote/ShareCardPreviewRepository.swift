import Foundation

@MainActor
protocol ShareCardPreviewRepository {
    func publish(content: WanderShareContent, previewPNG: Data) async throws -> WanderShareContent
}

enum ShareCardPreparationError: Error, Equatable {
    case artwork, publication, connection, session, unavailable, configuration

    var title: String {
        self == .artwork ? "Couldn't make the share image" : "Couldn't create the share link"
    }

    var message: String {
        switch self {
        case .artwork: "Try sharing this item again."
        case .connection: "Check your internet connection, then try sharing again."
        case .session: "Your session needs to reconnect. Reopen Astir, then try sharing again."
        case .unavailable: "This item is no longer available to share. Reopen the item and try again."
        case .configuration: "Sharing isn't available right now. Please try again later."
        case .publication: "The share link couldn't be created. Please try again in a moment."
        }
    }

    static func publicationFailure(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        if error is URLError { return .connection }
        switch error as? WanderRemoteError {
        case .notAuthenticated: return .session
        case .notConfigured: return .configuration
        case .invalidResponse(let reason) where reason.contains("share_target_unavailable"):
            return .unavailable
        default: return .publication
        }
    }
}

/// Existing external place links have no Astir entity to publish. Keep those
/// one-URL shares local; canonical Astir links still require their approved card.
@MainActor
enum ShareCardLinkPreparation {
    static func isExternalPlaceLink(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "www.google.com" && url.path == "/maps/dir"
            && url.user == nil && url.password == nil && url.port == nil && url.fragment == nil
    }

    static func prepare(
        content: WanderShareContent,
        repository: (any ShareCardPreviewRepository)?,
        previewPNG: () async throws -> Data
    ) async throws -> WanderShareContent {
        try Task.checkCancellation()
        if isExternalPlaceLink(content.item) { return content.withLink(content.item) }
        guard ShareCardLinkTarget(url: content.item) != nil else { throw ShareCardPreparationError.unavailable }
        guard let repository else { throw ShareCardPreparationError.configuration }
        do {
            let png = try await previewPNG()
            try Task.checkCancellation()
            let result = try await repository.publish(content: content, previewPNG: png)
            try Task.checkCancellation()
            return result
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let error = error as? URLError, error.code == .cancelled { throw CancellationError() }
            throw ShareCardPreparationError.publicationFailure(error)
        }
    }
}

struct ShareCardLinkTarget: Equatable {
    let kind: String
    let identifier: String

    init?(url: URL) {
        guard url.scheme == "https", url.host == "getrec.me", url.fragment == nil,
              !url.path.hasPrefix("/cards/"),
              let route = WanderDeepLinkRoute.parse(url) else { return nil }
        switch route {
        case .sharedProfile(let id): kind = "profile"; identifier = id
        case .sharedPlace(let id): kind = "place"; identifier = id
        case .sharedList(let id): kind = "list"; identifier = id
        case .sharedActivity(let id): kind = "activity"; identifier = id
        case .listInvite(let token): kind = "invite"; identifier = token
        default: return nil
        }
    }

    static func link(_ url: URL, token: String) -> URL? {
        guard token.range(of: "^[a-f0-9]{48}$", options: .regularExpression) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // The website keeps the token-backed preview; compatible apps unwrap
        // this route to the original entity without carrying the preview token.
        parts.percentEncodedPath = "/cards" + parts.percentEncodedPath
        parts.queryItems = [URLQueryItem(name: "card", value: token)]
        return parts.url
    }
}

@MainActor
final class SupabaseShareCardPreviewRepository: ShareCardPreviewRepository {
    static let bucket = "share-card-previews"
    private let rpc: any RemoteProcedureCalling
    private let storage: any RemoteStorageCalling
    private let authSession: any AuthSessionProviding

    init(rpc: any RemoteProcedureCalling, storage: any RemoteStorageCalling, authSession: any AuthSessionProviding) {
        self.rpc = rpc
        self.storage = storage
        self.authSession = authSession
    }

    func publish(content: WanderShareContent, previewPNG: Data) async throws -> WanderShareContent {
        guard case .signedIn(let session) = authSession.state else { throw WanderRemoteError.notAuthenticated }
        guard let target = ShareCardLinkTarget(url: content.item),
              session.userID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              previewPNG.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
              previewPNG.count <= 5_242_880 else { throw WanderRemoteError.invalidResponse("invalid_share_card") }
        let path = "\(session.userID)/\(UUID().uuidString.lowercased())/preview.png"
        try await storage.uploadObject(bucket: Self.bucket, path: path, data: previewPNG, contentType: "image/png", upsert: false)
        do {
            try Task.checkCancellation()
            let result: CreatedCard = try await rpc.call("create_share_card_preview", params: [
                "input_kind": target.kind, "input_identifier": target.identifier,
                "input_image_path": path, "input_title": content.subject
            ])
            guard let url = ShareCardLinkTarget.link(content.item, token: result.token) else {
                throw WanderRemoteError.invalidResponse("invalid_share_card_token")
            }
            return content.withLink(url)
        } catch {
            try? await storage.deleteObject(bucket: Self.bucket, path: path)
            throw error
        }
    }
}

private struct CreatedCard: Decodable { let token: String }
