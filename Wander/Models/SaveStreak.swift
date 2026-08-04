import Foundation

enum SaveStreakWindow {
    static let dayCount = 7
    static let minimumRecoveryStreakCount = 3
    static let recoveryCooldownDayCount = 30
}

enum SaveStreakDayState: Equatable {
    case missed
    case saved
    case streakSave
}

struct SaveStreakSummary: Equatable {
    let currentCount: Int
    let bestCount: Int
    let isTodayCovered: Bool
    let recentDayCoverage: [Bool]
    let recentDayStates: [SaveStreakDayState]
    let isRecoveryAvailable: Bool
    let recoverableCount: Int
    let hasRecoveryEntitlement: Bool

    init(
        currentCount: Int,
        bestCount: Int,
        isTodayCovered: Bool,
        recentDayCoverage: [Bool],
        recentDayStates: [SaveStreakDayState] = [],
        isRecoveryAvailable: Bool = false,
        recoverableCount: Int = 0,
        hasRecoveryEntitlement: Bool = true
    ) {
        self.currentCount = currentCount
        self.bestCount = bestCount
        self.isTodayCovered = isTodayCovered
        self.recentDayCoverage = recentDayCoverage
        self.recentDayStates = recentDayStates
        self.isRecoveryAvailable = isRecoveryAvailable
        self.recoverableCount = recoverableCount
        self.hasRecoveryEntitlement = hasRecoveryEntitlement
    }

    var displayedDayStates: [SaveStreakDayState] {
        guard recentDayStates.count == recentDayCoverage.count else {
            return recentDayCoverage.map { $0 ? .saved : .missed }
        }
        return recentDayStates
    }

    static let empty = SaveStreakSummary(
        currentCount: 0,
        bestCount: 0,
        isTodayCovered: false,
        recentDayCoverage: Array(repeating: false, count: SaveStreakWindow.dayCount)
    )
}

enum SaveStreakCalculator {
    static func summary(
        saveDates: [Date],
        recoveryDates: [Date] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SaveStreakSummary {
        let today = calendar.startOfDay(for: now)
        let uniqueDays = Set(saveDates.map(calendar.startOfDay(for:))).sorted()
        let uniqueDaySet = Set(uniqueDays)
        let recoveryDaySet = Set(recoveryDates.map(calendar.startOfDay(for:)))
        let coveredDaySet = uniqueDaySet.union(recoveryDaySet)
        let isTodayCovered = uniqueDaySet.contains(today)

        var bestCount = 0
        var runningCount = 0
        var previousDay: Date?

        for day in coveredDaySet.sorted() {
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
        } else if let yesterday, coveredDaySet.contains(yesterday) {
            yesterday
        } else {
            nil
        }

        var currentCount = 0
        if var cursor = currentEndDay {
            while coveredDaySet.contains(cursor) {
                currentCount += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                    break
                }
                cursor = previous
            }
        }

        let recentDayCoverage = (-(SaveStreakWindow.dayCount - 1)...0).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return false
            }
            return uniqueDaySet.contains(day)
        }

        let recentDayStates = (-(SaveStreakWindow.dayCount - 1)...0).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return SaveStreakDayState.missed
            }
            if uniqueDaySet.contains(day) {
                return .saved
            }
            if recoveryDaySet.contains(day) {
                return .streakSave
            }
            return .missed
        }

        let hasRecoveryEntitlement = !recoveryDaySet.contains { recoveryDay in
            guard let elapsedDays = calendar.dateComponents(
                [.day],
                from: recoveryDay,
                to: today
            ).day else {
                return false
            }
            return (0..<SaveStreakWindow.recoveryCooldownDayCount).contains(elapsedDays)
        }

        var recoverableCount = 0
        if !isTodayCovered,
           let yesterday,
           !coveredDaySet.contains(yesterday),
           let dayBeforeYesterday = calendar.date(byAdding: .day, value: -1, to: yesterday) {
            var cursor = dayBeforeYesterday
            while coveredDaySet.contains(cursor) {
                recoverableCount += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                    break
                }
                cursor = previous
            }
        }
        let isRecoveryAvailable = hasRecoveryEntitlement
            && recoverableCount >= SaveStreakWindow.minimumRecoveryStreakCount

        return SaveStreakSummary(
            currentCount: currentCount,
            bestCount: bestCount,
            isTodayCovered: isTodayCovered,
            recentDayCoverage: recentDayCoverage,
            recentDayStates: recentDayStates,
            isRecoveryAvailable: isRecoveryAvailable,
            recoverableCount: isRecoveryAvailable ? recoverableCount : 0,
            hasRecoveryEntitlement: hasRecoveryEntitlement
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
    let recoveryDate: Date?

    init(
        id: UUID = UUID(),
        kind: Kind,
        placeName: String,
        placeDetail: String?,
        status: PlaceStatus,
        streakCount: Int,
        saveDate: Date,
        recoveryDate: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.placeName = placeName
        self.placeDetail = placeDetail
        self.status = status
        self.streakCount = streakCount
        self.saveDate = saveDate
        self.recoveryDate = recoveryDate
    }
}

struct SaveStreakWeekday: Equatable {
    let date: Date
    let symbol: String
    let isCovered: Bool
    let isToday: Bool
    let isRecoveryDay: Bool
}

enum SaveStreakCelebrationPresentation {
    static let helperText = "Keep it up 🔥"

    static func helperText(for celebration: SaveStreakCelebration) -> String {
        celebration.recoveryDate == nil ? helperText : "Streak saved 🔥"
    }

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
        recoveryDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [SaveStreakWeekday] {
        let endDay = calendar.startOfDay(for: saveDate)
        let coveredDayCount = min(max(streakCount, 1), SaveStreakWindow.dayCount)
        let firstCoveredOffset = -(coveredDayCount - 1)
        let symbols = calendar.veryShortWeekdaySymbols

        return (-(SaveStreakWindow.dayCount - 1)...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: endDay) else {
                return nil
            }

            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            let symbol = symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : ""

            return SaveStreakWeekday(
                date: date,
                symbol: symbol,
                isCovered: offset >= firstCoveredOffset,
                isToday: offset == 0,
                isRecoveryDay: recoveryDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            )
        }
    }
}

enum SaveStreakPresentationPolicy {
    static let postSaveSheetDelay = Duration.milliseconds(140)

    static func canPresent(
        celebration: SaveStreakCelebration?,
        isSaveFlowPresented: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let celebration, !isSaveFlowPresented else { return false }
        return !isExpired(celebration, now: now, calendar: calendar)
    }

    static func isExpired(
        _ celebration: SaveStreakCelebration,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(celebration.saveDate, inSameDayAs: now)
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
