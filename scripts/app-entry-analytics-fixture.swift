// Compile with Wander/Services/AnalyticsEvent.swift. This small Foundation-only
// fixture exercises the production tracker without building the iOS app.
import Foundation

private final class RecordingAnalytics: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}

@main struct AppEntryAnalyticsFixture {
    @MainActor static func main() {
        let suite = "AppEntryAnalyticsFixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recording = RecordingAnalytics()
        let tracker = AppAnalyticsLifecycleTracker(analytics: recording, defaults: defaults)
        func events(_ name: String) -> [AnalyticsEvent] { recording.events.filter { $0.name == name } }
        func entries() -> [AnalyticsEvent] { events(WanderAnalyticsEvents.appEntryStarted) }
        func sources() -> [AnalyticsEvent] { events(WanderAnalyticsEvents.appEntrySourceObserved) }

        // A cold notification response can precede both launch and activation.
        tracker.recordEntrySource(.notification, notificationType: "followed_you", deliveryChannel: "remote", atUptime: 9)
        assert(entries().isEmpty)
        tracker.recordLaunch()
        tracker.recordEntryActivation(atUptime: 10)
        tracker.recordLaunch()
        tracker.recordEntryActivation(atUptime: 10.5)
        assert(entries().count == 1)
        assert(entries()[0].properties["entry_kind"] == "cold_launch")
        assert(sources()[0].properties["entry_id"] == entries()[0].properties["entry_id"])
        assert(events(WanderAnalyticsEvents.appSessionStarted).count == 1)
        assert(events(WanderAnalyticsEvents.appFirstOpened).count == 1)

        // A tap deep into the active app is a click, not an entry source.
        tracker.recordEntrySource(.notification, notificationType: "activity_liked", deliveryChannel: "remote", atUptime: 20)
        assert(sources().count == 1)

        // Even a brief background return is an entry, independent of session
        // refresh policy. A local reminder arriving after activation correlates.
        tracker.recordEntryBackground()
        tracker.recordEntryActivation(atUptime: 21)
        tracker.recordEntrySource(.notification, notificationType: "save_streak_reminder", deliveryChannel: "local", atUptime: 22)
        assert(entries().count == 2)
        assert(entries()[1].properties["entry_kind"] == "foreground_return")
        assert(sources()[1].properties["entry_id"] == entries()[1].properties["entry_id"])
        assert(entries()[0].properties["entry_id"] != entries()[1].properties["entry_id"])

        // Source state never leaks to a later direct/unknown return.
        tracker.recordEntryBackground()
        tracker.recordEntryActivation(atUptime: 40)
        assert(!sources().contains { $0.properties["entry_id"] == entries()[2].properties["entry_id"] })

        // The callback timestamp can precede activation while its main-actor
        // handoff runs afterwards. The inclusive 2s boundary is intentional.
        tracker.recordEntrySource(.link, atUptime: 38)
        tracker.recordEntrySource(.link, atUptime: 42)
        assert(sources().count == 4)
        tracker.recordEntrySource(.link, atUptime: 37.999)
        tracker.recordEntrySource(.link, atUptime: 42.001)
        assert(sources().count == 4)

        // Pending callbacks survive a duplicate background signal and share
        // one random entry ID; the dashboard reduces them to one source row.
        tracker.recordEntryBackground()
        tracker.recordEntrySource(.notification, notificationType: "mutual_follow", deliveryChannel: "remote", atUptime: 50)
        tracker.recordEntryBackground()
        tracker.recordEntrySource(.notification, notificationType: "mutual_follow", deliveryChannel: "remote", atUptime: 50)
        tracker.recordEntryActivation(atUptime: 51)
        assert(sources().suffix(2).allSatisfy { $0.properties["entry_id"] == entries()[3].properties["entry_id"] })
        assert(entries().count == 4)

        let allowed: Set<String> = ["entry_id", "entry_kind", "entry_source", "notification_type", "delivery_channel"]
        for event in entries() + sources() {
            assert(Set(event.properties.keys).isSubset(of: allowed))
            assert(UUID(uuidString: event.properties["entry_id"]!) != nil)
        }
        print("App entry attribution fixtures passed: cold/foreground, callback order, duplicate activation, source reset, 2s boundaries, active-app taps, pending callbacks, privacy.")
    }
}
