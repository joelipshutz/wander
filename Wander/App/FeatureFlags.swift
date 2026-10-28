import Foundation

enum FeatureFlagValue: Equatable {
    case boolean(Bool)
    case integer(Int)

    var booleanValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var displayValue: String {
        switch self {
        case .boolean(let value):
            value ? "On" : "Off"
        case .integer(let value):
            String(value)
        }
    }
}

enum FeatureFlagValueKind: String, Equatable {
    case boolean
    case integer
}

struct FeatureFlagDefinition: Equatable {
    let title: String
    let summary: String
    let bundledDefault: FeatureFlagValue
    let integerRange: ClosedRange<Int>?
    let allowsRemoteAccountOverride: Bool
    let isEditableOnDevice: Bool

    var valueKind: FeatureFlagValueKind {
        switch bundledDefault {
        case .boolean:
            .boolean
        case .integer:
            .integer
        }
    }

    func accepts(_ value: FeatureFlagValue) -> Bool {
        switch (bundledDefault, value) {
        case (.boolean, .boolean):
            true
        case (.integer, .integer(let value)):
            integerRange?.contains(value) ?? false
        default:
            false
        }
    }
}

/// The single app-side registry for rec.me feature flags. Adding a case here
/// makes the flag remotely fetchable and visible in the tester Settings UI.
enum FeatureFlagKey: String, CaseIterable, Hashable {
    case firstVisitNUX = "first_visit_nux"
    case debugSettings = "debug_settings"
    case placeProfileSaveTrayV1 = "place_profile_save_tray_v1"
    case semanticPlaceSearchV1 = "semantic_place_search_v1"
    case socialImportApifyGeminiV1 = "social_import_apify_gemini_v1"
    case placeProfileActionVariant = "place_profile_action_variant"
    case profileFeedbackV1 = "profile_feedback_v1"
    case notificationRepromptCampaign = "notification_reprompt_campaign"
    case unifiedLiveV1 = "unified_live_v1"

    var definition: FeatureFlagDefinition {
        switch self {
        case .unifiedLiveV1:
            FeatureFlagDefinition(
                title: "Unified Live Experience",
                summary: "Combines Map And Feed With Three Tabs And Private Replies. Restart To Apply.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .firstVisitNUX:
            FeatureFlagDefinition(
                title: "First-Visit NUX",
                summary: "Shows The Guided First-Visit Walkthrough.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .debugSettings:
            FeatureFlagDefinition(
                title: "Debug Settings Access",
                summary: "Server Entitlement For This Tester Control Panel.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: false
            )
        case .placeProfileSaveTrayV1:
            FeatureFlagDefinition(
                title: "Place Profile Save Tray V1",
                summary: "Uses The Floating Check In And Wanna Actions On Place Profiles.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .semanticPlaceSearchV1:
            FeatureFlagDefinition(
                title: "Semantic Place Search V1",
                summary: "Adds Semantic Candidate Retrieval To Place Search.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: false,
                isEditableOnDevice: true
            )
        case .socialImportApifyGeminiV1:
            FeatureFlagDefinition(
                title: "Apify + Gemini Social Import V1",
                summary: "Uses Server-Backed Understanding For Instagram And TikTok Imports.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .placeProfileActionVariant:
            FeatureFlagDefinition(
                title: "Place Button Style",
                summary: "Selects The Place-Profile Floating Action Layout.",
                bundledDefault: .integer(5),
                integerRange: 1 ... 5,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .profileFeedbackV1:
            FeatureFlagDefinition(
                title: "Profile Feedback",
                summary: "Shows The Profile Feedback Button. Enable After Delivery Setup Is Verified.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .notificationRepromptCampaign:
            FeatureFlagDefinition(
                title: "Notification Re-Prompt Campaign",
                summary: "0 Is Off. A Higher Campaign Number Reopens The Notification Primer Once Per Account On This Device While Notifications Are Off.",
                bundledDefault: .integer(0),
                integerRange: 0 ... 1_000_000,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        }
    }
}

enum FeatureFlagValueSource: Equatable {
    case bundledDefault
    case globalDefault
    case accountOverride
    case deviceOverride

    var settingsLabel: String {
        switch self {
        case .bundledDefault:
            "Bundled Default"
        case .globalDefault:
            "Remote Default"
        case .accountOverride:
            "Remote Account Override"
        case .deviceOverride:
            "Device Override"
        }
    }
}

struct ResolvedFeatureFlagValue: Equatable {
    let value: FeatureFlagValue
    let source: FeatureFlagValueSource

    init(value: FeatureFlagValue, source: FeatureFlagValueSource) {
        self.value = value
        self.source = source
    }

    init(isEnabled: Bool, source: FeatureFlagValueSource) {
        self.init(value: .boolean(isEnabled), source: source)
    }

    var isEnabled: Bool { value.booleanValue ?? false }
    var integerValue: Int? { value.integerValue }

    var explicitAccountOverride: Bool? {
        source == .accountOverride ? value.booleanValue : nil
    }
}

/// Mutable desired device state. Feature consumers never read this live; the
/// backend reads an immutable snapshot captured during app launch instead.
struct FeatureFlagOverrideStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func override(for key: FeatureFlagKey, userID: String) -> FeatureFlagValue? {
        Self.decode(
            defaults.object(forKey: Self.storageKey(for: key, userID: userID)),
            for: key
        ) ?? legacyOverride(for: key, userID: userID)
    }

    func overrides(for userID: String) -> [FeatureFlagKey: FeatureFlagValue] {
        Dictionary(uniqueKeysWithValues: FeatureFlagKey.allCases.compactMap { key in
            override(for: key, userID: userID).map { (key, $0) }
        })
    }

    func setOverride(_ value: FeatureFlagValue, for key: FeatureFlagKey, userID: String) {
        guard key.definition.isEditableOnDevice, key.definition.accepts(value) else { return }
        switch value {
        case .boolean(let value):
            defaults.set(value, forKey: Self.storageKey(for: key, userID: userID))
        case .integer(let value):
            defaults.set(value, forKey: Self.storageKey(for: key, userID: userID))
        }
        clearLegacyOverride(for: key, userID: userID)
    }

    func clearOverride(for key: FeatureFlagKey, userID: String) {
        defaults.removeObject(forKey: Self.storageKey(for: key, userID: userID))
        clearLegacyOverride(for: key, userID: userID)
    }

    func clearAllOverrides(for userID: String) {
        for key in FeatureFlagKey.allCases where key.definition.isEditableOnDevice {
            clearOverride(for: key, userID: userID)
        }
    }

    func launchSnapshot() -> FeatureFlagDeviceOverrideSnapshot {
        FeatureFlagDeviceOverrideSnapshot(values: defaults.dictionaryRepresentation())
    }

    static func storageKey(for key: FeatureFlagKey, userID: String) -> String {
        "wander.featureFlags.\(userID).\(key.rawValue).deviceOverride"
    }

    static func legacyStorageKey(for key: FeatureFlagKey, userID: String) -> String? {
        switch key {
        case .firstVisitNUX:
            "wander.debugSettings.\(userID).firstVisitNUX.enabled"
        case .placeProfileActionVariant:
            "wander.debugSettings.\(userID).placeActionVariant"
        case .debugSettings,
             .placeProfileSaveTrayV1,
             .semanticPlaceSearchV1,
             .socialImportApifyGeminiV1,
             .profileFeedbackV1,
             .unifiedLiveV1,
             .notificationRepromptCampaign:
            nil
        }
    }

    fileprivate static func decode(_ object: Any?, for key: FeatureFlagKey) -> FeatureFlagValue? {
        guard let object else { return nil }
        let value: FeatureFlagValue?
        switch key.definition.valueKind {
        case .boolean:
            value = (object as? NSNumber).map { .boolean($0.boolValue) }
        case .integer:
            value = (object as? NSNumber).map { .integer($0.intValue) }
        }
        guard let value, key.definition.accepts(value) else { return nil }
        return value
    }

    private func legacyOverride(for key: FeatureFlagKey, userID: String) -> FeatureFlagValue? {
        guard let legacyKey = Self.legacyStorageKey(for: key, userID: userID) else { return nil }
        return Self.decode(defaults.object(forKey: legacyKey), for: key)
    }

    private func clearLegacyOverride(for key: FeatureFlagKey, userID: String) {
        guard let legacyKey = Self.legacyStorageKey(for: key, userID: userID) else { return }
        defaults.removeObject(forKey: legacyKey)
    }
}

/// Immutable process-lifetime values. This is the restart guarantee: Settings
/// writes the next launch's desired state without changing active behavior.
struct FeatureFlagDeviceOverrideSnapshot {
    private let values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func override(for key: FeatureFlagKey, userID: String) -> FeatureFlagValue? {
        FeatureFlagOverrideStore.decode(
            values[FeatureFlagOverrideStore.storageKey(for: key, userID: userID)],
            for: key
        ) ?? legacyOverride(for: key, userID: userID)
    }

    private func legacyOverride(for key: FeatureFlagKey, userID: String) -> FeatureFlagValue? {
        guard let legacyKey = FeatureFlagOverrideStore.legacyStorageKey(
            for: key,
            userID: userID
        ) else { return nil }
        return FeatureFlagOverrideStore.decode(values[legacyKey], for: key)
    }
}
