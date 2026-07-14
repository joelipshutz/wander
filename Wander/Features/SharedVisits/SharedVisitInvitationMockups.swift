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
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Text("profile")
                        .font(.system(size: 30, weight: .black, design: .rounded))

                    profileHeader
                    profileStats
                    SharedVisitProfileInboxRow(count: 2)
                    monthSection
                    recentSection
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, 92)
            }

            SharedVisitMockTabBar()
        }
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            WanderAvatar(initials: "RL", size: 56, color: WanderTheme.avatarRyan.color)
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("Ryan Lieblein")
                    .font(.system(size: 23, weight: .black))
                Text("@ryan · Los Angeles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(WanderTheme.surfaceSand.color, in: Circle())
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var profileStats: some View {
        HStack(spacing: WanderTheme.spacing3) {
            SharedVisitMockStat(value: "38", label: "BEEN", tint: WanderTheme.categorySage.color.opacity(0.22))
            SharedVisitMockStat(value: "17", label: "WANNA", tint: WanderTheme.sunTint.color)
        }
    }

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("this month")
                    .font(.system(size: 17, weight: .black))
                Spacer()
                Text("JUL '26")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            HStack(spacing: WanderTheme.spacing4) {
                Text("6")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                Text("saved places this month.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("recent")
                .font(.system(size: 17, weight: .black))
            HStack(spacing: WanderTheme.spacing3) {
                SharedVisitPlaceThumbnail(
                    symbol: "takeoutbag.and.cup.and.straw.fill",
                    color: WanderTheme.terracotta.color,
                    size: 58
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gjusta")
                        .font(.system(size: 15, weight: .black))
                    Text("Venice · yesterday")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }
}

private struct SharedVisitMockStat: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(value)
                .font(.system(size: 30, weight: .black))
            Text(label)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(.horizontal, WanderTheme.spacing3)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
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

private struct SharedVisitMockTabBar: View {
    private let items = [
        ("map.fill", "map"),
        ("sparkles", "discover"),
        ("plus", "add"),
        ("list.bullet", "lists"),
        ("person.fill", "profile")
    ]

    var body: some View {
        HStack {
            ForEach(items, id: \.1) { item in
                VStack(spacing: 3) {
                    Image(systemName: item.0)
                        .font(.system(size: item.1 == "add" ? 20 : 16, weight: .black))
                        .frame(width: item.1 == "add" ? 44 : 30, height: item.1 == "add" ? 44 : 30)
                        .background(item.1 == "add" ? WanderTheme.terracotta.color : Color.clear)
                        .foregroundStyle(
                            item.1 == "add"
                                ? WanderTheme.textOnAction.color
                                : (item.1 == "profile" ? WanderTheme.terracotta.color : WanderTheme.textMuted.color)
                        )
                        .clipShape(Circle())
                    Text(item.1)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.1 == "profile" ? WanderTheme.terracotta.color : WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing1)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color.opacity(0.65))
                .frame(height: 1)
        }
    }
}
#endif
