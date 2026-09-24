import Foundation

/// Product areas, not municipalities. Coordinates describe public metro centers,
/// never a member's location. LA deliberately follows the county, not the wider MSA.
struct HomeMetro: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double

    static let otherID = "other"
    static let all: [HomeMetro] = [
        .init(id: "los-angeles", name: "Los Angeles", country: "US", latitude: 34.05, longitude: -118.24),
        .init(id: "orange-county", name: "Orange County", country: "US", latitude: 33.72, longitude: -117.83),
        .init(id: "inland-empire", name: "Inland Empire", country: "US", latitude: 34.05, longitude: -117.40),
        .init(id: "new-york", name: "New York", country: "US", latitude: 40.71, longitude: -74.01),
        .init(id: "san-francisco", name: "San Francisco Bay Area", country: "US", latitude: 37.63, longitude: -122.19),
        .init(id: "chicago", name: "Chicago", country: "US", latitude: 41.88, longitude: -87.63),
        .init(id: "boston", name: "Boston", country: "US", latitude: 42.36, longitude: -71.06),
        .init(id: "washington", name: "Washington, DC", country: "US", latitude: 38.91, longitude: -77.04),
        .init(id: "philadelphia", name: "Philadelphia", country: "US", latitude: 39.95, longitude: -75.17),
        .init(id: "miami", name: "Miami–Fort Lauderdale", country: "US", latitude: 25.99, longitude: -80.20),
        .init(id: "atlanta", name: "Atlanta", country: "US", latitude: 33.75, longitude: -84.39),
        .init(id: "dallas", name: "Dallas–Fort Worth", country: "US", latitude: 32.78, longitude: -97.00),
        .init(id: "houston", name: "Houston", country: "US", latitude: 29.76, longitude: -95.37),
        .init(id: "austin", name: "Austin", country: "US", latitude: 30.27, longitude: -97.74),
        .init(id: "san-antonio", name: "San Antonio", country: "US", latitude: 29.42, longitude: -98.49),
        .init(id: "seattle", name: "Seattle", country: "US", latitude: 47.61, longitude: -122.33),
        .init(id: "portland", name: "Portland", country: "US", latitude: 45.52, longitude: -122.68),
        .init(id: "san-diego", name: "San Diego", country: "US", latitude: 32.72, longitude: -117.16),
        .init(id: "sacramento", name: "Sacramento", country: "US", latitude: 38.58, longitude: -121.49),
        .init(id: "las-vegas", name: "Las Vegas", country: "US", latitude: 36.17, longitude: -115.14),
        .init(id: "phoenix", name: "Phoenix", country: "US", latitude: 33.45, longitude: -112.07),
        .init(id: "denver", name: "Denver", country: "US", latitude: 39.74, longitude: -104.99),
        .init(id: "salt-lake-city", name: "Salt Lake City", country: "US", latitude: 40.76, longitude: -111.89),
        .init(id: "minneapolis", name: "Minneapolis–Saint Paul", country: "US", latitude: 44.95, longitude: -93.18),
        .init(id: "detroit", name: "Detroit", country: "US", latitude: 42.33, longitude: -83.05),
        .init(id: "st-louis", name: "St. Louis", country: "US", latitude: 38.63, longitude: -90.20),
        .init(id: "kansas-city", name: "Kansas City", country: "US", latitude: 39.10, longitude: -94.58),
        .init(id: "nashville", name: "Nashville", country: "US", latitude: 36.16, longitude: -86.78),
        .init(id: "charlotte", name: "Charlotte", country: "US", latitude: 35.23, longitude: -80.84),
        .init(id: "raleigh", name: "Raleigh–Durham", country: "US", latitude: 35.90, longitude: -78.80),
        .init(id: "tampa", name: "Tampa Bay", country: "US", latitude: 27.95, longitude: -82.46),
        .init(id: "orlando", name: "Orlando", country: "US", latitude: 28.54, longitude: -81.38),
        .init(id: "new-orleans", name: "New Orleans", country: "US", latitude: 29.95, longitude: -90.07),
        .init(id: "pittsburgh", name: "Pittsburgh", country: "US", latitude: 40.44, longitude: -80.00),
        .init(id: "cleveland", name: "Cleveland", country: "US", latitude: 41.50, longitude: -81.69),
        .init(id: "columbus", name: "Columbus", country: "US", latitude: 39.96, longitude: -83.00),
        .init(id: "indianapolis", name: "Indianapolis", country: "US", latitude: 39.77, longitude: -86.16),
        .init(id: "cincinnati", name: "Cincinnati", country: "US", latitude: 39.10, longitude: -84.51),
        .init(id: "milwaukee", name: "Milwaukee", country: "US", latitude: 43.04, longitude: -87.91),
        .init(id: "baltimore", name: "Baltimore", country: "US", latitude: 39.29, longitude: -76.61),
        .init(id: "honolulu", name: "Honolulu", country: "US", latitude: 21.31, longitude: -157.86),
        .init(id: "toronto", name: "Toronto", country: "CA", latitude: 43.65, longitude: -79.38),
        .init(id: "vancouver", name: "Vancouver", country: "CA", latitude: 49.28, longitude: -123.12),
        .init(id: "montreal", name: "Montréal", country: "CA", latitude: 45.50, longitude: -73.57),
        .init(id: "mexico-city", name: "Mexico City", country: "MX", latitude: 19.43, longitude: -99.13),
        .init(id: "london", name: "London", country: "GB", latitude: 51.51, longitude: -0.13),
        .init(id: "paris", name: "Paris", country: "FR", latitude: 48.86, longitude: 2.35),
        .init(id: "berlin", name: "Berlin", country: "DE", latitude: 52.52, longitude: 13.40),
        .init(id: "amsterdam", name: "Amsterdam", country: "NL", latitude: 52.37, longitude: 4.90),
        .init(id: "madrid", name: "Madrid", country: "ES", latitude: 40.42, longitude: -3.70),
        .init(id: "barcelona", name: "Barcelona", country: "ES", latitude: 41.39, longitude: 2.17),
        .init(id: "rome", name: "Rome", country: "IT", latitude: 41.90, longitude: 12.50),
        .init(id: "sydney", name: "Sydney", country: "AU", latitude: -33.87, longitude: 151.21),
        .init(id: "melbourne", name: "Melbourne", country: "AU", latitude: -37.81, longitude: 144.96),
        .init(id: "tokyo", name: "Tokyo", country: "JP", latitude: 35.68, longitude: 139.69),
        .init(id: "seoul", name: "Seoul", country: "KR", latitude: 37.57, longitude: 126.98),
        .init(id: "singapore", name: "Singapore", country: "SG", latitude: 1.35, longitude: 103.82),
        .init(id: "hong-kong", name: "Hong Kong", country: "HK", latitude: 22.32, longitude: 114.17),
        .init(id: "dubai", name: "Dubai", country: "AE", latitude: 25.20, longitude: 55.27),
        .init(id: "mumbai", name: "Mumbai", country: "IN", latitude: 19.08, longitude: 72.88),
        .init(id: "delhi", name: "Delhi", country: "IN", latitude: 28.61, longitude: 77.21),
        .init(id: "sao-paulo", name: "São Paulo", country: "BR", latitude: -23.55, longitude: -46.63)
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static func find(_ id: String?) -> HomeMetro? { all.first { $0.id == id } }

    static func suggestedID(latitude: Double, longitude: Double, country: String, state: String?, county: String?) -> String? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        if country == "US", state == "CA" || state == "California" {
            let countyName = county?.lowercased().replacingOccurrences(of: " county", with: "")
            if countyName == "los angeles" { return "los-angeles" }
            if countyName == "orange" { return "orange-county" }
            if countyName == nil, distance(latitude, longitude, 34.05, -118.24) <= 80 { return nil }
            if countyName == "riverside" || countyName == "san bernardino" {
                // These counties also include distant desert areas; use the nearby metro below.
                return distance(latitude, longitude, 34.05, -117.40) <= 100 ? "inland-empire" : otherID
            }
        }
        // Never infer LA County from a radius that could include Orange/Ventura County.
        let candidates = all.filter { $0.country == country && $0.id != "los-angeles" }
        guard let nearest = candidates.min(by: {
            distance(latitude, longitude, $0.latitude, $0.longitude) < distance(latitude, longitude, $1.latitude, $1.longitude)
        }), distance(latitude, longitude, nearest.latitude, nearest.longitude) <= 80 else { return otherID }
        return nearest.id
    }

    private static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let a = pow(sin((lat2 - lat1) * radians / 2), 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * pow(sin((lon2 - lon1) * radians / 2), 2)
        return 6_371 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}
