import Foundation

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

struct YourMapPrototypeSavedLens: Identifiable, Equatable {
    let id: UUID
    let lens: YourMapPrototypeLens
    let title: String
    let detail: String

    init(
        lens: YourMapPrototypeLens,
        ordinal: Int,
        id: UUID = UUID()
    ) {
        self.id = id
        self.lens = lens

        let primaryTokens = [
            lens.categories.sorted().first,
            lens.cities.sorted().first,
            lens.statuses.sorted { $0.rawValue < $1.rawValue }.first?.title,
            lens.timeRange == .all ? nil : lens.timeRange.title
        ]
        .compactMap { $0 }

        title = primaryTokens.prefix(2).isEmpty
            ? "Saved lens \(ordinal)"
            : primaryTokens.prefix(2).joined(separator: " · ")
        detail = "\(lens.activeOptionCount) selected \(lens.activeOptionCount == 1 ? "option" : "options")"
    }
}

enum YourMapPrototypeLensSwipePolicy {
    static let revealWidth: CGFloat = 72

    static func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-revealWidth, offset))
    }

    static func settledOffset(for predictedOffset: CGFloat) -> CGFloat {
        clampedOffset(predictedOffset) <= -(revealWidth / 2) ? -revealWidth : 0
    }
}

enum YourMapPrototypeShareFormat: String, CaseIterable, Identifiable {
    case staticSnapshot = "static"
    case liveLens = "live"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staticSnapshot: "Static"
        case .liveLens: "Live"
        }
    }

    var systemImage: String {
        switch self {
        case .staticSnapshot: "camera.fill"
        case .liveLens: "dot.radiowaves.left.and.right"
        }
    }
}

struct YourMapPrototypeShareLink: Equatable {
    let format: YourMapPrototypeShareFormat
    let url: URL

    static func make(
        format: YourMapPrototypeShareFormat,
        token: UUID = UUID()
    ) -> Self {
        let tokenValue = token.uuidString.lowercased()
        let url = URL(string: "https://rec.me/maps/\(tokenValue)?type=\(format.rawValue)")!
        return Self(format: format, url: url)
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
    let initialLens: YourMapPrototypeLens
    let visiblePlaceByPlaceID: [String: VisiblePlace]

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

        let initialLens: YourMapPrototypeLens
        if volume == .medium || volume == .large {
            initialLens = YourMapPrototypeLens(
                statuses: [.been],
                categories: ["Coffee"],
                cities: ["Los Angeles"]
            )
        } else {
            initialLens = YourMapPrototypeLens()
        }

        return Self(
            volume: volume,
            places: places,
            now: now,
            initialLens: initialLens,
            visiblePlaceByPlaceID: [:]
        )
    }

    static func make(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        visiblePlaces: [VisiblePlace] = [],
        now: Date = .now
    ) -> Self {
        var placesByReferenceID: [String: LocalPlace] = [:]
        for place in places {
            var referenceIDs = [place.id, place.localID]
            if let serverID = place.serverID {
                referenceIDs.append(serverID)
            }
            for referenceID in referenceIDs {
                placesByReferenceID[referenceID] = place
            }
        }

        var latestSaveByPlaceID: [String: (userPlace: LocalUserPlace, place: LocalPlace)] = [:]
        for userPlace in userPlaces where userPlace.userID == ownerID && userPlace.deletedAt == nil {
            guard let place = placesByReferenceID[userPlace.placeID],
                  validCoordinate(latitude: place.latitude, longitude: place.longitude)
            else { continue }

            if let existing = latestSaveByPlaceID[place.id],
               existing.userPlace.updatedAt >= userPlace.updatedAt {
                continue
            }
            latestSaveByPlaceID[place.id] = (userPlace, place)
        }

        let activeVisitsByUserPlaceID = Dictionary(
            grouping: visits.lazy.filter { $0.deletedAt == nil },
            by: \.userPlaceID
        )

        let mappedPlaces = latestSaveByPlaceID.values.compactMap { saved -> YourMapPrototypePlace? in
            let userPlace = saved.userPlace
            let place = saved.place
            var savedReferenceIDs = [userPlace.id, userPlace.localID]
            if let serverID = userPlace.serverID {
                savedReferenceIDs.append(serverID)
            }
            let matchingVisits = savedReferenceIDs
                .flatMap { activeVisitsByUserPlaceID[$0, default: []] }
                .reduce(into: [String: LocalPlaceVisit]()) { result, visit in
                    guard let existing = result[visit.id],
                          existing.updatedAt >= visit.updatedAt
                    else {
                        result[visit.id] = visit
                        return
                    }
                }
                .values
            let latestRatedVisit = matchingVisits
                .filter { $0.ratingScore != nil }
                .max { $0.visitedAt < $1.visitedAt }
            let tags = Set(
                matchingVisits.flatMap(\.tags)
                    + userPlace.historicalWantTags
            )
            let resolvedCategory = userPlace.categoryOverride
                ?? userPlace.viewerPrimaryCategory
                ?? place.primaryCategory
            let city = normalized(place.locality, fallback: "Unknown city")
            let country = CountryCanonicalizer.canonicalName(place.country)
                ?? normalized(place.country, fallback: "Unknown country")
            let status: YourMapPrototypeStatus = userPlace.status == .been ? .been : .wanna
            let lastVisitedAt = matchingVisits.map(\.visitedAt).max()
                ?? userPlace.visitedAt
                ?? userPlace.savedAt

            return YourMapPrototypePlace(
                id: place.id,
                name: place.canonicalName,
                latitude: place.latitude,
                longitude: place.longitude,
                status: status,
                category: WanderPlaceCategory.broadCategory(for: resolvedCategory),
                city: city,
                country: country,
                tags: tags,
                rating: latestRatedVisit?.ratingScore ?? userPlace.ratingScore ?? 0,
                visitCount: status == .been ? max(matchingVisits.count, 1) : 0,
                lastVisitedAt: lastVisitedAt
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var visiblePlacesByUserPlaceReferenceID: [String: VisiblePlace] = [:]
        for visiblePlace in visiblePlaces where visiblePlace.owner.id == ownerID {
            for referenceID in referenceIDs(for: visiblePlace.userPlace) {
                visiblePlacesByUserPlaceReferenceID[referenceID] = visiblePlace
            }
        }

        var visiblePlaceByPlaceID: [String: VisiblePlace] = [:]
        for (placeID, saved) in latestSaveByPlaceID {
            let visiblePlace = referenceIDs(for: saved.userPlace).lazy
                .compactMap { visiblePlacesByUserPlaceReferenceID[$0] }
                .first
            if let visiblePlace {
                visiblePlaceByPlaceID[placeID] = visiblePlace
            }
        }

        return Self(
            volume: representativeVolume(for: mappedPlaces.count),
            places: mappedPlaces,
            now: now,
            initialLens: YourMapPrototypeLens(),
            visiblePlaceByPlaceID: visiblePlaceByPlaceID
        )
    }

    private static func referenceIDs(for userPlace: LocalUserPlace) -> [String] {
        [userPlace.id, userPlace.localID, userPlace.serverID].compactMap { $0 }
    }

    private static func representativeVolume(for count: Int) -> YourMapPrototypeDataVolume {
        switch count {
        case 0: .empty
        case 1...6: .small
        case 7...60: .medium
        default: .large
        }
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return fallback }
        return value
    }

    private static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }
}

struct YourMapPrototypeBreakdownItem: Identifiable, Equatable {
    let title: String
    let count: Int
    let fraction: Double

    var id: String { title }
}

struct YourMapPrototypeMonthActivity: Identifiable, Equatable {
    let month: Int
    let count: Int
    let intensity: Double

    var id: Int { month }

    var title: String {
        Self.monthTitles[month - 1]
    }

    var shortTitle: String {
        String(title.prefix(3))
    }

    private static let monthTitles = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
}

struct YourMapPrototypeInsights: Equatable {
    let totalCount: Int
    let repeatCount: Int
    let repeatRate: Double
    let categoryBreakdown: [YourMapPrototypeBreakdownItem]
    let cityBreakdown: [YourMapPrototypeBreakdownItem]
    let countryBreakdown: [YourMapPrototypeBreakdownItem]
    let monthlyActivity: [YourMapPrototypeMonthActivity]
    let returnMagnets: [YourMapPrototypePlace]

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

        cityBreakdown = Self.breakdown(places.map(\.city), totalCount: places.count)
        countryBreakdown = Self.breakdown(places.map(\.country), totalCount: places.count)

        let monthCounts = Dictionary(
            grouping: places,
            by: { calendar.component(.month, from: $0.lastVisitedAt) }
        )
        .mapValues(\.count)
        let maximumMonthCount = max(monthCounts.values.max() ?? 0, 1)
        monthlyActivity = (1...12).map { month in
            let count = monthCounts[month] ?? 0
            return YourMapPrototypeMonthActivity(
                month: month,
                count: count,
                intensity: Double(count) / Double(maximumMonthCount)
            )
        }

        returnMagnets = beenPlaces
            .filter { $0.visitCount > 1 }
            .sorted { lhs, rhs in
                if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
                if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

    }

    private static func breakdown(
        _ values: [String],
        totalCount: Int
    ) -> [YourMapPrototypeBreakdownItem] {
        Dictionary(grouping: values, by: { $0 })
            .map { title, values in
                YourMapPrototypeBreakdownItem(
                    title: title,
                    count: values.count,
                    fraction: totalCount == 0 ? 0 : Double(values.count) / Double(totalCount)
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title < rhs.title
            }
    }
}
