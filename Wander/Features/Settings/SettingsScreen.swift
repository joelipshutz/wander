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
        Text("settings")
            .font(AstirTypography.screenTitle)
            .lineLimit(1)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("account")

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
                        Text(session.displayName ?? "Signed in")
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
                        await pushNotifications.unregisterStoredDeviceTokenIfPossible(backend: backend)
                        try? await auth.signOut()
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        if auth.isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        Text(auth.isSigningOut ? "signing out" : "sign out")
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
                        .foregroundStyle(brandMode.accent)
                        .frame(width: 38, height: 38)
                        .background(brandMode.accentWash)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("Signed out")
                            .font(AstirTypography.control)
                        Text("Sign in to sync and follow people.")
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
                        Text("sign in")
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
                    Text("Checking account...")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.secondaryText)
                }
            case .unavailable(let message):
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(message)
                        .font(AstirTypography.label)
                        .foregroundStyle(WanderTheme.stateError.color)
                    Text("Rebuild with local auth config to sign in or out.")
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
            SettingsSectionTitle("privacy")

            privateProfileToggle

            if isUpdatingPrivateProfile {
                ProgressView("Updating privacy...")
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
                    .foregroundStyle(brandMode.accent)
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
            SettingsSectionTitle("blocked users")
            let blocked = store.blockedProfiles()
            if blocked.isEmpty {
                Text("No one blocked.")
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
                        Button("unblock") {
                            auth.requireSignIn(for: .manageBlocks) {
                                Task {
                                    await store.unblock(userID: profile.id, backend: backend)
                                }
                            }
                        }
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.accent)
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
            SettingsRow(title: "Contacts", subtitle: "managed in iOS Settings", systemImage: "person.crop.rectangle.stack")
            SettingsRow(title: "Notifications", subtitle: pushNotifications.statusTitle.lowercased(), systemImage: "bell") {
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
                                .foregroundStyle(brandMode.accent)
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
                    Button("done") {
                        dismiss()
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accent)
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
                        Text("notifications")
                            .font(AstirTypography.screenTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose the account activity rec.me can send to this phone.")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statusBlock

                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        SettingsSectionTitle("push types")
                        notificationToggle(
                            title: "Follows and friends",
                            systemImage: "person.2",
                            binding: preferenceBinding(\.socialGraphEnabled) { NotificationPreferencesUpdate(socialGraphEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Shared lists",
                            systemImage: "bookmark.square",
                            binding: preferenceBinding(\.sharedListsEnabled) { NotificationPreferencesUpdate(sharedListsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Shared check-ins",
                            systemImage: "person.2.badge.plus",
                            binding: preferenceBinding(\.sharedVisitsEnabled) { NotificationPreferencesUpdate(sharedVisitsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Saves from your map",
                            systemImage: "map",
                            binding: preferenceBinding(\.recommendationsEnabled) { NotificationPreferencesUpdate(recommendationsEnabled: $0) }
                        )
                        notificationToggle(
                            title: "People you follow",
                            systemImage: "person.crop.circle.badge.checkmark",
                            binding: preferenceBinding(\.followedActivityEnabled) { NotificationPreferencesUpdate(followedActivityEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Likes and comments",
                            systemImage: "heart.text.bubble",
                            binding: preferenceBinding(\.engagementEnabled) { NotificationPreferencesUpdate(engagementEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Capture ready",
                            systemImage: "sparkles",
                            binding: preferenceBinding(\.captureEnabled) { NotificationPreferencesUpdate(captureEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Discovery digest",
                            systemImage: "calendar.badge.clock",
                            binding: preferenceBinding(\.discoveryDigestEnabled) { NotificationPreferencesUpdate(discoveryDigestEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Wanna go reminders",
                            systemImage: "calendar.badge.exclamationmark",
                            binding: preferenceBinding(\.wannaGoRemindersEnabled) { NotificationPreferencesUpdate(wannaGoRemindersEnabled: $0) }
                        )
                        notificationToggle(
                            title: "Reservation check-in reminders",
                            systemImage: "fork.knife.circle",
                            binding: preferenceBinding(\.reservationRemindersEnabled) {
                                NotificationPreferencesUpdate(reservationRemindersEnabled: $0)
                            }
                        )
                        notificationToggle(
                            title: "Save streak reminders",
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
                    .foregroundStyle(brandMode.accent)
                }
            }
        }
        .task {
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
                    .foregroundStyle(brandMode.accent)
                    .frame(width: 38, height: 38)
                    .background(brandMode.accentWash)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(notificationsEnabled ? "Notifications on" : "Notifications off")
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
            return "This device can receive every enabled rec.me activity type."
        }
        switch pushNotifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allow notifications to turn on every activity type for this device."
        case .denied:
            return "Enable alerts in iOS Settings to receive pushes."
        case .notDetermined:
            return "rec.me will ask only when you allow it here."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    private var actionButtonTitle: String {
        if isChangingEnabledState || pushNotifications.isRequestingAuthorization || pushNotifications.isRegisteringToken {
            return notificationsEnabled ? "disabling" : "allowing"
        }
        return notificationsEnabled ? "disable notifications" : "allow notifications"
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
                    .foregroundStyle(brandMode.accent)
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
            pushNotifications.setSaveStreakRemindersEnabled(
                isEnabled,
                for: store.currentUser.id
            )
            Task {
                await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary, backend: backend)
            }
        }
    }

    private func load() async {
        await pushNotifications.refreshAuthorizationStatus()
        guard auth.isSignedIn, backend.canRegisterPushNotifications else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedPreferences = try await backend.notificationPreferences()
            preferences = pushNotifications.canRegisterForRemoteNotifications && loadedPreferences.pushEnabled
                ? loadedPreferences
                : .allDisabled
            pushNotifications.applyNotificationPreferences(preferences)
            pushNotifications.configureSaveStreakReminders(for: store.currentUser.id)
            await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems, backend: backend)
            await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary, backend: backend)
        } catch {
            errorMessage = "Could not load notification settings."
        }
    }

    private func enableNotifications(permissionAlreadyGranted: Bool = false) async {
        guard auth.isSignedIn, backend.canRegisterPushNotifications else {
            errorMessage = "Sign in to turn on notifications."
            return
        }

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
            authState: auth.state
        ) else {
            preferences = .allDisabled
            errorMessage = pushNotifications.lastErrorMessage ?? "Notifications were not allowed."
            return
        }
        preferences = enabledPreferences
        pushNotifications.configureSaveStreakReminders(for: store.currentUser.id)
        await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems, backend: backend)
        await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary, backend: backend)
        await calendarReservations.syncIfNeeded(
            backend: backend,
            store: store,
            userID: store.currentUser.id,
            force: true,
            reason: "notifications_enabled"
        )
    }

    private func disableNotifications() async {
        guard auth.isSignedIn, backend.canRegisterPushNotifications else { return }

        isChangingEnabledState = true
        errorMessage = nil
        pushNotifications.clearLastError()
        defer { isChangingEnabledState = false }

        if let disabledPreferences = await pushNotifications.disableNotifications(backend: backend) {
            preferences = disabledPreferences
        } else {
            errorMessage = pushNotifications.lastErrorMessage
        }
    }

    private func save(_ update: NotificationPreferencesUpdate) async {
        guard auth.isSignedIn, backend.canRegisterPushNotifications else {
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            preferences = try await backend.updateNotificationPreferences(update)
            pushNotifications.applyNotificationPreferences(preferences)
            await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems, backend: backend)
            await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary, backend: backend)
            if update.reservationRemindersEnabled == true {
                await calendarReservations.syncIfNeeded(
                    backend: backend,
                    store: store,
                    userID: store.currentUser.id,
                    force: true,
                    reason: "reservation_reminders_enabled"
                )
            }
        } catch {
            errorMessage = "Could not save notification settings."
        }
    }
}

struct SettingsTrustSurface {
    static let rowTitle = "Privacy and trust"
    static let rowSubtitle = "who sees places, location, sources"
    static let rowAccessibilityID = "settings.privacyTrust.row"
    static let sheetAccessibilityID = "settings.privacyTrust.sheet"
    static let factAccessibilityPrefix = "settings.privacyTrust.fact."
    static let sheetTitle = "privacy and trust"
    static let sheetIntro = "quick answers for what rec.me shares, syncs, and keeps private."

    static let facts: [TrustFact] = [
        TrustFact(
            id: "everyone",
            icon: "eye.slash",
            title: "Not private means followers",
            body: "Places saved outside stealth mode are visible to people who follow you. They are not a public internet feed."
        ),
        TrustFact(
            id: "stealth",
            icon: "lock",
            title: "Stealth mode means private",
            body: "Stealth places stay on your map for you only."
        ),
        TrustFact(
            id: "location",
            icon: "location",
            title: "Location is for finding places",
            body: "rec.me uses location when you ask for nearby candidates. It does not broadcast live location."
        ),
        TrustFact(
            id: "extraction",
            icon: "wand.and.stars",
            title: "Extraction asks first",
            body: "Links and photos can create candidates or drafts. Low-confidence results never auto-save to your map."
        ),
        TrustFact(
            id: "blocks",
            icon: "person.crop.circle.badge.xmark",
            title: "Blocks are hard blocks",
            body: "Blocking hides profiles, places, search results, and map content in both directions."
        ),
        TrustFact(
            id: "contacts",
            icon: "person.crop.rectangle.stack",
            title: "Contacts stay under your control",
            body: "rec.me asks for Contacts access only to help find people you know. You can change access anytime in iOS Settings."
        )
    ]
}

struct SettingsDefaultPlacePrivacySurface {
    static let toggleTitle = "stealth mode for new saves"

    static func helperCopy(for visibility: PlaceVisibility, isLockedByPrivateProfile: Bool = false) -> String {
        if isLockedByPrivateProfile {
            return "Locked on by Private Profile. New places stay hidden while Private Profile is on."
        }

        if visibility.isStealthModeEnabled {
            return "On: new places start private. Only you can see them unless you turn stealth off before saving."
        }

        return "Off: new places are visible to people who follow you. You can still turn stealth on before saving."
    }
}

struct SettingsProfilePrivacySurface {
    static let title = "Private profile"
    static let accessibilityID = "settings.profilePrivacy.explainer"

    static func body(isEnabled: Bool) -> String {
        if isEnabled {
            return "Your saved places are in stealth mode, new places stay stealth, and your username stays out of search. Existing friends and collaborative lists stay unchanged; new collaborative lists are unavailable."
        }

        return "Your username can appear in search and you can collaborate on lists."
    }

    static func warningTitle(enabling: Bool) -> String {
        enabling ? "Turn on Private Profile?" : "Turn off Private Profile?"
    }

    static func warningBody(enabling: Bool) -> String {
        if enabling {
            return "Places saved by you will switch to stealth mode, including your check-ins and Wanna Go places. Future saves stay stealth and your username will be hidden while Private Profile is on. Your followers and existing collaborative lists stay unchanged, but new collaborative lists are unavailable."
        }

        return "Your existing places will stay in stealth mode. Your username can appear in search again, and future saves will follow your stealth mode for new saves setting."
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
                .foregroundStyle(brandMode.accent)
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
                .foregroundStyle(brandMode.accent)
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
