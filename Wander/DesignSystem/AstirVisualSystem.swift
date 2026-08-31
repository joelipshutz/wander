import SwiftUI

enum AstirBrandMode: String, CaseIterable, Equatable {
    case editorial
    case cinemaGold

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AstirBrandMode {
        guard let flagIndex = arguments.firstIndex(of: "-AstirBrandMode") else {
            return .editorial
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .editorial }

        switch arguments[valueIndex].lowercased() {
        case "cinema", "cinemagold", "cinema-gold", "gold":
            return .cinemaGold
        default:
            return AstirBrandMode(rawValue: arguments[valueIndex]) ?? .editorial
        }
    }

    var background: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .cinemaGold: AstirTheme.cinemaBlack.color
        }
    }

    var raisedBackground: Color {
        switch self {
        case .editorial: AstirTheme.inkRaised.color
        case .cinemaGold: AstirTheme.cinemaRaisedBlack.color
        }
    }

    var primaryText: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .cinemaGold: AstirTheme.cinemaGoldLight.color
        }
    }

    var secondaryText: Color {
        switch self {
        case .editorial: AstirTheme.mutedOnInk.color
        case .cinemaGold: AstirTheme.cinemaGoldMuted.color
        }
    }

    var accent: Color {
        switch self {
        case .editorial: AstirTheme.signal.color
        case .cinemaGold: AstirTheme.cinemaGold.color
        }
    }

    var border: Color {
        switch self {
        case .editorial: AstirTheme.lineOnInk.color
        case .cinemaGold: AstirTheme.cinemaGoldDark.color.opacity(0.68)
        }
    }

    var selectedFill: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .cinemaGold: AstirTheme.cinemaGoldDark.color.opacity(0.18)
        }
    }

    var selectedForeground: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .cinemaGold: AstirTheme.cinemaGoldLight.color
        }
    }
}

private struct AstirBrandModeKey: EnvironmentKey {
    static let defaultValue = AstirBrandMode.resolved()
}

extension EnvironmentValues {
    var astirBrandMode: AstirBrandMode {
        get { self[AstirBrandModeKey.self] }
        set { self[AstirBrandModeKey.self] = newValue }
    }
}

enum AstirTheme {
    static let paper = WanderColorToken(name: "astir.color.paper", hex: "#F2E9DB")
    static let ink = WanderColorToken(name: "astir.color.ink", hex: "#141714")
    static let inkRaised = WanderColorToken(name: "astir.color.inkRaised", hex: "#1B1F1B")
    static let signal = WanderColorToken(name: "astir.color.signal", hex: "#F05A3C")
    static let mutedOnInk = WanderColorToken(name: "astir.color.mutedOnInk", hex: "#98958D")
    static let lineOnInk = WanderColorToken(name: "astir.color.lineOnInk", hex: "#464943")

    static let cinemaBlack = WanderColorToken(name: "astir.color.cinemaBlack", hex: "#070706")
    static let cinemaRaisedBlack = WanderColorToken(name: "astir.color.cinemaRaisedBlack", hex: "#11100D")
    static let cinemaGold = WanderColorToken(name: "astir.color.cinemaGold", hex: "#C7A45D")
    static let cinemaGoldLight = WanderColorToken(name: "astir.color.cinemaGoldLight", hex: "#E5CC91")
    static let cinemaGoldMuted = WanderColorToken(name: "astir.color.cinemaGoldMuted", hex: "#8F7A50")
    static let cinemaGoldDark = WanderColorToken(name: "astir.color.cinemaGoldDark", hex: "#765927")

    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("AvenirNext-Medium", size: size).weight(weight)
    }

    static func metadata(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-DemiBold", size: size)
    }
}

private struct AstirCinemaGoldTexture: View {
    var body: some View {
        LinearGradient(
            colors: [
                AstirTheme.cinemaGoldDark.color,
                AstirTheme.cinemaGoldLight.color,
                AstirTheme.cinemaGold.color,
                AstirTheme.cinemaGoldLight.color.opacity(0.88),
                AstirTheme.cinemaGoldDark.color
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Canvas { context, size in
                for index in 0 ..< 34 {
                    let seed = CGFloat((index * 37) % 101) / 101
                    let x = seed * size.width
                    let width = CGFloat(index % 3 + 1) * 0.45
                    let opacity = index.isMultiple(of: 4) ? 0.20 : 0.08
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                        with: .color(Color.white.opacity(opacity))
                    )
                }

                for index in 0 ..< 28 {
                    let xSeed = CGFloat((index * 29) % 97) / 97
                    let ySeed = CGFloat((index * 43) % 89) / 89
                    let diameter = CGFloat(index % 3 + 1) * 0.75
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: xSeed * size.width,
                                y: ySeed * size.height,
                                width: diameter,
                                height: diameter
                            )
                        ),
                        with: .color(Color.black.opacity(0.20))
                    )
                }
            }
            .blendMode(.softLight)
        }
    }
}

struct AstirTexturedAccent<Content: View>: View {
    @Environment(\.astirBrandMode) private var brandMode
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if brandMode == .cinemaGold {
            content
                .foregroundStyle(Color.clear)
                .overlay {
                    AstirCinemaGoldTexture()
                        .mask(content)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            content.foregroundStyle(brandMode.accent)
        }
    }
}

struct AstirMastheadLockup: View {
    @Environment(\.astirBrandMode) private var brandMode
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if brandMode == .cinemaGold {
                AstirTexturedAccent {
                    Text("ASTIR")
                        .font(AstirTheme.wordmark(isCompact ? 18 : 22))
                        .tracking(isCompact ? 4.2 : 5.2)
                }
                AstirTexturedAccent {
                    Text("OCEAN PARK")
                        .font(AstirTheme.metadata(isCompact ? 6.5 : 7.5))
                        .tracking(isCompact ? 1.8 : 2.3)
                }
            } else {
                Text("ASTIR")
                    .font(AstirTheme.wordmark(isCompact ? 18 : 22))
                    .tracking(isCompact ? 4.2 : 5.2)
                Text("OCEAN PARK")
                    .font(AstirTheme.metadata(isCompact ? 6.5 : 7.5))
                    .tracking(isCompact ? 1.8 : 2.3)
            }
        }
        .foregroundStyle(brandMode.primaryText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Astir, Ocean Park")
    }
}

/// Square-edged glass ribbon used as a true overlay so content can scroll
/// beneath it while the Astir mark stays visually anchored.
struct AstirFloatingHeaderSurface<Content: View>: View {
    @Environment(\.astirBrandMode) private var brandMode
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .background(brandMode.background.opacity(0.44))
                .glassEffect(
                    .regular.tint(brandMode.background.opacity(0.72)),
                    in: Rectangle()
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(brandMode.border).frame(height: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial)
                .background(brandMode.background.opacity(0.86))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(brandMode.border).frame(height: 1)
                }
        }
    }
}

struct AstirIconActionButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let systemImage: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(brandMode == .cinemaGold ? brandMode.accent : brandMode.primaryText)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(brandMode.raisedBackground.opacity(0.64))
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(brandMode.border, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

/// Segmented behavior without pill or chip styling. Direction A uses the
/// paper-block selection from the approved mock; Cinema Gold uses a lit gold
/// rule so the accent stays rare.
struct AstirEditorialSegmentedSwitch: View {
    @Environment(\.astirBrandMode) private var brandMode
    let options: [WanderSegmentOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection == option.id
                Button {
                    selection = option.id
                } label: {
                    VStack(spacing: 0) {
                        Text(option.title)
                            .font(AstirTheme.ui(13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                            .foregroundStyle(
                                isSelected
                                    ? brandMode.selectedForeground
                                    : brandMode.secondaryText
                            )
                            .background(
                                isSelected && brandMode == .editorial
                                    ? brandMode.selectedFill
                                    : Color.clear
                            )

                        Rectangle()
                            .fill(
                                isSelected && brandMode == .cinemaGold
                                    ? brandMode.accent
                                    : Color.clear
                            )
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel ?? option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlay {
            Rectangle().stroke(brandMode.border, lineWidth: 1)
        }
    }
}

struct AstirOutlinedSurface: ViewModifier {
    @Environment(\.astirBrandMode) private var brandMode
    var selected = false

    func body(content: Content) -> some View {
        content
            .background(
                selected
                    ? brandMode.selectedFill
                    : brandMode.raisedBackground.opacity(0.76)
            )
            .overlay {
                Rectangle()
                    .stroke(selected ? brandMode.accent : brandMode.border, lineWidth: selected ? 1.5 : 1)
            }
    }
}

extension View {
    func astirOutlinedSurface(selected: Bool = false) -> some View {
        modifier(AstirOutlinedSurface(selected: selected))
    }
}

enum PlaceProfileVisualStyle: Equatable {
    case standard
    case astir
}

private struct PlaceProfileVisualStyleKey: EnvironmentKey {
    static let defaultValue = PlaceProfileVisualStyle.standard
}

extension EnvironmentValues {
    var placeProfileVisualStyle: PlaceProfileVisualStyle {
        get { self[PlaceProfileVisualStyleKey.self] }
        set { self[PlaceProfileVisualStyleKey.self] = newValue }
    }
}
