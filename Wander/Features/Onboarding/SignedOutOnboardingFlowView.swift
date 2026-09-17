import SwiftUI

/// Production signed-out composition. The same view is used by the simulator
/// capture route, so the recording contains the real welcome and auth views.
struct SignedOutOnboardingFlowView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let analytics: AnalyticsClient
    var configuration: OnboardingWelcomeConfiguration = .current
    var initialAuthMode: NativeAuthMode? = nil

    @State private var appliedInitialMode = false

    var body: some View {
        ZStack {
            WanderTheme.surfaceBone.color.ignoresSafeArea()

            if auth.isPresentingNativeAuth {
                NativeAuthFlowView(
                    isDismissable: true,
                    mode: auth.activeNativeAuthMode,
                    onClose: { auth.nativeAuthDidDismiss() },
                    onLogIn: { auth.beginSignIn(mode: .signIn) }
                )
                .id(auth.activeNativeAuthMode)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                .zIndex(1)
            } else {
                LoggedOutCarouselView(
                    analytics: analytics,
                    getStarted: { auth.beginSignIn(mode: .signUp) },
                    logIn: { auth.beginSignIn(mode: .signIn) },
                    configuration: configuration
                )
                .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.42),
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
