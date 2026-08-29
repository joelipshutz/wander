import XCTest
@testable import Wander

final class SyncStateMachineTests: XCTestCase {
    private let stateMachine = SyncStateMachine()

    func testAllowedCreateFlowTransitions() {
        XCTAssertTrue(stateMachine.canTransition(from: .localOnly, to: .pendingCreate))
        XCTAssertTrue(stateMachine.canTransition(from: .pendingCreate, to: .synced))
        XCTAssertTrue(stateMachine.canTransition(from: .pendingCreate, to: .failed))
        XCTAssertTrue(stateMachine.canTransition(from: .pendingCreate, to: .serverDenied))
    }

    func testServerDeniedCanOnlyBecomeLocalOnlyOrTombstoned() {
        XCTAssertTrue(stateMachine.canTransition(from: .serverDenied, to: .localOnly))
        XCTAssertTrue(stateMachine.canTransition(from: .serverDenied, to: .tombstoned))
        XCTAssertFalse(stateMachine.canTransition(from: .serverDenied, to: .synced))
    }

    func testTombstonedIsTerminal() {
        for state in SyncState.allCases where state != .tombstoned {
            XCTAssertFalse(stateMachine.canTransition(from: .tombstoned, to: state))
        }
    }
}

final class DeferredSaveLifecycleStateMachineTests: XCTestCase {
    private let stateMachine = DeferredSaveLifecycleStateMachine()

    func testOptimisticSaveCanConfirmOrEnterRecoverableFailure() {
        XCTAssertTrue(stateMachine.canTransition(from: .pending, to: .optimisticallyCompleted))
        XCTAssertTrue(stateMachine.canTransition(from: .optimisticallyCompleted, to: .confirmed))
        XCTAssertTrue(stateMachine.canTransition(from: .optimisticallyCompleted, to: .failed))
        XCTAssertTrue(stateMachine.canTransition(from: .failed, to: .retrying))
        XCTAssertTrue(stateMachine.canTransition(from: .retrying, to: .confirmed))
    }

    func testPermanentFailureStopsAutomaticProgressButAllowsExplicitRetry() {
        XCTAssertTrue(stateMachine.canTransition(from: .failed, to: .permanentlyFailed))
        XCTAssertFalse(stateMachine.canTransition(from: .permanentlyFailed, to: .confirmed))
        XCTAssertTrue(stateMachine.canTransition(from: .permanentlyFailed, to: .retrying))
    }

    func testConfirmedSaveIsTerminal() {
        for state in DeferredSaveLifecycleState.allCases where state != .confirmed {
            XCTAssertFalse(stateMachine.canTransition(from: .confirmed, to: state))
        }
    }
}

final class DeferredSaveRecoveryPresentationTests: XCTestCase {
    func testPendingDurableWriteUsesHonestOptimisticCopy() throws {
        let presentation = try XCTUnwrap(
            DeferredSaveRecoveryPresentation(
                syncStates: [.synced, .pendingCreate],
                isRetrying: false
            )
        )

        XCTAssertEqual(presentation.state, .optimisticallyCompleted)
        XCTAssertEqual(presentation.title, "Saved — syncing…")
        XCTAssertNil(presentation.retryTitle)
    }

    func testRecoverableFailureOffersRetryAndKeepsLocalCopy() throws {
        let presentation = try XCTUnwrap(
            DeferredSaveRecoveryPresentation(
                syncStates: [.failed],
                isRetrying: false
            )
        )

        XCTAssertEqual(presentation.state, .failed)
        XCTAssertEqual(presentation.title, "Saved here, not synced")
        XCTAssertTrue(presentation.message.contains("safe on this phone"))
        XCTAssertEqual(presentation.retryTitle, "Retry")
    }

    func testPermanentFailureTakesPriorityAcrossOutstandingOperations() throws {
        let presentation = try XCTUnwrap(
            DeferredSaveRecoveryPresentation(
                syncStates: [.pendingUpdate, .failed, .serverDenied],
                isRetrying: false
            )
        )

        XCTAssertEqual(presentation.state, .permanentlyFailed)
        XCTAssertEqual(presentation.operationCount, 3)
        XCTAssertEqual(presentation.retryTitle, "Try again")
    }

    func testRetryingOverridesFailurePresentation() throws {
        let presentation = try XCTUnwrap(
            DeferredSaveRecoveryPresentation(
                syncStates: [.failed],
                isRetrying: true
            )
        )

        XCTAssertEqual(presentation.state, .retrying)
        XCTAssertNil(presentation.retryTitle)
    }

    func testNoBannerRemainsAfterConfirmation() {
        XCTAssertNil(
            DeferredSaveRecoveryPresentation(
                syncStates: [.synced, .tombstoned],
                isRetrying: false
            )
        )
    }
}

final class SaveSyncFeedbackTests: XCTestCase {
    func testSyncedSaveUsesSuccessPresentation() {
        let feedback = SaveSyncFeedback(syncState: .synced, canSignIn: false)

        XCTAssertEqual(feedback.title, "saved to your map")
        XCTAssertEqual(feedback.systemImage, "checkmark")
        XCTAssertFalse(feedback.usesWarningHaptic)
        XCTAssertEqual(feedback.mapMessage(successMessage: "Added to your map."), "Added to your map.")
    }

    func testFailedSaveClearlySaysRemoteSyncFailed() {
        let feedback = SaveSyncFeedback(syncState: .failed, canSignIn: false)

        XCTAssertEqual(feedback.title, "sync failed")
        XCTAssertEqual(feedback.message, "Saved on this phone. We'll retry automatically.")
        XCTAssertEqual(feedback.systemImage, "exclamationmark.triangle")
        XCTAssertTrue(feedback.usesWarningHaptic)
        XCTAssertEqual(feedback.dismissDelayNanoseconds, 5_000_000_000)
        XCTAssertEqual(
            feedback.mapMessage(successMessage: "Added to your map."),
            "Saved on this phone, but sync failed. We'll retry."
        )
    }

    func testQueuedSaveDistinguishesLocalPersistenceFromRemoteSync() {
        let feedback = SaveSyncFeedback(syncState: .pendingCreate, canSignIn: false)

        XCTAssertEqual(feedback.title, "saved")
        XCTAssertEqual(feedback.message, "Syncing in the background.")
        XCTAssertFalse(feedback.usesWarningHaptic)
        XCTAssertEqual(feedback.mapMessage(successMessage: "Visit saved."), "Visit saved. Syncing in the background.")
    }

    func testSignedOutLocalSaveOffersSignInWithoutClaimingSync() {
        let feedback = SaveSyncFeedback(syncState: .localOnly, canSignIn: true)

        XCTAssertEqual(feedback.title, "saved on this phone")
        XCTAssertEqual(feedback.message, "Sign in to back it up.")
        XCTAssertTrue(feedback.canSignIn)
        XCTAssertFalse(feedback.usesWarningHaptic)
    }
}

final class PlaceAttributeValuePresentationTests: XCTestCase {
    func testPersonalLabelArrayIsPresentedWithoutDependingOnGenericValueType() {
        XCTAssertEqual(
            PlaceAttributeValuePresentation.strings(from: #"["date night","  joe rec  ",""]"#),
            ["date night", "joe rec"]
        )
    }

    func testRestaurantCuisineStringIsPresented() {
        XCTAssertEqual(PlaceAttributeValuePresentation.strings(from: #""Thai""#), ["Thai"])
    }

    func testInvalidAttributeJSONIsIgnored() {
        XCTAssertTrue(PlaceAttributeValuePresentation.strings(from: "not-json").isEmpty)
    }
}
