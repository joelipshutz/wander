import XCTest
@testable import Wander

final class SaveStreakCalculatorTests: XCTestCase {
    func testPresentationWaitsForSaveSheetAndDailyTakeoverRequiresConfirmation() {
        let celebration = SaveStreakCelebration(
            kind: .dailyTakeover,
            placeName: "Maru Coffee",
            placeDetail: "Los Angeles · CA",
            status: .been,
            streakCount: 1,
            saveDate: .now
        )

        XCTAssertFalse(
            SaveStreakPresentationPolicy.canPresent(
                celebration: celebration,
                isSaveFlowPresented: true
            )
        )
        XCTAssertTrue(
            SaveStreakPresentationPolicy.canPresent(
                celebration: celebration,
                isSaveFlowPresented: false
            )
        )
        XCTAssertNil(
            SaveStreakPresentationPolicy.autoDismissDelay(for: .dailyTakeover)
        )
        XCTAssertNotNil(
            SaveStreakPresentationPolicy.autoDismissDelay(for: .sameDayConfetti)
        )
    }

    func testDebugMockupResolverDefaultsToTakeover() {
        XCTAssertNil(SaveStreakMockupPage.resolved(from: ["Wander"]))
        XCTAssertEqual(
            SaveStreakMockupPage.resolved(from: ["Wander", "-WanderStreakMockup"]),
            .takeover
        )
        XCTAssertEqual(
            SaveStreakMockupPage.resolved(
                from: ["Wander", "-WanderStreakMockup", "profileRow"]
            ),
            .profileRow
        )
    }

    func testCelebrationPresentationUsesNumericDayStreakLanguage() {
        XCTAssertEqual(
            SaveStreakCelebrationPresentation.visualCount(for: 4),
            "4"
        )
        XCTAssertEqual(
            SaveStreakCelebrationPresentation.accessibilityTitle(for: 4),
            "4 day streak"
        )
        XCTAssertEqual(
            SaveStreakCelebrationPresentation.accessibilityTitle(for: 1),
            "1 day streak"
        )
    }

    func testCelebrationPresentationBuildsSevenDayCardEndingToday() {
        let calendar = testCalendar
        let days = SaveStreakCelebrationPresentation.weekdays(
            streakCount: 4,
            endingOn: date(2026, 7, 25, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.isCovered), [false, false, false, true, true, true, true])
        XCTAssertEqual(days.filter(\.isToday).count, 1)
        XCTAssertTrue(days.last?.isToday == true)
        XCTAssertTrue(days.last?.isCovered == true)
    }

    func testCelebrationPresentationCapsVisibleCoverageAtSevenDays() {
        let days = SaveStreakCelebrationPresentation.weekdays(
            streakCount: 1_000,
            endingOn: date(2026, 7, 25, hour: 12),
            calendar: testCalendar
        )

        XCTAssertEqual(days.filter(\.isCovered).count, 7)
    }

    func testSummaryDeduplicatesSameDaySavesAndKeepsYesterdayRunActive() throws {
        let calendar = testCalendar
        let dates = [
            date(2026, 7, 19, hour: 9),
            date(2026, 7, 20, hour: 8),
            date(2026, 7, 20, hour: 19),
            date(2026, 7, 21, hour: 12)
        ]

        let summary = SaveStreakCalculator.summary(
            saveDates: dates,
            now: date(2026, 7, 22, hour: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.currentCount, 3)
        XCTAssertEqual(summary.bestCount, 3)
        XCTAssertFalse(summary.isTodayCovered)
        XCTAssertEqual(summary.recentDayCoverage.filter { $0 }.count, 3)
    }

    func testSummaryBreaksCurrentRunAfterAFullMissedDayButPreservesBest() {
        let calendar = testCalendar
        let dates = [
            date(2026, 7, 1, hour: 9),
            date(2026, 7, 2, hour: 9),
            date(2026, 7, 3, hour: 9),
            date(2026, 7, 9, hour: 9)
        ]

        let summary = SaveStreakCalculator.summary(
            saveDates: dates,
            now: date(2026, 7, 11, hour: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.currentCount, 0)
        XCTAssertEqual(summary.bestCount, 3)
        XCTAssertFalse(summary.isTodayCovered)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        testCalendar.date(from: DateComponents(
            timeZone: testCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

@MainActor
final class SaveStreakStoreTests: XCTestCase {
    func testSaveFlowPresentationRemainsActiveUntilHostDismissalCompletes() {
        let store = WanderStore(fixtures: .empty())

        XCTAssertFalse(store.isSaveFlowPresented)
        store.saveFlowDidPresent(.addSheet)
        XCTAssertTrue(store.isSaveFlowPresented)
        store.saveFlowDidPresent(.saveSheet)
        store.saveFlowDidDismiss(.saveSheet)
        XCTAssertTrue(store.isSaveFlowPresented)
        store.saveFlowDidDismiss(.addSheet)
        XCTAssertFalse(store.isSaveFlowPresented)
    }

    func testNewBeenAndWannaSavesAdvanceAtMostOncePerLocalDay() throws {
        let store = WanderStore(fixtures: .empty())

        _ = store.saveCandidate(
            candidate(id: "maru", name: "Maru Coffee"),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let firstCelebration = try XCTUnwrap(store.saveStreakCelebration)
        XCTAssertEqual(firstCelebration.kind, .dailyTakeover)
        XCTAssertEqual(firstCelebration.placeName, "Maru Coffee")
        XCTAssertEqual(firstCelebration.status, .been)
        XCTAssertEqual(firstCelebration.streakCount, 1)
        XCTAssertEqual(store.saveStreakSummary.currentCount, 1)
        XCTAssertTrue(store.saveStreakSummary.isTodayCovered)

        store.dismissSaveStreakCelebration(id: firstCelebration.id)

        _ = store.saveCandidate(
            candidate(id: "found", name: "Found Oyster"),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let sameDayCelebration = try XCTUnwrap(store.saveStreakCelebration)
        XCTAssertEqual(sameDayCelebration.kind, .sameDayConfetti)
        XCTAssertEqual(sameDayCelebration.status, .wannaGo)
        XCTAssertEqual(sameDayCelebration.streakCount, 1)
        XCTAssertEqual(store.saveStreakSummary.currentCount, 1)
    }

    func testEditingAnExistingSaveDoesNotTriggerAStreakEvent() throws {
        let store = WanderStore(fixtures: .empty())
        let place = candidate(id: "maru", name: "Maru Coffee")

        _ = store.saveCandidate(
            place,
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        let firstCelebration = try XCTUnwrap(store.saveStreakCelebration)
        store.dismissSaveStreakCelebration(id: firstCelebration.id)

        _ = store.saveCandidate(
            place,
            status: .been,
            visibility: .followers,
            note: "went today",
            sourceType: .manual
        )

        XCTAssertNil(store.saveStreakCelebration)
        XCTAssertEqual(store.saveStreakSummary.currentCount, 1)
    }

    func testStreakLedgerPersistsAndMovesFromGuestToSignedInUser() throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(
            load: { snapshot },
            save: { snapshot = $0 }
        )
        let firstStore = WanderStore(fixtures: .empty(), persistence: persistence)

        _ = firstStore.saveCandidate(
            candidate(id: "maru", name: "Maru Coffee"),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        firstStore.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
            )
        )

        XCTAssertEqual(firstStore.saveStreakSummary.currentCount, 1)
        XCTAssertNotNil(snapshot?.saveStreakDatesByUserID?["user_live"])

        let relaunchedStore = WanderStore(fixtures: .empty(), persistence: persistence)
        XCTAssertEqual(relaunchedStore.currentUser.id, "user_live")
        XCTAssertEqual(relaunchedStore.saveStreakSummary.currentCount, 1)
        XCTAssertTrue(relaunchedStore.saveStreakSummary.isTodayCovered)
        XCTAssertNil(relaunchedStore.saveStreakCelebration)
    }

    private func candidate(id: String, name: String) -> PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name,
            category: "restaurant",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.05,
            longitude: -118.25,
            confidence: 1
        )
    }
}
