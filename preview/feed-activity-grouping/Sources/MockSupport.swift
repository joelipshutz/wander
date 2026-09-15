import SwiftUI

// Preview-only adapters let the gallery compile the production disclosure.
// These types never belong to the Wander application target.
enum FeedActivityKind { case placeBeen, placeWannaGo, listItemAdded, listCreated, placeSaved }
struct LocalPlaceList: Identifiable { let id: String; let name: String }
struct FeedActivity: Identifiable {
    let id: String
    let kind: FeedActivityKind
    let occurredAt: Date
    var list: LocalPlaceList? = nil
    var actor = "Rachel"
    var place: String? { "Laurel Supply" }
    var activityEngagementContext: FeedActivity? { self }
    var label: String {
        switch kind {
        case .placeBeen: "Checked in"
        case .placeWannaGo: "Wanna"
        case .listItemAdded: "Added to list"
        default: "Saved"
        }
    }
}
struct FeedActivityGroup: Identifiable {
    let activities: [FeedActivity]
    var id: String { activities[0].id }
    var primaryActivity: FeedActivity {
        activities.first { $0.kind == .placeBeen }
        ?? activities.first { $0.kind == .placeWannaGo }
        ?? activities[0]
    }
    var lists: [LocalPlaceList] {
        var seen = Set<String>()
        return activities.compactMap { event in
            guard let list = event.list, seen.insert(list.id).inserted else { return nil }
            return list
        }
    }
}
enum MockSignInIntent { case socialActivity }
@MainActor final class AuthSessionStore: ObservableObject {
    func requireSignIn(for intent: MockSignInIntent, action: () -> Void) { action() }
}
@MainActor final class ActivityNavigationCoordinator: ObservableObject {
    @Published var selectedEvent: FeedActivity?
    func openComments(context: FeedActivity, visiblePlace: String?) { selectedEvent = context }
}
enum PlaceListSymbol { static let systemImage = "list.bullet" }
enum WanderTheme {
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let tapMinimum: CGFloat = 44
}
enum AstirTypography {
    static let bodySmall = Font.custom("AvenirNext-Regular", size: 14, relativeTo: .subheadline)
    static let label = Font.custom("AvenirNext-DemiBold", size: 13, relativeTo: .caption)
    static let caption = Font.custom("AvenirNext-Medium", size: 12, relativeTo: .caption)
    static let metadata = Font.custom("AvenirNextCondensed-DemiBold", size: 12, relativeTo: .caption)
}
struct MockBrandMode {
    var dark = true
    var primaryText: Color { dark ? Color(hex: 0xF2E9DB) : Color(hex: 0x141714) }
    var secondaryText: Color { primaryText.opacity(0.62) }
    var accentText: Color { Color(hex: dark ? 0xF05A3C : 0xB23620) }
    var background: Color { Color(hex: dark ? 0x141714 : 0xF2E9DB) }
    var card: Color { Color(hex: dark ? 0x1B201B : 0xF7EFE3) }
}
private struct BrandKey: EnvironmentKey { static let defaultValue = MockBrandMode() }
extension EnvironmentValues {
    var astirBrandMode: MockBrandMode {
        get { self[BrandKey.self] }
        set { self[BrandKey.self] = newValue }
    }
}
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

enum Scenario: Int, CaseIterable, Identifiable {
    case together, wanna, lists, later, revisit, people
    var id: Int { rawValue }
    var title: String {
        ["All three", "Wanna + list", "Several lists", "Later activity", "Another visit", "Two people"][rawValue]
    }
    var heading: String {
        ["One place. One moment.", "A plan worth saving.", "One card, several lists.", "A new moment stays new.", "Every visit has its story.", "Each person keeps their post."][rawValue]
    }
    var explanation: String {
        ["Three actions in 6 minutes become one card. The check-in leads.",
         "Wanna and a list addition combine. No check-in is implied.",
         "List additions share one card. Expand to see every list.",
         "These actions are 45 minutes apart, so they stay separate.",
         "A second check-in stays separate, even just 20 minutes later.",
         "The same place, saved by two people, remains two cards."][rawValue]
    }
    var groups: [FeedActivityGroup] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 14))!
        let la = LocalPlaceList(id: "la", name: "LA: Wanna Go")
        let weekend = LocalPlaceList(id: "weekend", name: "Weekend stops")
        let groceries = LocalPlaceList(id: "groceries", name: "Good groceries")
        func event(_ id: String, _ kind: FeedActivityKind, _ minute: Int,
                   _ list: LocalPlaceList? = nil, actor: String = "Rachel") -> FeedActivity {
            FeedActivity(id: id, kind: kind, occurredAt: start.addingTimeInterval(Double(minute * 60)), list: list, actor: actor)
        }
        switch self {
        case .together:
            return [.init(activities: [event("wanna", .placeWannaGo, 0), event("visit", .placeBeen, 3), event("list", .listItemAdded, 6, la)])]
        case .wanna:
            return [.init(activities: [event("wanna", .placeWannaGo, 0), event("list", .listItemAdded, 4, la)])]
        case .lists:
            return [.init(activities: [event("la", .listItemAdded, 0, la), event("weekend", .listItemAdded, 2, weekend), event("groceries", .listItemAdded, 5, groceries)])]
        case .later:
            return [.init(activities: [event("late", .placeBeen, 45)]), .init(activities: [event("early", .placeWannaGo, 0)])]
        case .revisit:
            return [.init(activities: [event("visit2", .placeBeen, 20)]), .init(activities: [event("visit1", .placeBeen, 0)])]
        case .people:
            return [.init(activities: [event("alex", .placeWannaGo, 2, actor: "Alex")]), .init(activities: [event("rachel", .placeWannaGo, 0)])]
        }
    }
}
