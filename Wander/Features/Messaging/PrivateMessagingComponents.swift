import SwiftUI

/// Keep the in-memory draft while obscuring private content in inactive-scene
/// snapshots. Replay masking remains separate from this on-screen cover.
struct PrivateMessagingInactiveCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brand

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                ZStack {
                    brand.background.ignoresSafeArea()
                    Label("Private messages", systemImage: "lock.fill")
                        .font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                }
                .accessibilityIdentifier("messaging.inactiveCover")
            }
        }
    }
}

@MainActor
protocol PrivateMessageSimulationIdentifying {
    var isSimulation: Bool { get }
}

struct PrivateMessagingSimulationLabel: View {
    @Environment(\.astirBrandMode) private var brand
    var body: some View {
        Label("Demo messages · nothing is delivered", systemImage: "testtube.2")
            .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("messaging.simulation")
    }
}

/// Messaging surfaces use existing Astir roles; private content is masked at
/// the individual content boundary, including conversation previews.
struct PrivateMessagingPrivacyLabel: View {
    @Environment(\.astirBrandMode) private var brand
    var body: some View {
        Label("Private conversation", systemImage: "lock.fill")
            .font(AstirTypography.caption)
            .foregroundStyle(brand.secondaryText)
            .accessibilityLabel("Private conversation between you and this person")
    }
}

struct PrivateMessagingNotice: View {
    @Environment(\.astirBrandMode) private var brand
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.title, weight: .light))
                .foregroundStyle(brand.accentText)
                .accessibilityHidden(true)
            Text(title).font(AstirTypography.sheetTitle).foregroundStyle(brand.primaryText)
            Text(detail).font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AstirTypography.control)
                    .foregroundStyle(brand.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("messaging.retry")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PrivateMessagingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AstirTypography.control)
            .foregroundStyle(brand.accentForeground)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 14)
            .background(brand.accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PrivateMessagingPersonLabel: View {
    @Environment(\.astirBrandMode) private var brand
    let name: String
    var avatarURL: String?
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            WanderAvatar(initials: initials, avatarURL: avatarURL, size: compact ? 36 : 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PrivateMessagingPrivacyLabel()
            }
        }
        .sessionReplayMasked()
    }

    private var initials: String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
