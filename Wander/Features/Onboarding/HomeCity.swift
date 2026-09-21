import CoreLocation
import Foundation

/// A locality, not an address. Only coarse city metadata is persisted.
struct HomeCity: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let countryCode: String
    var region: String?
    var county: String?

    enum CodingKeys: String, CodingKey {
        case name, region, county
        case countryCode = "country_code"
    }

    var id: String { [name, region ?? "", countryCode].joined(separator: "|") }
    var subtitle: String {
        [region, Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    var metroID: String {
        let normalizedCounty = county?.lowercased().replacingOccurrences(of: " county", with: "")
        return countryCode == "US" && ["CA", "California"].contains(region ?? "")
            && normalizedCounty == "los angeles" ? "los-angeles" : HomeMetro.otherID
    }

    static let losAngeles = HomeCity(name: "Los Angeles", countryCode: "US", region: "CA", county: "Los Angeles")

    static func from(_ placemark: CLPlacemark) -> HomeCity? {
        guard let name = placemark.locality, !name.isEmpty,
              let country = placemark.isoCountryCode else { return nil }
        return HomeCity(name: name, countryCode: country, region: placemark.administrativeArea, county: placemark.subAdministrativeArea)
    }

    /// Reads homes saved by the earlier metro version without losing them on travel.
    static func legacy(_ metroID: String?) -> HomeCity? {
        guard let metro = HomeMetro.find(metroID) else { return nil }
        if metro.id == "los-angeles" { return .losAngeles }
        return HomeCity(name: metro.name, countryCode: metro.country)
    }
}

struct HomeCitySuggestion: Equatable, Identifiable, Sendable {
    let title: String
    let subtitle: String
    var city: HomeCity?
    var id: String { [title, subtitle].joined(separator: "|") }
    init(title: String, subtitle: String, city: HomeCity? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.city = city
    }
    init(city: HomeCity) { self.init(title: city.name, subtitle: city.subtitle, city: city) }
}
