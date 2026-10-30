import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportSaveStreakProjectionTests: XCTestCase {
    func testProjectedDatesPreserveCompleteSummaryAcrossCalendarsBoundariesAndRecovery() throws {
        let projection = ImportSaveStreakDateProjection()
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .islamicCivil] {
            for zone in ["UTC", "America/Los_Angeles", "Asia/Kathmandu"] {
                var calendar = Calendar(identifier: identifier)
                calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
                let now = Date(timeIntervalSince1970: 1_773_000_000)
                let today = calendar.startOfDay(for: now)
                let saveDates = try [-31, -30, -4, -3, -2, -2, 0, 0, 1, 2].map { offset in
                    try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
                        .addingTimeInterval(12 * 60 * 60)
                }
                let recoveryDates = try [-30, -1].map {
                    try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: today))
                }
                for reference in [today.addingTimeInterval(-0.001), today, now,
                                  today.addingTimeInterval(86_400), today.addingTimeInterval(-86_400)] {
                    XCTAssertEqual(
                        SaveStreakCalculator.summary(
                            saveDates: projection.uniqueDays(in: saveDates, calendar: calendar),
                            recoveryDates: projection.uniqueDays(in: recoveryDates, calendar: calendar),
                            now: reference, calendar: calendar),
                        SaveStreakCalculator.summary(saveDates: saveDates, recoveryDates: recoveryDates,
                            now: reference, calendar: calendar))
                }
            }
        }
    }

    func testGrowingLedgerNormalizesEachDistinctDateOnceAndResetsForCalendarChanges() throws {
        let projection = ImportSaveStreakDateProjection()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_773_000_000)
        var ledger: [Date] = []
        for index in 0..<500 {
            ledger.append(start.addingTimeInterval(Double(index)))
            let dates = ledger + ledger
            XCTAssertEqual(Set(projection.uniqueDays(in: dates, calendar: calendar)),
                Set(dates.map(calendar.startOfDay(for:))))
        }
        XCTAssertEqual(projection.normalizationCount, 500)
        _ = projection.uniqueDays(in: [], calendar: calendar)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(Set(projection.uniqueDays(in: ledger, calendar: calendar)),
            Set(ledger.map(calendar.startOfDay(for:))))
        XCTAssertEqual(projection.normalizationCount, 1_000)
    }

    func testBatchedImportsPreserveStreakLedgerRecoveryCelebrationAnalyticsAndPersistence() throws {
        let initialDay = Calendar.current.startOfDay(for: .now)
        let ordinary = StreakImportRecordingState()
        let batched = StreakImportRecordingState()
        let ordinaryStore = WanderStore(fixtures: fixture(today: initialDay), analytics: ordinary,
            persistence: ordinary.persistence)
        let batchedStore = WanderStore(fixtures: fixture(today: initialDay), analytics: batched,
            persistence: batched.persistence)

        func saveRows(_ store: WanderStore) {
            for index in 0..<30 {
                _ = store.saveImportedCandidate(candidate(index), status: .wannaGo,
                    visibility: .selfOnly, note: nil, sourceType: PlaceImportSource.googleMaps.addSourceType)
            }
            // Existing imports and Wanna→Been upgrades must not append another
            // streak entry, even inside the transaction's normalization scope.
            _ = store.saveImportedCandidate(candidate(0), status: .wannaGo,
                visibility: .selfOnly, note: nil, sourceType: PlaceImportSource.googleMaps.addSourceType)
            _ = store.saveImportedCandidate(candidate(1), status: .been,
                visibility: .selfOnly, note: nil, sourceType: PlaceImportSource.googleMaps.addSourceType)
        }
        ordinaryStore.performBatchedLocalMutations { saveRows(ordinaryStore) }
        batchedStore.performBatchedImportMutations { saveRows(batchedStore) }

        XCTAssertEqual(batchedStore.saveStreakSummary, ordinaryStore.saveStreakSummary)
        XCTAssertEqual(batchedStore.saveStreakSummary.currentCount, 4)
        let ownerID = batchedStore.currentUser.id
        let ordinaryDates = ordinaryStore.saveStreakDatesByUserID[ownerID, default: []]
        let batchedDates = batchedStore.saveStreakDatesByUserID[ownerID, default: []]
        XCTAssertEqual(batchedDates.count, 32)
        XCTAssertEqual(batchedDates.map(Calendar.current.startOfDay(for:)),
            ordinaryDates.map(Calendar.current.startOfDay(for:)))
        XCTAssertEqual(batchedStore.saveStreakRecoveryDatesByUserID, ordinaryStore.saveStreakRecoveryDatesByUserID)
        XCTAssertEqual(batchedStore.saveStreakRecoveryDatesByUserID[ownerID]?.count, 1)
        let actual = try XCTUnwrap(batchedStore.saveStreakCelebration)
        let expected = try XCTUnwrap(ordinaryStore.saveStreakCelebration)
        XCTAssertEqual(actual.kind, expected.kind)
        XCTAssertEqual(actual.placeName, expected.placeName)
        XCTAssertEqual(actual.placeDetail, expected.placeDetail)
        XCTAssertEqual(actual.status, expected.status)
        XCTAssertEqual(actual.streakCount, expected.streakCount)
        XCTAssertEqual(actual.recoveryDate, expected.recoveryDate)
        XCTAssertEqual(batched.events.map(\.name), ordinary.events.map(\.name))
        XCTAssertEqual(batched.events.map(\.properties), ordinary.events.map(\.properties))
        XCTAssertEqual(batched.saveCount, 1)
        XCTAssertEqual(ordinary.saveCount, 1)
        XCTAssertEqual(batched.snapshot?.saveStreakDatesByUserID?[ownerID], batchedDates)
        XCTAssertEqual(batched.snapshot?.saveStreakRecoveryDatesByUserID, batchedStore.saveStreakRecoveryDatesByUserID)
        XCTAssertEqual(batchedStore.userPlaces.count, ordinaryStore.userPlaces.count)
        XCTAssertEqual(batchedStore.placeVisits.count, ordinaryStore.placeVisits.count)
    }

    func testLiveModelDatesOwnersNestedScopeAndThrowRemainFresh() throws {
        let store = WanderStore(fixtures: fixture(today: Calendar.current.startOfDay(for: .now)))
        func assertLiveSummary(file: StaticString = #filePath, line: UInt = #line) {
            let dates = store.saveStreakDatesByUserID[store.currentUser.id, default: []]
                + store.userPlaces.filter { $0.userID == store.currentUser.id }.map(\.savedAt)
            XCTAssertEqual(store.saveStreakSummary, SaveStreakCalculator.summary(saveDates: dates,
                recoveryDates: store.saveStreakRecoveryDatesByUserID[store.currentUser.id, default: []]),
                file: file, line: line)
        }
        enum ExpectedFailure: Error { case requested }
        XCTAssertThrowsError(try store.performBatchedImportMutations {
            assertLiveSummary()
            store.userPlaces[0].savedAt = .now
            store.userPlaces[1].userID = "other-owner"
            assertLiveSummary()
            store.performBatchedImportMutations {
                store.userPlaces[0].savedAt = Date.now.addingTimeInterval(3 * 86_400)
                assertLiveSummary()
            }
            assertLiveSummary()
            store.apply(authState: .signedIn(AuthSession(userID: "another-account", displayName: "Fixture", handle: "fixture")))
            assertLiveSummary()
            throw ExpectedFailure.requested
        })
        assertLiveSummary()
        store.userPlaces[0].savedAt = Date.now.addingTimeInterval(-60 * 86_400)
        assertLiveSummary()
    }

    private func fixture(today: Date) -> WanderFixtures {
        let empty = WanderFixtures.empty()
        let places = (0..<2).map { index in
            LocalPlace(localID: "streak-history-place-\(index)", canonicalName: "History \(index)",
                category: "park", latitude: 30 + Double(index), longitude: -110)
        }
        let saves = places.enumerated().map { index, place in
            LocalUserPlace(localID: "streak-history-save-\(index)", userID: empty.currentUser.id,
                placeID: place.id, status: .wannaGo, visibility: .selfOnly,
                savedAt: Calendar.current.date(byAdding: .day, value: -(index + 2), to: today)!,
                sourceType: "manual")
        }
        return WanderFixtures(currentUser: empty.currentUser, profiles: [empty.currentUser], places: places,
            userPlaces: saves, placeAttributes: [], follows: [], blocks: [], placeLists: [],
            placeListMembers: [], placeListItems: [], contactProvider: empty.contactProvider)
    }

    private func candidate(_ index: Int) -> PlaceCandidate {
        PlaceCandidate(id: "streak-import-\(index)", name: "Streak fixture \(index)", category: "park",
            locality: "Fixture city", region: "CA", latitude: 34 + Double(index) * 0.01, longitude: -118,
            sourceProvider: "fixture", sourceProviderPlaceID: "streak-provider-\(index)", confidence: 1)
    }
}

private final class StreakImportRecordingState: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var snapshot: WanderStoreSnapshot?
    private(set) var saveCount = 0
    var persistence: WanderStorePersistence {
        WanderStorePersistence(load: { nil }, save: { [self] value in
            snapshot = value
            saveCount += 1
        })
    }
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
