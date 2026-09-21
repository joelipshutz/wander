import MapKit

@MainActor protocol HomeCitySearchProviding {
    func suggestions(for query: String) async throws -> [HomeCitySuggestion]
    func resolve(_ suggestion: HomeCitySuggestion) async throws -> HomeCity
}

@MainActor enum HomeCitySearchProviderFactory {
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> any HomeCitySearchProviding {
        #if DEBUG && targetEnvironment(simulator)
        // Fictional account/location fixtures must not limit manual city search.
        // Only automated tests explicitly opt into the small deterministic list.
        if arguments.contains("-WanderHomeCitySearchFixtures"),
           !arguments.contains("-WanderHomeCityLiveSearch") {
            return SimulatorHomeCitySearchProvider()
        }
        #endif
        return MapKitHomeCitySearchProvider()
    }
}

/// No country restriction or local search region: suggestions cover the world.
/// One autocomplete request per settled query, one detail lookup on selection.
@MainActor final class MapKitHomeCitySearchProvider: HomeCitySearchProviding {
    func suggestions(for query: String) async throws -> [HomeCitySuggestion] {
        if #available(iOS 18.0, *) {
            return try await CityCompletionRequest().results(for: query)
        }
        // iOS 17 has no locality filter on autocomplete. Resolve one search and
        // reject streets/POIs instead of presenting street addresses as cities.
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response = try await search(request)
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            guard item.placemark.thoroughfare == nil, let city = HomeCity.from(item.placemark), seen.insert(city.id).inserted else { return nil }
            return HomeCitySuggestion(city: city)
        }
    }

    func resolve(_ suggestion: HomeCitySuggestion) async throws -> HomeCity {
        if let city = suggestion.city { return city }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [suggestion.title, suggestion.subtitle].joined(separator: ", ")
        request.resultTypes = .address
        if #available(iOS 18.0, *) { request.addressFilter = MKAddressFilter(including: .locality) }
        let response = try await search(request)
        guard let city = response.mapItems.compactMap({ HomeCity.from($0.placemark) }).first else {
            throw URLError(.cannotParseResponse)
        }
        return city
    }

    private func search(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        let search = MKLocalSearch(request: request)
        let cancel: @MainActor @Sendable () -> Void = { search.cancel() }
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(8))
            search.cancel()
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await search.start()
        } onCancel: {
            Task { await cancel() }
        }
    }
}

/// A separate delegate per query prevents late results from an older fragment
/// being mistaken for the newest query. Cancellation always resumes the waiter.
@available(iOS 18.0, *)
@MainActor private final class CityCompletionRequest: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[HomeCitySuggestion], Error>?

    func results(for query: String) async throws -> [HomeCitySuggestion] {
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(6))
            finish(.failure(URLError(.timedOut)))
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                completer.delegate = self
                completer.resultTypes = .address
                completer.addressFilter = MKAddressFilter(including: .locality)
                completer.queryFragment = query
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var seen = Set<String>()
        let results = completer.results.map { HomeCitySuggestion(title: $0.title, subtitle: $0.subtitle) }
            .filter { seen.insert($0.id).inserted }
        let suggestions = Array(results.prefix(6))
        Task { @MainActor in self.finish(.success(suggestions)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    private func finish(_ result: Result<[HomeCitySuggestion], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        completer.delegate = nil
        completer.cancel()
        continuation.resume(with: result)
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor struct SimulatorHomeCitySearchProvider: HomeCitySearchProviding {
    static let cities: [HomeCity] = [
        .losAngeles,
        .init(name: "Long Beach", countryCode: "US", region: "CA", county: "Los Angeles"),
        .init(name: "Pasadena", countryCode: "US", region: "CA", county: "Los Angeles"),
        .init(name: "Irvine", countryCode: "US", region: "CA", county: "Orange"),
        .init(name: "Paris", countryCode: "FR", region: "Île-de-France"),
        .init(name: "Paris", countryCode: "US", region: "TX", county: "Lamar"),
        .init(name: "Parintins", countryCode: "BR", region: "Amazonas"),
        .init(name: "Kyoto", countryCode: "JP", region: "Kyoto"),
        .init(name: "Nairobi", countryCode: "KE", region: "Nairobi"),
        .init(name: "São Paulo", countryCode: "BR", region: "São Paulo")
    ]
    func suggestions(for query: String) async throws -> [HomeCitySuggestion] {
        if query == "Par" { try await Task.sleep(for: .seconds(2)) }
        if query == "offline" { throw URLError(.notConnectedToInternet) }
        return Self.cities.filter { $0.name.localizedStandardContains(query) }.map(HomeCitySuggestion.init(city:))
    }
    func resolve(_ suggestion: HomeCitySuggestion) async throws -> HomeCity {
        guard let city = suggestion.city else { throw URLError(.cannotParseResponse) }
        return city
    }
}
#endif
