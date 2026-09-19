import SwiftUI
import UIKit
struct WanderColorToken: Equatable {
    let name: String
    let hex: String
    let darkHex: String?
    private let resolvedColor: Color

    init(name: String, hex: String, darkHex: String? = nil) {
        self.name = name
        self.hex = hex
        self.darkHex = darkHex
        if let darkHex {
            resolvedColor = Color(
                uiColor: UIColor { traits in
                    UIColor(wanderHex: traits.userInterfaceStyle == .dark ? darkHex : hex)
                }
            )
        } else {
            resolvedColor = Color(hex: hex)
        }
    }

    var color: Color {
        resolvedColor
    }

    static func == (lhs: WanderColorToken, rhs: WanderColorToken) -> Bool {
        lhs.name == rhs.name && lhs.hex == rhs.hex && lhs.darkHex == rhs.darkHex
    }
}

enum WanderTheme {
    static let canvasWarm = WanderColorToken(
        name: "color.canvas.warm",
        hex: "#F2E9DB",
        darkHex: "#141714"
    )
    static let surfaceBone = WanderColorToken(
        name: "color.surface.bone",
        hex: "#FBF6ED",
        darkHex: "#1B1F1B"
    )
    static let surfaceRaised = WanderColorToken(
        name: "color.surface.raised",
        hex: "#FFF9F0",
        darkHex: "#222622"
    )
    static let surfaceSand = WanderColorToken(
        name: "color.surface.sand",
        hex: "#E8DED0",
        darkHex: "#101210"
    )

    static let textInk = WanderColorToken(
        name: "color.text.ink",
        hex: "#141714",
        darkHex: "#F2E9DB"
    )
    static let textMuted = WanderColorToken(
        name: "color.text.muted",
        hex: "#655F57",
        darkHex: "#98958D"
    )
    static let textFaint = WanderColorToken(
        name: "color.text.faint",
        hex: "#8D877E",
        darkHex: "#74776F"
    )
    static let textOnAction = WanderColorToken(
        name: "color.text.onAction",
        hex: "#141714",
        darkHex: "#141714"
    )

    static let borderHairline = WanderColorToken(
        name: "color.border.hairline",
        hex: "#8A8176",
        darkHex: "#74786F"
    )
    static let borderStrong = WanderColorToken(
        name: "color.border.strong",
        hex: "#A99F91",
        darkHex: "#686C63"
    )

    static let terracotta = WanderColorToken(
        name: "color.action.terracotta",
        hex: "#F05A3C",
        darkHex: "#F05A3C"
    )
    static let terracottaDark = WanderColorToken(
        name: "color.action.terracottaDark",
        hex: "#C9422A",
        darkHex: "#FF8069"
    )
    static let terracottaTint = WanderColorToken(
        name: "color.action.terracottaTint",
        hex: "#FBE0D9",
        darkHex: "#3A211B"
    )
    static let sunTint = WanderColorToken(
        name: "color.surface.sunTint",
        hex: "#F4E8C9",
        darkHex: "#312B1A"
    )
    static let skyTint = WanderColorToken(
        name: "color.surface.skyTint",
        hex: "#DBEAF1",
        darkHex: "#172A32"
    )

    static let pinYou = WanderColorToken(name: "color.pin.you", hex: "#F05A3C")
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

/// Compatibility palette for Map-specific components. Chrome follows the live
/// adaptive Astir appearance; the separate Map setting now affects MapKit tiles
/// only, so it cannot introduce a third product theme.
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

private extension UIColor {
    convenience init(wanderHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

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

    /// Contrast-safe accent for labels and symbols drawn directly on the
    /// app surface. Filled controls continue to use `accent`.
    var accentText: Color {
        switch self {
        case .editorial: AstirTheme.signal.color
        case .editorialLight: AstirTheme.signalOnPaper.color
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
    static let signalOnPaper = WanderColorToken(name: "astir.color.signalOnPaper", hex: "#B23620")
    static let mutedOnInk = WanderColorToken(name: "astir.color.mutedOnInk", hex: "#98958D")
    static let mutedOnPaper = WanderColorToken(name: "astir.color.mutedOnPaper", hex: "#655F57")
    static let lineOnInk = WanderColorToken(name: "astir.color.lineOnInk", hex: "#74786F")
    static let lineOnPaper = WanderColorToken(name: "astir.color.lineOnPaper", hex: "#8A8176")

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

