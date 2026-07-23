import MapKit
import SwiftUI
import UIKit

enum ProfileHomeMode: Equatable {
    case owner
    case member(relationship: ViewerRelationship, inCommonCount: Int)

    var isOwner: Bool {
        self == .owner
    }

    var inCommonCount: Int? {
        guard case .member(_, let count) = self else { return nil }
        return count
    }

    var relationship: ViewerRelationship? {
        guard case .member(let relationship, _) = self else { return nil }
        return relationship
    }
}

struct ProfileMemberActions {
    let canUnfollow: Bool
    let isMuted: Bool
    let unfollowAction: () -> Void
    let toggleMuteAction: () -> Void
    let blockAction: () -> Void
}

struct ProfileOwnerHome: View {
    let profile: LocalProfile
    let mode: ProfileHomeMode
    let stats: ProfileStats
    let saveStreak: SaveStreakSummary?
    let followerCount: Int
    let followingCount: Int
    let sharedVisitInvitationCount: Int
    let importSummary: PlaceImportSummary?
    let insights: ProfileInsights
    @Binding var selectedMonth: Date
    let isAvatarSaving: Bool
    let avatarAction: () -> Void
    let editAction: () -> Void
    let settingsAction: () -> Void
    let relationshipAction: () -> Void
    let backAction: (() -> Void)?
    let memberActions: ProfileMemberActions?
    let graphAction: (ProfileSocialGraphTab) -> Void
    let sharedVisitInvitationsAction: () -> Void
    let importSourceAction: (PlaceImportSource) -> Void
    let importInboxAction: () -> Void
    let savedPlacesAction: (PlaceStatus) -> Void
    let inCommonAction: () -> Void
    let calendarDateAction: (Date, [String]) -> Void
    let mapSummaryAction: (ProfileMapSummaryKind, ProfileSummaryItem) -> Void
    @State private var showsMemberActions = ProcessInfo.processInfo.arguments.contains("-WanderShowProfileActions")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                identitySection
                ProfileSharedVisitInboxRow(
                    invitationCount: sharedVisitInvitationCount,
                    action: sharedVisitInvitationsAction
                )
                if mode.isOwner, let importSummary {
                    ProfileImportSection(
                        summary: importSummary,
                        sourceAction: importSourceAction,
                        inboxAction: importInboxAction
                    )
                }
                savedPlacesSection
                if mode.isOwner, let saveStreak {
                    ProfileSaveStreakRow(summary: saveStreak)
                }
                ProfileCalendarSection(
                    insights: insights,
                    selectedMonth: $selectedMonth,
                    ownerLabel: ownerLabel,
                    dateAction: calendarDateAction
                )
                ProfileMapSection(
                    profile: profile,
                    insights: insights,
                    beenCount: stats.been,
                    ownerLabel: ownerLabel,
                    summaryAction: mapSummaryAction
                )
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .wanderScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var identitySection: some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                    if let backAction {
                        ProfileHeaderActionButton(
                            systemImage: "chevron.left",
                            accessibilityLabel: "Back",
                            action: backAction
                        )
                    }

                    Text(profile.displayName)
                        .font(.system(size: 30, weight: .black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: WanderTheme.spacing2)

                    if mode.isOwner {
                        ProfileHeaderActionButton(systemImage: "pencil", accessibilityLabel: "Edit profile", action: editAction)
                    }

                    if let shareContent = WanderShareContent.profile(
                        serverID: profile.serverID,
                        displayName: profile.displayName,
                        handle: profile.handle
                    ) {
                        WanderShareButton(content: shareContent) {
                            ProfileHeaderActionLabel(systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share profile")
                    }

                    if mode.isOwner {
                        ProfileHeaderActionButton(systemImage: "gearshape.fill", accessibilityLabel: "Settings", action: settingsAction)
                    } else if let memberActions {
                        ProfileHeaderActionButton(
                            systemImage: "ellipsis",
                            accessibilityLabel: "More profile actions"
                        ) {
                            showsMemberActions.toggle()
                        }
                        .popover(
                            isPresented: $showsMemberActions,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .top
                        ) {
                            ProfileMemberActionsPopover(
                                actions: memberActions,
                                dismiss: { showsMemberActions = false }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }

            Group {
                if mode.isOwner {
                    Button(action: avatarAction) {
                        profileAvatar
                    }
                    .buttonStyle(.plain)
                    .disabled(isAvatarSaving)
                    .accessibilityLabel(profile.avatarURL == nil ? "Add profile photo" : "Change profile photo")
                } else {
                    profileAvatar
                        .accessibilityLabel("\(profile.displayName)'s profile photo")
                }
            }

            VStack(spacing: WanderTheme.spacing1) {
                Text("@\(profile.handle)")
                    .font(.system(size: 18, weight: .black))

                Text(profileMetadata)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)

                if let bio = normalized(profile.bio) {
                    Text(bio)
                        .font(.system(size: 15, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.top, WanderTheme.spacing1)
                }

                if let relationship = mode.relationship {
                    Button(action: relationshipAction) {
                        Label(relationshipTitle(relationship), systemImage: relationshipSymbol(relationship))
                            .font(.system(size: 14, weight: .black))
                            .padding(.horizontal, WanderTheme.spacing4)
                            .frame(minHeight: WanderTheme.tapMinimum)
                            .background(relationship == .nonFollower ? WanderTheme.terracotta.color : WanderTheme.surfaceRaised.color)
                            .foregroundStyle(relationship == .nonFollower ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, WanderTheme.spacing2)
                }
            }

            HStack(spacing: 0) {
                ProfileGraphCountButton(value: followerCount, label: "Followers") {
                    graphAction(.followers)
                }
                ProfileGraphCountButton(value: followingCount, label: "Following") {
                    graphAction(.following)
                }
                ProfileGraphCountButton(value: stats.friends, label: "Friends") {
                    graphAction(.friends)
                }
            }
            .padding(.vertical, WanderTheme.spacing2)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }

    private var profileAvatar: some View {
        ZStack {
            WanderAvatar(
                initials: profile.initials,
                avatarURL: profile.avatarURL,
                size: 132,
                color: WanderTheme.avatarRyan.color
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 12, y: 6)

            if isAvatarSaving && mode.isOwner {
                Circle()
                    .fill(WanderTheme.textInk.color.opacity(0.42))
                    .frame(width: 132, height: 132)
                ProgressView()
                    .tint(WanderTheme.textOnAction.color)
            }
        }
    }

    private var savedPlacesSection: some View {
        HStack(spacing: mode.isOwner ? WanderTheme.spacing3 : WanderTheme.spacing2) {
            OwnerProfileSaveTile(
                value: stats.been,
                label: "BEEN",
                symbol: "checkmark.circle.fill",
                color: WanderTheme.stateSuccess.color,
                fill: WanderTheme.categorySage.color.opacity(0.22),
                isCompact: !mode.isOwner
            ) {
                savedPlacesAction(.been)
            }

            OwnerProfileSaveTile(
                value: stats.wanna,
                label: "WANNA",
                symbol: "bookmark.fill",
                color: WanderTheme.stateWarning.color,
                fill: WanderTheme.sunTint.color,
                isCompact: !mode.isOwner
            ) {
                savedPlacesAction(.wannaGo)
            }

            if let inCommonCount = mode.inCommonCount {
                OwnerProfileSaveTile(
                    value: inCommonCount,
                    label: "IN COMMON",
                    symbol: "arrow.triangle.2.circlepath.circle.fill",
                    color: WanderTheme.pinSocial.color,
                    fill: WanderTheme.skyTint.color,
                    isCompact: true,
                    action: inCommonAction
                )
            }
        }
    }

    private var ownerLabel: String {
        mode.isOwner ? "your" : "\(profile.displayName.components(separatedBy: " ").first ?? profile.displayName)'s"
    }

    private func relationshipTitle(_ relationship: ViewerRelationship) -> String {
        switch relationship {
        case .owner: "You"
        case .mutual: "Friends"
        case .follower: "Following"
        case .nonFollower: "Follow"
        }
    }

    private func relationshipSymbol(_ relationship: ViewerRelationship) -> String {
        relationship == .nonFollower ? "person.badge.plus" : "checkmark"
    }

    private var profileMetadata: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var values = ["Member since \(formatter.string(from: profile.createdAt))"]
        if let homeArea = normalized(profile.homeArea) {
            values.append(homeArea)
        }
        return values.joined(separator: "  •  ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct ProfileMemberActionsPopover: View {
    let actions: ProfileMemberActions
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if actions.canUnfollow {
                actionButton(
                    title: "Unfollow",
                    systemImage: "person.badge.minus",
                    role: .destructive,
                    action: actions.unfollowAction
                )
                Divider()
            }

            actionButton(
                title: actions.isMuted ? "Unmute activity" : "Mute activity",
                systemImage: actions.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                action: actions.toggleMuteAction
            )
            Divider()
            actionButton(
                title: "Block",
                systemImage: "hand.raised.fill",
                role: .destructive,
                action: actions.blockAction
            )
        }
        .frame(width: 236)
        .padding(.vertical, WanderTheme.spacing1)
        .background(WanderTheme.surfaceBone.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile actions")
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            dismiss()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .padding(.horizontal, WanderTheme.spacing3)
        }
        .buttonStyle(.plain)
    }
}

struct ProfileHeaderActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileHeaderActionLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ProfileHeaderActionLabel: View {
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

private struct ProfileGraphCountButton: View {
    let value: Int
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
    }
}

private struct OwnerProfileSaveTile: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color
    let fill: Color
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: isCompact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
                    Image(systemName: symbol)
                        .font(.system(size: isCompact ? 16 : 19, weight: .black))
                    Text("\(value)")
                        .font(.system(size: isCompact ? 23 : 28, weight: .black))
                    Spacer(minLength: isCompact ? 0 : WanderTheme.spacing2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: isCompact ? 10 : 12, weight: .black))
                        .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.8))
                        .clipShape(Circle())
                }

                Text(label)
                    .font(.system(size: isCompact ? 11 : 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(isCompact ? WanderTheme.spacing2 : WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(fill)
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSaveStreakRow: View {
    let summary: SaveStreakSummary

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(WanderTheme.borderHairline.color)

            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 28, height: 28)

                Text(streakTitle)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)

                Spacer(minLength: WanderTheme.spacing1)

                HStack(spacing: 3) {
                    ForEach(summary.recentDayCoverage.indices, id: \.self) { index in
                        Capsule()
                            .fill(
                                summary.recentDayCoverage[index]
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderHairline.color.opacity(0.65)
                            )
                            .frame(width: 10, height: 4)
                    }
                }
                .accessibilityHidden(true)

                if summary.bestCount > 0 {
                    Text("\(summary.bestCount) best")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .padding(.vertical, WanderTheme.spacing1)

            Divider()
                .overlay(WanderTheme.borderHairline.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var streakTitle: String {
        guard summary.currentCount > 0 else { return "start a streak" }
        return "\(summary.currentCount)-day streak"
    }

    private var accessibilityLabel: String {
        guard summary.currentCount > 0 else {
            return "No active save streak. Save a Been or Wanna place to start one."
        }
        let todayStatus = summary.isTodayCovered ? "Today is covered." : "Save today to keep it going."
        return "\(summary.currentCount) day save streak. Best streak \(summary.bestCount) days. \(todayStatus)"
    }
}

#if DEBUG
struct SaveStreakProfileRowMockup: View {
    private let summary = SaveStreakSummary(
        currentCount: 4,
        bestCount: 9,
        isTodayCovered: true,
        recentDayCoverage: [true, true, true, true, false, false, false]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Joe")
                    .font(.system(size: 30, weight: .black))
            }

            HStack(spacing: WanderTheme.spacing3) {
                OwnerProfileSaveTile(
                    value: 87,
                    label: "BEEN",
                    symbol: "checkmark.circle.fill",
                    color: WanderTheme.stateSuccess.color,
                    fill: WanderTheme.categorySage.color.opacity(0.22),
                    action: {}
                )
                OwnerProfileSaveTile(
                    value: 34,
                    label: "WANNA",
                    symbol: "bookmark.fill",
                    color: WanderTheme.stateWarning.color,
                    fill: WanderTheme.sunTint.color,
                    action: {}
                )
            }

            ProfileSaveStreakRow(summary: summary)

            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                Text("Joe's calendar")
                    .font(.system(size: 23, weight: .black))
                Text("July 2026")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 7),
                    spacing: WanderTheme.spacing3
                ) {
                    ForEach(19...25, id: \.self) { day in
                        Text("\(day)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                day <= 22
                                    ? WanderTheme.terracotta.color.opacity(0.16)
                                    : WanderTheme.surfaceBone.color
                            )
                            .clipShape(Circle())
                    }
                }
            }
            .padding(WanderTheme.spacing4)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing6)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
#endif

private struct ProfileCalendarSection: View {
    let insights: ProfileInsights
    @Binding var selectedMonth: Date
    let ownerLabel: String
    let dateAction: (Date, [String]) -> Void

    private var calendar: Calendar { .current }
    private var weekdays: [String] { calendar.veryShortStandaloneWeekdaySymbols }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ownerLabel) calendar")
                        .font(.system(size: 23, weight: .black))
                    Text(monthTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                HStack(spacing: WanderTheme.spacing1) {
                    ProfileMonthButton(systemImage: "chevron.left") { shiftMonth(-1) }
                    ProfileMonthButton(systemImage: "chevron.right") { shiftMonth(1) }
                }
            }

            HStack(spacing: 0) {
                ProfileCalendarMetric(value: insights.monthSpotCount, label: "spots ranked")
                ProfileCalendarMetric(value: insights.monthCategoryCount, label: "cuisines")
                ProfileCalendarMetric(value: insights.monthCityCount, label: "cities")
            }

            Grid(horizontalSpacing: 6, verticalSpacing: WanderTheme.spacing2) {
                GridRow {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                        Text(weekday)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                }

                ForEach(Array(monthWeeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            if let date {
                                let day = calendar.startOfDay(for: date)
                                ProfileCalendarDayCell(date: date, visitCount: insights.monthVisitCounts[day])
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectDate(date, day: day) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Shows places from this date")
                                    .accessibilityAction { selectDate(date, day: day) }
                            } else {
                                ProfileCalendarDayCell(date: nil, visitCount: nil)
                            }
                        }
                    }
                }
            }

        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))
    }

    private var monthTitle: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth),
              let days = calendar.range(of: .day, in: .month, for: selectedMonth)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let leading = Array<Date?>(repeating: nil, count: leadingCount)
        let dates = days.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: interval.start)
        }.map(Optional.some)
        return leading + dates
    }

    private var monthWeeks: [[Date?]] {
        var days = monthDays
        let trailingCount = (7 - (days.count % 7)) % 7
        days.append(contentsOf: Array<Date?>(repeating: nil, count: trailingCount))
        return stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<(start + 7)])
        }
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonth = next
        }
    }

    private func selectDate(_ date: Date, day: Date) {
        dateAction(date, insights.monthPlaceIDs[day] ?? [])
    }
}

private struct ProfileMonthButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceRaised.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileCalendarMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileCalendarDayCell: View {
    let date: Date?
    let visitCount: Int?

    var body: some View {
        ZStack {
            if visitCount != nil {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .fill(WanderTheme.terracotta.color)
            }

            if let date {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: visitCount == nil ? .bold : .black))
                    .foregroundStyle(visitCount == nil ? WanderTheme.textInk.color : WanderTheme.textOnAction.color)
            }

            if let visitCount, visitCount > 1 {
                Text("\(visitCount)")
                    .font(.system(size: 10, weight: .black))
                    .frame(width: 18, height: 18)
                    .background(WanderTheme.textInk.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
                    .offset(x: 15, y: -15)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let date else { return "" }
        let base = date.formatted(.dateTime.month(.wide).day())
        guard let visitCount else { return base }
        return "\(base), \(visitCount) \(visitCount == 1 ? "visit" : "visits")"
    }
}

enum ProfileMapSummaryKind: String, CaseIterable, Identifiable {
    case places
    case cities
    case countries

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct ProfileMapSection: View {
    let profile: LocalProfile
    let insights: ProfileInsights
    let beenCount: Int
    let ownerLabel: String
    let summaryAction: (ProfileMapSummaryKind, ProfileSummaryItem) -> Void
    @State private var selectedSummary: ProfileMapSummaryKind = .places
    @State private var shareImageFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ownerLabel) map")
                        .font(.system(size: 23, weight: .black))
                    Text("\(insights.mapCityCount) \(insights.mapCityCount == 1 ? "city" : "cities")  •  \(beenCount) Been places")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                if let shareContent = mapShareContent {
                    WanderShareButton(content: shareContent) {
                        ProfileHeaderActionLabel(systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share \(profile.displayName)'s map")
                    .accessibilityHint("Shares the profile link and this map as a PNG")
                } else if profile.serverID != nil {
                    Button {} label: {
                        ProfileHeaderActionLabel(systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .accessibilityLabel("Share \(profile.displayName)'s map")
                    .accessibilityHint("Available when the map image is ready")
                }
            }

            ProfileMapSnapshotView(
                points: insights.mapPoints,
                shareImageFileURL: $shareImageFileURL
            )
                .frame(height: 205)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Map of \(ownerLabel) Been places")

            Picker("Map summary", selection: $selectedSummary) {
                ForEach(ProfileMapSummaryKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if summaryItems.isEmpty {
                Text(emptyCopy)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summaryItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            summaryAction(selectedSummary, item)
                        } label: {
                            ProfileMapSummaryRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows matching Been places")
                        if index < summaryItems.count - 1 {
                            Divider().overlay(WanderTheme.borderHairline.color)
                        }
                    }
                }
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }

    private var mapShareContent: WanderShareContent? {
        guard let shareImageFileURL else { return nil }
        return WanderShareContent.profileMap(
            serverID: profile.serverID,
            displayName: profile.displayName,
            handle: profile.handle,
            imageFileURL: shareImageFileURL
        )
    }

    private var summaryItems: [ProfileSummaryItem] {
        switch selectedSummary {
        case .places: insights.placeSummaries
        case .cities: insights.citySummaries
        case .countries: insights.countrySummaries
        }
    }

    private var emptyCopy: String {
        switch selectedSummary {
        case .places: "\(ownerLabel.capitalized) Been places will appear here."
        case .cities: "Cities appear after \(ownerLabel) Been places have location details."
        case .countries: "Countries appear after \(ownerLabel) Been places have location details."
        }
    }
}

private struct ProfileMapSnapshotView: View {
    let points: [ProfileMapPoint]
    @Binding var shareImageFileURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var renderedSnapshot: ProfileMapRenderedSnapshot?

    var body: some View {
        GeometryReader { geometry in
            let request = ProfileMapSnapshotRequest(
                points: points,
                size: geometry.size,
                displayScale: displayScale,
                colorScheme: colorScheme
            )

            Group {
                if let renderedSnapshot, renderedSnapshot.key == request.cacheKey {
                    Image(uiImage: renderedSnapshot.image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    WanderTheme.surfaceSand.color
                        .overlay {
                            Image(systemName: "map")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                }
            }
            .clipped()
            .task(id: request.cacheKey) {
                shareImageFileURL = nil
                guard request.isRenderable else { return }
                guard let image = await ProfileMapSnapshotCache.shared.image(for: request) else { return }
                guard !Task.isCancelled else { return }
                renderedSnapshot = ProfileMapRenderedSnapshot(key: request.cacheKey, image: image)

                guard let pngData = image.pngData(),
                      let imageFileURL = await WanderShareAttachmentStore.preparePNG(pngData),
                      !Task.isCancelled,
                      renderedSnapshot?.key == request.cacheKey
                else { return }
                shareImageFileURL = imageFileURL
            }
        }
    }
}

private struct ProfileMapRenderedSnapshot {
    let key: String
    let image: UIImage
}

private struct ProfileMapSnapshotRequest {
    struct Coordinate: Hashable {
        let latitude: Double
        let longitude: Double

        var mapCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    let coordinates: [Coordinate]
    let size: CGSize
    let displayScale: CGFloat
    let userInterfaceStyle: UIUserInterfaceStyle
    let cacheKey: String

    var isRenderable: Bool {
        size.width > 0 && size.height > 0 && displayScale > 0
    }

    init(points: [ProfileMapPoint], size: CGSize, displayScale: CGFloat, colorScheme: ColorScheme) {
        let scale = max(displayScale, 1)
        let pixelWidth = max(Int((size.width * scale).rounded()), 1)
        let pixelHeight = max(Int((size.height * scale).rounded()), 1)
        let normalizedSize = CGSize(
            width: CGFloat(pixelWidth) / scale,
            height: CGFloat(pixelHeight) / scale
        )
        let coordinates = points.compactMap { point -> Coordinate? in
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            return Coordinate(latitude: point.latitude, longitude: point.longitude)
        }
        .sorted { lhs, rhs in
            if lhs.latitude != rhs.latitude {
                return lhs.latitude < rhs.latitude
            }
            return lhs.longitude < rhs.longitude
        }
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let coordinateKey = coordinates.map { coordinate in
            "\(coordinate.latitude.bitPattern):\(coordinate.longitude.bitPattern)"
        }
        .joined(separator: ",")

        self.coordinates = coordinates
        self.size = normalizedSize
        self.displayScale = scale
        self.userInterfaceStyle = style
        self.cacheKey = "\(pixelWidth)x\(pixelHeight)@\(Double(scale).bitPattern)|\(style.rawValue)|\(coordinateKey)"
    }
}

@MainActor
private final class ProfileMapSnapshotCache {
    static let shared = ProfileMapSnapshotCache()

    private let images: NSCache<NSString, UIImage>

    private init() {
        let images = NSCache<NSString, UIImage>()
        images.countLimit = 6
        images.totalCostLimit = 18 * 1_024 * 1_024
        self.images = images
    }

    func image(for request: ProfileMapSnapshotRequest) async -> UIImage? {
        let key = request.cacheKey as NSString
        if let cached = images.object(forKey: key) {
            return cached
        }

        do {
            let image = try await render(request)
            guard !Task.isCancelled else { return nil }
            let pixelWidth = Int((request.size.width * request.displayScale).rounded())
            let pixelHeight = Int((request.size.height * request.displayScale).rounded())
            images.setObject(image, forKey: key, cost: pixelWidth * pixelHeight * 4)
            return image
        } catch {
            return nil
        }
    }

    private func render(_ request: ProfileMapSnapshotRequest) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: 18, longitude: -55),
            fromDistance: 38_000_000,
            pitch: 0,
            heading: 0
        )
        options.size = request.size
        options.traitCollection = UITraitCollection(mutations: { traits in
            traits.displayScale = request.displayScale
            traits.userInterfaceStyle = request.userInterfaceStyle
        })

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        let snapshot = try await MKMapSnapshotter(options: options).start()
        try Task.checkCancellation()

        let format = UIGraphicsImageRendererFormat()
        format.scale = request.displayScale
        format.opaque = true
        return UIGraphicsImageRenderer(size: request.size, format: format).image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: request.size))

            let fillColor = UIColor(WanderTheme.terracotta.color).cgColor
            let strokeColor = UIColor(WanderTheme.surfaceRaised.color).cgColor
            context.cgContext.setFillColor(fillColor)
            context.cgContext.setStrokeColor(strokeColor)
            context.cgContext.setLineWidth(1)

            for coordinate in request.coordinates {
                let point = snapshot.point(for: coordinate.mapCoordinate)
                let markerRect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                guard markerRect.intersects(CGRect(origin: .zero, size: request.size)) else { continue }
                context.cgContext.fillEllipse(in: markerRect)
                context.cgContext.strokeEllipse(in: markerRect)
            }
        }
    }
}

private struct ProfileMapSummaryRow: View {
    let item: ProfileSummaryItem

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("\(item.count) \(item.count == 1 ? "place" : "places")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text("\(item.percentage)%")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
    }
}
