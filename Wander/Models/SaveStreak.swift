import Foundation

struct SaveStreakSummary: Equatable {
    let currentCount: Int
    let bestCount: Int
    let isTodayCovered: Bool
    let recentDayCoverage: [Bool]

    static let empty = SaveStreakSummary(
        currentCount: 0,
        bestCount: 0,
        isTodayCovered: false,
        recentDayCoverage: Array(repeating: false, count: 7)
    )
}

enum SaveStreakCalculator {
    static func summary(
        saveDates: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SaveStreakSummary {
        let today = calendar.startOfDay(for: now)
        let uniqueDays = Set(saveDates.map(calendar.startOfDay(for:))).sorted()
        let uniqueDaySet = Set(uniqueDays)
        let isTodayCovered = uniqueDaySet.contains(today)

        var bestCount = 0
        var runningCount = 0
        var previousDay: Date?

        for day in uniqueDays {
            if let previousDay,
               calendar.dateComponents([.day], from: previousDay, to: day).day == 1 {
                runningCount += 1
            } else {
                runningCount = 1
            }
            bestCount = max(bestCount, runningCount)
            previousDay = day
        }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let currentEndDay: Date? = if isTodayCovered {
            today
        } else if let yesterday, uniqueDaySet.contains(yesterday) {
            yesterday
        } else {
            nil
        }

        var currentCount = 0
        if var cursor = currentEndDay {
            while uniqueDaySet.contains(cursor) {
                currentCount += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                    break
                }
                cursor = previous
            }
        }

        let recentDayCoverage = (-6...0).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return false
            }
            return uniqueDaySet.contains(day)
        }

        return SaveStreakSummary(
            currentCount: currentCount,
            bestCount: bestCount,
            isTodayCovered: isTodayCovered,
            recentDayCoverage: recentDayCoverage
        )
    }
}

struct SaveStreakCelebration: Identifiable, Equatable {
    enum Kind: Equatable {
        case dailyTakeover
        case sameDayConfetti
    }

    let id: UUID
    let kind: Kind
    let placeName: String
    let placeDetail: String?
    let status: PlaceStatus
    let streakCount: Int
    let saveDate: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        placeName: String,
        placeDetail: String?,
        status: PlaceStatus,
        streakCount: Int,
        saveDate: Date
    ) {
        self.id = id
        self.kind = kind
        self.placeName = placeName
        self.placeDetail = placeDetail
        self.status = status
        self.streakCount = streakCount
        self.saveDate = saveDate
    }
}

struct SaveStreakWeekday: Equatable {
    let date: Date
    let symbol: String
    let isCovered: Bool
    let isToday: Bool
}

enum SaveStreakCelebrationPresentation {
    static func visualCount(for streakCount: Int) -> String {
        "\(max(streakCount, 1))"
    }

    static func accessibilityTitle(for streakCount: Int) -> String {
        let count = max(streakCount, 1)
        return "\(count) day streak"
    }

    static func weekdays(
        streakCount: Int,
        endingOn saveDate: Date,
        calendar: Calendar = .current
    ) -> [SaveStreakWeekday] {
        let endDay = calendar.startOfDay(for: saveDate)
        let coveredDayCount = min(max(streakCount, 1), 7)
        let firstCoveredOffset = -(coveredDayCount - 1)

        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: endDay) else {
                return nil
            }

            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            let symbols = calendar.veryShortWeekdaySymbols
            let symbol = symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : ""

            return SaveStreakWeekday(
                date: date,
                symbol: symbol,
                isCovered: offset >= firstCoveredOffset,
                isToday: offset == 0
            )
        }
    }
}

enum SaveStreakPresentationPolicy {
    static let postSaveSheetDelay = Duration.milliseconds(140)

    static func canPresent(
        celebration: SaveStreakCelebration?,
        isSaveFlowPresented: Bool
    ) -> Bool {
        celebration != nil && !isSaveFlowPresented
    }

    static func autoDismissDelay(
        for kind: SaveStreakCelebration.Kind
    ) -> Duration? {
        switch kind {
        case .dailyTakeover:
            nil
        case .sameDayConfetti:
            .milliseconds(720)
        }
    }
}

enum SaveFlowPresentationLayer: Hashable {
    case addSheet
    case saveSheet
}
