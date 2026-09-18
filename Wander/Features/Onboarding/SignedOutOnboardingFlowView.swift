import SwiftUI

/// Production signed-out composition. The same view is used by the simulator
/// capture route, so the recording contains the real welcome and auth views.
struct SignedOutOnboardingFlowView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let analytics: AnalyticsClient
    var configuration: OnboardingWelcomeConfiguration = .current
    var initialAuthMode: NativeAuthMode? = nil

    @State private var appliedInitialMode = false
    @State private var welcomeGeneration = 0

    var body: some View {
        ZStack {
            OnboardingBoardColors.background(isDark: colorScheme == .dark).ignoresSafeArea()

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
        .task {
            guard !appliedInitialMode else { return }
            appliedInitialMode = true
            if let initialAuthMode {
                auth.beginSignIn(mode: initialAuthMode)
            }
        }
    }
}
