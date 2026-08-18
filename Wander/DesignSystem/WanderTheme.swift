import ImageIO
import SwiftUI
import UIKit

struct WanderColorToken: Equatable {
    let name: String
    let hex: String
    private let resolvedColor: Color

    init(name: String, hex: String) {
        self.name = name
        self.hex = hex
        resolvedColor = Color(hex: hex)
    }

    var color: Color {
        resolvedColor
    }

    static func == (lhs: WanderColorToken, rhs: WanderColorToken) -> Bool {
        lhs.name == rhs.name && lhs.hex == rhs.hex
    }
}

enum WanderTheme {
    static let canvasWarm = WanderColorToken(name: "color.canvas.warm", hex: "#F3DFCA")
    static let surfaceBone = WanderColorToken(name: "color.surface.bone", hex: "#FFF7EA")
    static let surfaceRaised = WanderColorToken(name: "color.surface.raised", hex: "#FFFFFF")
    static let surfaceSand = WanderColorToken(name: "color.surface.sand", hex: "#EFE3D0")

    static let textInk = WanderColorToken(name: "color.text.ink", hex: "#2C2118")
    static let textMuted = WanderColorToken(name: "color.text.muted", hex: "#7B6555")
    static let textFaint = WanderColorToken(name: "color.text.faint", hex: "#A8957F")
    static let textOnAction = WanderColorToken(name: "color.text.onAction", hex: "#FFF7EA")

    static let borderHairline = WanderColorToken(name: "color.border.hairline", hex: "#DBC2AA")
    static let borderStrong = WanderColorToken(name: "color.border.strong", hex: "#C9AC8F")

    static let terracotta = WanderColorToken(name: "color.action.terracotta", hex: "#D46F4D")
    static let terracottaDark = WanderColorToken(name: "color.action.terracottaDark", hex: "#A94F35")
    static let terracottaTint = WanderColorToken(name: "color.action.terracottaTint", hex: "#F6E0D2")
    static let sunTint = WanderColorToken(name: "color.surface.sunTint", hex: "#F4E8C9")
    static let skyTint = WanderColorToken(name: "color.surface.skyTint", hex: "#DBEAF1")

    static let pinYou = WanderColorToken(name: "color.pin.you", hex: "#D46F4D")
    static let pinSocial = WanderColorToken(name: "color.pin.social", hex: "#69B8D7")

    static let categoryMoss = WanderColorToken(name: "color.category.moss", hex: "#6F8F5F")
    static let categorySun = WanderColorToken(name: "color.category.sun", hex: "#E3B64B")
    static let categorySage = WanderColorToken(name: "color.category.sage", hex: "#A0B98A")

    static let stateSuccess = WanderColorToken(name: "color.state.success", hex: "#3F8F64")
    static let stateWarning = WanderColorToken(name: "color.state.warning", hex: "#B98528")
    static let stateError = WanderColorToken(name: "color.state.error", hex: "#B84A3A")
    static let stateInfo = WanderColorToken(name: "color.state.info", hex: "#4F8EAD")

    static let avatarJames = WanderColorToken(name: "color.avatar.james", hex: "#D4623F")
    static let avatarRyan = WanderColorToken(name: "color.avatar.ryan", hex: "#6F8F5F")
    static let avatarAndrew = WanderColorToken(name: "color.avatar.andrew", hex: "#E3B64B")
    static let avatarSofia = WanderColorToken(name: "color.avatar.sofia", hex: "#69B8D7")

    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing6: CGFloat = 24
    static let spacing8: CGFloat = 32
    static let spacing12: CGFloat = 48
    static let spacing16: CGFloat = 64

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusSheet: CGFloat = 24
    static let radiusPill: CGFloat = 999

    static let tapMinimum: CGFloat = 44

    static func editorialDisplay(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let allColorTokens: [WanderColorToken] = [
        canvasWarm, surfaceBone, surfaceRaised, surfaceSand,
        textInk, textMuted, textFaint, textOnAction,
        borderHairline, borderStrong,
        terracotta, terracottaDark, terracottaTint, sunTint, skyTint,
        pinYou, pinSocial,
        categoryMoss, categorySun, categorySage,
        stateSuccess, stateWarning, stateError, stateInfo,
        avatarJames, avatarRyan, avatarAndrew, avatarSofia
    ]
}

/// A map-scoped appearance palette. The rest of rec.me intentionally keeps its
/// warm light canvas; this palette only follows the Map setting through the Map
/// view hierarchy.
struct WanderMapAppearance: Equatable {
    static let nightSurface = WanderColorToken(name: "color.map.night.surface", hex: "#171A1C")
    static let nightRaised = WanderColorToken(name: "color.map.night.raised", hex: "#25292C")
    static let nightText = WanderColorToken(name: "color.map.night.text", hex: "#FFF7EA")
    static let nightMuted = WanderColorToken(name: "color.map.night.muted", hex: "#CEC1B4")

    static let light = WanderMapAppearance(isDark: false)
    static let dark = WanderMapAppearance(isDark: true)

    let isDark: Bool

    var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    var primaryText: Color {
        isDark ? Self.nightText.color : WanderTheme.textInk.color
    }

    var secondaryText: Color {
        isDark ? Self.nightMuted.color : WanderTheme.textMuted.color
    }

    var faintText: Color {
        isDark ? Self.nightMuted.color.opacity(0.72) : WanderTheme.textFaint.color
    }

    var surface: Color {
        isDark ? Self.nightSurface.color : WanderTheme.surfaceBone.color
    }

    var raisedSurface: Color {
        isDark ? Self.nightRaised.color : WanderTheme.surfaceRaised.color
    }

    var border: Color {
        isDark ? Color.white.opacity(0.20) : WanderTheme.borderHairline.color
    }

    var accentText: Color {
        isDark ? WanderTheme.terracotta.color : WanderTheme.terracottaDark.color
    }

    var neutralGlassTone: WanderGlassTone {
        isDark ? .darkOverlay : .neutral
    }

    func glassTone(isSelected: Bool) -> WanderGlassTone {
        if isDark {
            return .darkOverlay
        }
        return isSelected ? .selected : .neutral
    }

    var shadow: Color {
        isDark ? Color.black.opacity(0.55) : WanderTheme.textInk.color.opacity(0.12)
    }
}

private struct WanderMapAppearanceKey: EnvironmentKey {
    static let defaultValue = WanderMapAppearance.light
}

extension EnvironmentValues {
    var wanderMapAppearance: WanderMapAppearance {
        get { self[WanderMapAppearanceKey.self] }
        set { self[WanderMapAppearanceKey.self] = newValue }
    }
}

/// Semantic, Dynamic-Type-aware typography roles for the approved native
/// editorial system. Navigation chrome and utility copy stay in the default
/// system design; serif is reserved for named content, editorial headings,
/// and eligible custom content mastheads.
enum WanderTypography {
    static let editorialMasthead = Font.system(.title, design: .serif, weight: .bold)
    static let editorialNamedContent = Font.system(.headline, design: .serif, weight: .bold)
    static let editorialSmallNamedContent = Font.system(.subheadline, design: .serif, weight: .bold)
    static let editorialMajorSectionTitle = Font.system(.title2, design: .serif, weight: .semibold)
    static let editorialDisplay = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let editorialTitle = Font.system(.title2, design: .serif, weight: .bold)
    static let editorialCardTitle = Font.system(.title3, design: .serif, weight: .bold)
    static let editorialCompactTitle = Font.system(.headline, design: .serif, weight: .bold)
    static let editorialSectionTitle = Font.system(.title3, design: .serif, weight: .bold)
    static let editorialRatingDisplay = Font.system(.title2, design: .serif, weight: .bold).monospacedDigit()
    static let editorialRatingSuffix = Font.system(.caption, design: .serif, weight: .semibold).monospacedDigit()

    static let actionScreenTitle = Font.system(.title, design: .default, weight: .bold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let emphasizedBody = Font.system(.body, design: .default, weight: .semibold)
    static let label = Font.system(.subheadline, design: .default, weight: .semibold)
    static let metadata = Font.system(.caption, design: .default, weight: .semibold)
    static let control = Font.system(.body, design: .default, weight: .semibold)
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

struct WanderScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
            .foregroundStyle(WanderTheme.textInk.color)
    }
}

extension View {
    func wanderScreen() -> some View {
        modifier(WanderScreenBackground())
    }
}

struct WanderCategoryEmoji: View {
    private let emoji: String
    let size: CGFloat

    init(
        category: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        rawProviderType: String? = nil,
        name: String? = nil,
        size: CGFloat = 18
    ) {
        emoji = WanderPlaceCategory.emoji(
            for: category,
            subcategory: subcategory,
            cuisine: cuisine,
            rawProviderType: rawProviderType,
            name: name
        )
        self.size = size
    }

    init(
        assignment: PlaceCategoryAssignment,
        cuisine: String? = nil,
        name: String? = nil,
        size: CGFloat = 18
    ) {
        emoji = WanderPlaceCategory.emoji(for: assignment, cuisine: cuisine, name: name)
        self.size = size
    }

    init(emoji: String, size: CGFloat = 18) {
        self.emoji = emoji
        self.size = size
    }

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .lineLimit(1)
            .accessibilityHidden(true)
    }
}

struct WanderChip: View {
    let title: String
    var isSelected = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, WanderTheme.spacing4)
        .frame(minHeight: WanderTheme.tapMinimum)
        .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceSand.color)
        .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
        .clipShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PlaceVisibilityIconPill: View {
    let visibility: PlaceVisibility
    var size: CGFloat = 30
    var includeBackground = true

    var body: some View {
        if visibility.showsTileLockIndicator {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: iconSize, weight: .black))
            }
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, 0)
            .background(includeBackground ? WanderTheme.surfaceSand.color : Color.clear)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .accessibilityLabel("Stealth mode enabled")
        }
    }

    private var iconSize: CGFloat {
        max(12, size * 0.48)
    }
}

struct PlaceVisibilityStealthToggle: View {
    let title: String
    @Binding var visibility: PlaceVisibility
    var showsContainer = true
    var helperCopy: (PlaceVisibility) -> String

    init(
        title: String = "stealth mode",
        visibility: Binding<PlaceVisibility>,
        showsContainer: Bool = true,
        helperCopy: @escaping (PlaceVisibility) -> String = { $0.stealthModeHelperCopy }
    ) {
        self.title = title
        _visibility = visibility
        self.showsContainer = showsContainer
        self.helperCopy = helperCopy
    }

    var body: some View {
        if showsContainer {
            toggleContent
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        } else {
            toggleContent
                .padding(.vertical, WanderTheme.spacing1)
                .padding(.trailing, WanderTheme.spacing1)
        }
    }

    private var toggleContent: some View {
        Toggle(isOn: isPrivate) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle()
                        .fill(WanderTheme.terracottaTint.color)
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(helperCopy(visibility))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(WanderTheme.textInk.color)
        .accessibilityValue(visibility.isStealthModeEnabled ? "Private" : "Not private")
    }

    private var isPrivate: Binding<Bool> {
        Binding(
            get: { visibility.isStealthModeEnabled },
            set: { visibility = PlaceVisibility.visibilityForStealthMode(isPrivate: $0) }
        )
    }
}


struct WanderSegmentOption: Identifiable, Equatable {
    let id: String
    let title: String
}

enum WanderGlassTone: Equatable {
    case neutral
    case selected
    case accent
    case blackAction
    case deepBlackAction
    case lightAction
    case darkOverlay

    var tint: Color? {
        switch self {
        case .neutral:
            nil
        case .selected:
            WanderTheme.terracotta.color.opacity(0.18)
        case .accent:
            WanderTheme.terracotta.color.opacity(0.28)
        case .blackAction:
            Color.black.opacity(0.82)
        case .deepBlackAction:
            Color.black.opacity(0.94)
        case .lightAction:
            Color.white.opacity(0.56)
        case .darkOverlay:
            Color(white: 0.08).opacity(0.78)
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .neutral, .lightAction:
            WanderTheme.textInk.color
        case .selected, .accent:
            WanderTheme.terracottaDark.color
        case .blackAction, .deepBlackAction, .darkOverlay:
            .white
        }
    }

    var fallbackFill: Color {
        switch self {
        case .neutral:
            WanderTheme.surfaceRaised.color.opacity(0.72)
        case .selected:
            WanderTheme.terracottaTint.color.opacity(0.72)
        case .accent:
            WanderTheme.terracottaTint.color.opacity(0.78)
        case .blackAction:
            Color.black.opacity(0.88)
        case .deepBlackAction:
            Color.black.opacity(0.94)
        case .lightAction:
            Color.white.opacity(0.92)
        case .darkOverlay:
            Color.black.opacity(0.82)
        }
    }

    var border: Color {
        switch self {
        case .neutral:
            WanderTheme.surfaceRaised.color.opacity(0.72)
        case .selected, .accent:
            WanderTheme.terracotta.color
        case .blackAction:
            Color.white.opacity(0.24)
        case .deepBlackAction:
            Color.white.opacity(0.22)
        case .lightAction:
            Color.white.opacity(0.90)
        case .darkOverlay:
            Color.white.opacity(0.18)
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .neutral, .blackAction, .deepBlackAction, .lightAction, .darkOverlay:
            1
        case .selected, .accent:
            2
        }
    }
}

enum WanderGlassMaterial: Equatable {
    case regular
    case clear
}

private struct WanderGlassCapsuleModifier: ViewModifier {
    let tone: WanderGlassTone
    let isInteractive: Bool
    let showsBorder: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(tone.tint)
                        .interactive(isInteractive),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            showsBorder ? tone.border : Color.clear,
                            lineWidth: showsBorder ? tone.borderWidth : 0
                        )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(tone.fallbackFill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            showsBorder ? tone.border : Color.clear,
                            lineWidth: showsBorder ? tone.borderWidth : 0
                        )
                }
                .shadow(
                    color: tone == .darkOverlay || tone == .blackAction || tone == .deepBlackAction
                        ? Color.black.opacity(0.34)
                        : WanderTheme.textInk.color.opacity(tone == .neutral ? 0.08 : 0.12),
                    radius: 10,
                    x: 0,
                    y: 5
                )
        }
    }
}

private struct WanderGlassRoundedRectangleModifier: ViewModifier {
    let tone: WanderGlassTone
    let cornerRadius: CGFloat
    let material: WanderGlassMaterial
    let isInteractive: Bool
    let showsBorder: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            let glass: Glass = material == .clear ? .clear : .regular
            content
                .glassEffect(
                    glass
                        .tint(tone.tint)
                        .interactive(isInteractive),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        showsBorder ? tone.border : Color.clear,
                        lineWidth: showsBorder ? tone.borderWidth : 0
                    )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tone.fallbackFill, in: shape)
                .overlay {
                    shape.stroke(
                        showsBorder ? tone.border : Color.clear,
                        lineWidth: showsBorder ? tone.borderWidth : 0
                    )
                }
                .shadow(
                    color: tone == .darkOverlay || tone == .blackAction || tone == .deepBlackAction
                        ? Color.black.opacity(0.34)
                        : WanderTheme.textInk.color.opacity(tone == .neutral ? 0.08 : 0.12),
                    radius: 10,
                    x: 0,
                    y: 5
                )
        }
    }
}

private struct WanderGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tone: WanderGlassTone
    let isInteractive: Bool
    let showsBorder: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(tone.tint)
                        .interactive(isInteractive),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        showsBorder ? tone.border : Color.clear,
                        lineWidth: showsBorder ? tone.borderWidth : 0
                    )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tone.fallbackFill, in: shape)
                .overlay {
                    shape.stroke(
                        showsBorder ? tone.border : Color.clear,
                        lineWidth: showsBorder ? tone.borderWidth : 0
                    )
                }
                .shadow(
                    color: tone == .darkOverlay
                        ? Color.black.opacity(0.34)
                        : WanderTheme.textInk.color.opacity(tone == .neutral ? 0.08 : 0.12),
                    radius: isInteractive ? 6 : 14,
                    x: 0,
                    y: isInteractive ? 3 : 7
                )
        }
    }
}

private struct WanderSelectedGlassModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.wanderGlassCapsule(tone: .selected)
        } else {
            content
        }
    }
}

extension View {
    func wanderGlassCapsule(
        tone: WanderGlassTone = .neutral,
        interactive: Bool = true,
        showsBorder: Bool = true
    ) -> some View {
        modifier(
            WanderGlassCapsuleModifier(
                tone: tone,
                isInteractive: interactive,
                showsBorder: showsBorder
            )
        )
    }

    func wanderGlassPanel(
        cornerRadius: CGFloat = WanderTheme.radiusLarge,
        tone: WanderGlassTone = .neutral,
        interactive: Bool = false,
        showsBorder: Bool = true
    ) -> some View {
        modifier(
            WanderGlassPanelModifier(
                cornerRadius: cornerRadius,
                tone: tone,
                isInteractive: interactive,
                showsBorder: showsBorder
            )
        )
    }

    func wanderGlassRoundedRectangle(
        tone: WanderGlassTone = .neutral,
        cornerRadius: CGFloat = WanderTheme.radiusLarge,
        material: WanderGlassMaterial = .regular,
        interactive: Bool = true,
        showsBorder: Bool = true
    ) -> some View {
        modifier(
            WanderGlassRoundedRectangleModifier(
                tone: tone,
                cornerRadius: cornerRadius,
                material: material,
                isInteractive: interactive,
                showsBorder: showsBorder
            )
        )
    }
}

struct WanderGlassActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var tone: WanderGlassTone = .accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .black))
                .frame(width: 44, height: 44)
                .foregroundStyle(tone.foregroundStyle)
                .contentShape(Circle())
                .wanderGlassCapsule(tone: tone)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

struct WanderGlassHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                Text(title)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)

                Spacer(minLength: WanderTheme.spacing2)
                accessory
            }
            .padding(.leading, WanderTheme.spacing4)
            .padding(.trailing, WanderTheme.spacing2)
            .padding(.vertical, WanderTheme.spacing2)
            .wanderGlassPanel(cornerRadius: WanderTheme.radiusLarge)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .padding(.horizontal, WanderTheme.spacing2)
            }
        }
    }
}

struct WanderGlassSegmentedSwitch: View {
    let options: [WanderSegmentOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option.id
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(
                            isSelected
                                ? WanderTheme.terracottaDark.color
                                : WanderTheme.textMuted.color
                        )
                        .contentShape(Capsule())
                        .modifier(WanderSelectedGlassModifier(isSelected: isSelected))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .wanderGlassCapsule(interactive: false, showsBorder: false)
    }
}

struct WanderSegmentedSwitch: View {
    let options: [WanderSegmentOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selection == option.id ? WanderTheme.surfaceRaised.color : Color.clear)
                        .foregroundStyle(selection == option.id ? WanderTheme.textInk.color : WanderTheme.textMuted.color)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selection == option.id ? WanderTheme.terracotta.color : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.id ? .isSelected : [])
            }
        }
        .padding(4)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color.opacity(0.65), lineWidth: 1))
    }
}

enum WanderPrimaryButtonTone: Equatable {
    case brand
    case espressoConfirmation

    var glassTone: WanderGlassTone? {
        switch self {
        case .brand:
            nil
        case .espressoConfirmation:
            .deepBlackAction
        }
    }
}

private struct WanderPrimaryButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WanderPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    var tone: WanderPrimaryButtonTone = .brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let glassTone = tone.glassTone {
                label
                    .foregroundStyle(glassTone.foregroundStyle)
                    .wanderGlassRoundedRectangle(
                        tone: glassTone,
                        cornerRadius: WanderTheme.radiusLarge,
                        interactive: !isDisabled,
                        showsBorder: false
                    )
                    .opacity(isDisabled ? 0.68 : 1)
            } else {
                label
                    .background(isDisabled ? WanderTheme.borderStrong.color : WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(WanderPrimaryButtonPressStyle())
        .disabled(isDisabled)
    }

    private var label: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.system(size: 16, weight: .bold))
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

struct WanderAvatarLocalFileRevision: Hashable, Sendable {
    let modificationTimeBitPattern: UInt64
    let fileSize: UInt64
    let fileNumber: UInt64

    init?(url: URL, fileManager: FileManager = .default) {
        guard url.isFileURL,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            return nil
        }

        let modificationDate = attributes[.modificationDate] as? Date
        modificationTimeBitPattern = (
            modificationDate?.timeIntervalSinceReferenceDate ?? 0
        ).bitPattern
        self.fileSize = fileSize
        fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

struct WanderAvatarImageRequest: Hashable, Sendable {
    let url: URL
    let targetPixelSize: Int
    let localFileRevision: WanderAvatarLocalFileRevision?

    init?(avatarURL: String?, targetPixelSize: Int) {
        guard targetPixelSize > 0,
              let url = avatarURL.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              url.isFileURL || scheme == "http" || scheme == "https"
        else {
            return nil
        }

        self.url = url
        self.targetPixelSize = targetPixelSize
        localFileRevision = WanderAvatarLocalFileRevision(url: url)
    }
}

final class WanderAvatarDecodedImage: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    var pixelSize: CGSize {
        guard let cgImage = image.cgImage else { return .zero }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    var estimatedByteCost: Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

actor WanderAvatarImagePipeline {
    static let shared = WanderAvatarImagePipeline()

    typealias DataLoader = @Sendable (URL) async -> Data?

    private struct CacheKey: Hashable, Sendable {
        let url: URL
        let targetPixelSize: Int
        let localFileRevision: WanderAvatarLocalFileRevision?
    }

    private struct CacheEntry {
        let image: WanderAvatarDecodedImage
        let byteCost: Int
    }

    private struct InFlightEntry {
        let id: UUID
        let task: Task<WanderAvatarDecodedImage?, Never>
    }

    private let countLimit: Int
    private let totalCostLimit: Int
    private let dataLoader: DataLoader
    private var entries: [CacheKey: CacheEntry] = [:]
    private var recency: [CacheKey] = []
    private var inFlight: [CacheKey: InFlightEntry] = [:]
    private var totalCost = 0

    init(
        countLimit: Int = 128,
        totalCostLimit: Int = 32 * 1_024 * 1_024,
        session: URLSession = .shared
    ) {
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
        dataLoader = { url in
            if url.isFileURL {
                return try? Data(contentsOf: url, options: [.mappedIfSafe])
            }

            do {
                let (data, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200..<300).contains(httpResponse.statusCode) else { return nil }
                }
                return data
            } catch {
                return nil
            }
        }
    }

    init(
        countLimit: Int = 128,
        totalCostLimit: Int = 32 * 1_024 * 1_024,
        dataLoader: @escaping DataLoader
    ) {
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
        self.dataLoader = dataLoader
    }

    func image(for request: WanderAvatarImageRequest) async -> WanderAvatarDecodedImage? {
        guard !Task.isCancelled else { return nil }

        let revision: WanderAvatarLocalFileRevision?
        if request.url.isFileURL {
            guard let fileRevision = WanderAvatarLocalFileRevision(url: request.url) else {
                return nil
            }
            revision = fileRevision
        } else {
            revision = nil
        }

        let key = CacheKey(
            url: request.url,
            targetPixelSize: request.targetPixelSize,
            localFileRevision: revision
        )
        if let cached = cachedImage(for: key) {
            return cached
        }

        let entry: InFlightEntry
        if let existing = inFlight[key] {
            entry = existing
        } else {
            let id = UUID()
            let dataLoader = self.dataLoader
            let url = request.url
            let targetPixelSize = request.targetPixelSize
            let task = Task<WanderAvatarDecodedImage?, Never>.detached(priority: .utility) {
                guard let data = await dataLoader(url),
                      !Task.isCancelled,
                      let image = Self.downsampledImage(
                          from: data,
                          targetPixelSize: targetPixelSize
                      ),
                      !Task.isCancelled
                else {
                    return nil
                }
                return WanderAvatarDecodedImage(image: image)
            }
            let newEntry = InFlightEntry(id: id, task: task)
            inFlight[key] = newEntry
            entry = newEntry
        }

        let decodedImage = await entry.task.value
        if inFlight[key]?.id == entry.id {
            inFlight.removeValue(forKey: key)
            if let decodedImage {
                insert(decodedImage, for: key)
            }
        }
        guard !Task.isCancelled else { return nil }
        return decodedImage
    }

    nonisolated private static func downsampledImage(
        from data: Data,
        targetPixelSize: Int
    ) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func cachedImage(for key: CacheKey) -> WanderAvatarDecodedImage? {
        guard let entry = entries[key] else { return nil }
        markRecentlyUsed(key)
        return entry.image
    }

    private func insert(_ image: WanderAvatarDecodedImage, for key: CacheKey) {
        if let previousEntry = entries.removeValue(forKey: key) {
            totalCost -= previousEntry.byteCost
        }
        recency.removeAll { $0 == key }

        let entry = CacheEntry(
            image: image,
            byteCost: max(1, image.estimatedByteCost)
        )
        entries[key] = entry
        recency.append(key)
        totalCost += entry.byteCost

        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let oldestKey = recency.first else { break }
            recency.removeFirst()
            if let removedEntry = entries.removeValue(forKey: oldestKey) {
                totalCost -= removedEntry.byteCost
            }
        }
    }

    private func markRecentlyUsed(_ key: CacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

struct WanderAvatar: View {
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?

    let initials: String
    var avatarURL: String?
    var size: CGFloat = 44
    var color = WanderTheme.terracotta.color

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
            .task(id: imageRequest) {
                loadedImage = nil
                guard let imageRequest else { return }

                let decodedImage = await WanderAvatarImagePipeline.shared.image(
                    for: imageRequest
                )
                guard !Task.isCancelled else { return }
                loadedImage = decodedImage?.image
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let loadedImage {
            Image(uiImage: loadedImage)
                .resizable()
                .scaledToFill()
        } else {
            initialsFallback
        }
    }

    private var initialsFallback: some View {
        Text(initials)
            .font(.system(size: max(12, size * 0.34), weight: .black))
            .foregroundStyle(WanderTheme.textOnAction.color)
            .frame(width: size, height: size)
    }

    private var imageRequest: WanderAvatarImageRequest? {
        let requestedPixels = size * displayScale
        guard requestedPixels.isFinite, requestedPixels > 0 else { return nil }
        return WanderAvatarImageRequest(
            avatarURL: avatarURL,
            targetPixelSize: min(2_048, max(1, Int(ceil(requestedPixels))))
        )
    }
}

extension LocalProfile {
    var initials: String {
        displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
