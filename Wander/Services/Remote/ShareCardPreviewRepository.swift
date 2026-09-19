import Foundation

@MainActor
protocol ShareCardPreviewRepository {
    func publish(content: WanderShareContent, previewPNG: Data) async throws -> WanderShareContent
}

struct ShareCardLinkTarget: Equatable {
    let kind: String
    let identifier: String

    init?(url: URL) {
        guard url.scheme == "https", url.host == "getrec.me", url.fragment == nil,
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
        // Keep preview links outside AASA paths claimed by older installed apps.
        // Their query-free deep-link parser would otherwise swallow this link.
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
