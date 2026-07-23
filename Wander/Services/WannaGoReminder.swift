import Foundation
@preconcurrency import UserNotifications

struct WannaGoReminderItem: Equatable, Hashable {
    let userPlaceID: String
    let placeID: String
    let placeName: String
    let plannedDate: Date
}

struct WannaGoReminderPlan: Equatable {
    let item: WannaGoReminderItem
    let identifier: String
    let fireDate: Date
}

enum WannaGoDate {
    static func normalized(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    static func storageString(
        from date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: normalized(date, calendar: calendar))
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(
        fromStorageString value: String,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { normalized($0, calendar: calendar) }
    }

    static func displayString(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .long,
                time: .omitted,
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
        )
    }
}

enum WannaGoReminderPlanner {
    static let notificationIdentifierPrefix = "recme.wanna-go-reminder."
    static let notificationType = "wanna_go_reminder"
    static let maximumScheduledReminders = 60
    static let reminderHour = 9

    static func plans(
        for items: [WannaGoReminderItem],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [WannaGoReminderPlan] {
        items.compactMap { item in
            plan(for: item, now: now, calendar: calendar)
        }
        .sorted { lhs, rhs in
            if lhs.fireDate == rhs.fireDate {
                return lhs.identifier < rhs.identifier
            }
            return lhs.fireDate < rhs.fireDate
        }
        .prefix(maximumScheduledReminders)
        .map { $0 }
    }

    static func plan(
        for item: WannaGoReminderItem,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> WannaGoReminderPlan? {
        let plannedDay = WannaGoDate.normalized(item.plannedDate, calendar: calendar)
        guard let reminderDay = calendar.date(byAdding: .day, value: -3, to: plannedDay) else {
            return nil
        }

        var fireComponents = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        fireComponents.hour = reminderHour
        fireComponents.minute = 0
        fireComponents.second = 0
        guard let fireDate = calendar.date(from: fireComponents), fireDate > now else {
            return nil
        }

        return WannaGoReminderPlan(
            item: item,
            identifier: notificationIdentifierPrefix + item.userPlaceID,
            fireDate: fireDate
        )
    }

    static func request(
        for plan: WannaGoReminderPlan,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> UNNotificationRequest {
        let plannedDateString = WannaGoDate.storageString(
            from: plan.item.plannedDate,
            calendar: calendar
        )
        let displayDate = WannaGoDate.displayString(
            for: plan.item.plannedDate,
            calendar: calendar,
            locale: locale
        )
        let encodedPlaceID = plan.item.placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? plan.item.placeID

        let content = UNMutableNotificationContent()
        content.title = "Wanna go reminder"
        content.body = "You wanted to try \(plan.item.placeName) on \(displayDate)."
        content.sound = .default
        content.userInfo = [
            "recme": [
                "event_id": "\(notificationType):\(plan.item.userPlaceID):\(plannedDateString)",
                "notification_type": notificationType,
                "deeplink_url": "recme://places/\(encodedPlaceID)",
                "data": [
                    "place_id": plan.item.placeID,
                    "user_place_id": plan.item.userPlaceID,
                    "planned_date": plannedDateString
                ]
            ]
        ]

        let triggerComponents = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: plan.fireDate
        )
        return UNNotificationRequest(
            identifier: plan.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
    }
}
