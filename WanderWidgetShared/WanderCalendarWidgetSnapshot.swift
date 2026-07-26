import Foundation

enum WanderWidgetCalendar {
    static func gregorian(
        reference: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = reference.timeZone
        calendar.firstWeekday = reference.firstWeekday
        calendar.minimumDaysInFirstWeek = reference.minimumDaysInFirstWeek
        return calendar
    }

    static func monthTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: date)
    }

    static func rotatedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else {
            return ["S", "M", "T", "W", "T", "F", "S"]
        }
        let start = min(max(calendar.firstWeekday - 1, 0), 6)
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
}

struct WanderCalendarTimelineSchedule: Equatable, Sendable {
    let entryDates: [Date]
    let reloadAfter: Date

    static func make(
        startingAt date: Date,
        snapshot: WanderCalendarWidgetSnapshot?,
        minimumDaysAhead: Int = 35,
        referenceCalendar: Calendar = .autoupdatingCurrent
    ) -> Self {
        let calendar = WanderWidgetCalendar.gregorian(reference: referenceCalendar)
        let compatibleSnapshot = snapshot.flatMap {
            $0.isCompatible(with: calendar) ? $0 : nil
        }
        let startOfToday = calendar.startOfDay(for: date)
        let minimumEnd = calendar.date(
            byAdding: .day,
            value: max(1, minimumDaysAhead),
            to: startOfToday
        ) ?? date.addingTimeInterval(60 * 60 * 24)
        let snapshotCoverageEnd = compatibleSnapshot.flatMap { snapshot in
            calendar.date(
                from: DateComponents(
                    year: snapshot.nextMonth.year,
                    month: snapshot.nextMonth.month,
                    day: 1
                )
            ).flatMap {
                calendar.date(byAdding: .month, value: 1, to: $0)
            }
        }
        let maximumEnd = calendar.date(byAdding: .day, value: 93, to: startOfToday)
            ?? minimumEnd
        let finalEntryDate = min(
            max(minimumEnd, snapshotCoverageEnd ?? minimumEnd),
            maximumEnd
        )

        var entryDates = [date]
        var cursor = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? date.addingTimeInterval(60 * 60 * 24)
        while cursor <= finalEntryDate {
            entryDates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor
            else {
                break
            }
            cursor = next
        }

        let reloadAfter = calendar.date(byAdding: .day, value: 1, to: entryDates.last ?? date)
            ?? (entryDates.last ?? date).addingTimeInterval(60 * 60)
        return Self(entryDates: entryDates, reloadAfter: reloadAfter)
    }
}

enum WanderWidgetActivityState: String, Codable, Equatable, Sendable {
    case none
    case been
    case wanna
    case both

    init(beenCount: Int, wannaCount: Int) {
        switch (beenCount > 0, wannaCount > 0) {
        case (false, false):
            self = .none
        case (true, false):
            self = .been
        case (false, true):
            self = .wanna
        case (true, true):
            self = .both
        }
    }
}

struct WanderCalendarDaySnapshot: Codable, Equatable, Sendable {
    let dayNumber: Int
    let beenCount: Int
    let wannaCount: Int
    let state: WanderWidgetActivityState

    init(dayNumber: Int, beenCount: Int, wannaCount: Int) {
        precondition((1...31).contains(dayNumber), "Calendar day must be between 1 and 31.")
        precondition(beenCount >= 0 && wannaCount >= 0, "Calendar activity counts cannot be negative.")

        self.dayNumber = dayNumber
        self.beenCount = beenCount
        self.wannaCount = wannaCount
        state = WanderWidgetActivityState(beenCount: beenCount, wannaCount: wannaCount)
    }

    private enum CodingKeys: String, CodingKey {
        case dayNumber
        case beenCount
        case wannaCount
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dayNumber = try container.decode(Int.self, forKey: .dayNumber)
        let beenCount = try container.decode(Int.self, forKey: .beenCount)
        let wannaCount = try container.decode(Int.self, forKey: .wannaCount)
        let state = try container.decode(WanderWidgetActivityState.self, forKey: .state)

        guard (1...31).contains(dayNumber), beenCount >= 0, wannaCount >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .dayNumber,
                in: container,
                debugDescription: "Calendar day and activity counts must be valid."
            )
        }
        guard state == WanderWidgetActivityState(beenCount: beenCount, wannaCount: wannaCount) else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Calendar activity state must match its counts."
            )
        }

        self.dayNumber = dayNumber
        self.beenCount = beenCount
        self.wannaCount = wannaCount
        self.state = state
    }
}

struct WanderCalendarMonthSnapshot: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let title: String
    let leadingBlankCount: Int
    let dayCount: Int
    let beenCount: Int
    let wannaCount: Int
    let days: [WanderCalendarDaySnapshot]

    init(
        year: Int,
        month: Int,
        title: String,
        leadingBlankCount: Int,
        dayCount: Int,
        days: [WanderCalendarDaySnapshot]
    ) {
        precondition(year > 0, "Calendar year must be positive.")
        precondition((1...12).contains(month), "Calendar month must be between 1 and 12.")
        precondition((0...6).contains(leadingBlankCount), "Leading calendar blanks must be between 0 and 6.")
        precondition((28...31).contains(dayCount), "Calendar month must contain between 28 and 31 days.")
        precondition(days.allSatisfy { $0.dayNumber <= dayCount }, "Calendar activity must fall within the month.")

        let compactDays = Self.compacted(days)
        self.year = year
        self.month = month
        self.title = title
        self.leadingBlankCount = leadingBlankCount
        self.dayCount = dayCount
        beenCount = compactDays.reduce(0) { $0 + $1.beenCount }
        wannaCount = compactDays.reduce(0) { $0 + $1.wannaCount }
        self.days = compactDays
    }

    var trailingBlankCount: Int {
        (7 - ((leadingBlankCount + dayCount) % 7)) % 7
    }

    var gridCellCount: Int {
        leadingBlankCount + dayCount + trailingBlankCount
    }

    func day(_ dayNumber: Int) -> WanderCalendarDaySnapshot? {
        days.first { $0.dayNumber == dayNumber }
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case title
        case leadingBlankCount
        case dayCount
        case beenCount
        case wannaCount
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let title = try container.decode(String.self, forKey: .title)
        let leadingBlankCount = try container.decode(Int.self, forKey: .leadingBlankCount)
        let dayCount = try container.decode(Int.self, forKey: .dayCount)
        let encodedBeenCount = try container.decode(Int.self, forKey: .beenCount)
        let encodedWannaCount = try container.decode(Int.self, forKey: .wannaCount)
        let encodedDays = try container.decode([WanderCalendarDaySnapshot].self, forKey: .days)

        guard year > 0,
              (1...12).contains(month),
              (0...6).contains(leadingBlankCount),
              (28...31).contains(dayCount),
              encodedDays.allSatisfy({ $0.dayNumber <= dayCount })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .month,
                in: container,
                debugDescription: "Calendar month metadata is invalid."
            )
        }

        let compactDays = Self.compacted(encodedDays)
        let computedBeenCount = compactDays.reduce(0) { $0 + $1.beenCount }
        let computedWannaCount = compactDays.reduce(0) { $0 + $1.wannaCount }
        guard encodedDays == compactDays,
              encodedBeenCount == computedBeenCount,
              encodedWannaCount == computedWannaCount
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .days,
                in: container,
                debugDescription: "Calendar month activity must be compact, sorted, unique, and match its totals."
            )
        }

        self.year = year
        self.month = month
        self.title = title
        self.leadingBlankCount = leadingBlankCount
        self.dayCount = dayCount
        beenCount = encodedBeenCount
        wannaCount = encodedWannaCount
        days = compactDays
    }

    private static func compacted(_ days: [WanderCalendarDaySnapshot]) -> [WanderCalendarDaySnapshot] {
        let countsByDay = days.reduce(into: [Int: (been: Int, wanna: Int)]()) { partialResult, day in
            partialResult[day.dayNumber, default: (0, 0)].been += day.beenCount
            partialResult[day.dayNumber, default: (0, 0)].wanna += day.wannaCount
        }

        return countsByDay
            .filter { $0.value.been > 0 || $0.value.wanna > 0 }
            .map { dayNumber, counts in
                WanderCalendarDaySnapshot(
                    dayNumber: dayNumber,
                    beenCount: counts.been,
                    wannaCount: counts.wanna
                )
            }
            .sorted { $0.dayNumber < $1.dayNumber }
    }
}

struct WanderCalendarWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let timeZoneIdentifier: String
    let firstWeekday: Int
    let weekdaySymbols: [String]
    let previousMonth: WanderCalendarMonthSnapshot
    let currentMonth: WanderCalendarMonthSnapshot
    let nextMonth: WanderCalendarMonthSnapshot

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date,
        timeZoneIdentifier: String,
        firstWeekday: Int,
        weekdaySymbols: [String],
        previousMonth: WanderCalendarMonthSnapshot,
        currentMonth: WanderCalendarMonthSnapshot,
        nextMonth: WanderCalendarMonthSnapshot
    ) {
        precondition(TimeZone(identifier: timeZoneIdentifier) != nil, "Widget time zone must be valid.")
        precondition((1...7).contains(firstWeekday), "First weekday must be between 1 and 7.")
        precondition(weekdaySymbols.count == 7, "A calendar snapshot must contain seven weekday symbols.")

        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.firstWeekday = firstWeekday
        self.weekdaySymbols = weekdaySymbols
        self.previousMonth = previousMonth
        self.currentMonth = currentMonth
        self.nextMonth = nextMonth
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case timeZoneIdentifier
        case firstWeekday
        case weekdaySymbols
        case previousMonth
        case currentMonth
        case nextMonth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        let firstWeekday = try container.decode(Int.self, forKey: .firstWeekday)
        let weekdaySymbols = try container.decode([String].self, forKey: .weekdaySymbols)
        let previousMonth = try container.decode(
            WanderCalendarMonthSnapshot.self,
            forKey: .previousMonth
        )
        let currentMonth = try container.decode(
            WanderCalendarMonthSnapshot.self,
            forKey: .currentMonth
        )
        let nextMonth = try container.decode(
            WanderCalendarMonthSnapshot.self,
            forKey: .nextMonth
        )

        guard TimeZone(identifier: timeZoneIdentifier) != nil,
              (1...7).contains(firstWeekday),
              weekdaySymbols.count == 7
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .weekdaySymbols,
                in: container,
                debugDescription: "Calendar locale metadata is invalid."
            )
        }

        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.firstWeekday = firstWeekday
        self.weekdaySymbols = weekdaySymbols
        self.previousMonth = previousMonth
        self.currentMonth = currentMonth
        self.nextMonth = nextMonth
    }

    func month(year: Int, month: Int) -> WanderCalendarMonthSnapshot? {
        [previousMonth, currentMonth, nextMonth].first {
            $0.year == year && $0.month == month
        }
    }

    func month(containing date: Date) -> WanderCalendarMonthSnapshot? {
        var reference = Calendar(identifier: .gregorian)
        reference.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        reference.firstWeekday = firstWeekday
        let calendar = WanderWidgetCalendar.gregorian(reference: reference)
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        return self.month(year: year, month: month)
    }

    func isCompatible(with calendar: Calendar) -> Bool {
        timeZoneIdentifier == calendar.timeZone.identifier
            && firstWeekday == calendar.firstWeekday
            && weekdaySymbols == WanderWidgetCalendar.rotatedWeekdaySymbols(calendar: calendar)
    }

    func hasSameSemanticContent(as other: Self) -> Bool {
        schemaVersion == other.schemaVersion
            && timeZoneIdentifier == other.timeZoneIdentifier
            && firstWeekday == other.firstWeekday
            && weekdaySymbols == other.weekdaySymbols
            && previousMonth == other.previousMonth
            && currentMonth == other.currentMonth
            && nextMonth == other.nextMonth
    }
}

enum WanderCalendarWidgetSnapshotStoreError: Error, Equatable {
    case appGroupContainerUnavailable
    case unsupportedSchema(Int)
}

struct WanderCalendarWidgetSnapshotStore {
    static let freshnessWriteInterval: TimeInterval = 12 * 60 * 60

    private let fileURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: WanderWidgetConstants.appGroupIdentifier)?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(WanderWidgetConstants.calendarSnapshotFilename, isDirectory: false)
    }

    func load() -> WanderCalendarWidgetSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder.decode(WanderCalendarWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WanderCalendarWidgetSnapshot.currentSchemaVersion
        else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    func save(
        _ snapshot: WanderCalendarWidgetSnapshot,
        allowFreshnessAdvance: Bool = true
    ) throws -> Bool {
        guard snapshot.schemaVersion == WanderCalendarWidgetSnapshot.currentSchemaVersion else {
            throw WanderCalendarWidgetSnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard let fileURL else {
            throw WanderCalendarWidgetSnapshotStoreError.appGroupContainerUnavailable
        }
        if let existing = load(), existing.hasSameSemanticContent(as: snapshot) {
            guard allowFreshnessAdvance else { return false }
            let freshnessAdvance = snapshot.generatedAt.timeIntervalSince(existing.generatedAt)
            if freshnessAdvance < Self.freshnessWriteInterval {
                return false
            }
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var persistedFileURL = fileURL
        try persistedFileURL.setResourceValues(resourceValues)
        return true
    }

    @discardableResult
    func remove() throws -> Bool {
        guard let fileURL else {
            throw WanderCalendarWidgetSnapshotStoreError.appGroupContainerUnavailable
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        try fileManager.removeItem(at: fileURL)
        return true
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
