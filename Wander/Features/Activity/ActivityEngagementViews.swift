import SwiftUI

struct ActivityEngagementActionRow: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    var showsCommentButton = true
    var isEngagementEnabled = true
    var reportSubjectOverride: CommunityReportSubject?
    var onSharePreviewPresentation: ((ActivitySharePreviewPresentation) -> Void)?
    @State private var wannaSaveContext: MapPlaceSaveContext?
    @State private var sharePreviewPresentation: ActivitySharePreviewPresentation?
    @State private var reportSubject: CommunityReportSubject?

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            likeButton

            if showsCommentButton {
                commentButton
            }

            shareButton

            if context.actor.id != store.currentUser.id, resolvedReportSubject != nil {
                reportMenu
            }

            Spacer(minLength: WanderTheme.spacing3)

            bookmarkButton
        }
        .frame(minHeight: 44)
        .sheet(item: $wannaSaveContext, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { saveContext in
            MapPlaceSaveFlowSheet(context: saveContext) { submission in
                await persistNewPlaceSaveSubmission(
                    submission,
                    store: store,
                    backend: auth.isSignedIn ? backend : nil
                )
            } onRemove: { _ in
                false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $sharePreviewPresentation) { presentation in
            ActivitySharePreviewScreen(
                context: presentation.context,
                content: presentation.content
            )
            .id(presentation.id)
        }
        .sheet(item: $reportSubject) { subject in
            CommunityReportSheet(subject: subject)
                .environmentObject(backend)
        }
    }

    private var engagement: ActivityEngagementSummary {
        store.activityEngagement(for: context.activityID)
    }

    private var bookmarkState: ActivityBookmarkState {
        visiblePlace.map(store.activityBookmarkState(for:)) ?? .notSaved
    }

    private var likeButton: some View {
        Button {
            auth.requireSignIn(for: .socialActivity) {
                Task {
                    _ = await store.toggleActivityLike(
                        activityID: context.activityID,
                        backend: auth.isSignedIn ? backend : nil
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: engagement.viewerHasLiked ? "heart.fill" : "heart")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(
                        engagement.viewerHasLiked
                            ? WanderTheme.terracotta.color
                            : WanderTheme.textInk.color
                    )

                Text(engagement.likeCount.formatted())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WanderTheme.textInk.color)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEngagementEnabled || store.isActivityLikePending(context.activityID))
        .opacity(isEngagementEnabled ? 1 : 0.45)
        .accessibilityLabel(engagement.viewerHasLiked ? "Unlike activity" : "Like activity")
        .accessibilityValue("\(engagement.likeCount) likes")
    }

    private var commentButton: some View {
        Button {
            auth.requireSignIn(for: .socialActivity) {
                activityNavigation.openComments(
                    context: context,
                    visiblePlace: visiblePlace
                )
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(WanderTheme.textInk.color)

                Text(engagement.commentCount.formatted())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WanderTheme.textInk.color)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEngagementEnabled)
        .opacity(isEngagementEnabled ? 1 : 0.45)
        .accessibilityLabel("Open comments")
        .accessibilityValue("\(engagement.commentCount) comments")
    }

    private var reportMenu: some View {
        Menu {
            Button {
                auth.requireSignIn(for: .reportContent) {
                    reportSubject = resolvedReportSubject
                }
            } label: {
                Label("Report activity", systemImage: "exclamationmark.bubble")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Activity actions")
    }

    private var resolvedReportSubject: CommunityReportSubject? {
        if let reportSubjectOverride {
            return reportSubjectOverride
        }
        guard UUID(uuidString: context.activityID) != nil else {
            return nil
        }
        return CommunityReportSubject(
            kind: .activity,
            subjectID: context.activityID,
            reportedUserID: context.actor.id,
            context: "Report \(context.actor.displayName)’s activity at \(context.placeName)."
        )
    }

    @ViewBuilder
    private var shareButton: some View {
        if isEngagementEnabled, activityShareContent != nil {
            Button {
                guard let presentation = ActivitySharePreviewPresentation(context: context) else {
                    return
                }

                if let onSharePreviewPresentation {
                    onSharePreviewPresentation(presentation)
                } else {
                    sharePreviewPresentation = presentation
                }
            } label: {
                shareLabel
            }
            .buttonStyle(.plain)
        } else {
            Button(action: {}) {
                shareLabel
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.45)
            .accessibilityHint("Available when this activity finishes loading.")
        }
    }

    private var activityShareContent: WanderShareContent? {
        WanderShareContent.activity(
            activityID: context.activityID,
            placeName: context.placeName,
            message: context.shareMessage
        )
    }

    private var shareLabel: some View {
        Image(systemName: "paperplane")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Share activity")
    }

    private var bookmarkButton: some View {
        Group {
            if let visiblePlace {
                Button {
                    guard bookmarkState != .checkedIn else { return }
                    auth.requireSignIn(for: .socialSave) {
                        switch bookmarkState {
                        case .notSaved:
                            store.saveFlowDidPresent(.saveSheet)
                            wannaSaveContext = .addWannaVisiblePlace(
                                visiblePlace,
                                defaultVisibility: store.effectiveDefaultVisibility
                            )
                        case .wanna:
                            Task {
                                _ = await store.removeActivityWanna(
                                    for: visiblePlace,
                                    backend: auth.isSignedIn ? backend : nil
                                )
                            }
                        case .checkedIn:
                            break
                        }
                    }
                } label: {
                    Image(systemName: bookmarkState == .notSaved ? "bookmark" : "bookmark.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(bookmarkState == .wanna ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmarkState == .wanna ? "Remove from Wanna" : "Add to Wanna")
                .accessibilityValue(bookmarkState.accessibilityValue)
                .accessibilityHint(bookmarkState == .checkedIn ? "This place is already in your check-ins." : "")
            }
        }
    }
}

struct ActivityCommentsScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isPosting = false
    @State private var commentError: String?
    @State private var photoViewerRoute: ActivityCommentsPhotoViewerRoute?
    @State private var sharePreviewPresentation: ActivitySharePreviewPresentation?
    @State private var reportSubject: CommunityReportSubject?
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List {
                activityHeader
                    .listRowInsets(
                        EdgeInsets(
                            top: WanderTheme.spacing3,
                            leading: WanderTheme.spacing4,
                            bottom: WanderTheme.spacing2,
                            trailing: WanderTheme.spacing4
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if isLoading, comments.isEmpty {
                    ProgressView("Loading comments…")
                        .tint(WanderTheme.terracotta.color)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if comments.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .id(comment.id)
                            .padding(.horizontal, WanderTheme.spacing4)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                if let commentError {
                    Text(commentError)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, WanderTheme.spacing4)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, WanderTheme.spacing8, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.map(\.id)) { _, commentIDs in
                guard let newestID = commentIDs.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newestID, anchor: .bottom)
                }
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .task(id: context.activityID) {
            isLoading = true
            let didRefresh = await store.refreshActivityComments(
                activityID: context.activityID,
                backend: auth.isSignedIn ? backend : nil
            )
            commentError = didRefresh ? nil : "Comments couldn't refresh. Try again."
            isLoading = false
        }
        .fullScreenCover(item: $photoViewerRoute) { route in
            ActivityCommentsPhotoViewer(
                media: context.media,
                initialMediaID: route.mediaID,
                reportedUserID: context.actor.id,
                reportedUserName: context.actor.displayName,
                placeName: context.placeName
            )
        }
        .fullScreenCover(item: $sharePreviewPresentation) { presentation in
            ActivitySharePreviewScreen(
                context: presentation.context,
                content: presentation.content
            )
            .id(presentation.id)
        }
        .sheet(item: $reportSubject) { subject in
            CommunityReportSheet(subject: subject)
                .environmentObject(backend)
        }
    }

    private var comments: [ActivityComment] {
        store.activityComments(for: context.activityID)
    }

    @ViewBuilder
    private func commentRow(_ comment: ActivityComment) -> some View {
        if store.canDeleteActivityComment(comment) {
            ActivityCommentRow(comment: comment, onDelete: { delete(comment) })
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        delete(comment)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete comment")
                }
                .accessibilityAction(named: "Delete comment") {
                    delete(comment)
                }
        } else {
            ActivityCommentRow(comment: comment, onReport: { presentReport(for: comment) })
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        presentReport(for: comment)
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
                    }
                    .tint(WanderTheme.stateWarning.color)
                    .accessibilityLabel("Report comment")
                }
                .accessibilityAction(named: "Report comment") {
                    presentReport(for: comment)
                }
        }
    }

    private var activityHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            activitySummary

            ActivityEngagementActionRow(
                context: context,
                visiblePlace: visiblePlace,
                showsCommentButton: false,
                onSharePreviewPresentation: { presentation in
                    sharePreviewPresentation = presentation
                }
            )
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .checkInTicketSurface(
            accent: ticketAccent,
            surface: WanderTheme.surfaceBone.color,
            surroundingSurface: WanderTheme.canvasWarm.color,
            notchEdges: .trailing,
            castsShadow: false,
            borderWidth: 1.5
        )
    }

    @ViewBuilder
    private var activitySummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                    activityAvatar
                    activityCopy
                }

                if !context.media.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        activityMediaThumbnail
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                activityAvatar
                activityCopy

                if !context.media.isEmpty {
                    Spacer(minLength: WanderTheme.spacing1)
                    activityMediaThumbnail
                }
            }
        }
    }

    private var activityMediaThumbnail: some View {
        ActivityCommentsMediaThumbnail(media: context.media) { mediaID in
            photoViewerRoute = ActivityCommentsPhotoViewerRoute(mediaID: mediaID)
        }
    }

    private var activityAvatar: some View {
        WanderAvatar(
            initials: activityInitials(for: context.actor.displayName),
            avatarURL: context.actor.avatarURL,
            size: 48,
            color: WanderTheme.skyTint.color
        )
    }

    private var activityCopy: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            (Text(context.actor.displayName).fontWeight(.black)
                + Text(" \(context.actionTitle) ")
                + Text(context.placeName).fontWeight(.black))
                .font(.system(size: 16))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)

            Text(context.placeDetail)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)

            Text(FeedPresentation.timestampText(for: context.occurredAt))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WanderTheme.textFaint.color)

            if let note = context.note {
                Text("“\(note)”")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Note: \(note)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ticketAccent: Color {
        switch context.ticketKind {
        case .checkIn: WanderTheme.pinSocial.color
        case .wanna: WanderTheme.stateWarning.color
        case .list: WanderTheme.terracotta.color
        case .saved: WanderTheme.categorySage.color
        }
    }

    private var emptyState: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "bubble.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text("Start the conversation")
                .font(WanderTypography.editorialCardTitle)
                .foregroundStyle(WanderTheme.textInk.color)
            Text("Share what makes this place worth remembering.")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(WanderTheme.borderHairline.color)

            HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: activityInitials(for: store.currentUser.displayName),
                    avatarURL: store.currentUser.avatarURL,
                    size: 36,
                    color: WanderTheme.terracottaTint.color
                )

                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(post)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.vertical, 10)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(WanderTheme.borderStrong.color, lineWidth: 1)
                    )

                Button("Post", action: post)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(minWidth: 52, minHeight: 44)
                    .disabled(normalizedDraft.isEmpty || isPosting)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
        }
        .background(WanderTheme.surfaceBone.color)
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func post() {
        let body = normalizedDraft
        guard !body.isEmpty, body.count <= 1_000, !isPosting else { return }
        do {
            try CommunityContentPolicy.validate(body)
        } catch {
            commentError = error.localizedDescription
            return
        }
        draft = ""
        isPosting = true
        commentError = nil
        Task {
            let didPost = await store.addActivityComment(
                activityID: context.activityID,
                body: body,
                backend: auth.isSignedIn ? backend : nil
            )
            if !didPost {
                if draft.isEmpty { draft = body }
                commentError = "Your comment couldn't post. Try again."
            }
            isPosting = false
            composerFocused = true
        }
    }

    private func delete(_ comment: ActivityComment) {
        commentError = nil
        Task {
            let didDelete = await store.deleteActivityComment(
                comment,
                backend: auth.isSignedIn ? backend : nil
            )
            if !didDelete {
                commentError = "Your comment couldn't be deleted. Try again."
            }
        }
    }

    private func presentReport(for comment: ActivityComment) {
        auth.requireSignIn(for: .reportContent) {
            reportSubject = CommunityReportSubject(
                kind: .comment,
                subjectID: comment.id,
                reportedUserID: comment.author.id,
                context: "Report \(comment.author.displayName)’s comment."
            )
        }
    }
}

private struct ActivityCommentsMediaThumbnail: View {
    let media: [ActivityEngagementMedia]
    let onOpen: (String) -> Void
    private let size: CGFloat = 76

    var body: some View {
        if let first = media.first {
            Button {
                onOpen(first.id)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color.opacity(0.55))
                    }

                    if let localImage = VisitPhotoLocalFileStore.image(from: first.localAssetRef) {
                        Image(uiImage: localImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                    } else if let remoteURL = first.urlString.flatMap(URL.init(string:)) {
                        AsyncImage(url: remoteURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                        } placeholder: {
                            ProgressView()
                                .tint(WanderTheme.terracotta.color)
                        }
                    }

                    if media.count > 1 {
                        Text("+\(media.count - 1)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 20)
                            .background(Color.black.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(.trailing, 6)
                            .padding(.bottom, 9)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .contentShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }
            .buttonStyle(.plain)
            .frame(minWidth: size, minHeight: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open activity photos")
            .accessibilityValue(media.count == 1 ? "1 photo" : "\(media.count) photos")
            .accessibilityHint("Opens a full-screen photo viewer")
        }
    }
}

private struct ActivityCommentsPhotoViewerRoute: Identifiable {
    let mediaID: String

    var id: String { mediaID }
}

private struct ActivityCommentsPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let media: [ActivityEngagementMedia]
    let reportedUserID: String
    let reportedUserName: String
    let placeName: String
    @State private var selectedMediaID: String
    @State private var reportSubject: CommunityReportSubject?

    init(
        media: [ActivityEngagementMedia],
        initialMediaID: String,
        reportedUserID: String,
        reportedUserName: String,
        placeName: String
    ) {
        self.media = media
        self.reportedUserID = reportedUserID
        self.reportedUserName = reportedUserName
        self.placeName = placeName
        _selectedMediaID = State(initialValue: initialMediaID)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedMediaID) {
                ForEach(media) { item in
                    ZoomablePhoto {
                        ActivityCommentsFullScreenImage(media: item)
                    }
                    .tag(item.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, WanderTheme.spacing2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            HStack {
                WanderGlassActionButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back",
                    tone: .darkOverlay,
                    action: dismiss.callAsFunction
                )

                Spacer()

                if reportableSelectedPhoto != nil {
                    WanderGlassActionButton(
                        systemImage: "exclamationmark.bubble",
                        accessibilityLabel: "Report photo",
                        tone: .darkOverlay,
                        action: reportSelectedPhoto
                    )
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
        }
        .preferredColorScheme(.dark)
        .onChange(of: media.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                dismiss()
                return
            }
            if !ids.contains(selectedMediaID), let firstID = ids.first {
                selectedMediaID = firstID
            }
        }
        .sheet(item: $reportSubject) { subject in
            CommunityReportSheet(subject: subject)
                .environmentObject(backend)
        }
    }

    private var reportableSelectedPhoto: CommunityReportSubject? {
        guard reportedUserID != store.currentUser.id,
              UUID(uuidString: selectedMediaID) != nil
        else {
            return nil
        }
        return CommunityReportSubject(
            kind: .visitPhoto,
            subjectID: selectedMediaID,
            reportedUserID: reportedUserID,
            context: "Report \(reportedUserName)’s photo from \(placeName)."
        )
    }

    private func reportSelectedPhoto() {
        guard let reportableSelectedPhoto else { return }
        auth.requireSignIn(for: .reportContent) {
            reportSubject = reportableSelectedPhoto
        }
    }
}

private struct ActivityCommentsFullScreenImage: View {
    let media: ActivityEngagementMedia

    var body: some View {
        if let localImage = VisitPhotoLocalFileStore.image(from: media.localAssetRef) {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(media.accessibilityLabel)
        } else if let remoteURL = media.urlString.flatMap(URL.init(string:)) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(media.accessibilityLabel)
                case .failure:
                    placeholder(systemImage: "exclamationmark.triangle.fill", title: "Photo unavailable")
                case .empty:
                    placeholder(systemImage: "arrow.triangle.2.circlepath", title: "Loading photo")
                @unknown default:
                    placeholder(systemImage: "photo", title: "Photo")
                }
            }
        } else {
            placeholder(systemImage: "photo", title: "Photo unavailable")
        }
    }

    private func placeholder(systemImage: String, title: String) -> some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .black))
            Text(title)
                .font(.system(size: 15, weight: .black))
        }
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(title)
    }
}

struct ActivityCommentsRouteScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    let requestID: UUID
    let retry: @MainActor () async -> Void
    @State private var isRetrying = false

    var body: some View {
        Group {
            if let route = currentRoute, let context = route.context {
                ActivityCommentsScreen(
                    context: context,
                    visiblePlace: route.visiblePlace
                )
            } else {
                resolutionState
            }
        }
        .navigationTitle("comments")
        .navigationBarTitleDisplayMode(.inline)
        .tint(WanderTheme.textInk.color)
        .toolbarBackground(WanderTheme.surfaceBone.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var currentRoute: ActivityCommentsRoute? {
        guard let route = activityNavigation.commentsRoute, route.id == requestID else { return nil }
        return route
    }

    private var resolutionError: String? {
        guard let activityID = currentRoute?.activityID else { return nil }
        return store.activityEngagementError(for: activityID)
    }

    private var resolutionState: some View {
        VStack(spacing: WanderTheme.spacing4) {
            if resolutionError == nil || isRetrying {
                ProgressView("Opening activity…")
                    .tint(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textMuted.color)
            } else {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WanderTheme.terracotta.color)

                Text("This activity couldn’t load")
                    .font(WanderTypography.editorialCardTitle)
                    .foregroundStyle(WanderTheme.textInk.color)

                Text("Check your connection and try again.")
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WanderTheme.textMuted.color)

                Button("Try again") {
                    Task { @MainActor in
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                }
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.surfaceRaised.color)
                .frame(minWidth: 132, minHeight: 44)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
                .disabled(isRetrying)
            }
        }
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }
}

private struct ActivityCommentRow: View {
    let comment: ActivityComment
    var onDelete: (() -> Void)?
    var onReport: (() -> Void)?

    init(
        comment: ActivityComment,
        onDelete: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil
    ) {
        self.comment = comment
        self.onDelete = onDelete
        self.onReport = onReport
    }

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            WanderAvatar(
                initials: activityInitials(for: comment.author.displayName),
                avatarURL: comment.author.avatarURL,
                size: 34,
                color: WanderTheme.skyTint.color
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: WanderTheme.spacing1) {
                    Text(comment.author.displayName)
                        .font(.system(size: 14, weight: .black))
                    Text(FeedPresentation.timestampText(for: comment.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }

                Text(comment.body)
                    .font(.system(size: 15))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(comment.isPending ? 0.58 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(comment.author.displayName) commented: \(comment.body)")

            Spacer(minLength: 0)

            if onDelete != nil || onReport != nil {
                Menu {
                    if let onReport {
                        Button(action: onReport) {
                            Label("Report comment", systemImage: "exclamationmark.bubble")
                        }
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete comment", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Comment actions")
            }
        }
        .padding(.vertical, WanderTheme.spacing1)
        .accessibilityElement(children: .contain)
    }
}

private func activityInitials(for name: String) -> String {
    name
        .split(separator: " ")
        .prefix(2)
        .compactMap(\.first)
        .map(String.init)
        .joined()
        .uppercased()
}
