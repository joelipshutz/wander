import MessageUI
import Photos
import SwiftUI
import UIKit
#if canImport(TikTokOpenShareSDK)
import TikTokOpenShareSDK
#endif
#if canImport(TikTokOpenSDKCore)
import TikTokOpenSDKCore
#endif

enum ActivityShareDestination: String, CaseIterable, Identifiable {
    case messages
    case copyLink
    case instagramStory
    case instagramPost
    case tikTok
    case snapchat
    case save
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: "Messages"
        case .copyLink: "Copy Link"
        case .instagramStory: "Instagram Story"
        case .instagramPost: "Instagram Post"
        case .tikTok: "TikTok"
        case .snapchat: "Snapchat"
        case .save: "Save"
        case .more: "More"
        }
    }

    var route: ActivityShareDestinationRoute {
        switch self {
        case .messages: .messages
        case .copyLink: .copyLink
        case .instagramStory: .instagramStory
        case .instagramPost: .instagramPost
        case .tikTok: .tikTok
        case .snapchat: .snapchat
        case .save: .savePhoto
        case .more: .systemShare
        }
    }
}

enum ActivityShareDestinationRoute: Equatable {
    case messages
    case copyLink
    case instagramStory
    case instagramPost
    case tikTok
    case snapchat
    case savePhoto
    case systemShare
}

enum ActivitySharePhotoPermissionAction: Equatable {
    case requestAuthorization
    case save
    case showSettings
}

enum ActivitySharePhotoPermissionPolicy {
    static func action(for status: PHAuthorizationStatus) -> ActivitySharePhotoPermissionAction {
        switch status {
        case .notDetermined:
            .requestAuthorization
        case .authorized, .limited:
            .save
        case .denied, .restricted:
            .showSettings
        @unknown default:
            .showSettings
        }
    }
}

enum ActivityShareInstagramPostTapAction: Equatable {
    case showPhotoAccessGuidance
    case openDirectEditor
}

enum ActivityShareInstagramPhotoAccessGuidance {
    static let acknowledgementKey = "activityShare.instagramPostFullPhotoAccessAcknowledged"
    static let title = "Instagram needs Full Photo Access"
    static let settingsPath = "Settings → Apps → Instagram → Photos → Full Access"

    static func action(hasAcknowledgedFullAccess: Bool) -> ActivityShareInstagramPostTapAction {
        hasAcknowledgedFullAccess ? .openDirectEditor : .showPhotoAccessGuidance
    }
}

enum ActivityShareTikTokOutcome: Equatable, Sendable {
    case shared
    case savedAsDraft
    case cancelled
    case failed(message: String)
}

enum ActivityShareTikTokOutcomePolicy {
    static func outcome(errorCode: Int, shareState: Int) -> ActivityShareTikTokOutcome {
        if errorCode == -2 || shareState == 20_013 {
            return .cancelled
        }
        if errorCode == 0, shareState == 20_000 {
            return .shared
        }
        if shareState == 20_015 {
            return .savedAsDraft
        }

        let message = switch shareState {
        case 20_003:
            "TikTok did not grant this account permission to share."
        case 20_004, 22_001:
            "Sign in to the TikTok account enabled for this rec.me sandbox, then try again."
        case 20_005:
            "TikTok needs Photos access to import this share ticket."
        case 20_006:
            "TikTok could not connect. Check your connection and try again."
        case 20_008:
            "TikTok rejected the share image resolution."
        case 20_019:
            "TikTok is not installed on this iPhone."
        case 22_000:
            "Update TikTok, then try sharing again."
        default:
            "TikTok could not finish this share. Try again or use More to share another way."
        }
        return .failed(message: message)
    }
}

enum ActivityShareMessageCompletionAction: Equatable {
    case dismiss
    case openSystemShare
}

enum ActivityShareMessagePresentationPolicy {
    static func shouldBeginPresentation(isPending: Bool) -> Bool {
        !isPending
    }

    static func completionAction(
        for result: MessageComposeResult
    ) -> ActivityShareMessageCompletionAction {
        result == .failed ? .openSystemShare : .dismiss
    }
}

struct ActivitySharePreviewPresentation: Identifiable, Equatable {
    let id: UUID
    let context: ActivityEngagementContext
    let content: WanderShareContent

    init?(id: UUID = UUID(), context: ActivityEngagementContext) {
        guard let content = WanderShareContent.activity(
            activityID: context.activityID,
            placeName: context.placeName,
            message: context.shareMessage
        ) else { return nil }

        self.id = id
        self.context = context
        self.content = content
    }
}

struct ActivitySharePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.astirBrandMode) private var brandMode

    @AppStorage(ActivityShareInstagramPhotoAccessGuidance.acknowledgementKey)
    private var hasAcknowledgedInstagramFullPhotoAccess = false

    let context: ActivityEngagementContext
    let content: WanderShareContent
    let initiallyVisibleDestination: ActivityShareDestination?
    let analytics: AnalyticsClient

    init(
        context: ActivityEngagementContext,
        content: WanderShareContent,
        initiallyVisibleDestination: ActivityShareDestination? = nil,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.context = context
        self.content = content
        self.initiallyVisibleDestination = initiallyVisibleDestination
        self.analytics = analytics
    }

    @State private var renderedImage: UIImage?
    @State private var renderedImageURL: URL?
    @State private var resolvedAvatarImage: UIImage?
    @State private var isPreparingArtwork = false
    @State private var systemSharePresentation: ActivityShareSystemPresentation?
    @State private var messagePresentation: ActivityShareMessagePresentation?
    @State private var instagramPostPresentation: ActivityShareInstagramPostPresentation?
    @State private var instagramPhotoAccessGuidance: ActivityShareInstagramPhotoAccessGuidancePresentation?
    @State private var pendingInstagramPostShare: ActivityShareInstagramPostShareMethod?
    @State private var isMessagePresentationPending = false
    @State private var shouldOpenSystemShareAfterMessagesDismiss = false
    @State private var shouldOpenSystemShareAfterInstagramDismiss = false
    @State private var isShowingPhotoSettingsAlert = false
    @State private var isShowingExportError = false
    @State private var tikTokFailureMessage: String?
    @State private var confirmationMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            ActivityShareArtwork(
                context: context,
                avatarImage: resolvedAvatarImage
            )
                .ignoresSafeArea()

            topBar

            if let confirmationMessage {
                confirmationToast(confirmationMessage)
                    .padding(.top, 62)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActivityShareDestinationTray(
                isPreparing: isPreparingArtwork || isMessagePresentationPending,
                initiallyVisibleDestination: initiallyVisibleDestination,
                instagramPhotoAccessInfoAction: hasAcknowledgedInstagramFullPhotoAccess
                    ? { instagramPhotoAccessGuidance = .reminder }
                    : nil,
                action: handleDestination
            )
            .background(alignment: .bottom) {
                brandMode.raisedBackground
                    .frame(height: WanderTheme.spacing12)
                    .offset(y: WanderTheme.spacing12)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .sheet(item: $systemSharePresentation) { presentation in
            WanderShareSheet(content: presentation.content) { completed in
                trackShareCompleted(
                    destination: "system_share",
                    outcome: completed ? "shared" : "cancelled"
                )
            }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $messagePresentation, onDismiss: {
            messagePresentation = nil
            isMessagePresentationPending = false
            guard shouldOpenSystemShareAfterMessagesDismiss else { return }
            shouldOpenSystemShareAfterMessagesDismiss = false
            Task { await presentSystemShare() }
        }) { presentation in
            ActivityShareMessageComposer(
                body: presentation.content.messageBody,
                image: presentation.image
            ) { result in
                handleMessageCompletion(result)
            }
        }
        .sheet(item: $instagramPostPresentation, onDismiss: {
            guard shouldOpenSystemShareAfterInstagramDismiss else { return }
            shouldOpenSystemShareAfterInstagramDismiss = false
            Task { await presentSystemShare() }
        }) { presentation in
            ActivityShareInstagramPostComposer(fileURL: presentation.fileURL) { result in
                if result == .unavailable {
                    shouldOpenSystemShareAfterInstagramDismiss = true
                }
                instagramPostPresentation = nil
            }
        }
        .sheet(item: $instagramPhotoAccessGuidance, onDismiss: {
            resumePendingInstagramPostShare()
        }) { presentation in
            ActivityShareInstagramPhotoAccessGuidanceSheet(
                primaryTitle: presentation.primaryTitle,
                primaryAction: {
                    hasAcknowledgedInstagramFullPhotoAccess = true
                    pendingInstagramPostShare = .directEditor
                },
                compatibleAction: {
                    pendingInstagramPostShare = .compatibleDocumentHandoff
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(brandMode.background)
        }
        .alert("Allow rec.me to access your photos", isPresented: $isShowingPhotoSettingsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
        } message: {
            Text("Please go to Settings > rec.me and turn on Photos access.")
        }
        .alert("Couldn't make the share image", isPresented: $isShowingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try sharing this ticket again.")
        }
        .alert(
            "Couldn't share to TikTok",
            isPresented: Binding(
                get: { tikTokFailureMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        tikTokFailureMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tikTokFailureMessage ?? "TikTok could not finish this share.")
        }
        .task(id: context.activityID) {
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.activityShareOpened,
                    properties: ["ticket_kind": ticketKindAnalyticsValue]
                )
            )
            _ = await prepareArtworkIfNeeded()
        }
        .onDisappear {
            guard let renderedImageURL else { return }
            Task {
                await WanderShareAttachmentStore.removePreparedPNG(at: renderedImageURL)
            }
        }
        .foregroundStyle(brandMode.primaryText)
    }

    private var topBar: some View {
        HStack {
            ActivityShareChromeButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Close share preview",
                action: dismiss.callAsFunction
            )

            Spacer()

            if isPreparingArtwork {
                ProgressView()
                    .tint(brandMode.primaryText)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .accessibilityLabel("Preparing share image")
            } else {
                ActivityShareChromeButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Open more sharing options"
                ) {
                    handleDestination(.more)
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
    }

    private func confirmationToast(_ message: String) -> some View {
        Text(message)
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.primaryText)
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(brandMode.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }

    private func handleDestination(_ destination: ActivityShareDestination) {
        switch destination.route {
        case .copyLink:
            UIPasteboard.general.url = content.item
            trackShareCompleted(destination: "copy_link", outcome: "copied")
            showConfirmation("link copied")
        case .messages:
            startMessagesPresentation()
        case .instagramStory:
            Task { await presentInstagramStory() }
        case .instagramPost:
            switch ActivityShareInstagramPhotoAccessGuidance.action(
                hasAcknowledgedFullAccess: hasAcknowledgedInstagramFullPhotoAccess
            ) {
            case .showPhotoAccessGuidance:
                instagramPhotoAccessGuidance = .requiredBeforeFirstDirectShare
            case .openDirectEditor:
                Task { await presentInstagramPost() }
            }
        case .tikTok:
            Task { await presentTikTok() }
        case .snapchat:
            Task { await presentSnapchat() }
        case .systemShare:
            Task { await presentSystemShare() }
        case .savePhoto:
            Task { await saveArtworkToPhotos() }
        }
    }

    @MainActor
    private func startMessagesPresentation() {
        guard ActivityShareMessagePresentationPolicy.shouldBeginPresentation(
            isPending: isMessagePresentationPending
        ) else { return }

        isMessagePresentationPending = true
        Task { await presentMessages() }
    }

    @MainActor
    private func prepareArtworkIfNeeded() async -> Bool {
        if renderedImage != nil, renderedImageURL != nil {
            return true
        }
        guard !isPreparingArtwork else { return false }

        isPreparingArtwork = true
        defer { isPreparingArtwork = false }

        let avatarImage = await ActivityShareArtworkRenderer.resolveAvatarImage(
            avatarURL: context.actor.avatarURL
        )
        resolvedAvatarImage = avatarImage

        guard let image = ActivityShareArtworkRenderer.render(
            context: context,
            avatarImage: avatarImage,
            brandMode: brandMode
        ),
              let pngData = image.pngData(),
              let fileURL = await WanderShareAttachmentStore.preparePNG(pngData)
        else {
            isShowingExportError = true
            return false
        }

        renderedImage = image
        renderedImageURL = fileURL
        return true
    }

    @MainActor
    private func preparedShareContent() async -> WanderShareContent? {
        guard await prepareArtworkIfNeeded(), let renderedImageURL else { return nil }
        return content.attachingPNG(at: renderedImageURL)
    }

    @MainActor
    private func presentMessages() async {
        guard let shareContent = await preparedShareContent(), let renderedImage else {
            isMessagePresentationPending = false
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            isMessagePresentationPending = false
            systemSharePresentation = ActivityShareSystemPresentation(content: shareContent)
            return
        }
        messagePresentation = ActivityShareMessagePresentation(
            content: shareContent,
            image: renderedImage
        )
    }

    @MainActor
    private func handleMessageCompletion(_ result: MessageComposeResult) {
        switch result {
        case .sent:
            trackShareCompleted(destination: "messages", outcome: "sent")
        case .cancelled:
            trackShareCompleted(destination: "messages", outcome: "cancelled")
        case .failed:
            trackShareCompleted(destination: "messages", outcome: "failed")
        @unknown default:
            trackShareCompleted(destination: "messages", outcome: "failed")
        }
        let action = ActivityShareMessagePresentationPolicy.completionAction(for: result)
        shouldOpenSystemShareAfterMessagesDismiss = action == .openSystemShare
        messagePresentation = nil
    }

    @MainActor
    private func resumePendingInstagramPostShare() {
        guard let pendingInstagramPostShare else { return }
        self.pendingInstagramPostShare = nil

        switch pendingInstagramPostShare {
        case .directEditor:
            Task { await presentInstagramPost() }
        case .compatibleDocumentHandoff:
            Task { await presentCompatibleInstagramPost() }
        }
    }

    @MainActor
    private func presentSystemShare() async {
        guard let shareContent = await preparedShareContent() else { return }
        systemSharePresentation = ActivityShareSystemPresentation(content: shareContent)
    }

    @MainActor
    private func presentInstagramStory() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }
        guard await ActivityShareProviderLauncher.openInstagramStory(
            image: renderedImage,
            contentURL: content.item
        ) else {
            await presentSystemShare()
            return
        }
        trackShareCompleted(destination: "instagram_story", outcome: "handoff")
    }

    @MainActor
    private func presentInstagramPost() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }

        if ActivityShareProviderLauncher.canOpenInstagramPostLibrary,
           await ensurePhotoLibraryAccess() {
            do {
                let localIdentifier = try await ActivitySharePhotoWriter.save(renderedImage)
                if await ActivityShareProviderLauncher.openInstagramPost(
                    localIdentifier: localIdentifier
                ) {
                    trackShareCompleted(destination: "instagram_post", outcome: "handoff")
                    return
                }
            } catch {
                // The unsupported deep link is opportunistic. Keep Meta's documented
                // document-interaction route available if Photos or Instagram rejects it.
            }
        }

        await presentCompatibleInstagramPost()
    }

    @MainActor
    private func presentCompatibleInstagramPost() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }
        do {
            let fileURL = try ActivityShareInstagramFeedFile.prepare(renderedImage)
            instagramPostPresentation = ActivityShareInstagramPostPresentation(fileURL: fileURL)
            trackShareCompleted(destination: "instagram_post", outcome: "handoff")
        } catch {
            isShowingExportError = true
        }
    }

    @MainActor
    private func presentTikTok() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }
        guard ActivityShareProviderLauncher.canOpenTikTok else {
            await presentSystemShare()
            return
        }
        guard await ensurePhotoLibraryAccess() else { return }

        let localIdentifier: String
        do {
            localIdentifier = try await ActivitySharePhotoWriter.save(renderedImage)
        } catch {
            isShowingExportError = true
            return
        }
        guard await ActivityShareProviderLauncher.openTikTok(
            localIdentifier: localIdentifier,
            onCompletion: handleTikTokOutcome
        ) else {
            await presentSystemShare()
            return
        }
    }

    @MainActor
    private func handleTikTokOutcome(_ outcome: ActivityShareTikTokOutcome) {
        switch outcome {
        case .shared:
            trackShareCompleted(destination: "tiktok", outcome: "shared")
            showConfirmation("shared to TikTok")
        case .savedAsDraft:
            trackShareCompleted(destination: "tiktok", outcome: "draft")
            showConfirmation("saved as a TikTok draft")
        case .cancelled:
            trackShareCompleted(destination: "tiktok", outcome: "cancelled")
            showConfirmation("TikTok share canceled")
        case .failed(let message):
            trackShareCompleted(destination: "tiktok", outcome: "failed")
            tikTokFailureMessage = message
        }
    }

    @MainActor
    private func presentSnapchat() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }
        guard await ActivityShareProviderLauncher.openSnapchatPreview(
            image: renderedImage,
            contentURL: content.item
        ) else {
            await presentSystemShare()
            return
        }
        trackShareCompleted(destination: "snapchat", outcome: "handoff")
    }

    @MainActor
    private func saveArtworkToPhotos() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }

        guard await ensurePhotoLibraryAccess() else { return }

        do {
            _ = try await ActivitySharePhotoWriter.save(renderedImage)
            trackShareCompleted(destination: "save_photo", outcome: "saved")
            showConfirmation("saved to photos")
        } catch {
            isShowingExportError = true
        }
    }

    @MainActor
    private func ensurePhotoLibraryAccess() async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        switch ActivitySharePhotoPermissionPolicy.action(for: currentStatus) {
        case .requestAuthorization:
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .save:
            status = currentStatus
        case .showSettings:
            isShowingPhotoSettingsAlert = true
            return false
        }

        guard ActivitySharePhotoPermissionPolicy.action(for: status) == .save else {
            isShowingPhotoSettingsAlert = true
            return false
        }
        return true
    }

    @MainActor
    private func showConfirmation(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            confirmationMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard confirmationMessage == message else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                confirmationMessage = nil
            }
        }
    }

    private func trackShareCompleted(destination: String, outcome: String) {
        let properties = ["destination": destination, "outcome": outcome]
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.activityShareCompleted,
                properties: properties
            )
        )
        if ["copied", "draft", "handoff", "saved", "sent", "shared"].contains(outcome) {
            analytics.track(
                .engagement(
                    need: .expression,
                    action: .recommendationShared,
                    surface: "activity_share",
                    properties: properties
                )
            )
        }
    }

    private var ticketKindAnalyticsValue: String {
        switch context.ticketKind {
        case .checkIn: "check_in"
        case .wanna: "wanna"
        case .list: "list"
        case .saved: "saved"
        }
    }
}

private struct ActivityShareArtwork: View {
    @Environment(\.astirBrandMode) private var brandMode
    let context: ActivityEngagementContext
    let avatarImage: UIImage?

    var body: some View {
        ZStack {
            ActivityShareBackdrop()

            VStack(spacing: 0) {
                Spacer(minLength: WanderTheme.spacing12)

                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    ActivityShareTicket(
                        context: context,
                        avatarImage: avatarImage
                    )

                    Text("a place worth remembering")
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.accentForeground.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, WanderTheme.spacing6)

                Spacer(minLength: WanderTheme.spacing12)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Share preview. \(context.actor.displayName) \(context.actionTitle) \(context.placeName). \(context.placeDetail)"
        )
    }
}

private struct ActivityShareBackdrop: View {
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        brandMode.accent
    }
}

private struct ActivityShareTicket: View {
    @Environment(\.astirBrandMode) private var brandMode
    let context: ActivityEngagementContext
    let avatarImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.actor.displayName)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                        .lineLimit(1)

                    Text("@\(context.actor.handle)")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Text("ASTIR")
                    .font(AstirTypography.metadata)
                    .tracking(2.2)
                    .foregroundStyle(brandMode.accentText)
            }

            Rectangle()
                .fill(brandMode.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                (Text(context.actor.displayName).fontWeight(.regular)
                    + Text(" \(context.actionTitle) ")
                    + Text(context.placeName).fontWeight(.black))
                    .font(AstirTypography.sectionTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing1) {
                    Image(systemName: ticketIcon)
                        .font(AstirTypography.caption)

                    Text(context.placeDetail)
                        .font(AstirTypography.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(brandMode.secondaryText)

                if let note = context.note {
                    Text("“\(note)”")
                        .font(AstirTypography.bodySmall)
                        .italic()
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandMode.raisedBackground)
        .checkInTicketSurface(
            accent: ticketAccent,
            surface: brandMode.raisedBackground,
            notchEdges: .both,
            castsShadow: true,
            borderWidth: 1.5
        )
    }

    private var initials: String {
        context.actor.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var avatar: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.accentForeground)
            }
        }
        .frame(width: 54, height: 54)
        .background(brandMode.accent)
        .clipShape(Circle())
        .overlay(Circle().stroke(brandMode.raisedBackground, lineWidth: 2))
    }

    private var ticketIcon: String {
        switch context.ticketKind {
        case .checkIn: "checkmark.circle.fill"
        case .wanna: "bookmark.fill"
        case .list: PlaceListSymbol.systemImage
        case .saved: "mappin.circle.fill"
        }
    }

    private var ticketAccent: Color {
        switch context.ticketKind {
        case .checkIn: WanderTheme.pinSocial.color
        case .wanna: WanderTheme.stateWarning.color
        case .list: brandMode.accent
        case .saved: WanderTheme.categorySage.color
        }
    }
}

private struct ActivityShareDestinationTray: View {
    @Environment(\.astirBrandMode) private var brandMode
    let isPreparing: Bool
    let initiallyVisibleDestination: ActivityShareDestination?
    let instagramPhotoAccessInfoAction: (() -> Void)?
    let action: (ActivityShareDestination) -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Text("share this ticket")
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(brandMode.primaryText)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: WanderTheme.spacing2) {
                        ForEach(ActivityShareDestination.allCases) { destination in
                            ActivityShareDestinationButton(destination: destination) {
                                action(destination)
                            }
                            .id(destination)
                            .disabled(isPreparing && destination != .copyLink)
                            .opacity(isPreparing && destination != .copyLink ? 0.58 : 1)
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                }
                .frame(height: 104)
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let initiallyVisibleDestination else { return }
                    proxy.scrollTo(initiallyVisibleDestination, anchor: .center)
                }
            }

            if let instagramPhotoAccessInfoAction {
                Button(action: instagramPhotoAccessInfoAction) {
                    Label("Instagram Post needs Full Photo Access", systemImage: "info.circle.fill")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, WanderTheme.spacing4)
                .accessibilityHint("Shows the Instagram photo access instructions again.")
            }
        }
        .padding(.top, WanderTheme.spacing4)
        .padding(.bottom, WanderTheme.spacing2)
        .frame(maxWidth: .infinity)
        .background(brandMode.raisedBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: WanderTheme.radiusSheet,
                topTrailingRadius: WanderTheme.radiusSheet
            )
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: WanderTheme.radiusSheet,
                topTrailingRadius: WanderTheme.radiusSheet
            )
            .stroke(brandMode.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: -5)
    }
}

private struct ActivityShareDestinationButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let destination: ActivityShareDestination
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WanderTheme.spacing2) {
                destinationIcon
                    .frame(width: 58, height: 58)

                Text(destination.title)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 76)
                    .frame(minHeight: 31, alignment: .top)
            }
            .frame(width: 80)
            .frame(minHeight: 98, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var destinationIcon: some View {
        switch destination {
        case .messages:
            Circle()
                .fill(Color(red: 0.16, green: 0.79, blue: 0.31))
                .overlay {
                    Image(systemName: "message.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
        case .copyLink:
            Circle()
                .fill(brandMode.recessedBackground)
                .overlay {
                    Image(systemName: "link")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(brandMode.primaryText)
                }
        case .instagramStory:
            instagramIcon(showsStoryBadge: true)
        case .instagramPost:
            instagramIcon(showsStoryBadge: false)
        case .tikTok:
            Circle()
                .fill(Color.black)
                .overlay {
                    ZStack {
                        Image("BrandTikTok")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .offset(x: -1.5, y: 1.5)
                            .foregroundStyle(Color.cyan)
                        Image("BrandTikTok")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .offset(x: 1.5, y: -1.5)
                            .foregroundStyle(Color(red: 1, green: 0.18, blue: 0.42))
                        Image("BrandTikTok")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.white)
                    }
                    .padding(15)
                }
        case .snapchat:
            Circle()
                .fill(Color(red: 1, green: 0.99, blue: 0))
                .overlay {
                    ZStack {
                        Image("BrandSnapchat")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.black)
                        Image("BrandSnapchat")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .scaleEffect(0.87)
                            .foregroundStyle(.white)
                    }
                    .padding(13)
                }
        case .save:
            Circle()
                .fill(brandMode.accent)
                .overlay {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(brandMode.accentForeground)
                }
        case .more:
            Circle()
                .fill(brandMode.recessedBackground)
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(brandMode.primaryText)
                }
        }
    }

    private func instagramIcon(showsStoryBadge: Bool) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.22, blue: 0.78),
                        Color(red: 0.85, green: 0.12, blue: 0.49),
                        Color(red: 1, green: 0.66, blue: 0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image("BrandInstagram")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(15)
            }
            .overlay(alignment: .bottomTrailing) {
                if showsStoryBadge {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 21, height: 21)
                        .background(Color(red: 0.20, green: 0.48, blue: 0.96))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
    }

    private var accessibilityHint: String {
        switch destination.route {
        case .messages: "Opens Messages with the ticket image and rec.me link."
        case .copyLink: "Copies the rec.me link."
        case .instagramStory: "Opens the Instagram Story composer with the ticket image."
        case .instagramPost:
            "Opens the Instagram post composer with the ticket image. Instagram needs Full Photo Access to select the exact ticket."
        case .tikTok: "Shares the ticket image to TikTok when Share Kit is configured."
        case .snapchat: "Opens the Snapchat preview editor with the ticket image when Creative Kit is configured."
        case .savePhoto: "Saves the ticket image to Photos."
        case .systemShare: "Opens the standard iOS share sheet."
        }
    }
}

private enum ActivityShareInstagramPostShareMethod {
    case directEditor
    case compatibleDocumentHandoff
}

private enum ActivityShareInstagramPhotoAccessGuidancePresentation: String, Identifiable {
    case requiredBeforeFirstDirectShare
    case reminder

    var id: String { rawValue }

    var primaryTitle: String {
        switch self {
        case .requiredBeforeFirstDirectShare: "I've enabled Full Access"
        case .reminder: "Continue to Instagram"
        }
    }
}

private struct ActivityShareInstagramPhotoAccessGuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode

    let primaryTitle: String
    let primaryAction: () -> Void
    let compatibleAction: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            HStack {
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(brandMode.primaryText)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        .background(brandMode.raisedBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(brandMode.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Instagram photo access instructions")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(brandMode.accentText)
                        .frame(width: 58, height: 58)
                        .background(brandMode.accentWash)
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                    Text(ActivityShareInstagramPhotoAccessGuidance.title)
                        .font(AstirTypography.sheetTitle)
                        .foregroundStyle(brandMode.primaryText)

                    Text("To open this exact ticket directly in Instagram, go to:")
                        .font(AstirTypography.body)
                        .foregroundStyle(brandMode.secondaryText)

                    Text(ActivityShareInstagramPhotoAccessGuidance.settingsPath)
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WanderTheme.spacing4)
                        .background(brandMode.raisedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                                .stroke(brandMode.border, lineWidth: 1)
                        }

                    Text("Without Full Access, Instagram may select a different photo.")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(WanderTheme.stateWarning.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: WanderTheme.spacing2) {
                WanderPrimaryButton(title: primaryTitle, systemImage: "checkmark") {
                    primaryAction()
                    dismiss()
                }

                Button {
                    compatibleAction()
                    dismiss()
                } label: {
                    Text("Use compatible sharing")
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(brandMode.recessedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(brandMode.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Text("Compatible sharing avoids Instagram's Photos permission, but iOS may show an extra chooser.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.background)
    }
}

private struct ActivityShareChromeButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(brandMode.primaryText)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(brandMode.raisedBackground.opacity(0.92))
                .clipShape(Circle())
                .overlay(Circle().stroke(brandMode.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

@MainActor
enum ActivityShareArtworkRenderer {
    static let pointSize = CGSize(width: 360, height: 640)

    static func resolveAvatarImage(avatarURL: String?) async -> UIImage? {
        guard let request = WanderAvatarImageRequest(
            avatarURL: avatarURL,
            targetPixelSize: 162
        ) else {
            return nil
        }
        return await WanderAvatarImagePipeline.shared.image(for: request)?.image
    }

    static func render(
        context: ActivityEngagementContext,
        avatarImage: UIImage? = nil,
        brandMode: AstirBrandMode = .editorial
    ) -> UIImage? {
        let artwork = ActivityShareArtwork(
            context: context,
            avatarImage: avatarImage
        )
            .environment(\.astirBrandMode, brandMode)
            .frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: artwork)
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

enum ActivityShareProviderConfiguration {
    static var metaAppID: String? { configuredValue(for: "WANDER_META_APP_ID") }
    static var snapClientID: String? { configuredValue(for: "WANDER_SNAPCHAT_CLIENT_ID") }
    static var tikTokClientKey: String? { configuredValue(for: "TikTokClientKey") }
    static let tikTokRedirectURI = "https://getrec.me/share/tiktok"

    static func configuredValue(for key: String, bundle: Bundle = .main) -> String? {
        normalizedValue(bundle.object(forInfoDictionaryKey: key) as? String)
    }

    static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              !trimmed.hasSuffix("-unconfigured")
        else { return nil }
        return trimmed
    }
}

@MainActor
enum ActivityShareProviderLauncher {
    #if canImport(TikTokOpenShareSDK)
    private static var retainedTikTokRequest: TikTokShareRequest?
    #endif

    static var canOpenTikTok: Bool {
        guard ActivityShareProviderConfiguration.tikTokClientKey != nil,
              let url = URL(string: "tiktoksharesdk://")
        else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static var canOpenInstagramPostLibrary: Bool {
        UIApplication.shared.canOpenURL(ActivityShareInstagramFeedContract.libraryURL)
    }

    static func openInstagramStory(image: UIImage, contentURL: URL) async -> Bool {
        guard let appID = ActivityShareProviderConfiguration.metaAppID,
              let pngData = image.pngData(),
              var components = URLComponents(string: "instagram-stories://share")
        else { return false }

        components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        guard let shareURL = components.url, UIApplication.shared.canOpenURL(shareURL) else {
            return false
        }

        setExpiringPasteboardItems([[
            "com.instagram.sharedSticker.backgroundImage": pngData,
            "com.instagram.sharedSticker.contentURL": contentURL.absoluteString,
        ]])
        return await open(shareURL)
    }

    static func openInstagramPost(localIdentifier: String) async -> Bool {
        guard let shareURL = ActivityShareInstagramFeedContract.deepLinkURL(
            localIdentifier: localIdentifier
        ), UIApplication.shared.canOpenURL(shareURL) else {
            return false
        }
        return await open(shareURL)
    }

    static func openTikTok(
        localIdentifier: String,
        onCompletion: @escaping @MainActor (ActivityShareTikTokOutcome) -> Void
    ) async -> Bool {
        #if canImport(TikTokOpenShareSDK)
        guard canOpenTikTok else { return false }
        let request = TikTokShareRequest(
            localIdentifiers: [localIdentifier],
            mediaType: .image,
            redirectURI: ActivityShareProviderConfiguration.tikTokRedirectURI
        )
        retainedTikTokRequest = request
        let didSend = request.send { response in
            let outcome: ActivityShareTikTokOutcome
            if let shareResponse = response as? TikTokShareResponse {
                outcome = ActivityShareTikTokOutcomePolicy.outcome(
                    errorCode: shareResponse.errorCode.rawValue,
                    shareState: shareResponse.shareState.rawValue
                )
            } else {
                outcome = .failed(
                    message: "TikTok could not finish this share. Try again or use More to share another way."
                )
            }
            Task { @MainActor in
                retainedTikTokRequest = nil
                onCompletion(outcome)
            }
        }
        if !didSend {
            retainedTikTokRequest = nil
        }
        return didSend
        #else
        return false
        #endif
    }

    static func openSnapchatPreview(image: UIImage, contentURL: URL) async -> Bool {
        guard let clientID = ActivityShareProviderConfiguration.snapClientID,
              let pngData = image.pngData(),
              var components = URLComponents(string: "snapchat://creativekit/preview/1"),
              let baseURL = components.url,
              UIApplication.shared.canOpenURL(baseURL)
        else { return false }

        setExpiringPasteboardItems([[
            "com.snapchat.creativekit.clientID": clientID,
            "com.snapchat.creativekit.backgroundImage": pngData,
            "com.snapchat.creativekit.attachmentURL": contentURL.absoluteString,
            "com.snapchat.creativekit.appName": "rec.me",
        ]])

        components.queryItems = [
            URLQueryItem(name: "checkcount", value: String(UIPasteboard.general.changeCount)),
            URLQueryItem(name: "clientId", value: clientID),
            URLQueryItem(name: "appDisplayName", value: "rec.me"),
        ]
        guard let shareURL = components.url else { return false }
        return await open(shareURL)
    }

    private static func setExpiringPasteboardItems(_ items: [[String: Any]]) {
        UIPasteboard.general.setItems(
            items,
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
    }

    private static func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { didOpen in
                continuation.resume(returning: didOpen)
            }
        }
    }
}

private enum ActivitySharePhotoWriter {
    static func save(_ image: UIImage) async throws -> String {
        let identifierBox = ActivitySharePhotoIdentifierBox()
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                identifierBox.value = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { didSave, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if didSave, let localIdentifier = identifierBox.value {
                    continuation.resume(returning: localIdentifier)
                } else {
                    continuation.resume(throwing: ActivitySharePhotoWriterError.saveFailed)
                }
            }
        }
    }
}

private final class ActivitySharePhotoIdentifierBox: @unchecked Sendable {
    var value: String?
}

private enum ActivitySharePhotoWriterError: Error {
    case saveFailed
}

enum ActivityShareInstagramFeedContract {
    static let libraryURL = URL(string: "instagram://library")!
    static let fileExtension = "igo"
    static let uniformTypeIdentifier = "com.instagram.exclusivegram"

    static func deepLinkURL(localIdentifier: String) -> URL? {
        guard !localIdentifier.isEmpty,
              var components = URLComponents(url: libraryURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "OpenInEditor", value: "1"),
            URLQueryItem(name: "LocalIdentifier", value: localIdentifier),
        ]
        return components.url
    }
}

private enum ActivityShareInstagramFeedFile {
    static func prepare(_ image: UIImage) throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw ActivityShareInstagramFeedFileError.encodingFailed
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recme-instagram-\(UUID().uuidString)")
            .appendingPathExtension(ActivityShareInstagramFeedContract.fileExtension)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private enum ActivityShareInstagramFeedFileError: Error {
    case encodingFailed
}

private struct ActivityShareSystemPresentation: Identifiable {
    let id = UUID()
    let content: WanderShareContent
}

private struct ActivityShareInstagramPostPresentation: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private enum ActivityShareInstagramPostResult: Equatable {
    case dismissed
    case unavailable
}

private struct ActivityShareInstagramPostComposer: UIViewControllerRepresentable {
    let fileURL: URL
    let onFinish: (ActivityShareInstagramPostResult) -> Void

    func makeUIViewController(context: Context) -> ActivityShareInstagramPostHostController {
        ActivityShareInstagramPostHostController(fileURL: fileURL, onFinish: onFinish)
    }

    func updateUIViewController(
        _ uiViewController: ActivityShareInstagramPostHostController,
        context: Context
    ) {}
}

@MainActor
private final class ActivityShareInstagramPostHostController: UIViewController,
    @preconcurrency UIDocumentInteractionControllerDelegate
{
    private let fileURL: URL
    private let onFinish: (ActivityShareInstagramPostResult) -> Void
    private var documentController: UIDocumentInteractionController?
    private var hasPresented = false
    private var hasFinished = false

    init(fileURL: URL, onFinish: @escaping (ActivityShareInstagramPostResult) -> Void) {
        self.fileURL = fileURL
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented else { return }
        hasPresented = true

        let controller = UIDocumentInteractionController(url: fileURL)
        controller.uti = ActivityShareInstagramFeedContract.uniformTypeIdentifier
        controller.delegate = self
        documentController = controller

        guard controller.presentOpenInMenu(from: view.bounds, in: view, animated: true) else {
            finish(.unavailable)
            return
        }
    }

    func documentInteractionControllerDidDismissOpenInMenu(
        _ controller: UIDocumentInteractionController
    ) {
        finish(.dismissed)
    }

    private func finish(_ result: ActivityShareInstagramPostResult) {
        guard !hasFinished else { return }
        hasFinished = true
        try? FileManager.default.removeItem(at: fileURL)
        onFinish(result)
    }
}

private struct ActivityShareMessagePresentation: Identifiable {
    let id = UUID()
    let content: WanderShareContent
    let image: UIImage
}

private struct ActivityShareMessageComposer: UIViewControllerRepresentable {
    let body: String
    let image: UIImage
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = body
        if MFMessageComposeViewController.canSendAttachments(), let data = image.pngData() {
            controller.addAttachmentData(
                data,
                typeIdentifier: "public.png",
                filename: "recme-ticket.png"
            )
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

#if DEBUG
struct ActivitySharePreviewMockupRoot: View {
    private let context = ActivityEngagementContext(
        activityID: "41000000-0000-0000-0000-000000000264",
        actor: ProfileShell(
            id: "user_ryan",
            handle: "ryan",
            displayName: "Ryan",
            avatarURL: nil,
            bio: nil,
            relationship: .owner
        ),
        placeName: "Bar Chelou",
        placeServerID: "40000000-0000-0000-0000-000000000264",
        placeDetail: "Pasadena · French · Dinner",
        ticketKind: .checkIn,
        occurredAt: Date(timeIntervalSince1970: 1_775_520_000),
        note: "Order a few things, sit at the bar, and save room for dessert."
    )

    var body: some View {
        if let content = WanderShareContent.activity(
            activityID: context.activityID,
            placeName: context.placeName,
            message: context.shareMessage
        ) {
            ActivitySharePreviewScreen(
                context: context,
                content: content,
                initiallyVisibleDestination: ProcessInfo.processInfo.arguments.contains(
                    "-WanderActivityShareInstagramPostMockup"
                ) ? .instagramPost : .tikTok
            )
                .onOpenURL(perform: handleTikTokCallback)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handleTikTokCallback(url)
                }
        }
    }

    private func handleTikTokCallback(_ url: URL) {
        #if canImport(TikTokOpenSDKCore)
        _ = TikTokURLHandler.handleOpenURL(url)
        #endif
    }
}
#endif
