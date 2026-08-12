import MessageUI
import Photos
import SwiftUI
import UIKit

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
        case .instagramStory, .instagramPost, .tikTok, .snapchat: .socialShareFallback
        case .save: .savePhoto
        case .more: .systemShare
        }
    }
}

enum ActivityShareDestinationRoute: Equatable {
    case messages
    case copyLink
    case socialShareFallback
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

struct ActivitySharePreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let context: ActivityEngagementContext
    let content: WanderShareContent

    @State private var renderedImage: UIImage?
    @State private var renderedImageURL: URL?
    @State private var isPreparingArtwork = false
    @State private var systemSharePresentation: ActivityShareSystemPresentation?
    @State private var messagePresentation: ActivityShareMessagePresentation?
    @State private var isShowingPhotoSettingsAlert = false
    @State private var isShowingExportError = false
    @State private var confirmationMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            ActivityShareArtwork(
                context: context,
                topInset: WanderTheme.spacing12 + WanderTheme.tapMinimum + WanderTheme.spacing6
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
        case .socialShareFallback, .systemShare:
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

        guard let image = ActivityShareArtworkRenderer.render(context: context),
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
    private func saveArtworkToPhotos() async {
        guard await prepareArtworkIfNeeded(), let renderedImage else { return }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        switch ActivitySharePhotoPermissionPolicy.action(for: currentStatus) {
        case .requestAuthorization:
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .save:
            status = currentStatus
        case .showSettings:
            isShowingPhotoSettingsAlert = true
            return
        }

        guard ActivitySharePhotoPermissionPolicy.action(for: status) == .save else {
            isShowingPhotoSettingsAlert = true
            return
        }

        do {
            try await ActivitySharePhotoWriter.save(renderedImage)
            showConfirmation("saved to photos")
        } catch {
            isShowingExportError = true
        }
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
    var topInset = WanderTheme.spacing12

    var body: some View {
        ZStack {
            ActivityShareBackdrop()

            VStack(spacing: 0) {
                HStack {
                    Text("rec.me")
                        .font(WanderTypography.editorialMasthead)
                        .foregroundStyle(WanderTheme.textInk.color)

                    Spacer()

                    Text("a place worth remembering")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .padding(.horizontal, WanderTheme.spacing6)
                .padding(.top, topInset)

                Spacer(minLength: WanderTheme.spacing8)

                ActivityShareTicket(context: context)
                    .padding(.horizontal, WanderTheme.spacing6)

                Spacer(minLength: WanderTheme.spacing8)

                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("open on getrec.me")
                }
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color.opacity(0.78))
                .padding(.bottom, WanderTheme.spacing8)
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
        ZStack {
            LinearGradient(
                colors: [
                    WanderTheme.terracottaTint.color,
                    WanderTheme.canvasWarm.color,
                    WanderTheme.terracotta.color.opacity(0.48),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(WanderTheme.surfaceBone.color.opacity(0.38))
                .frame(width: 260, height: 260)
                .blur(radius: 2)
                .offset(x: 150, y: -260)

            Circle()
                .fill(WanderTheme.terracottaDark.color.opacity(0.10))
                .frame(width: 340, height: 340)
                .offset(x: -170, y: 300)
        }
    }
}

private struct ActivityShareTicket: View {
    let context: ActivityEngagementContext

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: initials,
                    avatarURL: context.actor.avatarURL,
                    size: 54,
                    color: WanderTheme.terracotta.color
                )

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
            Capsule()
                .fill(WanderTheme.borderStrong.color)
                .frame(width: 42, height: 5)

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
        .padding(.top, WanderTheme.spacing2)
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
            instagramIcon(systemImage: "plus.square.on.square")
        case .instagramPost:
            instagramIcon(systemImage: "camera")
        case .tikTok:
            Circle()
                .fill(Color.black)
                .overlay {
                    ZStack {
                        Image(systemName: "music.note")
                            .offset(x: -2, y: 1)
                            .foregroundStyle(Color.cyan)
                        Image(systemName: "music.note")
                            .offset(x: 2, y: -1)
                            .foregroundStyle(Color(red: 1, green: 0.18, blue: 0.42))
                        Image(systemName: "music.note")
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 26, weight: .black))
                }
        case .snapchat:
            Circle()
                .fill(Color(red: 1, green: 0.91, blue: 0.08))
                .overlay {
                    Image(systemName: "message.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.black)
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

    private func instagramIcon(systemImage: String) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        Color(red: 0.35, green: 0.20, blue: 0.78),
                        Color(red: 0.85, green: 0.12, blue: 0.49),
                        Color(red: 1, green: 0.66, blue: 0.20),
                        Color(red: 0.35, green: 0.20, blue: 0.78),
                    ],
                    center: .center
                )
            )
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private var accessibilityHint: String {
        switch destination.route {
        case .messages: "Opens Messages with the ticket image and rec.me link."
        case .copyLink: "Copies the rec.me link."
        case .socialShareFallback: "Opens iOS sharing options with the ticket image and rec.me link."
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
private enum ActivityShareArtworkRenderer {
    static let pointSize = CGSize(width: 360, height: 640)

    static func render(context: ActivityEngagementContext) -> UIImage? {
        let renderer = ImageRenderer(
            content: ActivityShareArtwork(context: context)
                .frame(width: pointSize.width, height: pointSize.height)
        )
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private enum ActivitySharePhotoWriter {
    static func save(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { didSave, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if didSave {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ActivitySharePhotoWriterError.saveFailed)
                }
            }
        }
    }
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
        }
    }
}
#endif
