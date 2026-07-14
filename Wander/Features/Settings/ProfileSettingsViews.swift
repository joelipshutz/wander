import SwiftUI

struct ProfileSettingsHome: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    @State private var showsAccountManagement = false
    @State private var showsNotifications = false
    @State private var showsDeleteWarning = false
    @State private var showsFinalDeleteWarning = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                privacySection
                supportSection

                Section {
                    Button(role: .destructive) {
                        showsDeleteWarning = true
                    } label: {
                        Label(isDeleting ? "deleting account..." : "delete my account", systemImage: "trash")
                            .font(.system(size: 15, weight: .black))
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                    }
                    .disabled(isDeleting || !auth.isSignedIn)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
            .sheet(isPresented: $showsAccountManagement) {
                ClerkAccountManagementView()
                    .onDisappear { Task { await auth.refreshSession() } }
            }
            .sheet(isPresented: $showsNotifications) {
                NotificationSettingsSheet()
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .environmentObject(pushNotifications)
            }
            .alert("You are deleting your account", isPresented: $showsDeleteWarning) {
                Button("Yes", role: .destructive) { showsFinalDeleteWarning = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to continue?")
            }
            .alert("Are you sure you want to permanently delete your account?", isPresented: $showsFinalDeleteWarning) {
                Button("Yes, delete", role: .destructive) { Task { await deleteAccount() } }
                Button("No, cancel", role: .cancel) {}
            } message: {
                Text("You will not be able to recover the data associated with your account.")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("account") {
            switch auth.state {
            case .signedIn(let session):
                ProfileSettingsIdentityRow(session: session, avatarURL: store.currentUser.avatarURL)
                accountRow("change email", value: session.email, icon: "envelope")
                accountRow("change phone number", value: session.phoneNumber ?? "optional", icon: "phone")
                accountRow("change password", value: nil, icon: "key")

                Button {
                    Task {
                        await pushNotifications.unregisterStoredDeviceTokenIfPossible(backend: backend)
                        try? await auth.signOut()
                    }
                } label: {
                    Label(auth.isSigningOut ? "signing out..." : "sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(WanderTheme.stateError.color)
                }
                .disabled(auth.isSigningOut)
            case .signedOut:
                Button("sign in") { auth.beginSignIn() }
            case .loading:
                ProgressView("checking account...")
            case .unavailable(let message):
                Text(message).foregroundStyle(WanderTheme.stateError.color)
            }
        }
    }

    private var privacySection: some View {
        Section("privacy and safety") {
            NavigationLink {
                ProfilePrivacyTrustScreen()
            } label: {
                Label("privacy and trust", systemImage: "shield.lefthalf.filled")
            }

            NavigationLink {
                BlockedMutedScreen()
            } label: {
                Label("blocked and muted accounts", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    private var supportSection: some View {
        Section("app") {
            Button {
                auth.requireSignIn(for: .manageNotifications) { showsNotifications = true }
            } label: {
                HStack {
                    Label("notifications", systemImage: "bell")
                    Spacer()
                    Text(pushNotifications.statusTitle.lowercased())
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .foregroundStyle(WanderTheme.textInk.color)

            HStack {
                Label("data and sync", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Text("\(store.pendingSyncCount) pending")
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }

    private func accountRow(_ title: String, value: String?, icon: String) -> some View {
        Button { showsAccountManagement = true } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Label(title, systemImage: icon)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
        }
        .foregroundStyle(WanderTheme.textInk.color)
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            await pushNotifications.unregisterStoredDeviceTokenIfPossible(backend: backend)
            try await auth.deleteAccount()
            store.resetAfterAccountDeletion()
            dismiss()
        } catch {
            errorMessage = "Your account could not be deleted. Nothing was removed. Please try again."
        }
    }
}

private struct ProfileSettingsIdentityRow: View {
    let session: AuthSession
    let avatarURL: String?

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: String((session.displayName ?? session.handle ?? "You").prefix(2)).uppercased(),
                avatarURL: avatarURL,
                size: 44,
                color: WanderTheme.avatarRyan.color
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName ?? "Your account")
                    .font(.system(size: 15, weight: .black))
                Text(session.handle.map { "@\($0)" } ?? session.userID)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(.vertical, WanderTheme.spacing1)
    }
}

struct ProfilePrivacyTrustScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var pendingPrivateProfileValue: Bool?
    @State private var showsWarning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle(isOn: privateProfileBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SettingsProfilePrivacySurface.title)
                            .font(.system(size: 15, weight: .black))
                        Text(SettingsProfilePrivacySurface.body(isEnabled: store.isPrivateProfile))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }
                .tint(WanderTheme.textInk.color)

                PlaceVisibilityStealthToggle(
                    title: SettingsDefaultPlacePrivacySurface.toggleTitle,
                    visibility: Binding(
                        get: { store.isPrivateProfile ? .selfOnly : store.defaultVisibility.normalizedForStealthMode },
                        set: { value in
                            guard !store.isPrivateProfile else { return }
                            store.defaultVisibility = value
                            Task { await persistPrivacyPreferences() }
                        }
                    ),
                    showsContainer: false,
                    helperCopy: { visibility in
                        SettingsDefaultPlacePrivacySurface.helperCopy(
                            for: visibility,
                            isLockedByPrivateProfile: store.isPrivateProfile
                        )
                    }
                )
                .disabled(store.isPrivateProfile)
                .opacity(store.isPrivateProfile ? 0.56 : 1)
            }

            Section("how privacy works") {
                ForEach(SettingsTrustSurface.facts) { fact in
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        Image(systemName: fact.icon)
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.title).font(.system(size: 15, weight: .black))
                            Text(fact.body)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
            }


            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.stateError.color)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WanderTheme.canvasWarm.color)
        .navigationTitle("privacy and trust")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            SettingsProfilePrivacySurface.warningTitle(enabling: pendingPrivateProfileValue ?? false),
            isPresented: $showsWarning
        ) {
            Button("Cancel", role: .cancel) { pendingPrivateProfileValue = nil }
            Button(SettingsProfilePrivacySurface.warningConfirmTitle(enabling: pendingPrivateProfileValue ?? false)) {
                guard let value = pendingPrivateProfileValue else { return }
                store.setPrivateProfile(value)
                pendingPrivateProfileValue = nil
                Task {
                    await persistPrivacyPreferences()
                    _ = await store.syncUnsyncedOwnPlaces(backend: backend)
                }
            }
        } message: {
            Text(SettingsProfilePrivacySurface.warningBody(enabling: pendingPrivateProfileValue ?? false))
        }
    }

    private var privateProfileBinding: Binding<Bool> {
        Binding(
            get: { store.isPrivateProfile },
            set: { value in
                guard value != store.isPrivateProfile else { return }
                pendingPrivateProfileValue = value
                showsWarning = true
            }
        )
    }


    @MainActor
    private func persistPrivacyPreferences() async {
        errorMessage = nil
        do {
            try await store.updateCurrentUserDetails(
                ProfileDetailsUpdate(
                    bio: store.currentUser.bio,
                    homeArea: store.currentUser.homeArea,
                    defaultVisibility: store.defaultVisibility,
                    isPrivateProfile: store.isPrivateProfile
                ),
                backend: backend
            )
        } catch {
            errorMessage = "Your privacy preference is saved on this device and will sync when the connection recovers."
        }
    }
}

enum ProfileRelationshipFilter: String, CaseIterable, Identifiable {
    case blocked
    case muted
    var id: String { rawValue }
    var title: String { rawValue == "blocked" ? "Blocked accounts" : "Muted accounts" }
}

struct BlockedMutedScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedTab: ProfileRelationshipFilter = .blocked

    var body: some View {
        VStack(spacing: 0) {
            Picker("Account controls", selection: $selectedTab) {
                ForEach(ProfileRelationshipFilter.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(WanderTheme.spacing4)

            let profiles = selectedTab == .blocked ? store.blockedProfiles() : store.mutedProfiles()
            if profiles.isEmpty {
                BlockedMutedEmptyState(tab: selectedTab)
            } else {
                List(profiles) { profile in
                    HStack(spacing: WanderTheme.spacing3) {
                        WanderAvatar(
                            initials: String(profile.displayName.prefix(2)).uppercased(),
                            avatarURL: profile.avatarURL,
                            size: 42,
                            color: WanderTheme.avatarRyan.color
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName).font(.system(size: 15, weight: .black))
                            Text("@\(profile.handle)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        Spacer()
                        Button(selectedTab == .blocked ? "unblock" : "unmute") {
                            auth.requireSignIn(for: .manageBlocks) {
                                Task {
                                    if selectedTab == .blocked {
                                        await store.unblock(userID: profile.id, backend: backend)
                                    } else {
                                        await store.unmute(userID: profile.id, backend: backend)
                                    }
                                }
                            }
                        }
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(WanderTheme.canvasWarm.color)
        .navigationTitle("blocked and muted")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refreshRemoteBlocks(backend: backend)
            await store.refreshRemoteMutes(backend: backend)
        }
    }
}

private struct BlockedMutedEmptyState: View {
    let tab: ProfileRelationshipFilter

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: tab == .blocked ? "person.crop.circle.badge.xmark" : "speaker.slash.circle")
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(WanderTheme.categoryMoss.color)
            Text(tab == .blocked ? "You haven't blocked anyone" : "You haven't muted anyone")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch tab {
        case .blocked:
            "Members you block will not be able to see your content and you will not be able to see theirs."
        case .muted:
            "Activity by members you mute will not appear in your newsfeed and you will not receive notifications for this person."
        }
    }
}
