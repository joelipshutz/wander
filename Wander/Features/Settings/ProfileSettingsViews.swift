import SwiftUI

struct ProfileSettingsHome: View {
    let onNUXDebugSettingsChanged: () -> Void

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
    @State private var isNUXEnabled = false
    @State private var isNUXReplayQueued = false

    private let walkthroughDebugPreferences = FirstVisitWalkthroughDebugPreferences()

    init(onNUXDebugSettingsChanged: @escaping () -> Void = {}) {
        self.onNUXDebugSettingsChanged = onNUXDebugSettingsChanged
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                mapSection
                privacySection
                supportSection
                if isDebugSettingsEntitled {
                    debugSettingsSection
                }

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
        .onChange(of: debugSettingsUserID, initial: true) { _, _ in
            refreshDebugSettingsState()
        }
        .onChange(of: isDebugSettingsEntitled) { _, isEntitled in
            if isEntitled {
                refreshDebugSettingsState()
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
            case .offline(let session, _):
                ProfileSettingsIdentityRow(session: session, avatarURL: store.currentUser.avatarURL)
                Label("Saved map available offline", systemImage: "wifi.slash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Button {
                    Task { try? await auth.signOut() }
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

    private var mapSection: some View {
        Section {
            NavigationLink {
                DefaultMapFilterSettingsScreen()
            } label: {
                HStack {
                    Label("default map filter", systemImage: "map")
                    Spacer()
                    Label(store.defaultMapFilter.title, systemImage: store.defaultMapFilter.systemImage)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .tint(WanderTheme.terracotta.color)
            .accessibilityIdentifier("settings.map.defaultFilter")
        } header: {
            Text("map")
        } footer: {
            Text("Used whenever the map opens or resets on this device.")
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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

            settingsLink(
                "import help",
                icon: "square.and.arrow.down",
                destination: ImportHelpDestination.url
            )
            settingsLink(
                "help and support",
                icon: "questionmark.circle",
                destination: RecmeSettingsWebDestination.support
            )
            settingsLink(
                "privacy policy",
                icon: "hand.raised",
                destination: RecmeSettingsWebDestination.privacy
            )
            settingsLink(
                "terms of use",
                icon: "doc.text",
                destination: RecmeSettingsWebDestination.terms
            )
            settingsLink(
                "community guidelines",
                icon: "person.3",
                destination: RecmeSettingsWebDestination.community
            )
            settingsLink(
                "privacy choices",
                icon: "slider.horizontal.3",
                destination: RecmeSettingsWebDestination.privacyChoices
            )
        }
    }

    // Debug settings is intentionally a server-entitled tester surface rather
    // than an iOS identity allowlist or a #if DEBUG block. That keeps it hidden
    // from normal accounts while letting Joe and Ryan test release/TestFlight builds.
    private var isDebugSettingsEntitled: Bool {
        guard let userID = debugSettingsUserID else { return false }
        return backend.featureFlag(.debugSettings, for: userID) == true
    }

    private var debugSettingsUserID: String? {
        auth.state.session?.userID
    }

    private var debugSettingsSection: some View {
        Section("debug settings") {
            Toggle(
                isOn: Binding(
                    get: { isNUXEnabled },
                    set: { newValue in
                        guard let userID = debugSettingsUserID else { return }
                        walkthroughDebugPreferences.setNUXEnabled(newValue, for: userID)
                        refreshDebugSettingsState()
                        if !newValue {
                            onNUXDebugSettingsChanged()
                        }
                    }
                )
            ) {
                Label("first-visit NUX", systemImage: "sparkles.rectangle.stack")
            }
            .tint(WanderTheme.terracotta.color)
            .accessibilityIdentifier("settings.debug.firstVisitNUX")

            Text(debugNUXStatusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
    }

    private var debugNUXStatusMessage: String {
        if isNUXReplayQueued {
            return "On for this account on this device. The NUX will restart on the next app launch."
        }
        if isNUXEnabled {
            return "On for this account on this device. Switch it off and back on to replay it."
        }
        return "Off for this account on this device. Other users are unaffected."
    }

    private func refreshDebugSettingsState() {
        guard let userID = debugSettingsUserID else {
            isNUXEnabled = false
            isNUXReplayQueued = false
            return
        }
        isNUXEnabled = walkthroughDebugPreferences.nuxOverride(for: userID)
            ?? backend.featureFlag(.firstVisitNUX, for: userID)
            ?? false
        isNUXReplayQueued = walkthroughDebugPreferences.isReplayRequested(for: userID)
    }

    private func settingsLink(
        _ title: String,
        icon: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .foregroundStyle(WanderTheme.textInk.color)
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
        let deletingUserID: String? = if case .signedIn(let session) = auth.state {
            session.userID
        } else {
            nil
        }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            await pushNotifications.unregisterStoredDeviceTokenIfPossible(backend: backend)
            try await auth.deleteAccount()
            if let deletingUserID {
                OnboardingCompletionStore().clear(for: deletingUserID)
            }
            store.resetAfterAccountDeletion()
            dismiss()
        } catch {
            errorMessage = "Your account could not be deleted. Nothing was removed. Please try again."
        }
    }
}

private struct DefaultMapFilterSettingsScreen: View {
    @EnvironmentObject private var store: WanderStore

    var body: some View {
        List {
            Section {
                ForEach(MapSource.allCases) { source in
                    Button {
                        store.defaultMapFilter = source
                    } label: {
                        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                            Image(systemName: source.systemImage)
                                .font(.system(.body, design: .default, weight: .bold))
                                .foregroundStyle(WanderTheme.terracotta.color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                                Text(source.title)
                                    .font(.system(.body, design: .default, weight: .bold))
                                    .foregroundStyle(WanderTheme.textInk.color)

                                Text(source.subtitle)
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: WanderTheme.spacing2)

                            if store.defaultMapFilter == source {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundStyle(WanderTheme.terracotta.color)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.title). \(source.subtitle)")
                    .accessibilityValue(store.defaultMapFilter == source ? "Selected" : "")
                    .accessibilityIdentifier("settings.map.defaultFilter.\(source.rawValue)")
                }
            } footer: {
                Text("Used whenever the map opens or resets on this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(WanderTheme.canvasWarm.color)
        .navigationTitle("default map filter")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum RecmeSettingsWebDestination {
    static let support = URL(string: "https://getrec.me/support")!
    static let privacy = URL(string: "https://getrec.me/privacy")!
    static let terms = URL(string: "https://getrec.me/terms")!
    static let community = URL(string: "https://getrec.me/community")!
    static let privacyChoices = URL(string: "https://getrec.me/privacy-choices")!
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
                if let publicHandle = SettingsAccountIdentityPresentation.publicHandle(for: session) {
                    Text(publicHandle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
        }
        .padding(.vertical, WanderTheme.spacing1)
    }
}

struct SettingsAccountIdentityPresentation {
    static func publicHandle(for session: AuthSession) -> String? {
        guard let handle = session.handle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !handle.isEmpty else {
            return nil
        }

        return handle.hasPrefix("@") ? handle : "@\(handle)"
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
                .font(WanderTypography.displayScreenTitle)
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
