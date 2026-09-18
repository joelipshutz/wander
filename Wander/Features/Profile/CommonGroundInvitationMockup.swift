import SwiftUI
import UIKit

/// Shared composer and artwork for the local rehearsal and real invitation links.
struct CommonGroundInvitationMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: CommonGroundInvitationDraft
    @State private var envelopeOpened: Bool
    @State private var showsMessages = false
    @State private var showsCalendar = false
    @State private var shareContent: WanderShareContent?
    @State private var isPreparingShare = false
    @State private var shareFailed = false
    @AccessibilityFocusState private var postcardFocused: Bool
    @FocusState private var noteFocused: Bool
    let opensEnvelope: Bool
    let liveSharing: Bool
    let showsLinkage: Bool
    private let sourcePlace: CommonGroundMockPlace
    private let canShare: (CommonGroundMockPlace) -> Bool
    private let prepareShare: ((CommonGroundInvitationDraft) async throws -> WanderShareContent)?

    init(draft: CommonGroundInvitationDraft, opensEnvelope: Bool = false, initiallyOpened: Bool = false, liveSharing: Bool = false, showsLinkage: Bool = false, canShare: @escaping (CommonGroundMockPlace) -> Bool = { _ in true }, prepareShare: ((CommonGroundInvitationDraft) async throws -> WanderShareContent)? = nil) {
        _draft = State(initialValue: draft)
        _envelopeOpened = State(initialValue: initiallyOpened)
        self.opensEnvelope = opensEnvelope
        self.liveSharing = liveSharing
        self.showsLinkage = showsLinkage
        sourcePlace = draft.place
        self.canShare = canShare
        self.prepareShare = prepareShare
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if opensEnvelope {
                    recipient
                } else {
                    Text(showsLinkage ? draft.reasonTitle : "ASTIR’s taking the wheel")
                        .font(AstirTypography.sheetTitle)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("common-ground.invitation.heading")
                    invitationPreview
                    composerFields
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
                    .accessibilityIdentifier("common-ground.invitation.done-editing")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !opensEnvelope || envelopeOpened { bottomAction }
        }
        .sheet(isPresented: $showsCalendar) {
            CGInvitationDatePicker(date: draft.suggestedDate ?? (liveSharing ? .now : CommonGroundInvitationDraft.preview.suggestedDate ?? .now)) {
                draft.suggestedDate = $0
            }
        }
        .sheet(isPresented: $showsMessages) {
            if liveSharing, let content = shareContent {
                WanderShareSheet(content: content)
            } else {
                CommonGroundMessagesMockup(draft: draft, isReply: opensEnvelope)
            }
        }
        .alert("Couldn’t create this invitation", isPresented: $shareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your draft is still here. Please try again in a moment")
        }
        .onChange(of: sourcePlace) { _, place in
            if liveSharing {
                showsMessages = false
            }
            draft = CommonGroundInvitationDraft(place: place, note: draft.note, suggestedDate: draft.suggestedDate)
        }
        .astirScreen()
        .astirAdaptiveBrandMode()
    }

    private var invitationPreview: some View {
        CGInvitationLinkPreview(draft: draft, showsViewButton: false)
            .accessibilityElement(children: .contain)
            .accessibilityFocused($postcardFocused)
    }

    private func invitationContext(includesMessage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if includesMessage {
                Text(draft.message)
                    .font(AstirTypography.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("common-ground.invitation.copy")
            }
            Label {
                Text(opensEnvelope ? draft.recipientReasonTitle : draft.reasonTitle)
                    .accessibilityIdentifier("common-ground.invitation.reason-title")
            } icon: {
                Image(systemName: draft.reasonSymbol)
            }
            .font(AstirTypography.label)
            .foregroundStyle(brand.accentText)
            if let evidence = draft.postcardReasonDetail {
                Text(evidence)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composerFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Make it yours").font(AstirTypography.control)
                    Text("Optional").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                TextField(draft.message, text: $draft.note, axis: .vertical)
                    .focused($noteFocused)
                    .font(AstirTypography.body).lineLimit(2...3)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                    .onTapGesture { noteFocused = true }
                    .accessibilityLabel("Your message, optional")
                    .accessibilityIdentifier("common-ground.invitation.message")
            }
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    noteFocused = false
                    showsCalendar = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.title3).foregroundStyle(brand.accentText)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("When").font(AstirTypography.control)
                            Text(draft.whenText ?? "Pick a day & time")
                                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("common-ground.invitation.when-selection")
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .foregroundStyle(brand.primaryText).padding(16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("When, \(draft.whenText ?? "optional, choose a day and time")")
                .accessibilityIdentifier("common-ground.invitation.when")

            }
        }
    }

    private var recipient: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                CommonGroundPersonAvatar(person: draft.place.viewer, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(draft.place.viewer.shortName)’s got a plan").font(AstirTypography.sheetTitle)
                    Text("And a pretty good reason for it")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
            }
            if envelopeOpened {
                invitationPreview
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 16)))
                invitationContext(includesMessage: true)
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) {
                        envelopeOpened = true
                    }
                    Task { @MainActor in
                        await Task.yield()
                        postcardFocused = true
                    }
                } label: {
                    VStack(spacing: 22) {
                        CGInvitationEnvelopeArtwork(symbol: draft.reasonSymbol, recipientName: draft.place.partner.shortName)
                            .aspectRatio(1.25, contentMode: .fit)
                        Text("A plan for us").font(AstirTypography.screenTitle)
                        Label("Take a peek", systemImage: "envelope.open")
                            .font(AstirTypography.control).foregroundStyle(brand.accentText)
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(brand.primaryText).frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.vertical, 20)
                .accessibilityLabel("Open \(draft.place.viewer.shortName)’s invitation")
                .accessibilityHint("Reveals the place, the reason, and the proposed time")
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 8) {
            Button {
                noteFocused = false
                guard !liveSharing || canShare(draft.place) else { return }
                if liveSharing {
                    Task { await createInvitation() }
                } else {
                    showsMessages = true
                }
            } label: {
                Label(isPreparingShare ? "Creating invitation…" : liveSharing ? "Share invitation" : opensEnvelope ? "Reply in Messages" : "Preview in Messages", systemImage: liveSharing ? "square.and.arrow.up" : "message.fill")
                    .font(AstirTypography.control).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(brand.accentForeground)
                    .background(brand.accent, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("common-ground.invitation.messages")
            .disabled(isPreparingShare || (liveSharing && !draft.canCreateInvitation))
            if liveSharing && !draft.canCreateInvitation {
                Text("This place needs to finish syncing before you can share")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
            }

        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
        .background(brand.background)
    }

    @MainActor
    private func createInvitation() async {
        guard !isPreparingShare, let prepareShare, canShare(draft.place) else { return }
        let sharedDraft = draft
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let content = try await prepareShare(sharedDraft)
            guard canShare(sharedDraft.place), draft == sharedDraft else { return }
            shareContent = content
            showsMessages = true
        } catch {
            shareFailed = true
        }
    }
}

/// The single invitation preview contract used by the composer, opened invite,
/// and Messages rehearsal. The recipient-facing card adds only the View affordance.
struct CGInvitationLinkPreview: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let draft: CommonGroundInvitationDraft
    var showsViewButton: Bool
    var sharePhoto: UIImage? = nil
    var rendersShareArtwork = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let sharePhoto {
                        Image(uiImage: sharePhoto).resizable().scaledToFill()
                    } else if rendersShareArtwork {
                        brand.raisedBackground.overlay {
                            Image(systemName: draft.place.systemImage)
                                .font(.system(size: 42, weight: .ultraLight))
                                .foregroundStyle(brand.accentText)
                        }
                    } else if let reference = draft.place.photoReference {
                        CommonGroundLivePlaceArtwork(reference: reference, systemImage: draft.place.systemImage, providerOnly: true)
                    } else {
                        CommonGroundPlaceArtwork(place: draft.place)
                    }
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 144 : PlacePlanArtworkLayout.photoHeight)
                    .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.place.name)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("common-ground.invitation.place")
                    Text(draft.linkLocation)
                        .font(.system(.subheadline, weight: .medium))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .padding(18)
            }

            PlacePlanInvitationCardFooter(title: draft.linkTitle, date: draft.linkSubtitle, showsViewButton: showsViewButton)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(brand.border.opacity(0.3), lineWidth: 0.75)
        }
    }

}

private struct CGInvitationEnvelopeArtwork: View {
    @Environment(\.astirBrandMode) private var brand
    let symbol: String
    let recipientName: String
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(WanderTheme.terracottaTint.color)
                Path { path in
                    let w = geometry.size.width, h = geometry.size.height
                    path.move(to: .zero)
                    path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.58), control: CGPoint(x: w * 0.25, y: h * 0.4))
                    path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.75, y: h * 0.4))
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.5))
                    path.move(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.5))
                }.stroke(brand.accentText.opacity(0.22), lineWidth: 1.2)
                VStack(spacing: 3) {
                    Text("\(recipientName.uppercased()),").font(AstirTypography.metadata).tracking(2)
                    Text("this one’s for us").font(AstirTypography.sectionTitle)
                }
                .foregroundStyle(brand.primaryText)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.2)
                Image(systemName: symbol).font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(brand.accentForeground).frame(width: 62, height: 62)
                    .background(brand.accent, in: Circle())
                    .overlay(Circle().stroke(brand.accentText.opacity(0.25), lineWidth: 4).padding(5))
                    .rotationEffect(.degrees(-10))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.58)
                Text("A LITTLE HELP FROM ASTIR").font(AstirTypography.metadata).tracking(1.4)
                    .foregroundStyle(brand.secondaryText)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.87)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(brand.border.opacity(0.4), lineWidth: 0.8))
            .rotationEffect(.degrees(-3)).padding(8)
        }.accessibilityHidden(true)
    }
}

private struct CGInvitationDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    @State var date: Date
    let confirm: (Date?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Put a little something on the calendar")
                        .font(AstirTypography.sheetTitle)
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("common-ground.invitation.date-picker")
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact).font(AstirTypography.control)
                        .frame(minHeight: 44)
                    Text("Just a proposal — work out the details in your chat")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }.padding(20)
            }
            .navigationTitle("Pick a time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("No date yet") { confirm(nil); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    confirm(date)
                    dismiss()
                } label: {
                    Text("Use this time").font(AstirTypography.control)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(brand.accentForeground)
                        .background(brand.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).padding(20)
                .accessibilityIdentifier("common-ground.invitation.use-date")
            }
            .astirScreen()
        }
        .tint(brand.accentText).astirAdaptiveBrandMode()
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

#Preview("Invitation · composer") {
    NavigationStack { CommonGroundInvitationMockup(draft: .preview) }
}
#Preview("Invitation · opened") {
    NavigationStack { CommonGroundInvitationMockup(draft: .preview, opensEnvelope: true, initiallyOpened: true) }
}
