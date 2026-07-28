import Foundation

@MainActor
final class OnboardingFriendSuggestionsModel: ObservableObject {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var recommendations: [DiscoverPeopleRecommendation] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var isFollowing = false

    private let backend: WanderBackend

    init(backend: WanderBackend) {
        self.backend = backend
    }

    func load() async {
        guard loadingState == .idle || loadingState == .failed else { return }
        loadingState = .loading
        do {
            recommendations = try await backend.discoverProfileRecommendations(limit: 12)
            selectedIDs = Set(recommendations.prefix(3).map(\.profile.id))
            loadingState = .loaded
        } catch {
            loadingState = .failed
        }
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    @discardableResult
    func followSelected() async -> Int {
        guard !isFollowing else { return 0 }
        isFollowing = true
        defer { isFollowing = false }

        var followedCount = 0
        for userID in selectedIDs {
            do {
                try await backend.follow(userID: userID)
                followedCount += 1
            } catch {
                // One failed suggestion should not block the rest or app entry.
            }
        }
        return followedCount
    }
}
