#if DEBUG
import SwiftUI

enum FutureDateSaveMockupPage: String, CaseIterable {
    case collapsed
    case calendar
    case selected

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> FutureDateSaveMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderFutureDateSaveMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .calendar
        }

        return FutureDateSaveMockupPage(rawValue: arguments[valueIndex]) ?? .calendar
    }
}

struct FutureDateSaveMockupRoot: View {
    let page: FutureDateSaveMockupPage

    var body: some View {
        FutureDateSaveMockup(page: page)
            .preferredColorScheme(.light)
    }
}

private struct FutureDateSaveMockup: View {
    @State private var isShowingMoreOptions: Bool
    @State private var isShowingCalendar: Bool
    @State private var selectedDate: Date?

    private let calendar = Calendar.autoupdatingCurrent

    init(page: FutureDateSaveMockupPage) {
        let suggestedDate = Self.suggestedDate()

        switch page {
        case .collapsed:
            _isShowingMoreOptions = State(initialValue: false)
            _isShowingCalendar = State(initialValue: false)
            _selectedDate = State(initialValue: nil)
        case .calendar:
            _isShowingMoreOptions = State(initialValue: true)
            _isShowingCalendar = State(initialValue: true)
            _selectedDate = State(initialValue: nil)
        case .selected:
            _isShowingMoreOptions = State(initialValue: true)
            _isShowingCalendar = State(initialValue: false)
            _selectedDate = State(initialValue: suggestedDate)
        }
    }

    private var minimumDate: Date {
        calendar.startOfDay(for: Date())
    }

    private var selectedDateBinding: Binding<Set<DateComponents>> {
        Binding(
            get: { WannaGoDate.calendarSelection(for: selectedDate, calendar: calendar) },
            set: {
                selectedDate = WannaGoDate.singleDate(
                    from: $0,
                    replacing: selectedDate,
                    calendar: calendar
                )
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    header
                    candidateCard
                    placeTypeSection
                    moreOptionsSection
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .scrollIndicators(.hidden)
            .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveFooter
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            HStack {
                Spacer()

                Button {} label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text("save this place")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
        }
    }

    private var candidateCard: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ZStack {
                Circle()
                    .fill(WanderTheme.terracottaTint.color)
                Text("🍜")
                    .font(.system(size: 22))
                    .accessibilityHidden(true)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Text("Jitlada")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Spacer(minLength: WanderTheme.spacing1)

                    Text("Wanna")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .padding(.vertical, WanderTheme.spacing1)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Capsule())
                }

                Text("Thai restaurant · East Hollywood")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var placeTypeSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text("place type")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle()
                        .fill(WanderTheme.terracottaTint.color)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restaurants & Food")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("Thai · Restaurant")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing1)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )
        }
    }

    private var moreOptionsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isShowingMoreOptions.toggle()
                    if !isShowingMoreOptions {
                        isShowingCalendar = false
                    }
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Text("more options")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Text("date, note, tags, labels & privacy")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: WanderTheme.spacing1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .rotationEffect(.degrees(isShowingMoreOptions ? 180 : 0))
                }
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowingMoreOptions ? "Hide more options" : "Show more options")
            .accessibilityValue(isShowingMoreOptions ? "Expanded" : "Collapsed")

            if isShowingMoreOptions {
                futureDateSection
                notePreview
                privacyPreview
            }
        }
    }

    private var futureDateSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("when do you wanna go?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isShowingCalendar.toggle()
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                                .fill(WanderTheme.terracottaTint.color)
                            Image(systemName: "calendar")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(WanderTheme.terracotta.color)
                        }
                        .frame(width: 42, height: 42)

                        if selectedDate == nil {
                            Text("add a date")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(WanderTheme.textInk.color)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("planned for")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(WanderTheme.textInk.color)

                                Text(dateSummary)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WanderTheme.terracotta.color)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.textFaint.color)
                            .rotationEffect(.degrees(isShowingCalendar ? 180 : 0))
                    }
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a future date")
                .accessibilityValue(selectedDate.map(Self.accessibilityDate) ?? "No date selected")

                if isShowingCalendar {
                    Divider()
                        .background(WanderTheme.borderHairline.color)

                    MultiDatePicker(
                        "Choose a future date",
                        selection: selectedDateBinding,
                        in: minimumDate...
                    )
                    .labelsHidden()
                    .tint(WanderTheme.terracotta.color)
                    .padding(.top, WanderTheme.spacing1)

                    Divider()
                        .background(WanderTheme.borderHairline.color)

                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Past dates are unavailable")
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        if selectedDate != nil {
                            Button("clear") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedDate = nil
                                    isShowingCalendar = false
                                }
                            }
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear planned date")
                        }
                    }
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .padding(.vertical, WanderTheme.spacing2)
                }
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )

            Text("If notifications are on, rec.me will remind you three days before.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notePreview: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("a note for future you")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            Text("Why you saved it, who told you...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textFaint.color)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }

    private var privacyPreview: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 32, height: 32)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("stealth mode")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("visible to followers")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .tint(WanderTheme.terracotta.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var saveFooter: some View {
        WanderPrimaryButton(title: "save to my map", systemImage: "checkmark") {}
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, WanderTheme.spacing2)
            .background(WanderTheme.canvasWarm.color)
    }

    private var dateSummary: String {
        guard let selectedDate else { return "" }

        return selectedDate.formatted(
            .dateTime
                .weekday(.wide)
                .month(.abbreviated)
                .day()
        )
    }

    private static func suggestedDate(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: Date())
        let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        guard let month = calendar.dateInterval(of: .month, for: today),
              let endOfMonth = calendar.date(byAdding: .day, value: -1, to: month.end)
        else {
            return threeDaysFromNow
        }

        return min(threeDaysFromNow, endOfMonth)
    }

    private static func accessibilityDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}
#endif
