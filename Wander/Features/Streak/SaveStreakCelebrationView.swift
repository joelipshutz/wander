import SwiftUI

struct SaveStreakCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let celebration: SaveStreakCelebration
    let onDismiss: () -> Void

    @State private var ticketLanded = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WanderTheme.textInk.color
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        WanderTheme.terracottaDark.color.opacity(0.52),
                        WanderTheme.textInk.color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.64
                )
                .ignoresSafeArea()

                SaveStreakConfettiLayer()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("REC.ME")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(WanderTheme.textOnAction.color)
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
                            .font(.system(size: 82, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)

                        Text("day streak!")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, WanderTheme.spacing6)
                    .opacity(ticketLanded ? 1 : 0)
                    .scaleEffect(ticketLanded ? 1 : 0.82)
                    .animation(countAnimation, value: ticketLanded)

                    SaveStreakWeekCard(
                        streakCount: celebration.streakCount,
                        saveDate: celebration.saveDate
                    )
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)
                    .padding(.top, WanderTheme.spacing4)
                    .opacity(ticketLanded ? 1 : 0)
                    .offset(y: ticketLanded ? 0 : 10)
                    .animation(copyAnimation, value: ticketLanded)

                    Text("One Check-in or Wanna keeps it going.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WanderTheme.textOnAction.color.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WanderTheme.spacing4)
                        .opacity(ticketLanded ? 1 : 0)
                        .offset(y: ticketLanded ? 0 : 12)
                        .animation(copyAnimation, value: ticketLanded)

                    Spacer(minLength: WanderTheme.spacing6)

                    Button(action: onDismiss) {
                        Text("got it")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .background(WanderTheme.surfaceBone.color)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
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
            : .spring(duration: 1.08, bounce: 0.22)
    }

    private var copyAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.22)
            : .easeOut(duration: 0.34).delay(0.68)
    }

    private var countAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.22)
            : .spring(duration: 0.5, bounce: 0.2).delay(0.56)
    }

    private var accessibilityLabel: String {
        let title = SaveStreakCelebrationPresentation.accessibilityTitle(
            for: celebration.streakCount
        )
        return "\(title). \(celebration.placeName) saved as \(celebration.status.streakDisplayName)."
    }
}

struct SaveStreakConfettiPopView: View {
    var body: some View {
        SaveStreakConfettiLayer(pieceCount: 30, travelScale: 0.62)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SaveStreakTicketCard: View {
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
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .fill(WanderTheme.surfaceBone.color)

            Circle()
                .fill(WanderTheme.textInk.color)
                .frame(width: 24, height: 24)
                .offset(x: 12)

            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("SAVED TODAY  ·  \(celebration.status.streakDisplayName.uppercased())")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(WanderTheme.terracottaDark.color)

                    Spacer(minLength: 0)

                    Text(celebration.placeName)
                        .font(.system(size: 29, weight: .black, design: .serif))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if let detail = celebration.placeDetail {
                        Text(detail)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: celebration.status == .been ? "checkmark" : "bookmark.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: 40, height: 40)
                    .background(statusColor)
                    .clipShape(Circle())
            }
            .padding(WanderTheme.spacing4)
        }
    }

    private var ticketBack: some View {
        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
            .fill(WanderTheme.surfaceBone.color)
            .overlay {
                VStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                    Text("REC.ME")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
    }

    private var statusColor: Color {
        celebration.status == .been
            ? WanderTheme.stateSuccess.color
            : WanderTheme.stateWarning.color
    }
}

private struct SaveStreakWeekCard: View {
    let streakCount: Int
    let saveDate: Date

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                VStack(spacing: WanderTheme.spacing2) {
                    Text(day.symbol)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(
                            day.isToday
                                ? WanderTheme.terracottaDark.color
                                : WanderTheme.textMuted.color
                        )

                    ZStack {
                        Circle()
                            .fill(
                                day.isCovered
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.surfaceSand.color
                            )

                        if day.isCovered {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(WanderTheme.textOnAction.color)
                        }

                        if day.isToday {
                            Circle()
                                .stroke(WanderTheme.textInk.color, lineWidth: 2)
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
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.78), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibilityLabel)
    }

    private var weekdays: [SaveStreakWeekday] {
        SaveStreakCelebrationPresentation.weekdays(
            streakCount: streakCount,
            endingOn: saveDate
        )
    }

    private var weekAccessibilityLabel: String {
        let coveredCount = weekdays.filter(\.isCovered).count
        return "Last seven days. \(coveredCount) days complete. Today complete."
    }
}

private struct SaveStreakConfettiLayer: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let pieceCount: Int
    let travelScale: CGFloat

    @State private var isFalling = false

    init(pieceCount: Int = 46, travelScale: CGFloat = 1) {
        self.pieceCount = pieceCount
        self.travelScale = travelScale
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<pieceCount, id: \.self) { index in
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
                                ? proxy.size.height * endVerticalFraction(index) * travelScale
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
        .easeIn(duration: 1.15 + Double(index % 5) * 0.12)
            .delay(Double(index % 9) * 0.035)
    }
}

private extension PlaceStatus {
    var streakDisplayName: String {
        switch self {
        case .been: CheckInCopy.noun.capitalized
        case .wannaGo: "Wanna"
        }
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
