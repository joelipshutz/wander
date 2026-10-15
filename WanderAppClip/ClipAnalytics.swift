import Foundation

/// Closed product events: no shared URLs, tokens, profile/place content or coordinates.
@MainActor
struct ClipAnalytics {
    let client: any AnalyticsClient

    static func live() -> Self {
        #if DEBUG || targetEnvironment(simulator)
        return Self(client: NoopAnalyticsClient())
        #else
        let client: any AnalyticsClient = PostHogAnalyticsClient(
            configuration: .current(), captureReplay: false) ?? NoopAnalyticsClient()
        return Self(client: ContextualAnalyticsClient(client: client))
        #endif
    }

    func opened(_ kind: AppClipRoute.Kind) {
        client.track(AnalyticsEvent(name: WanderAnalyticsEvents.appClipOpened,
            properties: ["surface": "app_clip", "link_kind": kind.rawValue]))
    }

    func authenticated() {
        client.track(AnalyticsEvent(name: WanderAnalyticsEvents.appClipAuthCompleted,
            properties: ["surface": "app_clip"]))
    }

    func saved() {
        client.track(AnalyticsEvent(name: WanderAnalyticsEvents.placeSaved,
            properties: ["surface": "app_clip", "source_type": "link", "status": "wanna_go"]))
        client.track(.engagement(need: .expression, action: .placeSaved, surface: "app_clip"))
    }

    func joined() {
        client.track(AnalyticsEvent(name: WanderAnalyticsEvents.placeListInviteAccepted,
            properties: ["surface": "app_clip"]))
        client.track(.engagement(need: .connect, action: .listJoined, surface: "app_clip"))
    }
}
