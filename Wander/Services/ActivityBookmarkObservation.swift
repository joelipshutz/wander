import Foundation
import Observation

/// Watches query inputs without retaining a second projection or authorization
/// policy. Unchanged objects keep their registrations across import checkpoints.
@MainActor
final class ActivityBookmarkObservation {
    private struct Key: Hashable {
        let identity: ObjectIdentifier
        let role: String
    }

    private let token = BookmarkObservationToken()
    private var entries: [Key: BookmarkObservationEntry] = [:]
    private var visited: Set<Key> = []
    private var isRefreshing = false
    private(set) var hasDemand = false
    private(set) var isFinished = false
    private(set) var registrationCount = 0

    var revision: UInt64 { token.revision }
    var hasPendingSettlement: Bool { token.hasPendingSettlement }
    var retainedRegistrationCount: Int { entries.count }

    func beginRefresh() -> Bool {
        guard !isFinished else { return false }
        hasDemand = true
        guard !hasPendingSettlement else { return false }
        visited.removeAll(keepingCapacity: true)
        isRefreshing = true
        return true
    }

    func watch<Model: AnyObject>(_ model: Model, role: String, read: (Model) -> Void) {
        guard isRefreshing, !isFinished, !hasPendingSettlement else { return }
        let key = Key(identity: ObjectIdentifier(model), role: role)
        visited.insert(key)
        if let existing = entries[key], existing.isValid { return }
        entries[key]?.finish()
        let token = token
        entries[key] = BookmarkObservationEntry(model: model, read: read) { [weak self, token] in
            // Observation fires before the model setter completes. Dirty state
            // precedes public notification, including synchronous reentrant reads.
            guard let ticket = token.invalidateForMutation() else { return }
            Task { @MainActor [weak self] in self?.settle(ticket: ticket) }
        }
        registrationCount += 1
    }

    func endRefresh() {
        guard isRefreshing else { return }
        isRefreshing = false
        for (key, entry) in entries where !visited.contains(key) { entry.finish() }
        entries = entries.filter { visited.contains($0.key) }
        visited.removeAll(keepingCapacity: true)
    }

    /// Collection writes have already completed. Keep surviving registrations;
    /// the next query chooses their current roles and prunes removed objects.
    func invalidateStructure() { token.invalidateStructure() }

    func reset() {
        for entry in entries.values { entry.finish() }
        entries.removeAll()
        visited.removeAll()
        isRefreshing = false
        hasDemand = false
        token.reset()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        for entry in entries.values { entry.finish() }
        entries.removeAll()
        visited.removeAll()
        isRefreshing = false
        hasDemand = false
        // An independent model observer may retire this scope before our own
        // willSet callback runs. Conservatively keep the handoff uncached for
        // the rest of this actor turn, even if no pending callback was observed.
        if let ticket = token.invalidateForMutation() {
            Task { @MainActor [weak self] in self?.settle(ticket: ticket) }
        }
    }

    func waitForPendingSettlement() async {
        while hasPendingSettlement { await Task.yield() }
    }

    private func settle(ticket: UInt64) {
        token.settle(ticket: ticket)
    }
}

@MainActor
private final class BookmarkObservationEntry {
    // Retaining the object prevents ObjectIdentifier reuse before pruning.
    private let model: AnyObject
    private let sentinel = BookmarkObservationSentinel()
    private let validity = BookmarkObservationValidity()
    var isValid: Bool { validity.isValid }

    init<Model: AnyObject>(model: Model, read: (Model) -> Void,
                          onChange: @escaping @Sendable () -> Void) {
        self.model = model
        let validity = validity
        withObservationTracking {
            _ = sentinel.generation
            read(model)
        } onChange: { [weak validity] in
            guard validity?.invalidateIfActive() == true else { return }
            onChange()
        }
    }

    func finish() {
        // The sentinel cancels one-shot registrations still waiting on models.
        // It must not publish an invalidation from a retired role or account.
        validity.finish()
        sentinel.generation &+= 1
    }
}

@MainActor @Observable
private final class BookmarkObservationSentinel {
    var generation: UInt64 = 0
}

private final class BookmarkObservationValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var valid = true
    var isValid: Bool { lock.withLock { active && valid } }
    func invalidateIfActive() -> Bool {
        lock.withLock {
            guard active, valid else { return false }
            valid = false
            return true
        }
    }
    func finish() { lock.withLock { active = false; valid = false } }
}

/// Observation callbacks may be Sendable, but never read actor-isolated models.
/// Locks protect state only; public notifications always run outside the lock.
private final class BookmarkObservationToken: Observable, @unchecked Sendable {
    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var settlementTicket: UInt64 = 0
    private var pending = false
    private var isPublishing = false

    var revision: UInt64 {
        registrar.access(self, keyPath: \.revision)
        return lock.withLock { epoch }
    }
    var hasPendingSettlement: Bool { lock.withLock { pending } }

    func invalidateForMutation() -> UInt64? {
        let ticket: UInt64? = lock.withLock {
            epoch &+= 1
            guard !pending else { return nil }
            pending = true
            settlementTicket &+= 1
            return settlementTicket
        }
        publish()
        return ticket
    }

    func invalidateStructure() {
        lock.withLock { epoch &+= 1 }
        publish()
    }

    func reset() {
        lock.withLock {
            epoch &+= 1
            // A reset can itself be called by a willSet observer. Preserve its
            // pending boundary until the already queued settlement executes.
            if !pending { settlementTicket &+= 1 }
        }
        publish()
    }

    func settle(ticket: UInt64) {
        let changed = lock.withLock {
            guard pending, settlementTicket == ticket else { return false }
            pending = false
            epoch &+= 1
            return true
        }
        // A caller may have observed the old value synchronously inside willSet.
        // Notify once more after that setter so its next read sees final values.
        if changed { publish() }
    }

    private func publish() {
        // Observation removes a one-shot callback after it returns. A callback
        // can finish the import scope synchronously, so do not recursively
        // notify that same registration while the outer publication unwinds.
        // Epoch/pending state is already dirty; settlement still publishes the
        // final post-setter value, and later independent writes can notify.
        let action: (publish: Bool, settlement: UInt64?) = lock.withLock {
            if isPublishing {
                // Structure/reset notifications can nest without a model's
                // pending setter. Give that change its own coalesced boundary
                // instead of losing a newly installed observer's notification.
                guard !pending else { return (false, nil) }
                pending = true
                settlementTicket &+= 1
                return (false, settlementTicket)
            }
            isPublishing = true
            return (true, nil)
        }
        if let ticket = action.settlement {
            Task { @MainActor [weak self] in self?.settle(ticket: ticket) }
        }
        guard action.publish else { return }
        defer { lock.withLock { isPublishing = false } }
        registrar.withMutation(of: self, keyPath: \.revision) {}
    }
}
