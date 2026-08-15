import Foundation

struct WanderBackendConfiguration: Equatable {
    static let defaultClerkPublishableKey = "pk_live_Y2xlcmsuZ2V0cmVjLm1lJA"
    static let defaultClerkFrontendAPI = "clerk.getrec.me"
    static let defaultSupabaseURLString = "https://rugmtlgufrhlxwfkumhw.supabase.co"
    static let defaultSupabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ1Z210bGd1ZnJobHh3Zmt1bWh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MjcxNjEsImV4cCI6MjA5NjAwMzE2MX0.O0HUcTUaAV1aq3UBusp1ggQNvIgS_e2NEVYtHW6hnwo"

    let clerkPublishableKey: String?
    let clerkFrontendAPI: String?
    let supabaseURL: URL?
    let supabasePublishableKey: String?

    var isClerkConfigured: Bool {
        clerkPublishableKey?.isEmpty == false
    }

    var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabasePublishableKey?.isEmpty == false
    }

    static func current(bundle: Bundle = .main) -> WanderBackendConfiguration {
        current { key in
            bundle.object(forInfoDictionaryKey: key) as? String
        }
    }

    static func current(valueFor keyValue: (String) -> String?) -> WanderBackendConfiguration {
        let supabaseURLString = resolvedString(
            for: "WANDER_SUPABASE_URL",
            fallback: defaultSupabaseURLString,
            valueFor: keyValue
        )

        return WanderBackendConfiguration(
            clerkPublishableKey: resolvedString(
                for: "WANDER_CLERK_PUBLISHABLE_KEY",
                fallback: defaultClerkPublishableKey,
                valueFor: keyValue
            ),
            clerkFrontendAPI: resolvedString(
                for: "WANDER_CLERK_FRONTEND_API",
                fallback: defaultClerkFrontendAPI,
                valueFor: keyValue
            ),
            supabaseURL: supabaseURLString.flatMap(URL.init(string:)),
            supabasePublishableKey: resolvedString(
                for: "WANDER_SUPABASE_PUBLISHABLE_KEY",
                fallback: defaultSupabasePublishableKey,
                valueFor: keyValue
            )
        )
    }

    private static func resolvedString(
        for key: String,
        fallback: String,
        valueFor keyValue: (String) -> String?
    ) -> String? {
        trimmedString(keyValue(key)) ?? fallback
    }
}

private func trimmedString(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
        return nil
    }

    return trimmed
}
