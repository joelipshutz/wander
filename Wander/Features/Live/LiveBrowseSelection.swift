import CoreLocation
import Foundation

/// Local presentation over already-authorized loaded Feed records. These fields
/// are not a replacement for the pending server query/pagination contract.
struct LiveBrowseSelection: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case following = "Following everywhere", nearby = "Nearby"
        var id: Self { self }
    }
    enum Radius: Int, CaseIterable, Identifiable {
        case fiveKilometers = 5_000, twentyFiveKilometers = 25_000
        var id: Self { self }
        var title: String { "\(rawValue / 1_000) km" }
    }

    var scope: Scope = .following {
        didSet {
            if scope == .nearby, oldValue != .nearby { radius = .fiveKilometers }
        }
    }
    var cityID: String?
    var radius: Radius = .fiveKilometers
    var activityType: LiveActivityFilter = .all
    var time: LiveTimeFilter = .week
    var categoryIDs: Set<String> = []
    var personIDs: Set<String> = []
    private(set) var committedAt: Date

    init(now: Date = .now) { committedAt = now }

    var city: HomeMetro? { HomeMetro.find(cityID) }
    var isValid: Bool { committedAt.timeIntervalSince1970.isFinite && (scope != .nearby || city != nil) }
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
        guard isValid, activity.occurredAt <= occurredBefore else { return false }
        if let occurredAfter, activity.occurredAt < occurredAfter { return false }
        guard activityType.includes(activity), personIDs.isEmpty || personIDs.contains(activity.actor.id) else { return false }
        if !categoryIDs.isEmpty {
            guard let place = activity.place, categoryIDs.contains(place.effectiveCategory) else { return false }
        }
        if scope == .nearby {
            guard let city, let place = activity.place else { return false }
            let coordinate = CLLocationCoordinate2D(latitude: place.place.latitude, longitude: place.place.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
            let center = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard center.distance(from: location) <= Double(radius.rawValue) else { return false }
        }
        return true
    }

    var summary: String {
        var terms = [scope == .nearby ? "\(radius.title) · \(city?.name ?? "Choose a city")" : "Following", time.title]
        if activityType != .all { terms.append(activityType.rawValue) }
        if !categoryIDs.isEmpty { terms.append("\(categoryIDs.count) \(categoryIDs.count == 1 ? "category" : "categories")") }
        if !personIDs.isEmpty { terms.append("\(personIDs.count) \(personIDs.count == 1 ? "person" : "people")") }
        return terms.joined(separator: " · ")
    }

    var activeFilterCount: Int {
        (scope == .nearby ? 1 : 0) + (activityType == .all ? 0 : 1) + (time == .week ? 0 : 1)
            + (categoryIDs.isEmpty ? 0 : 1) + (personIDs.isEmpty ? 0 : 1)
    }

    /// Derive choices before local refinements so a selection cannot remove its
    /// own picker option. Never hydrate people or private categories separately.
    static func categories(in authorizedActivity: [FeedActivity]) -> [String] {
        Set(authorizedActivity.compactMap { $0.place?.effectiveCategory }).sorted()
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
