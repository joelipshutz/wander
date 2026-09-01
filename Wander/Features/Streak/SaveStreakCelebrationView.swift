import SwiftUI

struct SaveStreakCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.astirBrandMode) private var brandMode
    @ScaledMetric(relativeTo: .largeTitle) private var streakCountFontSize: CGFloat = 82
    @ScaledMetric(relativeTo: .title) private var streakLabelFontSize: CGFloat = 28
    let celebration: SaveStreakCelebration
    let onDismiss: () -> Void

    @State private var ticketLanded = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                brandMode.background
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        brandMode.accent.opacity(0.42),
                        brandMode.background.opacity(0)
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.64
                )
                .ignoresSafeArea()

                SaveStreakConfettiLayer()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    AstirMastheadLockup(isCompact: true)
                        .padding(.top, max(proxy.safeAreaInsets.top, WanderTheme.spacing4) + WanderTheme.spacing4)

                    Spacer(minLength: WanderTheme.spacing6)

                    SaveStreakTicketCard(celebration: celebration, isFaceUp: ticketLanded)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)
                        .rotationEffect(
                            accessibilityReduceMotion || ticketLanded
                                ? .zero
                                : .degrees(-8)
                        )
                        .rotation3DEffect(
                            .degrees(accessibilityReduceMotion || ticketLanded ? 0 : -178),
                            axis: (x: 0.08, y: 1, z: 0),
                            perspective: 0.62
                        )
                        .offset(
                            x: accessibilityReduceMotion || ticketLanded ? 0 : -proxy.size.width * 0.48,
                            y: accessibilityReduceMotion || ticketLanded ? 0 : proxy.size.height * 0.23
                        )
                        .opacity(accessibilityReduceMotion && !ticketLanded ? 0 : 1)
                        .animation(ticketAnimation, value: ticketLanded)

                    VStack(spacing: WanderTheme.spacing1) {
                        Text(SaveStreakCelebrationPresentation.visualCount(for: celebration.streakCount))
                            .font(.system(size: streakCountFontSize, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)

                        Text("day streak!")
                            .font(.system(size: streakLabelFontSize, weight: .semibold, design: .serif))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                    }
                    .foregroundStyle(brandMode.primaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, WanderTheme.spacing6)
                    .opacity(ticketLanded ? 1 : 0)
                    .scaleEffect(accessibilityReduceMotion || ticketLanded ? 1 : 0.82)
                    .animation(countAnimation, value: ticketLanded)

                    SaveStreakWeekCard(
                        streakCount: celebration.streakCount,
                        saveDate: celebration.saveDate,
                        recoveryDate: celebration.recoveryDate
                    )
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)
                    .padding(.top, WanderTheme.spacing4)
                    .opacity(ticketLanded ? 1 : 0)
                    .offset(y: accessibilityReduceMotion || ticketLanded ? 0 : 10)
                    .animation(copyAnimation, value: ticketLanded)

                    Text(SaveStreakCelebrationPresentation.helperText(for: celebration))
                        .font(AstirTypography.body)
                        .foregroundStyle(brandMode.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WanderTheme.spacing4)
                        .opacity(ticketLanded ? 1 : 0)
                        .offset(y: accessibilityReduceMotion || ticketLanded ? 0 : 12)
                        .animation(copyAnimation, value: ticketLanded)

                    Spacer(minLength: WanderTheme.spacing6)

                    Button(action: onDismiss) {
                        Text("got it")
                            .font(AstirTypography.control)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                            .foregroundStyle(brandMode.selectedForeground)
                            .background(brandMode.selectedFill)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Closes the streak celebration")
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, WanderTheme.spacing4) + WanderTheme.spacing2)
                }
                .padding(.horizontal, WanderTheme.spacing6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard !ticketLanded else { return }
            DispatchQueue.main.async {
                ticketLanded = true
            }
        }
    }

    private var ticketAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.24)
            : .spring(duration: 0.72, bounce: 0.2)
    }

    private var copyAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.22)
            : .easeOut(duration: 0.28).delay(0.42)
    }

    private var countAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.22)
            : .spring(duration: 0.4, bounce: 0.18).delay(0.32)
    }

    private var accessibilityLabel: String {
        let title = SaveStreakCelebrationPresentation.accessibilityTitle(
            for: celebration.streakCount
        )
        let activity = celebration.status == .been ? CheckInCopy.pastTense : "added to Wanna"
        return "\(title). \(activity) at \(celebration.placeName)."
    }
}

struct SaveStreakConfettiPopView: View {
    var body: some View {
        SaveStreakConfettiLayer(motion: .sameDayPop)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SaveStreakTicketCard: View {
    @Environment(\.astirBrandMode) private var brandMode
    let celebration: SaveStreakCelebration
    let isFaceUp: Bool

    var body: some View {
        ZStack {
            ticketBack
                .opacity(isFaceUp ? 0 : 1)

            ticketFront
                .opacity(isFaceUp ? 1 : 0)
        }
        .frame(height: 142)
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 12)
    }

    private var ticketFront: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(ticketEyebrow)
                    .font(AstirTypography.metadata)
                    .tracking(1.3)
                    .foregroundStyle(brandMode.accent)

                Spacer(minLength: 0)

                Text(celebration.placeName)
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if let detail = celebration.placeDetail {
                    Text(detail)
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WanderTheme.spacing2)

            Image(systemName: celebration.status == .been ? "checkmark" : "plus")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(width: 40, height: 40)
                .background(statusColor)
                .clipShape(Circle())
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .checkInTicketSurface(
            accent: .clear,
            surface: brandMode.raisedBackground,
            notchEdges: .trailing,
            castsShadow: false
        )
    }

    private var ticketBack: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(brandMode.accent)
            Text("REC.ME")
                .font(AstirTypography.metadata)
                .tracking(2.2)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .checkInTicketSurface(
            accent: .clear,
            surface: brandMode.raisedBackground,
            notchEdges: .trailing,
            castsShadow: false
        )
    }

    private var statusColor: Color {
        celebration.status == .been
            ? WanderTheme.stateSuccess.color
            : WanderTheme.stateWarning.color
    }

    private var ticketEyebrow: String {
        celebration.status == .been ? "CHECKED IN TODAY" : "ADDED TO WANNA TODAY"
    }
}

private struct SaveStreakWeekCard: View {
    @Environment(\.astirBrandMode) private var brandMode
    let streakCount: Int
    let saveDate: Date
    let recoveryDate: Date?

    var body: some View {
        let days = weekdays

        HStack(spacing: WanderTheme.spacing2) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: WanderTheme.spacing2) {
                    Text(day.symbol)
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(
                            day.isToday
                                ? brandMode.accent
                                : brandMode.secondaryText
                        )

                    ZStack {
                        Circle()
                            .fill(
                                day.isRecoveryDay
                                    ? brandMode.accentWash
                                    : day.isCovered
                                        ? brandMode.accent
                                        : brandMode.recessedBackground
                            )

                        if day.isRecoveryDay {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(brandMode.accent)
                        } else if day.isCovered {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(brandMode.accentForeground)
                        }

                        if day.isToday {
                            Circle()
                                .stroke(brandMode.primaryText, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                    .frame(width: 27, height: 27)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(brandMode.border.opacity(0.78), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibilityLabel(for: days))
    }

    private var weekdays: [SaveStreakWeekday] {
        SaveStreakCelebrationPresentation.weekdays(
            streakCount: streakCount,
            endingOn: saveDate,
            recoveryDate: recoveryDate
        )
    }

    private func weekAccessibilityLabel(for days: [SaveStreakWeekday]) -> String {
        let coveredCount = days.filter(\.isCovered).count
        let recoveryCopy = days.contains(where: \.isRecoveryDay)
            ? " One missed day used a Streak Save."
            : ""
        return "Last \(SaveStreakWindow.dayCount) days. \(coveredCount) days complete. Today complete.\(recoveryCopy)"
    }
}

struct SaveStreakConfettiMotion: Equatable {
    let pieceCount: Int
    let travelScale: CGFloat
    let speedScale: Double
    let arrivalWindow: Double?

    static let welcome = SaveStreakConfettiMotion(
        pieceCount: 80,
        travelScale: 1,
        speedScale: 0.70,
        arrivalWindow: 1
    )

    static let sameDayPop = SaveStreakConfettiMotion(
        pieceCount: 42,
        travelScale: 0.72,
        speedScale: 0.92,
        arrivalWindow: nil
    )

    func travelDuration(for index: Int) -> Double {
        let shippingDuration = 1.15 + Double(index % 5) * 0.12
        return shippingDuration / max(speedScale, 0.01)
    }

    func delay(for index: Int) -> Double {
        guard let arrivalWindow else {
            return Double(index % 9) * 0.035
        }
        guard pieceCount > 1 else { return 0 }
        return arrivalWindow * Double(index) / Double(pieceCount - 1)
    }

    var latestEndTime: Double {
        (0..<pieceCount).map { delay(for: $0) + travelDuration(for: $0) }.max() ?? 0
    }
}

private struct SaveStreakConfettiLayer: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let motion: SaveStreakConfettiMotion

    @State private var isFalling = false

    init(motion: SaveStreakConfettiMotion = .welcome) {
        self.motion = motion
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<motion.pieceCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colors[index % colors.count])
                        .frame(
                            width: index.isMultiple(of: 4) ? 6 : 9,
                            height: index.isMultiple(of: 4) ? 14 : 6
                        )
                        .rotationEffect(.degrees(isFalling ? endRotation(index) : startRotation(index)))
                        .position(
                            x: proxy.size.width * horizontalFraction(index),
                            y: isFalling
                                ? proxy.size.height * endVerticalFraction(index) * motion.travelScale
                                : -24 - CGFloat(index % 7) * 16
                        )
                        .opacity(isFalling ? 0.06 : 1)
                        .animation(animation(index), value: isFalling)
                }
            }
            .onAppear {
                guard !accessibilityReduceMotion else { return }
                isFalling = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private let colors: [Color] = [
        WanderTheme.terracotta.color,
        WanderTheme.categorySun.color,
        WanderTheme.categorySage.color,
        WanderTheme.pinSocial.color,
        WanderTheme.surfaceBone.color
    ]

    private func horizontalFraction(_ index: Int) -> CGFloat {
        CGFloat((index * 37 + 13) % 101) / 100
    }

    private func endVerticalFraction(_ index: Int) -> CGFloat {
        1.08 + CGFloat(index % 5) * 0.08
    }

    private func startRotation(_ index: Int) -> Double {
        Double((index * 29) % 180)
    }

    private func endRotation(_ index: Int) -> Double {
        startRotation(index) + Double(260 + (index % 6) * 90)
    }

    private func animation(_ index: Int) -> Animation {
        .easeIn(duration: motion.travelDuration(for: index))
            .delay(motion.delay(for: index))
    }
}

#if DEBUG
enum SaveStreakMockupPage: String, CaseIterable {
    case takeover
    case profileRow

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> SaveStreakMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderStreakMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .takeover
        }

        return SaveStreakMockupPage(rawValue: arguments[valueIndex]) ?? .takeover
    }
}

struct SaveStreakMockupRoot: View {
    let page: SaveStreakMockupPage

    var body: some View {
        switch page {
        case .takeover:
            SaveStreakCelebrationView(
                celebration: SaveStreakCelebration(
                    kind: .dailyTakeover,
                    placeName: "Bar Etoile",
                    placeDetail: "Los Angeles · CA",
                    status: .been,
                    streakCount: 4,
                    saveDate: .now
                ),
                onDismiss: {}
            )
        case .profileRow:
            SaveStreakProfileRowMockup()
        }
    }
}
#endif
