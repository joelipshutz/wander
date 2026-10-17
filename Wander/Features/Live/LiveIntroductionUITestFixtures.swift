#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Isolated UI-test teaching state. No ordinary account, draft, cache, network,
/// permission or invitation data is changed. Relaunching the same run preserves
/// the checkpoint archive and acknowledgements being exercised.
enum LiveIntroductionUITestFixtures {
    private static let userID = "user_joe"
    private static let runKey = "astir.live.introduction.uiTest.user_joe.run"

    enum Scenario: String { case guide, calendar, device, cleanup }

    static func prepare(arguments: [String] = ProcessInfo.processInfo.arguments,
                        authenticatedUserID: String?, defaults: UserDefaults = .standard) {
        guard authenticatedUserID == userID,
              arguments.contains("-WanderAuthenticatedUITest"),
              arguments.contains("-WanderUseDemoFixtures"),
              let scenarioValue = value(after: "-WanderLiveIntroductionUITest", in: arguments),
              let scenario = Scenario(rawValue: scenarioValue),
              let runID = value(after: "-WanderLiveIntroductionUITestRun", in: arguments),
              UUID(uuidString: runID) != nil else { return }

        let overrides = FeatureFlagOverrideStore(defaults: defaults)
        if scenario == .cleanup {
            resetTeaching(defaults: defaults)
            defaults.removeObject(forKey: runKey)
            overrides.clearOverride(for: .unifiedLiveV1, userID: userID)
            return
        }

        let identity = "\(runID)|\(scenario.rawValue)"
        if defaults.string(forKey: runKey) != identity {
            resetTeaching(defaults: defaults)
            let legacy = FirstVisitWalkthroughStore(defaults: defaults)
            if scenario != .guide {
                legacy.markComplete(for: userID, surface: .map)
                legacy.markComplete(for: userID, surface: .feed)
            } else {
                legacy.setProgress(2, for: userID, surface: .map)
            }
            legacy.setCheckpoint(FirstVisitWalkthroughCheckpoint(
                target: scenario == .guide ? .mapMoreFilters : scenario == .calendar ? .profileCalendar : .mapAddAgain,
                updatedAt: .now, tutorialCandidate: nil, tutorialUserPlaceID: nil,
                tutorialMemorySnapshot: nil,
                presentation: scenario == .device ? .deviceFeaturesLesson : nil
            ), for: userID)
            defaults.set(identity, forKey: runKey)
        }
        // Use the normal account-scoped platform before the launch snapshot is
        // created. Explicit Off wins even with the isolated Live review flag.
        overrides.setOverride(.boolean(!arguments.contains("-WanderLiveIntroductionUITestRollback")),
                              for: .unifiedLiveV1, userID: userID)
    }

    private static func resetTeaching(defaults: UserDefaults) {
        FirstVisitWalkthroughStore(defaults: defaults).reset(for: userID)
        let exact = ["astir.live.introduction.v1.user_joe", "astir.live.orientation.v1.user_joe",
                     "astir.live.migration.v1.user_joe"]
        let prefixes = ["astir.live.introduction.v1.user_joe.", "astir.live.migration.v1.user_joe.archive."]
        for key in defaults.dictionaryRepresentation().keys
            where exact.contains(key) || prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
