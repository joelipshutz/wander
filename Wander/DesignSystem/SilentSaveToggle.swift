import SwiftUI

struct SilentSaveToggle: View {
    @Binding var isSilent: Bool
    var hasInvitations = false

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Toggle("Silent", isOn: $isSilent)
                .toggleStyle(.switch)
                .tint(WanderTheme.textInk.color)
                .frame(minHeight: WanderTheme.tapMinimum)
                .accessibilityIdentifier("save.silent")
            Text(hasInvitations
                 ? "Skip notifications for this save. Visibility stays the same. People you invite will still receive invitations."
                 : "Skip notifications for this save. Visibility stays the same.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("save.silentHelp")
        }
    }
}
