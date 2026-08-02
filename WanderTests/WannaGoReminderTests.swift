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
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 14))
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
        XCTAssertEqual(plan.streakCount, 4)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate),
            DateComponents(year: 2026, month: 8, day: 1, hour: 20, minute: 0)
        )
    }

    func testSaveStreakPlannerSkipsCoveredExpiredAndInactiveDays() throws {
        let calendar = testCalendar()
        let afternoon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 14))
        )
        let evening = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 20))
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
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 14))
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
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(PushNotificationManager.destination(from: request.content.userInfo), .quickCapture)
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
