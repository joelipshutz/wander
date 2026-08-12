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
        if errorCode == 0, shareState == 20_015 {
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

struct ActivitySharePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let context: ActivityEngagementContext
    let content: WanderShareContent

    @State private var renderedImage: UIImage?
    @State private var renderedImageURL: URL?
    @State private var resolvedAvatarImage: UIImage?
    @State private var isPreparingArtwork = false
    @State private var systemSharePresentation: ActivityShareSystemPresentation?
    @State private var messagePresentation: ActivityShareMessagePresentation?
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
                isPreparing: isPreparingArtwork,
                action: handleDestination
            )
            .background(alignment: .bottom) {
                WanderTheme.surfaceBone.color
                    .frame(height: WanderTheme.spacing12)
                    .offset(y: WanderTheme.spacing12)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .sheet(item: $systemSharePresentation) { presentation in
            WanderShareSheet(content: presentation.content)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $messagePresentation) { presentation in
            ActivityShareMessageComposer(
                body: presentation.content.messageBody,
                image: presentation.image
            ) { _ in
                messagePresentation = nil
            }
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
            _ = await prepareArtworkIfNeeded()
        }
        .onDisappear {
            guard let renderedImageURL else { return }
            Task {
                await WanderShareAttachmentStore.removePreparedPNG(at: renderedImageURL)
            }
        }
        .preferredColorScheme(.light)
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
                    .tint(WanderTheme.textInk.color)
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
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
            .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 10, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }

    private func handleDestination(_ destination: ActivityShareDestination) {
        switch destination.route {
        case .copyLink:
            UIPasteboard.general.url = content.item
            showConfirmation("link copied")
        case .messages:
            Task { await presentMessages() }
        case .instagramStory:
            Task { await presentInstagramStory() }
        case .instagramPost:
            Task { await presentInstagramPost() }
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
            avatarImage: avatarImage
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
        guard let shareContent = await preparedShareContent(), let renderedImage else { return }
        guard MFMessageComposeViewController.canSendText() else {
            systemSharePresentation = ActivityShareSystemPresentation(content: shareContent)
            return
        }
        messagePresentation = ActivityShareMessagePresentation(
            content: shareContent,
            image: renderedImage
        )
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
    }

    @MainActor
    private func presentInstagramPost() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }
        guard ActivityShareProviderLauncher.canOpenInstagram else {
            await presentSystemShare()
            return
        }
        guard await ensurePhotoLibraryAccess() else { return }

        do {
            let localIdentifier = try await ActivitySharePhotoWriter.save(renderedImage)
            guard await ActivityShareProviderLauncher.openInstagramPost(
                localIdentifier: localIdentifier
            ) else {
                await presentSystemShare()
                return
            }
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
            showConfirmation("shared to TikTok")
        case .savedAsDraft:
            showConfirmation("saved as a TikTok draft")
        case .cancelled:
            showConfirmation("TikTok share canceled")
        case .failed(let message):
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
    }

    @MainActor
    private func saveArtworkToPhotos() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }

        guard await ensurePhotoLibraryAccess() else { return }

        do {
            _ = try await ActivitySharePhotoWriter.save(renderedImage)
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
}

private struct ActivityShareArtwork: View {
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color.opacity(0.78))
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
    var body: some View {
        WanderTheme.terracotta.color
    }
}

private struct ActivityShareTicket: View {
    let context: ActivityEngagementContext
    let avatarImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.actor.displayName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)

                    Text("@\(context.actor.handle)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Text("rec.me")
                    .font(WanderTypography.editorialCardTitle)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }

            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                (Text(context.actor.displayName).fontWeight(.regular)
                    + Text(" \(context.actionTitle) ")
                    + Text(context.placeName).fontWeight(.black))
                    .font(.system(size: 20))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing1) {
                    Image(systemName: ticketIcon)
                        .font(.system(size: 12, weight: .black))

                    Text(context.placeDetail)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(WanderTheme.textMuted.color)

                if let note = context.note {
                    Text("“\(note)”")
                        .font(.system(size: 14, weight: .medium))
                        .italic()
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceBone.color)
        .checkInTicketSurface(
            accent: ticketAccent,
            surface: WanderTheme.surfaceBone.color,
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
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
            }
        }
        .frame(width: 54, height: 54)
        .background(WanderTheme.terracotta.color)
        .clipShape(Circle())
        .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
    }

    private var ticketIcon: String {
        switch context.ticketKind {
        case .checkIn: "checkmark.circle.fill"
        case .wanna: "bookmark.fill"
        case .list: "list.bullet"
        case .saved: "mappin.circle.fill"
        }
    }

    private var ticketAccent: Color {
        switch context.ticketKind {
        case .checkIn: WanderTheme.pinSocial.color
        case .wanna: WanderTheme.stateWarning.color
        case .list: WanderTheme.terracotta.color
        case .saved: WanderTheme.categorySage.color
        }
    }
}

private struct ActivityShareDestinationTray: View {
    let isPreparing: Bool
    let action: (ActivityShareDestination) -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Text("share this ticket")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: WanderTheme.spacing2) {
                    ForEach(ActivityShareDestination.allCases) { destination in
                        ActivityShareDestinationButton(destination: destination) {
                            action(destination)
                        }
                        .disabled(isPreparing && destination != .copyLink)
                        .opacity(isPreparing && destination != .copyLink ? 0.58 : 1)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
            }
            .frame(height: 104)
            .scrollIndicators(.hidden)
        }
        .padding(.top, WanderTheme.spacing4)
        .padding(.bottom, WanderTheme.spacing2)
        .frame(maxWidth: .infinity)
        .background(WanderTheme.surfaceBone.color)
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
            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 18, y: -5)
    }
}

private struct ActivityShareDestinationButton: View {
    let destination: ActivityShareDestination
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WanderTheme.spacing2) {
                destinationIcon
                    .frame(width: 58, height: 58)

                Text(destination.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
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
                .fill(WanderTheme.surfaceSand.color)
                .overlay {
                    Image(systemName: "link")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
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
                .fill(WanderTheme.terracotta.color)
                .overlay {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                }
        case .more:
            Circle()
                .fill(WanderTheme.surfaceSand.color)
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
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
        case .instagramPost: "Opens the Instagram post composer with the ticket image."
        case .tikTok: "Shares the ticket image to TikTok when Share Kit is configured."
        case .snapchat: "Opens the Snapchat preview editor with the ticket image when Creative Kit is configured."
        case .savePhoto: "Saves the ticket image to Photos."
        case .systemShare: "Opens the standard iOS share sheet."
        }
    }
}

private struct ActivityShareChromeButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceBone.color.opacity(0.92))
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
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
        avatarImage: UIImage? = nil
    ) -> UIImage? {
        let artwork = ActivityShareArtwork(
            context: context,
            avatarImage: avatarImage
        )
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

    static var canOpenInstagram: Bool {
        guard let url = URL(string: "instagram://app") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static var canOpenTikTok: Bool {
        guard ActivityShareProviderConfiguration.tikTokClientKey != nil,
              let url = URL(string: "tiktoksharesdk://")
        else { return false }
        return UIApplication.shared.canOpenURL(url)
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
        guard var components = URLComponents(string: "instagram://library") else { return false }
        components.queryItems = [URLQueryItem(name: "LocalIdentifier", value: localIdentifier)]
        guard let shareURL = components.url, UIApplication.shared.canOpenURL(shareURL) else {
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

private struct ActivityShareSystemPresentation: Identifiable {
    let id = UUID()
    let content: WanderShareContent
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

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
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
            ActivitySharePreviewScreen(context: context, content: content)
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
