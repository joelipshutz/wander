import Foundation

/// Supplied only by the first-visit entry. Ordinary guide replay has no context.
struct LiveIntroductionOrientationContext: Equatable, Sendable {
    let userID: String
    let version: Int

    init(userID: String, version: Int = LiveIntroductionStore.currentVersion) {
        self.userID = userID
        self.version = version
    }
}

/// Explicit reading acknowledgements for fresh orientation, separate from both
/// the presentation marker and archived recovery. No checkpoint is synthesized.
struct LiveIntroductionOrientationStore {
    let defaults: UserDefaults
    let version: Int

    init(defaults: UserDefaults = .standard, version: Int = LiveIntroductionStore.currentVersion) {
        self.defaults = defaults
        self.version = version
    }

    private struct Record: Codable, Equatable {
        let userID: String
        let version: Int
        var acknowledgedTargets: Set<WalkthroughTargetID> = []
    }

    /// A nil context is ordinary replay. Refuse every write if authentication,
    /// the current account, or existing recovery state no longer matches.
    @discardableResult
    func acknowledge(_ step: LiveIntroductionStep,
                     context: LiveIntroductionOrientationContext?,
                     authenticatedUserID: String?, storeUserID: String,
                     isSessionValidated: Bool) -> Bool {
        guard let context, !context.userID.isEmpty, context.version == version,
              isSessionValidated, authenticatedUserID == context.userID,
              storeUserID == context.userID else { return false }
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        guard !legacy.hasCheckpointRecord(for: context.userID),
              !legacy.requiresLegacySessionRetirement(for: context.userID),
              !LiveIntroductionMigrationStore(defaults: defaults).hasRecord(for: context.userID)
        else { return false }

        let surfaces = FirstVisitWalkthroughContent.primaryJourneySurfaces
        let targets = surfaces.flatMap { FirstVisitWalkthroughContent.stepsBySurface[$0, default: []] }
            .map(\.target).filter { LiveIntroductionMigrationStore.guideStep(for: $0) == step }
        guard !targets.isEmpty else { return false }
        let storageKey = key(for: context.userID)
        var record: Record
        if defaults.object(forKey: storageKey) != nil {
            guard let data = defaults.data(forKey: storageKey),
                  let stored = try? JSONDecoder().decode(Record.self, from: data),
                  stored.userID == context.userID, stored.version == version else { return false }
            record = stored
        } else {
            record = Record(userID: context.userID, version: version)
        }
        record.acknowledgedTargets.formUnion(targets)
        guard let encoded = try? JSONEncoder().encode(record) else { return false }
        defaults.set(encoded, forKey: storageKey)

        // A repeated acknowledgement also repairs an interruption between the
        // local record and semantic progress writes. Never cross an unmapped
        // target or complete a real action, import or device lesson.
        for surface in surfaces where !legacy.isComplete(for: context.userID, surface: surface) {
            let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
            let prior = legacy.progress(for: context.userID, surface: surface)
            guard !steps.isEmpty, (0...steps.count).contains(prior) else { continue }
            var next = prior
            while next < steps.count,
                  LiveIntroductionMigrationStore.guideStep(for: steps[next].target) != nil,
                  record.acknowledgedTargets.contains(steps[next].target) { next += 1 }
            if next > prior { legacy.setProgress(next, for: context.userID, surface: surface) }
            if next == steps.count { legacy.markComplete(for: context.userID, surface: surface) }
        }
        return true
    }

    private func key(for userID: String) -> String {
        "astir.live.orientation.v\(version).\(userID)"
    }
}
