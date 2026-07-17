import SwiftUI
import UIKit

struct WanderColorToken: Equatable {
    let name: String
    let hex: String

    var color: Color {
        Color(hex: hex)
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

    init(category: String, size: CGFloat = 18) {
        emoji = WanderPlaceCategory.emoji(for: category)
        self.size = size
    }

    init(assignment: PlaceCategoryAssignment, size: CGFloat = 18) {
        emoji = WanderPlaceCategory.emoji(for: assignment)
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

struct WanderPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isDisabled ? WanderTheme.borderStrong.color : WanderTheme.terracotta.color)
            .foregroundStyle(WanderTheme.textOnAction.color)
            .clipShape(Capsule())
        }
        .disabled(isDisabled)
    }
}

struct WanderAvatar: View {
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
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let fileImage {
            Image(uiImage: fileImage)
                .resizable()
                .scaledToFill()
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    initialsFallback
                @unknown default:
                    initialsFallback
                }
            }
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

    private var fileImage: UIImage? {
        guard let url = avatarURL.flatMap(URL.init(string:)),
              url.isFileURL
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var remoteURL: URL? {
        guard let url = avatarURL.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
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
