import Foundation

@MainActor
final class OnboardingFriendSuggestionsModel: ObservableObject {
    // Canonical Joe/Ryan targets from the existing signup-default migration.
    // This is onboarding presentation only; membership comes from the real graph.
    static let defaultFollowProfileIDs = [
        "user_3EhATWssjvHxwGiUaoWR5VTgeoy", // Joe
        "user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc" // Ryan
    ]

    enum LoadingState: Equatable {
        case idle, loading, loaded, failed
    }

    @Published private(set) var recommendations: [DiscoverPeopleRecommendation] = []
    @Published private(set) var defaultFollowProfiles: [ProfileShell] = []
    @Published var query = ""
    @Published private(set) var searchResults: [ProfileShell] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var searchState: LoadingState = .idle
    @Published private(set) var pendingIDs: Set<String> = []
    @Published private(set) var followedIDs: Set<String> = []
    @Published private(set) var followErrors: [String: String] = [:]
    @Published private(set) var completedFollowCount = 0

    private let fetchRecommendations: () async throws -> [DiscoverPeopleRecommendation]
    private let searchProfiles: (String) async throws -> [ProfileShell]
    private let fetchFollowing: () async throws -> [ProfileShell]
    private let createFollow: (String) async throws -> Void
    private var searchGeneration = 0
    private var loadGeneration = 0

    convenience init(backend: WanderBackend, userID: String) {
        self.init(
            recommendations: { try await backend.peopleRecommendations(userID: userID, limit: 20) },
            search: { try await backend.searchProfiles(handleQuery: $0) },
            following: { try await backend.following(userID: userID) },
            follow: { try await backend.follow(userID: $0) }
        )
    }

    init(
        recommendations: @escaping () async throws -> [DiscoverPeopleRecommendation],
        search: @escaping (String) async throws -> [ProfileShell],
        following: @escaping () async throws -> [ProfileShell],
        follow: @escaping (String) async throws -> Void
    ) {
        fetchRecommendations = recommendations
        searchProfiles = search
        fetchFollowing = following
        createFollow = follow
    }

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    var isSearching: Bool { !normalizedQuery.isEmpty }
    var visibleProfiles: [ProfileShell] {
        guard !isSearching else { return searchResults }
        let pinnedIDs = Set(defaultFollowProfiles.map(\.id))
        return defaultFollowProfiles + recommendations.map(\.profile).filter { !pinnedIDs.contains($0.id) }
    }
    var isFollowing: Bool { !pendingIDs.isEmpty }

    func isFollowed(_ profile: ProfileShell) -> Bool {
        followedIDs.contains(profile.id) || profile.relationship == .follower || profile.relationship == .mutual
    }

    func clearContactRecommendations() {
        loadGeneration += 1
        recommendations.removeAll { $0.reason == .contacts }
    }

    func load(force: Bool = false) async {
        guard force || loadingState == .idle || loadingState == .failed else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let followedAtStart = followedIDs
        loadingState = .loading
        do {
            // Search RPCs omit relationship data. Load the viewer's real graph
            // before offering follow actions, including resumed onboarding.
            let following = try await fetchFollowing()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let loaded = try await fetchRecommendations()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            // Respect an external unfollow on refresh while retaining any explicit
            // follow that completed while this snapshot was being fetched.
            followedIDs = Set(following.map(\.id)).union(followedIDs.subtracting(followedAtStart))
            defaultFollowProfiles = Self.defaultFollowProfileIDs.compactMap { id in
                following.first { $0.id == id }
            }
            recommendations = loaded
            loadingState = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadingState = .failed
        }
    }

    func search(debounce: Duration = .milliseconds(300)) async {
        searchGeneration += 1
        let generation = searchGeneration
        let term = normalizedQuery
        searchResults = []
        guard term.count >= 2 else {
            searchState = .idle
            return
        }
        searchState = .loading
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let results = try await searchProfiles(term)
            guard !Task.isCancelled, generation == searchGeneration, term == normalizedQuery else { return }
            searchResults = results
            searchState = .loaded
        } catch is CancellationError {
            // A new query owns the visible state.
        } catch {
            guard !Task.isCancelled, generation == searchGeneration, term == normalizedQuery else { return }
            searchState = .failed
        }
    }

    @discardableResult
    func follow(_ profile: ProfileShell) async -> Bool {
        guard loadingState == .loaded, !isFollowed(profile), !pendingIDs.contains(profile.id) else { return false }
        pendingIDs.insert(profile.id)
        followErrors[profile.id] = nil
        defer { pendingIDs.remove(profile.id) }
        do {
            try await createFollow(profile.id)
            followedIDs.insert(profile.id)
            completedFollowCount += 1
            return true
        } catch {
            followErrors[profile.id] = "Couldn’t follow. Tap to retry."
            return false
        }
    }
}
