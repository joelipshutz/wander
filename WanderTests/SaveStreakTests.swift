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
        XCTAssertEqual(
            SaveStreakPresentationPolicy.autoDismissDelay(for: .sameDayConfetti),
            .milliseconds(2_250)
        )
        XCTAssertLessThan(
            SaveStreakConfettiMotion.sameDayPop.latestEndTime,
            Double(SaveStreakPresentationPolicy.sameDayConfettiAutoDismissMilliseconds) / 1_000
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

    func testWelcomeConfettiUsesApprovedSlowerLongerRainRecipe() throws {
        let motion = SaveStreakConfettiMotion.welcome

        XCTAssertEqual(motion.pieceCount, 80)
        XCTAssertEqual(motion.travelScale, 1, accuracy: 0.001)
        XCTAssertEqual(motion.speedScale, 0.70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(motion.arrivalWindow), 1, accuracy: 0.001)
        XCTAssertEqual(motion.delay(for: 0), 0, accuracy: 0.001)
        XCTAssertEqual(motion.delay(for: 79), 1, accuracy: 0.001)
        XCTAssertEqual(motion.travelDuration(for: 4), 1.63 / 0.70, accuracy: 0.001)
        XCTAssertEqual(motion.latestEndTime, 1.63 / 0.70 + 1, accuracy: 0.001)
    }

    func testSameDayConfettiPopUsesFullerFollowThroughRecipe() {
        let motion = SaveStreakConfettiMotion.sameDayPop

        XCTAssertEqual(motion.pieceCount, 42)
        XCTAssertEqual(motion.travelScale, 0.72, accuracy: 0.001)
        XCTAssertEqual(motion.speedScale, 0.92, accuracy: 0.001)
        XCTAssertNil(motion.arrivalWindow)
        XCTAssertEqual(motion.delay(for: 8), 0.28, accuracy: 0.001)
        XCTAssertEqual(motion.travelDuration(for: 4), 1.63 / 0.92, accuracy: 0.001)
        XCTAssertGreaterThan(motion.latestEndTime, 2)
        XCTAssertLessThan(motion.latestEndTime, 2.1)
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
        XCTAssertEqual(
            SaveStreakCelebrationPresentation.helperText,
            "Keep it up 🔥"
        )
    }

    func testPresentationRejectsCelebrationAfterItsLocalSaveDayEnds() {
        let calendar = testCalendar
        let celebration = SaveStreakCelebration(
            kind: .dailyTakeover,
            placeName: "Maru Coffee",
            placeDetail: nil,
            status: .been,
            streakCount: 4,
            saveDate: date(2026, 7, 25, hour: 23)
        )

        XCTAssertTrue(
            SaveStreakPresentationPolicy.canPresent(
                celebration: celebration,
                isSaveFlowPresented: false,
                now: date(2026, 7, 25, hour: 23),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            SaveStreakPresentationPolicy.canPresent(
                celebration: celebration,
                isSaveFlowPresented: false,
                now: date(2026, 7, 26, hour: 0),
                calendar: calendar
            )
        )
        XCTAssertTrue(
            SaveStreakPresentationPolicy.isExpired(
                celebration,
                now: date(2026, 7, 26, hour: 0),
                calendar: calendar
            )
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

    func testCelebrationPresentationClampsNonPositiveCountsToOne() {
        for count in [0, -1, Int.min] {
            XCTAssertEqual(SaveStreakCelebrationPresentation.visualCount(for: count), "1")
            XCTAssertEqual(
                SaveStreakCelebrationPresentation.accessibilityTitle(for: count),
                "1 day streak"
            )

            let days = SaveStreakCelebrationPresentation.weekdays(
                streakCount: count,
                endingOn: date(2026, 7, 25, hour: 12),
                calendar: testCalendar
            )
            XCTAssertEqual(days.filter(\.isCovered).count, 1)
            XCTAssertTrue(days.last?.isCovered == true)
        }
    }

    func testCelebrationWeekdaysPreserveLocalizedDatesAcrossDaylightSavingTime() throws {
        var calendar = testCalendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: 1,
            hour: 12
        )))

        let days = SaveStreakCelebrationPresentation.weekdays(
            streakCount: SaveStreakWindow.dayCount,
            endingOn: end,
            calendar: calendar
        )

        XCTAssertEqual(
            days.map { calendar.component(.day, from: $0.date) },
            [26, 27, 28, 29, 30, 31, 1]
        )
        XCTAssertEqual(days.map(\.symbol), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertTrue(
            zip(days, days.dropFirst()).allSatisfy { current, next in
                calendar.dateComponents([.day], from: current.date, to: next.date).day == 1
            }
        )
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

    func testSummaryOffersOneDayRecoveryForEstablishedStreak() {
        let summary = SaveStreakCalculator.summary(
            saveDates: [
                date(2026, 7, 1, hour: 9),
                date(2026, 7, 2, hour: 9),
                date(2026, 7, 3, hour: 9)
            ],
            now: date(2026, 7, 5, hour: 9),
            calendar: testCalendar
        )

        XCTAssertEqual(summary.currentCount, 0)
        XCTAssertTrue(summary.isRecoveryAvailable)
        XCTAssertEqual(summary.recoverableCount, 3)
        XCTAssertTrue(summary.hasRecoveryEntitlement)
    }

    func testRecoveryDayTransparentlyContinuesCalendarStreak() {
        let summary = SaveStreakCalculator.summary(
            saveDates: [
                date(2026, 7, 1, hour: 9),
                date(2026, 7, 2, hour: 9),
                date(2026, 7, 3, hour: 9),
                date(2026, 7, 5, hour: 9)
            ],
            recoveryDates: [date(2026, 7, 4, hour: 0)],
            now: date(2026, 7, 5, hour: 9),
            calendar: testCalendar
        )

        XCTAssertEqual(summary.currentCount, 5)
        XCTAssertEqual(summary.bestCount, 5)
        XCTAssertTrue(summary.isTodayCovered)
        XCTAssertEqual(summary.displayedDayStates.suffix(5), [.saved, .saved, .saved, .streakSave, .saved])
        XCTAssertFalse(summary.hasRecoveryEntitlement)
    }

    func testRecoveryRequiresTwoDaysAndExpiresAfterFollowingDay() {
        let oneDayStreak = SaveStreakCalculator.summary(
            saveDates: [date(2026, 7, 3, hour: 9)],
            now: date(2026, 7, 5, hour: 9),
            calendar: testCalendar
        )
        let twoDayStreak = SaveStreakCalculator.summary(
            saveDates: [date(2026, 7, 2, hour: 9), date(2026, 7, 3, hour: 9)],
            now: date(2026, 7, 5, hour: 9),
            calendar: testCalendar
        )
        let twoMissedDays = SaveStreakCalculator.summary(
            saveDates: [
                date(2026, 7, 1, hour: 9),
                date(2026, 7, 2, hour: 9),
                date(2026, 7, 3, hour: 9)
            ],
            now: date(2026, 7, 6, hour: 9),
            calendar: testCalendar
        )

        XCTAssertFalse(oneDayStreak.isRecoveryAvailable)
        XCTAssertTrue(twoDayStreak.isRecoveryAvailable)
        XCTAssertEqual(twoDayStreak.recoverableCount, 2)
        XCTAssertFalse(twoMissedDays.isRecoveryAvailable)
    }

    func testRecoveryEntitlementReturnsAfterRollingThirtyDayCooldown() {
        let activeStreakDates = [
            date(2026, 8, 16, hour: 9),
            date(2026, 8, 17, hour: 9),
            date(2026, 8, 18, hour: 9)
        ]
        let unavailable = SaveStreakCalculator.summary(
            saveDates: activeStreakDates,
            recoveryDates: [date(2026, 8, 1, hour: 0)],
            now: date(2026, 8, 20, hour: 9),
            calendar: testCalendar
        )
        let available = SaveStreakCalculator.summary(
            saveDates: activeStreakDates,
            recoveryDates: [date(2026, 7, 21, hour: 0)],
            now: date(2026, 8, 20, hour: 9),
            calendar: testCalendar
        )

        XCTAssertFalse(unavailable.hasRecoveryEntitlement)
        XCTAssertFalse(unavailable.isRecoveryAvailable)
        XCTAssertTrue(available.hasRecoveryEntitlement)
        XCTAssertTrue(available.isRecoveryAvailable)
    }

    func testCelebrationMarksRecoveryDateAndUsesSavedHelperText() {
        let recoveryDate = date(2026, 7, 24, hour: 0)
        let celebration = SaveStreakCelebration(
            kind: .dailyTakeover,
            placeName: "Maru Coffee",
            placeDetail: nil,
            status: .been,
            streakCount: 5,
            saveDate: date(2026, 7, 25, hour: 12),
            recoveryDate: recoveryDate
        )
        let days = SaveStreakCelebrationPresentation.weekdays(
            streakCount: celebration.streakCount,
            endingOn: celebration.saveDate,
            recoveryDate: celebration.recoveryDate,
            calendar: testCalendar
        )

        XCTAssertEqual(SaveStreakCelebrationPresentation.helperText(for: celebration), "Streak saved 🔥")
        XCTAssertEqual(days.filter(\.isRecoveryDay).map(\.date), [recoveryDate])
        XCTAssertTrue(days.first(where: \.isRecoveryDay)?.isCovered == true)
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

    func testQualifyingSaveRestoresMissedDayPersistsAndTracksAggregateEvent() throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(
            load: { snapshot },
            save: { snapshot = $0 }
        )
        let analytics = SaveStreakRecordingAnalyticsClient()
        let store = WanderStore(
            fixtures: recoveryEligibleFixtures(),
            analytics: analytics,
            persistence: persistence
        )

        XCTAssertTrue(store.saveStreakSummary.isRecoveryAvailable)
        _ = store.saveCandidate(
            candidate(id: "recovery", name: "Recovery Coffee"),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let celebration = try XCTUnwrap(store.saveStreakCelebration)
        XCTAssertNotNil(celebration.recoveryDate)
        XCTAssertEqual(store.saveStreakSummary.currentCount, 4)
        XCTAssertEqual(store.saveStreakSummary.displayedDayStates.suffix(2), [.streakSave, .saved])
        XCTAssertEqual(snapshot?.saveStreakRecoveryDatesByUserID?[store.currentUser.id]?.count, 1)

        let recoveryEvent = try XCTUnwrap(
            analytics.events.first(where: { $0.name == WanderAnalyticsEvents.saveStreakRecovered })
        )
        XCTAssertEqual(recoveryEvent.properties["recovered_streak_count"], "2")
        XCTAssertEqual(recoveryEvent.properties["recovery_cooldown_days"], "30")
        XCTAssertNil(recoveryEvent.properties["user_id"])
        XCTAssertNil(recoveryEvent.properties["place_id"])

        let relaunchedStore = WanderStore(
            fixtures: .empty(),
            persistence: persistence
        )
        XCTAssertEqual(relaunchedStore.saveStreakSummary.currentCount, 4)
        XCTAssertEqual(relaunchedStore.saveStreakSummary.displayedDayStates.suffix(2), [.streakSave, .saved])
    }

    func testRecoveryLedgerMovesFromGuestAndRemainsIsolatedByAccount() {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(
            load: { snapshot },
            save: { snapshot = $0 }
        )
        let store = WanderStore(
            fixtures: recoveryEligibleFixtures(),
            persistence: persistence
        )
        let guestUserID = store.currentUser.id

        _ = store.saveCandidate(
            candidate(id: "guest_recovery", name: "Guest Recovery Coffee"),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        XCTAssertEqual(snapshot?.saveStreakRecoveryDatesByUserID?[guestUserID]?.count, 1)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Aye", handle: "aye")
            )
        )
        XCTAssertEqual(store.saveStreakSummary.currentCount, 4)
        XCTAssertNil(snapshot?.saveStreakRecoveryDatesByUserID?[guestUserID])
        XCTAssertEqual(snapshot?.saveStreakRecoveryDatesByUserID?["user_a"]?.count, 1)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "Bee", handle: "bee")
            )
        )
        XCTAssertEqual(store.saveStreakSummary.currentCount, 0)
        XCTAssertFalse(store.saveStreakSummary.isTodayCovered)
        XCTAssertFalse(store.saveStreakSummary.isRecoveryAvailable)
        XCTAssertNil(snapshot?.saveStreakRecoveryDatesByUserID?["user_b"])

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Aye", handle: "aye")
            )
        )
        XCTAssertEqual(store.saveStreakSummary.currentCount, 4)
        XCTAssertEqual(store.saveStreakSummary.displayedDayStates.suffix(2), [.streakSave, .saved])
    }

    private func recoveryEligibleFixtures() -> WanderFixtures {
        let empty = WanderFixtures.empty()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let places = (2...3).map { offset in
            LocalPlace(
                localID: "historical_place_\(offset)",
                canonicalName: "Historical Place \(offset)",
                category: "place",
                latitude: 34.05,
                longitude: -118.25
            )
        }
        let userPlaces = zip(places, 2...3).map { place, offset in
            LocalUserPlace(
                localID: "historical_save_\(offset)",
                userID: empty.currentUser.id,
                placeID: place.id,
                status: .been,
                visibility: .followers,
                savedAt: calendar.date(byAdding: .day, value: -offset, to: today)!,
                sourceType: AddSourceType.manual.rawValue
            )
        }

        return WanderFixtures(
            currentUser: empty.currentUser,
            profiles: empty.profiles,
            places: places,
            userPlaces: userPlaces,
            placeAttributes: [],
            follows: [],
            blocks: [],
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: empty.contactProvider
        )
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

private final class SaveStreakRecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}
