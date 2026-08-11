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
    @State private var wannaSaveContext: MapPlaceSaveContext?

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            likeButton

            if showsCommentButton {
                commentButton
            }

            shareButton

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

    @ViewBuilder
    private var shareButton: some View {
        if isEngagementEnabled,
           let content = WanderShareContent.activity(
                activityID: context.activityID,
                placeName: context.placeName,
                message: context.shareMessage
           ) {
            WanderShareButton(content: content) {
                shareLabel
            }
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isPosting = false
    @State private var commentError: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        activityHeader

                        if isLoading, comments.isEmpty {
                            ProgressView("Loading comments…")
                                .tint(WanderTheme.terracotta.color)
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .frame(maxWidth: .infinity, minHeight: 140)
                        } else if comments.isEmpty {
                            emptyState
                        } else {
                            ForEach(comments) { comment in
                                ActivityCommentRow(comment: comment)
                                    .id(comment.id)
                            }
                        }

                        if let commentError {
                            Text(commentError)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WanderTheme.terracottaDark.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing8)
                }
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
            .navigationTitle("comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WanderTheme.surfaceBone.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                }
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
        }
    }

    private var comments: [ActivityComment] {
        store.activityComments(for: context.activityID)
    }

    private var activityHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: activityInitials(for: context.actor.displayName),
                    avatarURL: context.actor.avatarURL,
                    size: 48,
                    color: WanderTheme.skyTint.color
                )

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
                }
            }

            ActivityEngagementActionRow(
                context: context,
                visiblePlace: visiblePlace,
                showsCommentButton: false
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
}

struct ActivityCommentsRouteScreen: View {
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
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
            .navigationTitle("comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WanderTheme.surfaceBone.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activityNavigation.dismiss(requestID: requestID)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }
}

private struct ActivityCommentRow: View {
    let comment: ActivityComment

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            WanderAvatar(
                initials: activityInitials(for: comment.author.displayName),
                avatarURL: comment.author.avatarURL,
                size: 34,
                color: WanderTheme.skyTint.color
            )

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

            Spacer(minLength: 0)
        }
        .padding(.vertical, WanderTheme.spacing1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.author.displayName) commented: \(comment.body)")
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
