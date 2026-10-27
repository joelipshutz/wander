import SwiftUI

struct ActivityNotificationRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let notification: ActivityNotification
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: notification.symbol)
                    .font(.title3)
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(notification.displayTitle).font(AstirTypography.cardTitle)
                    Text(notification.displayBody)
                        .font(AstirTypography.bodySmall).foregroundStyle(brandMode.secondaryText)
                    Text(notification.createdAt, style: .relative)
                        .font(AstirTypography.caption).foregroundStyle(brandMode.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.activity.\(notification.id.uuidString)")
    }
}
