import SwiftUI
import UIKit

private enum FeatureFlagBooleanOverrideChoice: String, CaseIterable, Identifiable {
    case remote
    case off
    case on

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: "Remote"
        case .off: "Off"
        case .on: "On"
        }
    }
}

struct ProfileSettingsHome: View {
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @EnvironmentObject private var importStore: PlaceImportStore

    @State private var showsAccountManagement = false
    @State private var showsNotifications = false
    @State private var showsDeleteWarning = false
    @State private var showsFinalDeleteWarning = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var deviceFeatureFlagOverrides: [FeatureFlagKey: FeatureFlagValue] = [:]
    @State private var settingsDragOffset: CGFloat = 0

    private let walkthroughDebugPreferences = FirstVisitWalkthroughDebugPreferences()
    private let featureFlagOverrideStore = FeatureFlagOverrideStore()

    init(
        onDismiss: (() -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                settingsHeader
                settingsList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(brandMode.primaryText)
            .background(brandMode.background.ignoresSafeArea())
            .offset(x: settingsDragOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(interactiveDismissGesture(containerWidth: geometry.size.width))
            .accessibilityIdentifier("settings.screen")
        }
        .tint(brandMode.accent)
        .toolbar(.hidden, for: .navigationBar)
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
        .onChange(of: debugSettingsUserID, initial: true) { _, _ in
            refreshDebugSettingsState()
        }
        .onChange(of: isDebugSettingsEntitled) { _, isEntitled in
            if isEntitled {
                refreshDebugSettingsState()
            }
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing4) {
            Button(action: closeSettings) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .background(brandMode.raisedBackground, in: Circle())
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("settings.back")

            Text("Settings")
                .font(AstirTypography.screenTitle)
                .foregroundStyle(brandMode.primaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(brandMode.background)
    }

    private var settingsList: some View {
        List {
            accountSection
            mapSection
            notificationsSection
            privacySection
            importsSection
            if isDebugSettingsEntitled {
                featureFlagsSection
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(AstirTypography.label)
                        .foregroundStyle(WanderTheme.stateError.color)
                }
                .listRowBackground(brandMode.raisedBackground)
            }

            accountActionsSection
            resourcesSection
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
    }

    private func interactiveDismissGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.x <= 28,
                      value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }

                settingsDragOffset = value.translation.width
            }
            .onEnded { value in
                guard settingsDragOffset > 0 else { return }

                let shouldDismiss = value.translation.width >= containerWidth * 0.3
                    || value.predictedEndTranslation.width >= containerWidth * 0.55

                guard shouldDismiss else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        settingsDragOffset = 0
                    }
                    return
                }

                withAnimation(.easeOut(duration: 0.14)) {
                    settingsDragOffset = containerWidth
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    closeSettings()
                }
            }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            switch auth.state {
            case .signedIn(let session):
                ProfileSettingsIdentityRow(session: session, avatarURL: store.currentUser.avatarURL)
                ProfileSettingsAccountActions(session: session) {
                    showsAccountManagement = true
                }
            case .offline(let session, _):
                ProfileSettingsIdentityRow(session: session, avatarURL: store.currentUser.avatarURL)
                Label("Saved map available offline", systemImage: "wifi.slash")
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.secondaryText)
            case .signedOut:
                Button("Sign in") { auth.beginSignIn() }
            case .loading:
                ProgressView("Checking account...")
            case .unavailable(let message):
                Text(message).foregroundStyle(WanderTheme.stateError.color)
            }
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    private var privacySection: some View {
        Section("Privacy and safety") {
            NavigationLink {
                ProfilePrivacyTrustScreen()
            } label: {
                Label("Privacy and trust", systemImage: "shield.lefthalf.filled")
            }

            NavigationLink {
                BlockedMutedScreen()
            } label: {
                Label("Blocked and muted accounts", systemImage: "person.crop.circle.badge.xmark")
            }

            SettingsExternalLink(
                title: "Privacy choices",
                icon: "slider.horizontal.3",
                destination: RecmeSettingsWebDestination.privacyChoices
            )
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    private var mapSection: some View {
        Section {
            NavigationLink {
                DefaultMapFilterSettingsScreen()
            } label: {
                HStack {
                    Label("Default map filter", systemImage: "map")
                    Spacer()
                    Label(store.defaultMapFilter.title, systemImage: store.defaultMapFilter.systemImage)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                }
            }
            .tint(brandMode.accent)
            .accessibilityIdentifier("settings.map.defaultFilter")

            Toggle(
                isOn: Binding(
                    get: { store.isDarkMapEnabled },
                    set: { store.isDarkMapEnabled = $0 }
                )
            ) {
                Label("Dark map", systemImage: "moon.stars")
            }
            .tint(brandMode.accent)
            .accessibilityHint("Uses a dark map and matching controls on the Map tab")
            .accessibilityIdentifier("settings.map.darkMode")
        } header: {
            Text("Map")
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Button {
                auth.requireSignIn(for: .manageNotifications) { showsNotifications = true }
            } label: {
                HStack {
                    Label("Notifications", systemImage: "bell")
                    Spacer()
                    Text(pushNotifications.statusTitle)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(brandMode.secondaryText)
                }
            }
            .foregroundStyle(brandMode.primaryText)
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    private var importsSection: some View {
        Section("Imports") {
            NavigationLink {
                PlaceImportHistoryScreen(importStore: importStore)
            } label: {
                Label("Import history", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("settings.importHistory")
        }
    }

    @ViewBuilder
    private var accountActionsSection: some View {
        Section("Account actions") {
            switch auth.state {
            case .signedIn, .offline:
                Button {
                    Task { await signOut() }
                } label: {
                    destructiveSettingsLabel(
                        auth.isSigningOut ? "Signing out..." : "Sign out",
                        icon: "rectangle.portrait.and.arrow.right",
                        color: WanderTheme.stateError.color
                    )
                }
                .disabled(auth.isSigningOut)
                .accessibilityIdentifier("settings.account.signOut")
            case .signedOut, .loading, .unavailable:
                EmptyView()
            }

            Button(role: .destructive) {
                showsDeleteWarning = true
            } label: {
                destructiveSettingsLabel(
                    isDeleting ? "Deleting account..." : "Delete my account",
                    icon: "trash",
                    color: .red
                )
            }
            .disabled(isDeleting || !auth.isSignedIn)
            .accessibilityIdentifier("settings.account.delete")
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    private var resourcesSection: some View {
        Section {
            NavigationLink {
                SettingsResourcesScreen()
            } label: {
                Label("Resources", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("settings.resources")
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    // Every Simulator build exposes this local tester surface. Physical devices
    // and TestFlight remain server-entitled so normal accounts never see it.
    private var isDebugSettingsEntitled: Bool {
        guard let userID = debugSettingsUserID else { return false }
        return DebugSettingsAccessPolicy.isEntitled(
            serverFlag: backend.remoteFeatureFlag(.debugSettings, for: userID)?.isEnabled
        )
    }

    private var debugSettingsUserID: String? {
        auth.state.session?.userID
    }

    private var featureFlagsSection: some View {
        Section {
            Text("Device overrides are saved for this account on this device. Active behavior changes only after you fully quit and reopen rec.me.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)

            ForEach(FeatureFlagKey.allCases, id: \.self) { key in
                featureFlagControl(for: key)
            }

            if hasDeviceFeatureFlagOverrides {
                Button("Reset all to defaults", role: .destructive) {
                    resetAllDeviceFeatureFlagOverrides()
                }
                .accessibilityIdentifier("settings.flags.resetAll")
            }

            if hasPendingFeatureFlagRestart {
                Label("Restart rec.me to apply these changes", systemImage: "arrow.clockwise")
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
                    .accessibilityIdentifier("settings.flags.restartRequired")
            }
        } header: {
            Text("Feature flags")
        }
        .listRowBackground(brandMode.raisedBackground)
    }

    @ViewBuilder
    private func featureFlagControl(for key: FeatureFlagKey) -> some View {
        let definition = key.definition
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(definition.title)
                    .font(AstirTypography.cardTitle)
                Spacer()
                if !definition.isEditableOnDevice {
                    Text(activeFeatureFlagStatus(for: key))
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.secondaryText)
                }
            }

            Text(definition.summary)
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)

            if definition.isEditableOnDevice {
                switch definition.valueKind {
                case .boolean:
                    Picker("Device value", selection: booleanOverrideBinding(for: key)) {
                        ForEach(FeatureFlagBooleanOverrideChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                case .integer:
                    integerFeatureFlagControl(for: key, definition: definition)
                }
            }

            Text(featureFlagProvenance(for: key))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(brandMode.secondaryText)
        }
        .padding(.vertical, WanderTheme.spacing1)
        .accessibilityIdentifier("settings.flags.\(key.rawValue)")
    }

    @ViewBuilder
    private func integerFeatureFlagControl(
        for key: FeatureFlagKey,
        definition: FeatureFlagDefinition
    ) -> some View {
        if let range = definition.integerRange {
            Toggle("Override on this device", isOn: integerOverrideEnabledBinding(for: key))
                .tint(brandMode.accent)
            if deviceFeatureFlagOverrides[key]?.integerValue != nil {
                Stepper(value: integerOverrideBinding(for: key, range: range), in: range) {
                    Text("Value: \(integerOverrideBinding(for: key, range: range).wrappedValue)")
                        .font(AstirTypography.label)
                }
            }
        } else {
            Text("Invalid integer flag configuration")
                .font(AstirTypography.caption)
                .foregroundStyle(WanderTheme.stateError.color)
        }
    }

    private func refreshDebugSettingsState() {
        guard let userID = debugSettingsUserID else {
            deviceFeatureFlagOverrides = [:]
            return
        }
        deviceFeatureFlagOverrides = featureFlagOverrideStore.overrides(for: userID)
    }

    private var hasDeviceFeatureFlagOverrides: Bool {
        !deviceFeatureFlagOverrides.isEmpty
    }

    private var hasPendingFeatureFlagRestart: Bool {
        guard let userID = debugSettingsUserID else { return false }
        return FeatureFlagKey.allCases.contains { key in
            guard key.definition.isEditableOnDevice else { return false }
            return deviceFeatureFlagOverrides[key]
                != backend.deviceFeatureFlagOverride(key, for: userID)
        }
    }

    private func activeFeatureFlagStatus(for key: FeatureFlagKey) -> String {
        guard let userID = debugSettingsUserID,
              let resolved = backend.resolvedFeatureFlag(key, for: userID)
        else { return "Loading" }
        return resolved.value.displayValue
    }

    private func featureFlagProvenance(for key: FeatureFlagKey) -> String {
        guard let userID = debugSettingsUserID,
              let resolved = backend.resolvedFeatureFlag(key, for: userID)
        else { return "\(key.rawValue) · loading remote value" }
        return "\(key.rawValue) · active \(resolved.value.displayValue) · \(resolved.source.settingsLabel)"
    }

    private func booleanOverrideBinding(for key: FeatureFlagKey) -> Binding<FeatureFlagBooleanOverrideChoice> {
        Binding(
            get: {
                guard let value = deviceFeatureFlagOverrides[key]?.booleanValue else {
                    return .remote
                }
                return value ? .on : .off
            },
            set: { choice in
                switch choice {
                case .remote:
                    persistDeviceFeatureFlagOverride(nil, for: key)
                case .off:
                    persistDeviceFeatureFlagOverride(.boolean(false), for: key)
                case .on:
                    persistDeviceFeatureFlagOverride(.boolean(true), for: key)
                }
            }
        )
    }

    private func integerOverrideEnabledBinding(for key: FeatureFlagKey) -> Binding<Bool> {
        Binding(
            get: { deviceFeatureFlagOverrides[key]?.integerValue != nil },
            set: { isEnabled in
                guard isEnabled else {
                    persistDeviceFeatureFlagOverride(nil, for: key)
                    return
                }
                let value = backend.integerFeatureFlag(key, for: debugSettingsUserID ?? "")
                    ?? key.definition.bundledDefault.integerValue
                    ?? key.definition.integerRange?.lowerBound
                    ?? 0
                persistDeviceFeatureFlagOverride(.integer(value), for: key)
            }
        )
    }

    private func integerOverrideBinding(
        for key: FeatureFlagKey,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { deviceFeatureFlagOverrides[key]?.integerValue ?? range.lowerBound },
            set: { persistDeviceFeatureFlagOverride(.integer($0), for: key) }
        )
    }

    private func persistDeviceFeatureFlagOverride(
        _ value: FeatureFlagValue?,
        for key: FeatureFlagKey
    ) {
        guard let userID = debugSettingsUserID else { return }
        if key == .firstVisitNUX {
            if let isEnabled = value?.booleanValue {
                walkthroughDebugPreferences.setNUXEnabled(isEnabled, for: userID)
            } else {
                walkthroughDebugPreferences.clearNUXOverride(for: userID)
            }
        } else if let value {
            featureFlagOverrideStore.setOverride(value, for: key, userID: userID)
        } else {
            featureFlagOverrideStore.clearOverride(for: key, userID: userID)
        }
        refreshDebugSettingsState()
    }

    private func resetAllDeviceFeatureFlagOverrides() {
        guard let userID = debugSettingsUserID else { return }
        featureFlagOverrideStore.clearAllOverrides(for: userID)
        walkthroughDebugPreferences.clearReplayRequest(for: userID)
        refreshDebugSettingsState()
    }

    private func destructiveSettingsLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 22)
            Text(title)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
    }

    private func closeSettings() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func signOut() async {
        let signingOutUserID: String? = if case .signedIn(let session) = auth.state {
            session.userID
        } else {
            nil
        }
        if let signingOutUserID {
            await pushNotifications.unregisterStoredDeviceTokenIfPossible(
                backend: backend,
                userID: signingOutUserID,
                authSession: auth
            )
        }
        do {
            try await auth.signOut()
        } catch {
            if let signingOutUserID {
                await pushNotifications.restoreRegistrationAfterFailedAccountTeardown(
                    userID: signingOutUserID,
                    backend: backend,
                    authSession: auth
                )
            }
        }
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
            if let deletingUserID {
                await pushNotifications.unregisterStoredDeviceTokenIfPossible(
                    backend: backend,
                    userID: deletingUserID,
                    authSession: auth
                )
            }
            try await auth.deleteAccount()
            if let deletingUserID {
                OnboardingCompletionStore().clear(for: deletingUserID)
            }
            store.resetAfterAccountDeletion()
            closeSettings()
        } catch {
            if let deletingUserID {
                await pushNotifications.restoreRegistrationAfterFailedAccountTeardown(
                    userID: deletingUserID,
                    backend: backend,
                    authSession: auth
                )
            }
            errorMessage = "Your account could not be deleted. Nothing was removed. Please try again."
        }
    }
}

private struct DefaultMapFilterSettingsScreen: View {
    @Environment(\.astirBrandMode) private var brandMode
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
                                .foregroundStyle(brandMode.accentText)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                                Text(source.title)
                                    .font(AstirTypography.cardTitle)
                                    .foregroundStyle(brandMode.primaryText)

                                Text(source.subtitle)
                                    .font(AstirTypography.bodySmall)
                                    .foregroundStyle(brandMode.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: WanderTheme.spacing2)

                            if store.defaultMapFilter == source {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundStyle(brandMode.accentText)
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
            .listRowBackground(brandMode.raisedBackground)
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .tint(brandMode.accent)
        .navigationTitle("Default map filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct SettingsResourcesScreen: View {
    @Environment(\.astirBrandMode) private var brandMode
    var body: some View {
        List {
            SettingsExternalLink(
                title: "Import help",
                icon: "square.and.arrow.down",
                destination: ImportHelpDestination.url
            )
            SettingsExternalLink(
                title: "Help and support",
                icon: "questionmark.circle",
                destination: RecmeSettingsWebDestination.support
            )
            SettingsExternalLink(
                title: "Privacy policy",
                icon: "hand.raised",
                destination: RecmeSettingsWebDestination.privacy
            )
            SettingsExternalLink(
                title: "Terms of use",
                icon: "doc.text",
                destination: RecmeSettingsWebDestination.terms
            )
            SettingsExternalLink(
                title: "Community guidelines",
                icon: "person.3",
                destination: RecmeSettingsWebDestination.community
            )
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .tint(brandMode.accent)
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private enum RecmeSettingsWebDestination {
    static let support = URL(string: "https://getrec.me/support")!
    static let privacy = URL(string: "https://getrec.me/privacy")!
    static let terms = URL(string: "https://getrec.me/terms")!
    static let community = URL(string: "https://getrec.me/community")!
    static let privacyChoices = URL(string: "https://getrec.me/privacy-choices")!
}

private struct SettingsExternalLink: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let icon: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: icon)
                    .font(AstirTypography.control)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(brandMode.secondaryText)
            }
        }
        .foregroundStyle(brandMode.primaryText)
    }
}

private struct ProfileSettingsIdentityRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let session: AuthSession
    let avatarURL: String?

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: String((session.displayName ?? session.handle ?? "You").prefix(2)).uppercased(),
                avatarURL: avatarURL,
                size: 52,
                color: WanderTheme.avatarRyan.color
            )
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(session.displayName ?? "Your account")
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)
                if let emailAddress = SettingsAccountIdentityPresentation.emailAddress(for: session) {
                    Text(emailAddress)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let phoneNumber = SettingsAccountIdentityPresentation.phoneNumber(for: session) {
                    Text(phoneNumber)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.vertical, WanderTheme.spacing2)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSettingsAccountActions: View {
    @Environment(\.astirBrandMode) private var brandMode
    let session: AuthSession
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                title: "Change email",
                value: SettingsAccountIdentityPresentation.emailAddress(for: session) ?? "Not added",
                icon: "envelope"
            )

            actionDivider

            actionButton(
                title: "Change phone number",
                value: SettingsAccountIdentityPresentation.phoneNumber(for: session) ?? "Not added",
                icon: "phone"
            )

            actionDivider

            actionButton(
                title: "Change password",
                value: nil,
                icon: "key"
            )
        }
        .listRowInsets(EdgeInsets())
    }

    private func actionButton(title: String, value: String?, icon: String) -> some View {
        Button(action: onSelect) {
            VStack(spacing: WanderTheme.spacing2) {
                Image(systemName: icon)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(brandMode.accentText)
                    .frame(height: 24)

                Text(title)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let value {
                    Text(value)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, WanderTheme.spacing1)
            .padding(.vertical, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
    }

    private var actionDivider: some View {
        Divider()
            .overlay(brandMode.border)
            .padding(.vertical, WanderTheme.spacing3)
    }
}

struct SettingsAccountIdentityPresentation {
    static func emailAddress(for session: AuthSession) -> String? {
        normalized(session.email)
    }

    static func phoneNumber(for session: AuthSession) -> String? {
        normalized(session.phoneNumber)
    }

    static func publicHandle(for session: AuthSession) -> String? {
        guard let handle = session.handle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !handle.isEmpty else {
            return nil
        }

        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

struct ProfilePrivacyTrustScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var calendarReservations: CalendarReservationManager
    @State private var pendingPrivateProfileValue: Bool?
    @State private var showsWarning = false
    @State private var isConnectingCalendar = false
    @State private var errorMessage: String?
    @State private var calendarErrorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle(isOn: privateProfileBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SettingsProfilePrivacySurface.title)
                            .font(AstirTypography.cardTitle)
                            .foregroundStyle(brandMode.primaryText)
                        Text(SettingsProfilePrivacySurface.body(isEnabled: store.isPrivateProfile))
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                    }
                }
                .tint(brandMode.accent)

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
            .listRowBackground(brandMode.raisedBackground)

            calendarPermissionSection

            Section("How privacy works") {
                ForEach(SettingsTrustSurface.facts) { fact in
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        Image(systemName: fact.icon)
                            .foregroundStyle(brandMode.accentText)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.title)
                                .font(AstirTypography.cardTitle)
                                .foregroundStyle(brandMode.primaryText)
                            Text(fact.body)
                                .font(AstirTypography.bodySmall)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
            }
            .listRowBackground(brandMode.raisedBackground)


            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(AstirTypography.label)
                        .foregroundStyle(WanderTheme.stateError.color)
                }
                .listRowBackground(brandMode.raisedBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .tint(brandMode.accent)
        .navigationTitle("Privacy and trust")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            calendarReservations.refreshAuthorizationStatus()
        }
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

    private var calendarPermissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(width: 38, height: 38)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("Apple Calendar")
                            .font(.system(size: 15, weight: .black))
                        Text(calendarReservations.hasFullAccess
                             ? "Connected. rec.me can recognize restaurant reservations on this iPhone."
                             : "Connect to let rec.me look for restaurant reservations on this iPhone.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }

                Button {
                    Task { await connectOrSyncCalendar() }
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: calendarReservations.hasFullAccess
                              ? "arrow.triangle.2.circlepath"
                              : "calendar.badge.plus")
                        Text(isConnectingCalendar
                             ? "working"
                             : CalendarPermissionPolicy.primaryTitle(
                                 for: calendarReservations.authorizationStatus
                             ))
                    }
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
                }
                .disabled(isConnectingCalendar || !auth.isSignedIn)
                .accessibilityIdentifier("settings.privacy.calendar.action")

                Text("rec.me never uploads or stores raw calendar titles, notes, guests, URLs, or addresses—only the matched restaurant and reservation time.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Text("Choose whether to receive reservation reminders in Notifications.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)

                if let calendarErrorMessage {
                    Text(calendarErrorMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.stateError.color)
                }
            }
            .padding(.vertical, WanderTheme.spacing1)
            .accessibilityIdentifier("settings.privacy.calendar")
        } header: {
            Text("Permissions")
        }
    }

    @MainActor
    private func connectOrSyncCalendar() async {
        if CalendarPermissionPolicy.action(for: calendarReservations.authorizationStatus) == .openSettings {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
            return
        }

        isConnectingCalendar = true
        calendarErrorMessage = nil
        defer { isConnectingCalendar = false }

        if !calendarReservations.hasFullAccess {
            let granted = await calendarReservations.requestAccess()
            guard granted else {
                if calendarReservations.authorizationStatus == .denied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                } else {
                    calendarErrorMessage = calendarReservations.lastErrorMessage
                }
                return
            }
        }

        await calendarReservations.syncIfNeeded(
            backend: backend,
            store: store,
            userID: store.currentUser.id,
            force: true,
            reason: "settings_manual"
        )
        calendarErrorMessage = calendarReservations.lastErrorMessage
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
    @Environment(\.astirBrandMode) private var brandMode
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
                            Text(profile.displayName)
                                .font(AstirTypography.cardTitle)
                                .foregroundStyle(brandMode.primaryText)
                            Text("@\(profile.handle)")
                                .font(AstirTypography.bodySmall)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        Spacer()
                        Button(selectedTab == .blocked ? "Unblock" : "Unmute") {
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
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.accentText)
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                    .listRowBackground(brandMode.raisedBackground)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(brandMode.background)
        .tint(brandMode.accent)
        .navigationTitle("Blocked and muted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await store.refreshRemoteBlocks(backend: backend)
            await store.refreshRemoteMutes(backend: backend)
        }
    }
}

private struct BlockedMutedEmptyState: View {
    @Environment(\.astirBrandMode) private var brandMode
    let tab: ProfileRelationshipFilter

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: tab == .blocked ? "person.crop.circle.badge.xmark" : "speaker.slash.circle")
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(WanderTheme.categoryMoss.color)
            Text(tab == .blocked ? "You haven't blocked anyone" : "You haven't muted anyone")
                .font(AstirTypography.sheetTitle)
                .foregroundStyle(brandMode.primaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.secondaryText)
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
