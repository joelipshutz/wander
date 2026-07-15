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

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("add friends to this visit")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("They will get their own editable copy of this visit.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: WanderTheme.spacing2)
                Button {
                    isPresentingPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        .background(WanderTheme.terracotta.color)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading || errorMessage != nil)
                .opacity(isLoading || errorMessage != nil ? 0.5 : 1)
                .accessibilityLabel("Add friends to this visit")
            }

            if isLoading {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                    Text("Loading shared friends...")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
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
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
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

struct SharedVisitCompanionLabel: View {
    let companions: [SharedVisitCompanion]
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        if !companions.isEmpty {
            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: -8) {
                    ForEach(companions.prefix(3)) { companion in
                        Button {
                            onSelect?(companion.userID)
                        } label: {
                            WanderAvatar(
                                initials: String(companion.displayName.prefix(2)).uppercased(),
                                avatarURL: companion.avatarURL,
                                size: 26,
                                color: WanderTheme.pinSocial.color
                            )
                            .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(onSelect == nil)
                        .accessibilityLabel("Open \(companion.displayName)'s profile")
                    }
                }
                Text(companionText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
            .accessibilityElement(children: onSelect == nil ? .combine : .contain)
        }
    }

    private var companionText: String {
        let names = companions.map(\.displayName)
        if names.count == 1 { return "with \(names[0])" }
        if names.count == 2 { return "with \(names[0]) and \(names[1])" }
        return "with \(names[0]), \(names[1]) +\(names.count - 2)"
    }
}

struct SharedVisitInboxCard: View {
    let invitation: SharedVisitInvitation
    let additionalCount: Int
    let onOpen: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: String(invitation.sourceOwnerDisplayName.prefix(2)).uppercased(),
                avatarURL: invitation.sourceOwnerAvatarURL,
                size: 38,
                color: WanderTheme.pinSocial.color
            )
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invitation.sourceOwnerDisplayName) saved \(invitation.placeName) with you")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text(additionalCount > 0 ? "Review visit · +\(additionalCount) more" : "Review your copy")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(width: 32, height: 32)
                    .background(WanderTheme.surfaceRaised.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decline shared visit")
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.terracotta.color.opacity(0.45), lineWidth: 1)
        )
    }
}
