#if DEBUG
import SwiftUI

struct CommonGroundInvitationMockup: View {
    let placeName: String
    let category: String
    let systemImage: String
    var opensEnvelope = false

    var body: some View {
        CGInvitationScreen(
            placeName: placeName,
            category: category,
            systemImage: systemImage,
            opensEnvelope: opensEnvelope
        )
        .astirAdaptiveBrandMode()
    }
}

private struct CGInvitationScreen: View {
    let placeName: String
    let category: String
    let systemImage: String
    let opensEnvelope: Bool

    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var note = ""
    @State private var suggestedTime = ""
    @State private var envelopeOpened = false
    @State private var showsSharingPreview = false
    @AccessibilityFocusState private var postcardFocused: Bool

    private var invitationCopy: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Astir picked this for us. Want to go?"
            : note
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                if opensEnvelope {
                    recipientContent
                } else {
                    composerContent
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing6)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(opensEnvelope ? "For you two" : "Your invitation")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !opensEnvelope || envelopeOpened {
                bottomAction
            }
        }
        .sheet(isPresented: $showsSharingPreview) {
            CGInvitationSharingPreview(
                placeName: placeName,
                invitationCopy: invitationCopy,
                suggestedTime: suggestedTime,
                isReply: opensEnvelope
            )
        }
        .astirScreen()
        .astirAdaptiveBrandMode()
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("A little nudge from Astir.")
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text("A place picked for your two maps. Make the invitation yours.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            postcard

            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                invitationField(title: "A personal note", detail: "Optional") {
                    TextField("Add your own message…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityLabel("Personal note, optional")
                }
                invitationField(title: "When", detail: "Optional") {
                    TextField("Maybe Saturday afternoon?", text: $suggestedTime)
                        .accessibilityLabel("Suggested time, optional")
                }
            }
        }
    }

    private var recipientContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
            HStack(spacing: WanderTheme.spacing3) {
                CGInvitationInitials(initials: "R", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ryan found something for you two.")
                        .font(AstirTypography.cardTitle)
                    Text("A suggestion from your two maps.")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)

            if envelopeOpened {
                postcard
                    .accessibilityFocused($postcardFocused)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 12)))

                Text("Something familiar or somewhere new. The next move is yours.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(action: revealPostcard) {
                    VStack(spacing: WanderTheme.spacing4) {
                        CGInvitationEnvelopeArtwork()
                            .aspectRatio(1.35, contentMode: .fit)
                            .accessibilityHidden(true)
                        Text("A little common ground.")
                            .font(AstirTypography.sheetTitle)
                            .foregroundStyle(brandMode.primaryText)
                        Label("Open your invitation", systemImage: "envelope.open")
                            .font(AstirTypography.control)
                            .foregroundStyle(brandMode.accentText)
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Ryan’s invitation")
                .accessibilityHint("Reveals the place suggested for you two")
                .padding(.vertical, WanderTheme.spacing6)
            }
        }
    }

    private var postcard: some View {
        CGInvitationPostcard(
            placeName: placeName,
            category: category,
            systemImage: systemImage,
            message: invitationCopy,
            suggestedTime: suggestedTime
        )
        .accessibilityElement(children: .combine)
    }

    private func invitationField<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AstirTypography.control)
                Text(detail)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }
            content()
                .font(AstirTypography.body)
                .tint(brandMode.accentText)
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(brandMode.recessedBackground, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bottomAction: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Button {
                showsSharingPreview = true
            } label: {
                Label(
                    opensEnvelope ? "Reply in Messages" : "Share your invitation",
                    systemImage: opensEnvelope ? "message" : "square.and.arrow.up"
                )
                .font(AstirTypography.control)
                .multilineTextAlignment(.center)
                .padding(.vertical, WanderTheme.spacing3)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(brandMode.accentForeground)
                .background(brandMode.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a sharing preview. This mock does not send messages.")

            Text("Sharing preview · nothing is sent")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing2)
        .background(brandMode.background)
        .overlay(alignment: .top) {
            Rectangle().fill(brandMode.border.opacity(0.35)).frame(height: 0.5)
        }
    }

    private func revealPostcard() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            envelopeOpened = true
        }
        Task { @MainActor in
            await Task.yield()
            postcardFocused = true
        }
    }
}

private struct CGInvitationPostcard: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let placeName: String
    let category: String
    let systemImage: String
    let message: String
    let suggestedTime: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("Ryan & Joe")
                        .font(AstirTypography.sectionTitle)
                    Text("A PLACE FOR YOU TWO")
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkle")
                    .font(.system(.title2))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 46, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(brandMode.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .rotationEffect(.degrees(5))
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: WanderTheme.spacing4) {
                Image(systemName: systemImage)
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 66, height: 78)
                    .background(brandMode.accentWash, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(placeName)
                        .font(AstirTypography.sheetTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(category)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(brandMode.border.opacity(0.45))
                .frame(height: 0.5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                Text(message)
                    .font(AstirTypography.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !suggestedTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(suggestedTime, systemImage: "calendar")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                signatureRow
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    signature
                    attribution
                }
            }
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? WanderTheme.spacing4 : WanderTheme.spacing6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(brandMode.border.opacity(0.7), lineWidth: 0.75)
        }
    }

    private var signatureRow: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing4) {
            signature
            Spacer(minLength: WanderTheme.spacing2)
            attribution
        }
    }

    private var signature: some View {
        HStack(spacing: WanderTheme.spacing2) {
            CGInvitationInitials(initials: "R", size: 30)
            Text("From Ryan")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
        }
        .fixedSize()
    }

    private var attribution: some View {
        Text("Picked by Astir")
            .font(AstirTypography.caption)
            .foregroundStyle(brandMode.secondaryText)
            .fixedSize()
    }
}

private struct CGInvitationInitials: View {
    @Environment(\.astirBrandMode) private var brandMode
    let initials: String
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.accentText)
            .frame(width: size, height: size)
            .background(brandMode.accentWash, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct CGInvitationEnvelopeArtwork: View {
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(brandMode.raisedBackground)
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.58))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width * 0.38, y: height * 0.46))
                    path.move(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: width * 0.62, y: height * 0.46))
                }
                .stroke(brandMode.border.opacity(0.55), lineWidth: 0.75)

                Image(systemName: "sparkle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(brandMode.accentForeground)
                    .frame(width: 58, height: 58)
                    .background(brandMode.accent, in: Circle())
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.56)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(brandMode.border.opacity(0.7), lineWidth: 0.75)
            }
        }
    }
}

private struct CGInvitationSharingPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    let placeName: String
    let invitationCopy: String
    let suggestedTime: String
    let isReply: Bool
    @State private var selectedChannel: String?
    @State private var reply = ""

    private var channel: String? { selectedChannel ?? (isReply ? "Messages" : nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    if let channel {
                        channelPreview(channel)
                    } else {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("An invitation, your way.")
                                .font(AstirTypography.sheetTitle)
                            Text("Choose where to share your postcard.")
                                .font(AstirTypography.bodySmall)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        VStack(spacing: 0) {
                            channelButton("Messages", systemImage: "message.fill")
                            Divider().overlay(brandMode.border.opacity(0.4))
                            channelButton("More sharing", systemImage: "square.and.arrow.up")
                        }
                        .padding(.horizontal, WanderTheme.spacing4)
                        .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: 16))
                    }

                    Label("Preview only. Nothing has been sent.", systemImage: "eye")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WanderTheme.spacing4)
            }
            .navigationTitle(channel ?? "Sharing preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(brandMode.accentText)
                }
                if selectedChannel != nil && !isReply {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { selectedChannel = nil }
                            .tint(brandMode.accentText)
                    }
                }
            }
            .astirScreen()
        }
        .astirAdaptiveBrandMode()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func channelButton(_ title: String, systemImage: String) -> some View {
        Button {
            selectedChannel = title
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .foregroundStyle(brandMode.accentText)
                    .frame(width: 30)
                Text(title).font(AstirTypography.control)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(brandMode.secondaryText)
            }
            .foregroundStyle(brandMode.primaryText)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows a local preview only")
    }

    @ViewBuilder
    private func channelPreview(_ channel: String) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Text(isReply ? "To Ryan" : "To Joe")
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.secondaryText)

            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                Text(placeName)
                    .font(AstirTypography.sectionTitle)
                Text(invitationCopy)
                    .font(AstirTypography.body)
                if !suggestedTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(suggestedTime, systemImage: "calendar")
                        .font(AstirTypography.bodySmall)
                }
                Text("An Astir postcard")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WanderTheme.spacing4)
            .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: 18))

            if isReply {
                TextField("Write a reply…", text: $reply, axis: .vertical)
                    .font(AstirTypography.body)
                    .lineLimit(3...6)
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .background(brandMode.recessedBackground, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Reply preview, not sent")
            } else if channel == "More sharing" {
                Text("Your postcard can travel with its place link.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Label("AirDrop", systemImage: "airplayaudio")
                    Label("Mail", systemImage: "envelope")
                    Label("Copy link", systemImage: "link")
                }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.secondaryText)
                .accessibilityLabel("Example sharing destinations: AirDrop, Mail, and Copy link")
            }
        }
    }
}

#Preview("Invitation · Light") {
    NavigationStack {
        CommonGroundInvitationMockup(
            placeName: "Courage Bagels",
            category: "Bagels · Virgil Village",
            systemImage: "cup.and.saucer"
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Invitation · Envelope") {
    NavigationStack {
        CommonGroundInvitationMockup(
            placeName: "Courage Bagels",
            category: "Bagels · Virgil Village",
            systemImage: "cup.and.saucer",
            opensEnvelope: true
        )
    }
    .preferredColorScheme(.dark)
}
#endif
