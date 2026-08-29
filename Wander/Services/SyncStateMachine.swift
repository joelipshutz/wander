import Foundation

struct SyncStateMachine {
    func canTransition(from current: SyncState, to next: SyncState) -> Bool {
        allowedTransitions[current, default: []].contains(next)
    }

    private var allowedTransitions: [SyncState: Set<SyncState>] {
        [
            .localOnly: [.pendingCreate, .tombstoned],
            .pendingCreate: [.synced, .failed, .serverDenied, .tombstoned],
            .pendingUpdate: [.synced, .failed, .serverDenied, .tombstoned],
            .pendingDelete: [.tombstoned, .failed],
            .failed: [.pendingCreate, .pendingUpdate, .pendingDelete, .tombstoned],
            .synced: [.pendingUpdate, .pendingDelete, .tombstoned],
            .serverDenied: [.localOnly, .tombstoned],
            .tombstoned: []
        ]
    }
}

struct DeferredSaveLifecycleStateMachine {
    func canTransition(
        from current: DeferredSaveLifecycleState,
        to next: DeferredSaveLifecycleState
    ) -> Bool {
        allowedTransitions[current, default: []].contains(next)
    }

    private var allowedTransitions: [DeferredSaveLifecycleState: Set<DeferredSaveLifecycleState>] {
        [
            .pending: [.optimisticallyCompleted, .failed, .permanentlyFailed],
            .optimisticallyCompleted: [.confirmed, .failed, .retrying, .permanentlyFailed],
            .confirmed: [],
            .failed: [.retrying, .permanentlyFailed],
            .retrying: [.confirmed, .failed, .permanentlyFailed],
            .permanentlyFailed: [.retrying]
        ]
    }
}
