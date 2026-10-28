import Combine
import Foundation

@MainActor
final class ListPlaceSearchModel: ObservableObject {
    @Published private(set) var candidates: [PlaceCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private var generation = 0

    func search(
        _ text: String,
        debounce: Duration = .milliseconds(300),
        resolve: @MainActor (String) async throws -> [PlaceCandidate]
    ) async {
        generation += 1
        let request = generation
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates = []
        errorMessage = nil
        isSearching = !query.isEmpty
        guard !query.isEmpty else { return }

        defer {
            if request == generation { isSearching = false }
        }
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let results = try await resolve(query)
            // Some providers complete even after cancellation. A previous query
            // must never replace results or loading/error state for the new one.
            guard !Task.isCancelled, request == generation else { return }
            candidates = results
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            if error as? PlaceResolutionError != .noCandidates {
                errorMessage = "Couldn’t Find Places. Check Your Connection And Try Again."
            }
        }
    }

    func removeCandidate(id: String) {
        candidates.removeAll { $0.id == id }
    }
}
