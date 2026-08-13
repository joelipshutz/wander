import SwiftUI

struct CommunityReportSheet: View {
    @Environment(\.dismiss) private var dismiss
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
            .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
            .navigationTitle(receipt == nil ? "report \(subject.kind.displayName)" : "report sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                }
            }
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
                        .font(WanderTypography.editorialTitle)
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(subject.context)
                        .font(WanderTypography.emphasizedBody)
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text("Your report is private. The person you report won’t be told who sent it.")
                        .font(WanderTypography.body)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(CommunityReportReason.allCases) { reason in
                        reasonButton(reason)
                    }
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Anything else? (optional)")
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.textInk.color)
                    TextField("Add context for our safety team", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($detailsFocused)
                        .padding(WanderTheme.spacing3)
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                        .overlay {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                                .stroke(WanderTheme.borderStrong.color, lineWidth: 1)
                        }
                        .onChange(of: details) { _, newValue in
                            if newValue.count > 500 {
                                details = String(newValue.prefix(500))
                            }
                        }
                        .accessibilityIdentifier("communityReport.details")
                    Text("\(details.count)/500")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(WanderTypography.emphasizedBody)
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
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
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
                            ? WanderTheme.textOnAction.color
                            : WanderTheme.terracottaDark.color
                    )
                    .background(
                        selectedReason == reason
                            ? WanderTheme.terracotta.color
                            : WanderTheme.terracottaTint.color
                    )
                    .clipShape(Circle())

                Text(reason.title)
                    .font(WanderTypography.emphasizedBody)
                    .foregroundStyle(WanderTheme.textInk.color)

                Spacer()

                Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        selectedReason == reason
                            ? WanderTheme.terracotta.color
                            : WanderTheme.borderStrong.color
                    )
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        selectedReason == reason
                            ? WanderTheme.terracotta.color
                            : WanderTheme.borderHairline.color,
                        lineWidth: selectedReason == reason ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("communityReport.reason.\(reason.rawValue)")
    }

    private var confirmation: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .accessibilityHidden(true)

            Text("Thanks for looking out for the community.")
                .font(WanderTypography.editorialTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(WanderTheme.textInk.color)

            Text("Our safety team will review the report. If anyone is in immediate danger, contact local emergency services.")
                .font(WanderTypography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)

            WanderPrimaryButton(title: "Done", systemImage: "checkmark") {
                dismiss()
            }

            if subject.reportedUserID != store.currentUser.id {
                Button(role: .destructive) {
                    blockReportedUser()
                } label: {
                    Label(isBlocking ? "Blocking…" : "Block this person", systemImage: "hand.raised.fill")
                        .font(WanderTypography.emphasizedBody)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
                .disabled(isBlocking)
                .accessibilityIdentifier("communityReport.block")
            }
        }
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("communityReport.confirmation")
    }

    private func submit() {
        guard let selectedReason, !isSubmitting else { return }
        let normalizedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CommunityContentPolicy.validate(normalizedDetails)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

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
