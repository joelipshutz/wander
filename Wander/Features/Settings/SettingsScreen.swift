import SwiftUI
import UIKit

struct SettingsScreen: View {
    let onDismiss: (() -> Void)?

    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var activeDetail: SettingsDetail?
    @State private var pendingPrivateProfileValue: Bool?
    @State private var showsPrivateProfileWarning = false
    @State private var isUpdatingPrivateProfile = false
    @State private var privacyErrorMessage: String?

    init(
        onDismiss: (() -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ProfileSettingsHome(onDismiss: onDismiss)
            .foregroundStyle(brandMode.primaryText)
            .tint(brandMode.accent)
            .background(brandMode.background.ignoresSafeArea())
    }

    private var header: some View {
        Text("Settings")
            .font(AstirTypography.screenTitle)
            .lineLimit(1)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("Account")

            switch auth.state {
            case .signedIn(let session), .offline(let session, _):
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: initials(for: session),
                        avatarURL: store.currentUser.avatarURL,
                        size: 40,
                        color: WanderTheme.pinSocial.color
                    )
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(session.displayName ?? "Signed In")
                            .font(AstirTypography.control)
                        if let publicHandle = SettingsAccountIdentityPresentation.publicHandle(for: session) {
                            Text(publicHandle)
                                .font(AstirTypography.caption)
                                .foregroundStyle(brandMode.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }

                Button {
                    Task {
                        await pushNotifications.unregisterStoredDeviceTokenIfPossible(
                            backend: backend,
                            userID: session.userID,
                            authSession: auth
                        )
                        do {
                            try await auth.signOut()
                        } catch {
                            await pushNotifications.restoreRegistrationAfterFailedAccountTeardown(
                                userID: session.userID,
                                backend: backend,
                                authSession: auth
                            )
                        }
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        if auth.isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        Text(auth.isSigningOut ? "Signing Out" : "Sign Out")
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.stateError.color.opacity(0.10))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusLarge,
                            style: .continuous
                        )
                    )
                }
                .disabled(auth.isSigningOut)

                if let signOutError = auth.signOutError {
                    Text(signOutError)
                        .font(AstirTypography.caption)
                        .foregroundStyle(WanderTheme.stateError.color)
                }
            case .signedOut:
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(brandMode.accentText)
                        .frame(width: 38, height: 38)
                        .background(brandMode.accentWash)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("Signed Out")
                            .font(AstirTypography.control)
                        Text("Sign In To Sync And Follow People.")
                            .font(AstirTypography.caption)
                            .foregroundStyle(brandMode.secondaryText)
                    }
                    Spacer()
                }

                Button {
                    auth.beginSignIn()
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Sign In")
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentForeground)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(brandMode.accent)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusLarge,
                            style: .continuous
                        )
                    )
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text("Checking Account...")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.secondaryText)
                }
            case .unavailable(let message):
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(message)
                        .font(AstirTypography.label)
                        .foregroundStyle(WanderTheme.stateError.color)
                    Text("Rebuild With Local Auth Config To Sign In Or Out.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("Privacy")

            privateProfileToggle

            if isUpdatingPrivateProfile {
                ProgressView("Updating Privacy...")
                    .font(AstirTypography.caption)
            } else if let privacyErrorMessage {
                Text(privacyErrorMessage)
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.stateError.color)
            }

            Divider()
                .overlay(brandMode.border)

            PlaceVisibilityStealthToggle(
                title: SettingsDefaultPlacePrivacySurface.toggleTitle,
                visibility: Binding(
                    get: { store.isPrivateProfile ? .selfOnly : store.defaultVisibility.normalizedForStealthMode },
                    set: { newVisibility in
                        guard !store.isPrivateProfile else { return }
                        store.defaultVisibility = newVisibility
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
        .onAppear {
            if !store.isPrivateProfile {
                store.defaultVisibility = store.defaultVisibility.normalizedForStealthMode
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var privateProfileToggle: some View {
        Toggle(
            isOn: Binding(
                get: { store.isPrivateProfile },
                set: { nextValue in
                    guard nextValue != store.isPrivateProfile else { return }
                    pendingPrivateProfileValue = nextValue
                    showsPrivateProfileWarning = true
                }
            )
        ) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Image(systemName: store.isPrivateProfile ? "lock.shield.fill" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 38, height: 38)
                    .background(brandMode.accentWash)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(SettingsProfilePrivacySurface.title)
                        .font(AstirTypography.control)
                    Text(SettingsProfilePrivacySurface.body(isEnabled: store.isPrivateProfile))
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(brandMode.accent)
        .disabled(isUpdatingPrivateProfile)
        .accessibilityIdentifier(SettingsProfilePrivacySurface.accessibilityID)
    }

    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("Blocked Users")
            let blocked = store.blockedProfiles()
            if blocked.isEmpty {
                Text("No One Blocked.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
            } else {
                ForEach(blocked) { profile in
                    HStack {
                        WanderAvatar(
                            initials: String(profile.displayName.prefix(2)).uppercased(),
                            avatarURL: profile.avatarURL,
                            size: 34,
                            color: WanderTheme.stateError.color
                        )
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                                .font(AstirTypography.control)
                            Text("@\(profile.handle)")
                                .font(AstirTypography.caption)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        Spacer()
                        Button("Unblock") {
                            auth.requireSignIn(for: .manageBlocks) {
                                Task {
                                    await store.unblock(userID: profile.id, backend: backend)
                                }
                            }
                        }
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.accentText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var groupedRows: some View {
        VStack(spacing: WanderTheme.spacing3) {
            SettingsRow(
                title: SettingsTrustSurface.rowTitle,
                subtitle: SettingsTrustSurface.rowSubtitle,
                systemImage: "shield.lefthalf.filled",
                accessibilityIdentifier: SettingsTrustSurface.rowAccessibilityID
            ) {
                activeDetail = .trust
            }
            SettingsRow(title: "Contacts", subtitle: "Managed In iOS Settings", systemImage: "person.crop.rectangle.stack")
            SettingsRow(title: "Notifications", subtitle: pushNotifications.statusTitle, systemImage: "bell") {
                auth.requireSignIn(for: .manageNotifications) {
                    activeDetail = .notifications
                }
            }
        }
    }

    private func initials(for session: AuthSession) -> String {
        let source = session.displayName ?? session.handle ?? session.userID
        return String(source.prefix(2)).uppercased()
    }
}

private enum SettingsDetail: String, Identifiable {
    case trust
    case notifications

    var id: String { rawValue }
}

private struct SettingsSectionTitle: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(AstirTypography.sectionTitle)
            .foregroundStyle(brandMode.primaryText)
    }
}

private struct TrustAndPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text(SettingsTrustSurface.sheetTitle)
                            .font(AstirTypography.screenTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(SettingsTrustSurface.sheetIntro)
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(SettingsTrustSurface.facts) { fact in
                        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                            Image(systemName: fact.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(brandMode.accentText)
                                .frame(width: 38, height: 38)
                                .background(brandMode.accentWash)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                                Text(fact.title)
                                    .font(AstirTypography.cardTitle)
                                Text(fact.body)
                                    .font(AstirTypography.bodySmall)
                                    .foregroundStyle(brandMode.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(WanderTheme.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(brandMode.raisedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(SettingsTrustSurface.factAccessibilityPrefix + fact.id)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .astirScreen()
            .accessibilityIdentifier(SettingsTrustSurface.sheetAccessibilityID)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentText)
                }
            }
        }
    }
}

struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @EnvironmentObject private var calendarReservations: CalendarReservationManager
    @State private var preferences = NotificationPreferences.allDisabled
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isChangingEnabledState = false
    @State private var isWaitingForSettingsAuthorization = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("Notifications")
                            .font(AstirTypography.screenTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose The Account Activity Astir Can Send To This Phone.")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statusBlock

                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        SettingsSectionTitle("Push Types")
                        notificationToggle(
                            title: "Follows And Friends",
                            systemImage: "person.2",
                            binding: preferenceBinding(\.socialGraphEnabled) { NotificationPreferencesUpdate(socialGraphEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Shared Lists",
                            systemImage: PlaceListSymbol.systemImage,
                            binding: preferenceBinding(\.sharedListsEnabled) { NotificationPreferencesUpdate(sharedListsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Shared Check-Ins",
                            systemImage: "person.2.badge.plus",
                            binding: preferenceBinding(\.sharedVisitsEnabled) { NotificationPreferencesUpdate(sharedVisitsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Saves From Your Map",
                            systemImage: "map",
                            binding: preferenceBinding(\.recommendationsEnabled) { NotificationPreferencesUpdate(recommendationsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "People You Follow",
                            systemImage: "person.crop.circle.badge.checkmark",
                            binding: preferenceBinding(\.followedActivityEnabled) { NotificationPreferencesUpdate(followedActivityEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Likes And Comments",
                            systemImage: "heart.text.bubble",
                            binding: preferenceBinding(\.engagementEnabled) { NotificationPreferencesUpdate(engagementEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Capture Ready",
                            systemImage: "sparkles",
                            binding: preferenceBinding(\.captureEnabled) { NotificationPreferencesUpdate(captureEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Discovery Digest",
                            systemImage: "calendar.badge.clock",
                            binding: preferenceBinding(\.discoveryDigestEnabled) { NotificationPreferencesUpdate(discoveryDigestEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Wanna Go Reminders",
                            systemImage: "calendar.badge.exclamationmark",
                            binding: preferenceBinding(\.wannaGoRemindersEnabled) { NotificationPreferencesUpdate(wannaGoRemindersEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Reservation Check-In Reminders",
                            systemImage: "fork.knife.circle",
                            binding: preferenceBinding(\.reservationRemindersEnabled) {
                                NotificationPreferencesUpdate(reservationRemindersEnabled: $0)
                            }
                        )
                        notificationToggle(
                            title: "Save Streak Reminders",
                            systemImage: "flame",
                            binding: saveStreakReminderBinding
                        )
                    }
                    .padding(WanderTheme.spacing3)
                    .background(brandMode.raisedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AstirTypography.label)
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .astirScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentText)
                }
            }
        }
        .task(id: auth.state.session?.userID) {
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            guard isWaitingForSettingsAuthorization else { return }
            Task {
                await pushNotifications.refreshAuthorizationStatus()
                guard pushNotifications.canRegisterForRemoteNotifications else { return }
                isWaitingForSettingsAuthorization = false
                await enableNotifications(permissionAlreadyGranted: true)
            }
        }
        .onChange(of: pushNotifications.lastErrorMessage) { _, message in
            if let message {
                errorMessage = message
            }
        }
    }

    private var notificationsEnabled: Bool {
        preferences.pushEnabled && pushNotifications.canRegisterForRemoteNotifications
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 38, height: 38)
                    .background(brandMode.accentWash)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(notificationsEnabled ? "Notifications On" : "Notifications Off")
                        .font(AstirTypography.cardTitle)
                    Text(statusSubtitle)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                }

                Spacer()
            }

            Button {
                Task {
                    if notificationsEnabled {
                        await disableNotifications()
                    } else {
                        await enableNotifications()
                    }
                }
            } label: {
                actionLabel(
                    title: actionButtonTitle,
                    systemImage: notificationsEnabled ? "bell.slash" : "bell.badge"
                )
            }
            .disabled(isChangingEnabledState || isLoading || !auth.isSignedIn || !backend.canRegisterPushNotifications)
        }
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var statusSubtitle: String {
        if notificationsEnabled {
            return "This Device Can Receive Every Enabled Astir Activity Type."
        }
        switch pushNotifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allow Notifications To Turn On Every Activity Type For This Device."
        case .denied:
            return "Enable Alerts In iOS Settings To Receive Pushes."
        case .notDetermined:
            return "Astir Will Ask Only When You Allow It Here."
        @unknown default:
            return "Notification Status Is Unavailable."
        }
    }

    private var actionButtonTitle: String {
        if isChangingEnabledState || pushNotifications.isRequestingAuthorization || pushNotifications.isRegisteringToken {
            return notificationsEnabled ? "Disabling" : "Allowing"
        }
        if notificationsEnabled {
            return "Disable Notifications"
        }
        switch pushNotifications.authorizationStatus {
        case .notDetermined:
            return "Continue"
        case .denied:
            return "Open Settings"
        case .authorized, .provisional, .ephemeral:
            return "Allow Notifications"
        @unknown default:
            return "Continue"
        }
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(AstirTypography.control)
        .foregroundStyle(brandMode.accentForeground)
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
        .background(brandMode.accent)
        .clipShape(
            RoundedRectangle(
                cornerRadius: WanderTheme.radiusLarge,
                style: .continuous
            )
        )
    }

    private func notificationToggle(title: String, systemImage: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 32, height: 32)
                    .background(brandMode.accentWash)
                    .clipShape(Circle())
                Text(title)
                    .font(AstirTypography.control)
            }
        }
        .toggleStyle(.switch)
        .tint(brandMode.accent)
        .disabled(isLoading || isSaving || isChangingEnabledState || !notificationsEnabled || !backend.canRegisterPushNotifications)
    }

    private func preferenceBinding(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>,
        update: @escaping (Bool) -> NotificationPreferencesUpdate
    ) -> Binding<Bool> {
        Binding {
            preferences[keyPath: keyPath]
        } set: { nextValue in
            preferences[keyPath: keyPath] = nextValue
            Task {
                await save(update(nextValue))
            }
        }
    }

    private var saveStreakReminderBinding: Binding<Bool> {
        Binding {
            pushNotifications.saveStreakRemindersEnabled
        } set: { isEnabled in
            guard let userID = auth.state.session?.userID else { return }
            pushNotifications.setSaveStreakRemindersEnabled(
                isEnabled,
                for: userID
            )
            Task {
                await pushNotifications.reconcileSaveStreakReminder(
                    store.saveStreakSummary,
                    backend: backend,
                    userID: userID,
                    authSession: auth
                )
            }
        }
    }

    private func load() async {
        await pushNotifications.refreshAuthorizationStatus()
        guard case .signedIn(let session) = auth.state,
              backend.canRegisterPushNotifications else {
            return
        }
        let userID = session.userID
        pushNotifications.bindNotificationPreferences(to: userID)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedPreferences = try await backend.notificationPreferences()
            guard isCurrentNotificationAccount(userID) else { return }
            let resolvedPreferences = pushNotifications.canRegisterForRemoteNotifications && loadedPreferences.pushEnabled
                ? loadedPreferences
                : .allDisabled
            preferences = resolvedPreferences
            pushNotifications.applyNotificationPreferences(resolvedPreferences, for: userID)
            pushNotifications.configureSaveStreakReminders(for: userID)
            await pushNotifications.reconcileWannaGoReminders(
                store.wannaGoReminderItems,
                backend: backend,
                userID: userID,
                authSession: auth
            )
            guard isCurrentNotificationAccount(userID) else { return }
            await pushNotifications.reconcileSaveStreakReminder(
                store.saveStreakSummary,
                backend: backend,
                userID: userID,
                authSession: auth
            )
        } catch {
            if isCurrentNotificationAccount(userID) {
                errorMessage = "Could Not Load Notification Settings."
            }
        }
    }

    private func enableNotifications(permissionAlreadyGranted: Bool = false) async {
        guard case .signedIn(let session) = auth.state,
              backend.canRegisterPushNotifications else {
            errorMessage = "Sign In To Turn On Notifications."
            return
        }
        let userID = session.userID

        if pushNotifications.authorizationStatus == .denied && !permissionAlreadyGranted {
            isWaitingForSettingsAuthorization = true
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }

        isChangingEnabledState = true
        errorMessage = nil
        pushNotifications.clearLastError()
        defer { isChangingEnabledState = false }

        if permissionAlreadyGranted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        guard let enabledPreferences = await pushNotifications.enableNotifications(
            backend: backend,
            expectedUserID: userID,
            authSession: auth
        ) else {
            guard isCurrentNotificationAccount(userID) else { return }
            preferences = .allDisabled
            errorMessage = pushNotifications.lastErrorMessage ?? "Notifications Were Not Allowed."
            return
        }
        guard isCurrentNotificationAccount(userID) else { return }
        preferences = enabledPreferences
        pushNotifications.configureSaveStreakReminders(for: userID)
        await pushNotifications.reconcileWannaGoReminders(
            store.wannaGoReminderItems,
            backend: backend,
            userID: userID,
            authSession: auth
        )
        guard isCurrentNotificationAccount(userID) else { return }
        await pushNotifications.reconcileSaveStreakReminder(
            store.saveStreakSummary,
            backend: backend,
            userID: userID,
            authSession: auth
        )
        guard isCurrentNotificationAccount(userID) else { return }
        await calendarReservations.syncIfNeeded(
            backend: backend,
            store: store,
            userID: userID,
            force: true,
            reason: "notifications_enabled"
        )
    }

    private func disableNotifications() async {
        guard case .signedIn(let session) = auth.state,
              backend.canRegisterPushNotifications else { return }
        let userID = session.userID

        isChangingEnabledState = true
        errorMessage = nil
        pushNotifications.clearLastError()
        defer { isChangingEnabledState = false }

        if let disabledPreferences = await pushNotifications.disableNotifications(
            backend: backend,
            userID: userID,
            authSession: auth
        ) {
            guard isCurrentNotificationAccount(userID) else { return }
            preferences = disabledPreferences
        } else if isCurrentNotificationAccount(userID) {
            errorMessage = pushNotifications.lastErrorMessage
        }
    }

    private func save(_ update: NotificationPreferencesUpdate) async {
        guard case .signedIn(let session) = auth.state,
              backend.canRegisterPushNotifications else {
            return
        }
        let userID = session.userID

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let savedPreferences = try await backend.updateNotificationPreferences(update)
            guard isCurrentNotificationAccount(userID) else { return }
            preferences = savedPreferences
            pushNotifications.applyNotificationPreferences(savedPreferences, for: userID)
            await pushNotifications.reconcileWannaGoReminders(
                store.wannaGoReminderItems,
                backend: backend,
                userID: userID,
                authSession: auth
            )
            guard isCurrentNotificationAccount(userID) else { return }
            await pushNotifications.reconcileSaveStreakReminder(
                store.saveStreakSummary,
                backend: backend,
                userID: userID,
                authSession: auth
            )
            guard isCurrentNotificationAccount(userID) else { return }
            if update.reservationRemindersEnabled == true {
                await calendarReservations.syncIfNeeded(
                    backend: backend,
                    store: store,
                    userID: userID,
                    force: true,
                    reason: "reservation_reminders_enabled"
                )
            }
        } catch {
            if isCurrentNotificationAccount(userID) {
                errorMessage = "Could Not Save Notification Settings."
            }
        }
    }

    private func isCurrentNotificationAccount(_ userID: String) -> Bool {
        auth.state.session?.userID == userID
            && pushNotifications.notificationPreferencesUserID == userID
    }
}

struct SettingsTrustSurface {
    static let rowTitle = "Privacy And Trust"
    static let rowSubtitle = "Who Sees Places, Location, Sources"
    static let rowAccessibilityID = "settings.privacyTrust.row"
    static let sheetAccessibilityID = "settings.privacyTrust.sheet"
    static let factAccessibilityPrefix = "settings.privacyTrust.fact."
    static let sheetTitle = "Privacy And Trust"
    static let sheetIntro = "Quick Answers For What Astir Shares, Syncs, And Keeps Private."

    static let facts: [TrustFact] = [
        TrustFact(
            id: "everyone",
            icon: "eye.slash",
            title: "Not Private Means Followers",
            body: "Places Saved Outside Stealth Mode Are Visible To People Who Follow You. They Are Not A Public Internet Feed."
        ),
        TrustFact(
            id: "stealth",
            icon: "lock",
            title: "Stealth Mode Means Private",
            body: "Stealth Places Stay On Your Map For You Only."
        ),
        TrustFact(
            id: "location",
            icon: "location",
            title: "Location Is For Finding Places",
            body: "Astir Uses Location When You Ask For Nearby Candidates. It Does Not Broadcast Live Location."
        ),
        TrustFact(
            id: "extraction",
            icon: "wand.and.stars",
            title: "Extraction Asks First",
            body: "Links And Photos Can Create Candidates Or Drafts. Low-Confidence Results Never Auto-Save To Your Map."
        ),
        TrustFact(
            id: "blocks",
            icon: "person.crop.circle.badge.xmark",
            title: "Blocks Are Hard Blocks",
            body: "Blocking Hides Profiles, Places, Search Results, And Map Content In Both Directions."
        ),
        TrustFact(
            id: "contacts",
            icon: "person.crop.rectangle.stack",
            title: "Contacts Stay Under Your Control",
            body: "If You Choose Find Friends, Astir Securely Compares Allowed Contact Phone Numbers And Emails With Verified Accounts Without Saving Your Address Book. Turn Matching Off In Find Friends Settings, Or Manage Contacts Access In iOS Settings."
        )
    ]
}

struct SettingsDefaultPlacePrivacySurface {
    static let toggleTitle = "Stealth Mode For New Saves"

    static func helperCopy(for visibility: PlaceVisibility, isLockedByPrivateProfile: Bool = false) -> String {
        if isLockedByPrivateProfile {
            return "Locked On By Private Profile. New Places Stay Hidden While Private Profile Is On."
        }

        if visibility.isStealthModeEnabled {
            return "On: New Places Start Private. Only You Can See Them Unless You Turn Stealth Off Before Saving."
        }

        return "Off: New Places Are Visible To People Who Follow You. You Can Still Turn Stealth On Before Saving."
    }
}

struct SettingsProfilePrivacySurface {
    static let title = "Private Profile"
    static let accessibilityID = "settings.profilePrivacy.explainer"

    static func body(isEnabled: Bool) -> String {
        if isEnabled {
            return "Your Saved Places Are In Stealth Mode, New Places Stay Stealth, And Your Username Stays Out Of Search. Existing Friends And Collaborative Lists Stay Unchanged; New Collaborative Lists Are Unavailable."
        }

        return "Your Username Can Appear In Search And You Can Collaborate On Lists."
    }

    static func warningTitle(enabling: Bool) -> String {
        enabling ? "Turn On Private Profile?" : "Turn Off Private Profile?"
    }

    static func warningBody(enabling: Bool) -> String {
        if enabling {
            return "Places Saved By You Will Switch To Stealth Mode, Including Your Check-Ins And Wanna Go Places. Future Saves Stay Stealth And Your Username Will Be Hidden While Private Profile Is On. Your Followers And Existing Collaborative Lists Stay Unchanged, But New Collaborative Lists Are Unavailable."
        }

        return "Your Existing Places Will Stay In Stealth Mode. Your Username Can Appear In Search Again, And Future Saves Will Follow Your Stealth Mode For New Saves Setting."
    }

    static func warningConfirmTitle(enabling: Bool) -> String {
        enabling ? "Turn On" : "Turn Off"
    }
}

struct TrustFact: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let body: String
}

private struct SettingsInlineInfo: View {
    @Environment(\.astirBrandMode) private var brandMode
    let systemImage: String
    let title: String
    let message: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(brandMode.accentText)
                .frame(width: 38, height: 38)
                .background(brandMode.accentWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(AstirTypography.cardTitle)
                Text(message)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SettingsRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let subtitle: String
    let systemImage: String
    var accessibilityIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "settings.row.\(title.lowercased().replacingOccurrences(of: " ", with: "."))")
    }

    private var rowContent: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(brandMode.accentText)
                .frame(width: 38, height: 38)
                .background(brandMode.accentWash)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(AstirTypography.cardTitle)
                Text(subtitle)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .foregroundStyle(brandMode.secondaryText)
            }
        }
        .frame(minHeight: WanderTheme.tapMinimum)
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
