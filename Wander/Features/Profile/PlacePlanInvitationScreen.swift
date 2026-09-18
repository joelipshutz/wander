import SwiftUI

/// Link recipients see the shared snapshot. There is no editable draft here.
struct PlacePlanInvitationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    let source: PlacePlanInvitationSource
    let repository: (any PlacePlanInvitationRepository)?
    var onOpened: (() -> Void)? = nil
    @State private var invitation: PlacePlanInvitation?
    @State private var isLoading = true
    @State private var failed = false
    @State private var attempt = 0

    init(token: String, repository: (any PlacePlanInvitationRepository)?) {
        self.source = .link(token)
        self.repository = repository
    }

    init(invitationID: UUID, repository: (any PlacePlanInvitationRepository)?, onOpened: @escaping () -> Void) {
        self.source = .notifications(invitationID)
        self.repository = repository
        self.onOpened = onOpened
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if isLoading {
                        ProgressView("Opening invitation")
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let invitation {
                        PlacePlanInvitationContent(invitation: invitation)
                    } else {
                        ContentUnavailableView {
                            Label(failed ? "Couldn’t open this invitation" : "This invitation is unavailable", systemImage: "envelope")
                        } description: {
                            Text(failed ? "Check your connection and try again" : "Ask your friend for a fresh invitation")
                        } actions: {
                            if failed { Button("Try again") { attempt += 1 } }
                        }
                        .accessibilityIdentifier("place-plan.unavailable")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("place-plan.close")
                }
            }
            .astirScreen()
        }
        .tint(brand.accentText)
        .astirAdaptiveBrandMode()
        .task(id: source) { await load() }
        .task(id: attempt) { if attempt > 0 { await load() } }
    }

    @MainActor private func load() async {
        isLoading = true
        invitation = nil
        failed = false
        do {
            guard let repository else { throw WanderRemoteError.notConfigured }
            let result: PlacePlanInvitation?
            switch source {
            case .link(let token): result = try await repository.invitation(token: token)
            case .notifications(let id): result = try await repository.receivedInvitation(id: id)
            }
            guard !Task.isCancelled else { return }
            invitation = result
            if result != nil { onOpened?() }
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        isLoading = false
    }
}

struct PlacePlanInvitationContent: View {
    @Environment(\.astirBrandMode) private var brand
    let invitation: PlacePlanInvitation
    private var plan: PlacePlanInvitationPayload { invitation.payload }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                AsyncImage(url: plan.senderAvatarURL?.scheme == "https" ? plan.senderAvatarURL : nil) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(String(plan.senderName.prefix(1)))
                            .font(AstirTypography.control)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(brand.accentWash)
                    }
                }
                .frame(width: 42, height: 42).clipShape(Circle()).accessibilityHidden(true)
                Text("\(plan.senderName)’s got a plan")
                    .font(AstirTypography.sheetTitle)
            }
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    AsyncImage(url: invitation.artworkURL) { phase in
                        if let image = phase.image {
                            // Crop off the rendered footer, including its View label.
                            image.resizable().scaledToFit()
                                .frame(width: geometry.size.width, alignment: .top)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            brand.raisedBackground.overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(plan.placeName).font(AstirTypography.sheetTitle)
                                    Text(plan.location).font(AstirTypography.bodySmall)
                                }.padding()
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .clipped()
                }
                .aspectRatio(PlacePlanArtworkLayout.width / PlacePlanArtworkLayout.photoHeight, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(plan.placeName), \(plan.location)")
                PlacePlanInvitationCardFooter(title: plan.title, date: plan.dateLabel, showsViewButton: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(brand.border.opacity(0.3), lineWidth: 0.75) }
            Text(plan.message).font(AstirTypography.sheetTitle)
                .accessibilityIdentifier("place-plan.message")
            Text(plan.connection).font(AstirTypography.label).foregroundStyle(brand.accentText)
                .accessibilityIdentifier("place-plan.connection")
        }
        .foregroundStyle(brand.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlacePlanInvitationCardFooter: View {
    @Environment(\.astirBrandMode) private var brand
    let title: String
    let date: String
    let showsViewButton: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("InvitationAppIcon").resizable().scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .accessibilityLabel("ASTIR")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(brand.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("common-ground.invitation.link-title")
                Text(date).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("common-ground.invitation.when-value")
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if showsViewButton {
                Text("View").font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(brand.accentForeground)
                    .padding(.horizontal, 19).frame(minHeight: 44)
                    .background(brand.accent, in: Capsule())
                    .accessibilityIdentifier("common-ground.invitation.view")
            }
        }
        .padding(14).background(brand.raisedBackground)
    }
}
