import SwiftUI

struct PlacePlanNotificationRow: View {
    @Environment(\.astirBrandMode) private var brand
    let plan: ReceivedPlacePlanInvitation
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                AsyncImage(url: plan.invitation.artworkURL) { phase in
                    if let image = phase.image {
                        // Use the photograph at the top of the shared artwork.
                        image.resizable().scaledToFit().frame(width: 160)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2).foregroundStyle(brand.accentText)
                            .frame(width: 72, height: 72).background(brand.accentWash)
                    }
                }
                .frame(width: 72, height: 72, alignment: .top).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(plan.invitation.payload.senderName) invited you to \(plan.invitation.payload.placeName)")
                        .font(AstirTypography.control).foregroundStyle(brand.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.invitation.payload.dateLabel)
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if plan.isUnread {
                    Circle().fill(brand.accent).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(brand.secondaryText).accessibilityHidden(true)
            }
            .padding(14).frame(minHeight: 100)
            .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(plan.isUnread ? "Unread" : "Read")
        .accessibilityHint("Opens your invitation")
        .accessibilityIdentifier("place-plan.notification.\(plan.id.uuidString)")
    }
}
