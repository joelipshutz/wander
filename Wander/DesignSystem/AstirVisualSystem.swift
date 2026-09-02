import SwiftUI

enum AstirBrandMode: String, CaseIterable, Equatable {
    case editorial
    case editorialLight

    var background: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .editorialLight: AstirTheme.paper.color
        }
    }

    var raisedBackground: Color {
        switch self {
        case .editorial: AstirTheme.inkRaised.color
        case .editorialLight: AstirTheme.paperRaised.color
        }
    }

    /// A quieter well for fields and grouped rows. This stays within the same
    /// paper/ink family instead of reintroducing the legacy beige surfaces.
    var recessedBackground: Color {
        switch self {
        case .editorial: AstirTheme.inkRecessed.color
        case .editorialLight: AstirTheme.paperRecessed.color
        }
    }

    var primaryText: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .editorialLight: AstirTheme.ink.color
        }
    }

    var secondaryText: Color {
        switch self {
        case .editorial: AstirTheme.mutedOnInk.color
        case .editorialLight: AstirTheme.mutedOnPaper.color
        }
    }

    var accent: Color {
        switch self {
        case .editorial: AstirTheme.signal.color
        case .editorialLight: AstirTheme.signal.color
        }
    }

    var border: Color {
        switch self {
        case .editorial: AstirTheme.lineOnInk.color
        case .editorialLight: AstirTheme.lineOnPaper.color
        }
    }

    var selectedFill: Color {
        switch self {
        case .editorial: AstirTheme.paper.color
        case .editorialLight: AstirTheme.ink.color
        }
    }

    var selectedForeground: Color {
        switch self {
        case .editorial: AstirTheme.ink.color
        case .editorialLight: AstirTheme.paper.color
        }
    }

    var prefersDarkInterface: Bool {
        self == .editorial
    }

    var accentForeground: Color {
        AstirTheme.ink.color
    }

    var accentWash: Color {
        accent.opacity(prefersDarkInterface ? 0.18 : 0.12)
    }
}

private struct AstirBrandModeKey: EnvironmentKey {
    static let defaultValue = AstirBrandMode.editorial
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
    static let paperRecessed = WanderColorToken(name: "astir.color.paperRecessed", hex: "#E8DED0")
    static let ink = WanderColorToken(name: "astir.color.ink", hex: "#141714")
    static let inkRaised = WanderColorToken(name: "astir.color.inkRaised", hex: "#1B1F1B")
    static let inkRecessed = WanderColorToken(name: "astir.color.inkRecessed", hex: "#101210")
    static let signal = WanderColorToken(name: "astir.color.signal", hex: "#F05A3C")
    static let mutedOnInk = WanderColorToken(name: "astir.color.mutedOnInk", hex: "#98958D")
    static let mutedOnPaper = WanderColorToken(name: "astir.color.mutedOnPaper", hex: "#6F6A62")
    static let lineOnInk = WanderColorToken(name: "astir.color.lineOnInk", hex: "#464943")
    static let lineOnPaper = WanderColorToken(name: "astir.color.lineOnPaper", hex: "#C9BFB0")

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

/// Semantic roles shared by production Astir screens. Fixed-size helpers above
/// remain for the exploration shell and wordmark; product UI should use these
/// roles so Dynamic Type and hierarchy stay consistent across surfaces.
enum AstirTypography {
    static let screenTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let sheetTitle = Font.system(.title2, design: .serif).weight(.semibold)
    static let sectionTitle = Font.system(.title3, design: .serif).weight(.semibold)
    static let metricDisplay = Font.system(.title2, design: .serif, weight: .bold).monospacedDigit()
    static let metricSuffix = Font.system(.caption, design: .serif, weight: .semibold).monospacedDigit()
    static let cardTitle = Font.custom("AvenirNext-DemiBold", size: 16, relativeTo: .body)
    static let body = Font.custom("AvenirNext-Regular", size: 16, relativeTo: .body)
    static let bodySmall = Font.custom("AvenirNext-Regular", size: 14, relativeTo: .subheadline)
    static let control = Font.custom("AvenirNext-DemiBold", size: 15, relativeTo: .body)
    static let label = Font.custom("AvenirNext-DemiBold", size: 13, relativeTo: .caption)
    static let caption = Font.custom("AvenirNext-Medium", size: 12, relativeTo: .caption)
    static let metadata = Font.custom(
        "AvenirNextCondensed-DemiBold",
        size: 12,
        relativeTo: .caption
    )
}

private struct AstirAdaptiveBrandModeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(
            \.astirBrandMode,
            colorScheme == .dark ? AstirBrandMode.editorial : .editorialLight
        )
    }
}

private struct AstirScreenSurface: ViewModifier {
    @Environment(\.astirBrandMode) private var brandMode

    func body(content: Content) -> some View {
        content
            .foregroundStyle(brandMode.primaryText)
            .background(brandMode.background.ignoresSafeArea())
    }
}

extension View {
    func astirAdaptiveBrandMode() -> some View {
        modifier(AstirAdaptiveBrandModeModifier())
    }

    func astirScreen() -> some View {
        modifier(AstirScreenSurface())
    }
}

struct AstirMastheadLockup: View {
    @Environment(\.astirBrandMode) private var brandMode
    var isCompact = false
    var presentation: AstirMastheadPresentation = .glass

    var body: some View {
        masthead
            .modifier(
                AstirMastheadPresentationModifier(
                    presentation: presentation,
                    isCompact: isCompact
                )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Astir, Ocean Park")
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ASTIR")
                .font(AstirTheme.wordmark(isCompact ? 18 : 22))
                .tracking(isCompact ? 4.2 : 5.2)
            Text("OCEAN PARK")
                .font(AstirTheme.metadata(isCompact ? 6.5 : 7.5))
                .tracking(isCompact ? 1.8 : 2.3)
        }
        .foregroundStyle(brandMode.primaryText)
    }
}

enum AstirMastheadPresentation {
    case glass
    case localizedBlur
}

private struct AstirMastheadPresentationModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.astirBrandMode) private var brandMode
    let presentation: AstirMastheadPresentation
    let isCompact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .glass:
            content
                .padding(.horizontal, isCompact ? 12 : 14)
                .padding(.vertical, isCompact ? 8 : 10)
                .astirGlassSurface(cornerRadius: isCompact ? 15 : 18, castsShadow: true)
        case .localizedBlur:
            content
                .padding(.horizontal, isCompact ? 7 : 9)
                .padding(.vertical, isCompact ? 5 : 7)
                .background {
                    Rectangle()
                        .fill(
                            reduceTransparency
                                ? AnyShapeStyle(brandMode.background.opacity(0.82))
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                        .mask {
                            RadialGradient(
                                colors: [.black, .black.opacity(0.72), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: isCompact ? 46 : 58
                            )
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
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
                .foregroundStyle(brandMode.primaryText)
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
                            .font(AstirTypography.label)
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
