import Foundation
import XCTest
@testable import Wander

@MainActor
final class RootReminderProjectionTests: XCTestCase {
    func testReminderProjectionPreservesFirstAliasLastLocalPlanAndMutableInputs() {
        let owner = LocalProfile(localID: "reminder-owner", handle: "reminder", displayName: "Fixture")
        let first = place("collision", serverID: "first-server", name: "First")
        let second = place("second-local", serverID: "collision", name: "Second")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let saves = [
            save("earlier-local", ownerID: owner.id, placeID: "collision", date: date),
            save("z-last-local", ownerID: owner.id, placeID: first.localID, date: date),
            save("a-second", ownerID: owner.id, placeID: second.localID, date: date),
            save("missing-place", ownerID: owner.id, placeID: "missing", date: date),
            save("other-owner", ownerID: "other", placeID: first.id, date: date),
            save("deleted", ownerID: owner.id, placeID: first.id, date: date),
            save("unplanned", ownerID: owner.id, placeID: first.id, date: nil),
            save("been", ownerID: owner.id, placeID: first.id, date: date)
        ]
        saves[5].deletedAt = date
        saves[7].statusRaw = PlaceStatus.been.rawValue
        let store = makeStore(owner: owner, places: [first, second], saves: saves)
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.map(\.userPlaceID), ["a-second", "z-last-local"])
        XCTAssertEqual(store.wannaGoReminderItems.last?.placeName, "First")
        XCTAssertEqual(store.wannaGoReminderItems.last?.placeID, "first-server")

        first.serverID = "changed-first-server"
        first.canonicalName = "Changed after first read"
        saves[1].plannedDate = date.addingTimeInterval(86_400)
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.last?.placeName, first.canonicalName)
        XCTAssertEqual(store.wannaGoReminderItems.last?.placeID, first.id)
        saves[1].statusRaw = PlaceStatus.been.rawValue
        saves[0].plannedDate = nil
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.map(\.userPlaceID), ["a-second"])
    }

    func testRemotePlansRemainAvailableWithoutLocalPlansAndLocalPlansWin() async {
        let owner = LocalProfile(localID: "reminder-owner", handle: "reminder", displayName: "Fixture")
        let local = place("local", serverID: "shared-route", name: "Local place")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let localSave = save("local-plan", ownerID: owner.id, placeID: local.id, date: nil)
        let store = makeStore(owner: owner, places: [local], saves: [localSave])
        let remoteShared = place("remote-shared", serverID: local.id, name: "Remote shared")
        let remoteOnly = place("remote-only", serverID: "remote-route", name: "Remote only")
        let remote = [
            VisiblePlace(id: "remote-save-shared", place: remoteShared,
                userPlace: save("remote-save-shared", ownerID: owner.id, placeID: remoteShared.id, date: date), owner: owner),
            VisiblePlace(id: "remote-save-only", place: remoteOnly,
                userPlace: save("remote-save-only", ownerID: owner.id, placeID: remoteOnly.id, date: date), owner: owner)
        ]
        await store.refreshRemoteProfileVisiblePlaces(profileID: owner.id,
            backend: WanderBackend(userPlaceRepository: ReminderProjectionRepository(places: remote)))
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.count, 2)
        localSave.plannedDate = date.addingTimeInterval(86_400)
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.first { $0.placeID == local.id }?.userPlaceID, localSave.localID)
        localSave.deletedAt = date
        XCTAssertEqual(store.wannaGoReminderItems, referenceReminders(store))
        XCTAssertEqual(store.wannaGoReminderItems.first { $0.placeID == local.id }?.userPlaceID, "remote-save-shared")
    }

    /// Use unchanged on both revisions. Measures the property observed by the
    /// root across redraws; excludes fixture creation and the reference oracle.
    func testPerformancePlannedReminderProjectionWith1500Saves() {
        let count = 1_500
        let owner = LocalProfile(localID: "reminder-perf-owner", handle: "reminder-perf", displayName: "Fixture")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let places = (0..<count).map { place("reminder-place-\($0)", serverID: "reminder-server-\($0)", name: "Fixture \($0)") }
        let saves = places.enumerated().map { index, place in
            save("reminder-save-\(index)", ownerID: owner.id,
                placeID: index.isMultiple(of: 2) ? place.localID : place.id,
                date: date.addingTimeInterval(Double(index % 31) * 86_400))
        }
        let store = makeStore(owner: owner, places: places, saves: saves)
        let expected = referenceReminders(store)
        XCTAssertEqual(expected.count, count)
        XCTAssertEqual(store.wannaGoReminderItems, expected)
        var samples: [Double] = []
        var results: [[WannaGoReminderItem]] = []
        for _ in 0..<3 {
            results.removeAll(keepingCapacity: true)
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<3 { results.append(store.wannaGoReminderItems) }
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertTrue(results.allSatisfy { $0 == expected })
        }
        let report = "REC675 planned_reminder_projection saves=1500 reads=3 samples_ms=\(samples) median_ms=\(samples.sorted()[1])"
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }

    private func referenceReminders(_ store: WanderStore) -> [WannaGoReminderItem] {
        var reminders: [String: WannaGoReminderItem] = [:]
        for row in store.userPlaces where row.userID == store.currentUser.id
            && row.status == .wannaGo && row.deletedAt == nil {
            guard let date = row.plannedDate,
                  let place = store.places.first(where: {
                      $0.id == row.placeID || $0.localID == row.placeID || $0.serverID == row.placeID
                  }) else { continue }
            let route = place.serverID ?? place.id
            reminders[route] = WannaGoReminderItem(userPlaceID: row.localID, placeID: route,
                placeName: place.canonicalName, plannedDate: date)
        }
        for visible in store.remoteVisiblePlaceCache where visible.owner.id == store.currentUser.id
            && visible.userPlace.status == .wannaGo && visible.userPlace.deletedAt == nil {
            let route = visible.place.serverID ?? visible.place.id
            guard reminders[route] == nil, let date = visible.userPlace.plannedDate else { continue }
            reminders[route] = WannaGoReminderItem(userPlaceID: visible.userPlace.id, placeID: route,
                placeName: visible.place.canonicalName, plannedDate: date)
        }
        return reminders.values.sorted {
            $0.plannedDate == $1.plannedDate ? $0.userPlaceID < $1.userPlaceID : $0.plannedDate < $1.plannedDate
        }
    }

    private func place(_ localID: String, serverID: String, name: String) -> LocalPlace {
        LocalPlace(localID: localID, serverID: serverID, canonicalName: name, category: "park",
            latitude: 34, longitude: -118)
    }

    private func save(_ id: String, ownerID: String, placeID: String, date: Date?) -> LocalUserPlace {
        LocalUserPlace(localID: id, userID: ownerID, placeID: placeID, status: .wannaGo,
            visibility: .selfOnly, plannedDate: date, sourceType: "manual")
    }

    private func makeStore(owner: LocalProfile, places: [LocalPlace], saves: [LocalUserPlace]) -> WanderStore {
        WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [owner], places: places,
            userPlaces: saves, placeAttributes: [], follows: [], blocks: [], placeLists: [],
            placeListMembers: [], placeListItems: [], contactProvider: FakeContactProvider(seededMatches: [])))
    }
}

@MainActor
private final class ReminderProjectionRepository: UserPlaceRepository {
    let places: [VisiblePlace]
    init(places: [VisiblePlace]) { self.places = places }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { places }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}
