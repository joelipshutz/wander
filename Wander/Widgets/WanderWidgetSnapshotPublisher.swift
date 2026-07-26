import Foundation
import WidgetKit

@MainActor
enum WanderWidgetSnapshotPublisher {
    static func publish(
        store: WanderStore,
        isAvailable: Bool,
        now: Date = .now,
        allowFreshnessAdvance: Bool = true,
        snapshotStore: WanderCalendarWidgetSnapshotStore = WanderCalendarWidgetSnapshotStore()
    ) {
        guard isAvailable else {
            clear(snapshotStore: snapshotStore)
            return
        }

        let calendar = WanderWidgetCalendar.gregorian()

        guard let currentMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)
        else {
            return
        }

        let projection = store.currentUserCalendarProjection
        let monthDates = [previousMonth, currentMonth, nextMonth]
        let months = monthDates.map { month in
            makeMonthSnapshot(
                ownerID: store.currentUser.id,
                userPlaces: projection.userPlaces,
                visits: projection.visits,
                places: projection.places,
                month: month,
                calendar: calendar
            )
        }
        let snapshot = WanderCalendarWidgetSnapshot(
            generatedAt: now,
            timeZoneIdentifier: calendar.timeZone.identifier,
            firstWeekday: calendar.firstWeekday,
            weekdaySymbols: WanderWidgetCalendar.rotatedWeekdaySymbols(calendar: calendar),
            previousMonth: months[0],
            currentMonth: months[1],
            nextMonth: months[2]
        )

        do {
            if try snapshotStore.save(
                snapshot,
                allowFreshnessAdvance: allowFreshnessAdvance
            ) {
                WidgetCenter.shared.reloadTimelines(
                    ofKind: WanderWidgetConstants.activityCalendarKind
                )
            }
        } catch {
            #if DEBUG
            WanderDebugLog.sync.error(
                "widget snapshot publish failed error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    static func clear(
        snapshotStore: WanderCalendarWidgetSnapshotStore = WanderCalendarWidgetSnapshotStore()
    ) {
        do {
            _ = try snapshotStore.remove()
            WidgetCenter.shared.reloadTimelines(
                ofKind: WanderWidgetConstants.activityCalendarKind
            )
        } catch {
            #if DEBUG
            WanderDebugLog.sync.error(
                "widget snapshot clear failed error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    private static func makeMonthSnapshot(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        month: Date,
        calendar: Calendar
    ) -> WanderCalendarMonthSnapshot {
        let insights = ProfileInsightsPresenter.present(
            ownerID: ownerID,
            userPlaces: userPlaces,
            visits: visits,
            places: places,
            month: month,
            calendar: calendar
        )
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? 1
        let monthNumber = components.month ?? 1
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = insights.monthDaySummaries.values.compactMap { summary -> WanderCalendarDaySnapshot? in
            guard summary.visitCount > 0 else { return nil }
            return WanderCalendarDaySnapshot(
                dayNumber: calendar.component(.day, from: summary.date),
                beenCount: summary.visitCount,
                wannaCount: 0
            )
        }

        return WanderCalendarMonthSnapshot(
            year: year,
            month: monthNumber,
            title: WanderWidgetCalendar.monthTitle(for: monthStart, calendar: calendar),
            leadingBlankCount: leadingBlankCount,
            dayCount: dayCount,
            days: days
        )
    }

}
