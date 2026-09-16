#if DEBUG
import SwiftUI

/// Shared composer for the local rehearsal and the signed-in app’s place-link sharing.
struct CommonGroundInvitationMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: CommonGroundInvitationDraft
    @State private var envelopeOpened: Bool
    @State private var showsMessages = false
    @State private var showsLivePreview = false
    @State private var showsCalendar = false
    @AccessibilityFocusState private var postcardFocused: Bool
    @FocusState private var noteFocused: Bool
    let opensEnvelope: Bool
    let liveSharing: Bool
    private let sourcePlace: CommonGroundMockPlace
    private let canShare: (CommonGroundMockPlace) -> Bool

    init(draft: CommonGroundInvitationDraft, opensEnvelope: Bool = false, initiallyOpened: Bool = false, liveSharing: Bool = false, canShare: @escaping (CommonGroundMockPlace) -> Bool = { _ in true }) {
        _draft = State(initialValue: draft)
        _envelopeOpened = State(initialValue: initiallyOpened)
        self.opensEnvelope = opensEnvelope
        self.liveSharing = liveSharing
        sourcePlace = draft.place
        self.canShare = canShare
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if opensEnvelope {
                    recipient
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASTIR’s taking the wheel")
                            .font(AstirTypography.sheetTitle).accessibilityAddTraits(.isHeader)
                        Text("You bring the company")
                            .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                    }
                    postcard
                    composerFields
                }
            }
            .padding(20).padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if liveSharing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Preview", systemImage: "eye") { showsLivePreview = true }
                        .accessibilityLabel("Preview invitation in Messages")
                }
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
            if liveSharing, let content = draft.shareContent {
                WanderShareSheet(content: content)
            } else {
                CommonGroundMessagesMockup(draft: draft, isReply: opensEnvelope)
            }
        }
        .sheet(isPresented: $showsLivePreview) {
            CommonGroundMessagesMockup(draft: draft)
        }
        .onChange(of: sourcePlace) { _, place in
            if liveSharing {
                showsMessages = false
                showsLivePreview = false
            }
            draft = CommonGroundInvitationDraft(place: place, note: draft.note, suggestedDate: draft.suggestedDate)
        }
        .astirScreen()
        .astirAdaptiveBrandMode()
    }

    private var postcard: some View {
        CGInvitationPostcard(draft: draft)
            .accessibilityElement(children: .contain)
            .accessibilityFocused($postcardFocused)
    }

    private var composerFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Make it yours").font(AstirTypography.control)
                    Text("Optional").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                TextField(draft.message, text: $draft.note, axis: .vertical)
                    .focused($noteFocused)
                    .font(AstirTypography.body).lineLimit(2...5)
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
                if draft.suggestedDate != nil {
                    Button("Keep the time open") { draft.suggestedDate = nil }
                        .font(AstirTypography.bodySmall).frame(minHeight: 44)
                        .accessibilityIdentifier("common-ground.invitation.clear-date")
                }
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
                postcard
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 16)))
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
                showsMessages = true
            } label: {
                Label(liveSharing ? "Share invitation" : opensEnvelope ? "Reply in Messages" : "Preview in Messages", systemImage: liveSharing ? "square.and.arrow.up" : "message.fill")
                    .font(AstirTypography.control).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(brand.accentForeground)
                    .background(brand.accent, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("common-ground.invitation.messages")
            .disabled(liveSharing && draft.shareContent == nil)
            Text(liveSharing
                 ? (draft.shareContent == nil ? "This place needs to finish syncing before you can share" : "Choose Messages to send your plan and place link")
                 : "Design preview · nothing is sent")
                .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(brand.background)
    }
}

/// Shared artwork, also usable inside the Messages rich-link mock.
struct CGInvitationPostcard: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let draft: CommonGroundInvitationDraft
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(draft.place.viewer.shortName) + \(draft.place.partner.shortName)".uppercased()).font(AstirTypography.metadata).tracking(2)
                        Text("Good company\nGood excuse")
                            .font(AstirTypography.sectionTitle)
                    }
                    Spacer(minLength: 8)
                    postageStamp
                }
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.place.name).font(compact ? AstirTypography.sheetTitle : AstirTypography.screenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("common-ground.invitation.place")
                        Text("\(draft.place.category) · \(draft.place.area)")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize && !compact {
                        CommonGroundPlaceArtwork(place: draft.place)
                            .frame(width: 78, height: 96)
                            .padding(5).padding(.bottom, 12)
                            .background(brand.raisedBackground)
                            .rotationEffect(.degrees(6))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(compact ? 18 : 22)
            .background(WanderTheme.terracottaTint.color)

            VStack(alignment: .leading, spacing: 12) {
                Text(draft.message)
                    .font(compact ? AstirTypography.body : AstirTypography.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("common-ground.invitation.copy")
                if let when = draft.whenText {
                    Label {
                        Text(when).accessibilityIdentifier("common-ground.invitation.when-value")
                    } icon: { Image(systemName: "calendar") }
                    .font(AstirTypography.control).foregroundStyle(brand.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                CGInvitationPerforation().stroke(brand.border, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(height: 1).accessibilityHidden(true)
                footerLayout {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(draft.reasonTitle)
                                .accessibilityIdentifier("common-ground.invitation.reason-title")
                        } icon: { Image(systemName: draft.reasonSymbol) }
                        .font(AstirTypography.label).foregroundStyle(brand.accentText)
                        if let evidence = draft.postcardReasonDetail {
                            Text(evidence)
                                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                    Text("ASTIR").font(.system(.title3, design: .serif).italic())
                }
            }
            .padding(.horizontal, compact ? 18 : 22)
            .padding(.vertical, 16)
            .background(brand.raisedBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(brand.border.opacity(0.3), lineWidth: 0.75)
        }
    }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var postageStamp: some View {
        VStack(spacing: 3) {
            Image(systemName: draft.reasonSymbol).font(.system(size: 24, weight: .semibold))
            Text("LET’S GO").font(AstirTypography.metadata).tracking(1)
        }
        .foregroundStyle(brand.accentText).frame(width: 66, height: 76)
        .background(brand.raisedBackground.opacity(0.85))
        .overlay {
            RoundedRectangle(cornerRadius: 3).stroke(brand.accentText.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        }
        .rotationEffect(.degrees(8)).accessibilityHidden(true)
    }
}

private struct CGInvitationPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
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
    let confirm: (Date) -> Void

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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
#endif
