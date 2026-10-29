import SwiftUI

struct FeedAudienceMenu: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var selection: FeedAudience

    var body: some View {
        Menu {
            Picker("Activity audience", selection: $selection) {
                ForEach(FeedAudience.allCases, id: \.self) { audience in
                    Text(audience.title).tag(audience)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(AstirTypography.control)
            .foregroundStyle(brandMode.accentText)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .tint(brandMode.accentText)
        .accessibilityLabel("Activity audience")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("feed.audience")
    }
}

struct FeedAudienceEmptyState: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var audience: FeedAudience

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(audience == .onlyMe ? "No activity from you yet" : "No activity from friends yet")
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.primaryText)
            Text(audience == .onlyMe
                 ? "Your check-ins, Wannas, and lists will appear here."
                 : "Activity from people you follow who also follow you will appear here.")
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.secondaryText)
            Button("Show Everyone") { audience = .everyone }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentText)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
        .accessibilityIdentifier("feed.audience.empty")
    }
}
