import SwiftUI
import PhotosUI
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
struct OnboardingEmptySuggestions: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 44))
                .foregroundStyle(WanderTheme.pinSocial.color)
            Text(title).font(AstirTypography.sectionTitle)
            Text(message)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
        }
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppEntryRecoveryView: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let message: String
    let canContinueOffline: Bool
    let retry: () -> Void
    let continueOffline: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing6) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(brandMode.accentText)
                .frame(width: 112, height: 112)
                .background(brandMode.accentWash)
                .clipShape(Circle())

            VStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(AstirTypography.screenTitle)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(AstirTypography.body)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            VStack(spacing: WanderTheme.spacing1) {
                WanderPrimaryButton(title: "Try again") { retry() }
                if canContinueOffline {
                    Button("Continue offline") { continueOffline() }
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.background.ignoresSafeArea())
        .foregroundStyle(brandMode.primaryText)
    }
}
struct ProductUpsellContentView: View {
    let content: ProductUpsellContent
    let isWorking: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: WanderTheme.spacing6) {
                Spacer(minLength: WanderTheme.spacing4)
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 220, height: 220)
                    Image(systemName: content.systemImage)
                        .font(.system(size: 86, weight: .medium))
                        .foregroundStyle(accent)
                        .symbolEffect(.bounce, value: isWorking)
                }
                .accessibilityHidden(true)

                OnboardingHeadline(
                    eyebrow: content.eyebrow,
                    title: content.title,
                    message: content.message
                )
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityIdentifier("productUpsell.progress")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(maxWidth: .infinity, minHeight: 560)
        }
    }

    private var accent: Color {
        switch content.palette {
        case .sun:
            WanderTheme.categorySun.color
        }
    }
}

struct OnboardingIdentityView: View {
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
        let state = ProcessInfo.processInfo.arguments.last ?? ""
        _availability = State(initialValue: state == "identity-checking" ? .checking : state == "identity-taken" ? .unavailable : .available)
        _isSaving = State(initialValue: state == "identity-saving")
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
                                    .foregroundStyle(AstirTheme.ink.color)
                                    .frame(width: 34, height: 34)
                                    .background(WanderTheme.terracotta.color)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 3))
                            }
                        }
                        .accessibilityLabel("Add an optional profile photo")

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add a photo")
                                .font(AstirTypography.cardTitle)
                            Text("Optional — you can always do this later.")
                                .font(AstirTypography.bodySmall)
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

    private func checkAvailability() async {}
    private func save() async {}
    private func loadPhoto(_ item: PhotosPickerItem) async {}
}
struct OnboardingFriendRow: View {
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
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("@\(recommendation.profile.handle) · \(reason)")
                    .font(AstirTypography.caption)
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

