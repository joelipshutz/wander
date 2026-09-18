import SwiftUI

/// Production signed-out composition. The same view is used by the simulator
/// capture route, so the recording contains the real welcome and auth views.
struct SignedOutOnboardingFlowView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.astirBrandMode) private var brandMode

    let analytics: AnalyticsClient
    var configuration: OnboardingWelcomeConfiguration = .current

    @State private var welcomeGeneration = 0
    @State private var filmIsPlaying = false
    @State private var reviewTreatment: OnboardingVisualTreatment?

    private var treatment: OnboardingVisualTreatment { reviewTreatment ?? configuration.visualTreatment }

    var body: some View {
        ZStack {
            (treatment.isFilm ? OnboardingVisualTreatment.background
                : OnboardingWelcomeColors.background(isDark: colorScheme == .dark)).ignoresSafeArea()

            if auth.isPresentingNativeAuth {
                NativeAuthFlowView(
                    isDismissable: true,
                    mode: auth.activeNativeAuthMode,
                    onClose: {
                        // A quick close can reverse the slide before SwiftUI
                        // removes the old carousel. Its finished latch must not
                        // survive into the newly interactive welcome screen.
                        welcomeGeneration += 1
                        auth.nativeAuthDidDismiss()
                    },
                    onLogIn: { auth.beginSignIn(mode: .signIn) }
                )
                .id(auth.activeNativeAuthMode)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                .zIndex(2)
            } else {
                LoggedOutCarouselView(
                    analytics: analytics,
                    getStarted: { auth.beginSignIn(mode: .signUp) },
                    logIn: { auth.beginSignIn(mode: .signIn) },
                    configuration: configuration
                )
                .id(welcomeGeneration)
                .transition(reduceMotion ? .opacity : .move(edge: .leading))
                .zIndex(1)
            }
        }
        .environment(\.onboardingVisualTreatment, treatment)
        // The account hero keeps its own decorative motion after the carousel
        // ends. Form controls and their background never enter the ink layer.
        .environment(\.onboardingFilmMotion, auth.isPresentingNativeAuth || filmIsPlaying)
        .environment(\.astirBrandMode, treatment.isFilm ? .editorial : brandMode)
        .preferredColorScheme(treatment.isFilm ? .dark : nil)
        .onPreferenceChange(OnboardingMotionPreferenceKey.self) { filmIsPlaying = $0 }
        .overlay(alignment: .topTrailing) { reviewMenu }
        .animation(
            reduceMotion ? nil : OnboardingCarouselTiming.slideAnimation,
            value: auth.isPresentingNativeAuth
        )

    }

    @ViewBuilder private var reviewMenu: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WanderOnboardingUITestSignedOut"),
           ProcessInfo.processInfo.environment["WANDER_ONBOARDING_REVIEW_PICKER"] == "1" {
            Menu {
                Button("Approved opening") { reviewTreatment = .approved }
                Button("Film · current fonts") { reviewTreatment = .film }
                Button("Film · matching fonts") { reviewTreatment = .filmType }
                Divider()
                Button("Replay introduction") {
                    welcomeGeneration += 1
                    auth.nativeAuthDidDismiss()
                }
            } label: {
                Label("Style", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityIdentifier("onboarding.reviewTreatment")
            .accessibilityValue(treatment.rawValue)
            .disabled(auth.isPerformingNativeAuth)
            .padding(.trailing, 62)
            .padding(.top, 2)
        }
        #endif
    }
}

#if DEBUG
/// Exercises production entry routing with local providers for native UI tests.
struct SignedOutOnboardingPreview: View {
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var coordinator: AppEntryCoordinator
    @StateObject private var pushNotifications = PushNotificationManager(analytics: NoopAnalyticsClient())
    @StateObject private var productUpsells = ProductUpsellCoordinator()
    @StateObject private var calendarReservations = CalendarReservationManager(analytics: NoopAnalyticsClient())

    init() {
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedOut, canPresentNativeAuth: true))
        let backend = WanderBackend(notificationRepository: SimulatorNotificationRepository())
        _auth = StateObject(wrappedValue: auth)
        _backend = StateObject(wrappedValue: backend)
        _coordinator = StateObject(wrappedValue: AppEntryCoordinator(
            auth: auth, backend: backend, analytics: NoopAnalyticsClient(),
            usesLocalSimulatorTestSession: true, forcedLocalSimulatorOnboardingStep: .identity
        ))
    }

    var body: some View {
        AppEntryView(coordinator: coordinator, analytics: NoopAnalyticsClient(),
            analyticsLifecycle: AppAnalyticsLifecycleTracker(analytics: NoopAnalyticsClient()),
            parser: DeterministicFilterParser())
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(pushNotifications)
            .environmentObject(productUpsells)
            .environmentObject(calendarReservations)
            .modelContainer(WanderModelContainer.preview)
            .astirAdaptiveBrandMode()
    }
}
#endif
