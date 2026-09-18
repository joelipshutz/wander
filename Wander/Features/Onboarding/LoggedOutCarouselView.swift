import MapKit
import SwiftUI

enum OnboardingCarouselTiming {
    static let defaultAutoAdvanceSeconds = 7.0
    static let slideSeconds = 0.6
    static let slideAnimation = Animation.timingCurve(0.32, 0, 0.18, 1, duration: slideSeconds)
}

/// A persistent lower board lets benefit copy flip while only the upper app UI
/// slides. Opening and account transitions move their entire compositions.
struct LoggedOutCarouselView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.astirBrandMode) private var brandMode
    let analytics: AnalyticsClient
    let getStarted: () -> Void
    let logIn: () -> Void
    let configuration: OnboardingWelcomeConfiguration
    @State private var selection: Int
    @State private var previousSelection: Int?
    @State private var slideProgress = 1.0
    @State private var slideDirection = 1.0
    @State private var slideGeneration = 0
    @State private var autoAdvanceGeneration = 0
    @State private var isPaused: Bool
    @State private var didFinish = false
    @State private var queuedAdvances = 0

    init(analytics: AnalyticsClient, getStarted: @escaping () -> Void,
         logIn: @escaping () -> Void, configuration: OnboardingWelcomeConfiguration = .current) {
        self.analytics = analytics; self.getStarted = getStarted
        self.logIn = logIn; self.configuration = configuration
        _selection = State(initialValue: configuration.startsAt
            .flatMap { configuration.steps.firstIndex(of: $0) } ?? 0)
        _isPaused = State(initialValue: configuration.pausesAutomatically)
    }
    private var accessibilityPausesAutoAdvance: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WANDER_ONBOARDING_FORCE_AUTO_ADVANCE"] == "1" { return false }
        #endif
        return reduceMotion || voiceOverEnabled
    }
    private var isPlaying: Bool {
        scenePhase == .active && !accessibilityPausesAutoAdvance && !isPaused && !didFinish && previousSelection == nil
    }
    private var step: OnboardingWelcomeStep { configuration.steps[selection] }
    private var previousStep: OnboardingWelcomeStep? { previousSelection.map { configuration.steps[$0] } }

    var body: some View {
        ZStack {
            OnboardingBoardColors.background(isDark: colorScheme == .dark).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    AstirMastheadLockup(isCompact: true)
                    Spacer()
                    if !accessibilityPausesAutoAdvance {
                        Button { isPaused.toggle() } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        }
                        .foregroundStyle(brandMode.secondaryText)
                        .accessibilityLabel(isPaused ? "Play introduction" : "Pause introduction")
                        .accessibilityIdentifier("onboarding.pause")
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)
                GeometryReader { geometry in
                    ZStack {
                        if step == .opening || previousStep == .opening, let ticker = configuration.ticker {
                            OnboardingTickerView(content: ticker,
                                descriptionIsDelayed: configuration.descriptionIsDelayed,
                                isPlaying: isPlaying && step == .opening)
                            .offset(x: step == .opening
                                ? (previousSelection == nil ? 0 : slideDirection * geometry.size.width * (1 - slideProgress))
                                : -slideDirection * geometry.size.width * slideProgress)
                            .accessibilityHidden(step != .opening)
                        }
                        // Mount the real preview during the opening so its photo
                        // and map are ready before the first slide reaches them.
                        OnboardingBenefitSequenceView(
                                step: step == .opening ? (previousStep ?? .places) : step,
                                previousStep: previousStep,
                                progress: slideProgress, direction: slideDirection,
                                isPlaying: isPlaying && step != .opening
                            )
                            .offset(x: step == .opening
                                ? -slideDirection * geometry.size.width * slideProgress
                                : (previousStep == .opening ? slideDirection * geometry.size.width * (1 - slideProgress) : 0))
                            .opacity(step == .opening && previousStep == nil ? 0 : 1)
                            .accessibilityHidden(step == .opening)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height), abs(drag.translation.width) > 50 else { return }
                        moveTo(selection + (drag.translation.width < 0 ? 1 : -1), source: "swipe")
                    })
                }
                .accessibilityLabel("What you can do with Astir")
                HStack(spacing: 7) {
                    ForEach(configuration.steps.indices, id: \.self) { index in
                        Capsule().fill(index == selection ? brandMode.primaryText : brandMode.secondaryText.opacity(0.4))
                            .frame(width: index == selection ? 24 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Carousel page").accessibilityValue(String(selection + 1))
                .accessibilityIdentifier("onboarding.carouselPage")
                .padding(.bottom, WanderTheme.spacing4)
                VStack(spacing: WanderTheme.spacing2) {
                    WanderPrimaryButton(title: "Next", systemImage: "arrow.right") { advance(source: "manual") }
                        .accessibilityIdentifier("onboarding.next")
                    Button("Already have an account? Log in") { startAuth(mode: .signIn) }
                        .font(AstirTypography.control).foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        .accessibilityIdentifier("onboarding.logIn")
                }
                .padding(.horizontal, WanderTheme.spacing4).padding(.bottom, WanderTheme.spacing2)
            }
        }
        .onAppear { trackViewed() }
        .onChange(of: selection) { _, _ in autoAdvanceGeneration += 1; trackViewed() }
        .task(id: slideGeneration) {
            guard previousSelection != nil else { return }
            let generation = slideGeneration
            do {
                try await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                // Retain the outgoing view until rendering actually finishes.
                // A wall-clock delay can expire before a busy Map has slid out.
                withAnimation(
                    reduceMotion ? nil : OnboardingCarouselTiming.slideAnimation,
                    completionCriteria: .removed
                ) {
                    slideProgress = 1
                } completion: {
                    guard slideGeneration == generation else { return }
                    previousSelection = nil
                    if queuedAdvances > 0 {
                        queuedAdvances -= 1
                        advance(source: "manual")
                    }
                }
            } catch { }
        }
        .task(id: AutoAdvanceID(generation: autoAdvanceGeneration, selection: selection, isPlaying: isPlaying)) {
            guard isPlaying else { return }
            do {
                try await Task.sleep(for: .seconds(configuration.seconds(for: step)))
                guard !Task.isCancelled, isPlaying else { return }
                advance(source: "timer")
            } catch { }
        }
    }
    private func moveTo(_ next: Int, source: String) {
        guard !didFinish, previousSelection == nil, configuration.steps.indices.contains(next), next != selection else { return }
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) {
            previousSelection = selection; slideDirection = next > selection ? 1 : -1
            selection = next; slideProgress = 0; slideGeneration += 1
        }
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.onboardingCarouselAdvanced,
            properties: ["slide": String(next), "source": source]))
    }
    private func advance(source: String) {
        guard !didFinish else { return }
        if previousSelection != nil {
            // Preserve fast Next taps while each outgoing slide completes.
            // The queue is bounded by the remaining pages plus account entry.
            queuedAdvances = min(queuedAdvances + 1, configuration.steps.count - selection)
            return
        }
        if selection + 1 < configuration.steps.count { moveTo(selection + 1, source: source) }
        else { startAuth(mode: .signUp) }
    }
    private func startAuth(mode: NativeAuthMode) {
        guard !didFinish else { return }
        didFinish = true
        queuedAdvances = 0
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.onboardingAuthStarted,
            properties: ["mode": mode == .signUp ? "sign_up" : "sign_in"]))
        if mode == .signUp { getStarted() } else { logIn() }
    }
    private func trackViewed() {
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.onboardingCarouselViewed, properties: ["slide": String(selection)]))
    }
}
private struct AutoAdvanceID: Equatable { let generation: Int; let selection: Int; let isPlaying: Bool }

private struct OnboardingBenefitSequenceView: View {
    let step: OnboardingWelcomeStep
    let previousStep: OnboardingWelcomeStep?
    let progress: Double
    let direction: Double
    let isPlaying: Bool
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 32, 440)
            let pictureSide = min(width, geometry.size.height * 0.65)
            VStack(spacing: 18) {
                Spacer(minLength: 4)
                ZStack {
                    // Keep both native views at stable identities and dimensions.
                    // Recreating the outgoing Map loses its loaded tiles mid-slide.
                    ForEach([OnboardingWelcomeStep.places, .people]) { scene in
                        let isCurrent = scene == step
                        let isOutgoing = scene == previousStep && scene != step
                        upper(scene)
                            .frame(width: pictureSide, height: pictureSide)
                            .clipped()
                            .offset(x: isCurrent
                                ? (previousStep != nil && previousStep != .opening && previousStep != step
                                    ? direction * geometry.size.width * (1 - progress) : 0)
                                : -direction * geometry.size.width * progress)
                            .opacity(isCurrent || isOutgoing ? 1 : 0)
                            .accessibilityHidden(!isCurrent)
                    }
                }
                .frame(width: pictureSide, height: pictureSide).clipped()
                OnboardingSplitFlapBoard(
                    fromRows: previousStep == .opening ? ["", "", ""] : OnboardingBoardCopy.benefitRows(previousStep ?? step),
                    toRows: OnboardingBoardCopy.benefitRows(step), progress: progress
                )
                .frame(width: width, height: width * 0.36)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(step == .places ? "Keep track of everywhere you’ve been." : "Keep up with the people you love.")
                .accessibilityIdentifier("onboarding.benefitCopy")
                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private func upper(_ step: OnboardingWelcomeStep) -> some View {
        if step == .places {
            OnboardingWelcomeParkPreview().accessibilityIdentifier("onboarding.nativeMap")
        } else {
            OnboardingWelcomePostcard().allowsHitTesting(false)
        }
    }
}

/// A cropped view of the real selected-place surface, with its production photo
/// loader and controls. No separate illustrated card or fictional coffee shop.
private struct OnboardingWelcomeParkPreview: View {
    @StateObject private var previewBackend = WanderBackend(placePhotoRepository: OnboardingPlacePhotoRepository())
    @StateObject private var store = WanderStore(fixtures: .empty())
    private let candidate = FirstVisitParkSuggestionPolicy.hotchkissPark
    var body: some View {
        ZStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.00585, longitude: -118.4842),
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )), interactionModes: []) {
                Marker(candidate.name, coordinate: CLLocationCoordinate2D(latitude: 34.00585, longitude: -118.4842))
                    .tint(AstirTheme.signal.color)
            }
            .mapStyle(.standard(elevation: .flat))
            PlaceProfileMapSurface(place: PlaceSheetPlace(candidate: candidate), saves: [], tasteSaves: [],
                currentUserID: store.currentUser.id, viewerLocation: nil, action: .add,
                onOpen: {}, onAction: {}, onAddToList: {}, onReady: {})
                .environmentObject(store)
                .environmentObject(previewBackend)
                .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct OnboardingWelcomePostcard: View {
    // The existing public-safe onboarding activity fixture. It is clearly
    // identified in the review inventory and cannot invoke signed-in actions or requests.
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

enum OnboardingBoardColors {
    static func background(isDark: Bool) -> Color { isDark ? AstirTheme.ink.color : .white }
    static func face(isDark: Bool, top: Bool) -> Color {
        if isDark { return top ? Color(red: 0.14, green: 0.16, blue: 0.145) : Color(red: 0.10, green: 0.12, blue: 0.105) }
        return top ? .white : Color(red: 0.965, green: 0.965, blue: 0.955)
    }
}

struct OnboardingTickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.astirBrandMode) private var brandMode
    let content: OnboardingTickerContent
    let descriptionIsDelayed: Bool
    let isPlaying: Bool
    @State private var startedAt = Date.now
    @State private var elapsedBeforePause = 0.0
    @State private var flapHaptics = OnboardingFlapHaptics()
    private var animates: Bool { isPlaying && !reduceMotion && !voiceOverEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animates)) { context in
            let elapsed = elapsedBeforePause + (animates ? context.date.timeIntervalSince(startedAt) : 0)
            let readableElapsed = (reduceMotion || voiceOverEnabled)
                ? floor(elapsed / OnboardingTickerFrame.wordSeconds) * OnboardingTickerFrame.wordSeconds : elapsed
            let frame = OnboardingTickerFrame.at(elapsed: readableElapsed, content: content)
            let currentWord = content.words.indices.contains(frame.wordIndex) ? content.words[frame.wordIndex] : ""
            let nextWord = frame.nextWordIndex.flatMap { content.words.indices.contains($0) ? content.words[$0] : nil } ?? currentWord
            let finalRows = OnboardingBoardCopy.finalRows(content.finalLockup ?? "a local experiment")
            let fromRows = frame.showsFinalLockup ? finalRows : OnboardingBoardCopy.openingRows(word: currentWord)
            let toRows = frame.isFinalTransition || frame.showsFinalLockup ? finalRows : OnboardingBoardCopy.openingRows(word: nextWord)
            let leadOpacity = OnboardingTickerFrame.leadOpacity(elapsed: readableElapsed, content: content)
            let outerRowsOpacity = frame.showsFinalLockup ? 1 : (frame.isFinalTransition ? min(1, frame.transitionProgress * 10) : 0)
            let descriptionHasArrived = !descriptionIsDelayed || elapsed >= OnboardingTickerFrame.descriptionArrivalSeconds || reduceMotion || voiceOverEnabled
            GeometryReader { geometry in
                let width = min(geometry.size.width - 32, 440)
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    ZStack {
                        OnboardingSplitFlapBoard(fromRows: fromRows, toRows: toRows,
                            progress: frame.isTransitioning ? frame.transitionProgress : 1,
                            minimumColumns: OnboardingBoardCopy.openingColumns,
                            outerRowsOpacity: outerRowsOpacity, flips: OnboardingSplitFlapFrame.flipCount)
                        Text(content.stableText)
                            .font(.custom("AvenirNext-DemiBold", size: 27, relativeTo: .title2))
                            .foregroundStyle(brandMode.primaryText)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: width)
                            .offset(y: -width * 0.16)
                            .opacity(leadOpacity)
                            .accessibilityHidden(true)
                    }
                        .frame(width: width, height: width * 0.48)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(frame.showsFinalLockup ? (content.finalLockup ?? "") : "\(content.stableText) \(content.words.joined(separator: ", "))")
                        .accessibilityIdentifier("onboarding.ticker")
                    Spacer(minLength: 30)
                    if let description = content.description {
                        Text(description).font(AstirTypography.body)
                            .foregroundStyle(brandMode.secondaryText)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(width: min(width, 360))
                            .opacity(descriptionHasArrived ? 1 : 0)
                            .offset(x: descriptionHasArrived ? 0 : geometry.size.width)
                            .animation(animates ? .easeOut(duration: 0.5) : nil, value: descriptionHasArrived)
                            .padding(.bottom, 26)
                            .accessibilityIdentifier("onboarding.openingDescription")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: elapsed) { _, time in
                flapHaptics.advance(to: time, playing: animates, content: content)
            }
        }
        .onAppear { startedAt = .now }
        .onChange(of: animates) { _, playing in
            flapHaptics.reset()
            if playing { startedAt = .now }
            else { elapsedBeforePause += max(0, Date.now.timeIntervalSince(startedAt)) }
        }
        .onDisappear { flapHaptics.reset() }
    }
}

/// Uniform cells, full flap faces, and a constant three-row footprint. The same
/// board persists across the benefit transition while its letters change.
struct OnboardingSplitFlapBoard: View, @MainActor Animatable {
    let fromRows: [String]
    let toRows: [String]
    var progress: Double
    var minimumColumns: Int = OnboardingBoardCopy.columns
    var outerRowsOpacity: Double = 1
    var flips: Int = 2
    var animatableData: Double { get { progress } set { progress = newValue } }
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        OnboardingFlapSurface(fromRows: fromRows, toRows: toRows,
                              progress: progress, isDark: colorScheme == .dark,
                              minimumColumns: minimumColumns, outerRowsOpacity: outerRowsOpacity, flips: flips)
            .accessibilityHidden(true)
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
