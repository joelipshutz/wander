import SwiftUI

/// Compact controls for Feed geography, shared filters, and drawer shortcuts.
struct LiveFeedHeader: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let scope: LiveFeedLocationScope
    let summary: String
    let mapActivityCount: String
    let showsReset: Bool
    let eventsAvailable: Bool
    let detent: Int
    let dragGesture: AnyGesture<DragGesture.Value>
    let onScope: (LiveFeedLocationScope) -> Void
    let onReset: () -> Void
    let onEvents: () -> Void
    let onInvite: () -> Void
    let onDetent: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(brand.secondaryText.opacity(0.45))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentShape(Rectangle())
                // The visible, accessible handle owns the native gesture.
                // A separate overlay blocks its hit point and survives an empty header.
                .gesture(dragGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("Activity drawer, \(["collapsed", "half expanded", "expanded"][detent])")
                .accessibilityValue("\(mapActivityCount) on map. Feed: \(summary)")
                .accessibilityAdjustableAction { direction in
                    onDetent(detent + (direction == .increment ? 1 : -1))
                }
                .accessibilityIdentifier("live.drawerHandle")

            Text(mapActivityCount)
                .font(AstirTypography.bodySmall.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("live.map.activityCount")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        scopeMenu
                        Spacer(minLength: 0)
                        inviteButton
                    }
                    if showsReset || eventsAvailable {
                        HStack(spacing: 8) {
                            if eventsAvailable { eventsButton }
                            Spacer(minLength: 0)
                            if showsReset { resetButton }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if eventsAvailable { eventsButton }
                    scopeMenu
                    Spacer(minLength: 0)
                    if showsReset { resetButton }
                    inviteButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .foregroundStyle(brand.primaryText)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.feed.header")
    }

    private var scopeMenu: some View {
        Menu {
            Section("Show in feed") {
                Picker("Feed location", selection: Binding(get: { scope }, set: { onScope($0) })) {
                    ForEach(LiveFeedLocationScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Feed: \(scope.title)").font(AstirTypography.bodySmall.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(brand.accentText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Feed location")
        .accessibilityValue(scope.title)
        .accessibilityHint("Changes feed activity only. \(summary)")
        .accessibilityIdentifier("live.feed.scope.menu")
    }

    private var resetButton: some View {
        Button(action: onReset) {
            Text("Reset filters")
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brand.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Reset filters")
        .accessibilityHint("Clears shared filters and keeps your selected area and activity location")
        .accessibilityIdentifier("live.resetFilters")
    }

    private var eventsButton: some View {
        action("Upcoming events", symbol: "calendar", identifier: "live.utility.events", perform: onEvents)
    }

    private var inviteButton: some View {
        action("Invite people to Astir", symbol: "person.badge.plus", identifier: "live.utility.invite", perform: onInvite)
            .walkthroughTarget(.feedInvite)
    }

    private func action(_ title: String, symbol: String, identifier: String,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
