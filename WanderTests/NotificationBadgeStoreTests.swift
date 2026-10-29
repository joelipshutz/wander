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

    func testOpenAndRefreshNeverAcknowledgeOffscreenRows() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let plan = makePlan()
        let checkIn = makeCheckIn()
        let snapshot = NotificationBadgeSnapshot(userID: "recipient",
            plans: [plan, plan, makePlan(readAt: .now)], checkIns: [checkIn, checkIn, makeCheckIn(status: .accepted)])
        badge.open(snapshot)
        badge.updateVisibleInbox(snapshot)
        XCTAssertEqual(badge.count(for: snapshot), 2)
        let id = "plan:\(plan.id.uuidString)"
        badge.observe(frames: [id: CGRect(x: 0, y: 800, width: 300, height: 100)],
                      viewport: viewport, userID: snapshot.userID)
        badge.close()
        XCTAssertEqual(badge.count(for: snapshot), 2, "Lazy preloading is not exposure")
        XCTAssertTrue(plan.isUnread)
        XCTAssertEqual(checkIn.status, .pending)
    }

    func testDotsRemainWhileReadingThenClearAfterScrollingPast() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let first = makePlan(), second = makePlan()
        let snapshot = NotificationBadgeSnapshot(userID: "recipient", plans: [first, second], checkIns: [])
        let id = "plan:\(first.id.uuidString)", other = "plan:\(second.id.uuidString)"
        badge.open(snapshot)
        badge.observe(frames: [id: CGRect(x: 0, y: 20, width: 300, height: 100),
                               other: CGRect(x: 0, y: 800, width: 300, height: 100)],
                      viewport: viewport, userID: "recipient")
        XCTAssertTrue(badge.isUnseen(id, in: snapshot))
        badge.observe(frames: [id: CGRect(x: 0, y: -101, width: 300, height: 100),
                               other: CGRect(x: 0, y: 680, width: 300, height: 100)],
                      viewport: viewport, userID: "recipient")
        XCTAssertFalse(badge.isUnseen(id, in: snapshot))
        XCTAssertTrue(badge.isUnseen(other, in: snapshot))
        XCTAssertEqual(badge.count(for: snapshot), 1)
    }

    func testVisibleRowsPersistOnExitButSliversAndOffscreenRowsStayNew() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let snapshot = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan(), makePlan(), makePlan()], checkIns: [])
        let ids = snapshot.notificationIDs.sorted()
        badge.open(snapshot)
        badge.observe(frames: [ids[0]: CGRect(x: 0, y: 20, width: 300, height: 100),
                               ids[1]: CGRect(x: 0, y: 490, width: 300, height: 100),
                               ids[2]: CGRect(x: 0, y: 700, width: 300, height: 100)],
                      viewport: viewport, userID: "recipient")
        badge.close()
        badge.open(NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: []))
        badge.close()
        let restored = NotificationBadgeStore(defaults: defaults)
        XCTAssertFalse(restored.isUnseen(ids[0], in: snapshot))
        XCTAssertTrue(restored.isUnseen(ids[1], in: snapshot))
        XCTAssertTrue(restored.isUnseen(ids[2], in: snapshot))
    }

    func testAccountSwitchAndClosedInboxRejectLateExposure() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let plan = makePlan()
        let first = NotificationBadgeSnapshot(userID: "first", plans: [plan], checkIns: [])
        let second = NotificationBadgeSnapshot(userID: "second", plans: [plan], checkIns: [])
        let id = first.notificationIDs.first!
        badge.open(first)
        badge.updateVisibleInbox(second)
        badge.observe(frames: [id: viewport], viewport: viewport, userID: "second")
        badge.acknowledge(id, userID: "second")
        badge.open(second)
        badge.observe(frames: [id: viewport], viewport: viewport, userID: "first")
        badge.close()
        badge.observe(frames: [id: viewport], viewport: viewport, userID: "second")
        badge.acknowledge(id, userID: "second")
        XCTAssertEqual(badge.count(for: first), 1)
        XCTAssertEqual(badge.count(for: second), 1)
    }

    func testRefreshAddsNewRowsWithoutClearingThemAndNewGenerationStaysUnread() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let original = NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: [makeCheckIn()])
        badge.open(original)
        badge.acknowledge(original.notificationIDs.first!, userID: "recipient")
        let refreshed = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan()],
                                                  checkIns: [makeCheckIn(), makeCheckIn(generation: 2)])
        badge.updateVisibleInbox(refreshed)
        XCTAssertEqual(badge.count(for: refreshed), 2)
        badge.acknowledge("not-a-current-row", userID: "recipient")
        XCTAssertEqual(badge.count(for: refreshed), 2)
    }

    func testOversizedAccessibleRowCanBeEncounteredAndLazyRemovalAcknowledgesIt() {
        let badge = NotificationBadgeStore(defaults: defaults)
        let snapshot = NotificationBadgeSnapshot(userID: "recipient", plans: [makePlan()], checkIns: [])
        let id = snapshot.notificationIDs.first!
        badge.open(snapshot)
        badge.observe(frames: [id: CGRect(x: 0, y: 0, width: 300, height: 900)], viewport: viewport, userID: "recipient")
        badge.observe(frames: [:], viewport: viewport, userID: "recipient")
        XCTAssertEqual(badge.count(for: snapshot), 0)
    }

    private var viewport: CGRect { CGRect(x: 0, y: 0, width: 320, height: 500) }

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
