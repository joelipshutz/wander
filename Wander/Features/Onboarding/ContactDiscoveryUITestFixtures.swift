#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Fictional data injected only by an explicit authenticated UI test launch.
@MainActor final class ContactDiscoveryUITestRepository: ProfileRepository, FollowRepository, ContactDiscoveryRepository {
    static let argument = "-WanderContactDiscoveryUITest"
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(argument) && SimulatorTestSessionPolicy.isActive() }
    private var enabled = false
    private var followed = Set<String>()
    private let friend = ProfileShell(id: "user_contact_friend", handle: "contactfriend", displayName: "Contact Friend", avatarURL: nil, bio: nil, relationship: .nonFollower)
    private let general = ProfileShell(id: "user_general_friend", handle: "generalfriend", displayName: "General Friend", avatarURL: nil, bio: nil, relationship: .nonFollower)
    func currentProfile() async throws -> LocalProfile? { LocalProfile(localID: "user_joe", handle: "joe", displayName: "Joe") }
    func profile(id: String) async throws -> ProfileViewState { throw ContactDiscoveryError.unavailable }
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] { [friend, general].filter { $0.displayName.lowercased().contains(handleQuery.lowercased()) } }
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        [.init(profile: general, reason: .suggested, rank: 1), .init(profile: friend, reason: .suggested, rank: 2)]
    }
    func follow(userID: String) async throws { followed.insert(userID) }
    func unfollow(userID: String) async throws { followed.remove(userID) }
    func followers(userID: String) async throws -> [ProfileShell] { [] }
    func following(userID: String) async throws -> [ProfileShell] { [friend, general].filter { followed.contains($0.id) } }
    func relationship(to userID: String) async throws -> ViewerRelationship { followed.contains(userID) ? .follower : .nonFollower }
    func isEnabled() async throws -> Bool { enabled }
    func setEnabled(_ enabled: Bool) async throws { self.enabled = enabled }
    func match(_ identifiers: [ContactDiscoveryIdentifier], region: String?) async throws -> [ProfileShell] {
        if ProcessInfo.processInfo.arguments.contains("-WanderContactDiscoveryFailure") { throw ContactDiscoveryError.unavailable }
        return enabled && !identifiers.isEmpty ? [friend] : []
    }
    func service(auth: AuthSessionStore) -> ContactDiscoveryService {
        let suite = "AstirContactDiscoveryUITest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ContactDiscoveryService(repository: self, provider: ContactDiscoveryUITestProvider(), defaults: defaults,
            activeUserID: { [weak auth] in auth?.state.session?.userID })
    }
}

private struct ContactDiscoveryUITestProvider: ContactProvider {
    func authorization() async -> ContactProviderAuthorization {
        ProcessInfo.processInfo.arguments.contains("-WanderContactDiscoveryDenied") ? .denied : .authorized
    }
    func requestAccess() async -> ContactProviderAuthorization { await authorization() }
    func matches() async throws -> [ContactMatch] { [] }
    func discoveryIdentifiers() async throws -> [ContactDiscoveryIdentifier] { [.init(kind: .email, value: "friend@example.test")] }
}
#endif
