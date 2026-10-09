import SwiftUI
import MapKit

enum ReviewTab: String, CaseIterable { case live = "Live", lists = "Lists", profile = "Profile" }
enum DrawerHeight: String, CaseIterable { case peek = "Map", half = "Together", full = "Feed" }
enum PeopleScope: String, CaseIterable, Identifiable {
    case following = "Following", nearby = "Nearby", yours = "Your places"
    var id: String { rawValue }
}
enum ActivityKind: String, CaseIterable, Identifiable, Sendable {
    case checkin = "Been", wanna = "Wanna", plan = "Plans"
    var id: String { rawValue }
    var symbol: String { switch self { case .checkin: "checkmark"; case .wanna: "bookmark"; case .plan: "calendar" } }
    var verb: String { switch self { case .checkin: "went to"; case .wanna: "wants to try"; case .plan: "is making a plan for" } }
}
enum TimeWindow: String, CaseIterable, Identifiable {
    case week = "Past 7 days", month = "Past 30 days", all = "All time"
    var id: String { rawValue }
    var days: Double { switch self { case .week: 7; case .month: 30; case .all: 100_000 } }
}
enum ReviewScenario: String, CaseIterable, Identifiable {
    case dense = "A busy week", sparse = "A quiet week", empty = "No activity yet", offline = "Offline · saved activity"
    var id: String { rawValue }
}
struct Activity: Identifiable, Sendable {
    let id: UUID
    var person: String
    var initials: String
    var place: String
    var neighborhood: String
    var category: String
    var kind: ActivityKind
    var hoursAgo: Double
    var note: String
    var latitude: Double
    var longitude: Double
    var isOwn: Bool = false
    var isFollowing: Bool = true
    var plannedFor: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var placeKey: String { "\(place.lowercased())|\(neighborhood.lowercased())" }
    var timeLabel: String {
        if kind == .plan { return plannedFor ?? "Time to decide" }
        if hoursAgo < 1 { return "Just now" }
        if hoursAgo < 24 { return "\(Int(hoursAgo))h ago" }
        return "\(Int(hoursAgo / 24))d ago"
    }
    init(person: String, initials: String, place: String, neighborhood: String, category: String,
         kind: ActivityKind, hoursAgo: Double, note: String, latitude: Double, longitude: Double,
         isOwn: Bool = false, isFollowing: Bool = true, plannedFor: String? = nil) {
        id = UUID(); self.person = person; self.initials = initials; self.place = place
        self.neighborhood = neighborhood; self.category = category; self.kind = kind
        self.hoursAgo = hoursAgo; self.note = note; self.latitude = latitude; self.longitude = longitude
        self.isOwn = isOwn; self.isFollowing = isFollowing
        self.plannedFor = plannedFor
    }
}
struct GeographicArea {
    var center: CLLocationCoordinate2D
    var radius: CLLocationDistance
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= radius
    }
    var label: String { radius >= 1000 ? String(format: "%.1f km area", radius / 1000) : "\(Int(radius)) m area" }
}
struct DemoReply: Identifiable {
    let id = UUID()
    let person: String
    let place: String
    let message: String
}
enum ReviewSheet: Identifiable {
    case filters, detail(Activity), plan(Activity), reply(Activity), add, inbox, guide, events
    var id: String {
        switch self {
        case .filters: "filters"
        case .detail(let activity): "detail-\(activity.id)"
        case .plan(let activity): "plan-\(activity.id)"
        case .reply(let activity): "reply-\(activity.id)"
        case .add: "add"
        case .inbox: "inbox"
        case .guide: "guide"
        case .events: "events"
        }
    }
}

@MainActor
final class ReviewStore: ObservableObject {
    static let center = CLLocationCoordinate2D(latitude: 34.0045, longitude: -118.4795)
    @Published var tab: ReviewTab = .live
    @Published var drawer: DrawerHeight = .half
    @Published var scope: PeopleScope = .following
    @Published var time: TimeWindow = .week
    @Published var kinds: Set<ActivityKind> = []
    @Published var query = ""
    @Published var area: GeographicArea?
    @Published var scenario: ReviewScenario = .dense
    @Published var activities = Fixtures.activities
    @Published var replies: [DemoReply] = []
    @Published var sheet: ReviewSheet?
    @Published var banner: String?
    @Published var fromProfile = false
    @Published var showPatterns = false
    @Published var showYourMap = false
    @Published var profileMapKind: ActivityKind?
    @Published var profileMapCamera: MapCameraPosition = .region(.init(center: center, span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))
    @Published var selectedCollection = "All saved"
    @Published var nearbyRadius: Double = 5000
    @Published var eventsInterested = false
    @Published var showTransition: Bool
    @Published var camera: MapCameraPosition = .region(.init(center: center, span: .init(latitudeDelta: 0.065, longitudeDelta: 0.065)))
    @Published var viewportCenter = center
    @Published var drawing = false
    @Published var draftArea: GeographicArea?
    private var savedExplore: (PeopleScope, TimeWindow, Set<ActivityKind>, String, GeographicArea?, DrawerHeight, MapCameraPosition, CLLocationCoordinate2D, Double)?

    init(arguments args: [String] = ProcessInfo.processInfo.arguments) {
        showTransition = !UserDefaults.standard.bool(forKey: "review.transitionSeen")
        if args.contains("--ui-testing") { showTransition = false }
        if args.contains("--scenario-sparse") { scenario = .sparse }
        if args.contains("--scenario-empty") { scenario = .empty }
        if args.contains("--scenario-offline") { scenario = .offline }
        if args.contains("--show-transition") { showTransition = true }
        if args.contains("--hide-transition") { showTransition = false }
        if args.contains("--feed") { drawer = .full }
        if args.contains("--map") { drawer = .peek }
        if args.contains("--profile") { tab = .profile }
        if args.contains("--lists") { tab = .lists }
        if args.contains("--your-map") { tab = .profile; showYourMap = true }
        if args.contains("--patterns") { tab = .profile; showYourMap = true; showPatterns = true }
        if args.contains("--fixture-wanna") { scope = .following; kinds = [.wanna]; drawer = .full }
        if args.contains("--fixture-reply") { sheet = .reply(Fixtures.activities[0]) }
        if args.contains("--fixture-plan") { sheet = .plan(Fixtures.activities[1]) }
        if args.contains("--fixture-draw") { drawer = .peek; drawing = true; draftArea = GeographicArea(center: Self.center, radius: 1000) }
    }

    var filtered: [Activity] {
        projection(kinds: kinds, time: time, area: area, nearbyRadius: nearbyRadius, query: query)
    }
    func projection(kinds: Set<ActivityKind>, time: TimeWindow, area: GeographicArea?, nearbyRadius: Double, query: String) -> [Activity] {
        let candidates: [Activity]
        switch scenario {
        case .empty: candidates = activities.filter { $0.hoursAgo < 1 }
        case .sparse: candidates = Array(activities.filter { !$0.isOwn }.prefix(2)) + activities.filter { $0.isOwn }
        case .dense, .offline: candidates = activities
        }
        let matches = candidates.filter { item in
            let scopeMatches = switch scope {
            case .following: item.isFollowing || item.isOwn
            case .nearby: (item.isOwn || item.isFollowing) && GeographicArea(center: Self.center, radius: nearbyRadius).contains(item.coordinate)
            case .yours: item.isOwn
            }
            return scopeMatches && item.hoursAgo < time.days * 24
                && (kinds.isEmpty || kinds.contains(item.kind))
                && (area == nil || area!.contains(item.coordinate))
                && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    "\(item.person) \(item.place) \(item.neighborhood) \(item.category) \(item.note)".localizedCaseInsensitiveContains(query))
        }.sorted { $0.hoursAgo < $1.hoursAgo }
        return scope == .yours ? uniquePlaces(matches) : matches
    }
    var defaultTime: TimeWindow { scope == .yours ? .all : .week }
    var activeFilterCount: Int { (kinds.isEmpty ? 0 : 1) + (time == defaultTime ? 0 : 1) + (area == nil ? 0 : 1) + (scope == .nearby && nearbyRadius != 5000 ? 1 : 0) }
    var ownPlaces: [Activity] { ownPlaces(matching: nil) }
    func ownPlaces(matching kind: ActivityKind?) -> [Activity] {
        uniquePlaces(activities.filter { $0.isOwn && (kind == nil || $0.kind == kind) }.sorted { $0.hoursAgo < $1.hoursAgo })
    }
    private func uniquePlaces(_ items: [Activity]) -> [Activity] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.placeKey).inserted }
    }
    var filterSummary: String {
        [time.rawValue, kinds.isEmpty ? "All activity" : kinds.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ", "), scope == .nearby ? "\(Int(nearbyRadius / 1000)) km around Ocean Park" : nil, area?.label].compactMap { $0 }.joined(separator: " · ")
    }
    func resetFilters() { kinds = []; time = defaultTime; area = nil; query = ""; nearbyRadius = 5000 }
    func dismissTransition() { showTransition = false; UserDefaults.standard.set(true, forKey: "review.transitionSeen") }
    func openYourMap() {
        selectTab(.profile); showYourMap = true; showPatterns = false
    }
    func exploreOwnPlace(_ activity: Activity) {
        guard activity.isOwn else { return }
        if !fromProfile { savedExplore = (scope, time, kinds, query, area, drawer, camera, viewportCenter, nearbyRadius) }
        scope = .yours; time = .all; kinds = []; query = activity.place; area = nil
        camera = .region(.init(center: activity.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
        viewportCenter = activity.coordinate
        fromProfile = true; drawer = .half; tab = .live
    }
    func backToProfile() {
        selectTab(.profile)
    }
    func selectTab(_ destination: ReviewTab) {
        if fromProfile && destination != .live { restoreExploration() }
        if destination != .live { cancelAreaDraft() }
        tab = destination
    }
    private func restoreExploration() {
        fromProfile = false
        if let savedExplore {
            (scope, time, kinds, query, area, drawer, camera, viewportCenter, nearbyRadius) = savedExplore
            self.savedExplore = nil
        }
    }
    func changeDrawer(to height: DrawerHeight) {
        guard !drawing || height == .peek else { return }
        drawer = height
    }
    func cancelAreaDraft() { drawing = false; draftArea = nil }
    func savePlan(for item: Activity, title: String, when: String) {
        activities.insert(Activity(person: "You", initials: "AL", place: item.place, neighborhood: item.neighborhood,
                                   category: item.category, kind: .plan, hoursAgo: 0,
                                   note: "\(title) · \(when). Demo plan, saved on this device.",
                                   latitude: item.latitude, longitude: item.longitude, isOwn: true, plannedFor: when), at: 0)
        sheet = nil; banner = "Demo plan created · saved in Your Map"
    }
    func savePlace(_ item: Activity, kind: ActivityKind, note: String) {
        activities.insert(Activity(person: "You", initials: "AL", place: item.place, neighborhood: item.neighborhood,
                                   category: item.category, kind: kind, hoursAgo: 0, note: note.isEmpty ? "A new place memory." : note,
                                   latitude: item.latitude, longitude: item.longitude, isOwn: true), at: 0)
        sheet = nil; banner = "Saved in Your Map · demo only"
    }
}

enum Fixtures {
    static let activities: [Activity] = [
        .init(person: "Maya Chen", initials: "MC", place: "Juniper Coffee", neighborhood: "Ocean Park", category: "Coffee",
              kind: .checkin, hoursAgo: 2, note: "The sunny corner table. A flat white and absolutely nowhere to rush.", latitude: 34.0018, longitude: -118.4828),
        .init(person: "Leo Park", initials: "LP", place: "Little Tide", neighborhood: "Main Street", category: "Dinner",
              kind: .wanna, hoursAgo: 4, note: "Heard the courtyard is lovely at sunset. Who’s in?", latitude: 34.0058, longitude: -118.4849),
        .init(person: "Nina Flores", initials: "NF", place: "Daybreak Books", neighborhood: "Venice", category: "Books",
              kind: .checkin, hoursAgo: 7, note: "Came for one book. Left with three and a very good recommendation.", latitude: 33.9961, longitude: -118.4698),
        .init(person: "Sam Rivera", initials: "SR", place: "Sunday Table", neighborhood: "Rose Avenue", category: "Brunch",
              kind: .plan, hoursAgo: 21, note: "Sunday, 10 am. A slow breakfast with a few familiar faces.", latitude: 33.9982, longitude: -118.4772, plannedFor: "Sunday · 10 am"),
        .init(person: "Maya Chen", initials: "MC", place: "Saltwater Walk", neighborhood: "Ocean Park", category: "Outdoors",
              kind: .checkin, hoursAgo: 28, note: "A little sea air between everything else.", latitude: 34.0032, longitude: -118.4915),
        .init(person: "Leo Park", initials: "LP", place: "Field Notes Gallery", neighborhood: "Santa Monica", category: "Art",
              kind: .wanna, hoursAgo: 49, note: "Saving this for a free afternoon.", latitude: 34.0131, longitude: -118.4840),
        .init(person: "You", initials: "AL", place: "Copper Fig", neighborhood: "Ocean Park", category: "Dinner",
              kind: .checkin, hoursAgo: 72, note: "The kind of dinner you want to have again.", latitude: 34.0092, longitude: -118.4741, isOwn: true),
        .init(person: "You", initials: "AL", place: "Dune Bakery", neighborhood: "Venice", category: "Bakery",
              kind: .wanna, hoursAgo: 240, note: "Next Saturday, before the good things sell out.", latitude: 33.9918, longitude: -118.4709, isOwn: true),
        .init(person: "You", initials: "AL", place: "Juniper Coffee", neighborhood: "Ocean Park", category: "Coffee",
              kind: .checkin, hoursAgo: 504, note: "Your reliable corner of the neighborhood.", latitude: 34.0018, longitude: -118.4828, isOwn: true),
        .init(person: "Alex Bell", initials: "AB", place: "North Shore Studio", neighborhood: "Santa Monica", category: "Art",
              kind: .checkin, hoursAgo: 30, note: "Open studio afternoon. A place worth remembering.", latitude: 34.0210, longitude: -118.4923, isFollowing: false)
    ]
}
