import XCTest
@testable import Wander

@MainActor
final class FeatureFlagTests: XCTestCase {
    func testRegistryContainsEveryHostedFlagAndTypedDefinitions() {
        XCTAssertEqual(
            FeatureFlagKey.allCases.map(\.rawValue),
            [
                "first_visit_nux",
                "debug_settings",
                "place_profile_save_tray_v1",
                "semantic_place_search_v1",
                "place_profile_action_variant",
            ]
        )
        XCTAssertEqual(FeatureFlagKey.placeProfileSaveTrayV1.definition.valueKind, .boolean)
        XCTAssertTrue(FeatureFlagKey.placeProfileSaveTrayV1.definition.isEditableOnDevice)
        XCTAssertEqual(FeatureFlagKey.placeProfileActionVariant.definition.valueKind, .integer)
        XCTAssertEqual(FeatureFlagKey.placeProfileActionVariant.definition.integerRange, 1 ... 5)
        XCTAssertFalse(FeatureFlagKey.debugSettings.definition.isEditableOnDevice)
    }

    func testOverrideStorePersistsBooleanAndIntegerValuesPerAccount() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureFlagOverrideStore(defaults: defaults)

        store.setOverride(.boolean(true), for: .placeProfileSaveTrayV1, userID: "user_a")
        store.setOverride(.integer(2), for: .placeProfileActionVariant, userID: "user_a")
        store.setOverride(.integer(99), for: .placeProfileActionVariant, userID: "user_a")

        XCTAssertEqual(
            store.override(for: .placeProfileSaveTrayV1, userID: "user_a"),
            .boolean(true)
        )
        XCTAssertEqual(
            store.override(for: .placeProfileActionVariant, userID: "user_a"),
            .integer(2),
            "An invalid integer must not replace the last valid override."
        )
        XCTAssertNil(store.override(for: .placeProfileSaveTrayV1, userID: "user_b"))

        store.clearAllOverrides(for: "user_a")
        XCTAssertTrue(store.overrides(for: "user_a").isEmpty)
    }

    func testLaunchSnapshotMakesChangesApplyOnlyAfterRestartAndResetReturnsToRemote() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureFlagOverrideStore(defaults: defaults)
        let remoteValues: [FeatureFlagKey: ResolvedFeatureFlagValue] = [
            .placeProfileSaveTrayV1: ResolvedFeatureFlagValue(
                isEnabled: false,
                source: .globalDefault
            )
        ]

        let runningBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        await runningBackend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(runningBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), false)

        store.setOverride(.boolean(true), for: .placeProfileSaveTrayV1, userID: "user_a")
        XCTAssertEqual(
            runningBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"),
            false,
            "The running process must keep the launch snapshot until restart."
        )

        let restartedBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        XCTAssertEqual(restartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), true)
        XCTAssertEqual(
            restartedBackend.resolvedFeatureFlag(.placeProfileSaveTrayV1, for: "user_a")?.source,
            .deviceOverride
        )

        store.clearOverride(for: .placeProfileSaveTrayV1, userID: "user_a")
        XCTAssertEqual(restartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), true)

        let resetAndRestartedBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        await resetAndRestartedBackend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(
            resetAndRestartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"),
            false
        )
        XCTAssertEqual(
            resetAndRestartedBackend.resolvedFeatureFlag(.placeProfileSaveTrayV1, for: "user_a")?.source,
            .globalDefault
        )
    }

    func testLegacyNUXAndPlaceActionOverridesAreReadAndMigrated() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "wander.debugSettings.user_a.firstVisitNUX.enabled")
        defaults.set(3, forKey: "wander.debugSettings.user_a.placeActionVariant")
        let store = FeatureFlagOverrideStore(defaults: defaults)

        XCTAssertEqual(store.override(for: .firstVisitNUX, userID: "user_a"), .boolean(true))
        XCTAssertEqual(store.override(for: .placeProfileActionVariant, userID: "user_a"), .integer(3))

        store.setOverride(.integer(4), for: .placeProfileActionVariant, userID: "user_a")
        XCTAssertNil(defaults.object(forKey: "wander.debugSettings.user_a.placeActionVariant"))
        XCTAssertEqual(store.override(for: .placeProfileActionVariant, userID: "user_a"), .integer(4))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "FeatureFlagTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private struct FeatureFlagTestRepository: FeatureFlagRepository {
    let values: [FeatureFlagKey: ResolvedFeatureFlagValue]

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        values
    }
}
