import Combine
import Foundation

@MainActor final class HomeCitySearchModel: ObservableObject {
    @Published private(set) var suggestions: [HomeCitySuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isResolving = false
    @Published private(set) var message: String?
    private let provider: any HomeCitySearchProviding
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0
    private var query = ""
    private var cache: [String: [HomeCitySuggestion]] = [:]
    private var recentQueries: [String] = []

    init(provider: (any HomeCitySearchProviding)? = nil, debounce: Duration = .milliseconds(150)) {
        self.provider = provider ?? HomeCitySearchProviderFactory.make()
        self.debounce = debounce
    }

    func update(_ text: String, force: Bool = false) {
        let next = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard force || next != query else { return }
        cancel()
        query = next
        message = nil
        suggestions = []
        guard !next.isEmpty else { return }
        let key = next.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let cached = cache[key], !force {
            suggestions = cached
            if cached.isEmpty { message = "No matching cities. Try another spelling." }
            return
        }
        isSearching = true
        let current = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
                let results = try await provider.suggestions(for: next)
                guard !Task.isCancelled, current == generation else { return }
                suggestions = Array(results.prefix(6))
                cache[key] = suggestions
                recentQueries.removeAll { $0 == key }
                recentQueries.append(key)
                if recentQueries.count > 20 { cache.removeValue(forKey: recentQueries.removeFirst()) }
                if suggestions.isEmpty { message = "No matching cities. Try another spelling." }
                isSearching = false
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                isSearching = false
                message = "Couldn’t find cities. Check your connection and try again."
            }
        }
    }

    func select(_ suggestion: HomeCitySuggestion, completion: @escaping (HomeCity) -> Void) {
        cancel()
        isResolving = true
        message = nil
        let current = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let city = try await provider.resolve(suggestion)
                guard !Task.isCancelled, current == generation else { return }
                isResolving = false
                suggestions = []
                completion(city)
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                isResolving = false
                message = "Couldn’t select that city. Try again."
            }
        }
    }

    func retry() { update(query, force: true) }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isSearching = false
        isResolving = false
    }
}
