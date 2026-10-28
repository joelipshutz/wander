import SwiftUI

struct FeedAudienceMenu: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var selection: FeedAudience

    var body: some View {
        Menu {
            Picker("Activity Audience", selection: $selection) {
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
        .accessibilityLabel("Activity Audience")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("feed.audience")
    }
}

struct FeedAudienceEmptyState: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var audience: FeedAudience

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(audience == .onlyMe ? "No Activity From You Yet" : "No Activity From Friends Yet")
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.primaryText)
            Text(audience == .onlyMe
                 ? "Your Check-Ins, Wannas, And Lists Will Appear Here."
                 : "Activity From People You Follow Who Also Follow You Will Appear Here.")
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
