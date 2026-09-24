import Combine
import Foundation

@MainActor final class PeopleSearchModel: ObservableObject {
    @Published private(set) var profiles: [ProfileShell] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation = UUID()

    func search(
        query: String,
        local: (String) -> [ProfileShell],
        remote: (String) async throws -> [ProfileShell],
        debounce: Duration = .milliseconds(225)
    ) async {
        let request = UUID()
        generation = request
        let normalized = query.replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        failed = false
        profiles = normalized.count >= 2 ? local(normalized) : []
        isLoading = normalized.count >= 2
        guard isLoading else { return }
        defer { if generation == request { isLoading = false } }
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let results = try await remote(normalized)
            guard generation == request, !Task.isCancelled else { return }
            profiles = results
        } catch is CancellationError {
            return
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            failed = true
        }
    }
}
