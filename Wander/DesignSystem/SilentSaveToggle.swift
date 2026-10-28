import SwiftUI

struct SilentSaveToggle: View {
    @Binding var isSilent: Bool
    var hasInvitations = false

    var body: some View {
        Toggle(isOn: $isSilent) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle()
                        .fill(WanderTheme.terracottaTint.color)
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("Silent")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(hasInvitations
                         ? "Skip Notifications For This Save. Visibility Stays The Same. People You Invite Will Still Receive Invitations."
                         : "Skip Notifications For This Save. Visibility Stays The Same.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("save.silentHelp")
                }
            }
        }
        .toggleStyle(.switch)
        .tint(WanderTheme.textInk.color)
        .frame(minHeight: WanderTheme.tapMinimum)
        .accessibilityIdentifier("save.silent")
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
