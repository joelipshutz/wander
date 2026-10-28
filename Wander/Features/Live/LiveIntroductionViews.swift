import SwiftUI

struct LiveIntroductionCard: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let audience: LiveIntroductionAudience
    let onShowMe: () -> Void
    let onNotNow: () -> Void
    var onPresented: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(audience == .returning ? "Your Feed Now Has A Map" : "Welcome To Live")
                .font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Explore Your People’s Activity In The Feed Or On Its Map. Your Map Is Still In Profile.")
                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { actions }
            } else {
                HStack(spacing: 20) { actions }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("live.introduction.card")
        .onAppear(perform: onPresented)
    }

    @ViewBuilder private var actions: some View {
        Button("Show Me", action: onShowMe)
            .font(AstirTypography.control).foregroundStyle(brand.accentText)
            .frame(minHeight: 44).accessibilityIdentifier("live.introduction.showMe")
        Button("Not Now", action: onNotNow)
            .font(AstirTypography.control).foregroundStyle(brand.secondaryText)
            .frame(minHeight: 44).accessibilityIdentifier("live.introduction.notNow")
    }
}

/// Optional teaching, reusable from Live or Settings. Default replay is read-only;
/// an explicit first-visit context can acknowledge represented teaching steps.
struct LiveIntroductionGuide: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    @State private var step: LiveIntroductionStep
    // Capture the original guide account even if its host changes while closing.
    @State private var orientation: LiveIntroductionOrientationContext?
    private let steps: [LiveIntroductionStep]
    var onStepChange: ((LiveIntroductionStep) -> Void)?
    var onStepAcknowledged: ((LiveIntroductionStep) -> Void)?
    var onFinished: (() -> Void)?

    init(initialStep: LiveIntroductionStep = .mapAndFeed,
         steps: [LiveIntroductionStep] = LiveIntroductionStep.allCases,
         orientation: LiveIntroductionOrientationContext? = nil,
         onStepChange: ((LiveIntroductionStep) -> Void)? = nil,
         onStepAcknowledged: ((LiveIntroductionStep) -> Void)? = nil,
         onFinished: (() -> Void)? = nil) {
        let resolved = steps.isEmpty ? LiveIntroductionStep.allCases : steps
        self.steps = resolved
        _step = State(initialValue: resolved.contains(initialStep) ? initialStep : resolved[0])
        _orientation = State(initialValue: orientation)
        self.onStepChange = onStepChange
        self.onStepAcknowledged = onStepAcknowledged
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Live · Lists · Profile", systemImage: "rectangle.bottomthird.inset.filled")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                Image(systemName: step.symbol)
                    .font(.system(size: 40, weight: .medium)).foregroundStyle(brand.accentText)
                    .accessibilityHidden(true)
                Text(step.title).font(AstirTypography.screenTitle).foregroundStyle(brand.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(step.message).font(AstirTypography.body).foregroundStyle(brand.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(index + 1) Of \(steps.count)")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                VStack(spacing: 8) {
                    Button(index == steps.count - 1 ? "Done" : "Next", action: advance)
                        .font(AstirTypography.control).foregroundStyle(brand.accentForeground)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(brand.accent, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("live.introduction.next")
                    if index > 0 {
                        Button("Previous") { step = steps[index - 1] }
                            .font(AstirTypography.control).foregroundStyle(brand.accentText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("live.introduction.previous")
                    }
                }
                Text("You Can Revisit This Guide In Settings → What’s Changed.")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(brand.background.ignoresSafeArea())
        .navigationTitle("What’s Changed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }.foregroundStyle(brand.accentText)
                    .accessibilityIdentifier("live.introduction.close")
            }
        }
        .accessibilityIdentifier("live.introduction.guide")
        .onChange(of: step, initial: true) { _, newValue in onStepChange?(newValue) }
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private func advance() {
        if let orientation,
           LiveIntroductionOrientationStore().acknowledge(step, context: orientation,
               authenticatedUserID: auth.state.session?.userID,
               storeUserID: store.currentUser.id, isSessionValidated: auth.isSignedIn) {
            LiveIntroductionRecoveryCenter.shared.didChange()
        }
        onStepAcknowledged?(step)
        if index + 1 < steps.count {
            step = steps[index + 1]
        } else {
            onFinished?()
            dismiss()
        }
    }
}

struct LiveIntroductionMigrationCard: View {
    @Environment(\.astirBrandMode) private var brand
    let onContinue: () -> Void
    let onNotNow: () -> Void
    let onPresented: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Where You Left Off").font(AstirTypography.cardTitle)
            Text("Your Unfinished Guide And Saved Details Are Still Here. Continue Now, Or Find Them In Settings → What’s Changed.")
                .font(AstirTypography.bodySmall).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { actions }
                VStack(alignment: .leading) { actions }
            }
        }.foregroundStyle(brand.primaryText).padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("live.migration.card").onAppear(perform: onPresented)
    }
    @ViewBuilder private var actions: some View {
        Button("Continue", action: onContinue).foregroundStyle(brand.accentText)
            .frame(minHeight: 44).accessibilityIdentifier("live.migration.continue")
        Button("Not Now", action: onNotNow).foregroundStyle(brand.secondaryText)
            .frame(minHeight: 44).accessibilityIdentifier("live.migration.notNow")
    }
}

/// Settings and the optional migration card share the same resumable guide.
struct LiveIntroductionReplayView: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    let userID: String
    @State private var record: LiveIntroductionMigrationRecord?
    @State private var recoveryHandoff = LiveIntroductionReplayRecoveryHandoff()
    init(userID: String) {
        self.userID = userID
        _record = State(initialValue: LiveIntroductionMigrationStore().load(for: userID))
    }
    var body: some View {
        Group {
            if let record, !record.isComplete {
                List {
                    if record.recovery != nil {
                        Section("Your Unfinished Step") {
                            Text(recoveryMessage(record))
                            Button("Continue") {
                                guard let latest = LiveIntroductionMigrationStore().load(for: userID),
                                      latest.id == record.id,
                                      recoveryHandoff.queue(latest, authenticatedUserID: authenticatedUserID,
                                          storeUserID: store.currentUser.id,
                                          isSessionValidated: auth.isSessionValidated) else { return }
                                // Pop this Settings destination (or dismiss its
                                // migration sheet) before Root routes recovery.
                                dismiss()
                            }.accessibilityIdentifier("live.migration.openRecovery")
                                .disabled(!auth.isSessionValidated)
                            Text("Opening A Screen Does Not Complete A Save, Send An Invitation, Or Change Permissions.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Dismiss This Old Tutorial Step") {
                                guard store.currentUser.id == userID else { return }
                                self.record = LiveIntroductionMigrationStore().dismissRecovery(userID: userID, recordID: record.id)
                                LiveIntroductionRecoveryCenter.shared.didChange()
                            }.accessibilityIdentifier("live.migration.dismissOldStep")
                            Text("This Dismisses Only The Tutorial Reminder. Saved Drafts, Permissions And Invitations Remain Unchanged.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !record.pendingSteps.isEmpty {
                        NavigationLink("Continue The Live Guide") {
                            LiveIntroductionGuide(initialStep: record.pendingSteps[0], steps: record.pendingSteps,
                                onStepAcknowledged: { step in acknowledge(step, record: record) })
                        }.accessibilityIdentifier("live.migration.guide")
                    }
                    if record.pendingSteps.isEmpty, record.recovery == nil, !record.isComplete {
                        Text("This Older Guide Contains A Step This Version Cannot Restore. Its Original Checkpoint Is Preserved; It Has Not Been Marked Complete.")
                    }
                    NavigationLink("Review The Whole Guide") { LiveIntroductionGuide() }
                }
            } else { LiveIntroductionGuide() }
        }
        .navigationTitle("What’s Changed").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .disabled(recoveryHandoff.hasPendingRequest)
        .onChange(of: store.currentUser.id) { _, id in
            if id != userID { recoveryHandoff.cancel(); dismiss() }
        }
        .onAppear { record = LiveIntroductionMigrationStore().load(for: userID) }
        .onDisappear {
            // Pushing a teaching guide also disappears this view, but cannot
            // route anything without an explicit queued Continue action.
            guard let latest = recoveryHandoff.takeAfterDisappearance(
                authenticatedUserID: authenticatedUserID, storeUserID: store.currentUser.id,
                isSessionValidated: auth.isSessionValidated,
                latestRecord: LiveIntroductionMigrationStore().load(for: userID)) else { return }
            LiveIntroductionRecoveryCenter.shared.open(latest)
        }
    }
    private var authenticatedUserID: String? { auth.isSignedIn ? auth.state.session?.userID : nil }
    private func acknowledge(_ step: LiveIntroductionStep, record: LiveIntroductionMigrationRecord) {
        guard store.currentUser.id == userID else { return }
        _ = LiveIntroductionMigrationStore().acknowledge(step, userID: userID, recordID: record.id)
        LiveIntroductionRecoveryCenter.shared.didChange()
    }
    private func recoveryMessage(_ record: LiveIntroductionMigrationRecord) -> String {
        switch record.recovery {
        case .retained(.saveFlow, _), .retained(.add, _):
            "Continue Reopens Your Saved Form When It Is Available. Otherwise, It Starts A New Save Using The Previous Place Name When Available. Add The Date, Notes And Photos Again."
        case .retainedLesson(.contactInvite): "Your Invitation Step Is Optional. Continue With Your Previous Selection; Nothing Is Sent Automatically."
        case .retainedLesson(.deviceFeaturesLesson), .retainedLesson(.awaitingDeviceFeaturesLesson): "Review The Existing Widget And Device Setup Guide. No Permission Is Requested Automatically."
        case .retainedLesson(.importLesson): "Open The Existing Import Flow When You Are Ready. Your Imports Stay Unchanged."
        case .retained(.listDetail, _), .retained(.listEditor, _): "Continue Opens Lists So You Can Choose The List You Want To Return To."
        default: "Continue Takes You Back To The Relevant Screen So You Can Pick Up Where You Left Off."
        }
    }
}

struct LiveIntroductionDeviceRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let onAcknowledged: () -> Void
    var body: some View {
        List {
            Section("Astir, One Press Away") {
                Label("Choose Astir Check In For Action Button Or Controls", systemImage: "button.programmable")
                Label("Add Quick Add, Search, Activity Or Nearby Widgets", systemImage: "square.grid.2x2")
                Label("Send Places To Astir From Another App’s Share Sheet", systemImage: "square.and.arrow.up")
                Link("Setup Guide", destination: WalkthroughHelpDestination.extensions)
                Text("These Are Optional Setup Instructions. This Guide Does Not Request Or Change Device Permissions.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Got It", action: onAcknowledged).accessibilityIdentifier("live.migration.deviceAcknowledged")
            }
        }.navigationTitle("Device Setup")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not Now") { dismiss() } } }
    }
}
