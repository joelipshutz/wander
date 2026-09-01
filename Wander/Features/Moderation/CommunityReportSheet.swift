import SwiftUI

struct CommunityReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend

    let subject: CommunityReportSubject

    @State private var selectedReason: CommunityReportReason?
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var receipt: CommunityReportReceipt?
    @State private var errorMessage: String?
    @State private var isBlocking = false
    @FocusState private var detailsFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if receipt != nil {
                    confirmation
                } else {
                    reportForm
                }
            }
            .foregroundStyle(brandMode.primaryText)
            .background(brandMode.background.ignoresSafeArea())
            .navigationTitle(receipt == nil ? "report \(subject.kind.displayName)" : "report sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                }
            }
            .tint(brandMode.accent)
            .toolbarBackground(brandMode.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled(isSubmitting)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("communityReport.sheet")
    }

    private var reportForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("What’s going on?")
                        .font(AstirTypography.sheetTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text(subject.context)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.secondaryText)
                    Text("Your report is private. The person you report won’t be told who sent it.")
                        .font(AstirTypography.body)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(CommunityReportReason.allCases) { reason in
                        reasonButton(reason)
                    }
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Anything else? (optional)")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.primaryText)
                    TextField("Add context for our safety team", text: $details, axis: .vertical)
                        .font(AstirTypography.body)
                        .lineLimit(3...6)
                        .focused($detailsFocused)
                        .padding(WanderTheme.spacing3)
                        .background(brandMode.recessedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                        .overlay {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                                .stroke(brandMode.border, lineWidth: 1)
                        }
                        .onChange(of: details) { _, newValue in
                            if newValue.count > 500 {
                                details = String(newValue.prefix(500))
                            }
                        }
                        .accessibilityIdentifier("communityReport.details")
                    Text("\(details.count)/500")
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(WanderTheme.stateError.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("communityReport.error")
                }

                WanderPrimaryButton(
                    title: isSubmitting ? "Sending…" : "Send report",
                    systemImage: "paperplane.fill",
                    isDisabled: selectedReason == nil || isSubmitting
                ) {
                    submit()
                }
                .accessibilityIdentifier("communityReport.submit")

                Link(destination: URL(string: "https://getrec.me/community")!) {
                    Label("Read the rec.me community guidelines", systemImage: "arrow.up.right")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.accent)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func reasonButton(_ reason: CommunityReportReason) -> some View {
        Button {
            selectedReason = reason
            errorMessage = nil
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: reason.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(
                        selectedReason == reason
                            ? brandMode.accentForeground
                            : brandMode.accent
                    )
                    .background(
                        selectedReason == reason
                            ? brandMode.accent
                            : brandMode.accentWash
                    )
                    .clipShape(Circle())

                Text(reason.title)
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)

                Spacer()

                Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        selectedReason == reason
                            ? brandMode.accent
                            : brandMode.border
                    )
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        selectedReason == reason
                            ? brandMode.accent
                            : brandMode.border,
                        lineWidth: selectedReason == reason ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("communityReport.reason.\(reason.rawValue)")
    }

    private var confirmation: some View {
        ScrollView {
            VStack(spacing: WanderTheme.spacing4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(WanderTheme.stateSuccess.color)
                    .accessibilityHidden(true)

                Text("Thanks for looking out for the community.")
                    .font(AstirTypography.sheetTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(brandMode.primaryText)

                Text("Our safety team will review the report. If anyone is in immediate danger, contact local emergency services.")
                    .font(AstirTypography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                WanderPrimaryButton(title: "Done", systemImage: "checkmark") {
                    dismiss()
                }

                if subject.reportedUserID != store.currentUser.id {
                    Button(role: .destructive) {
                        blockReportedUser()
                    } label: {
                        Label(isBlocking ? "Blocking…" : "Block this person", systemImage: "hand.raised.fill")
                            .font(AstirTypography.control)
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    }
                    .disabled(isBlocking)
                    .accessibilityIdentifier("communityReport.block")
                }
            }
            .padding(WanderTheme.spacing6)
            .frame(maxWidth: .infinity, minHeight: 520)
        }
        .accessibilityIdentifier("communityReport.confirmation")
    }

    private func submit() {
        guard let selectedReason, !isSubmitting else { return }
        let normalizedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        errorMessage = nil
        detailsFocused = false
        Task {
            do {
                receipt = try await backend.submitCommunityReport(
                    CommunityReportSubmission(
                        subject: subject,
                        reason: selectedReason,
                        details: normalizedDetails.isEmpty ? nil : normalizedDetails
                    )
                )
            } catch {
                errorMessage = "Your report couldn’t be sent. Check your connection and try again."
            }
            isSubmitting = false
        }
    }

    private func blockReportedUser() {
        guard !isBlocking else { return }
        isBlocking = true
        Task {
            await store.block(userID: subject.reportedUserID, backend: backend)
            dismiss()
        }
    }
}
