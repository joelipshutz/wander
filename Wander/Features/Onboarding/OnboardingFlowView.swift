import PhotosUI
import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    let session: AuthSession
    let initialStep: OnboardingStep
    let analytics: AnalyticsClient
    let saveProgress: (OnboardingStep) -> Void
    let complete: (Bool) -> Void

    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var productUpsells: ProductUpsellCoordinator
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var step: OnboardingStep
    @State private var didTrackStart = false
    @StateObject private var locationPermission = OnboardingLocationPermissionManager()
    @StateObject private var contactsPermission = OnboardingContactsPermissionManager()

    init(
        session: AuthSession,
        initialStep: OnboardingStep,
        analytics: AnalyticsClient,
        saveProgress: @escaping (OnboardingStep) -> Void,
        complete: @escaping (Bool) -> Void
    ) {
        self.session = session
        self.initialStep = initialStep
        self.analytics = analytics
        self.saveProgress = saveProgress
        self.complete = complete
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        Group {
            switch step {
            case .identity:
                OnboardingIdentityView(session: session, analytics: analytics) {
                    advance(from: .identity)
                }
            case .location:
                if OnboardingLocationPermissionPolicy.action(
                    for: locationPermission.authorizationStatus
                ) == .skip {
                    Color.clear
                        .task { advance(from: .location) }
                } else {
                    OnboardingLocationPermissionView(
                        permission: locationPermission,
                        analytics: analytics,
                        continueAction: { advance(from: .location) }
                    )
                }
            case .contacts:
                OnboardingPermissionView(
                    step: .contacts,
                    systemImage: "person.2.fill",
                    accent: WanderTheme.pinSocial.color,
                    title: "Connect with your people",
                    message: "Use your contacts to connect with people you know.",
                    bullets: [],
                    primaryTitle: "Continue",
                    analytics: analytics,
                    request: { await contactsPermission.requestAccess() },
                    continueAction: { advance(from: .contacts) }
                )
            case .friends:
                OnboardingFriendSuggestionsView(backend: backend, userID: session.userID, analytics: analytics) {
                    advance(from: .friends)
                }
            case .notifications:
                OnboardingNotificationUpsellTrigger(
                    userID: session.userID,
                    finish: finish
                )
            }
        }
        .environmentObject(backend)
        .environmentObject(auth)
        .environmentObject(productUpsells)
        .environmentObject(pushNotifications)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(.snappy(duration: 0.35), value: step)
        .task(id: step) {
            if !didTrackStart {
                didTrackStart = true
                analytics.track(
                    AnalyticsEvent(
                        name: WanderAnalyticsEvents.onboardingStarted,
                        properties: [
                            "initial_step": initialStep.rawValue,
                            "is_resumed": initialStep == .identity ? "false" : "true"
                        ]
                    )
                )
            }
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.onboardingStepViewed,
                    properties: ["step": step.rawValue]
                )
            )
        }
    }

    private func advance(from current: OnboardingStep) {
        guard step == current else { return }
        guard let next = current.next else { return }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingStepCompleted,
                properties: ["step": current.rawValue]
            )
        )
        saveProgress(next)
        step = next
    }

    @MainActor
    private func finish() async {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingStepCompleted,
                properties: ["step": OnboardingStep.notifications.rawValue]
            )
        )
        let serverConfirmed: Bool
        do {
            _ = try await backend.updateCurrentProfile(
                ProfileDetailsUpdate(markOnboardingComplete: true)
            )
            serverConfirmed = true
        } catch {
            serverConfirmed = false
        }
        complete(serverConfirmed)
    }
}

struct OnboardingIdentityView: View {
    @Environment(\.astirBrandMode) private var brandMode
    private enum Availability: Equatable {
        case idle
        case checking
        case available
        case unavailable
    }

    @EnvironmentObject private var backend: WanderBackend
    let session: AuthSession
    let analytics: AnalyticsClient
    let continueAction: () -> Void
    private let originalNormalizedHandle: String

    @State private var name: String
    @State private var handle: String
    @State private var hasEditedHandle = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoCropSelection: ProfilePhotoCropSelection?
    @State private var previewImage: UIImage?
    @State private var jpegData: Data?
    @State private var existingAvatarURL: String?
    @State private var availability: Availability = .idle
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, handle }

    init(session: AuthSession, analytics: AnalyticsClient, initialPhoto: UIImage? = nil, continueAction: @escaping () -> Void) {
        self.session = session
        self.analytics = analytics
        self.continueAction = continueAction
        let initialName = session.displayName ?? ""
        let initialHandle = session.handle ?? ""
        originalNormalizedHandle = ProfileIdentityDraft(
            displayName: initialName,
            handle: initialHandle
        ).normalizedHandle
        _name = State(initialValue: initialName)
        _handle = State(initialValue: initialHandle)
        _previewImage = State(initialValue: initialPhoto)
        _jpegData = State(initialValue: initialPhoto?.jpegData(compressionQuality: 0.9))
    }

    private var draft: ProfileIdentityDraft {
        ProfileIdentityDraft(displayName: name, handle: handle)
    }

    private var canSubmit: Bool {
        draft.isValid
            && (jpegData?.isEmpty == false || existingAvatarURL != nil)
            && availability != .checking
            && availability != .unavailable
            && !isSaving
    }

    private var handleBinding: Binding<String> {
        Binding(
            get: { handle },
            set: { value in
                guard value != handle else { return }
                handle = value
                hasEditedHandle = true
                availability = .idle
                errorMessage = nil
            }
        )
    }

    var body: some View {
        OnboardingStepScaffold(step: .identity) {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                        Text("YOUR PROFILE")
                            .font(AstirTypography.metadata)
                            .tracking(1.4)
                            .foregroundStyle(brandMode.accentText)
                        ProfileIdentityHeader(name: draft.normalizedDisplayName.isEmpty ? "Your name" : draft.normalizedDisplayName) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VStack(spacing: WanderTheme.spacing2) {
                                    ZStack(alignment: .bottomTrailing) {
                                        profilePhoto
                                            .frame(width: 104, height: 104)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(brandMode.border, lineWidth: 1))
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(brandMode.background)
                                            .frame(width: 30, height: 30)
                                            .background(brandMode.primaryText, in: Circle())
                                            .overlay(Circle().stroke(brandMode.background, lineWidth: 3))
                                    }
                                    Text(previewImage == nil && existingAvatarURL == nil ? "Add a photo" : "Change photo")
                                        .font(AstirTypography.caption)
                                        .foregroundStyle(brandMode.primaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(previewImage == nil && existingAvatarURL == nil ? "Add a required profile photo" : "Change profile photo")
                            .accessibilityIdentifier("onboarding.identity.photo")
                        } details: {
                            Text("@\(draft.normalizedHandle.isEmpty ? "your_username" : draft.normalizedHandle)")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.secondaryText)
                                .lineLimit(2)
                                .accessibilityIdentifier("onboarding.identity.previewHandle")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, WanderTheme.spacing4)
                    .frame(minHeight: 240, alignment: .top)

                    VStack(spacing: WanderTheme.spacing3) {
                        OnboardingTextField(
                            title: "Name",
                            prompt: "How friends know you",
                            text: $name,
                            capitalization: .words
                        )
                        .focused($focusedField, equals: .name)

                        VStack(alignment: .leading, spacing: 6) {
                            OnboardingTextField(
                                title: "Username",
                                prompt: "your_username",
                                text: handleBinding,
                                prefix: "@",
                                capitalization: .never,
                                autocorrectionDisabled: true
                            )
                            .focused($focusedField, equals: .handle)

                            HStack(spacing: 6) {
                                switch availability {
                                case .checking:
                                    ProgressView().controlSize(.small)
                                    Text("Checking username…")
                                case .available:
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Username available")
                                case .unavailable:
                                    Image(systemName: "xmark.circle.fill")
                                    Text("That username is taken")
                                case .idle:
                                    Text("2–39 letters, numbers, or underscores")
                                }
                            }
                            .font(AstirTypography.caption)
                            .foregroundStyle(availabilityFeedbackColor)
                        }
                    }

                    if let validation = draft.validationError, !name.isEmpty || !handle.isEmpty {
                        Text(validation.message)
                            .font(AstirTypography.caption)
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AstirTypography.label)
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
                .disabled(isSaving)
            }
            .scrollDismissesKeyboard(.interactively)
        } footer: {
            WanderPrimaryButton(
                title: isSaving ? "Creating your profile…" : "Continue",
                systemImage: isSaving ? nil : "arrow.right",
                isDisabled: !canSubmit
            ) {
                focusedField = nil
                Task { await save() }
            }
            .accessibilityIdentifier("onboarding.identity.continue")
        }
        .task(id: draft.normalizedHandle) { await checkAvailability() }
        .task {
            guard let profile = try? await backend.currentProfile(), !Task.isCancelled,
                  let url = profile.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty
            else { return }
            existingAvatarURL = url
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fullScreenCover(item: $photoCropSelection) { selection in
            ProfilePhotoCropView(
                image: selection.image,
                cancel: { photoCropSelection = nil },
                choose: { data, image in
                    jpegData = data
                    previewImage = image
                    photoCropSelection = nil
                    errorMessage = nil
                }
            )
        }
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let previewImage {
            Image(uiImage: previewImage).resizable().scaledToFill()
        } else if let existingAvatarURL {
            WanderAvatar(initials: String(draft.normalizedDisplayName.prefix(2)).uppercased(), avatarURL: existingAvatarURL, size: 104)
        } else {
            Circle().fill(brandMode.border.opacity(0.4))
                .overlay(Image(systemName: "person.crop.circle")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundStyle(brandMode.secondaryText))
        }
    }

    private var availabilityFeedbackColor: Color {
        switch availability {
        case .available:
            WanderTheme.stateSuccess.color
        case .unavailable:
            WanderTheme.stateError.color
        case .checking, .idle:
            WanderTheme.textMuted.color
        }
    }

    @MainActor
    private func checkAvailability() async {
        guard OnboardingHandleAvailabilityPolicy.shouldCheck(
            normalizedHandle: draft.normalizedHandle,
            originalNormalizedHandle: originalNormalizedHandle,
            hasUserEdited: hasEditedHandle,
            validationError: draft.validationError
        ) else {
            availability = .idle
            return
        }
        availability = .checking
        let candidate = draft.normalizedHandle
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let isAvailable = try await backend.isProfileHandleAvailable(candidate)
            guard !Task.isCancelled, candidate == draft.normalizedHandle else { return }
            availability = isAvailable ? .available : .unavailable
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, candidate == draft.normalizedHandle else { return }
            availability = .idle
        }
    }

    @MainActor
    private func save() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await OnboardingIdentitySubmission.save(
                draft: draft,
                photoData: jpegData,
                existingAvatarURL: existingAvatarURL,
                updateIdentity: { update in _ = try await backend.updateCurrentProfile(update) },
                uploadPhoto: { data in _ = try await backend.uploadProfileAvatar(jpegData: data, userID: session.userID) }
            )
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingIdentitySubmitted,
                properties: ["photo_selected": jpegData == nil ? "false" : "true"]
            ))
            continueAction()
        } catch let error as OnboardingIdentityPhotoError {
            errorMessage = error.message
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingIdentityFailed,
                properties: ["reason": "photo_save_failed"]
            ))
        } catch {
            let mapped = ProfileIdentitySubmissionError.map(error)
            availability = mapped == .handleTaken ? .unavailable : availability
            errorMessage = mapped.message
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingIdentityFailed,
                properties: ["reason": String(describing: mapped)]
            ))
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            errorMessage = "That photo couldn’t be loaded. Try another one."
            return
        }
        errorMessage = nil
        photoCropSelection = ProfilePhotoCropSelection(image: image)
    }
}

private struct OnboardingLocationPermissionView: View {
    @ObservedObject var permission: OnboardingLocationPermissionManager
    let analytics: AnalyticsClient
    let continueAction: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRequesting = false

    private var permissionAction: OnboardingLocationPermissionAction {
        OnboardingLocationPermissionPolicy.action(for: permission.authorizationStatus)
    }

    var body: some View {
        OnboardingStepScaffold(step: .location) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    OnboardingLocationMapPreview()
                        .frame(height: 350)

                    OnboardingHeadline(
                        eyebrow: OnboardingLocationContent.eyebrow,
                        title: OnboardingLocationContent.title,
                        message: OnboardingLocationContent.message
                    )

                    Label(
                        OnboardingLocationContent.privacyMessage,
                        systemImage: "lock.fill"
                    )
                    .font(AstirTypography.control)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .symbolRenderingMode(.hierarchical)
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)
                .padding(.bottom, WanderTheme.spacing6)
            }
        } footer: {
            VStack(spacing: WanderTheme.spacing1) {
                WanderPrimaryButton(
                    title: isRequesting
                        ? "Requesting location…"
                        : OnboardingLocationPermissionPolicy.primaryTitle(
                            for: permission.authorizationStatus
                        ),
                    isDisabled: isRequesting
                ) {
                    performPrimaryAction()
                }
                .accessibilityIdentifier("onboarding.location.primary")

                if permissionAction == .openSettings {
                    Button("Not now") {
                        trackResult("skipped")
                        continueAction()
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .task {
            permission.refreshAuthorizationStatus()
            advanceIfAuthorized()
        }
        .onChange(of: permission.authorizationStatus) { _, _ in
            advanceIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            permission.refreshAuthorizationStatus()
            advanceIfAuthorized()
        }
    }

    private func performPrimaryAction() {
        switch permissionAction {
        case .skip:
            continueAction()
        case .request:
            Task {
                isRequesting = true
                let granted = await permission.requestAccess()
                trackResult(granted ? "true" : "false")
                isRequesting = false
                continueAction()
            }
        case .openSettings:
            trackResult("settings")
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        case .continueWithoutAccess:
            trackResult("restricted")
            continueAction()
        }
    }

    private func advanceIfAuthorized() {
        guard OnboardingLocationPermissionPolicy.action(
            for: permission.authorizationStatus
        ) == .skip else { return }
        continueAction()
    }

    private func trackResult(_ result: String) {
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.onboardingPermissionResult,
            properties: ["permission": OnboardingStep.location.rawValue, "granted": result]
        ))
    }
}

private struct OnboardingPermissionView: View {
    let step: OnboardingStep
    let systemImage: String
    let accent: Color
    let title: String
    let message: String
    let bullets: [String]
    let primaryTitle: String
    let analytics: AnalyticsClient
    let request: () async -> Bool
    let continueAction: () -> Void

    @State private var isRequesting = false

    var body: some View {
        OnboardingStepScaffold(step: step) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: WanderTheme.spacing6) {
                    Spacer(minLength: WanderTheme.spacing4)
                    ZStack {
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .fill(accent.opacity(0.12))
                            .frame(width: 270, height: 210)
                            .rotationEffect(.degrees(-5))
                        Image(systemName: systemImage)
                            .font(.system(size: 88, weight: .medium))
                            .foregroundStyle(accent)
                            .symbolEffect(.bounce, value: isRequesting)
                    }

                    OnboardingHeadline(eyebrow: "ONE QUICK THING", title: title, message: message)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        ForEach(bullets, id: \.self) { bullet in
                            Label(bullet, systemImage: "checkmark.circle.fill")
                                .font(AstirTypography.body)
                                .foregroundStyle(WanderTheme.textInk.color)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, WanderTheme.spacing4)
            }
        } footer: {
            WanderPrimaryButton(
                title: isRequesting ? "Opening settings…" : primaryTitle,
                isDisabled: isRequesting
            ) {
                Task {
                    isRequesting = true
                    let granted = await request()
                    analytics.track(AnalyticsEvent(
                        name: WanderAnalyticsEvents.onboardingPermissionResult,
                        properties: ["permission": step.rawValue, "granted": granted ? "true" : "false"]
                    ))
                    isRequesting = false
                    continueAction()
                }
            }
        }
    }
}

private struct OnboardingNotificationUpsellTrigger: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var productUpsells: ProductUpsellCoordinator
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    let userID: String
    let finish: () async -> Void
    @State private var didBeginPreparation = false
    @State private var didResolveStep = false
    @State private var preferenceFallbackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let content = ProductUpsellCatalog.production
                .configuration(for: .onboardingNotifications)?
                .content(for: .onboardingNotifications) {
                OnboardingStepScaffold(step: .notifications) {
                    ProductUpsellContentView(content: content, isWorking: true)
                } footer: {
                    WanderPrimaryButton(title: "Continue", isDisabled: true) {}
                }
            } else {
                ProgressView()
            }
        }
            .task {
                guard !didBeginPreparation else { return }
                didBeginPreparation = true
                pushNotifications.bindNotificationPreferences(to: userID)
                await pushNotifications.refreshAuthorizationStatus()
                guard !Task.isCancelled,
                      auth.state.session?.userID == userID else { return }
                preferenceFallbackTask = Task { @MainActor in
                    do {
                        try await Task.sleep(
                            for: .milliseconds(
                                OnboardingNotificationUpsellPreparationPolicy
                                    .systemPermissionFallbackDelayMilliseconds
                            )
                        )
                    } catch {
                        return
                    }
                    requestCampaignWithoutPreferencesIfSystemPermissionIsOff()
                    guard !didResolveStep else { return }
                    do {
                        try await Task.sleep(
                            for: .milliseconds(
                                OnboardingNotificationUpsellPreparationPolicy
                                    .maximumPreferenceWaitMilliseconds
                                    - OnboardingNotificationUpsellPreparationPolicy
                                        .systemPermissionFallbackDelayMilliseconds
                            )
                        )
                    } catch {
                        return
                    }
                    finishWithoutCampaignIfNeeded()
                }
                while !Task.isCancelled, !didResolveStep {
                    do {
                        let preferences = try await backend.notificationPreferences()
                        guard !Task.isCancelled,
                              auth.state.session?.userID == userID else { return }
                        preferenceFallbackTask?.cancel()
                        preferenceFallbackTask = nil
                        requestCampaignIfNeeded(preferences: preferences)
                    } catch {
                        guard !Task.isCancelled,
                              auth.state.session?.userID == userID else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(1_500))
                        } catch {
                            return
                        }
                    }
                }
            }
            .onDisappear {
                preferenceFallbackTask?.cancel()
                preferenceFallbackTask = nil
            }
    }

    private func requestCampaignIfNeeded(preferences: NotificationPreferences) {
        guard !didResolveStep,
              auth.state.session?.userID == userID else { return }
        pushNotifications.applyNotificationPreferences(preferences, for: userID)
        guard OnboardingNotificationUpsellPreparationPolicy.resolution(
            preferences: preferences,
            authorizationStatus: pushNotifications.authorizationStatus
        ) == .present else {
            finishWithoutCampaignIfNeeded()
            return
        }
        didResolveStep = true
        productUpsells.bind(to: userID)
        productUpsells.request(
            trigger: .onboardingNotifications,
            userID: userID,
            isEligible: !pushNotifications.notificationsAreEnabled,
            bypassesFrequencyCap: ProductUpsellDebugPolicy.bypassesFrequencyCap()
        ) {
            Task { await finish() }
        }
    }

    private func finishWithoutCampaignIfNeeded() {
        guard !didResolveStep,
              auth.state.session?.userID == userID else { return }
        didResolveStep = true
        Task { await finish() }
    }

    private func requestCampaignWithoutPreferencesIfSystemPermissionIsOff() {
        guard !didResolveStep,
              auth.state.session?.userID == userID,
              OnboardingNotificationUpsellPreparationPolicy.resolution(
                preferences: nil,
                authorizationStatus: pushNotifications.authorizationStatus
              ) == .present else { return }
        didResolveStep = true
        productUpsells.bind(to: userID)
        productUpsells.request(
            trigger: .onboardingNotifications,
            userID: userID,
            isEligible: true,
            bypassesFrequencyCap: ProductUpsellDebugPolicy.bypassesFrequencyCap()
        ) {
            Task { await finish() }
        }
    }
}

struct OnboardingStepScaffold<Content: View, Footer: View>: View {
    @Environment(\.astirBrandMode) private var brandMode
    let step: OnboardingStep
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        step: OnboardingStep,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.step = step
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                    Capsule()
                        .fill(candidateIndex(candidate) <= candidateIndex(step) ? brandMode.accent : brandMode.border)
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, WanderTheme.spacing3)
            .accessibilityLabel("Onboarding step \(candidateIndex(step) + 1) of \(OnboardingStep.allCases.count)")

            content.frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)
                .padding(.bottom, WanderTheme.spacing2)
                .background(.ultraThinMaterial)
        }
        .background(brandMode.background.ignoresSafeArea())
        .foregroundStyle(brandMode.primaryText)
    }

    private func candidateIndex(_ candidate: OnboardingStep) -> Int {
        OnboardingStep.allCases.firstIndex(of: candidate) ?? 0
    }
}

struct OnboardingHeadline: View {
    @Environment(\.astirBrandMode) private var brandMode
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(eyebrow)
                .font(AstirTypography.metadata)
                .tracking(1.4)
                .foregroundStyle(brandMode.accentText)
            Text(title)
                .font(AstirTypography.screenTitle)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingTextField: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let prompt: String
    @Binding var text: String
    var prefix: String?
    var capitalization: TextInputAutocapitalization
    var autocorrectionDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AstirTypography.label)
                .foregroundStyle(brandMode.primaryText)
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix).font(AstirTypography.control)
                }
                TextField(prompt, text: $text)
                    .font(AstirTypography.body)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(autocorrectionDisabled)
                    .submitLabel(.next)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .frame(minHeight: 58)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
    }
}
