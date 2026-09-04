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
                    title: "Find friends already here",
                    message: "Allow contacts so rec.me can help connect you with people you know. We won’t message anyone.",
                    bullets: ["See friends’ place maps", "Share trusted recommendations"],
                    primaryTitle: "Continue",
                    analytics: analytics,
                    request: { await contactsPermission.requestAccess() },
                    continueAction: { advance(from: .contacts) }
                )
            case .friends:
                OnboardingFriendSuggestionsView(backend: backend, analytics: analytics) {
                    advance(from: .friends)
                }
            case .notifications:
                OnboardingNotificationView(analytics: analytics) {
                    await finish()
                }
            }
        }
        .environmentObject(backend)
        .environmentObject(auth)
        .environmentObject(pushNotifications)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(.snappy(duration: 0.35), value: step)
        .preferredColorScheme(.light)
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

private struct OnboardingIdentityView: View {
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
    @State private var availability: Availability = .idle
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, handle }

    init(session: AuthSession, analytics: AnalyticsClient, continueAction: @escaping () -> Void) {
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
    }

    private var draft: ProfileIdentityDraft {
        ProfileIdentityDraft(displayName: name, handle: handle)
    }

    private var canSubmit: Bool {
        draft.isValid
            && availability != .checking
            && availability != .unavailable
            && !isSaving
    }

    private var handleBinding: Binding<String> {
        Binding(
            get: { handle },
            set: { value in
                handle = value
                hasEditedHandle = true
                availability = .idle
                errorMessage = nil
            }
        )
    }

    var body: some View {
        let avatarImage = previewImage.map { Image(uiImage: $0) }

        OnboardingStepScaffold(step: .identity) {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    HStack(spacing: WanderTheme.spacing4) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let avatarImage {
                                        avatarImage
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Circle()
                                            .fill(WanderTheme.terracottaTint.color)
                                            .overlay(
                                                Image(systemName: "person.crop.circle.fill")
                                                    .font(.system(size: 52))
                                                    .foregroundStyle(WanderTheme.terracotta.color)
                                            )
                                    }
                                }
                                .frame(width: 104, height: 104)
                                .clipShape(Circle())

                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(WanderTheme.textOnAction.color)
                                    .frame(width: 34, height: 34)
                                    .background(WanderTheme.terracotta.color)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 3))
                            }
                        }
                        .accessibilityLabel("Add an optional profile photo")

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add a photo")
                                .font(.system(size: 17, weight: .black))
                            Text("Optional — you can always do this later.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }

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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(availabilityFeedbackColor)
                        }
                    }

                    if let validation = draft.validationError, !name.isEmpty || !handle.isEmpty {
                        Text(validation.message)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
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
                }
            )
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
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            availability = try await backend.isProfileHandleAvailable(draft.normalizedHandle) ? .available : .unavailable
        } catch is CancellationError {
        } catch {
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
            _ = try await backend.updateCurrentProfile(
                ProfileDetailsUpdate(
                    displayName: draft.normalizedDisplayName,
                    handle: draft.normalizedHandle
                )
            )
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingIdentitySubmitted,
                properties: ["photo_selected": jpegData == nil ? "false" : "true"]
            ))
            if let jpegData {
                _ = try? await backend.uploadProfileAvatar(jpegData: jpegData, userID: session.userID)
            }
            continueAction()
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
                    .font(.system(size: 15, weight: .bold))
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
                    .font(.system(size: 15, weight: .bold))
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
                                .font(.system(size: 16, weight: .bold))
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

private struct OnboardingFriendSuggestionsView: View {
    let analytics: AnalyticsClient
    let continueAction: () -> Void
    @StateObject private var model: OnboardingFriendSuggestionsModel

    init(
        backend: WanderBackend,
        analytics: AnalyticsClient,
        continueAction: @escaping () -> Void
    ) {
        self.analytics = analytics
        self.continueAction = continueAction
        _model = StateObject(wrappedValue: OnboardingFriendSuggestionsModel(backend: backend))
    }

    var body: some View {
        OnboardingStepScaffold(step: .friends) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                OnboardingHeadline(
                    eyebrow: "YOUR TRUSTED MAP",
                    title: "rec.me is better with people",
                    message: "Start with a few people whose taste you’d like to see. You’re always in control of who you follow."
                )
                .padding(.horizontal, WanderTheme.spacing4)

                Group {
                    switch model.loadingState {
                    case .idle, .loading:
                        Spacer()
                        ProgressView("Finding good people to follow…")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        Spacer()
                    case .failed:
                        OnboardingEmptySuggestions(
                            title: "Suggestions are taking a minute",
                            message: "You can skip this and find people from Discover anytime."
                        )
                    case .loaded:
                        if model.recommendations.isEmpty {
                            OnboardingEmptySuggestions(
                                title: "Your people will show up here",
                                message: "Skip for now — we’ll keep finding trusted people as rec.me grows."
                            )
                        } else {
                            ScrollView {
                                LazyVStack(spacing: WanderTheme.spacing2) {
                                    ForEach(model.recommendations, id: \.profile.id) { recommendation in
                                        Button { model.toggle(recommendation.profile.id) } label: {
                                            OnboardingFriendRow(
                                                recommendation: recommendation,
                                                isSelected: model.selectedIDs.contains(recommendation.profile.id)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, WanderTheme.spacing4)
                            }
                        }
                    }
                }
            }
            .padding(.top, WanderTheme.spacing2)
        } footer: {
            VStack(spacing: WanderTheme.spacing1) {
                let count = model.selectedIDs.count
                WanderPrimaryButton(
                    title: count == 0 ? "Continue" : "Follow \(count) \(count == 1 ? "person" : "people")",
                    isDisabled: model.isFollowing
                ) {
                    Task {
                        let followed = await model.followSelected()
                        analytics.track(AnalyticsEvent(
                            name: WanderAnalyticsEvents.onboardingFriendSuggestionsCompleted,
                            properties: ["selected_count": String(count), "followed_count": String(followed)]
                        ))
                        if followed > 0 {
                            analytics.track(
                                AnalyticsEvent(
                                    name: WanderAnalyticsEvents.followCreated,
                                    properties: [
                                        "source": "onboarding_suggestions",
                                        "outcome": "succeeded",
                                        "followed_count": String(followed)
                                    ]
                                )
                            )
                            analytics.track(
                                .engagement(
                                    need: .connect,
                                    action: .followCreated,
                                    surface: "onboarding_suggestions",
                                    properties: ["followed_count": String(followed)]
                                )
                            )
                        }
                        continueAction()
                    }
                }
                Button("Skip") {
                    analytics.track(AnalyticsEvent(
                        name: WanderAnalyticsEvents.onboardingFriendSuggestionsCompleted,
                        properties: ["selected_count": "0", "followed_count": "0", "source": "skipped"]
                    ))
                    continueAction()
                }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            }
        }
        .task {
            await model.load()
        }
    }
}

private struct OnboardingFriendRow: View {
    let recommendation: DiscoverPeopleRecommendation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: String(recommendation.profile.displayName.prefix(2)).uppercased(),
                avatarURL: recommendation.profile.avatarURL,
                size: 50,
                color: WanderTheme.avatarSofia.color
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.profile.displayName)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("@\(recommendation.profile.handle) · \(reason)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(isSelected ? WanderTheme.stateSuccess.color : WanderTheme.borderStrong.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(isSelected ? WanderTheme.stateSuccess.color.opacity(0.45) : WanderTheme.borderHairline.color)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var reason: String {
        switch recommendation.reason {
        case .followsYou: "follows you"
        case .sharedFollows(let count): "\(count) mutual connections"
        case .suggested: "suggested for you"
        }
    }
}

private struct OnboardingEmptySuggestions: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 44))
                .foregroundStyle(WanderTheme.pinSocial.color)
            Text(title).font(.system(size: 18, weight: .black))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
        }
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingNotificationView: View {
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let analytics: AnalyticsClient
    let finish: () async -> Void
    @State private var isWorking = false

    var body: some View {
        OnboardingStepScaffold(step: .notifications) {
            VStack(spacing: WanderTheme.spacing6) {
                Spacer(minLength: WanderTheme.spacing4)
                ZStack {
                    Circle()
                        .fill(WanderTheme.categorySun.color.opacity(0.18))
                        .frame(width: 220, height: 220)
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 86, weight: .medium))
                        .foregroundStyle(WanderTheme.categorySun.color)
                        .symbolEffect(.bounce, value: isWorking)
                }
                OnboardingHeadline(
                    eyebrow: "STAY IN THE LOOP",
                    title: "Don’t miss a great find",
                    message: "Get a heads-up when friends connect with you, share places, or add something worth seeing."
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing4)
        } footer: {
            VStack(spacing: WanderTheme.spacing1) {
                WanderPrimaryButton(
                    title: isWorking ? "Turning on notifications…" : OnboardingNotificationPermissionPolicy.primaryTitle(
                        for: pushNotifications.authorizationStatus
                    ),
                    isDisabled: isWorking
                ) {
                    Task {
                        isWorking = true
                        await pushNotifications.refreshAuthorizationStatus()
                        if OnboardingNotificationPermissionPolicy.action(
                            for: pushNotifications.authorizationStatus
                        ) == .openSettings {
                            isWorking = false
                            analytics.track(AnalyticsEvent(
                                name: WanderAnalyticsEvents.onboardingPermissionResult,
                                properties: ["permission": "notifications", "granted": "settings"]
                            ))
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                            return
                        }

                        let enabled = await pushNotifications.enableNotifications(backend: backend, authState: auth.state) != nil
                        analytics.track(AnalyticsEvent(
                            name: WanderAnalyticsEvents.onboardingPermissionResult,
                            properties: ["permission": "notifications", "granted": enabled ? "true" : "false"]
                        ))
                        await finish()
                    }
                }
                if OnboardingNotificationPermissionPolicy.allowsSecondaryAction(
                    for: pushNotifications.authorizationStatus
                ) {
                    Button("Not now") {
                        analytics.track(AnalyticsEvent(
                            name: WanderAnalyticsEvents.onboardingPermissionResult,
                            properties: ["permission": "notifications", "granted": "skipped"]
                        ))
                        Task { await finish() }
                    }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .task {
            await pushNotifications.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await pushNotifications.refreshAuthorizationStatus() }
        }
    }
}

private struct OnboardingStepScaffold<Content: View, Footer: View>: View {
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
                        .fill(candidateIndex(candidate) <= candidateIndex(step) ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color)
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
        .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private func candidateIndex(_ candidate: OnboardingStep) -> Int {
        OnboardingStep.allCases.firstIndex(of: candidate) ?? 0
    }
}

private struct OnboardingHeadline: View {
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .black))
                .tracking(1.4)
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(title)
                .font(WanderTheme.editorialDisplay(size: 38, weight: .bold))
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var prefix: String?
    var capitalization: TextInputAutocapitalization
    var autocorrectionDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix).font(.system(size: 16, weight: .bold))
                }
                TextField(prompt, text: $text)
                    .font(.system(size: 16, weight: .medium))
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(autocorrectionDisabled)
                    .submitLabel(.next)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .frame(minHeight: 58)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}
