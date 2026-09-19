import Foundation

@MainActor
final class OnboardingFriendSuggestionsModel: ObservableObject {
    enum LoadingState: Equatable {
        case idle, loading, loaded, failed
    }

    @Published private(set) var recommendations: [DiscoverPeopleRecommendation] = []
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

    convenience init(backend: WanderBackend, userID: String) {
        self.init(
            recommendations: { try await backend.discoverProfileRecommendations(limit: 12) },
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
        isSearching ? searchResults : recommendations.map(\.profile)
    }
    var isFollowing: Bool { !pendingIDs.isEmpty }

    func isFollowed(_ profile: ProfileShell) -> Bool {
        followedIDs.contains(profile.id) || profile.relationship == .follower || profile.relationship == .mutual
    }

    func load() async {
        guard loadingState == .idle || loadingState == .failed else { return }
        loadingState = .loading
        do {
            // Search RPCs omit relationship data. Load the viewer's real graph
            // before offering follow actions, including resumed onboarding.
            let following = try await fetchFollowing()
            followedIDs.formUnion(following.map(\.id))
            recommendations = try await fetchRecommendations()
            loadingState = .loaded
        } catch {
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
