import SwiftUI

/// The same identity row is used by the profile and its live onboarding editor.
struct ProfileIdentityHeader<Avatar: View, Details: View>: View {
    @Environment(\.astirBrandMode) private var brandMode
    let name: String
    var tracksProfileMotion = false
    @ViewBuilder let avatar: Avatar
    @ViewBuilder let details: Details

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            avatar.profileMotionSource(tracksProfileMotion ? .avatar : nil)
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(name)
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .lineLimit(tracksProfileMotion ? 1 : 2)
                    .minimumScaleFactor(0.75)
                    .profileMotionSource(tracksProfileMotion ? .name : nil)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, WanderTheme.spacing2)
        }
    }
}
