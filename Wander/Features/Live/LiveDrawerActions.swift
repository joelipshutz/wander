import SwiftUI

/// Separate from the drawer's drag gesture and combined summary accessibility element.
struct LiveDrawerActions: View {
    @Environment(\.astirBrandMode) private var brand

    let eventsAvailable: Bool
    let onEvents: () -> Void
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if eventsAvailable {
                action("Upcoming events", symbol: "calendar", identifier: "live.utility.events", perform: onEvents)
            }
            Spacer(minLength: 0)
            action("Invite people to Astir", symbol: "person.badge.plus", identifier: "live.utility.invite", perform: onInvite)
                .walkthroughTarget(.feedInvite)
        }
        .foregroundStyle(brand.primaryText)
        .buttonStyle(.plain)
    }

    private func action(_ title: String, symbol: String, identifier: String,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
