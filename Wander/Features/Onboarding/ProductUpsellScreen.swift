import SwiftUI
import UserNotifications

struct ProductUpsellScreen: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
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
                .environment(\.astirBrandMode, .editorial)
                .preferredColorScheme(.dark)
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
                .background(brandMode.background.ignoresSafeArea())
                .foregroundStyle(brandMode.primaryText)
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
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.secondaryText)
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
                OnboardingNotificationExamples()
                    .padding(.top, WanderTheme.spacing6)

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
            .frame(maxWidth: .infinity)
            .padding(.bottom, WanderTheme.spacing6)
        }
    }
}

/// Illustrative examples of supported notification types, rendered natively in
/// every notification primer. They are not live account activity.
struct OnboardingNotificationExamples: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visibleCount = 0

    private let examples: [(icon: String, title: String, message: String)] = [
        ("mappin.and.ellipse", "Ryan checked in", "A new place to discover."),
        ("square.and.arrow.down", "Your Instagram import is ready", "Your places are ready to review."),
        ("person.crop.circle.badge.checkmark", "Mina followed you", "Your circle is growing.")
    ]

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            ForEach(examples.indices, id: \.self) { index in
                let example = examples[index]
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    Image("InvitationAppIcon")
                        .resizable().scaledToFit().frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("ASTIR").font(AstirTypography.metadata).tracking(0.8)
                            Spacer()
                            Text("now").font(AstirTypography.caption)
                        }
                        .foregroundStyle(brandMode.secondaryText)
                        Text(example.title).font(AstirTypography.control)
                            .foregroundStyle(brandMode.primaryText)
                        Text(example.message).font(AstirTypography.caption)
                            .foregroundStyle(brandMode.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(WanderTheme.spacing3)
                .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(brandMode.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                .opacity(reduceMotion || index < visibleCount ? 1 : 0)
                .offset(y: reduceMotion || index < visibleCount ? 0 : 20)
                .scaleEffect(reduceMotion || index < visibleCount ? 1 : 0.96)
            }
        }
        .padding(.vertical, WanderTheme.spacing2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example Astir notifications: Ryan checked in. Your Instagram import is ready. Mina followed you.")
        .accessibilityIdentifier("onboarding.notificationExamples")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if reduceMotion {
                visibleCount = examples.count
                return
            }
            visibleCount = 0
            for count in 1...examples.count {
                do { try await Task.sleep(for: .milliseconds(count == 1 ? 180 : 500)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    visibleCount = count
                }
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion { visibleCount = examples.count }
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
