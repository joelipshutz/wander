import SwiftUI
import UIKit

/// Shared by the recommendation shelf and onboarding. Pending requests show
/// Following immediately; failures restore a tappable retry without a spinner.
struct PeopleFollowButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    @State private var feedback = UIImpactFeedbackGenerator(style: .medium)
    let displayName: String
    let isFollowing: Bool
    let isPending: Bool
    let didFail: Bool
    let action: () -> Void

    private var showsFollowing: Bool { isFollowing || isPending }
    var body: some View {
        Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { action() }
        } label: {
            Text(showsFollowing ? "Following" : didFail ? "Try again" : "Follow")
                .font(AstirTypography.label)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .foregroundStyle(showsFollowing ? brandMode.primaryText : brandMode.accentForeground)
                .background(showsFollowing ? brandMode.recessedBackground : brandMode.accent)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                .contentShape(Rectangle())
                .contentTransition(.identity)
        }
        .buttonStyle(PeopleFollowPressStyle {
            feedback.impactOccurred(intensity: 1)
            feedback.prepare()
        })
        .disabled(showsFollowing)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .onAppear { feedback.prepare() }
        .accessibilityLabel(showsFollowing ? "Following \(displayName)" : didFail ? "Couldn't follow \(displayName). Try again" : "Follow \(displayName)")
    }
}

/// Native Button cancellation keeps either horizontal or vertical scrolling
/// from submitting a follow. No press fade or delayed label transition.
private struct PeopleFollowPressStyle: ButtonStyle {
    let onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, pressed in
            if pressed { onPress() }
        }
    }
}
