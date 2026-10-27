import XCTest
@testable import Wander

@MainActor
final class RecentPlaceListChoiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentChoiceSurvivesServerIDAssignmentButExpiresAtThirtyMinutes() {
        let choice = RecentPlaceListChoice()
        var list = makeList()
        choice.remember(list, accountID: "viewer", notificationPolicy: .silent, now: now)
        list.serverID = "server-list"
        XCTAssertEqual(choice.resolve(accountID: "viewer", lists: [list], now: now.addingTimeInterval(1_799))?.id, "server-list")
        XCTAssertEqual(choice.notificationPolicy, .silent)
        XCTAssertNil(choice.resolve(accountID: "viewer", lists: [list], now: now.addingTimeInterval(1_800)))
    }

    func testAccountSwitchClearsChoiceRatherThanRecoveringAnotherAccountsList() {
        let choice = RecentPlaceListChoice(), list = makeList()
        choice.remember(list, accountID: "viewer", notificationPolicy: .standard, now: now)
        XCTAssertNil(choice.resolve(accountID: "other", lists: [list], now: now))
        XCTAssertNil(choice.resolve(accountID: "viewer", lists: [list], now: now))
    }

    func testDeletedOrNoLongerAuthorizedListAndBackwardClockCannotQuickAdd() {
        let choice = RecentPlaceListChoice()
        var list = makeList()
        choice.remember(list, accountID: "viewer", notificationPolicy: .standard, now: now)
        XCTAssertNil(choice.resolve(accountID: "viewer", lists: [], now: now))
        choice.remember(list, accountID: "viewer", notificationPolicy: .standard, now: now)
        list.deletedAt = now
        XCTAssertNil(choice.resolve(accountID: "viewer", lists: [list], now: now))
        list.deletedAt = nil
        choice.remember(list, accountID: "viewer", notificationPolicy: .standard, now: now)
        XCTAssertNil(choice.resolve(accountID: "viewer", lists: [list], now: now.addingTimeInterval(-1)))
    }

    func testLocalAdditionCannotConfirmRemoteReplacementBeforeMembershipSyncs() {
        var list = makeList()
        var item = LocalPlaceListItem(localID: "item", listID: list.id, placeID: "canonical-place",
            addedByUserID: "viewer", syncState: .pendingCreate)
        XCTAssertEqual(RecentPlaceListMembershipState.resolve(list: list, items: [item]), .pending)
        list.serverID = "remote-list"
        XCTAssertEqual(RecentPlaceListMembershipState.resolve(list: list, items: [item]), .pending)
        item.syncStateRaw = SyncState.failed.rawValue
        XCTAssertEqual(RecentPlaceListMembershipState.resolve(list: list, items: [item]), .failed)
        item.serverID = "remote-item"
        item.syncStateRaw = SyncState.synced.rawValue
        XCTAssertEqual(RecentPlaceListMembershipState.resolve(list: list, items: [item]), .synced)
        item.deletedAt = now
        XCTAssertEqual(RecentPlaceListMembershipState.resolve(list: list, items: [item]), .missing)
    }

    func testRepeatedChangeCarriesOnlyNewMembershipOwnership() {
        XCTAssertEqual(RecentPlaceListReplacementPolicy.replaceableDestinationID(
            destinationIDs: ["B"], newlyAddedIDs: ["B"]), "B")
        XCTAssertEqual(RecentPlaceListReplacementPolicy.replaceableDestinationID(
            destinationIDs: ["C"], newlyAddedIDs: ["C"]), "C")
        XCTAssertNil(RecentPlaceListReplacementPolicy.replaceableDestinationID(
            destinationIDs: ["already-there"], newlyAddedIDs: []),
            "Changing again must not remove membership that predated the picker")
        XCTAssertNil(RecentPlaceListReplacementPolicy.replaceableDestinationID(
            destinationIDs: ["B", "C"], newlyAddedIDs: ["B", "C"]),
            "A single Change target must not choose one of several selected lists arbitrarily")
    }

    private func makeList() -> LocalPlaceList {
        LocalPlaceList(localID: "local-list", ownerUserID: "viewer", name: "Weekend", description: "")
    }
}
