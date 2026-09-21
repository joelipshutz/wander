import CoreLocation
import Foundation

struct HomeMetroSuggestion: Equatable {
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

    func suggestion() async throws -> HomeMetroSuggestion? {
        // .map does not prompt for permission or demand precise location. Never
        // use MapLaunchLocationResolver: its Santa Monica fallback is not a fix.
        let location = try await locationProvider.currentLocation()
        try Task.checkCancellation()
        let placemark = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first
        guard let country = placemark?.isoCountryCode else { return nil }
        guard let placemark, let city = HomeCity.from(placemark) else { return nil }
        return HomeMetroSuggestion(metroID: city.metroID, countryCode: country, city: city)
    }
}
