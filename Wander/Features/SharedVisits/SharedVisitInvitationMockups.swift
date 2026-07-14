#if DEBUG
import SwiftUI

enum SharedVisitInvitationMockupPage: String, CaseIterable {
    case profileBanner
    case inbox
    case emptyInbox

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SharedVisitInvitationMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderSharedVisitInvitationMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .profileBanner
        }

        return SharedVisitInvitationMockupPage(rawValue: arguments[valueIndex]) ?? .profileBanner
    }
}

struct SharedVisitInvitationMockupRoot: View {
    let page: SharedVisitInvitationMockupPage

    var body: some View {
        Group {
            switch page {
            case .profileBanner:
                SharedVisitProfileBannerMockup()
            case .inbox:
                SharedVisitInvitationInboxMockup(invitations: SharedVisitInvitationMockData.invitations)
            case .emptyInbox:
                SharedVisitInvitationInboxMockup(invitations: [])
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct SharedVisitInvitationMock: Identifiable {
    let id: String
    let inviterName: String
    let inviterInitials: String
    let inviterColor: Color
    let placeName: String
    let location: String
    let visitDate: String
    let timeAgo: String
    let status: String
    let tags: [String]
    let thumbnailSymbol: String
    let thumbnailColor: Color
}

private enum SharedVisitInvitationMockData {
    static let invitations = [
        SharedVisitInvitationMock(
            id: "rvr-joe",
            inviterName: "Joe Lipshutz",
            inviterInitials: "JL",
            inviterColor: WanderTheme.pinSocial.color,
            placeName: "RVR",
            location: "Venice · Italian",
            visitDate: "Tonight, 8:14 PM",
            timeAgo: "just now",
            status: "been",
            tags: ["group drinks", "date night"],
            thumbnailSymbol: "fork.knife",
            thumbnailColor: WanderTheme.categoryMoss.color
        ),
        SharedVisitInvitationMock(
            id: "menottis-maya",
            inviterName: "Maya Chen",
            inviterInitials: "MC",
            inviterColor: WanderTheme.avatarAndrew.color,
            placeName: "Menotti's Coffee Stop",
            location: "Venice · Coffee",
            visitDate: "Sunday, 10:32 AM",
            timeAgo: "2h",
            status: "been",
            tags: ["walk-in", "neighborhood standby"],
            thumbnailSymbol: "cup.and.saucer.fill",
            thumbnailColor: WanderTheme.categorySun.color
        )
    ]
}

private struct SharedVisitProfileBannerMockup: View {
    var body: some View {
        ZStack(alignment: .top) {
            SharedVisitProfileShell()
            SharedVisitFlashBanner(invitation: SharedVisitInvitationMockData.invitations[0])
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.top, WanderTheme.spacing2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }
}

private struct SharedVisitFlashBanner: View {
    let invitation: SharedVisitInvitationMock

    var body: some View {
        Button(action: {}) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: invitation.inviterInitials,
                    size: 42,
                    color: invitation.inviterColor
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(invitation.inviterName) invited you to \(invitation.placeName)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text("Shared visit · \(invitation.timeAgo)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(WanderTheme.pinSocial.color)
                    .frame(width: 4)
                    .padding(.vertical, WanderTheme.spacing2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(WanderTheme.borderHairline.color.opacity(0.75), lineWidth: 1)
            }
            .shadow(color: WanderTheme.textInk.color.opacity(0.15), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open visit invitation from \(invitation.inviterName) for \(invitation.placeName)")
    }
}

private struct SharedVisitProfileShell: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                profileHeader
                SharedVisitProfileInboxRow(count: 2)
                profileStats
                calendarPreview
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var profileHeader: some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                    Text("Ryan Lieblein")
                        .font(.system(size: 30, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: WanderTheme.spacing2)

                    SharedVisitProfileAction(systemImage: "pencil")
                    SharedVisitProfileAction(systemImage: "square.and.arrow.up")
                    SharedVisitProfileAction(systemImage: "gearshape.fill")
                }
            }

            WanderAvatar(initials: "RL", size: 132, color: WanderTheme.avatarRyan.color)
                .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 12, y: 6)

            VStack(spacing: WanderTheme.spacing1) {
                Text("@ryan_lieblein")
                    .font(.system(size: 18, weight: .black))
                Text("Member since October 2023  •  Los Angeles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                SharedVisitSocialCount(value: "128", label: "Followers")
                SharedVisitSocialCount(value: "96", label: "Following")
                SharedVisitSocialCount(value: "42", label: "Friends")
            }
            .padding(.vertical, WanderTheme.spacing2)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
    }

    private var profileStats: some View {
        HStack(spacing: WanderTheme.spacing3) {
            SharedVisitMockStat(
                value: "87",
                label: "BEEN",
                symbol: "checkmark.circle.fill",
                color: WanderTheme.stateSuccess.color,
                tint: WanderTheme.categorySage.color.opacity(0.22)
            )
            SharedVisitMockStat(
                value: "34",
                label: "WANNA",
                symbol: "bookmark.fill",
                color: WanderTheme.stateWarning.color,
                tint: WanderTheme.sunTint.color
            )
        }
    }

    private var calendarPreview: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("your calendar")
                        .font(.system(size: 23, weight: .black))
                    Text("July 2026")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                SharedVisitProfileAction(systemImage: "chevron.left")
                SharedVisitProfileAction(systemImage: "chevron.right")
            }

            HStack(spacing: 0) {
                SharedVisitCalendarMetric(value: "6", label: "spots ranked")
                SharedVisitCalendarMetric(value: "4", label: "cuisines")
                SharedVisitCalendarMetric(value: "2", label: "cities")
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }
}

private struct SharedVisitProfileAction: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .black))
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .background(WanderTheme.surfaceBone.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.borderHairline.color))
    }
}

private struct SharedVisitSocialCount: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .black))
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }
}

private struct SharedVisitMockStat: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .black))
                Text(value)
                    .font(.system(size: 28, weight: .black))
                Spacer(minLength: WanderTheme.spacing2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.8))
                    .clipShape(Circle())
            }
            Text(label)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(tint)
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .stroke(color.opacity(0.3), lineWidth: 1.5)
        }
    }
}

private struct SharedVisitCalendarMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

private struct SharedVisitProfileInboxRow: View {
    let count: Int

    var body: some View {
        Button(action: {}) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WanderTheme.stateInfo.color)
                    .frame(width: 44, height: 44)
                    .background(WanderTheme.skyTint.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text("visit invitations")
                        .font(.system(size: 16, weight: .black))
                    Text("\(count) waiting for you")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(WanderTheme.terracotta.color, in: Circle())

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.pinSocial.color.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Visit invitations, \(count) pending")
    }
}

private struct SharedVisitInvitationInboxMockup: View {
    let invitations: [SharedVisitInvitationMock]

    var body: some View {
        VStack(spacing: 0) {
            inboxHeader
            if invitations.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: WanderTheme.spacing4) {
                        ForEach(invitations) { invitation in
                            SharedVisitInvitationCard(invitation: invitation)
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing2)
                    .padding(.bottom, WanderTheme.spacing8)
                }
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var inboxHeader: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: {}) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(WanderTheme.surfaceBone.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text("visit invitations")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(invitations.isEmpty ? "you're all caught up" : "\(invitations.count) waiting for you")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing3)
    }

    private var emptyState: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .frame(width: 84, height: 84)
                .background(WanderTheme.categorySage.color.opacity(0.22), in: Circle())
            Text("no invitations waiting")
                .font(.system(size: 21, weight: .black, design: .rounded))
            Text("New shared visits will show up here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WanderTheme.spacing8)
    }
}

private struct SharedVisitInvitationCard: View {
    let invitation: SharedVisitInvitationMock

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            inviterRow
            Divider()
                .overlay(WanderTheme.borderHairline.color.opacity(0.7))
            placeRow
            tagRow
            actionRow
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.8), lineWidth: 1)
        }
    }

    private var inviterRow: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: invitation.inviterInitials,
                size: 38,
                color: invitation.inviterColor
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.inviterName)
                    .font(.system(size: 14, weight: .black))
                Text("invited you to a visit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text(invitation.timeAgo)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
    }

    private var placeRow: some View {
        HStack(spacing: WanderTheme.spacing3) {
            SharedVisitPlaceThumbnail(
                symbol: invitation.thumbnailSymbol,
                color: invitation.thumbnailColor,
                size: 82
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.placeName)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(2)
                Text(invitation.location)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Label(invitation.visitDate, systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text(invitation.status.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(WanderTheme.stateSuccess.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(invitation.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minHeight: 32)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Button(action: {}) {
                Text("Decline")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.stateError.color)
                    .frame(minWidth: 92, minHeight: 50)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(WanderTheme.stateError.color.opacity(0.45), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                HStack(spacing: WanderTheme.spacing2) {
                    Text("Review & save")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
                .shadow(color: WanderTheme.terracottaDark.color.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SharedVisitPlaceThumbnail: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.32, weight: .black))
            .foregroundStyle(WanderTheme.surfaceBone.color)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.surfaceRaised.color, lineWidth: 2)
            }
    }
}

#endif
