import Foundation

/// Shares the full app's strict canonical route validation. Preview tokens are
/// retained for the published artwork, never used to authorize account actions.
struct AppClipRoute: Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case profile, place, list, activity, invite }
    let url: URL
    let kind: Kind
    let identifier: String
    let cardToken: String?

    init?(url: URL) {
        guard url.scheme == "https", let route = WanderDeepLinkRoute.parse(url) else { return nil }
        switch route {
        case .sharedProfile(let id): kind = .profile; identifier = id
        case .sharedPlace(let id): kind = .place; identifier = id
        case .sharedList(let id): kind = .list; identifier = id
        case .sharedActivity(let id): kind = .activity; identifier = id
        case .listInvite(let id): kind = .invite; identifier = id
        default: return nil
        }
        self.url = url
        cardToken = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "card" })?.value
    }
}

struct AppClipContinuation: Codable, Equatable {
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    let url: URL
    let userID: String?
    let createdAt: Date

    func route(for userID: String, now: Date = Date()) -> AppClipRoute? {
        guard createdAt <= now, now.timeIntervalSince(createdAt) <= Self.lifetime,
              self.userID == nil || self.userID == userID else { return nil }
        return AppClipRoute(url: url)
    }
}

enum AppClipHandoff {
    static let group = "group.com.grayline.wander.clip"
    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("continuation-v1.json")
    }

    static func save(route: AppClipRoute, userID: String?) throws {
        guard let file else { throw CocoaError(.fileWriteNoPermission) }
        let value = AppClipContinuation(url: route.url, userID: userID, createdAt: Date())
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> AppClipContinuation? {
        guard let file, let data = try? Data(contentsOf: file), data.count < 4096 else { return nil }
        return try? JSONDecoder().decode(AppClipContinuation.self, from: data)
    }

    static func clear() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
