import Foundation
import Combine

struct LiveIntroductionMigrationRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: String
    let checkpoint: FirstVisitWalkthroughCheckpoint
    let requiredTargets: [WalkthroughTargetID]
    var acknowledgedTargets: Set<WalkthroughTargetID> = []
    var hasBeenOffered = false
    var recoveryOpened = false
    var recoveryCompleted = false
    var recoveryDismissed = false
    var contactSelection: Set<String>?

    var recovery: LiveIntroductionResumePlan.Destination? {
        let destination = LiveIntroductionCheckpointAdapter.plan(for: checkpoint, completedSurfaces: [], hasPriorityPresentation: false).destination
        switch destination {
        case .retained, .retainedLesson: return recoveryCompleted || recoveryDismissed ? nil : destination
        default: return nil
        }
    }

    var pendingSteps: [LiveIntroductionStep] {
        var seen: Set<LiveIntroductionStep> = []
        return requiredTargets.filter { !acknowledgedTargets.contains($0) }.compactMap { target in
            guard let step = LiveIntroductionMigrationStore.guideStep(for: target), seen.insert(step).inserted else { return nil }
            return step
        }
    }

    var isComplete: Bool { requiredTargets.allSatisfy(acknowledgedTargets.contains) && recovery == nil }

    func canCompleteSaveRecovery(with draft: PlaceSaveDraft) -> Bool {
        guard draft.ownerUserID == userID else { return false }
        switch recovery {
        case .retained(.saveFlow, _), .retained(.add, _), .retained(.map, .mapAddAgain):
            return checkpoint.tutorialCandidate.map { $0.id == draft.candidate.id }
                ?? (draft.walkthroughContentVersion != nil)
        default: return false
        }
    }
}

/// Owns only migration/teaching state. It never changes a save, permission,
/// invitation, or account onboarding state. Original checkpoints remain archived.
struct LiveIntroductionMigrationStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var legacy: FirstVisitWalkthroughStore { FirstVisitWalkthroughStore(defaults: defaults) }
    private func key(_ userID: String) -> String { "astir.live.migration.v1.\(userID)" }

    /// An unreadable recovery record still blocks fresh-orientation writes.
    func hasRecord(for userID: String) -> Bool {
        !userID.isEmpty && defaults.object(forKey: key(userID)) != nil
    }

    func load(for userID: String) -> LiveIntroductionMigrationRecord? {
        guard !userID.isEmpty, let data = defaults.data(forKey: key(userID)),
              let record = try? JSONDecoder().decode(LiveIntroductionMigrationRecord.self, from: data),
              record.userID == userID else { return nil }
        return record
    }

    @discardableResult
    func capture(for userID: String) -> LiveIntroductionMigrationRecord? {
        guard !userID.isEmpty else { return nil }
        let activeCheckpoint = legacy.checkpoint(for: userID)
        if let existing = load(for: userID), activeCheckpoint == nil || activeCheckpoint == existing.checkpoint {
            // Recover an interruption between durable archive and slot removal.
            if legacy.checkpoint(for: userID) == existing.checkpoint { legacy.clearCheckpoint(for: userID) }
            return existing
        }
        guard let checkpoint = activeCheckpoint else { return nil }
        var targets: [WalkthroughTargetID] = []
        for surface in FirstVisitWalkthroughContent.primaryJourneySurfaces where !legacy.isComplete(for: userID, surface: surface) {
            let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
            let checkpointIndex = checkpoint.presentation == nil ? (steps.firstIndex { $0.target == checkpoint.target } ?? 0) : 0
            let start = min(max(legacy.progress(for: userID, surface: surface), checkpointIndex), steps.count)
            targets += steps.dropFirst(start).map(\.target)
        }
        if checkpoint.presentation == nil, Self.guideStep(for: checkpoint.target) != nil,
           !FirstVisitWalkthroughContent.allSteps.contains(where: { $0.target == checkpoint.target }),
           !targets.contains(checkpoint.target),
           !legacy.isComplete(for: userID, surface: LiveIntroductionCheckpointAdapter.legacySurface(for: checkpoint.target)) {
            targets.insert(checkpoint.target, at: 0)
        }
        let record = LiveIntroductionMigrationRecord(id: UUID(), userID: userID, checkpoint: checkpoint, requiredTargets: targets)
        guard save(record), load(for: userID) == record else { return nil }
        legacy.clearCheckpoint(for: userID)
        return record
    }

    @discardableResult
    func markOffered(userID: String, recordID: UUID) -> LiveIntroductionMigrationRecord? {
        mutate(userID: userID, recordID: recordID) { $0.hasBeenOffered = true }
    }

    @discardableResult
    func acknowledge(_ step: LiveIntroductionStep, userID: String, recordID: UUID) -> LiveIntroductionMigrationRecord? {
        guard let current = load(for: userID), current.id == recordID,
              current.requiredTargets.contains(where: { Self.guideStep(for: $0) == step }) else { return nil }
        guard let record = mutate(userID: userID, recordID: recordID, { record in
            for target in record.requiredTargets where Self.guideStep(for: target) == step {
                record.acknowledgedTargets.insert(target)
            }
        }) else { return nil }
        // Advance only contiguous, represented progress. Never rewind or mark
        // an unrelated surface/import/device lesson complete.
        for surface in FirstVisitWalkthroughContent.primaryJourneySurfaces where !legacy.isComplete(for: userID, surface: surface) {
            let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
            guard steps.contains(where: { record.requiredTargets.contains($0.target) }) else { continue }
            let checkpointFloor = record.checkpoint.presentation == nil ? (steps.firstIndex { $0.target == record.checkpoint.target } ?? 0) : 0
            var progress = min(max(legacy.progress(for: userID, surface: surface), checkpointFloor), steps.count)
            while progress < steps.count, record.acknowledgedTargets.contains(steps[progress].target) { progress += 1 }
            legacy.setProgress(progress, for: userID, surface: surface)
            if !steps.isEmpty, progress == steps.count { legacy.markComplete(for: userID, surface: surface) }
        }
        return record
    }

    @discardableResult
    func markRecoveryOpened(userID: String, recordID: UUID) -> LiveIntroductionMigrationRecord? {
        mutate(userID: userID, recordID: recordID) { $0.recoveryOpened = true }
    }

    /// Only actual domain evidence or explicit acknowledgment of an educational
    /// lesson may call this. Opening/cancelling a real editor is not completion.
    @discardableResult
    func completeRecovery(userID: String, recordID: UUID) -> LiveIntroductionMigrationRecord? {
        mutate(userID: userID, recordID: recordID) { $0.recoveryCompleted = true }
    }

    @discardableResult
    func dismissRecovery(userID: String, recordID: UUID) -> LiveIntroductionMigrationRecord? {
        mutate(userID: userID, recordID: recordID) { $0.recoveryDismissed = true }
    }

    func updateContactSelection(_ ids: Set<String>, userID: String, recordID: UUID) {
        _ = mutate(userID: userID, recordID: recordID) { $0.contactSelection = ids }
    }

    static func guideStep(for target: WalkthroughTargetID) -> LiveIntroductionStep? {
        let checkpoint = FirstVisitWalkthroughCheckpoint(target: target, updatedAt: .distantPast,
            tutorialCandidate: nil, tutorialUserPlaceID: nil, tutorialMemorySnapshot: nil)
        if case .guide(let step) = LiveIntroductionCheckpointAdapter.plan(for: checkpoint, completedSurfaces: [], hasPriorityPresentation: false).destination { return step }
        return nil
    }

    private func mutate(userID: String, recordID: UUID, _ update: (inout LiveIntroductionMigrationRecord) -> Void) -> LiveIntroductionMigrationRecord? {
        guard var record = load(for: userID), record.id == recordID else { return nil }
        update(&record)
        return save(record) ? record : nil
    }
    private func save(_ record: LiveIntroductionMigrationRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        // Keep each original when a newer legacy checkpoint supersedes it.
        // This is logical write ordering, not a filesystem durability promise.
        defaults.set(data, forKey: key(record.userID) + ".archive." + record.id.uuidString)
        defaults.set(data, forKey: key(record.userID))
        return true
    }
}

struct LiveIntroductionRecoveryRequest: Equatable, Identifiable {
    let id = UUID()
    let userID: String
    let recordID: UUID
}

/// A replay may disappear because it pushed a teaching guide or changed tabs.
/// Only an explicit Continue action arms this one-shot, process-only handoff.
struct LiveIntroductionReplayRecoveryHandoff {
    private var pending: LiveIntroductionRecoveryRequest?
    var hasPendingRequest: Bool { pending != nil }

    mutating func queue(_ record: LiveIntroductionMigrationRecord,
                        authenticatedUserID: String?, storeUserID: String, isSessionValidated: Bool) -> Bool {
        guard isSessionValidated, pending == nil, record.userID == authenticatedUserID,
              record.userID == storeUserID, record.recovery != nil else { return false }
        pending = LiveIntroductionRecoveryRequest(userID: record.userID, recordID: record.id)
        return true
    }

    mutating func cancel() { pending = nil }

    mutating func takeAfterDisappearance(authenticatedUserID: String?, storeUserID: String,
                                         isSessionValidated: Bool, latestRecord: LiveIntroductionMigrationRecord?) -> LiveIntroductionMigrationRecord? {
        defer { pending = nil }
        guard isSessionValidated, let pending, pending.userID == authenticatedUserID, pending.userID == storeUserID,
              let latestRecord, latestRecord.userID == pending.userID,
              latestRecord.id == pending.recordID, latestRecord.recovery != nil else { return nil }
        return latestRecord
    }
}

/// Process-only handoff from Settings or the guide to the authenticated root.
@MainActor
final class LiveIntroductionRecoveryCenter: ObservableObject {
    static let shared = LiveIntroductionRecoveryCenter()
    @Published private(set) var request: LiveIntroductionRecoveryRequest?
    @Published private(set) var revision = 0
    func didChange() { revision &+= 1 }
    func open(_ record: LiveIntroductionMigrationRecord) {
        request = LiveIntroductionRecoveryRequest(userID: record.userID, recordID: record.id)
    }
    func consume(_ id: UUID) { if request?.id == id { request = nil } }
}
