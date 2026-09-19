import SwiftUI

/// Production signed-out composition. The same view is used by the simulator
/// capture route, so the recording contains the real welcome and auth views.
struct SignedOutOnboardingFlowView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let analytics: AnalyticsClient
    var configuration: OnboardingWelcomeConfiguration = .current

    @State private var welcomeGeneration = 0

    var body: some View {
        ZStack {
            OnboardingWelcomeColors.background(isDark: colorScheme == .dark).ignoresSafeArea()

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
        .animation(
            reduceMotion ? nil : OnboardingCarouselTiming.slideAnimation,
            value: auth.isPresentingNativeAuth
        )

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
