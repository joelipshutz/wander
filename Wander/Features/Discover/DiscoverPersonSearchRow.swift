import SwiftUI

struct DiscoverPersonSearchRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let profile: ProfileShell
    let isFollowing: Bool
    let isLoading: Bool
    let failed: Bool
    let open: () -> Void
    let follow: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: open) {
                HStack(spacing: WanderTheme.spacing3) {
                    WanderAvatar(initials: String(profile.displayName.prefix(1)), avatarURL: profile.avatarURL,
                                 size: 44, color: WanderTheme.pinSocial.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName).font(AstirTypography.cardTitle)
                        Text("@\(profile.handle)").font(AstirTypography.caption).foregroundStyle(brandMode.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discover.person.\(profile.id)")
            PeopleFollowButton(
                displayName: profile.displayName,
                isFollowing: isFollowing,
                isPending: isLoading,
                didFail: failed,
                action: follow
            )
            .frame(width: 112)
            .accessibilityIdentifier("discover.person.\(profile.id).follow")
        }
        .foregroundStyle(brandMode.primaryText)
        .padding(.vertical, WanderTheme.spacing2)
    }
}
