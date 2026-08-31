import SwiftUI

enum AstirBrandMode: String, CaseIterable, Equatable {
    case editorial
    case editorialLight
    case cinemaGold

    static func launchOverride(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AstirBrandMode? {
        guard let flagIndex = arguments.firstIndex(of: "-AstirBrandMode") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }

        switch arguments[valueIndex].lowercased() {
        case "editoriallight", "editorial-light", "light", "paper":
            return .editorialLight
        case "cinema", "cinemagold", "cinema-gold", "gold":
            return .cinemaGold
        default:
            return AstirBrandMode(rawValue: arguments[valueIndex])
        }
    }

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AstirBrandMode {
        launchOverride(from: arguments) ?? .editorial
    }

    var background: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .editorialLight: AstirTheme.paper.color
        case .cinemaGold: AstirTheme.cinemaBlack.color
        }
    }

    var raisedBackground: Color {
        switch self {
        case .editorial: AstirTheme.inkRaised.color
        case .editorialLight: AstirTheme.paperRaised.color
        case .cinemaGold: AstirTheme.cinemaRaisedBlack.color
        }
    }

    var primaryText: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .editorialLight: AstirTheme.ink.color
        case .cinemaGold: AstirTheme.cinemaIvory.color
        }
    }

    var secondaryText: Color {
        switch self {
        case .editorial: AstirTheme.mutedOnInk.color
        case .editorialLight: AstirTheme.mutedOnPaper.color
        case .cinemaGold: AstirTheme.cinemaBrassMuted.color
        }
    }

    var accent: Color {
        switch self {
        case .editorial: AstirTheme.signal.color
        case .editorialLight: AstirTheme.signal.color
        case .cinemaGold: AstirTheme.cinemaBrass.color
        }
    }

    var border: Color {
        switch self {
        case .editorial: AstirTheme.lineOnInk.color
        case .editorialLight: AstirTheme.lineOnPaper.color
        case .cinemaGold: AstirTheme.cinemaBrassDark.color.opacity(0.72)
        }
    }

    var selectedFill: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .editorialLight: AstirTheme.ink.color
        case .cinemaGold: AstirTheme.cinemaBrassDark.color.opacity(0.20)
        }
    }

    var selectedForeground: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .editorialLight: AstirTheme.paper.color
        case .cinemaGold: AstirTheme.cinemaIvory.color
        }
    }

    var prefersDarkInterface: Bool {
        self != .editorialLight
    }

    var usesCinemaGoldTexture: Bool {
        self == .cinemaGold
    }

    var accentForeground: Color {
        usesCinemaGoldTexture ? AstirTheme.cinemaBlack.color : AstirTheme.ink.color
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
    static let paperRaised = WanderColorToken(name: "astir.color.paperRaised", hex: "#FBF6ED")
    static let ink = WanderColorToken(name: "astir.color.ink", hex: "#141714")
    static let inkRaised = WanderColorToken(name: "astir.color.inkRaised", hex: "#1B1F1B")
    static let signal = WanderColorToken(name: "astir.color.signal", hex: "#F05A3C")
    static let mutedOnInk = WanderColorToken(name: "astir.color.mutedOnInk", hex: "#98958D")
    static let mutedOnPaper = WanderColorToken(name: "astir.color.mutedOnPaper", hex: "#6F6A62")
    static let lineOnInk = WanderColorToken(name: "astir.color.lineOnInk", hex: "#464943")
    static let lineOnPaper = WanderColorToken(name: "astir.color.lineOnPaper", hex: "#C9BFB0")

    static let cinemaBlack = WanderColorToken(name: "astir.color.cinemaBlack", hex: "#070706")
    static let cinemaRaisedBlack = WanderColorToken(name: "astir.color.cinemaRaisedBlack", hex: "#11100D")
    // Retained as the original exploration reference. The live cinema mode
    // uses the less-yellow brass system below.
    static let cinemaGold = WanderColorToken(name: "astir.color.cinemaGold", hex: "#C7A45D")
    static let cinemaIvory = WanderColorToken(name: "astir.color.cinemaIvory", hex: "#E9E1D5")
    static let cinemaBrass = WanderColorToken(name: "astir.color.cinemaBrass", hex: "#A77A46")
    static let cinemaBrassLight = WanderColorToken(name: "astir.color.cinemaBrassLight", hex: "#C4A276")
    static let cinemaBrassMuted = WanderColorToken(name: "astir.color.cinemaBrassMuted", hex: "#7D7468")
    static let cinemaBrassDark = WanderColorToken(name: "astir.color.cinemaBrassDark", hex: "#563D26")

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
                AstirTheme.cinemaBrassDark.color,
                AstirTheme.cinemaBrassLight.color,
                AstirTheme.cinemaBrass.color,
                AstirTheme.cinemaBrassLight.color.opacity(0.82),
                AstirTheme.cinemaBrassDark.color
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
        if brandMode.usesCinemaGoldTexture {
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
            if brandMode.usesCinemaGoldTexture {
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
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 8 : 10)
        .astirGlassSurface(cornerRadius: isCompact ? 15 : 18, castsShadow: true)
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
            let glass = selected
                ? Glass.regular.tint(brandMode.accent.opacity(0.24))
                : Glass.regular.tint(brandMode.background.opacity(0.035))

            content
                .glassEffect(
                    glass,
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

/// Positions independently floating controls without placing another glass
/// slab behind the group. A frameless material field lightly softens moving
/// content beneath the controls, then fades away without reading as a card.
struct AstirFloatingHeaderSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, WanderTheme.spacing2)
            .padding(.top, WanderTheme.spacing1)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                AstirHeaderBlurBackdrop()
                    .padding(.horizontal, -WanderTheme.spacing2)
                    .padding(.top, -72)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

private struct AstirHeaderBlurBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        Group {
            if reduceTransparency {
                brandMode.background.opacity(0.94)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(brandMode.prefersDarkInterface ? 0.34 : 0.42)
                    .overlay(brandMode.background.opacity(brandMode.prefersDarkInterface ? 0.04 : 0.025))
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.94), location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
                .foregroundStyle(brandMode.usesCinemaGoldTexture ? brandMode.accent : brandMode.primaryText)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .astirGlassSurface(cornerRadius: WanderTheme.tapMinimum / 2, castsShadow: true)
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
        .astirGlassSurface(cornerRadius: 17, castsShadow: true)
    }
}

struct AstirOutlinedSurface: ViewModifier {
    @Environment(\.astirBrandMode) private var brandMode
    var selected = false
    var castsShadow = false

    func body(content: Content) -> some View {
        content
            .astirGlassSurface(
                cornerRadius: 16,
                selected: selected,
                castsShadow: castsShadow
            )
    }
}

extension View {
    func astirOutlinedSurface(
        selected: Bool = false,
        castsShadow: Bool = false
    ) -> some View {
        modifier(
            AstirOutlinedSurface(
                selected: selected,
                castsShadow: castsShadow
            )
        )
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
