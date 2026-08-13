import Foundation

#if canImport(PostHog)
import PostHog
#endif

struct PostHogAnalyticsConfiguration: Equatable {
    static let defaultHost = "https://us.i.posthog.com"

    let projectToken: String?
    let host: String

    var isConfigured: Bool {
        projectToken?.isEmpty == false
    }

    static func current(bundle: Bundle = .main) -> PostHogAnalyticsConfiguration {
        current { key in
            bundle.object(forInfoDictionaryKey: key) as? String
        }
    }

    static func current(valueFor keyValue: (String) -> String?) -> PostHogAnalyticsConfiguration {
        PostHogAnalyticsConfiguration(
            projectToken: trimmedPostHogString(keyValue("WANDER_POSTHOG_PROJECT_TOKEN")),
            host: trimmedPostHogString(keyValue("WANDER_POSTHOG_HOST")) ?? defaultHost
        )
    }
}

final class PostHogAnalyticsClient: AnalyticsClient {
#if canImport(PostHog)
    private let sdk: PostHogSDK

    init?(configuration: PostHogAnalyticsConfiguration, sdk: PostHogSDK = .shared) {
        guard let projectToken = configuration.projectToken,
              !projectToken.isEmpty
        else { return nil }

        self.sdk = sdk

        let postHogConfig = Self.sdkConfiguration(
            projectToken: projectToken,
            host: configuration.host
        )
        sdk.setup(postHogConfig)
    }

    static func sdkConfiguration(projectToken: String, host: String) -> PostHogConfig {
        let configuration = PostHogConfig(projectToken: projectToken, host: host)
        configuration.captureApplicationLifecycleEvents = false
        configuration.captureScreenViews = false
        configuration.captureElementInteractions = false
        configuration.enableSwizzling = false
        configuration.sessionReplay = false
        configuration.surveys = false
        configuration.errorTrackingConfig.autoCapture = false
        configuration.setDefaultPersonProperties = false
        configuration.setBeforeSend { event in
            // Defense in depth: prevent event IPs from becoming GeoIP properties even if the
            // PostHog project-level IP capture setting is changed later.
            event.properties["$geoip_disable"] = true
            return event
        }
        return configuration
    }

    func track(_ event: AnalyticsEvent) {
        sdk.capture(event.name, properties: event.properties.reduce(into: [String: Any]()) { properties, item in
            properties[item.key] = item.value
        })
    }

    func identify(userID: String) {
        sdk.identify(userID)
    }

    func resetIdentity() {
        sdk.reset()
    }
#else
    init?(configuration: PostHogAnalyticsConfiguration) {
        return nil
    }

    func track(_ event: AnalyticsEvent) {}
    func identify(userID: String) {}
    func resetIdentity() {}
#endif
}

private func trimmedPostHogString(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
        return nil
    }

    return trimmed
}
