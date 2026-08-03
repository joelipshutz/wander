import Foundation
@preconcurrency import UserNotifications

struct SaveStreakReminderPlan: Equatable {
    let streakCount: Int
    let identifier: String
    let fireDate: Date
}

enum SaveStreakReminderPlanner {
    static let notificationIdentifierPrefix = "recme.save-streak-reminder."
    static let notificationIdentifier = notificationIdentifierPrefix + "daily"
    static let notificationType = "save_streak_reminder"
    static let reminderHour = 20

    static func productionReminderIdentifiers(in identifiers: [String]) -> [String] {
        identifiers.filter { $0 == notificationIdentifier }
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

        return SaveStreakReminderPlan(
            streakCount: summary.currentCount,
            identifier: notificationIdentifier,
            fireDate: fireDate
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
                eventID: "\(notificationType):\(Int(plan.fireDate.timeIntervalSince1970))"
            ),
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
    }

    static func debugRequest(
        for summary: SaveStreakSummary,
        delay: TimeInterval = 5
    ) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: notificationIdentifierPrefix + "debug",
            content: content(
                streakCount: max(summary.currentCount, 1),
                eventID: "\(notificationType):debug:\(UUID().uuidString.lowercased())"
            ),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        )
    }

    private static func content(
        streakCount: Int,
        eventID: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = streakCount == 1
            ? "Keep your streak going"
            : "Your \(streakCount)-day streak is waiting"
        content.body = "Where did you go today? Check in or save a place to keep your streak."
        content.sound = .default
        content.userInfo = [
            "recme": [
                "event_id": eventID,
                "notification_type": notificationType,
                "deeplink_url": "recme://add/here-now",
                "data": ["streak_count": "\(streakCount)"]
            ]
        ]
        return content
    }
}
