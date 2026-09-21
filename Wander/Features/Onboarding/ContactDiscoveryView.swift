import SwiftUI

enum ContactDiscoveryContent {
    static let title = "Connect with your people"
    static let explanation = "Find friends on Astir by securely comparing phone numbers and email addresses from the contacts you allow. Your address book isn’t saved on our servers."
    static let discoverability = "Finding friends also lets people who have your verified email or phone number find your public Astir profile. You choose whom to follow. Turn this off anytime in Settings."
}

struct OnboardingContactsView: View {
    let userID: String
    let service: ContactDiscoveryService
    let analytics: AnalyticsClient
    let continueAction: () -> Void
    @Environment(\.astirBrandMode) private var brandMode
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        OnboardingStepScaffold(step: .contacts) {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 64)).foregroundStyle(brandMode.accentText)
                        .frame(maxWidth: .infinity).padding(.vertical, WanderTheme.spacing6)
                    OnboardingHeadline(eyebrow: "YOUR PEOPLE", title: ContactDiscoveryContent.title,
                        message: ContactDiscoveryContent.explanation)
                    Text(ContactDiscoveryContent.discoverability)
                        .font(AstirTypography.bodySmall).foregroundStyle(brandMode.secondaryText)
                    if let errorMessage {
                        Text(errorMessage).font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.primaryText)
                            .accessibilityIdentifier("onboarding.contacts.error")
                    }
                }.padding(WanderTheme.spacing4)
            }
        } footer: {
            VStack(spacing: WanderTheme.spacing2) {
                WanderPrimaryButton(title: isWorking ? "Connecting…" : "Find friends", isDisabled: isWorking) {
                    Task {
                        isWorking = true; errorMessage = nil
                        defer { isWorking = false }
                        do {
                            try await service.enable(userID: userID)
                            analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.onboardingPermissionResult,
                                properties: ["permission": "contacts", "granted": "true"]))
                            continueAction()
                        } catch {
                            errorMessage = (error as? ContactDiscoveryError)?.errorDescription ?? ContactDiscoveryError.unavailable.errorDescription
                        }
                    }
                }.accessibilityIdentifier("onboarding.contacts.findFriends")
                Button("Not now", action: continueAction)
                    .font(AstirTypography.control).foregroundStyle(brandMode.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(isWorking).accessibilityIdentifier("onboarding.contacts.skip")
            }
        }
    }
}

struct ContactDiscoverySettingsScreen: View {
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var revision = 0

    var body: some View {
        Form {
            Section {
                Text(ContactDiscoveryContent.explanation)
                Text(ContactDiscoveryContent.discoverability).font(.footnote)
            }
            Section {
                if let userID = auth.state.session?.userID {
                    if backend.contactDiscovery.hasConsent(userID: userID) {
                        Label("Contact suggestions are on", systemImage: "checkmark.circle")
                    } else {
                        Button("Find friends on this device") { Task { await enable(userID) } }
                            .accessibilityIdentifier("contacts.settings.enable")
                    }
                    if enabled || backend.contactDiscovery.hasConsent(userID: userID) {
                        Button("Turn off contact matching", role: .destructive) { Task { await disable(userID) } }
                            .accessibilityIdentifier("contacts.settings.disable")
                    }
                }
                if isWorking { ProgressView() }
                if let errorMessage { Text(errorMessage).font(.footnote) }
            } footer: {
                Text("Turning this off removes your matching identifiers and contact suggestions. Existing follows stay. Manage which contacts are allowed in iOS Settings.")
            }
        }
        .id(revision)
        .disabled(isWorking)
        .navigationTitle("Find friends")
        .task { await refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        guard let userID = auth.state.session?.userID, !isWorking else { return }
        do { enabled = try await backend.contactDiscovery.reconcile(userID: userID) }
        catch { errorMessage = "Couldn’t check contact matching. Try again when you’re connected." }
    }
    private func enable(_ userID: String) async {
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do { try await backend.contactDiscovery.enable(userID: userID); enabled = true; revision += 1 }
        catch { errorMessage = (error as? ContactDiscoveryError)?.errorDescription ?? ContactDiscoveryError.unavailable.errorDescription }
    }
    private func disable(_ userID: String) async {
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do { try await backend.contactDiscovery.disable(userID: userID); enabled = false; revision += 1 }
        catch { errorMessage = "Contact uploads are off on this device. Reconnect to finish turning off discovery for your account."; revision += 1 }
    }
}
