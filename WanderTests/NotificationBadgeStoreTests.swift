import XCTest
@testable import Wander

@MainActor final class NotificationBadgeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NotificationBadgeStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCombinesPlansAndPendingCheckInsWithoutCountingDuplicatesOrOpenedPlans() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let plan = makePlan()
        let checkIn = makeCheckIn()
        let snapshot = NotificationBadgeSnapshot(userID: "recipient",
            plans: [plan, plan, makePlan(readAt: .now)], checkIns: [checkIn, checkIn, makeCheckIn(status: .accepted)])
        XCTAssertEqual(badge.count(for: snapshot), 2)
        badge.open(snapshot)
        XCTAssertEqual(badge.count(for: snapshot), 0)
        XCTAssertTrue(plan.isUnread, "Visiting Notifications must not open the plan")
        XCTAssertEqual(checkIn.status, .pending, "Visiting Notifications must not accept or decline")
    }

    func testClearedCountSurvivesReopeningRelaunchAndTemporaryEmptyRefresh() {
        let snapshot = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan()], checkIns: [makeCheckIn()])
        let badge = NotificationBadgeStore(defaults: defaults)
        badge.open(snapshot)
        badge.close()
        badge.open(NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: []))
        badge.close()
        let relaunched = NotificationBadgeStore(defaults: defaults)
        XCTAssertEqual(relaunched.count(for: snapshot), 0)
        relaunched.open(snapshot)
        XCTAssertEqual(relaunched.count(for: snapshot), 0)
    }

    func testOnlyNewPlansAndNewCheckInGenerationsRestoreTheCount() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let oldPlan = makePlan()
        badge.open(NotificationBadgeSnapshot(userID: "recipient", plans: [oldPlan], checkIns: [makeCheckIn()]))
        badge.close()
        let refreshed = NotificationBadgeSnapshot(userID: "recipient", plans: [oldPlan, makePlan()],
            checkIns: [makeCheckIn(), makeCheckIn(generation: 2)])
        XCTAssertEqual(badge.count(for: refreshed), 2)
        badge.open(refreshed)
        XCTAssertEqual(badge.count(for: refreshed), 0)
    }

    func testLateResultsClearWhileVisibleButRemainNewAfterLeaving() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let empty = NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: [])
        let loaded = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan()], checkIns: [makeCheckIn()])
        badge.open(empty)
        badge.updateVisibleInbox(loaded)
        XCTAssertEqual(badge.count(for: loaded), 0)
        badge.close()
        let late = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan()], checkIns: [makeCheckIn(generation: 2)])
        badge.updateVisibleInbox(late)
        XCTAssertEqual(badge.count(for: late), 2)
    }

    func testAccountSwitchCannotAcknowledgeAnotherAccountsNotifications() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let plan = makePlan()
        let first = NotificationBadgeSnapshot(userID: "first", plans: [plan], checkIns: [makeCheckIn()])
        let second = NotificationBadgeSnapshot(userID: "second", plans: [plan], checkIns: [makeCheckIn()])
        badge.open(first)
        badge.updateVisibleInbox(second)
        XCTAssertEqual(badge.count(for: second), 2)
        badge.close()
        let relaunched = NotificationBadgeStore(defaults: defaults)
        XCTAssertEqual(relaunched.count(for: first), 0)
        XCTAssertEqual(relaunched.count(for: second), 2)
        relaunched.open(second)
        XCTAssertEqual(relaunched.count(for: second), 0)
    }

    private func makePlan(readAt: Date? = nil) -> ReceivedPlacePlanInvitation {
        ReceivedPlacePlanInvitation(id: UUID(), invitation: PlacePlanInvitation(payload: PlacePlanInvitationPayload(
            title: "Plan", placeName: "Cafe", location: "City", senderName: "Sender", senderAvatarURL: nil,
            message: "Coffee?", connection: "Both Wanna Go", dateLabel: "Tomorrow", imagePath: ""
        ), artworkURL: URL(string: "https://example.invalid/preview.png")!), createdAt: .now, readAt: readAt)
    }

    private func makeCheckIn(generation: Int = 1, status: SharedVisitParticipantStatus = .pending) -> SharedVisitInvitation {
        SharedVisitInvitation(participantID: "participant", groupID: "group", invitationGeneration: generation,
            snapshotRevision: 1, status: status, invitedAt: .now, sourceVisitID: "source",
            sourceOwnerUserID: "owner", sourceOwnerHandle: "owner", sourceOwnerDisplayName: "Owner",
            sourceOwnerAvatarURL: nil, placeID: "place", placeName: "Cafe", category: "coffee",
            primaryCategory: "coffee_tea_sweets", subcategory: "Coffee shop", address: nil,
            locality: nil, region: nil, country: nil, latitude: 0, longitude: 0,
            sourceProvider: "manual", sourceProviderPlaceID: nil, visitedAt: .now,
            note: nil, ratingScore: nil, attributeAnswers: [], tags: [], photos: [])
    }
}
