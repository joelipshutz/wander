import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testCarouselAutoAdvanceIntervalIsSevenSeconds() {
        XCTAssertEqual(OnboardingCarouselTiming.defaultAutoAdvanceSeconds, 7)
    }

    func testCompletionStoreIsIsolatedPerUserAndPersistsProgress() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingCompletionStore(defaults: defaults)

        store.setNextStep(.friends, for: "user_a")
        store.markComplete(for: "user_a", needsServerCompletion: true)

        XCTAssertEqual(
            store.state(for: "user_a"),
            OnboardingLocalState(nextStep: .friends, isComplete: true, needsServerCompletion: true)
        )
        XCTAssertEqual(store.state(for: "user_b"), .fresh)

        store.clear(for: "user_a")

        XCTAssertEqual(store.state(for: "user_a"), .fresh)
    }

    func testServerCompletionRoutesStraightToMainApp() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let profile = LocalProfile(
            localID: "profile",
            serverID: "user",
            handle: "maya",
            displayName: "Maya",
            onboardingCompletedAt: Date()
        )

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: .fresh, remoteProfile: profile),
            .ready(session: session)
        )
    }

    func testIncompleteProfileResumesSavedOptionalStep() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let local = OnboardingLocalState(nextStep: .contacts, isComplete: false, needsServerCompletion: false)

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: local, remoteProfile: nil),
            .onboarding(session: session, step: .contacts)
        )
    }

    func testOptionalStepOrderIsStableForPhaseBReuse() {
        XCTAssertEqual(OnboardingStep.identity.next, .location)
        XCTAssertEqual(OnboardingStep.location.next, .contacts)
        XCTAssertEqual(OnboardingStep.contacts.next, .friends)
        XCTAssertEqual(OnboardingStep.friends.next, .notifications)
        XCTAssertNil(OnboardingStep.notifications.next)
    }

    func testLocationPermissionPolicySkipsAlreadyAuthorizedUsers() {
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .authorizedWhenInUse),
            .skip
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .authorizedAlways),
            .skip
        )
    }

    func testLocationPermissionPolicyKeepsDeniedAndRestrictedActionsUseful() {
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .notDetermined),
            .request
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .denied),
            .openSettings
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.primaryTitle(for: .denied),
            "Open Settings"
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .restricted),
            .continueWithoutAccess
        )
    }

    func testApprovedLocationValueCopyIsStable() {
        XCTAssertEqual(OnboardingLocationContent.eyebrow, "AROUND YOU")
        XCTAssertEqual(OnboardingLocationContent.title, "Find the good stuff nearby")
        XCTAssertEqual(
            OnboardingLocationContent.privacyMessage,
            "Your location is never shown to friends."
        )
        XCTAssertEqual(OnboardingLocationContent.selectedPlaceName, "Circuit Coffee")
    }

    func testLocationPreviewUsesNativeMapPinsAndSelectedPlaceCard() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Onboarding/OnboardingLocationMapPreview.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Map(position: $position"))
        XCTAssertTrue(source.contains("OnboardingLocationMapPin(pin: pin)"))
        XCTAssertTrue(source.contains("OnboardingLocationSelectedPlaceCard()"))
        XCTAssertTrue(source.contains("isSelected: true"))
    }
}
