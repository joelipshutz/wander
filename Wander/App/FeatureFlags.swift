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
            integerRange?.contains(value) ?? true
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
    case placeProfileActionVariant = "place_profile_action_variant"

    var definition: FeatureFlagDefinition {
        switch self {
        case .firstVisitNUX:
            FeatureFlagDefinition(
                title: "First-visit NUX",
                summary: "Shows the guided first-visit walkthrough.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .debugSettings:
            FeatureFlagDefinition(
                title: "Debug settings access",
                summary: "Server entitlement for this tester control panel.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: false
            )
        case .placeProfileSaveTrayV1:
            FeatureFlagDefinition(
                title: "Place profile save tray v1",
                summary: "Uses the floating Check in and Wanna actions on place profiles.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: true,
                isEditableOnDevice: true
            )
        case .semanticPlaceSearchV1:
            FeatureFlagDefinition(
                title: "Semantic place search v1",
                summary: "Adds semantic candidate retrieval to place search.",
                bundledDefault: .boolean(false),
                integerRange: nil,
                allowsRemoteAccountOverride: false,
                isEditableOnDevice: true
            )
        case .placeProfileActionVariant:
            FeatureFlagDefinition(
                title: "Place button style",
                summary: "Selects the place-profile floating action layout.",
                bundledDefault: .integer(5),
                integerRange: 1 ... 5,
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
            "Bundled default"
        case .globalDefault:
            "Remote default"
        case .accountOverride:
            "Remote account override"
        case .deviceOverride:
            "Device override"
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
        let legacyKey: String?
        switch key {
        case .firstVisitNUX:
            legacyKey = "wander.debugSettings.\(userID).firstVisitNUX.enabled"
        case .placeProfileActionVariant:
            legacyKey = "wander.debugSettings.\(userID).placeActionVariant"
        case .debugSettings, .placeProfileSaveTrayV1, .semanticPlaceSearchV1:
            legacyKey = nil
        }
        guard let legacyKey else { return nil }
        return Self.decode(defaults.object(forKey: legacyKey), for: key)
    }

    private func clearLegacyOverride(for key: FeatureFlagKey, userID: String) {
        switch key {
        case .firstVisitNUX:
            defaults.removeObject(forKey: "wander.debugSettings.\(userID).firstVisitNUX.enabled")
        case .placeProfileActionVariant:
            defaults.removeObject(forKey: "wander.debugSettings.\(userID).placeActionVariant")
        case .debugSettings, .placeProfileSaveTrayV1, .semanticPlaceSearchV1:
            break
        }
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
        let legacyKey: String?
        switch key {
        case .firstVisitNUX:
            legacyKey = "wander.debugSettings.\(userID).firstVisitNUX.enabled"
        case .placeProfileActionVariant:
            legacyKey = "wander.debugSettings.\(userID).placeActionVariant"
        case .debugSettings, .placeProfileSaveTrayV1, .semanticPlaceSearchV1:
            legacyKey = nil
        }
        guard let legacyKey else { return nil }
        return FeatureFlagOverrideStore.decode(values[legacyKey], for: key)
    }
}
