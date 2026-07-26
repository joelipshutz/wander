import SwiftUI
import WidgetKit

@main
struct WanderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WanderQuickCaptureWidget()
        WanderQuickSearchWidget()
        WanderActivityCalendarWidget()
    }
}

// MARK: - Shared timeline support

private struct WanderShortcutEntry: TimelineEntry {
    let date: Date
}

private struct WanderShortcutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WanderShortcutEntry {
        WanderShortcutEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WanderShortcutEntry) -> Void
    ) {
        completion(WanderShortcutEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WanderShortcutEntry>) -> Void
    ) {
        let entry = WanderShortcutEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct WanderCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WanderCalendarWidgetSnapshot?
}

private struct WanderCalendarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WanderCalendarEntry {
        WanderCalendarEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WanderCalendarEntry) -> Void
    ) {
        let snapshot = context.isPreview
            ? WanderWidgetPreviewData.calendarSnapshot
            : WanderCalendarWidgetSnapshotStore().load()
        completion(WanderCalendarEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WanderCalendarEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = WanderCalendarWidgetSnapshotStore().load()
        let schedule = WanderCalendarTimelineSchedule.make(
            startingAt: now,
            snapshot: snapshot
        )
        let entries = schedule.entryDates.map {
            WanderCalendarEntry(date: $0, snapshot: snapshot)
        }
        completion(
            Timeline(
                entries: entries,
                policy: .after(schedule.reloadAfter)
            )
        )
    }
}

// MARK: - Quick capture

private struct WanderQuickCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WanderWidgetConstants.quickCaptureKind,
            provider: WanderShortcutTimelineProvider()
        ) { entry in
            WanderQuickCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("I'm here now")
        .description("Open rec.me to save the place where you are.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

private struct WanderQuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WanderShortcutEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            case .accessoryInline:
                inlineView
            default:
                smallView
            }
        }
        .containerBackground(for: .widget) {
            WanderWidgetPalette.surfaceBone
        }
        .widgetURL(WanderWidgetConstants.quickCaptureURL)
    }

    private var smallView: some View {
        ViewThatFits(in: .vertical) {
            regularSmallView
            compactSmallView
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I'm here now. Opens rec.me to save your current place.")
    }

    private var regularSmallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WanderWidgetBrand()
                Spacer(minLength: 8)
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderWidgetPalette.terracotta)
                    .frame(width: 34, height: 34)
                    .background(WanderWidgetPalette.terracottaTint)
                    .clipShape(Circle())
            }

            Spacer(minLength: 8)

            Text("I'm here\nnow")
                .font(.title2.weight(.black))
                .fontDesign(.rounded)
                .foregroundStyle(WanderWidgetPalette.textInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("Save this place")
                    .lineLimit(1)
                Image(systemName: "arrow.right")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(WanderWidgetPalette.textOnAction)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(WanderWidgetPalette.terracottaDark)
            .clipShape(Capsule())
        }
    }

    private var compactSmallView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                WanderWidgetBrand()
                Spacer(minLength: 6)
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderWidgetPalette.terracottaDark)
            }

            Text("I'm here now")
                .font(.headline.weight(.black))
                .fontDesign(.rounded)
                .foregroundStyle(WanderWidgetPalette.textInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 5) {
                Text("Save this place")
                    .lineLimit(1)
                Image(systemName: "arrow.right")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(WanderWidgetPalette.textOnAction)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(WanderWidgetPalette.terracottaDark)
            .clipShape(Capsule())
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "location.fill")
                    .font(.system(size: 19, weight: .bold))
                Text("HERE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
            }
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I'm here now. Opens rec.me to save your current place.")
    }

    private var rectangularView: some View {
        HStack(spacing: 9) {
            Image(systemName: "location.fill")
                .font(.system(size: 19, weight: .bold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text("I'm here now")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("Save in rec.me")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I'm here now. Opens rec.me to save your current place.")
    }

    private var inlineView: some View {
        Label("I'm here now", systemImage: "location.fill")
            .accessibilityLabel("I'm here now. Opens rec.me.")
    }
}

// MARK: - Quick search

private struct WanderQuickSearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WanderWidgetConstants.quickSearchKind,
            provider: WanderShortcutTimelineProvider()
        ) { entry in
            WanderQuickSearchWidgetView(entry: entry)
        }
        .configurationDisplayName("Search rec.me")
        .description("Jump to the map and start a place search.")
        .supportedFamilies([
            .systemMedium,
            .accessoryRectangular,
        ])
    }
}

private struct WanderQuickSearchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WanderShortcutEntry

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessoryView
            } else {
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            WanderWidgetPalette.surfaceBone
        }
        .widgetURL(WanderWidgetConstants.quickSearchURL)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WanderWidgetBrand()
                Spacer()
                Text("MAP")
                    .font(.caption2.weight(.black))
                    .fontDesign(.rounded)
                    .foregroundStyle(WanderWidgetPalette.textMuted)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WanderWidgetPalette.terracotta)

                Text("Search in rec.me")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WanderWidgetPalette.textInk)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderWidgetPalette.textMuted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(WanderWidgetPalette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(WanderWidgetPalette.borderHairline, lineWidth: 1)
            )

            Text("Opens the map ready to type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WanderWidgetPalette.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search rec.me. Opens the map with search ready.")
    }

    private var accessoryView: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text("Search rec.me")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("Opens the map")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search rec.me. Opens the map with search ready.")
    }
}

// MARK: - Activity calendar

private struct WanderActivityCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WanderWidgetConstants.activityCalendarKind,
            provider: WanderCalendarTimelineProvider()
        ) { entry in
            WanderActivityCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Activity calendar")
        .description("See your been activity for the current month.")
        .supportedFamilies([.systemLarge])
    }
}

private struct WanderActivityCalendarWidgetView: View {
    let entry: WanderCalendarEntry

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 3),
        count: 7
    )

    private var model: WanderCalendarDisplayModel {
        WanderCalendarDisplayModel(snapshot: entry.snapshot, date: entry.date)
    }

    var body: some View {
        GeometryReader { geometry in
            calendarContent(availableHeight: geometry.size.height)
        }
        .containerBackground(for: .widget) {
            WanderWidgetPalette.surfaceBone
        }
        .widgetURL(WanderWidgetConstants.profileCalendarURL)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens your calendar in rec.me.")
    }

    private func calendarContent(availableHeight: CGFloat) -> some View {
        let sectionSpacing: CGFloat = 6
        let rowSpacing: CGFloat = 1
        let headerHeight: CGFloat = 36
        let weekdayHeight: CGFloat = 12
        let footerHeight: CGFloat = 16
        let fixedHeight = headerHeight
            + weekdayHeight
            + footerHeight
            + (sectionSpacing * 3)
            + (rowSpacing * 5)
        let rowHeight = max(30, floor((availableHeight - fixedHeight) / 6))
        let markerSize = min(27, max(20, rowHeight - 10))

        return VStack(alignment: .leading, spacing: sectionSpacing) {
            header
                .frame(height: headerHeight)

            HStack(spacing: 3) {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.black))
                        .fontDesign(.rounded)
                        .foregroundStyle(WanderWidgetPalette.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: weekdayHeight)
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: rowSpacing) {
                ForEach(0..<42, id: \.self) { index in
                    let dayNumber = model.dayNumber(atGridIndex: index)
                    WanderCalendarDayCell(
                        dayNumber: dayNumber,
                        snapshot: dayNumber.flatMap { model.daysByNumber[$0] },
                        monthTitle: model.monthTitle,
                        isToday: dayNumber.map(model.isToday(dayNumber:)) ?? false,
                        cellHeight: rowHeight,
                        markerSize: markerSize
                    )
                }
            }
            .frame(height: (rowHeight * 6) + (rowSpacing * 5))

            footer
                .frame(height: footerHeight)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("your calendar")
                    .font(.headline.weight(.black))
                    .fontDesign(.rounded)
                    .foregroundStyle(WanderWidgetPalette.textInk)
                    .lineLimit(1)
                Text(model.monthTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WanderWidgetPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(model.beenCount) been")
                .foregroundStyle(WanderWidgetPalette.terracottaDark)
                .font(.caption2.weight(.black))
                .fontDesign(.rounded)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.monthTitle). Been: \(model.beenCount)."
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            WanderCalendarLegendItem(state: .been, title: "been")

            Spacer(minLength: 2)

            if model.needsRefresh {
                Text("Open rec.me to update")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WanderWidgetPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            model.needsRefresh
                ? "Calendar has not synced yet. Open rec.me to update."
                : "Calendar legend: filled is been."
        )
    }
}

private struct WanderCalendarDayCell: View {
    let dayNumber: Int?
    let snapshot: WanderCalendarDaySnapshot?
    let monthTitle: String
    let isToday: Bool
    let cellHeight: CGFloat
    let markerSize: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var nowTextSize: CGFloat = 6

    private var state: WanderWidgetActivityState {
        (snapshot?.beenCount ?? 0) > 0 ? .been : .none
    }

    var body: some View {
        VStack(spacing: 2) {
            if dayNumber != nil, isToday {
                Text("NOW")
                    .font(.system(size: min(nowTextSize, 8), weight: .black, design: .rounded))
                    .foregroundStyle(WanderWidgetPalette.textInk)
                    .padding(.horizontal, 4)
                    .frame(height: 8)
                    .background(WanderWidgetPalette.surfaceRaised)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(WanderWidgetPalette.borderHairline, lineWidth: 0.6)
                    )
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .frame(height: 8)
                    .accessibilityHidden(true)
            }

            if let dayNumber {
                WanderCalendarActivityMarker(
                    state: state,
                    size: markerSize,
                    label: String(dayNumber)
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHidden(dayNumber == nil || (state == .none && !isToday))
    }

    private var accessibilityLabel: String {
        guard let dayNumber else { return "" }
        let dateLabel = "\(monthTitle) \(dayNumber)"
        let todayLabel = isToday ? ", today" : ""
        guard let snapshot, snapshot.beenCount > 0 else {
            return "\(dateLabel)\(todayLabel), no activity"
        }
        return "\(dateLabel)\(todayLabel). Been: \(snapshot.beenCount)."
    }
}

private struct WanderCalendarActivityMarker: View {
    let state: WanderWidgetActivityState
    let size: CGFloat
    let label: String?

    @ScaledMetric(relativeTo: .caption) private var labelScale: CGFloat = 1

    var body: some View {
        ZStack {
            if state == .been {
                Circle()
                    .fill(WanderWidgetPalette.terracottaDark)
                    .frame(width: size - 3, height: size - 3)
            }

            if let label {
                Text(label)
                    .font(
                        .system(
                            size: min(size * 0.45, size * 0.37 * labelScale),
                            weight: state == .none ? .bold : .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        state == .been
                            ? WanderWidgetPalette.textOnAction
                            : WanderWidgetPalette.textInk
                    )
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct WanderCalendarLegendItem: View {
    let state: WanderWidgetActivityState
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            WanderCalendarActivityMarker(state: state, size: 14, label: nil)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(WanderWidgetPalette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct WanderCalendarDisplayModel {
    let year: Int
    let month: Int
    let monthTitle: String
    let leadingBlankCount: Int
    let dayCount: Int
    let beenCount: Int
    let weekdaySymbols: [String]
    let timeZoneIdentifier: String
    let daysByNumber: [Int: WanderCalendarDaySnapshot]
    let referenceDate: Date
    let hasCurrentMonthSnapshot: Bool
    let needsRefresh: Bool

    init(snapshot: WanderCalendarWidgetSnapshot?, date: Date) {
        let currentCalendar = WanderWidgetCalendar.gregorian()
        let compatibleSnapshot = snapshot.flatMap {
            $0.isCompatible(with: currentCalendar) ? $0 : nil
        }

        if let snapshot = compatibleSnapshot,
           let month = snapshot.month(containing: date) {
            year = month.year
            self.month = month.month
            monthTitle = month.title
            leadingBlankCount = month.leadingBlankCount
            dayCount = month.dayCount
            beenCount = month.beenCount
            weekdaySymbols = snapshot.weekdaySymbols
            timeZoneIdentifier = snapshot.timeZoneIdentifier
            daysByNumber = Dictionary(
                uniqueKeysWithValues: month.days.map { ($0.dayNumber, $0) }
            )
            referenceDate = date
            hasCurrentMonthSnapshot = true
            needsRefresh = date.timeIntervalSince(snapshot.generatedAt) > (36 * 60 * 60)
        } else {
            let calendar = currentCalendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let fallbackYear = components.year ?? 1970
            let fallbackMonth = components.month ?? 1
            let monthStart = calendar.date(
                from: DateComponents(year: fallbackYear, month: fallbackMonth, day: 1)
            ) ?? date
            let firstWeekday = calendar.component(.weekday, from: monthStart)

            year = fallbackYear
            month = fallbackMonth
            monthTitle = WanderWidgetCalendar.monthTitle(for: monthStart, calendar: calendar)
            leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7
            dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            beenCount = 0
            weekdaySymbols = WanderWidgetCalendar.rotatedWeekdaySymbols(calendar: calendar)
            timeZoneIdentifier = calendar.timeZone.identifier
            daysByNumber = [:]
            referenceDate = date
            hasCurrentMonthSnapshot = false
            needsRefresh = true
        }
    }

    func dayNumber(atGridIndex index: Int) -> Int? {
        let day = index - leadingBlankCount + 1
        guard day >= 1, day <= dayCount else { return nil }
        return day
    }

    func isToday(dayNumber: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        return components.year == year
            && components.month == month
            && components.day == dayNumber
    }

}

// MARK: - Widget-local design tokens

private struct WanderWidgetBrand: View {
    var body: some View {
        Text("rec.me")
            .font(.caption.weight(.black))
            .fontDesign(.rounded)
            .foregroundStyle(WanderWidgetPalette.textInk)
    }
}

private enum WanderWidgetPalette {
    static let canvasWarm = Color(
        red: 243.0 / 255.0,
        green: 223.0 / 255.0,
        blue: 202.0 / 255.0
    )
    static let surfaceBone = Color(
        red: 255.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 234.0 / 255.0
    )
    static let surfaceRaised = Color.white
    static let textInk = Color(
        red: 44.0 / 255.0,
        green: 33.0 / 255.0,
        blue: 24.0 / 255.0
    )
    static let textMuted = Color(
        red: 123.0 / 255.0,
        green: 101.0 / 255.0,
        blue: 85.0 / 255.0
    )
    static let textFaint = Color(
        red: 168.0 / 255.0,
        green: 149.0 / 255.0,
        blue: 127.0 / 255.0
    )
    static let textOnAction = Color(
        red: 255.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 234.0 / 255.0
    )
    static let borderHairline = Color(
        red: 219.0 / 255.0,
        green: 194.0 / 255.0,
        blue: 170.0 / 255.0
    )
    static let terracotta = Color(
        red: 212.0 / 255.0,
        green: 111.0 / 255.0,
        blue: 77.0 / 255.0
    )
    static let terracottaDark = Color(
        red: 169.0 / 255.0,
        green: 79.0 / 255.0,
        blue: 53.0 / 255.0
    )
    static let terracottaTint = Color(
        red: 246.0 / 255.0,
        green: 224.0 / 255.0,
        blue: 210.0 / 255.0
    )
}

// MARK: - Previews

private enum WanderWidgetPreviewData {
    static let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
        )!
    }()

    static let calendarSnapshot = WanderCalendarWidgetSnapshot(
        generatedAt: date,
        timeZoneIdentifier: "America/Los_Angeles",
        firstWeekday: 1,
        weekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
        previousMonth: WanderCalendarMonthSnapshot(
            year: 2026,
            month: 6,
            title: "June 2026",
            leadingBlankCount: 1,
            dayCount: 30,
            days: []
        ),
        currentMonth: WanderCalendarMonthSnapshot(
            year: 2026,
            month: 7,
            title: "July 2026",
            leadingBlankCount: 3,
            dayCount: 31,
            days: [
                WanderCalendarDaySnapshot(dayNumber: 2, beenCount: 1, wannaCount: 0),
                WanderCalendarDaySnapshot(dayNumber: 7, beenCount: 2, wannaCount: 0),
                WanderCalendarDaySnapshot(dayNumber: 8, beenCount: 1, wannaCount: 0),
                WanderCalendarDaySnapshot(dayNumber: 15, beenCount: 1, wannaCount: 0),
                WanderCalendarDaySnapshot(dayNumber: 24, beenCount: 3, wannaCount: 0)
            ]
        ),
        nextMonth: WanderCalendarMonthSnapshot(
            year: 2026,
            month: 8,
            title: "August 2026",
            leadingBlankCount: 6,
            dayCount: 31,
            days: []
        )
    )
}

#Preview("Quick capture", as: .systemSmall) {
    WanderQuickCaptureWidget()
} timeline: {
    WanderShortcutEntry(date: WanderWidgetPreviewData.date)
}

#Preview("Quick search", as: .systemMedium) {
    WanderQuickSearchWidget()
} timeline: {
    WanderShortcutEntry(date: WanderWidgetPreviewData.date)
}

#Preview("Activity calendar", as: .systemLarge) {
    WanderActivityCalendarWidget()
} timeline: {
    WanderCalendarEntry(
        date: WanderWidgetPreviewData.date,
        snapshot: WanderWidgetPreviewData.calendarSnapshot
    )
}
