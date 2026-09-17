import SwiftUI

enum OnboardingCarouselTiming {
    static let defaultAutoAdvanceSeconds = 7.0
}

/// Native onboarding content. Benefit scenes render the same map and postcard
/// components as the app instead of raster illustrations of an interface.
struct LoggedOutCarouselView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    let analytics: AnalyticsClient
    let getStarted: () -> Void
    let logIn: () -> Void
    let configuration: OnboardingWelcomeConfiguration

    @State private var selection: Int
    @State private var autoAdvanceGeneration = 0
    @State private var isPaused: Bool
    @State private var didFinish = false

    init(
        analytics: AnalyticsClient,
        getStarted: @escaping () -> Void,
        logIn: @escaping () -> Void,
        configuration: OnboardingWelcomeConfiguration = .current
    ) {
        self.analytics = analytics
        self.getStarted = getStarted
        self.logIn = logIn
        self.configuration = configuration
        _selection = State(initialValue: configuration.startsAt
            .flatMap { configuration.steps.firstIndex(of: $0) } ?? 0)
        _isPaused = State(initialValue: configuration.pausesAutomatically)
    }

    private var accessibilityPausesAutoAdvance: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WANDER_ONBOARDING_FORCE_AUTO_ADVANCE"] == "1" {
            return false
        }
        #endif
        return reduceMotion || voiceOverEnabled
    }

    private var isPlaying: Bool {
        scenePhase == .active && !accessibilityPausesAutoAdvance && !isPaused && !didFinish
    }

    var body: some View {
        ZStack {
            WanderTheme.surfaceBone.color.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    AstirMastheadLockup(isCompact: true)
                    Spacer()
                    if !accessibilityPausesAutoAdvance {
                        Button {
                            isPaused.toggle()
                        } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        }
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .accessibilityLabel(isPaused ? "Play introduction" : "Pause introduction")
                        .accessibilityIdentifier("onboarding.pause")
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)

                TabView(selection: $selection) {
                    ForEach(Array(configuration.steps.enumerated()), id: \.element.id) { index, step in
                        welcomeScene(step, isPlaying: isPlaying && index == selection)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityLabel("What you can do with Astir")

                HStack(spacing: 7) {
                    ForEach(configuration.steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? WanderTheme.textInk.color : WanderTheme.borderStrong.color)
                            .frame(width: index == selection ? 24 : 7, height: 7)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selection)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Carousel page")
                .accessibilityValue(String(selection + 1))
                .accessibilityIdentifier("onboarding.carouselPage")
                .padding(.bottom, WanderTheme.spacing4)

                VStack(spacing: WanderTheme.spacing2) {
                    WanderPrimaryButton(title: "Next", systemImage: "arrow.right") {
                        advance(source: "manual")
                    }
                    .accessibilityIdentifier("onboarding.next")

                    Button("Already have an account? Log in") {
                        startAuth(mode: .signIn)
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .accessibilityIdentifier("onboarding.logIn")
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing2)
            }
        }
        .onAppear { trackViewed() }
        .onChange(of: selection) { _, _ in
            autoAdvanceGeneration += 1
            trackViewed()
        }
        .task(id: AutoAdvanceID(
            generation: autoAdvanceGeneration,
            selection: selection,
            isPlaying: isPlaying
        )) {
            guard isPlaying else { return }
            let seconds = configuration.seconds(for: configuration.steps[selection])
            do {
                try await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, isPlaying else { return }
                advance(source: "timer")
            } catch {
                // Navigation, backgrounding, Pause and accessibility all cancel
                // this view-owned task. Returning restarts a full reading interval.
            }
        }
    }

    @ViewBuilder
    private func welcomeScene(_ step: OnboardingWelcomeStep, isPlaying: Bool) -> some View {
        switch step {
        case .opening:
            if let ticker = configuration.ticker {
                OnboardingTickerView(
                    content: ticker,
                    descriptionIsDelayed: configuration.descriptionIsDelayed,
                    isPlaying: isPlaying
                )
            }
        case .places, .people:
            OnboardingBenefitScene(step: step, isPlaying: isPlaying)
        }
    }

    private func advance(source: String) {
        guard !didFinish else { return }
        if selection + 1 < configuration.steps.count {
            let next = selection + 1
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                selection = next
            }
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingCarouselAdvanced,
                properties: ["slide": String(next), "source": source]
            ))
        } else {
            startAuth(mode: .signUp)
        }
    }

    private func startAuth(mode: NativeAuthMode) {
        guard !didFinish else { return }
        didFinish = true
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.onboardingAuthStarted,
            properties: ["mode": mode == .signUp ? "sign_up" : "sign_in"]
        ))
        if mode == .signUp { getStarted() } else { logIn() }
    }

    private func trackViewed() {
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.onboardingCarouselViewed,
            properties: ["slide": String(selection)]
        ))
    }
}

private struct AutoAdvanceID: Equatable {
    let generation: Int
    let selection: Int
    let isPlaying: Bool
}

private struct OnboardingBenefitScene: View {
    let step: OnboardingWelcomeStep
    let isPlaying: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: WanderTheme.spacing4) {
                    Group {
                        if step == .places {
                            OnboardingLocationMapPreview(isPlaying: isPlaying)
                                .frame(height: min(390, max(260, proxy.size.height * 0.67)))
                                .accessibilityIdentifier("onboarding.nativeMap")
                        } else {
                            OnboardingWelcomePostcard()
                        }
                    }

                    VStack(spacing: WanderTheme.spacing2) {
                        Text(step == .places ? "Example places" : "Example activity")
                            .font(AstirTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)

                        Text(step == .places
                             ? "Keep track of everywhere you’ve been."
                             : "Keep up with the people you love.")
                            .font(AstirTypography.screenTitle)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct OnboardingWelcomePostcard: View {
    // The existing public-safe onboarding activity fixture. It is clearly
    // labelled as an example and cannot invoke signed-in actions or requests.
    private let context = ActivityEngagementContext(
        activityID: "00000000-0000-0000-0000-000000000447",
        actor: ProfileShell(
            id: "onboarding-Mina", handle: "mina", displayName: "Mina",
            avatarURL: nil, bio: nil, relationship: .mutual
        ),
        placeName: "Marigold Table", placeServerID: nil,
        placeDetail: "Santa Monica · Restaurant", status: .been,
        occurredAt: Date().addingTimeInterval(-7200),
        note: "The patio at golden hour. Get the focaccia!", rating: 5
    )

    var body: some View {
        ActivityPostcardView(
            context: context,
            visiblePlace: nil,
            metadataIcon: "fork.knife",
            secondaryMetadataTitle: nil,
            secondaryMetadataAction: nil,
            secondaryMetadataAccessibilityLabel: nil,
            artworkAction: nil,
            artworkAccessibilityLabel: nil,
            destinationAction: nil,
            destinationAccessibilityLabel: nil,
            openProfile: nil,
            actorAccessibilityIdentifier: "onboarding.exampleActor",
            destinationAccessibilityIdentifier: "onboarding.examplePlace",
            postcardAccessibilityIdentifier: "onboarding.nativePostcard",
            showsEngagementActions: false,
            onSharePreviewPresentation: nil
        )
        .environment(\.activityPostcardVisualStyle, .astir)
    }
}

/// The confirmed opening uses physical, individually hinged letter flaps.
/// The supporting line and surrounding pages retain their separate slide motion.
struct OnboardingTickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let content: OnboardingTickerContent
    let descriptionIsDelayed: Bool
    let isPlaying: Bool

    @State private var startedAt = Date.now
    @State private var elapsedBeforePause = 0.0

    private var animates: Bool { isPlaying && !reduceMotion && !voiceOverEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animates)) { context in
            let elapsed = elapsedBeforePause + (animates ? context.date.timeIntervalSince(startedAt) : 0)
            // Accessibility can be enabled mid-flip. Resolve to a whole readable
            // word rather than freezing half of two different glyphs on screen.
            let readableElapsed = (reduceMotion || voiceOverEnabled)
                ? floor(elapsed / OnboardingTickerFrame.wordSeconds) * OnboardingTickerFrame.wordSeconds
                : elapsed
            let frame = OnboardingTickerFrame.at(elapsed: readableElapsed, content: content)
            let currentWord = content.words.indices.contains(frame.wordIndex) ? content.words[frame.wordIndex] : ""
            let nextWord = frame.nextWordIndex.flatMap { content.words.indices.contains($0) ? content.words[$0] : nil } ?? currentWord
            let closing = frame.isFinalTransition || frame.showsFinalLockup
            let descriptionHasArrived = !descriptionIsDelayed
                || elapsed >= OnboardingTickerFrame.wordSeconds * 1.5
                || reduceMotion || voiceOverEnabled
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    OnboardingSplitFlapLine(
                        from: frame.showsFinalLockup ? (content.finalLockup ?? content.stableText) : content.stableText,
                        to: closing ? (content.finalLockup ?? content.stableText) : content.stableText,
                        progress: frame.isFinalTransition ? frame.transitionProgress : 1,
                        choices: [content.stableText, content.finalLockup ?? content.stableText],
                        color: closing ? WanderTheme.terracotta.color : WanderTheme.textInk.color,
                        showsHousing: false
                    )
                    OnboardingSplitFlapLine(
                        from: frame.showsFinalLockup ? "" : currentWord,
                        to: closing ? "" : nextWord,
                        progress: frame.isTransitioning ? frame.transitionProgress : 1,
                        choices: content.words,
                        color: WanderTheme.terracotta.color,
                        showsHousing: true
                    )
                    .opacity(frame.showsFinalLockup ? 0 : 1)
                    .accessibilityHidden(closing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(frame.showsFinalLockup
                    ? (content.finalLockup ?? "")
                    : "\(content.stableText) \(content.words.joined(separator: ", "))")
                .accessibilityIdentifier("onboarding.ticker")

                if let description = content.description {
                    Text(description)
                        .font(AstirTypography.body)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(closing ? 0 : (descriptionHasArrived ? 1 : 0))
                        .offset(x: descriptionHasArrived ? 0 : 48)
                        .animation(animates ? .easeOut(duration: 0.45) : nil, value: descriptionHasArrived)
                        .animation(animates ? .easeOut(duration: 0.2) : nil, value: closing)
                }
                Spacer(minLength: WanderTheme.spacing6)
            }
            .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing6)
            .frame(maxWidth: .infinity)
        }
        .onAppear { startedAt = .now }
        .onChange(of: animates) { _, playing in
            if playing {
                startedAt = .now
            } else {
                elapsedBeforePause += max(0, Date.now.timeIntervalSince(startedAt))
            }
        }
    }
}

/// Column widths stay fixed across all words. Each column has two stationary
/// half-glyphs and two physical flap faces rotating around the same center hinge.
private struct OnboardingSplitFlapLine: View {
    @ScaledMetric(relativeTo: .largeTitle) private var pointSize = 34.0
    let from: String
    let to: String
    let progress: Double
    let choices: [String]
    let color: Color
    let showsHousing: Bool

    private var columnWidths: [CGFloat] {
        let strings = (choices + [from, to]).map(Array.init)
        let count = strings.map(\.count).max() ?? 0
        let base = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
        let font = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: pointSize)
        return (0..<count).map { index in
            let width = strings.map { characters -> CGFloat in
                guard characters.indices.contains(index) else { return 0 }
                return (String(characters[index]) as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            return max(pointSize * 0.24, width) + (showsHousing ? 5 : 1)
        }
    }

    var body: some View {
        let source = Array(from)
        let destination = Array(to)
        let widths = columnWidths
        GeometryReader { geometry in
            let gap = showsHousing ? 2.0 : 0.0
            let total = widths.reduce(0, +) + gap * Double(max(0, widths.count - 1))
            let scale = min(1, geometry.size.width / max(1, total))
            HStack(spacing: gap * scale) {
                ForEach(widths.indices, id: \.self) { index in
                    let frame = OnboardingSplitFlapFrame.at(
                        progress: progress,
                        from: source.indices.contains(index) ? source[index] : " ",
                        to: destination.indices.contains(index) ? destination[index] : " ",
                        column: index
                    )
                    OnboardingSplitFlapLetter(
                        frame: frame,
                        width: widths[index] * scale,
                        height: pointSize * 1.38 * scale,
                        fontSize: pointSize * scale,
                        color: color,
                        showsHousing: showsHousing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: pointSize * 1.38)
        .accessibilityHidden(true)
    }
}

private struct OnboardingSplitFlapLetter: View {
    let frame: OnboardingSplitFlapFrame
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let color: Color
    let showsHousing: Bool

    private var isTurning: Bool { frame.from != frame.to && frame.progress > 0 && frame.progress < 1 }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                half(frame.to, top: true)
                half(frame.from, top: false)
            }
            if frame.progress < 0.5 {
                half(frame.from, top: true)
                    .overlay(Color.black.opacity(isTurning ? frame.progress * 0.2 : 0))
                    .rotation3DEffect(
                        .degrees(-180 * frame.progress),
                        axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                half(frame.to, top: false)
                    .overlay(Color.black.opacity(isTurning ? (1 - frame.progress) * 0.16 : 0))
                    .rotation3DEffect(
                        .degrees(180 * (1 - frame.progress)),
                        axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55
                    )
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if showsHousing || isTurning {
                Rectangle()
                    .fill(WanderTheme.textInk.color.opacity(showsHousing ? 0.16 : 0.08))
                    .frame(height: 0.6)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: showsHousing ? 2 : 0))
        .overlay {
            if showsHousing {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(WanderTheme.textInk.color.opacity(0.06), lineWidth: 0.5)
            }
        }
    }

    private func half(_ character: Character, top: Bool) -> some View {
        Text(String(character))
            .font(.system(size: fontSize, weight: .semibold, design: .serif))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(width: width, height: height)
            .offset(y: top ? height / 4 : -height / 4)
            .frame(width: width, height: height / 2)
            .clipped()
            .background {
                WanderTheme.surfaceBone.color
                if showsHousing {
                    WanderTheme.textInk.color.opacity(top ? 0.018 : 0.045)
                }
            }
    }
}

struct OnboardingLaunchView: View {
    let message: String?

    init(message: String? = nil) {
        self.message = message
    }

    var body: some View {
        ZStack {
            AstirLaunchArtwork.background.ignoresSafeArea()
            GeometryReader { proxy in
                // Center the artwork alone. Loading copy must not change its frame.
                AstirLaunchLockup(animationsEnabled: false)
                    .frame(width: AstirLaunchArtwork.width(availableWidth: proxy.size.width))
                    .overlay(alignment: .top) {
                        if let message {
                            VStack(spacing: WanderTheme.spacing2) {
                                ProgressView()
                                    .tint(AstirTheme.signal.color)
                                    .dynamicTypeSize(.large)
                                Text(message)
                                    .font(AstirTypography.bodySmall)
                                    .foregroundStyle(AstirLaunchArtwork.text)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: max(0, proxy.size.width - 48))
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: AstirLaunchArtwork.width(availableWidth: proxy.size.width)
                                / AstirLaunchArtwork.aspectRatio + WanderTheme.spacing4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Startup and the map tab must use the same full-screen center.
            .ignoresSafeArea(.container)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Opening Astir")
    }
}
