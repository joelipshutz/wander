import SwiftUI

struct SharedVisitInviteSection: View {
    @EnvironmentObject private var store: WanderStore
    @Binding var selectedUserIDs: [String]
    var isLoading = false
    var errorMessage: String?
    var onRetry: (() -> Void)?
    @State private var isPresentingPicker = false

    private var selectedFriends: [LocalProfile] {
        selectedUserIDs.compactMap { userID in
            store.profiles.first { $0.id == userID }
        }
    }

    private var hasExpandedContent: Bool {
        isLoading || errorMessage != nil || !selectedFriends.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Button {
                isPresentingPicker = true
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.pinSocial.color)
                    Text("friends")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Spacer()

                    Text(selectedFriends.isEmpty ? "add" : "\(selectedFriends.count) added")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || errorMessage != nil)
            .opacity(isLoading || errorMessage != nil ? 0.5 : 1)
            .accessibilityLabel("Add friends to this check-in")
            .accessibilityValue(selectedFriends.isEmpty ? "None added" : "\(selectedFriends.count) added")

            if isLoading {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                    Text("Loading shared friends...")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .padding(.horizontal, WanderTheme.spacing3)
            } else if let errorMessage {
                HStack(spacing: WanderTheme.spacing2) {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.stateError.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
            }

            ForEach(selectedFriends) { friend in
                HStack(spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: friend.initials,
                        avatarURL: friend.avatarURL,
                        size: 36,
                        color: WanderTheme.pinSocial.color
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .font(.system(size: 14, weight: .black))
                        Text("@\(friend.handle)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                    Button {
                        selectedUserIDs.removeAll { $0 == friend.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(friend.displayName)")
                }
                .padding(.horizontal, WanderTheme.spacing3)
            }
        }
        .padding(.bottom, hasExpandedContent ? WanderTheme.spacing3 : 0)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color)
        )
        .sheet(isPresented: $isPresentingPicker) {
            SharedVisitFriendPicker(selectedUserIDs: $selectedUserIDs)
                .environmentObject(store)
        }
    }
}

struct SharedVisitFriendPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @Binding var selectedUserIDs: [String]
    @State private var query = ""

    private var friends: [LocalProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.following(of: store.currentUser.id)
            .filter { store.relationship(to: $0.id) == .mutual && !$0.isPrivateProfile }
            .filter { profile in
                normalizedQuery.isEmpty
                    || profile.displayName.lowercased().contains(normalizedQuery)
                    || profile.handle.lowercased().contains(normalizedQuery)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WanderTheme.textMuted.color)
                        TextField("Search friends", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("friends") {
                    if friends.isEmpty {
                        Text("No mutual friends available.")
                            .foregroundStyle(WanderTheme.textMuted.color)
                    } else {
                        ForEach(friends) { friend in
                            Button {
                                toggle(friend.id)
                            } label: {
                                HStack(spacing: WanderTheme.spacing3) {
                                    WanderAvatar(
                                        initials: friend.initials,
                                        avatarURL: friend.avatarURL,
                                        size: 40,
                                        color: WanderTheme.pinSocial.color
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName)
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundStyle(WanderTheme.textInk.color)
                                        Text("@\(friend.handle)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(WanderTheme.textMuted.color)
                                    }
                                    Spacer()
                                    Image(systemName: selectedUserIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(selectedUserIDs.contains(friend.id) ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }

    private func toggle(_ userID: String) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.removeAll { $0 == userID }
        } else if selectedUserIDs.count < 19 {
            selectedUserIDs.append(userID)
        }
    }
}

enum SharedVisitCompanionPresentation {
    static func ordered(
        _ companions: [SharedVisitCompanion],
        currentUserID: String
    ) -> [SharedVisitCompanion] {
        companions.filter { $0.userID == currentUserID }
            + companions.filter { $0.userID != currentUserID }
    }

    static func text(
        companions: [SharedVisitCompanion],
        currentUserID: String
    ) -> String {
        let names = ordered(companions, currentUserID: currentUserID).map { companion in
            companion.userID == currentUserID ? "You" : companion.displayName
        }
        guard !names.isEmpty else { return "" }
        if names.count == 1 { return "with \(names[0])" }
        if names.count == 2 { return "with \(names[0]) and \(names[1])" }
        return "with \(names[0]), \(names[1]) +\(names.count - 2)"
    }
}

struct SharedVisitCompanionLabel: View {
    let companions: [SharedVisitCompanion]
    let currentUserID: String
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        if !companions.isEmpty {
            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: -8) {
                    ForEach(displayCompanions.prefix(3)) { companion in
                        if companion.userID == currentUserID {
                            companionAvatar(companion)
                                .accessibilityLabel("You")
                        } else if let onSelect {
                            Button {
                                onSelect(companion.userID)
                            } label: {
                                companionAvatar(companion)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(companion.displayName)'s profile")
                        } else {
                            companionAvatar(companion)
                                .accessibilityLabel(companion.displayName)
                        }
                    }
                }
                Text(
                    SharedVisitCompanionPresentation.text(
                        companions: companions,
                        currentUserID: currentUserID
                    )
                )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
            .accessibilityElement(children: onSelect == nil ? .combine : .contain)
        }
    }

    private var displayCompanions: [SharedVisitCompanion] {
        SharedVisitCompanionPresentation.ordered(companions, currentUserID: currentUserID)
    }

    private func companionAvatar(_ companion: SharedVisitCompanion) -> some View {
        WanderAvatar(
            initials: String(companion.displayName.prefix(2)).uppercased(),
            avatarURL: companion.avatarURL,
            size: 26,
            color: WanderTheme.pinSocial.color
        )
        .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
    }
}

struct SharedVisitBannerTracker {
    private(set) var knownInvitationKeys: Set<String> = []

    static func key(participantID: String, generation: Int) -> String {
        "\(participantID):\(generation)"
    }

    static func key(for invitation: SharedVisitInvitation) -> String {
        key(participantID: invitation.participantID, generation: invitation.invitationGeneration)
    }

    mutating func seed(invitationKeys: [String]) {
        knownInvitationKeys = Set(invitationKeys)
    }

    mutating func nextUnseenKey(in invitationKeys: [String]) -> String? {
        let nextKey = invitationKeys.first { !knownInvitationKeys.contains($0) }
        knownInvitationKeys.formUnion(invitationKeys)
        return nextKey
    }
}

enum SharedVisitBannerCopy {
    static func title(inviterName: String, placeName: String) -> String {
        "\(inviterName) tagged you at \(placeName)"
    }
}

struct SharedVisitNotificationBanner: View {
    let invitation: SharedVisitInvitation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: String(invitation.sourceOwnerDisplayName.prefix(2)).uppercased(),
                    avatarURL: invitation.sourceOwnerAvatarURL,
                    size: 42,
                    color: WanderTheme.pinSocial.color
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        SharedVisitBannerCopy.title(
                            inviterName: invitation.sourceOwnerDisplayName,
                            placeName: invitation.placeName
                        )
                    )
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text("Shared check-in · \(relativeInvitationTime)")
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
        .accessibilityLabel(
            "Open check-in invitations. \(SharedVisitBannerCopy.title(inviterName: invitation.sourceOwnerDisplayName, placeName: invitation.placeName))"
        )
    }

    private var relativeInvitationTime: String {
        invitation.invitedAt.formatted(.relative(presentation: .named))
    }
}

struct ProfileSharedVisitInboxRow: View {
    let invitationCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WanderTheme.stateInfo.color)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .background(WanderTheme.skyTint.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text("check-in invitations")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if invitationCount > 0 {
                    Text("\(invitationCount)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(WanderTheme.terracotta.color, in: Circle())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.pinSocial.color.opacity(invitationCount > 0 ? 0.45 : 0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        switch invitationCount {
        case 0: "You're all caught up"
        case 1: "1 waiting for you"
        default: "\(invitationCount) waiting for you"
        }
    }

    private var accessibilityText: String {
        invitationCount == 0
            ? "Check-in invitations, none pending"
            : "Check-in invitations, \(invitationCount) pending"
    }
}

struct SharedVisitInvitationInboxScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    let onReview: (SharedVisitInvitation) -> Void
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var decliningParticipantID: String?
    @State private var declineErrors: [String: String] = [:]

    var body: some View {
        Group {
            if store.sharedVisitInvitations.isEmpty, !isRefreshing {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: WanderTheme.spacing4) {
                        if let refreshError {
                            refreshErrorRow(refreshError)
                        }

                        ForEach(store.sharedVisitInvitations) { invitation in
                            SharedVisitInboxInvitationCard(
                                invitation: invitation,
                                isDeclining: decliningParticipantID == invitation.participantID,
                                errorMessage: declineErrors[invitation.participantID],
                                onReview: { onReview(invitation) },
                                onDecline: { Task { await decline(invitation) } }
                            )
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing8)
                }
                .refreshable { await refresh() }
            }
        }
        .overlay {
            if isRefreshing, store.sharedVisitInvitations.isEmpty {
                ProgressView("Loading invitations...")
                    .font(.system(size: 13, weight: .bold))
                    .tint(WanderTheme.terracotta.color)
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
        .navigationTitle("check-in invitations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
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
            Text("New shared check-ins will show up here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)

            if refreshError != nil {
                Button("Try again") { Task { await refresh() } }
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(minWidth: 128, minHeight: 48)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WanderTheme.spacing8)
    }

    private func refreshErrorRow(_ message: String) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WanderTheme.stateError.color)
            Text(message)
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") { Task { await refresh() } }
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let didRefresh = await store.refreshSharedVisitInbox(backend: backend)
        refreshError = didRefresh ? nil : "Could not refresh invitations. Your saved invitations are still here."
    }

    @MainActor
    private func decline(_ invitation: SharedVisitInvitation) async {
        guard decliningParticipantID == nil else { return }
        decliningParticipantID = invitation.participantID
        declineErrors[invitation.participantID] = nil
        defer { decliningParticipantID = nil }

        let didDecline = await store.declineSharedVisit(
            participantID: invitation.participantID,
            generation: invitation.invitationGeneration,
            backend: backend
        )
        if !didDecline {
            declineErrors[invitation.participantID] = "Could not decline this invitation. Try again."
        }
    }
}

private struct SharedVisitInboxInvitationCard: View {
    let invitation: SharedVisitInvitation
    let isDeclining: Bool
    let errorMessage: String?
    let onReview: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            inviterRow
            Divider().overlay(WanderTheme.borderHairline.color.opacity(0.7))
            placeRow
            if !invitation.tags.isEmpty {
                tagRow
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.stateError.color)
            }
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
                initials: String(invitation.sourceOwnerDisplayName.prefix(2)).uppercased(),
                avatarURL: invitation.sourceOwnerAvatarURL,
                size: 38,
                color: WanderTheme.pinSocial.color
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.sourceOwnerDisplayName)
                    .font(.system(size: 14, weight: .black))
                Text("invited you to a check-in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text(invitation.invitedAt.formatted(.relative(presentation: .numeric)))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
    }

    private var placeRow: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderCategoryEmoji(emoji: invitation.categoryEmoji, size: 27)
                .frame(width: 82, height: 82)
                .background(WanderTheme.categoryMoss.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .stroke(WanderTheme.surfaceRaised.color, lineWidth: 2)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.placeName)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(2)
                Text(placeContext)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Label(invitation.visitedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text(CheckInCopy.noun.uppercased())
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
            Button(action: onDecline) {
                Group {
                    if isDeclining {
                        ProgressView().tint(WanderTheme.stateError.color)
                    } else {
                        Text("Decline")
                    }
                }
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.stateError.color)
                .frame(minWidth: 92, minHeight: 50)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(WanderTheme.stateError.color.opacity(0.45), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeclining)

            Button(action: onReview) {
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
            .disabled(isDeclining)
        }
    }

    private var placeContext: String {
        [invitation.locality, WanderPlaceCategory.broadCategory(for: invitation.primaryCategory)]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }
}
