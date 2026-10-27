#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import Wander

@MainActor
final class LiveIntroductionUITestFixtureTests: XCTestCase {
    func testRequiresEveryFixtureGateAndExactScenario() throws {
        let defaults = try makeDefaults()
        let valid = arguments(scenario: "calendar")
        for omitted in ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderLiveIntroductionUITest"] {
            let before = defaults.dictionaryRepresentation()
            LiveIntroductionUITestFixtures.prepare(arguments: valid.filter { $0 != omitted },
                authenticatedUserID: "user_joe", defaults: defaults)
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
        }
        LiveIntroductionUITestFixtures.prepare(arguments: arguments(scenario: "unknown"),
            authenticatedUserID: "user_joe", defaults: defaults)
        LiveIntroductionUITestFixtures.prepare(arguments: valid, authenticatedUserID: "other", defaults: defaults)
        XCTAssertNil(FirstVisitWalkthroughStore(defaults: defaults).checkpoint(for: "user_joe"))
    }

    func testSameRunRetainsArchiveAndProgressAcrossExplicitOffRelaunch() throws {
        let defaults = try makeDefaults()
        let launch = arguments(scenario: "guide")
        LiveIntroductionUITestFixtures.prepare(arguments: launch, authenticatedUserID: "user_joe", defaults: defaults)
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let original = try XCTUnwrap(migration.capture(for: "user_joe"))
        _ = migration.acknowledge(.drawArea, userID: "user_joe", recordID: original.id)
        _ = migration.markOffered(userID: "user_joe", recordID: original.id)
        let progressed = try XCTUnwrap(migration.load(for: "user_joe"))
        LiveIntroductionUITestFixtures.prepare(arguments: launch + ["-WanderLiveIntroductionUITestRollback"],
            authenticatedUserID: "user_joe", defaults: defaults)
        XCTAssertEqual(migration.load(for: "user_joe"), progressed)
        XCTAssertNil(FirstVisitWalkthroughStore(defaults: defaults).checkpoint(for: "user_joe"))
        XCTAssertEqual(FeatureFlagOverrideStore(defaults: defaults).override(for: .unifiedLiveV1,
            userID: "user_joe"), .boolean(false))
    }

    func testCleanupTouchesOnlyKnownFixtureTeachingAndOneFlag() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        legacy.setProgress(4, for: "other", surface: .map)
        defaults.set("ordinary-draft", forKey: "fixture-ordinary-draft")
        FeatureFlagOverrideStore(defaults: defaults).setOverride(.boolean(true), for: .firstVisitNUX, userID: "other")
        LiveIntroductionUITestFixtures.prepare(arguments: arguments(scenario: "calendar"),
            authenticatedUserID: "user_joe", defaults: defaults)
        XCTAssertNotNil(LiveIntroductionMigrationStore(defaults: defaults).capture(for: "user_joe"))
        LiveIntroductionUITestFixtures.prepare(arguments: arguments(scenario: "cleanup"),
            authenticatedUserID: "user_joe", defaults: defaults)
        XCTAssertNil(LiveIntroductionMigrationStore(defaults: defaults).load(for: "user_joe"))
        XCTAssertNil(legacy.checkpoint(for: "user_joe"))
        XCTAssertEqual(legacy.progress(for: "other", surface: .map), 4)
        XCTAssertEqual(defaults.string(forKey: "fixture-ordinary-draft"), "ordinary-draft")
        XCTAssertEqual(FeatureFlagOverrideStore(defaults: defaults).override(for: .firstVisitNUX,
            userID: "other"), .boolean(true))
        XCTAssertNil(FeatureFlagOverrideStore(defaults: defaults).override(for: .unifiedLiveV1, userID: "user_joe"))
    }

    private func arguments(scenario: String) -> [String] {
        ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderLiveIntroductionUITest", scenario,
         "-WanderLiveIntroductionUITestRun", UUID().uuidString]
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "LiveIntroductionUITestFixtureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
#endif
