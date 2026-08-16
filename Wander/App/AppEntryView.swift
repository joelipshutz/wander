import Foundation
import SwiftUI
#if canImport(TikTokOpenSDKCore)
import TikTokOpenSDKCore
#endif

struct AppEntryForegroundRefreshPolicy {
    static let graceInterval: TimeInterval = 30

    private var backgroundedAtUptime: TimeInterval?

    mutating func didEnterBackground(atUptime uptime: TimeInterval) {
        backgroundedAtUptime = uptime
    }

    mutating func shouldRefreshSession(atUptime uptime: TimeInterval) -> Bool {
        guard let backgroundedAtUptime else { return true }
        self.backgroundedAtUptime = nil
        return uptime - backgroundedAtUptime >= Self.graceInterval
    }
}

enum AppEntryNotificationGateState: Equatable {
    case validating(expectedUserID: String?)
    case authenticated(userID: String)
    case signedOut

    init(authState: AuthState, isSessionValidated: Bool) {
        if isSessionValidated, case .signedIn(let session) = authState {
            self = .authenticated(userID: session.userID)
            return
        }

        switch authState {
        case .signedIn(let session), .offline(let session, _):
            self = .validating(expectedUserID: session.userID)
        case .loading:
            self = .validating(expectedUserID: nil)
        case .signedOut, .unavailable:
            self = .signedOut
        }
    }

    func synchronize() {
        switch self {
        case .validating(let expectedUserID):
            WanderAppDelegate.beginAuthenticatedSessionValidation(
                expectedUserID: expectedUserID
            )
        case .authenticated(let userID):
            WanderAppDelegate.setAuthenticatedSessionActive(userID: userID)
        case .signedOut:
            WanderAppDelegate.setAuthenticatedSessionSignedOut()
        }
    }
}

@MainActor
struct AppEntryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @ObservedObject var coordinator: AppEntryCoordinator

    let analytics: AnalyticsClient
    let analyticsLifecycle: AppAnalyticsLifecycleTracker
    let parser: any LLMFilterParser

    @State private var didFinishInitialResolution = false
    @State private var deepLinkInbox = WanderDeepLinkInbox()
    @State private var foregroundRefreshPolicy = AppEntryForegroundRefreshPolicy()

    var body: some View {
        let notificationGateState = AppEntryNotificationGateState(
            authState: auth.state,
            isSessionValidated: auth.isSessionValidated
        )

        Group {
            switch coordinator.state {
            case .launching:
                OnboardingLaunchView()
            case .signedOut:
                LoggedOutCarouselView(analytics: analytics) {
                    auth.beginSignIn(mode: .signUp)
                } logIn: {
                    auth.beginSignIn(mode: .signIn)
                }
            case .onboarding(let session, let step):
                OnboardingFlowView(
                    session: session,
                    initialStep: step,
                    analytics: analytics,
                    saveProgress: { coordinator.saveProgress($0, for: session) },
                    complete: { coordinator.completeOnboarding(for: session, serverConfirmed: $0) }
                )
            case .ready(let session, let firstVisitWalkthroughEligible):
                WanderRootView(
                    initialSharedProfileRoute: coordinator.pendingSharedProfileRoute,
                    initialSession: session,
                    isSessionValidated: auth.isSessionValidated,
                    isFirstVisitWalkthroughEligible: firstVisitWalkthroughEligible,
                    onFirstVisitWalkthroughCompleted: {
                        coordinator.completeFirstVisitWalkthrough(for: session)
                    },
                    deepLinkLaunchRequest: deepLinkInbox.request(
                        ifSessionValidated: auth.isSessionValidated
                    ),
                    onDeepLinkLaunchRequestHandled: { requestID in
                        deepLinkInbox.consume(requestID)
                    },
                    analytics: analytics,
                    parser: parser
                )
                .id(session.userID)
            case .recoverableFailure(_, let message, let canContinueOffline):
                AppEntryRecoveryView(
                    title: "Your map is still here",
                    message: message,
                    canContinueOffline: canContinueOffline,
                    retry: coordinator.retry,
                    continueOffline: coordinator.continueOffline
                )
            case .unavailable(let message):
                AppEntryRecoveryView(
                    title: "Sign in isn’t available",
                    message: message,
                    canContinueOffline: false,
                    retry: coordinator.retry,
                    continueOffline: {}
                )
            }
        }
        .environmentObject(auth)
        .environmentObject(backend)
        .environmentObject(pushNotifications)
        .sheet(isPresented: $auth.isPresentingNativeAuth, onDismiss: {
            auth.nativeAuthDidDismiss()
            Task {
                await auth.refreshSession()
                coordinator.authStateChanged(auth.state)
            }
        }) {
            ClerkNativeAuthView(mode: auth.activeNativeAuthMode)
                .environmentObject(auth)
        }
        .task {
            analyticsLifecycle.recordLaunch()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-WanderForceSignedOut") {
                try? await auth.signOut()
            }
            #endif
            await coordinator.start()
            didFinishInitialResolution = true
        }
        .onChange(of: auth.state) { _, state in
            guard didFinishInitialResolution else { return }
            coordinator.authStateChanged(state)
        }
        .onChange(of: notificationGateState, initial: true) { _, state in
            state.synchronize()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                foregroundRefreshPolicy.didEnterBackground(
                    atUptime: ProcessInfo.processInfo.systemUptime
                )
            case .active:
                guard didFinishInitialResolution else { return }
                let shouldRefreshSession = foregroundRefreshPolicy.shouldRefreshSession(
                    atUptime: ProcessInfo.processInfo.systemUptime
                )
                if !shouldRefreshSession,
                   auth.isSessionValidated,
                   case .ready = coordinator.state {
                    return
                }
                analyticsLifecycle.recordForegroundSession()
                auth.beginSessionValidation()
                Task { await coordinator.start(preservingReadyState: true) }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onOpenURL { url in
            receiveIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            receiveIncomingURL(url)
        }
    }

    private func receiveIncomingURL(_ url: URL) {
        #if canImport(TikTokOpenSDKCore)
        if TikTokURLHandler.handleOpenURL(url) {
            return
        }
        #endif
        if let attribution = AcquisitionAttribution(url: url) {
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.acquisitionLinkOpened,
                    properties: attribution.properties
                )
            )
        }
        if WanderRootView.sharedProfileRoute(for: url) != nil {
            if case .ready = coordinator.state {
                deepLinkInbox.receive(url)
            } else {
                coordinator.capturePendingURL(url)
            }
            return
        }
        deepLinkInbox.receive(url)
    }
}

private struct AppEntryRecoveryView: View {
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
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 112, height: 112)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Circle())

            VStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(WanderTheme.editorialDisplay(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            VStack(spacing: WanderTheme.spacing1) {
                WanderPrimaryButton(title: "Try again") { retry() }
                if canContinueOffline {
                    Button("Continue offline") { continueOffline() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }
}
