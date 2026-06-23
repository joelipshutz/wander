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

        let postHogConfig = PostHogConfig(projectToken: projectToken, host: configuration.host)
        postHogConfig.captureScreenViews = false
        postHogConfig.captureElementInteractions = false
        postHogConfig.sessionReplay = false
        postHogConfig.surveys = false
        sdk.setup(postHogConfig)
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
