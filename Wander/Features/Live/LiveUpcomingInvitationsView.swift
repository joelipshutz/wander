import SwiftUI

/// A bounded projection of the existing recipient inbox, never an attendance
/// record or a complete calendar. The RPC currently returns at most 100 rows.
struct LiveUpcomingInvitationsProjection: Equatable {
    let rows: [ReceivedPlacePlanInvitation]
    var visibleRows: [ReceivedPlacePlanInvitation] { Array(rows.prefix(3)) }

    init(invitations: [ReceivedPlacePlanInvitation], inboxUserID: String?, userID: String?,
         failed: Bool = false, now: Date) {
        guard let userID, !userID.isEmpty, inboxUserID == userID, !failed else {
            rows = []
            return
        }
        rows = invitations.filter {
            guard let date = $0.invitation.payload.suggestedAt else { return false }
            return date >= now
        }.sorted {
            let left = $0.invitation.payload.suggestedAt!
            let right = $1.invitation.payload.suggestedAt!
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }
}

/// Navigation callbacks retain the existing invitation and full-inbox flows.
/// The root owns modal lifecycle; this view neither fetches nor marks rows read.
struct LiveUpcomingInvitationsView: View {
    @EnvironmentObject private var inbox: PlacePlanInvitationInbox
    @Environment(\.astirBrandMode) private var brand

    let userID: String?
    let onOpenInvitation: (ReceivedPlacePlanInvitation) -> Void
    let onOpenInbox: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let projection = LiveUpcomingInvitationsProjection(
                invitations: inbox.invitations, inboxUserID: inbox.userID,
                userID: userID, failed: inbox.failed, now: context.date
            )
            if !projection.rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming Invitations")
                        .font(AstirTypography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(projection.visibleRows.count) Shown · \(projection.rows.count) In Recent Inbox")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                        .accessibilityIdentifier("live.upcoming.count")
                    ForEach(projection.visibleRows) { invitation in
                        row(invitation)
                    }
                    Text("From Up To 100 Recent Received Invitations")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("View Inbox") {
                        guard let userID, inbox.userID == userID else { return }
                        onOpenInbox()
                    }
                        .font(AstirTypography.control).foregroundStyle(brand.accentText)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("live.upcoming.inbox")
                }
                .foregroundStyle(brand.primaryText)
            } else if let userID, inbox.userID == userID {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming Invitations").font(AstirTypography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    if inbox.failed {
                        Text("Couldn’t Refresh Invitations. Open Your Inbox To Try Again.")
                            .font(AstirTypography.bodySmall)
                    } else if inbox.isLoading {
                        ProgressView("Refreshing Invitations")
                    } else {
                        Text("No Upcoming Dates In Your Recent Received Invitations.")
                            .font(AstirTypography.bodySmall)
                    }
                    Button("View Inbox") {
                        guard inbox.userID == userID else { return }
                        onOpenInbox()
                    }
                    .font(AstirTypography.control).foregroundStyle(brand.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("live.upcoming.inbox")
                }
                .foregroundStyle(brand.primaryText)
            } else {
                Text("Invitations Are Unavailable.")
                    .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
            }
        }
    }

    private func row(_ invitation: ReceivedPlacePlanInvitation) -> some View {
        Button {
            // Recheck identity at the action boundary, not only during rendering.
            guard let userID, inbox.userID == userID, !inbox.failed,
                  let current = inbox.invitations.first(where: { $0.id == invitation.id }) else { return }
            onOpenInvitation(current)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.invitation.payload.placeName).font(AstirTypography.control)
                    Text("From \(invitation.invitation.payload.senderName)")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                    if let date = invitation.invitation.payload.suggestedAt {
                        Text("Suggested \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(brand.secondaryText).accessibilityHidden(true)
            }
            .frame(minHeight: 44).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Your Invitation. No Response Is Sent.")
        .accessibilityIdentifier("live.upcoming.invitation.\(invitation.id.uuidString)")
    }
}
