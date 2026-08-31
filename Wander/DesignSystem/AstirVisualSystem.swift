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

private struct AstirGlassSurface: ViewModifier {
    @Environment(\.astirBrandMode) private var brandMode
    let cornerRadius: CGFloat
    let selected: Bool
    let castsShadow: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(
                        selected
                            ? brandMode.accent.opacity(0.24)
                            : brandMode.raisedBackground.opacity(0.16)
                    ),
                    in: shape
                )
                .overlay {
                    shape.stroke(edgeHighlight, lineWidth: selected ? 1.15 : 0.75)
                }
                .shadow(
                    color: castsShadow ? Color.black.opacity(0.20) : .clear,
                    radius: castsShadow ? 18 : 0,
                    y: castsShadow ? 8 : 0
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(
                    (selected ? brandMode.accent : brandMode.background)
                        .opacity(selected ? 0.16 : 0.48),
                    in: shape
                )
                .overlay {
                    shape.stroke(edgeHighlight, lineWidth: selected ? 1.15 : 0.75)
                }
                .shadow(
                    color: castsShadow ? Color.black.opacity(0.18) : .clear,
                    radius: castsShadow ? 16 : 0,
                    y: castsShadow ? 7 : 0
                )
        }
    }

    private var edgeHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.34),
                brandMode.accent.opacity(selected ? 0.54 : 0.16),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func astirGlassSurface(
        cornerRadius: CGFloat,
        selected: Bool = false,
        castsShadow: Bool = false
    ) -> some View {
        modifier(
            AstirGlassSurface(
                cornerRadius: cornerRadius,
                selected: selected,
                castsShadow: castsShadow
            )
        )
    }
}

/// A true floating overlay. On iOS 26 this uses Apple's liquid-glass renderer;
/// older systems receive a translucent material fallback with the same shape.
struct AstirFloatingHeaderSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .astirGlassSurface(cornerRadius: 30, castsShadow: true)
            .padding(.horizontal, WanderTheme.spacing2)
            .padding(.top, WanderTheme.spacing1)
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
                .astirGlassSurface(cornerRadius: WanderTheme.tapMinimum / 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

/// Segmented behavior without chip styling. Selection is carried by type and a
/// fine illuminated rule rather than a hard filled rectangle.
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
                                    ? brandMode.accent
                                    : brandMode.secondaryText
                            )

                        Rectangle()
                            .fill(isSelected ? brandMode.accent : Color.clear)
                            .frame(height: 1.5)
                            .padding(.horizontal, WanderTheme.spacing3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel ?? option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .astirGlassSurface(cornerRadius: 17)
    }
}

struct AstirOutlinedSurface: ViewModifier {
    @Environment(\.astirBrandMode) private var brandMode
    var selected = false

    func body(content: Content) -> some View {
        content
            .astirGlassSurface(cornerRadius: 16, selected: selected)
    }
}

extension View {
    func astirOutlinedSurface(selected: Bool = false) -> some View {
        modifier(AstirOutlinedSurface(selected: selected))
    }
}

/// Deterministic local fallback composed from the real place photography
/// already bundled in the app. Network/provider photos replace it when ready.
struct AstirPlacePhotoAsset: View {
    let stableKey: String

    var body: some View {
        GeometryReader { proxy in
            if let image = AstirPlacePhotoCropper.image(for: stableKey) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                AstirTheme.inkRaised.color
            }
        }
    }
}

private enum AstirPlacePhotoCropper {
    private static let crops = [
        CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    ]

    static func image(for stableKey: String) -> UIImage? {
        let stableValue = stableKey.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31) &+ Int(scalar.value)
        }
        let crop = crops[abs(stableValue) % crops.count]

        guard let source = UIImage(named: "PlaceCarouselPhotos"),
              let sourceCGImage = source.cgImage
        else { return nil }

        let pixelRect = CGRect(
            x: crop.origin.x * CGFloat(sourceCGImage.width),
            y: crop.origin.y * CGFloat(sourceCGImage.height),
            width: crop.width * CGFloat(sourceCGImage.width),
            height: crop.height * CGFloat(sourceCGImage.height)
        ).integral

        guard let croppedImage = sourceCGImage.cropping(to: pixelRect) else { return nil }
        return UIImage(
            cgImage: croppedImage,
            scale: source.scale,
            orientation: source.imageOrientation
        )
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
