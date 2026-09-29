import Combine
import Foundation

@MainActor
final class PersonTypeaheadModel: ObservableObject {
    @Published private(set) var profiles: [ProfileShell] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation = UUID()
    private var ownerID: String?
    private var recommendations: [ProfileShell]?

    func search(
        query: String?, ownerID: String,
        local: () -> [ProfileShell],
        recommendations loadRecommendations: () async throws -> [ProfileShell],
        remote: (String) async throws -> [ProfileShell],
        eligible: (ProfileShell) -> Bool,
        debounce: Duration = .milliseconds(180)
    ) async {
        let request = UUID()
        generation = request
        if self.ownerID != ownerID {
            self.ownerID = ownerID
            recommendations = nil
        }
        failed = false
        guard let query else {
            profiles = []
            // Recheck contact consent and ranking when the next picker opens.
            recommendations = nil
            isLoading = false
            return
        }
        profiles = PersonMentionCandidates.matching(
            (local() + (recommendations ?? [])).filter(eligible), query: query
        )
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            if recommendations == nil {
                do {
                    let ranked = try await loadRecommendations()
                    guard generation == request, !Task.isCancelled else { return }
                    recommendations = ranked
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == request, !Task.isCancelled else { return }
                    // A recommendations outage must not disable explicit search.
                    failed = query.isEmpty
                }
            }
            var candidates = local() + (recommendations ?? [])
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let matches = try await remote(query)
                guard generation == request, !Task.isCancelled else { return }
                candidates += matches
            }
            guard generation == request, !Task.isCancelled else { return }
            profiles = PersonMentionCandidates.matching(candidates.filter(eligible), query: query)
        } catch is CancellationError {
            return
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            failed = true
            profiles = PersonMentionCandidates.matching(
                (local() + (recommendations ?? [])).filter(eligible), query: query
            )
        }
    }
}

extension WanderStore {
    /// Known connections first; the shared recommender excludes existing follows.
    /// The picker never treats a mention as an invitation or visibility grant.
    var personTypeaheadConnections: [ProfileShell] {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-WanderPersonTypeaheadUITest"),
           (ProcessInfo.processInfo.arguments.contains("-WanderUseStorefrontFixtures")
                || ProcessInfo.processInfo.arguments.contains("-WanderUseDemoFixtures")) {
            return PersonTypeaheadUITestFixtures.profiles
        }
        #endif
        return (friends(of: currentUser.id) + following(of: currentUser.id) + followers(of: currentUser.id))
            .map(shell(for:))
            .filter(isEligibleForPersonTypeahead)
    }

    func isEligibleForPersonTypeahead(_ profile: ProfileShell) -> Bool {
        profile.id != currentUser.id && profile.isPrivateProfile != true
            && !isProfilePrivate(profile.id) && !isBlockedBetweenCurrentUser(and: profile.id)
    }
}
