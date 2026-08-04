import MapKit
import SwiftUI
import UIKit

private enum ProfileHomeScrollAnchor {
    static let calendar = "profile.calendar"
}

enum ProfileActivityFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case checkIns = "check_ins"
    case wanna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .checkIns: CheckInCopy.pluralTitle
        case .wanna: "Wanna"
        }
    }

    func includes(_ item: ProfileActivityItem) -> Bool {
        switch self {
        case .all: true
        case .checkIns: item.kind == .checkIn
        case .wanna: item.kind == .wanna
        }
    }
}

enum ProfileActivityKind: String, Equatable {
    case checkIn
    case wanna

    var status: PlaceStatus {
        switch self {
        case .checkIn: .been
        case .wanna: .wannaGo
        }
    }

    var title: String {
        switch self {
        case .checkIn: CheckInCopy.title
        case .wanna: "Wanna"
        }
    }

    var symbol: String {
        switch self {
        case .checkIn: "ticket.fill"
        case .wanna: "bookmark.fill"
        }
    }
}

struct ProfileActivityItem: Identifiable {
    let id: String
    let visiblePlace: VisiblePlace
    let kind: ProfileActivityKind
    let timestamp: Date
    let visitID: String?
}

struct ProfileActivityTimestampText: Equatable {
    let date: String
    let time: String
}

enum ProfileActivityPresenter {
    static func items(
        visiblePlaces: [VisiblePlace],
        visits: [LocalPlaceVisit],
        currentUserID: String
    ) -> [ProfileActivityItem] {
        let representativePlaces = VisiblePlaceGrouping.representativePlaces(
            from: visiblePlaces,
            currentUserID: currentUserID
        )

        return representativePlaces
            .flatMap { visiblePlace -> [ProfileActivityItem] in
                let userPlace = visiblePlace.userPlace
                let referenceIDs = Set(
                    [userPlace.id, userPlace.localID, userPlace.serverID].compactMap { $0 }
                )
                let matchingVisits = visits.filter {
                    $0.deletedAt == nil && referenceIDs.contains($0.userPlaceID)
                }

                if userPlace.status == .been {
                    var activity = matchingVisits.map { visit in
                        ProfileActivityItem(
                            id: "check-in-\(visit.id)",
                            visiblePlace: visiblePlace,
                            kind: .checkIn,
                            timestamp: visit.visitedAt,
                            visitID: visit.id
                        )
                    }

                    if activity.isEmpty {
                        activity.append(
                            ProfileActivityItem(
                                id: "check-in-legacy-\(userPlace.id)",
                                visiblePlace: visiblePlace,
                                kind: .checkIn,
                                timestamp: userPlace.visitedAt ?? userPlace.savedAt,
                                visitID: nil
                            )
                        )
                    }

                    if let historicalWantedAt = userPlace.historicalWantedAt {
                        activity.append(
                            ProfileActivityItem(
                                id: "wanna-history-\(userPlace.id)-\(historicalWantedAt.timeIntervalSince1970)",
                                visiblePlace: visiblePlace,
                                kind: .wanna,
                                timestamp: historicalWantedAt,
                                visitID: nil
                            )
                        )
                    }
                    return activity
                }

                return [
                    ProfileActivityItem(
                        id: "wanna-\(userPlace.id)",
                        visiblePlace: visiblePlace,
                        kind: .wanna,
                        timestamp: userPlace.savedAt,
                        visitID: nil
                    )
                ]
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id < rhs.id
            }
    }

    static func timestampText(
        for timestamp: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> ProfileActivityTimestampText {
        let date: String
        if calendar.isDate(timestamp, inSameDayAs: now) {
            date = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(timestamp, inSameDayAs: yesterday) {
            date = "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = calendar
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.dateFormat = calendar.isDate(timestamp, equalTo: now, toGranularity: .year)
                ? "MMM d"
                : "MMM d, yyyy"
            date = dateFormatter.string(from: timestamp)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "h:mm a"
        return ProfileActivityTimestampText(
            date: date,
            time: timeFormatter.string(from: timestamp)
        )
    }
}

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
    let viewerProfile: LocalProfile
    let mode: ProfileHomeMode
    let stats: ProfileStats
    let saveStreak: SaveStreakSummary?
    let followerCount: Int
    let followingCount: Int
    let sharedVisitInvitationCount: Int
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
    let recentActivity: [ProfileActivityItem]
    let recentActivityAction: (ProfileActivityItem) -> Void
    let allActivityAction: (ProfileActivityFilter) -> Void
    let inCommonAction: () -> Void
    let calendarDateAction: (ProfileCalendarDaySummary) -> Void
    let mapSummaryAction: (ProfileMapSummaryKind, ProfileSummaryItem) -> Void
    let calendarScrollRequestID: UUID?
    let onCalendarScrollRequestHandled: (UUID) -> Void
    @State private var showsMemberActions = ProcessInfo.processInfo.arguments.contains("-WanderShowProfileActions")
    @State private var profileScrollPosition: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                identitySection
                if let inCommonCount = mode.inCommonCount {
                    ProfileInCommonPlacesRow(
                        viewerProfile: viewerProfile,
                        profile: profile,
                        count: inCommonCount,
                        action: inCommonAction
                    )
                }
                if mode.isOwner {
                    if let saveStreak {
                        ProfileSaveStreakRow(summary: saveStreak)
                    }
                }
                if mode.isOwner || sharedVisitInvitationCount > 0 {
                    ProfileSharedVisitInboxRow(
                        invitationCount: sharedVisitInvitationCount,
                        action: sharedVisitInvitationsAction
                    )
                }
                ProfileRecentActivitySection(
                    items: recentActivity,
                    checkInCount: stats.checkIns,
                    wannaCount: stats.wanna,
                    itemAction: recentActivityAction,
                    allActivityAction: allActivityAction
                )
                ProfileCalendarSection(
                    insights: insights,
                    selectedMonth: $selectedMonth,
                    ownerLabel: ownerLabel,
                    dateAction: calendarDateAction
                )
                .id(ProfileHomeScrollAnchor.calendar)
                ProfileMapSection(
                    profile: profile,
                    insights: insights,
                    ownerLabel: ownerLabel,
                    summaryAction: mapSummaryAction
                )
            }
            .scrollTargetLayout()
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $profileScrollPosition, anchor: .top)
        .task(id: calendarScrollRequestID) {
            guard let calendarScrollRequestID else { return }

            // Keep the target bound until the selected Profile tab has laid out.
            // Unlike a one-shot proxy scroll, this also works during a cold
            // widget launch when TabView is still activating the Profile view.
            profileScrollPosition = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            profileScrollPosition = ProfileHomeScrollAnchor.calendar
            await Task.yield()
            guard !Task.isCancelled,
                  profileScrollPosition == ProfileHomeScrollAnchor.calendar
            else { return }
            onCalendarScrollRequestHandled(calendarScrollRequestID)
        }
        .wanderScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var identitySection: some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                    if let backAction {
                        ProfileHeaderActionButton(
                            systemImage: "chevron.left",
                            accessibilityLabel: "Back",
                            action: backAction
                        )
                    }

                    Text(profile.displayName)
                        .font(WanderTypography.editorialDisplay)
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
                            .foregroundStyle(
                                relationship == .nonFollower
                                    ? WanderTheme.terracottaDark.color
                                    : WanderTheme.textInk.color
                            )
                            .wanderGlassCapsule(tone: relationship == .nonFollower ? .accent : .neutral)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, WanderTheme.spacing2)
                }
            }

            HStack(spacing: 0) {
                ProfileGraphCountButton(value: followerCount, label: "Followers") {
                    graphAction(.followers)
                }
                ProfileGraphDivider()
                ProfileGraphCountButton(value: followingCount, label: "Following") {
                    graphAction(.following)
                }
                ProfileGraphDivider()
                ProfileGraphCountButton(value: stats.friends, label: "Friends") {
                    graphAction(.friends)
                }
            }
            .padding(.vertical, WanderTheme.spacing1)
            .wanderGlassPanel(cornerRadius: 22)
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
            .foregroundStyle(WanderTheme.textInk.color)
            .contentShape(Circle())
            .wanderGlassCapsule()
    }
}

private struct ProfileGraphDivider: View {
    var body: some View {
        Rectangle()
            .fill(WanderTheme.surfaceRaised.color.opacity(0.72))
            .frame(width: 1, height: 34)
            .accessibilityHidden(true)
    }
}

private struct ProfileInCommonPlacesRow: View {
    let viewerProfile: LocalProfile
    let profile: LocalProfile
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                avatarPair

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) \(count == 1 ? "place" : "places") in common")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("See where your maps overlap")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .wanderGlassPanel(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(count == 1 ? "place" : "places") in common with \(profile.displayName)")
        .accessibilityHint("Opens shared places")
    }

    private var avatarPair: some View {
        HStack(spacing: -10) {
            WanderAvatar(
                initials: viewerProfile.initials,
                avatarURL: viewerProfile.avatarURL,
                size: 32,
                color: WanderTheme.avatarRyan.color
            )
            .overlay(Circle().stroke(WanderTheme.canvasWarm.color, lineWidth: 2))
            .zIndex(1)

            WanderAvatar(
                initials: profile.initials,
                avatarURL: profile.avatarURL,
                size: 32,
                color: WanderTheme.avatarJames.color
            )
            .overlay(Circle().stroke(WanderTheme.canvasWarm.color, lineWidth: 2))
        }
        .frame(width: 54, alignment: .leading)
        .accessibilityHidden(true)
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

struct ProfileActivityFilterControl: View {
    @Binding var selection: ProfileActivityFilter
    let checkInCount: Int
    let wannaCount: Int

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ForEach(ProfileActivityFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(title(for: filter))
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(
                            selection == filter
                                ? WanderTheme.terracottaDark.color
                                : WanderTheme.textMuted.color
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        .background(
                            selection == filter
                                ? WanderTheme.sunTint.color.opacity(0.72)
                                : WanderTheme.surfaceBone.color
                        )
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                        .overlay {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                                .stroke(
                                    selection == filter
                                        ? WanderTheme.terracotta.color.opacity(0.32)
                                        : WanderTheme.borderHairline.color,
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: filter))
                .accessibilityAddTraits(selection == filter ? .isSelected : [])
            }
        }
    }

    private func title(for filter: ProfileActivityFilter) -> String {
        switch filter {
        case .all: filter.title
        case .checkIns: "\(checkInCount) \(filter.title)"
        case .wanna: "\(wannaCount) \(filter.title)"
        }
    }

    private func accessibilityLabel(for filter: ProfileActivityFilter) -> String {
        switch filter {
        case .all: "All activity"
        case .checkIns: "\(CheckInCopy.pluralTitle) activity, \(checkInCount)"
        case .wanna: "Wanna activity, \(wannaCount)"
        }
    }
}

private struct ProfileRecentActivitySection: View {
    let items: [ProfileActivityItem]
    let checkInCount: Int
    let wannaCount: Int
    let itemAction: (ProfileActivityItem) -> Void
    let allActivityAction: (ProfileActivityFilter) -> Void
    @State private var filter: ProfileActivityFilter = .all

    private var filteredItems: [ProfileActivityItem] {
        items.filter(filter.includes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("Activity")
                .font(WanderTypography.editorialMajorSectionTitle)
                .accessibilityAddTraits(.isHeader)

            ProfileActivityFilterControl(
                selection: $filter,
                checkInCount: checkInCount,
                wannaCount: wannaCount
            )

            VStack(spacing: 0) {
                if filteredItems.isEmpty {
                    Text(emptyStateText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                        .padding(.horizontal, WanderTheme.spacing3)
                } else {
                    ForEach(Array(filteredItems.prefix(6).enumerated()), id: \.element.id) { index, item in
                        ProfileActivityRow(item: item) {
                            itemAction(item)
                        }
                        if index < min(filteredItems.count, 6) - 1 {
                            Divider()
                                .overlay(WanderTheme.borderHairline.color)
                                .padding(.leading, 58)
                        }
                    }
                }
            }
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }

            Button {
                allActivityAction(filter)
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Text("See more")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                }
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyStateText: String {
        switch filter {
        case .all: "Activity will show up here."
        case .checkIns: "No check-ins yet."
        case .wanna: "No Wanna activity yet."
        }
    }
}

struct ProfileActivityRow: View {
    let item: ProfileActivityItem
    let action: () -> Void

    private var timestamp: ProfileActivityTimestampText {
        ProfileActivityPresenter.timestampText(for: item.timestamp)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                WanderCategoryEmoji(emoji: item.visiblePlace.categoryEmoji, size: 24)
                    .frame(width: 42, height: 42)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.visiblePlace.place.canonicalName)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(statusColor)
                        Text(item.kind.title)
                        if let locality = normalized(item.visiblePlace.place.locality) {
                            Text("·")
                            Text(locality)
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(timestamp.date)
                    Text(timestamp.time)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 62, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.visiblePlace.place.canonicalName), \(item.kind.title), \(timestamp.date) at \(timestamp.time)"
        )
        .accessibilityHint("Opens this place at its activity")
    }

    private var statusColor: Color {
        item.kind == .checkIn
            ? WanderTheme.stateSuccess.color
            : WanderTheme.stateWarning.color
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
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
                    ForEach(summary.displayedDayStates.indices, id: \.self) { index in
                        Capsule()
                            .fill(dayFill(summary.displayedDayStates[index]))
                            .frame(width: 10, height: 4)
                            .overlay {
                                if summary.displayedDayStates[index] == .streakSave {
                                    Capsule()
                                        .stroke(WanderTheme.terracotta.color, lineWidth: 1)
                                }
                            }
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
        if summary.isRecoveryAvailable {
            return "restore \(summary.recoverableCount)-day streak"
        }
        guard summary.currentCount > 0 else { return "start a streak" }
        return "\(summary.currentCount)-day streak"
    }

    private var accessibilityLabel: String {
        if summary.isRecoveryAvailable {
            return "Your \(summary.recoverableCount) day save streak can be restored today. Check in or save a place to use your Streak Save."
        }
        guard summary.currentCount > 0 else {
            return "No active save streak. Check in or save a Wanna place to start one."
        }
        let todayStatus = summary.isTodayCovered ? "Today is covered." : "Save today to keep it going."
        let streakSaveStatus = summary.displayedDayStates.contains(.streakSave)
            ? "One missed day was protected by a Streak Save."
            : ""
        return "\(summary.currentCount) day save streak. Best streak \(summary.bestCount) days. \(todayStatus) \(streakSaveStatus)"
    }

    private func dayFill(_ state: SaveStreakDayState) -> Color {
        switch state {
        case .saved:
            WanderTheme.terracotta.color
        case .streakSave:
            WanderTheme.terracotta.color.opacity(0.2)
        case .missed:
            WanderTheme.borderHairline.color.opacity(0.65)
        }
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
                    label: CheckInCopy.pluralNoun.uppercased(),
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

                Grid(horizontalSpacing: WanderTheme.spacing3) {
                    GridRow {
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
    let dateAction: (ProfileCalendarDaySummary) -> Void

    private var calendar: Calendar { .current }
    private var weekdays: [String] { calendar.veryShortStandaloneWeekdaySymbols }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ownerLabel) calendar")
                        .font(WanderTypography.editorialMajorSectionTitle)
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

            Text(monthActivitySummary)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .accessibilityLabel(monthActivitySummary)

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
                                let summary = insights.monthDaySummaries[day]
                                    ?? ProfileCalendarDaySummary.empty(on: day)
                                ProfileCalendarDayCell(
                                    date: date,
                                    summary: summary,
                                    isToday: calendar.isDateInToday(date)
                                )
                                    .contentShape(Rectangle())
                                    .onTapGesture { dateAction(summary) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Shows places from this date")
                                    .accessibilityAction { dateAction(summary) }
                            } else {
                                ProfileCalendarDayCell(date: nil, summary: nil, isToday: false)
                            }
                        }
                    }
                }
            }

            ProfileCalendarLegend()
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))
    }

    private var monthTitle: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthActivitySummary: String {
        CheckInCopy.count(insights.monthVisitCount)
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

}

private struct ProfileMonthButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .foregroundStyle(WanderTheme.textInk.color)
                .contentShape(Circle())
                .wanderGlassCapsule()
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
    let summary: ProfileCalendarDaySummary?
    let isToday: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if let date {
                ProfileCalendarActivityMarker(
                    state: (summary?.visitCount ?? 0) > 0 ? .visit : .none,
                    size: 40,
                    label: "\(Calendar.current.component(.day, from: date))"
                )
                .padding(.top, isToday ? 13 : 5)

                if isToday {
                    Text("NOW")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, 5)
                        .frame(height: 13)
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 0.75))
                        .offset(y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let date else { return "" }
        let base = date.formatted(.dateTime.month(.wide).day())
        let today = isToday ? ", today" : ""
        guard let summary, summary.visitCount > 0 else {
            return "\(base)\(today), no activity"
        }
        return "\(base)\(today), \(CheckInCopy.count(summary.visitCount))"
    }
}

private struct ProfileCalendarActivityMarker: View {
    let state: ProfileCalendarActivityState
    let size: CGFloat
    let label: String?

    var body: some View {
        ZStack {
            if state == .visit {
                Circle()
                    .fill(WanderTheme.terracotta.color)
                    .frame(width: size - 4, height: size - 4)
            }

            if let label {
                Text(label)
                    .font(.system(size: size * 0.35, weight: state == .none ? .bold : .black))
                    .foregroundStyle(
                        state == .visit
                            ? WanderTheme.textOnAction.color
                            : WanderTheme.textInk.color
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ProfileCalendarLegend: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            item(state: .visit, title: CheckInCopy.pluralNoun)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(WanderTheme.textMuted.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar legend: filled is check-ins")
    }

    private func item(state: ProfileCalendarActivityState, title: String) -> some View {
        HStack(spacing: 5) {
            ProfileCalendarActivityMarker(state: state, size: 18, label: nil)
                .accessibilityHidden(true)
            Text(title)
        }
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
    let ownerLabel: String
    let summaryAction: (ProfileMapSummaryKind, ProfileSummaryItem) -> Void
    @State private var selectedSummary: ProfileMapSummaryKind = .places
    @State private var shareImageFileURL: URL?
    @State private var activeShareItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ownerLabel) map")
                        .font(WanderTypography.editorialMajorSectionTitle)
                    Text(mapCountSummary)
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
                .accessibilityLabel("Map of \(ownerLabel) checked-in places")

            ProfileMapSummaryPicker(selection: $selectedSummary)

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
                        HStack(spacing: 0) {
                            Button {
                                summaryAction(selectedSummary, item)
                            } label: {
                                ProfileMapSummaryRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows matching checked-in places")

                            ProfileMapSummaryShareButton(
                                profile: profile,
                                item: item,
                                points: insights.mapPoints(matching: item),
                                activeShareItemID: $activeShareItemID
                            )
                            .padding(.trailing, WanderTheme.spacing2)
                        }
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

    private var mapCountSummary: String {
        let cityLabel = insights.mapCityCount == 1 ? "city" : "cities"
        let placeLabel = insights.mapPlaceCount == 1 ? "place" : "places"
        return "\(insights.mapCityCount) \(cityLabel)  •  \(insights.mapPlaceCount) checked-in \(placeLabel)"
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
        case .places: "\(ownerLabel.capitalized) checked-in places will appear here."
        case .cities: "Cities appear after \(ownerLabel) checked-in places have location details."
        case .countries: "Countries appear after \(ownerLabel) checked-in places have location details."
        }
    }
}

private struct ProfileMapSummaryPicker: View {
    @Binding var selection: ProfileMapSummaryKind

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ForEach(ProfileMapSummaryKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(
                            selection == kind
                                ? WanderTheme.terracottaDark.color
                                : WanderTheme.textInk.color
                        )
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        .contentShape(Capsule())
                        .wanderGlassCapsule(tone: selection == kind ? .selected : .neutral)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == kind ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map summary")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
    }
}

private struct ProfileMapSummaryShareButton: View {
    let profile: LocalProfile
    let item: ProfileSummaryItem
    let points: [ProfileMapPoint]
    @Binding var activeShareItemID: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var shareTask: Task<Void, Never>?
    @State private var shareContent: WanderShareContent?
    @State private var showsShareSheet = false
    @State private var showsShareError = false

    var body: some View {
        Button {
            prepareAndShare()
        } label: {
            ZStack {
                if isPreparing {
                    ProgressView()
                        .tint(WanderTheme.terracotta.color)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .contentShape(Circle())
            .wanderGlassCapsule()
        }
        .buttonStyle(.plain)
        .disabled(activeShareItemID != nil || profile.serverID == nil)
        .opacity(profile.serverID == nil ? 0.45 : 1)
        .accessibilityLabel("Share \(item.title)")
        .accessibilityHint(shareAccessibilityHint)
        .sheet(isPresented: $showsShareSheet, onDismiss: cleanupShareAttachment) {
            if let shareContent {
                WanderShareSheet(content: shareContent)
            }
        }
        .alert("Couldn't prepare this map", isPresented: $showsShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try sharing again.")
        }
        .onDisappear(perform: cancelSharePreparation)
    }

    private func prepareAndShare() {
        shareTask?.cancel()
        showsShareError = false
        activeShareItemID = item.id
        shareTask = Task {
            defer {
                if activeShareItemID == item.id {
                    activeShareItemID = nil
                }
                shareTask = nil
            }

            let request = ProfileMapSnapshotRequest(
                points: points,
                size: CGSize(width: 334, height: 205),
                displayScale: displayScale,
                colorScheme: colorScheme
            )
            guard let image = await ProfileMapSnapshotCache.shared.image(for: request),
                  !Task.isCancelled,
                  let pngData = image.pngData(),
                  let imageFileURL = await WanderShareAttachmentStore.preparePNG(pngData),
                  !Task.isCancelled,
                  let content = WanderShareContent.profileMap(
                    serverID: profile.serverID,
                    displayName: profile.displayName,
                    handle: profile.handle,
                    imageFileURL: imageFileURL,
                    filterTitle: item.title
                  )
            else {
                guard !Task.isCancelled else { return }
                showsShareError = true
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Couldn't prepare this map. Check your connection and try sharing again."
                )
                return
            }

            shareContent = content
            showsShareSheet = true
        }
    }

    private var isPreparing: Bool {
        activeShareItemID == item.id
    }

    private var shareAccessibilityHint: String {
        guard profile.serverID != nil else {
            return "Available after this profile finishes syncing"
        }
        return "Shares the profile link and a map of these \(item.count) checked-in \(item.count == 1 ? "place" : "places")"
    }

    private func cancelSharePreparation() {
        shareTask?.cancel()
        shareTask = nil
        if activeShareItemID == item.id {
            activeShareItemID = nil
        }
    }

    private func cleanupShareAttachment() {
        guard let fileURL = shareContent?.additionalItems.first else {
            shareContent = nil
            return
        }
        shareContent = nil
        Task {
            await WanderShareAttachmentStore.removePreparedPNG(at: fileURL)
        }
    }
}
