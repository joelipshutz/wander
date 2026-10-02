import XCTest
@testable import Wander

final class WanderForegroundEntryTests: XCTestCase {
    func testColdLaunchAndInactiveOnlyInterruptionsDoNotRequestFeed() {
        var policy = WanderForegroundEntryPolicy()
        XCTAssertFalse(consume(&policy, isActive: false))
        XCTAssertFalse(consume(&policy))
        XCTAssertFalse(consume(&policy))
    }

    func testOrdinaryBackgroundReturnRequestsFeedExactlyOncePerEntry() {
        var policy = WanderForegroundEntryPolicy()
        for _ in 0..<3 {
            policy.didEnterBackground(preservingCurrentFlow: false)
            XCTAssertFalse(consume(&policy, isActive: false))
            XCTAssertTrue(consume(&policy))
            XCTAssertFalse(consume(&policy))
        }
    }

    func testForegroundEntryWaitsForAuthenticationWithoutLosingTheDefault() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertFalse(consume(&policy, isSessionValidated: false))
        XCTAssertFalse(consume(&policy, isSessionValidated: false))
        XCTAssertTrue(consume(&policy))
        XCTAssertFalse(consume(&policy))
    }

    func testExplicitDestinationBeforeActivationWinsAndDoesNotLeakIntoNextEntry() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: false)
        policy.recordExplicitNavigation()
        XCTAssertFalse(consume(&policy))

        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertTrue(consume(&policy))
    }

    func testExplicitDestinationDuringAuthenticationCannotBeOverwrittenAfterValidation() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertFalse(consume(&policy, isSessionValidated: false))
        policy.recordExplicitNavigation()
        XCTAssertFalse(consume(&policy))
    }

    func testPreviouslyRoutedNotificationCannotSuppressALaterOrdinaryEntry() {
        var policy = WanderForegroundEntryPolicy()
        let unavailableListRequest = UUID()
        policy.recordNotificationNavigation(requestID: unavailableListRequest)
        policy.didEnterBackground(preservingCurrentFlow: false)
        let hasNewDestination = policy.hasUnroutedNotification(requestID: unavailableListRequest)
        XCTAssertTrue(consume(&policy, hasExplicitDestination: hasNewDestination))
        XCTAssertFalse(policy.hasUnroutedNotification(requestID: nil))
        XCTAssertTrue(policy.hasUnroutedNotification(requestID: UUID()))
    }

    func testPendingDestinationConsumesDefaultEvenBeforeAuthenticationFinishes() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertFalse(consume(&policy, isSessionValidated: false, hasExplicitDestination: true))
        XCTAssertFalse(consume(&policy))
    }

    func testAnActiveFlowAtBackgroundKeepsItsContextEvenIfItFinishesWhileAway() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: true)
        XCTAssertFalse(consume(&policy))
        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertTrue(consume(&policy))
    }

    func testNewProtectedFlowConsumesDefaultRatherThanJumpingWhenItCloses() {
        var policy = WanderForegroundEntryPolicy()
        policy.didEnterBackground(preservingCurrentFlow: false)
        XCTAssertFalse(consume(&policy, preservingCurrentFlow: true))
        XCTAssertFalse(consume(&policy))
    }

    func testEveryExplicitRouteReplacesAFeedHandoffAwaitingDismissal() throws {
        let routes: [WanderDeepLinkRoute] = [
            .map, .quickCapture, .addSearch(query: "coffee"), .quickSearch(query: nil),
            .nearbyPlace(candidateID: "candidate"),
            .calendarReservation(reservationID: UUID().uuidString), .profileCalendar,
            .profileCalendarDate(try XCTUnwrap(WanderCalendarDate(urlValue: "2026-09-28"))),
            .sharedProfile(profileID: "profile"), .sharedPlace(placeID: "place"),
            .sharedActivity(activityID: "activity"),
            .checkInActivity(userPlaceID: "save", visitID: "visit"),
            .sharedList(listID: "list"), .listInvite(token: "invite"),
            .placePlanInvitation(token: "plan")
        ]
        for route in routes {
            var handoff = WanderDeepLinkHandoffCoordinator()
            let feedID = UUID()
            let destinationID = UUID()
            let presentation = WanderDeepLinkPresentationToken(surface: .feedProfile)
            handoff.begin(requestID: feedID, route: .feed, awaitingDismissals: [presentation])
            handoff.begin(requestID: destinationID, route: route, awaitingDismissals: [])
            XCTAssertNil(handoff.takeReadyRoute(requestID: feedID))
            XCTAssertEqual(handoff.acknowledgeDismissal(presentation), route)
            XCTAssertNil(handoff.pendingRoute)
        }
    }

    func testDirectNotificationOrTabNavigationCanCancelDelayedFeedSelection() {
        var handoff = WanderDeepLinkHandoffCoordinator()
        let feedID = UUID()
        let presentation = WanderDeepLinkPresentationToken(surface: .feedProfile)
        handoff.begin(requestID: feedID, route: .feed, awaitingDismissals: [presentation])
        XCTAssertEqual(handoff.pendingRoute, .feed)
        handoff.cancel()
        XCTAssertNil(handoff.takeReadyRoute(requestID: feedID))
        XCTAssertNil(handoff.acknowledgeDismissal(presentation))
    }

    func testExplicitRouteStillOpensAfterFeedHasAlreadyActivated() {
        var handoff = WanderDeepLinkHandoffCoordinator()
        let feedID = UUID()
        handoff.begin(requestID: feedID, route: .feed, awaitingDismissals: [])
        XCTAssertEqual(handoff.takeReadyRoute(requestID: feedID), .feed)
        let destinationID = UUID()
        handoff.begin(requestID: destinationID, route: .map, awaitingDismissals: [])
        XCTAssertEqual(handoff.takeReadyRoute(requestID: destinationID), .map)
    }

    private func consume(
        _ policy: inout WanderForegroundEntryPolicy,
        isActive: Bool = true,
        isSessionValidated: Bool = true,
        hasExplicitDestination: Bool = false,
        preservingCurrentFlow: Bool = false
    ) -> Bool {
        policy.consumeFeedEntry(
            isActive: isActive,
            isSessionValidated: isSessionValidated,
            hasExplicitDestination: hasExplicitDestination,
            preservingCurrentFlow: preservingCurrentFlow
        )
    }
}
