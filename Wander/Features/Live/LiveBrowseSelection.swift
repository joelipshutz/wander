import CoreLocation
import Foundation

enum LiveFeedLocationScope: String, Codable, CaseIterable, Identifiable {
    case everywhere, mapArea
    var id: Self { self }
    var title: String { self == .everywhere ? "Everywhere" : "Map area" }
}

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
    // Older bookmarks decode as Everywhere without migrating their map choices.
    private var storedFeedLocationScope: LiveFeedLocationScope?
    var feedLocationScope: LiveFeedLocationScope {
        get { storedFeedLocationScope ?? .everywhere }
        set { storedFeedLocationScope = newValue }
    }
    private(set) var committedAt: Date

    init(now: Date = .now) { committedAt = now }

    var hasCategorySelection: Bool { !categoryIDs.isEmpty || !categoryOptions.isEmpty }

    mutating func setCategory(_ category: String, selected: Bool) {
        storedCategoryOptions?.removeValue(forKey: category)
        if storedCategoryOptions?.isEmpty == true { storedCategoryOptions = nil }
        if selected { categoryIDs.insert(category) }
        else { categoryIDs.remove(category) }
    }

    mutating func toggleCategoryOption(_ option: String, in category: String) {
        let option = WanderPlaceCategory.normalizedCategoryText(option)
        guard !option.isEmpty else { return }
        let allOptions = MapMoreFilterPolicy.normalizedOptions(for: category)
        var selections = categoryOptions
        // Keep full categories compact; only partial selections need explicit children.
        var options = categoryIDs.remove(category) != nil
            ? allOptions : selections[category, default: []]
        if !options.insert(option).inserted { options.remove(option) }
        if !allOptions.isEmpty, options == allOptions {
            categoryIDs.insert(category)
            selections.removeValue(forKey: category)
        } else {
            selections[category] = options.isEmpty ? nil : options
        }
        storedCategoryOptions = selections.isEmpty ? nil : selections
    }

    func isCategoryOptionSelected(_ option: String, in category: String) -> Bool {
        categoryIDs.contains(category)
            || categoryOptions[category, default: []].contains(WanderPlaceCategory.normalizedCategoryText(option))
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

    func query(area: LiveDrawnArea? = nil, includingGeography: Bool = true) -> LiveFeedQuery {
        let type: LiveFeedQuery.ActivityType = switch activityType {
        case .all: .all
        case .checkIns: .checkIns
        case .wannas: .wannas
        case .lists: .lists
        }
        return LiveFeedQuery(occurredAfter: occurredAfter, occurredBefore: occurredBefore,
            activityType: type, polygon: includingGeography ? area?.vertices.map { .init(latitude: $0.latitude, longitude: $0.longitude) } : nil,
            center: includingGeography && area == nil && scope == .nearby ? center : nil,
            radiusMeters: includingGeography && area == nil && scope == .nearby ? radius.rawValue : nil,
            categoryIDs: categoryIDs, categoryOptions: categoryOptions, personIDs: personIDs)
    }

    func feedQuery(area: LiveDrawnArea?) -> LiveFeedQuery {
        query(area: area, includingGeography: feedLocationScope == .mapArea)
    }

    func applyingFilters(from previous: Self, audienceChanged: Bool, at now: Date) -> Self {
        let changed = audienceChanged
            || query(includingGeography: false) != previous.query(includingGeography: false)
        return changed ? committed(at: now) : self
    }

    /// Reset what is shown without changing where either surface is browsing.
    func resettingSharedFilters() -> Self {
        var copy = self
        copy.activityType = .all; copy.time = .all
        copy.clearCategories(); copy.personIDs = []
        return copy
    }

    var sharedFilterCount: Int {
        (activityType == .all ? 0 : 1) + (time == .all ? 0 : 1)
            + (hasCategorySelection ? 1 : 0) + (personIDs.isEmpty ? 0 : 1)
    }

    var sharedFilterTerms: [String] {
        var terms: [String] = []
        if activityType != .all { terms.append(activityType.rawValue) }
        if time != .all { terms.append(time.title) }
        if hasCategorySelection {
            if categoryIDs.count == 1, let category = categoryIDs.first {
                terms.append(WanderPlaceCategory.broadCategory(for: category))
            } else if !categoryIDs.isEmpty { terms.append("\(categoryIDs.count) categories") }
            let options = categoryOptions.values.flatMap { $0 }.sorted()
            if options.count <= 2 { terms += options.map { AppCopy.capitalizingInitial($0) } }
            else { terms.append("\(options.count) category options") }
        }
        if !personIDs.isEmpty { terms.append("\(personIDs.count) \(personIDs.count == 1 ? "person" : "people")") }
        return terms
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
        (scope == .nearby ? 1 : 0) + sharedFilterCount
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
