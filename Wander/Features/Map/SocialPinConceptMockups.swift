#if DEBUG
import SwiftUI

enum SocialPinMockupPage: String, CaseIterable {
    case comparison
    case splitHalo
    case statusPips
    case stateLanes

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> SocialPinMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderSocialPinMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .comparison
        }

        return SocialPinMockupPage(rawValue: arguments[valueIndex]) ?? .comparison
    }
}

struct SocialPinMockupRoot: View {
    let page: SocialPinMockupPage

    var body: some View {
        Group {
            switch page {
            case .comparison:
                SocialPinComparisonMockup()
            case .splitHalo:
                SocialPinMapMockup(concept: .splitHalo)
            case .statusPips:
                SocialPinMapMockup(concept: .statusPips)
            case .stateLanes:
                SocialPinMapMockup(concept: .stateLanes)
            }
        }
        .preferredColorScheme(.light)
    }
}

private enum SocialPinConcept: String, CaseIterable, Identifiable {
    case splitHalo
    case statusPips
    case stateLanes

    var id: String { rawValue }

    var option: String {
        switch self {
        case .splitHalo: "A"
        case .statusPips: "B"
        case .stateLanes: "C"
        }
    }

    var title: String {
        switch self {
        case .splitHalo: "split halo"
        case .statusPips: "status pips"
        case .stateLanes: "state lanes"
        }
    }

    var summary: String {
        switch self {
        case .splitHalo:
            "Equal solid and dotted sky arcs show that both social signals exist."
        case .statusPips:
            "Two small sky badges make Been and Wanna explicit around the pin."
        case .stateLanes:
            "A complete ring for each present state keeps every signal literal."
        }
    }

    var mapCaption: String {
        switch self {
        case .splitHalo: "same footprint"
        case .statusPips: "most explicit"
        case .stateLanes: "most literal"
        }
    }

    var isRecommended: Bool {
        self == .splitHalo
    }
}

private struct SocialPinComparisonMockup: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                comparisonHeader
                CurrentBehaviorCard()

                Text("three ways to keep both signals")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .padding(.top, 2)

                ForEach(SocialPinConcept.allCases) { concept in
                    SocialPinConceptCard(concept: concept)
                }

                RecommendationCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private var comparisonHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("rec.me")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.terracotta.color)

                Spacer()

                Text("REC-99 · SWIFTUI")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Text("mixed social pin")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.textInk.color)

            Text("Ryan · been   Joe · been   Maya · wanna")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
    }
}

private struct CurrentBehaviorCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(WanderTheme.skyTint.color)
                    .frame(width: 66, height: 66)

                CurrentMixedStatePin()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("today · Maya disappears")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)

                Text("The sky ring resolves to solid Been because Joe has been. Maya’s Wanna never reaches the map.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(WanderTheme.surfaceBone.color)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct SocialPinConceptCard: View {
    let concept: SocialPinConcept

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                MockMapPatch()
                SocialSignalPin(concept: concept)
            }
            .frame(width: 92, height: 94)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottom) {
                Text("40pt map size")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.4)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(.bottom, 6)
            }

            ZStack {
                Circle()
                    .fill(WanderTheme.surfaceSand.color.opacity(0.8))
                    .frame(width: 78, height: 78)

                SocialSignalPin(concept: concept, scale: 1.55)
            }
            .frame(width: 82, height: 94)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(concept.option)
                        .font(.system(size: 11, weight: .black))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .background(concept.isRecommended ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                        .clipShape(Circle())

                    Text(concept.title)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                }

                if concept.isRecommended {
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                } else {
                    Text(concept.mapCaption.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Text(concept.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(WanderTheme.surfaceRaised.color)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    concept.isRecommended ? WanderTheme.terracotta.color.opacity(0.7) : WanderTheme.borderHairline.color,
                    lineWidth: concept.isRecommended ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct RecommendationCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)

            VStack(alignment: .leading, spacing: 3) {
                Text("pick A · split halo")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)

                Text("The pin says both social signals are present, never which one won. Exact names and counts stay one tap away.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(WanderTheme.terracottaTint.color)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SocialPinMapMockup: View {
    let concept: SocialPinConcept

    var body: some View {
        ZStack {
            MockMapBackground()
                .ignoresSafeArea()

            GeometryReader { proxy in
                backgroundPins(in: proxy.size)

                SocialSignalPin(concept: concept, scale: 1.18)
                    .position(x: proxy.size.width * 0.55, y: proxy.size.height * 0.42)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                MockMapHeader()
                MapFilterRow()

                HStack {
                    Spacer()

                    Text("\(concept.option) · \(concept.title)")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.94))
                        .clipShape(Capsule())
                        .shadow(color: WanderTheme.textInk.color.opacity(0.1), radius: 5, y: 2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer()

                MixedSocialPlaceCard()
            }
        }
    }

    @ViewBuilder
    private func backgroundPins(in size: CGSize) -> some View {
        SimpleMapPin(symbol: "fork.knife", ringColor: WanderTheme.pinSocial.color, isDashed: false)
            .position(x: size.width * 0.18, y: size.height * 0.32)

        SimpleMapPin(symbol: "tree.fill", ringColor: WanderTheme.pinYou.color, isDashed: true)
            .position(x: size.width * 0.82, y: size.height * 0.27)

        SimpleMapPin(symbol: "wineglass.fill", ringColor: WanderTheme.pinSocial.color, isDashed: true)
            .position(x: size.width * 0.25, y: size.height * 0.53)
    }
}

private struct MockMapHeader: View {
    var body: some View {
        HStack {
            Text("rec.me")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.terracotta.color)

            Spacer()

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

private struct MapFilterRow: View {
    private let filters = ["YOU", "SOCIAL", "BEEN", "WANNA"]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Text(filter)
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, 13)
                        .frame(height: 44)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.94))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MixedSocialPlaceCard: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(WanderTheme.borderStrong.color)
                .frame(width: 36, height: 4)
                .padding(.top, 9)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Woodcat Coffee")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundStyle(WanderTheme.textInk.color)

                        Text("Coffee · Echo Park")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    Spacer()

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .background(WanderTheme.sunTint.color)
                        .clipShape(Circle())
                }

                HStack(spacing: 8) {
                    SummaryChip(title: "you · been", color: WanderTheme.pinYou.color)
                    SummaryChip(title: "social · 1 been · 1 wanna", color: WanderTheme.pinSocial.color)
                }

                Divider()
                    .overlay(WanderTheme.borderHairline.color)

                SocialProofRow(
                    avatars: [
                        SocialProofAvatar(initials: "RY", color: WanderTheme.avatarRyan.color),
                        SocialProofAvatar(initials: "JL", color: WanderTheme.avatarJames.color)
                    ],
                    title: "You + Joe have been here",
                    isDashed: false
                )

                SocialProofRow(
                    avatars: [
                        SocialProofAvatar(initials: "MP", color: WanderTheme.avatarSofia.color)
                    ],
                    title: "Maya wants to go",
                    isDashed: true
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: WanderTheme.textInk.color.opacity(0.16), radius: 14, y: -3)
    }
}

private struct SummaryChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct SocialProofAvatar {
    let initials: String
    let color: Color
}

private struct SocialProofRow: View {
    let avatars: [SocialProofAvatar]
    let title: String
    let isDashed: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -7) {
                ForEach(Array(avatars.enumerated()), id: \.offset) { _, avatar in
                    Text(avatar.initials)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(avatar.color)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(WanderTheme.surfaceRaised.color, lineWidth: 2)
                        )
                }
            }
            .frame(minWidth: avatars.count > 1 ? 49 : 28, alignment: .leading)

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)

            Spacer()

            Circle()
                .stroke(
                    WanderTheme.pinSocial.color,
                    style: StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        dash: isDashed ? [1.5, 3.5] : []
                    )
                )
                .frame(width: 22, height: 22)
        }
    }
}

private struct SocialSignalPin: View {
    let concept: SocialPinConcept
    var scale: CGFloat = 1

    var body: some View {
        pin
            .frame(width: 44, height: 44)
            .scaleEffect(scale)
            .frame(width: 44 * scale, height: 44 * scale)
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: 5 * scale, y: 2 * scale)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Coffee, Woodcat Coffee. You and Joe have been here. Maya wants to go.")
    }

    @ViewBuilder
    private var pin: some View {
        switch concept {
        case .splitHalo:
            SplitHaloPin()
        case .statusPips:
            StatusPipsPin()
        case .stateLanes:
            StateLanesPin()
        }
    }
}

private struct SplitHaloPin: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.028, to: 0.472)
                .stroke(
                    WanderTheme.pinSocial.color,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 37, height: 37)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.528, to: 0.972)
                .stroke(
                    WanderTheme.pinSocial.color,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1.5, 3.5])
                )
                .frame(width: 37, height: 37)
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(WanderTheme.pinYou.color, lineWidth: 3)
                .frame(width: 30, height: 30)

            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 27, height: 27)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
        }
    }
}

private struct StatusPipsPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 37, height: 37)

            Circle()
                .stroke(WanderTheme.pinYou.color, lineWidth: 3)
                .frame(width: 37, height: 37)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .offset(y: -1)

            Circle()
                .fill(WanderTheme.pinSocial.color)
                .frame(width: 11, height: 11)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 5, weight: .black))
                        .foregroundStyle(Color.white)
                )
                .offset(x: -10.5, y: 13)

            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(
                            WanderTheme.pinSocial.color,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 2])
                        )
                )
                .offset(x: 10.5, y: 13)
        }
    }
}

private struct StateLanesPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 40, height: 40)

            Circle()
                .stroke(
                    WanderTheme.pinSocial.color,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 3.5])
                )
                .frame(width: 38, height: 38)

            Circle()
                .stroke(WanderTheme.pinSocial.color, lineWidth: 2)
                .frame(width: 32, height: 32)

            Circle()
                .stroke(WanderTheme.pinYou.color, lineWidth: 2)
                .frame(width: 26, height: 26)

            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 22, height: 22)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
        }
    }
}

private struct CurrentMixedStatePin: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(WanderTheme.pinSocial.color, lineWidth: 3)
                .frame(width: 40, height: 40)

            Circle()
                .stroke(WanderTheme.pinYou.color, lineWidth: 3)
                .frame(width: 31, height: 31)

            Circle()
                .fill(WanderTheme.surfaceRaised.color)
                .frame(width: 27, height: 27)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
        }
        .frame(width: 44, height: 44)
        .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 4, y: 2)
        .accessibilityLabel("Current behavior. Your Been and social Been appear. Social Wanna is hidden.")
    }
}

private struct SimpleMapPin: View {
    let symbol: String
    let ringColor: Color
    let isDashed: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 34, height: 34)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        ringColor,
                        style: StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            dash: isDashed ? [1.5, 3.5] : []
                        )
                    )
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 4, y: 2)
            .frame(width: 44, height: 44)
    }
}

private struct MockMapPatch: View {
    var body: some View {
        ZStack {
            Color(red: 0.89, green: 0.90, blue: 0.84)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.75, green: 0.84, blue: 0.72))
                .frame(width: 50, height: 34)
                .rotationEffect(.degrees(-13))
                .offset(x: 27, y: -25)

            Rectangle()
                .fill(Color.white.opacity(0.86))
                .frame(width: 120, height: 10)
                .rotationEffect(.degrees(-24))

            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 92, height: 8)
                .rotationEffect(.degrees(54))
                .offset(x: -20, y: 10)
        }
    }
}

private struct MockMapBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Color(red: 0.89, green: 0.90, blue: 0.84)

                RoundedRectangle(cornerRadius: 70)
                    .fill(Color(red: 0.75, green: 0.84, blue: 0.72))
                    .frame(width: size.width * 0.54, height: size.height * 0.24)
                    .rotationEffect(.degrees(-11))
                    .position(x: size.width * 0.88, y: size.height * 0.26)

                Path { path in
                    path.move(to: CGPoint(x: -20, y: size.height * 0.18))
                    path.addCurve(
                        to: CGPoint(x: size.width + 20, y: size.height * 0.49),
                        control1: CGPoint(x: size.width * 0.28, y: size.height * 0.28),
                        control2: CGPoint(x: size.width * 0.72, y: size.height * 0.34)
                    )
                }
                .stroke(Color.white.opacity(0.88), style: StrokeStyle(lineWidth: 15, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.1, y: -20))
                    path.addCurve(
                        to: CGPoint(x: size.width * 0.78, y: size.height * 0.7),
                        control1: CGPoint(x: size.width * 0.2, y: size.height * 0.2),
                        control2: CGPoint(x: size.width * 0.5, y: size.height * 0.45)
                    )
                }
                .stroke(Color.white.opacity(0.82), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: -20, y: size.height * 0.58))
                    path.addCurve(
                        to: CGPoint(x: size.width + 20, y: size.height * 0.16),
                        control1: CGPoint(x: size.width * 0.32, y: size.height * 0.5),
                        control2: CGPoint(x: size.width * 0.72, y: size.height * 0.28)
                    )
                }
                .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 9, lineCap: .round))

                Text("ECHO PARK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(WanderTheme.textMuted.color.opacity(0.58))
                    .position(x: size.width * 0.52, y: size.height * 0.28)

                Text("SILVER LAKE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(WanderTheme.textMuted.color.opacity(0.52))
                    .position(x: size.width * 0.76, y: size.height * 0.5)
            }
        }
    }
}
#endif
