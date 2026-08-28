import XCTest
@testable import Wander

final class WannaPlanModelsTests: XCTestCase {
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

    func testFirstCheckInFulfillsAllActiveWannasWithoutPrompt() {
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

    func testCheckInWithoutActiveWannaNeedsNoResolution() {
        XCTAssertEqual(
            WannaCheckInResolution.afterSavingCheckIn(
                previousRelationship: PlaceRelationshipSnapshot(visitCount: 2, activeWannaCount: 0)
            ),
            .none
        )
    }

    func testPrivateCreatorForcesPrivateSharing() {
        XCTAssertEqual(
            WannaPlanVisibilityPolicy.effectiveSharing(
                requested: .feed,
                creatorIsPrivate: true,
                saveVisibility: .followers
            ),
            .privateOnly
        )
    }

    func testSelfOnlySaveForcesPrivateSharing() {
        XCTAssertEqual(
            WannaPlanVisibilityPolicy.effectiveSharing(
                requested: .feed,
                creatorIsPrivate: false,
                saveVisibility: .selfOnly
            ),
            .privateOnly
        )
    }

    func testFeedIncludesOnlyAcceptedInvitees() {
        let participants = [
            participant(id: "accepted", state: .accepted),
            participant(id: "pending", state: .pending),
            participant(id: "declined", state: .declined),
            WannaPlanParticipant(
                participantID: "creator",
                userID: "creator",
                handle: "creator",
                displayName: "Creator",
                avatarURL: nil,
                role: .creator,
                state: .accepted
            ),
        ]

        XCTAssertEqual(
            WannaPlanVisibilityPolicy.feedParticipants(from: participants).map(\.userID),
            ["accepted"]
        )
    }

    func testAcceptanceIdentifiersAreStableAndGenerationScoped() {
        let first = WannaPlanAcceptanceIdentifiers.deterministic(
            participantID: "participant-1",
            invitationGeneration: 1
        )
        let retry = WannaPlanAcceptanceIdentifiers.deterministic(
            participantID: "participant-1",
            invitationGeneration: 1
        )
        let reinvite = WannaPlanAcceptanceIdentifiers.deterministic(
            participantID: "participant-1",
            invitationGeneration: 2
        )

        XCTAssertEqual(first, retry)
        XCTAssertNotEqual(first, reinvite)
        XCTAssertNotNil(UUID(uuidString: first.operationID))
        XCTAssertNotNil(UUID(uuidString: first.wannaEventID))
        XCTAssertNotEqual(first.operationID, first.wannaEventID)
    }

    func testFeedCopyUsesEventTimeVisitedSnapshot() {
        let firstTime = context(wasVisitedBefore: false)
        let returnVisit = context(wasVisitedBefore: true)

        XCTAssertEqual(firstTime.feedTicketEyebrow, "WANTS TO GO")
        XCTAssertEqual(firstTime.feedAttributionAction, "wants to go")
        XCTAssertEqual(returnVisit.feedTicketEyebrow, "WANTS TO GO BACK")
        XCTAssertEqual(returnVisit.feedAttributionAction, "wants to go back")
    }

    func testWannaAnalyticsContractUsesOnlyAggregateProperties() {
        let allowedProperties = [
            "has_date": "true",
            "invitee_count_bucket": "2_3",
            "sharing": WannaPlanSharing.privateOnly.rawValue,
            "was_visited_before": "true",
        ]
        let sanitized = WanderAnalyticsSchema.sanitized(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.wannaPlanCreated,
                properties: allowedProperties.merging([
                    "place_name": "Private place",
                    "display_name": "Private invitee",
                    "note": "Private plan note",
                ]) { _, new in new }
            )
        )

        XCTAssertEqual(sanitized.properties, allowedProperties)
        XCTAssertEqual(sanitized.name, "wanna_plan_created")
        XCTAssertEqual(
            AnalyticsEngagementAction.wannaPlanInvitationAccepted.rawValue,
            "wanna_plan_invitation_accepted"
        )
    }

    private func participant(
        id: String,
        state: WannaPlanParticipantState
    ) -> WannaPlanParticipant {
        WannaPlanParticipant(
            participantID: "participant-\(id)",
            userID: id,
            handle: id,
            displayName: id.capitalized,
            avatarURL: nil,
            role: .invitee,
            state: state
        )
    }

    private func context(wasVisitedBefore: Bool) -> WannaPlanContext {
        WannaPlanContext(
            wannaEventID: "event",
            note: nil,
            wasVisitedBefore: wasVisitedBefore,
            plannedDate: nil,
            planID: nil,
            sharing: nil,
            status: nil,
            participants: []
        )
    }
}
