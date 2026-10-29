import CoreLocation
import Foundation

/// Draft controls become an immutable server query only when committed.
struct LiveBrowseSelection: Codable, Equatable {
    enum Scope: String, Codable, CaseIterable, Identifiable {
        case featured = "Featured", nearby = "Nearby"
        var id: Self { self }
    }
    enum Radius: Int, Codable, CaseIterable, Identifiable {
        case fiveKilometers = 5_000, tenKilometers = 10_000, twentyFiveKilometers = 25_000
        var id: Self { self }
        var title: String { "\(rawValue / 1_000) km" }
    }

    var scope: Scope = .featured {
        didSet {
            if scope == .nearby, oldValue != .nearby { radius = .tenKilometers }
        }
    }
    var cityID: String? { didSet { if cityID != oldValue { nearbyCenter = nil; nearbyCenterName = nil } } }
    var nearbyCenter: LiveFeedQuery.Vertex?
    var nearbyCenterName: String?
    var radius: Radius = .tenKilometers
    var activityType: LiveActivityFilter = .all
    var time: LiveTimeFilter = .all
    var categoryIDs: Set<String> = []
    // Optional storage keeps previously saved browse state decodable.
    private var storedCategoryOptions: [String: Set<String>]?
    var categoryOptions: [String: Set<String>] { storedCategoryOptions ?? [:] }
    var personIDs: Set<String> = []
    private(set) var committedAt: Date

    init(now: Date = .now) { committedAt = now }

    var hasCategorySelection: Bool { !categoryIDs.isEmpty || !categoryOptions.isEmpty }

    mutating func setCategory(_ category: String, selected: Bool) {
        if selected {
            categoryIDs.insert(category)
            storedCategoryOptions?.removeValue(forKey: category)
            if storedCategoryOptions?.isEmpty == true { storedCategoryOptions = nil }
        } else {
            categoryIDs.remove(category)
        }
    }

    mutating func toggleCategoryOption(_ option: String, in category: String) {
        let option = WanderPlaceCategory.normalizedCategoryText(option)
        guard !option.isEmpty else { return }
        categoryIDs.remove(category)
        var selections = categoryOptions
        var options = selections[category, default: []]
        if !options.insert(option).inserted { options.remove(option) }
        selections[category] = options.isEmpty ? nil : options
        storedCategoryOptions = selections.isEmpty ? nil : selections
    }

    func isCategoryOptionSelected(_ option: String, in category: String) -> Bool {
        categoryOptions[category, default: []].contains(WanderPlaceCategory.normalizedCategoryText(option))
    }

    mutating func clearCategories() {
        categoryIDs = []
        storedCategoryOptions = nil
    }

    var city: HomeMetro? { HomeMetro.find(cityID) }
    var center: LiveFeedQuery.Vertex? {
        nearbyCenter ?? city.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }
    var isValid: Bool { committedAt.timeIntervalSince1970.isFinite && (scope != .nearby || center != nil) && query().isValid }
    var occurredAfter: Date? {
        time == .all ? nil : committedAt.addingTimeInterval(-Double(time.rawValue) * 86_400)
    }
    var occurredBefore: Date { committedAt }

    func committed(at now: Date) -> Self {
        var copy = self
        copy.committedAt = now
        return copy
    }

    func includes(_ activity: FeedActivity) -> Bool {
        isValid && query().includes(activity)
    }

    func query(area: LiveDrawnArea? = nil) -> LiveFeedQuery {
        let type: LiveFeedQuery.ActivityType = switch activityType {
        case .all: .all
        case .checkIns: .checkIns
        case .wannas: .wannas
        case .lists: .lists
        }
        return LiveFeedQuery(occurredAfter: occurredAfter, occurredBefore: occurredBefore,
            activityType: type, polygon: area?.vertices.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
            center: scope == .nearby ? center : nil, radiusMeters: scope == .nearby ? radius.rawValue : nil,
            categoryIDs: categoryIDs, categoryOptions: categoryOptions, personIDs: personIDs)
    }

    /// The visible map replaces earlier geographic bounds; all other filters
    /// and the remembered city/radius choices remain available in Filters.
    func searchingMapArea() -> Self {
        var copy = self
        copy.scope = .featured
        return copy
    }

    var summary: String {
        var terms = [scope == .nearby ? "\(radius.title) · \(nearbyCenter == nil ? (city?.name ?? "Choose a city") : (nearbyCenterName ?? "Map center"))" : "Featured", time.title]
        if activityType != .all { terms.append(activityType.rawValue) }
        if !categoryIDs.isEmpty { terms.append("\(categoryIDs.count) \(categoryIDs.count == 1 ? "category" : "categories")") }
        let optionCount = categoryOptions.values.reduce(0) { $0 + $1.count }
        if optionCount > 0 { terms.append("\(optionCount) \(optionCount == 1 ? "category option" : "category options")") }
        if !personIDs.isEmpty { terms.append("\(personIDs.count) \(personIDs.count == 1 ? "person" : "people")") }
        return terms.joined(separator: " · ")
    }

    var activeFilterCount: Int {
        (scope == .nearby ? 1 : 0) + (activityType == .all ? 0 : 1) + (time == .all ? 0 : 1)
            + (hasCategorySelection ? 1 : 0) + (personIDs.isEmpty ? 0 : 1)
    }

    /// Derive choices before local refinements so a selection cannot remove its
    /// own picker option. Never hydrate people or private categories separately.
    static func categories(in authorizedActivity: [FeedActivity]) -> [String] {
        Set(authorizedActivity.compactMap { $0.place.map(LiveFeedQuery.categoryID) }).sorted()
    }

    static func people(in authorizedActivity: [FeedActivity]) -> [ProfileShell] {
        var seen: Set<String> = []
        return authorizedActivity.compactMap { seen.insert($0.actor.id).inserted ? $0.actor : nil }
            .sorted {
                if $0.displayName == $1.displayName { return $0.id < $1.id }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }
}
