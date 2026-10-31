import Foundation

/// Reuses formatter configuration, never rendered date strings. The lock covers
/// both lookup and formatting so no mutable DateFormatter escapes this cache.
final class ActivityDateFormatterCache: @unchecked Sendable {
    static let shared = ActivityDateFormatterCache()

    private struct Key: Hashable {
        let calendar: Calendar
        // Resolve the live settings too: autoupdating calendars/locales can keep
        // their identity while the user's effective configuration changes.
        let calendarIdentifier: Calendar.Identifier
        let localeIdentifier: String?
        let timeZoneIdentifier: String
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int
        let format: String
    }

    private let lock = NSLock()
    private let capacity: Int
    private var formatters: [Key: DateFormatter] = [:]
    private var insertionOrder: [Key] = []

    init(capacity: Int = 16) {
        self.capacity = max(1, capacity)
    }

    var cachedFormatterCount: Int { lock.withLock { formatters.count } }

    func string(from date: Date, calendar: Calendar, format: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(calendar: calendar, calendarIdentifier: calendar.identifier, localeIdentifier: calendar.locale?.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier, firstWeekday: calendar.firstWeekday,
            minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek, format: format)
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if formatters.count >= capacity, let oldest = insertionOrder.first {
                formatters.removeValue(forKey: oldest)
                insertionOrder.removeFirst()
            }
            formatters[key] = formatter
            insertionOrder.append(key)
        }
        return formatter.string(from: date)
    }
}
