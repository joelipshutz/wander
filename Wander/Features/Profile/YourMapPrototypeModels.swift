import Foundation

#if DEBUG
enum YourMapPrototypeMode: String, CaseIterable, Identifiable {
    case map
    case patterns

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum YourMapPrototypeStatus: String, CaseIterable, Identifiable, Hashable {
    case been
    case wanna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: CheckInCopy.pluralTitle
        case .wanna: "Wanna"
        }
    }

    var systemImage: String {
        switch self {
        case .been: "checkmark.circle.fill"
        case .wanna: "bookmark.fill"
        }
    }
}

enum YourMapPrototypeTimeRange: String, CaseIterable, Identifiable {
    case all
    case thisYear
    case thisMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All time"
        case .thisYear: "This year"
        case .thisMonth: "This month"
        }
    }

    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            true
        case .thisYear:
            calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .thisMonth:
            calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
    }
}

struct YourMapPrototypeLens: Equatable {
    var timeRange: YourMapPrototypeTimeRange = .all
    var statuses: Set<YourMapPrototypeStatus> = []
    var categories: Set<String> = []
    var cities: Set<String> = []
    var countries: Set<String> = []
    var tags: Set<String> = []
    var minimumRating: Double?
    var repeatOnly = false

    var activeSectionCount: Int {
        (timeRange == .all ? 0 : 1)
            + (statuses.isEmpty ? 0 : 1)
            + (categories.isEmpty ? 0 : 1)
            + (cities.isEmpty && countries.isEmpty ? 0 : 1)
            + (tags.isEmpty ? 0 : 1)
            + (minimumRating == nil ? 0 : 1)
            + (repeatOnly ? 1 : 0)
    }

    var activeOptionCount: Int {
        (timeRange == .all ? 0 : 1)
            + statuses.count
            + categories.count
            + cities.count
            + countries.count
            + tags.count
            + (minimumRating == nil ? 0 : 1)
            + (repeatOnly ? 1 : 0)
    }

    func matches(
        _ place: YourMapPrototypePlace,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard timeRange.contains(place.lastVisitedAt, now: now, calendar: calendar) else { return false }
        guard statuses.isEmpty || statuses.contains(place.status) else { return false }
        guard categories.isEmpty || categories.contains(place.category) else { return false }
        guard cities.isEmpty || cities.contains(place.city) else { return false }
        guard countries.isEmpty || countries.contains(place.country) else { return false }
        guard tags.isEmpty || !tags.isDisjoint(with: place.tags) else { return false }
        guard minimumRating.map({ place.rating >= $0 }) ?? true else { return false }
        guard !repeatOnly || place.visitCount > 1 else { return false }
        return true
    }

    mutating func toggleStatus(_ status: YourMapPrototypeStatus) {
        Self.toggle(status, in: &statuses)
    }

    mutating func toggleCategory(_ category: String) {
        Self.toggle(category, in: &categories)
    }

    mutating func toggleCity(_ city: String) {
        Self.toggle(city, in: &cities)
    }

    mutating func toggleCountry(_ country: String) {
        Self.toggle(country, in: &countries)
    }

    mutating func toggleTag(_ tag: String) {
        Self.toggle(tag, in: &tags)
    }

    private static func toggle<Value: Hashable>(_ value: Value, in values: inout Set<Value>) {
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
    }
}

struct YourMapPrototypePlace: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let status: YourMapPrototypeStatus
    let category: String
    let city: String
    let country: String
    let tags: Set<String>
    let rating: Double
    let visitCount: Int
    let lastVisitedAt: Date
}

enum YourMapPrototypeDataVolume: String, CaseIterable, Identifiable {
    case empty
    case small
    case medium
    case large

    var id: String { rawValue }

    var count: Int {
        switch self {
        case .empty: 0
        case .small: 6
        case .medium: 60
        case .large: 600
        }
    }

    static func resolved(from arguments: [String]) -> Self {
        guard let flagIndex = arguments.firstIndex(of: "-WanderYourMapPrototypeVolume") else {
            return .medium
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .medium }
        return Self(rawValue: arguments[valueIndex]) ?? .medium
    }
}

struct YourMapPrototypeDataset {
    struct CitySeed {
        let name: String
        let country: String
        let latitude: Double
        let longitude: Double
    }

    let volume: YourMapPrototypeDataVolume
    let places: [YourMapPrototypePlace]
    let now: Date

    static func make(
        volume: YourMapPrototypeDataVolume,
        now: Date = Date(timeIntervalSince1970: 1_787_623_200),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Self {
        let cities = [
            CitySeed(name: "Los Angeles", country: "United States", latitude: 34.0522, longitude: -118.2437),
            CitySeed(name: "San Francisco", country: "United States", latitude: 37.7749, longitude: -122.4194),
            CitySeed(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
            CitySeed(name: "Portland", country: "United States", latitude: 45.5152, longitude: -122.6784),
            CitySeed(name: "Chicago", country: "United States", latitude: 41.8781, longitude: -87.6298),
            CitySeed(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522)
        ]
        let categories = ["Coffee", "Restaurants", "Bars", "Bakeries", "Outdoors"]
        let tags: [[String]] = [
            ["calm", "morning"],
            ["date night", "cozy"],
            ["laptop", "quiet"],
            ["friends", "late night"],
            ["sunny", "weekend"]
        ]
        let nameStems = ["Juniper", "Dayglow", "Bar Nido", "Tartine", "Elysian", "Woodcat", "Little Fern", "North Star"]

        let places = (0..<volume.count).map { index in
            let isCuratedCoffee = index.isMultiple(of: 4)
            let city = isCuratedCoffee ? cities[0] : cities[index % cities.count]
            let category = isCuratedCoffee ? categories[0] : categories[(index * 3 + 1) % categories.count]
            let status: YourMapPrototypeStatus = index.isMultiple(of: 5) ? .wanna : .been
            let visitCount = status == .been ? 1 + (index % 4) : 0
            let daysAgo = (index * 11) % 1_400
            let visitedAt = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let latitudeOffset = Double((index * 37) % 101 - 50) / 4_000
            let longitudeOffset = Double((index * 53) % 101 - 50) / 4_000
            let tagSet = Set(tags[index % tags.count] + (isCuratedCoffee ? ["coffee"] : []))
            let placeNumber = (index / nameStems.count) + 1

            return YourMapPrototypePlace(
                id: "your-map-prototype-\(index)",
                name: "\(nameStems[index % nameStems.count]) \(placeNumber)",
                latitude: city.latitude + latitudeOffset,
                longitude: city.longitude + longitudeOffset,
                status: status,
                category: category,
                city: city.name,
                country: city.country,
                tags: tagSet,
                rating: 3.5 + (Double(index % 4) * 0.5),
                visitCount: visitCount,
                lastVisitedAt: visitedAt
            )
        }

        return Self(volume: volume, places: places, now: now)
    }

    var initialLens: YourMapPrototypeLens {
        guard volume == .medium || volume == .large else { return YourMapPrototypeLens() }
        return YourMapPrototypeLens(
            statuses: [.been],
            categories: ["Coffee"],
            cities: ["Los Angeles"]
        )
    }
}

struct YourMapPrototypeBreakdownItem: Identifiable, Equatable {
    let title: String
    let count: Int
    let fraction: Double

    var id: String { title }
}

struct YourMapPrototypeInsights: Equatable {
    let totalCount: Int
    let repeatCount: Int
    let repeatRate: Double
    let categoryBreakdown: [YourMapPrototypeBreakdownItem]
    let thisYearCount: Int
    let previousYearCount: Int
    let insight: String

    init(
        places: [YourMapPrototypePlace],
        now: Date,
        calendar: Calendar = .current
    ) {
        totalCount = places.count
        let beenPlaces = places.filter { $0.status == .been }
        repeatCount = beenPlaces.filter { $0.visitCount > 1 }.count
        repeatRate = beenPlaces.isEmpty ? 0 : Double(repeatCount) / Double(beenPlaces.count)

        let groups = Dictionary(grouping: places, by: \YourMapPrototypePlace.category)
        categoryBreakdown = groups.map { category, values in
            YourMapPrototypeBreakdownItem(
                title: category,
                count: values.count,
                fraction: places.isEmpty ? 0 : Double(values.count) / Double(places.count)
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title < rhs.title
        }

        let currentYear = calendar.component(.year, from: now)
        thisYearCount = places.filter { calendar.component(.year, from: $0.lastVisitedAt) == currentYear }.count
        previousYearCount = places.filter { calendar.component(.year, from: $0.lastVisitedAt) == currentYear - 1 }.count

        if let topCategory = categoryBreakdown.first?.title.lowercased(), repeatRate >= 0.35 {
            insight = "You returned to \(topCategory) places more this year"
        } else if let topCategory = categoryBreakdown.first?.title.lowercased() {
            insight = "\(topCategory.capitalized) shaped this slice of your map"
        } else {
            insight = "Your patterns will appear as your map grows"
        }
    }
}

enum YourMapPrototypeLaunchConfiguration {
    static func shouldPresent(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains("-WanderShowYourMapPrototype")
        #else
        false
        #endif
    }

    static func volume(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> YourMapPrototypeDataVolume {
        YourMapPrototypeDataVolume.resolved(from: arguments)
    }

    static func mode(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> YourMapPrototypeMode {
        guard
            let flagIndex = arguments.firstIndex(of: "-WanderYourMapPrototypeMode"),
            arguments.indices.contains(flagIndex + 1),
            let mode = YourMapPrototypeMode(rawValue: arguments[flagIndex + 1])
        else {
            return .map
        }
        return mode
    }

    static func shouldPresentSharePreview(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-WanderShowYourMapPrototypeSharePreview")
    }
}
#endif
