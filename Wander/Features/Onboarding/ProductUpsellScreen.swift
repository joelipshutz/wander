import SwiftUI
import UserNotifications

struct ProductUpsellScreen: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var coordinator: ProductUpsellCoordinator
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    let presentation: ProductUpsellPresentation
    let analytics: AnalyticsClient

    var body: some View {
        Group {
            if presentation.isOnboarding {
                OnboardingStepScaffold(step: .notifications) {
                    ProductUpsellContentView(content: presentation.content, isWorking: isWorking)
                } footer: {
                    footer
                }
            } else {
                VStack(spacing: 0) {
                    ProductUpsellContentView(content: presentation.content, isWorking: isWorking)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    footer
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.top, WanderTheme.spacing2)
                        .padding(.bottom, WanderTheme.spacing2)
                        .background(.ultraThinMaterial)
                }
                .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
                .foregroundStyle(WanderTheme.textInk.color)
            }
        }
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled(requiresSystemPermissionRequest)
        .task {
            await pushNotifications.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await pushNotifications.refreshAuthorizationStatus() }
        }
    }

    private var footer: some View {
        VStack(spacing: WanderTheme.spacing1) {
            WanderPrimaryButton(
                title: isWorking ? "Turning on notifications…" : primaryTitle,
                isDisabled: isWorking
            ) {
                handlePrimaryAction()
            }
            .accessibilityIdentifier("productUpsell.primary")

            if allowsSecondaryAction {
                Button("Not now") {
                    trackOnboardingPermissionResult("skipped")
                    coordinator.complete(
                        presentationID: presentation.id,
                        with: .dismissed
                    )
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .accessibilityIdentifier("productUpsell.secondary")
            }
        }
    }

    private var requiresSystemPermissionRequest: Bool {
        OnboardingNotificationPermissionPolicy.action(
            for: pushNotifications.authorizationStatus
        ) == .request
    }

    private var allowsSecondaryAction: Bool {
        !isWorking && OnboardingNotificationPermissionPolicy.allowsSecondaryAction(
            for: pushNotifications.authorizationStatus
        )
    }

    private var primaryTitle: String {
        OnboardingNotificationPermissionPolicy.primaryTitle(
            for: pushNotifications.authorizationStatus
        )
    }

    private func handlePrimaryAction() {
        guard isCurrentPresentation,
              coordinator.beginAction(for: presentation.id) else { return }
        Task { @MainActor in
            defer { coordinator.endAction(for: presentation.id) }
            await pushNotifications.refreshAuthorizationStatus()
            guard isCurrentPresentation else {
                return
            }
            switch OnboardingNotificationPermissionPolicy.action(
                for: pushNotifications.authorizationStatus
            ) {
            case .openSettings:
                coordinator.recordAction(.openedSettings, for: presentation.id)
                trackOnboardingPermissionResult("settings")
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            case .request, .enable:
                let enabled = await pushNotifications.enableNotifications(
                    backend: backend,
                    expectedUserID: presentation.userID,
                    authSession: auth
                ) != nil
                guard isCurrentPresentation else { return }
                trackOnboardingPermissionResult(enabled ? "true" : "false")
                coordinator.complete(
                    presentationID: presentation.id,
                    with: enabled ? .enabled : .declined
                )
            }
        }
    }

    private var isCurrentPresentation: Bool {
        auth.state.session?.userID == presentation.userID
            && pushNotifications.notificationPreferencesUserID == presentation.userID
            && coordinator.ownsPresentation(id: presentation.id)
    }

    private var isWorking: Bool {
        coordinator.actionInFlightPresentationIDs.contains(presentation.id)
    }

    private func trackOnboardingPermissionResult(_ result: String) {
        guard presentation.isOnboarding else { return }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingPermissionResult,
                properties: ["permission": "notifications", "granted": result]
            )
        )
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

private struct ProductUpsellPresentationBlockerModifier: ViewModifier {
    @EnvironmentObject private var coordinator: ProductUpsellCoordinator
    let isPresented: Bool
    @State private var blockerID = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, isPresented in
                coordinator.setPresentationBlocker(id: blockerID, isActive: isPresented)
            }
            .onDisappear {
                coordinator.setPresentationBlocker(id: blockerID, isActive: false)
            }
    }
}

extension View {
    func blocksProductUpsells(while isPresented: Bool) -> some View {
        modifier(ProductUpsellPresentationBlockerModifier(isPresented: isPresented))
    }
}
