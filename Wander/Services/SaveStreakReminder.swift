import Foundation
@preconcurrency import UserNotifications

struct SaveStreakReminderPlan: Equatable {
    enum Kind: String, Equatable {
        case daily
        case recovery
    }

    let streakCount: Int
    let identifier: String
    let fireDate: Date
    let copyVariant: SaveStreakReminderCopyVariant
    let scheduledWeekday: String
    let kind: Kind
}

struct SaveStreakReminderCopy: Equatable {
    let title: String
    let body: String
}

enum SaveStreakReminderCopyVariant: String, CaseIterable, Equatable {
    case current
    case anythingWorthRemembering = "anything_worth_remembering"
    case onePlaceKeepsStreakAlive = "one_place_keeps_streak_alive"
    case mapHasRoom = "map_has_room"
    case recovery = "keep_your_streak_alive"

    func copy(streakCount: Int) -> SaveStreakReminderCopy {
        switch self {
        case .current:
            return SaveStreakReminderCopy(
                title: streakCount == 1
                    ? "Keep your streak going"
                    : "Your \(streakCount)-day streak is waiting",
                body: "Where did you go today? Check in or save a place to keep your streak."
            )
        case .anythingWorthRemembering:
            return SaveStreakReminderCopy(
                title: "Anything worth remembering today?",
                body: "Save it now and keep your streak going."
            )
        case .onePlaceKeepsStreakAlive:
            return SaveStreakReminderCopy(
                title: "One place keeps the streak alive",
                body: "Check in or save somewhere before the day ends."
            )
        case .mapHasRoom:
            return SaveStreakReminderCopy(
                title: "Your map has room for today",
                body: "Add somewhere you went or somewhere you want to go."
            )
        case .recovery:
            return SaveStreakReminderCopy(
                title: "Keep your streak alive",
                body: "Save a place today to bring back your \(streakCount)-day streak."
            )
        }
    }
}

enum SaveStreakReminderPlanner {
    static let notificationIdentifierPrefix = "recme.save-streak-reminder."
    static let notificationIdentifier = notificationIdentifierPrefix + "daily"
    static let recoveryNotificationIdentifier = notificationIdentifierPrefix + "recovery"
    static let notificationType = "save_streak_reminder"
    static let reminderHour = 20
    static let recoveryReminderHour = 10

    static func productionReminderIdentifiers(in identifiers: [String]) -> [String] {
        identifiers.filter { $0 == notificationIdentifier || $0 == recoveryNotificationIdentifier }
    }

    static func plans(
        for summary: SaveStreakSummary,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SaveStreakReminderPlan] {
        [
            plan(for: summary, now: now, calendar: calendar),
            recoveryPlan(for: summary, now: now, calendar: calendar)
        ].compactMap { $0 }
    }

    static func plan(
        for summary: SaveStreakSummary,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SaveStreakReminderPlan? {
        guard summary.currentCount > 0, !summary.isTodayCovered else {
            return nil
        }

        var fireComponents = calendar.dateComponents([.year, .month, .day], from: now)
        fireComponents.hour = reminderHour
        fireComponents.minute = 0
        fireComponents.second = 0
        guard let fireDate = calendar.date(from: fireComponents), fireDate > now else {
            return nil
        }

        let copyVariant = copyVariant(for: fireDate, calendar: calendar)
        return SaveStreakReminderPlan(
            streakCount: summary.currentCount,
            identifier: notificationIdentifier,
            fireDate: fireDate,
            copyVariant: copyVariant,
            scheduledWeekday: weekdayName(for: fireDate, calendar: calendar),
            kind: .daily
        )
    }

    static func recoveryPlan(
        for summary: SaveStreakSummary,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SaveStreakReminderPlan? {
        guard summary.hasRecoveryEntitlement else { return nil }

        let dayOffset: Int
        let streakCount: Int
        if summary.isRecoveryAvailable {
            dayOffset = 0
            streakCount = summary.recoverableCount
        } else if summary.currentCount >= SaveStreakWindow.minimumRecoveryStreakCount {
            dayOffset = summary.isTodayCovered ? 2 : 1
            streakCount = summary.currentCount
        } else {
            return nil
        }

        guard let fireDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
            return nil
        }
        var fireComponents = calendar.dateComponents([.year, .month, .day], from: fireDay)
        fireComponents.hour = recoveryReminderHour
        fireComponents.minute = 0
        fireComponents.second = 0
        guard let fireDate = calendar.date(from: fireComponents), fireDate > now else {
            return nil
        }

        return SaveStreakReminderPlan(
            streakCount: streakCount,
            identifier: recoveryNotificationIdentifier,
            fireDate: fireDate,
            copyVariant: .recovery,
            scheduledWeekday: weekdayName(for: fireDate, calendar: calendar),
            kind: .recovery
        )
    }

    static func request(
        for plan: SaveStreakReminderPlan,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNNotificationRequest {
        let triggerComponents = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: plan.fireDate
        )
        return UNNotificationRequest(
            identifier: plan.identifier,
            content: content(
                streakCount: plan.streakCount,
                copyVariant: plan.copyVariant,
                scheduledWeekday: plan.scheduledWeekday,
                reminderKind: plan.kind,
                eventID: "\(notificationType):\(Int(plan.fireDate.timeIntervalSince1970))"
            ),
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
    }

    static func debugRequest(
        for summary: SaveStreakSummary,
        delay: TimeInterval = 5,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNNotificationRequest {
        let copyVariant = copyVariant(for: now, calendar: calendar)
        return UNNotificationRequest(
            identifier: notificationIdentifierPrefix + "debug",
            content: content(
                streakCount: max(summary.currentCount, 1),
                copyVariant: copyVariant,
                scheduledWeekday: weekdayName(for: now, calendar: calendar),
                reminderKind: .daily,
                eventID: "\(notificationType):debug:\(UUID().uuidString.lowercased())"
            ),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        )
    }

    private static func content(
        streakCount: Int,
        copyVariant: SaveStreakReminderCopyVariant,
        scheduledWeekday: String,
        reminderKind: SaveStreakReminderPlan.Kind,
        eventID: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let copy = copyVariant.copy(streakCount: streakCount)
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = [
            "recme": [
                "event_id": eventID,
                "notification_type": notificationType,
                "deeplink_url": "recme://add/here-now",
                "data": [
                    "streak_count": "\(streakCount)",
                    "copy_variant": copyVariant.rawValue,
                    "scheduled_weekday": scheduledWeekday,
                    "reminder_kind": reminderKind.rawValue
                ]
            ]
        ]
        return content
    }

    static func copyVariant(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SaveStreakReminderCopyVariant {
        switch calendar.component(.weekday, from: date) {
        case 1: .anythingWorthRemembering // Sunday
        case 2: .current // Monday
        case 3: .anythingWorthRemembering // Tuesday
        case 4: .onePlaceKeepsStreakAlive // Wednesday
        case 5: .current // Thursday
        case 6: .mapHasRoom // Friday
        case 7: .onePlaceKeepsStreakAlive // Saturday
        default: .current
        }
    }

    static func weekdayName(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "sunday"
        case 2: "monday"
        case 3: "tuesday"
        case 4: "wednesday"
        case 5: "thursday"
        case 6: "friday"
        case 7: "saturday"
        default: "unknown"
        }
    }

    static func matches(
        _ request: UNNotificationRequest,
        plan: SaveStreakReminderPlan,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard request.identifier == plan.identifier,
              let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let payload = request.content.userInfo["recme"] as? [String: Any],
              let data = payload["data"] as? [String: String],
              data["copy_variant"] == plan.copyVariant.rawValue,
              data["scheduled_weekday"] == plan.scheduledWeekday,
              data["streak_count"] == "\(plan.streakCount)",
              data["reminder_kind"] == plan.kind.rawValue
        else {
            return false
        }

        let planned = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: plan.fireDate
        )
        let scheduled = trigger.dateComponents
        return scheduled.year == planned.year
            && scheduled.month == planned.month
            && scheduled.day == planned.day
            && scheduled.hour == planned.hour
            && scheduled.minute == planned.minute
    }

    static func analyticsData(from userInfo: [AnyHashable: Any]) -> [String: String] {
        let payload = userInfo["recme"] as? [String: Any]
        return payload?["data"] as? [String: String] ?? [:]
    }

    static func isSaveStreakPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        let payload = userInfo["recme"] as? [String: Any]
        return payload?["notification_type"] as? String == notificationType
    }
}

struct SaveStreakReminderAnalytics {
    static let completionAttributionWindow: TimeInterval = 4 * 60 * 60

    private static let openedAtKeyPrefix = "wander.saveStreakReminderAnalytics.openedAt."
    private static let openedVariantKeyPrefix = "wander.saveStreakReminderAnalytics.openedVariant."
    private static let openedWeekdayKeyPrefix = "wander.saveStreakReminderAnalytics.openedWeekday."
    private static let openedStreakCountKeyPrefix = "wander.saveStreakReminderAnalytics.openedStreakCount."
    private static let openedKindKeyPrefix = "wander.saveStreakReminderAnalytics.openedKind."

    private let analytics: AnalyticsClient
    private let userDefaults: UserDefaults

    init(analytics: AnalyticsClient, userDefaults: UserDefaults) {
        self.analytics = analytics
        self.userDefaults = userDefaults
    }

    func recordScheduled(_ plan: SaveStreakReminderPlan) {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.saveStreakReminderScheduled,
                properties: [
                    "copy_variant": plan.copyVariant.rawValue,
                    "scheduled_weekday": plan.scheduledWeekday,
                    "scheduled_hour": "\(plan.kind == .daily ? SaveStreakReminderPlanner.reminderHour : SaveStreakReminderPlanner.recoveryReminderHour)",
                    "streak_count": "\(plan.streakCount)",
                    "reminder_kind": plan.kind.rawValue
                ]
            )
        )
    }

    func recordCancelledBySave(
        request: UNNotificationRequest,
        status: PlaceStatus,
        streakCount: Int
    ) {
        let data = SaveStreakReminderPlanner.analyticsData(from: request.content.userInfo)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.saveStreakReminderCancelledBySave,
                properties: [
                    "copy_variant": data["copy_variant"] ?? "unknown",
                    "scheduled_weekday": data["scheduled_weekday"] ?? "unknown",
                    "status": status.rawValue,
                    "streak_count": "\(streakCount)",
                    "reminder_kind": data["reminder_kind"] ?? "unknown"
                ]
            )
        )
    }

    func recordOpened(
        userInfo: [AnyHashable: Any],
        userID: String,
        now: Date = .now
    ) {
        guard SaveStreakReminderPlanner.isSaveStreakPayload(userInfo) else { return }
        let data = SaveStreakReminderPlanner.analyticsData(from: userInfo)
        let copyVariant = data["copy_variant"] ?? "unknown"
        let scheduledWeekday = data["scheduled_weekday"] ?? "unknown"
        let streakCount = Int(data["streak_count"] ?? "") ?? 0
        let reminderKind = data["reminder_kind"] ?? "unknown"

        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.saveStreakReminderOpened,
                properties: [
                    "copy_variant": copyVariant,
                    "scheduled_weekday": scheduledWeekday,
                    "streak_count": "\(streakCount)",
                    "reminder_kind": reminderKind
                ]
            )
        )

        userDefaults.set(now.timeIntervalSince1970, forKey: Self.openedAtKeyPrefix + userID)
        userDefaults.set(copyVariant, forKey: Self.openedVariantKeyPrefix + userID)
        userDefaults.set(scheduledWeekday, forKey: Self.openedWeekdayKeyPrefix + userID)
        userDefaults.set(streakCount, forKey: Self.openedStreakCountKeyPrefix + userID)
        userDefaults.set(reminderKind, forKey: Self.openedKindKeyPrefix + userID)
    }

    @discardableResult
    func recordSaveCompletedAfterOpen(
        userID: String,
        status: PlaceStatus,
        streakCount: Int,
        now: Date = .now
    ) -> Bool {
        let openedAt = userDefaults.double(forKey: Self.openedAtKeyPrefix + userID)
        guard openedAt > 0 else { return false }

        let elapsed = now.timeIntervalSince1970 - openedAt
        let copyVariant = userDefaults.string(forKey: Self.openedVariantKeyPrefix + userID) ?? "unknown"
        let scheduledWeekday = userDefaults.string(forKey: Self.openedWeekdayKeyPrefix + userID) ?? "unknown"
        let openedStreakCount = userDefaults.integer(forKey: Self.openedStreakCountKeyPrefix + userID)
        let reminderKind = userDefaults.string(forKey: Self.openedKindKeyPrefix + userID) ?? "unknown"
        clearOpenAttribution(userID: userID)

        guard elapsed >= 0, elapsed <= Self.completionAttributionWindow else {
            return false
        }

        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.saveStreakReminderCompletedSaveAfterOpen,
                properties: [
                    "copy_variant": copyVariant,
                    "scheduled_weekday": scheduledWeekday,
                    "status": status.rawValue,
                    "opened_streak_count": "\(openedStreakCount)",
                    "streak_count": "\(streakCount)",
                    "time_to_save_bucket": Self.timeToSaveBucket(elapsed),
                    "reminder_kind": reminderKind
                ]
            )
        )
        return true
    }

    func clearOpenAttribution(userID: String) {
        userDefaults.removeObject(forKey: Self.openedAtKeyPrefix + userID)
        userDefaults.removeObject(forKey: Self.openedVariantKeyPrefix + userID)
        userDefaults.removeObject(forKey: Self.openedWeekdayKeyPrefix + userID)
        userDefaults.removeObject(forKey: Self.openedStreakCountKeyPrefix + userID)
        userDefaults.removeObject(forKey: Self.openedKindKeyPrefix + userID)
    }

    private static func timeToSaveBucket(_ elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<(5 * 60): "under_5_minutes"
        case ..<(15 * 60): "5_to_15_minutes"
        case ..<(60 * 60): "15_to_60_minutes"
        default: "1_to_4_hours"
        }
    }
}
