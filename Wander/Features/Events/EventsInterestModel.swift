import Foundation
import Combine

/// Only server-confirmed signups are cached; absence is never persisted.
@MainActor struct EventsInterestCache {
    private let defaults: UserDefaults?
    init(defaults: UserDefaults? = .standard) { self.defaults = defaults }

    static var application: Self {
        // Fixture signups must not leak between UI test launches or into real accounts.
        Self(defaults: ProcessInfo.processInfo.arguments.contains("-WanderAuthenticatedUITest") ? nil : .standard)
    }

    func interest(for userID: String) -> EventsInterest? {
        guard let date = defaults?.object(forKey: "events.waitlist.confirmed.v1." + userID) as? Date else { return nil }
        return EventsInterest(createdAt: date)
    }

    func store(_ interest: EventsInterest, for userID: String) {
        defaults?.set(interest.createdAt, forKey: "events.waitlist.confirmed.v1." + userID)
    }
}

enum EventsInterestPresentation: Equatable {
    case unknown, available, registered
}

@MainActor final class EventsInterestModel: ObservableObject {
    @Published private(set) var interest: EventsInterest?
    @Published private(set) var isSaving = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private var userID: String?
    private var generation = 0
    @Published private(set) var loaded = false
    private let cache: EventsInterestCache

    init(cache: EventsInterestCache = .application) { self.cache = cache }

    var isRegistered: Bool { interest != nil }

    /// Reads cached confirmation synchronously, including before SwiftUI starts .task.
    /// Never display a previous account's state during an account transition.
    func presentation(for userID: String?) -> EventsInterestPresentation {
        guard let userID else { return .unknown }
        if cache.interest(for: userID) != nil { return .registered }
        guard self.userID == userID else { return .unknown }
        if isRegistered { return .registered }
        return loaded ? .available : .unknown
    }

    /// Invalidate old-account completions before starting a new account's read.
    func load(userID: String?, repository: (any EventsInterestRepository)?) async {
        if self.userID != userID {
            generation += 1
            self.userID = userID
            interest = userID.flatMap { cache.interest(for: $0) }
            loaded = interest != nil
            isSaving = false
            isLoading = false
            errorMessage = nil
        }
        guard let userID, !loaded, !isLoading, !isSaving, let repository else { return }
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let saved = try await repository.currentInterest()
            try Task.checkCancellation()
            guard request == generation else { return }
            interest = saved
            if let saved { cache.store(saved, for: userID) }
            loaded = true
        } catch {
            // Keep an unknown state blank after a failed read. A later visit retries;
            // previously confirmed accounts restore locally without a network read.
        }
    }

    func register(repository: (any EventsInterestRepository)?, analytics: AnalyticsClient = NoopAnalyticsClient()) async {
        guard let userID, !isRegistered, !isSaving else { return }
        guard let repository else {
            errorMessage = "Couldn't save that yet. Please try again."
            return
        }
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.eventsInterestSubmitted, properties: [:]))
        // Supersede a pending read so its older nil result cannot undo success.
        generation += 1
        let request = generation
        isLoading = false
        isSaving = true
        errorMessage = nil
        defer { if request == generation { isSaving = false } }
        do {
            let saved = try await repository.registerInterest()
            guard request == generation else { return }
            interest = saved
            cache.store(saved, for: userID)
            loaded = true
            analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.eventsInterestResult,
                                          properties: ["outcome": "confirmed"]))
        } catch {
            guard request == generation else { return }
            analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.eventsInterestResult,
                                          properties: ["outcome": "failed"]))
            errorMessage = "Couldn't save that yet. Please try again."
        }
    }
}
