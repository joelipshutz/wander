import XCTest
@preconcurrency import UserNotifications
@testable import Wander

@MainActor
final class WannaGoReminderTests: XCTestCase {
    func testStorageDateRoundTripsWithoutTimeOfDay() throws {
        let calendar = testCalendar()
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18, minute: 45))
        )

        let stored = WannaGoDate.storageString(from: date, calendar: calendar)
        let restored = try XCTUnwrap(WannaGoDate.date(fromStorageString: stored, calendar: calendar))

        XCTAssertEqual(stored, "2026-08-20")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour], from: restored),
            DateComponents(year: 2026, month: 8, day: 20, hour: 0)
        )
    }

    func testEmptyCalendarSelectionDoesNotCreateDefaultDate() {
        XCTAssertNil(
            WannaGoDate.singleDate(
                from: [],
                replacing: nil,
                calendar: testCalendar()
            )
        )
    }

    func testCalendarSelectionAddsThenReplacesOneDate() throws {
        let calendar = testCalendar()
        let firstDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let secondDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3))
        )
        let firstSelection = WannaGoDate.calendarSelection(for: firstDate, calendar: calendar)
        let selectedFirstDate = try XCTUnwrap(
            WannaGoDate.singleDate(
                from: firstSelection,
                replacing: nil,
                calendar: calendar
            )
        )
        let replacementSelection = firstSelection.union(
            WannaGoDate.calendarSelection(for: secondDate, calendar: calendar)
        )

        let selectedSecondDate = try XCTUnwrap(
            WannaGoDate.singleDate(
                from: replacementSelection,
                replacing: selectedFirstDate,
                calendar: calendar
            )
        )

        XCTAssertEqual(selectedFirstDate, calendar.startOfDay(for: firstDate))
        XCTAssertEqual(selectedSecondDate, calendar.startOfDay(for: secondDate))
    }

    func testCalendarSelectionReplacementIgnoresCalendarMetadataDifferences() throws {
        let calendar = testCalendar()
        let currentDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let selection = Set([
            DateComponents(year: 2026, month: 8, day: 20),
            DateComponents(year: 2026, month: 9, day: 3)
        ])

        let replacement = try XCTUnwrap(
            WannaGoDate.singleDate(
                from: selection,
                replacing: currentDate,
                calendar: calendar
            )
        )

        XCTAssertEqual(WannaGoDate.storageString(from: replacement, calendar: calendar), "2026-09-03")
    }

    func testPlannerSchedulesNineAMThreeCalendarDaysBefore() throws {
        let calendar = testCalendar()
        let plannedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        let item = WannaGoReminderItem(
            userPlaceID: "up_maru",
            placeID: "place_maru",
            placeName: "Maru Coffee",
            plannedDate: plannedDate
        )

        let plan = try XCTUnwrap(
            WannaGoReminderPlanner.plan(for: item, now: now, calendar: calendar)
        )

        XCTAssertEqual(plan.identifier, "recme.wanna-go-reminder.up_maru")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate),
            DateComponents(year: 2026, month: 8, day: 17, hour: 9, minute: 0)
        )
    }

    func testPlannerSkipsReminderWhenThreeDayFireTimeAlreadyPassed() throws {
        let calendar = testCalendar()
        let plannedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 9))
        )

        XCTAssertNil(
            WannaGoReminderPlanner.plan(
                for: WannaGoReminderItem(
                    userPlaceID: "up_maru",
                    placeID: "place_maru",
                    placeName: "Maru Coffee",
                    plannedDate: plannedDate
                ),
                now: now,
                calendar: calendar
            )
        )
    }

    func testNotificationCopyPayloadAndPlaceCardRoute() throws {
        let calendar = testCalendar()
        let plannedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        let plan = try XCTUnwrap(
            WannaGoReminderPlanner.plan(
                for: WannaGoReminderItem(
                    userPlaceID: "up_maru",
                    placeID: "place_maru",
                    placeName: "Maru Coffee",
                    plannedDate: plannedDate
                ),
                now: now,
                calendar: calendar
            )
        )

        let request = WannaGoReminderPlanner.request(
            for: plan,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let payload = try XCTUnwrap(request.content.userInfo["recme"] as? [String: Any])
        let data = try XCTUnwrap(payload["data"] as? [String: String])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

        XCTAssertEqual(request.content.title, "Wanna go reminder")
        XCTAssertEqual(request.content.body, "You wanted to try Maru Coffee on August 20, 2026.")
        XCTAssertEqual(payload["notification_type"] as? String, "wanna_go_reminder")
        XCTAssertEqual(payload["deeplink_url"] as? String, "recme://places/place_maru")
        XCTAssertEqual(data["place_id"], "place_maru")
        XCTAssertEqual(data["planned_date"], "2026-08-20")
        XCTAssertEqual(trigger.dateComponents.day, 17)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(PushNotificationManager.destination(from: request.content.userInfo), .place(id: "place_maru"))
    }

    func testPlannerRespectsThePendingNotificationLimitHeadroom() throws {
        let calendar = testCalendar()
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        let items = try (0..<65).map { index in
            WannaGoReminderItem(
                userPlaceID: "up_\(index)",
                placeID: "place_\(index)",
                placeName: "Place \(index)",
                plannedDate: try XCTUnwrap(
                    calendar.date(from: DateComponents(year: 2027, month: 1, day: 1 + index))
                )
            )
        }

        XCTAssertEqual(
            WannaGoReminderPlanner.plans(for: items, now: now, calendar: calendar).count,
            WannaGoReminderPlanner.maximumScheduledReminders
        )
    }

    func testSaveStreakPlannerSchedulesEightPMWhenActiveDayIsUncovered() throws {
        let calendar = testCalendar()
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let summary = SaveStreakSummary(
            currentCount: 4,
            bestCount: 7,
            isTodayCovered: false,
            recentDayCoverage: [true, true, false, true, true, true, false]
        )

        let plan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(for: summary, now: now, calendar: calendar)
        )

        XCTAssertEqual(plan.identifier, "recme.save-streak-reminder.daily")
        XCTAssertEqual(plan.kind, .daily)
        XCTAssertEqual(plan.streakCount, 4)
        XCTAssertEqual(plan.copyVariant, .current)
        XCTAssertEqual(plan.scheduledWeekday, "monday")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate),
            DateComponents(year: 2026, month: 8, day: 3, hour: 20, minute: 0)
        )
    }

    func testSaveStreakPlannerSkipsCoveredExpiredAndInactiveDays() throws {
        let calendar = testCalendar()
        let afternoon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let evening = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 20))
        )
        let active = SaveStreakSummary(
            currentCount: 2,
            bestCount: 2,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7)
        )
        let covered = SaveStreakSummary(
            currentCount: 2,
            bestCount: 2,
            isTodayCovered: true,
            recentDayCoverage: Array(repeating: true, count: 7)
        )

        XCTAssertNil(SaveStreakReminderPlanner.plan(for: .empty, now: afternoon, calendar: calendar))
        XCTAssertNil(SaveStreakReminderPlanner.plan(for: covered, now: afternoon, calendar: calendar))
        XCTAssertNil(SaveStreakReminderPlanner.plan(for: active, now: evening, calendar: calendar))
    }

    func testSaveStreakReminderCopyPayloadAndQuickCaptureRoute() throws {
        let calendar = testCalendar()
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let summary = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7)
        )
        let plan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(for: summary, now: now, calendar: calendar)
        )
        let request = SaveStreakReminderPlanner.request(for: plan, calendar: calendar)
        let payload = try XCTUnwrap(request.content.userInfo["recme"] as? [String: Any])
        let data = try XCTUnwrap(payload["data"] as? [String: String])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

        XCTAssertEqual(request.content.title, "Your 4-day streak is waiting")
        XCTAssertEqual(
            request.content.body,
            "Where did you go today? Check in or save a place to keep your streak."
        )
        XCTAssertEqual(payload["notification_type"] as? String, "save_streak_reminder")
        XCTAssertEqual(payload["deeplink_url"] as? String, "recme://add/here-now")
        XCTAssertEqual(data["streak_count"], "4")
        XCTAssertEqual(data["copy_variant"], "current")
        XCTAssertEqual(data["scheduled_weekday"], "monday")
        XCTAssertEqual(data["reminder_kind"], "daily")
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(PushNotificationManager.destination(from: request.content.userInfo), .quickCapture)
    }

    func testSaveStreakReminderCopyRotationIsDeterministicByWeekday() throws {
        let calendar = testCalendar()
        let summary = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7)
        )
        let expectations: [(day: Int, variant: SaveStreakReminderCopyVariant, title: String, body: String)] = [
            (2, .anythingWorthRemembering, "Anything worth remembering today?", "Save it now and keep your streak going."),
            (3, .current, "Your 4-day streak is waiting", "Where did you go today? Check in or save a place to keep your streak."),
            (4, .anythingWorthRemembering, "Anything worth remembering today?", "Save it now and keep your streak going."),
            (5, .onePlaceKeepsStreakAlive, "One place keeps the streak alive", "Check in or save somewhere before the day ends."),
            (6, .current, "Your 4-day streak is waiting", "Where did you go today? Check in or save a place to keep your streak."),
            (7, .mapHasRoom, "Your map has room for today", "Add somewhere you went or somewhere you want to go."),
            (8, .onePlaceKeepsStreakAlive, "One place keeps the streak alive", "Check in or save somewhere before the day ends.")
        ]

        for expectation in expectations {
            let now = try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        year: 2026,
                        month: 8,
                        day: expectation.day,
                        hour: 14
                    )
                )
            )
            let plan = try XCTUnwrap(
                SaveStreakReminderPlanner.plan(for: summary, now: now, calendar: calendar)
            )
            let request = SaveStreakReminderPlanner.request(for: plan, calendar: calendar)

            XCTAssertEqual(plan.copyVariant, expectation.variant)
            XCTAssertEqual(request.content.title, expectation.title)
            XCTAssertEqual(request.content.body, expectation.body)
        }
    }

    func testMatchingSameDaySaveStreakRequestCanBeKeptWithoutRescheduling() throws {
        let calendar = testCalendar()
        let summary = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7)
        )
        let monday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let tuesday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 14))
        )
        let mondayPlan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(for: summary, now: monday, calendar: calendar)
        )
        let changedCountPlan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(
                for: SaveStreakSummary(
                    currentCount: 5,
                    bestCount: 5,
                    isTodayCovered: false,
                    recentDayCoverage: Array(repeating: false, count: 7)
                ),
                now: monday,
                calendar: calendar
            )
        )
        let tuesdayPlan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(for: summary, now: tuesday, calendar: calendar)
        )
        let mondayRequest = SaveStreakReminderPlanner.request(for: mondayPlan, calendar: calendar)

        XCTAssertTrue(
            SaveStreakReminderPlanner.matches(mondayRequest, plan: mondayPlan, calendar: calendar)
        )
        XCTAssertFalse(
            SaveStreakReminderPlanner.matches(mondayRequest, plan: tuesdayPlan, calendar: calendar)
        )
        XCTAssertFalse(
            SaveStreakReminderPlanner.matches(
                mondayRequest,
                plan: changedCountPlan,
                calendar: calendar
            )
        )
    }

    func testRecoveryReminderIsScheduledProspectivelyForDayAfterOneMiss() throws {
        let calendar = testCalendar()
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let coveredToday = SaveStreakSummary(
            currentCount: 2,
            bestCount: 2,
            isTodayCovered: true,
            recentDayCoverage: Array(repeating: true, count: 7)
        )
        let plan = try XCTUnwrap(
            SaveStreakReminderPlanner.recoveryPlan(
                for: coveredToday,
                now: now,
                calendar: calendar
            )
        )
        let request = SaveStreakReminderPlanner.request(for: plan, calendar: calendar)
        let data = try XCTUnwrap(
            (request.content.userInfo["recme"] as? [String: Any])?["data"] as? [String: String]
        )

        XCTAssertEqual(plan.kind, .recovery)
        XCTAssertEqual(plan.identifier, SaveStreakReminderPlanner.recoveryNotificationIdentifier)
        XCTAssertEqual(plan.copyVariant, .recovery)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour], from: plan.fireDate),
            DateComponents(year: 2026, month: 8, day: 5, hour: 10)
        )
        XCTAssertEqual(request.content.title, "Keep your streak alive")
        XCTAssertEqual(request.content.body, "Save a place today to bring back your 2-day streak.")
        XCTAssertEqual(data["reminder_kind"], "recovery")
        XCTAssertEqual(PushNotificationManager.destination(from: request.content.userInfo), .quickCapture)
    }

    func testRecoveryReminderReconcilesToSameRequestOnceMissIsKnown() throws {
        let calendar = testCalendar()
        let firstNow = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let recoveryDayNow = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 8))
        )
        let active = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: true,
            recentDayCoverage: Array(repeating: true, count: 7)
        )
        let recoverable = SaveStreakSummary(
            currentCount: 0,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: [false, false, true, true, true, true, false],
            isRecoveryAvailable: true,
            recoverableCount: 4
        )
        let prospective = try XCTUnwrap(
            SaveStreakReminderPlanner.recoveryPlan(for: active, now: firstNow, calendar: calendar)
        )
        let current = try XCTUnwrap(
            SaveStreakReminderPlanner.recoveryPlan(for: recoverable, now: recoveryDayNow, calendar: calendar)
        )
        let request = SaveStreakReminderPlanner.request(for: prospective, calendar: calendar)

        XCTAssertEqual(prospective, current)
        XCTAssertTrue(SaveStreakReminderPlanner.matches(request, plan: current, calendar: calendar))
    }

    func testRecoveryReminderSkipsUsedEntitlementAndExpiredMorning() throws {
        let calendar = testCalendar()
        let morning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 8))
        )
        let lateMorning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 11))
        )
        let used = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: true,
            recentDayCoverage: Array(repeating: true, count: 7),
            hasRecoveryEntitlement: false
        )
        let recoverable = SaveStreakSummary(
            currentCount: 0,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7),
            isRecoveryAvailable: true,
            recoverableCount: 4
        )

        XCTAssertNil(SaveStreakReminderPlanner.recoveryPlan(for: used, now: morning, calendar: calendar))
        XCTAssertNil(SaveStreakReminderPlanner.recoveryPlan(for: recoverable, now: lateMorning, calendar: calendar))
    }

    func testSaveStreakReminderFunnelEventsContainOnlyAggregateProperties() throws {
        let calendar = testCalendar()
        let suiteName = "SaveStreakReminderAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ReminderRecordingAnalyticsClient()
        let tracker = SaveStreakReminderAnalytics(analytics: analytics, userDefaults: defaults)
        let summary = SaveStreakSummary(
            currentCount: 4,
            bestCount: 4,
            isTodayCovered: false,
            recentDayCoverage: Array(repeating: false, count: 7)
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14))
        )
        let plan = try XCTUnwrap(
            SaveStreakReminderPlanner.plan(for: summary, now: now, calendar: calendar)
        )
        let request = SaveStreakReminderPlanner.request(for: plan, calendar: calendar)
        let openedAt = plan.fireDate.addingTimeInterval(5 * 60)

        tracker.recordScheduled(plan)
        tracker.recordCancelledBySave(request: request, status: .wannaGo, streakCount: 5)
        tracker.recordOpened(userInfo: request.content.userInfo, userID: "local-user-a", now: openedAt)
        XCTAssertFalse(
            tracker.recordSaveCompletedAfterOpen(
                userID: "local-user-b",
                status: .wannaGo,
                streakCount: 5,
                now: openedAt.addingTimeInterval(9 * 60)
            )
        )
        XCTAssertTrue(
            tracker.recordSaveCompletedAfterOpen(
                userID: "local-user-a",
                status: .wannaGo,
                streakCount: 5,
                now: openedAt.addingTimeInterval(10 * 60)
            )
        )
        XCTAssertFalse(
            tracker.recordSaveCompletedAfterOpen(
                userID: "local-user-a",
                status: .wannaGo,
                streakCount: 5,
                now: openedAt.addingTimeInterval(11 * 60)
            )
        )

        XCTAssertEqual(
            analytics.events.map(\.name),
            [
                WanderAnalyticsEvents.saveStreakReminderScheduled,
                WanderAnalyticsEvents.saveStreakReminderCancelledBySave,
                WanderAnalyticsEvents.saveStreakReminderOpened,
                WanderAnalyticsEvents.saveStreakReminderCompletedSaveAfterOpen
            ]
        )
        XCTAssertEqual(analytics.events[0].properties["copy_variant"], "current")
        XCTAssertEqual(analytics.events[0].properties["scheduled_weekday"], "monday")
        XCTAssertEqual(analytics.events[0].properties["reminder_kind"], "daily")
        XCTAssertEqual(analytics.events[1].properties["status"], PlaceStatus.wannaGo.rawValue)
        XCTAssertEqual(analytics.events[3].properties["time_to_save_bucket"], "5_to_15_minutes")

        let forbiddenKeys = Set([
            "user_id", "account_id", "event_id", "place_id", "place_name",
            "note", "latitude", "longitude", "coordinates"
        ])
        for event in analytics.events {
            XCTAssertTrue(forbiddenKeys.isDisjoint(with: event.properties.keys))
            XCTAssertFalse(event.properties.values.contains("local-user-a"))
        }
    }

    func testExpiredSaveStreakReminderOpenDoesNotClaimACompletion() throws {
        let suiteName = "SaveStreakReminderExpiredAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ReminderRecordingAnalyticsClient()
        let tracker = SaveStreakReminderAnalytics(analytics: analytics, userDefaults: defaults)
        let request = SaveStreakReminderPlanner.debugRequest(for: .empty)
        let openedAt = Date(timeIntervalSince1970: 1_800_000_000)

        tracker.recordOpened(userInfo: request.content.userInfo, userID: "local-user-a", now: openedAt)
        XCTAssertFalse(
            tracker.recordSaveCompletedAfterOpen(
                userID: "local-user-a",
                status: .been,
                streakCount: 1,
                now: openedAt.addingTimeInterval(
                    SaveStreakReminderAnalytics.completionAttributionWindow + 1
                )
            )
        )
        XCTAssertEqual(
            analytics.events.map(\.name),
            [WanderAnalyticsEvents.saveStreakReminderOpened]
        )
    }

    func testPushNotificationManagerAttributesOneSaveToOneReminderOpen() throws {
        let suiteName = "SaveStreakReminderManagerAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ReminderRecordingAnalyticsClient()
        let manager = PushNotificationManager(userDefaults: defaults, analytics: analytics)
        let request = SaveStreakReminderPlanner.debugRequest(for: .empty)

        XCTAssertTrue(
            manager.handleNotificationResponse(
                userInfo: request.content.userInfo,
                userID: "local-user-a"
            )
        )
        XCTAssertFalse(
            manager.handleNotificationResponse(
                userInfo: request.content.userInfo,
                userID: "local-user-a"
            )
        )
        XCTAssertTrue(
            manager.recordSaveCompletedAfterReminderOpen(
                userID: "local-user-a",
                status: .been,
                streakCount: 1,
                savedAt: .now
            )
        )

        XCTAssertEqual(
            analytics.events.map(\.name),
            [
                WanderAnalyticsEvents.saveStreakReminderOpened,
                WanderAnalyticsEvents.saveStreakReminderCompletedSaveAfterOpen
            ]
        )
    }

    func testSaveStreakProductionReconciliationDoesNotCancelDebugReminder() {
        let identifiers = [
            SaveStreakReminderPlanner.notificationIdentifier,
            SaveStreakReminderPlanner.recoveryNotificationIdentifier,
            SaveStreakReminderPlanner.notificationIdentifierPrefix + "debug",
            WannaGoReminderPlanner.notificationIdentifierPrefix + "unrelated"
        ]

        XCTAssertEqual(
            SaveStreakReminderPlanner.productionReminderIdentifiers(in: identifiers),
            [
                SaveStreakReminderPlanner.notificationIdentifier,
                SaveStreakReminderPlanner.recoveryNotificationIdentifier
            ]
        )
    }

    func testSaveStreakReminderPreferenceIsIsolatedByAccount() {
        let suiteName = "SaveStreakReminderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = PushNotificationManager(userDefaults: defaults)

        manager.applyNotificationPreferences(.allEnabled)
        manager.configureSaveStreakReminders(for: "user_a")
        XCTAssertTrue(manager.saveStreakRemindersEnabled)

        manager.setSaveStreakRemindersEnabled(false, for: "user_a")
        XCTAssertFalse(manager.saveStreakRemindersEnabled)

        manager.configureSaveStreakReminders(for: "user_b")
        XCTAssertTrue(manager.saveStreakRemindersEnabled)

        manager.configureSaveStreakReminders(for: "user_a")
        XCTAssertFalse(manager.saveStreakRemindersEnabled)
        manager.applyNotificationPreferences(.allDisabled)
        manager.applyNotificationPreferences(.allEnabled)
        XCTAssertFalse(manager.saveStreakRemindersEnabled)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private final class ReminderRecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}
