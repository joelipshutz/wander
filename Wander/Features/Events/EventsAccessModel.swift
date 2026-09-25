import Combine
import Foundation

enum EventsAccessPolicy {
    static func isEligible(metroID: String?) -> Bool { metroID == "los-angeles" }

    static func availableTabs(metroID: String?) -> [WanderTab] {
        WanderTab.primaryTabs.filter { $0 != .events || isEligible(metroID: metroID) }
    }

    static func resolvedTab(_ requested: WanderTab, metroID: String?) -> WanderTab {
        requested == .events && !isEligible(metroID: metroID) ? .discover : requested
    }

    #if DEBUG && targetEnvironment(simulator)
    static func fixtureMetroID(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        // Existing explicit simulator fixtures represent an LA member. Dedicated
        // gate tests can override the home area without modifying real accounts.
        guard let index = arguments.firstIndex(of: "-WanderHomeMetroUITest"), arguments.indices.contains(index + 1) else { return "los-angeles" }
        let value = arguments[index + 1]
        return value == "unknown" ? nil : value
    }
    #endif
}

@MainActor final class EventsAccessModel: ObservableObject {
    @Published private(set) var metroID: String?
    private var userID: String?
    private var generation = 0
    private let cache: HomeMetroSelectionStore

    init(userID: String?, initialMetroID: String?, cache: HomeMetroSelectionStore = HomeMetroSelectionStore()) {
        self.cache = cache
        self.userID = userID
        metroID = initialMetroID
    }

    convenience init(userID: String? = nil, cache: HomeMetroSelectionStore = HomeMetroSelectionStore()) {
        self.init(userID: userID, initialMetroID: userID.flatMap { cache.metroID(for: $0) }, cache: cache)
    }

    func homeMetro(for userID: String?) -> String? {
        guard let userID else { return nil }
        return self.userID == userID ? metroID : cache.metroID(for: userID)
    }

    func cachedSelectionDidChange(userID: String?) {
        generation += 1 // A Settings save must win over an older in-flight read.
        self.userID = userID
        metroID = userID.flatMap { cache.metroID(for: $0) }
    }

    func load(userID: String?, repository: (any EventsAccessRepository)?) async {
        if self.userID != userID { cachedSelectionDidChange(userID: userID) }
        generation += 1
        let requestGeneration = generation
        guard let userID, let repository else { return }
        do {
            let access = try await repository.currentAccess()
            guard !Task.isCancelled, generation == requestGeneration, self.userID == userID else { return }
            metroID = access?.metroID
            cache.remember(metroID, for: userID)
        } catch {
            // Remember the last confirmed home when offline. Server-side Events
            // mutations still enforce current eligibility when connectivity returns.
        }
    }
}
