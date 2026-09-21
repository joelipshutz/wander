#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit

/// Fictional data injected only by an explicit authenticated UI test launch.
@MainActor final class ContactDiscoveryUITestRepository: ProfileRepository, FollowRepository, ContactDiscoveryRepository {
    static let argument = "-WanderContactDiscoveryUITest"
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(argument) && SimulatorTestSessionPolicy.isActive() }
    private var enabled = false
    private var followed = Set<String>()
    private var followAttempts = 0
    private let friend = ProfileShell(id: "user_contact_friend", handle: "contactfriend", displayName: "Contact Friend", avatarURL: nil, bio: nil, relationship: .nonFollower)
    private let general = ProfileShell(id: "user_general_friend", handle: "generalfriend", displayName: "General Friend", avatarURL: nil, bio: nil, relationship: .nonFollower)
    func currentProfile() async throws -> LocalProfile? { LocalProfile(localID: "user_joe", handle: "joe", displayName: "Joe") }
    func profile(id: String) async throws -> ProfileViewState { throw ContactDiscoveryError.unavailable }
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] { [friend, general].filter { $0.displayName.lowercased().contains(handleQuery.lowercased()) } }
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        [.init(profile: general, reason: .suggested, rank: 1), .init(profile: friend, reason: .suggested, rank: 2)]
    }
    func rankedPeopleRecommendations(contactIDs: [String], limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        let curated = ProfileShell(id: "user_curated_rachel", handle: "rachelfixture", displayName: "Rachel (preview)", avatarURL: nil, bio: nil, relationship: .nonFollower)
        let local = ProfileShell(id: "user_local_friend", handle: "localfriend", displayName: "Local Friend", avatarURL: nil, bio: nil, homeArea: "Los Angeles", relationship: .nonFollower)
        let contact = contactIDs.contains(friend.id) ? [DiscoverPeopleRecommendation(profile: friend, reason: .contacts, rank: 2)] : []
        let rows = [.init(profile: curated, reason: .suggested, rank: 1)] + contact
            + [.init(profile: local, reason: .nearby, rank: 3), .init(profile: general, reason: .suggested, rank: 4)]
        return Array(rows.prefix(limit))
    }
    func follow(userID: String) async throws {
        followAttempts += 1
        if ProcessInfo.processInfo.arguments.contains("-WanderContactDiscoveryDelayedFollow") {
            try await Task.sleep(for: .seconds(2))
            if followAttempts == 1 { throw ContactDiscoveryError.unavailable }
        }
        followed.insert(userID)
    }
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

@MainActor private final class ContactDiscoveryUITestProvider: ContactProvider {
    private var revoked = false
    private var hasRequestedAccess = false
    private var foregroundObserver: NSObjectProtocol?
    init() {
        if ProcessInfo.processInfo.arguments.contains("-WanderContactDiscoveryRevokeOnForeground") {
            foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    // Cold launch also enters the foreground. Simulate a Settings
                    // revocation only after the test has explicitly enabled access.
                    guard let self, self.hasRequestedAccess else { return }
                    self.revoked = true
                }
            }
        }
    }
    func authorization() async -> ContactProviderAuthorization {
        revoked || ProcessInfo.processInfo.arguments.contains("-WanderContactDiscoveryDenied") ? .denied : .authorized
    }
    func requestAccess() async -> ContactProviderAuthorization {
        hasRequestedAccess = true
        return await authorization()
    }
    func matches() async throws -> [ContactMatch] { [] }
    func discoveryIdentifiers() async throws -> [ContactDiscoveryIdentifier] { [.init(kind: .email, value: "friend@example.test")] }
}
#endif
