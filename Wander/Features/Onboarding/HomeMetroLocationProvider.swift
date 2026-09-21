import CoreLocation
import Foundation

struct HomeMetroSuggestion: Equatable, Sendable {
    let metroID: String?
    let countryCode: String
    var city: HomeCity? = nil
}

#if DEBUG && targetEnvironment(simulator)
@MainActor struct SimulatorHomeMetroLocationProvider: HomeMetroLocationProviding {
    func suggestion() async throws -> HomeMetroSuggestion? {
        HomeMetroSuggestion(metroID: "los-angeles", countryCode: "US", city: .losAngeles)
    }
}
#endif

@MainActor protocol HomeMetroLocationProviding {
    func suggestion() async throws -> HomeMetroSuggestion?
}

@MainActor struct HomeMetroLocationProvider: HomeMetroLocationProviding {
    var locationProvider: any CurrentLocationProviding = CoreLocationProvider(purpose: .map)
    var recentLocation: () -> CLLocation? = { HomeMetroLocationProvider.recentAuthorizedLocation() }
    var reverseGeocode: (CLLocation) async throws -> HomeCity? = { location in
        try await HomeMetroLocationProvider.city(at: location)
    }
    var budget: Duration = .seconds(3)

    func suggestion() async throws -> HomeMetroSuggestion? {
        // The field is already usable with its fallback. Bound this background
        // prefill, reuse an authorized recent fix, and never prompt for location.
        let work = Task { @MainActor in
            let location: CLLocation
            if let recent = recentLocation() { location = recent }
            else { location = try await locationProvider.currentLocation() }
            try Task.checkCancellation()
            guard let city = try await reverseGeocode(location) else { return nil as HomeMetroSuggestion? }
            try Task.checkCancellation()
            return HomeMetroSuggestion(metroID: city.metroID, countryCode: city.countryCode, city: city)
        }
        let timeout = Task { @MainActor in
            try await Task.sleep(for: budget)
            work.cancel()
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await work.value
        } onCancel: { work.cancel() }
    }

    private static func recentAuthorizedLocation() -> CLLocation? {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return nil }
        guard let location = manager.location ?? LastSharedLocationStore().location,
              LastSharedLocationStore.isValid(location),
              location.timestamp.timeIntervalSinceNow >= -120 else { return nil }
        return location
    }

    private static func city(at location: CLLocation) async throws -> HomeCity? {
        let geocoder = CLGeocoder()
        let cancel: @MainActor @Sendable () -> Void = { geocoder.cancelGeocode() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let placemark = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first
            return placemark.flatMap(HomeCity.from)
        } onCancel: { Task { await cancel() } }
    }
}
