import XCTest
@testable import Wander

final class WannaPlanModelsTests: XCTestCase {
    func testMockupLaunchArgumentResolvesRequestedPage() {
        XCTAssertEqual(
            WannaGoWithMockupPage.resolved(
                from: ["Wander", "-WanderWannaGoWithMockup", "plan"],
                environment: [:]
            ),
            .plan
        )
    }

    func testMockupEnvironmentResolvesRequestedPage() {
        XCTAssertEqual(
            WannaGoWithMockupPage.resolved(
                from: ["Wander"],
                environment: ["WANDER_WANNA_GO_WITH_MOCKUP": "invitation"]
            ),
            .invitation
        )
    }

    func testMockupResolverIsInactiveWithoutExplicitConfiguration() {
        XCTAssertNil(
            WannaGoWithMockupPage.resolved(from: ["Wander"], environment: [:])
        )
    }

    func testRelationshipCanBeBeenAndWannaAtTheSameTime() {
        let relationship = PlaceRelationshipSnapshot(visitCount: 2, activeWannaCount: 1)

        XCTAssertTrue(relationship.matches(.been))
        XCTAssertTrue(relationship.matches(.wannaGo))
    }

    func testRelationshipClampsInvalidCounts() {
        let relationship = PlaceRelationshipSnapshot(visitCount: -2, activeWannaCount: -1)

        XCTAssertEqual(relationship.visitCount, 0)
        XCTAssertEqual(relationship.activeWannaCount, 0)
    }

    func testFirstCheckInFulfillsWannaWithoutPrompt() {
        let relationship = PlaceRelationshipSnapshot(visitCount: 0, activeWannaCount: 2)

        XCTAssertEqual(
            WannaCheckInResolution.afterSavingCheckIn(previousRelationship: relationship),
            .fulfillAfterFirstVisit
        )
    }

    func testRepeatCheckInDefaultsToKeepingWanna() {
        let relationship = PlaceRelationshipSnapshot(visitCount: 1, activeWannaCount: 1)

        XCTAssertEqual(
            WannaCheckInResolution.afterSavingCheckIn(previousRelationship: relationship),
            .askAfterRepeatVisit(defaultChoice: .keep)
        )
    }

    func testStealthCreatorForcesPrivateSharing() {
        XCTAssertEqual(
            WannaPlanVisibilityProjection.effectiveSharing(
                requested: .feed,
                creatorIsStealth: true,
                saveVisibility: .followers
            ),
            .privateOnly
        )
    }

    func testSelfOnlySaveForcesPrivateSharing() {
        XCTAssertEqual(
            WannaPlanVisibilityProjection.effectiveSharing(
                requested: .feed,
                creatorIsStealth: false,
                saveVisibility: .selfOnly
            ),
            .privateOnly
        )
    }

    func testPublicFeedOmitsPendingDeclinedAndStealthParticipants() {
        let participants = [
            WannaPlanParticipantProjection(
                id: "joe",
                displayName: "Joe",
                role: .invitee,
                state: .accepted
            ),
            WannaPlanParticipantProjection(
                id: "maia",
                displayName: "Maia",
                role: .invitee,
                state: .pending
            ),
            WannaPlanParticipantProjection(
                id: "ryan",
                displayName: "Ryan",
                role: .invitee,
                state: .accepted,
                isStealth: true
            ),
            WannaPlanParticipantProjection(
                id: "sam",
                displayName: "Sam",
                role: .invitee,
                state: .declined
            ),
        ]

        XCTAssertEqual(
            WannaPlanVisibilityProjection.feedParticipants(from: participants).map(\.id),
            ["joe"]
        )
        XCTAssertEqual(
            WannaPlanVisibilityProjection.feedCompanionCopy(from: participants),
            "Joe"
        )
    }

    func testDirectPlanKeepsPendingAndAcceptedParticipants() {
        let participants = [
            WannaPlanParticipantProjection(
                id: "joe",
                displayName: "Joe",
                role: .invitee,
                state: .accepted
            ),
            WannaPlanParticipantProjection(
                id: "maia",
                displayName: "Maia",
                role: .invitee,
                state: .pending
            ),
            WannaPlanParticipantProjection(
                id: "sam",
                displayName: "Sam",
                role: .invitee,
                state: .declined
            ),
        ]

        XCTAssertEqual(
            WannaPlanVisibilityProjection.directParticipants(from: participants).map(\.id),
            ["joe", "maia"]
        )
    }
}
