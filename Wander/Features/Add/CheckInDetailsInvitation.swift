import SwiftUI

/// The invitation always targets a visit, never the place's latest-visit shortcut.
struct CheckInDetailsInvitation: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brandMode
    let onEdit: (LocalPlaceVisit, VisiblePlace) -> Void

    var body: some View {
        if let (visit, place) = store.pendingCheckInDetails {
            HStack(spacing: WanderTheme.spacing1) {
                Button { onEdit(visit, place) } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        CategoryThumb(emoji: place.categoryEmoji, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add details to your check-in at")
                                .font(AstirTypography.caption).foregroundStyle(brandMode.secondaryText)
                            Text(place.place.canonicalName)
                                .font(AstirTypography.control).foregroundStyle(brandMode.accentText)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(brandMode.accentText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add details to your check-in at \(place.place.canonicalName)")
                .accessibilityHint("Opens this visit's editor")
                .accessibilityIdentifier("check-in.invitation.edit")
                Button {
                    let ownerID = store.currentUser.id
                    let visitID = visit.id
                    store.dismissCheckInDetails(visitID: visitID)
                    store.flushPersistence()
                    if auth.isSignedIn {
                        Task { @MainActor in
                            guard store.currentUser.id == ownerID else { return }
                            _ = await store.syncVisit(visitID: visitID, backend: backend)
                        }
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(brandMode.secondaryText)
                .accessibilityLabel("Dismiss check-in invitation")
                .accessibilityIdentifier("check-in.invitation.dismiss")
            }
            .padding(WanderTheme.spacing3)
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("check-in.invitation")
        }
    }
}
