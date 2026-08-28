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
        }
        .fullScreenCover(item: $sharePreviewPresentation) { presentation in
            ActivitySharePreviewScreen(
                context: presentation.context,
                content: presentation.content,
                analytics: store.productAnalytics
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
        let resolvedBookmarkState = bookmarkState
        return Group {
            if let visiblePlace {
                Button {
                    guard resolvedBookmarkState != .checkedIn else { return }
                    auth.requireSignIn(for: .socialSave) {
                        switch resolvedBookmarkState {
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
                    Image(systemName: resolvedBookmarkState == .notSaved ? "bookmark" : "bookmark.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(resolvedBookmarkState == .wanna ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(resolvedBookmarkState == .wanna ? "Remove from Wanna" : "Add to Wanna")
                .accessibilityValue(resolvedBookmarkState.accessibilityValue)
                .accessibilityHint(resolvedBookmarkState == .checkedIn ? "This place is already in your check-ins." : "")
            }
        }
    }
}

private enum ActivityPostcardLayout {
    static let artworkHeight: CGFloat = 154
    static let contentSpacing: CGFloat = 10
    static let contentVerticalPadding: CGFloat = 14
}

enum ActivityPostcardTypographyPolicy {
    static func ticketBadgeFontSize(for ticketKind: FeedTicketKind) -> CGFloat {
        // Mixed-case glyphs have a smaller optical height than the all-caps
        // labels, so Wanna needs a two-point compensation to match CHECKED IN.
        ticketKind == .wanna ? 12 : 10
    }
}

struct ActivityPostcardView: View {
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    let metadataIcon: String
    let secondaryMetadataTitle: String?
    let secondaryMetadataAction: (() -> Void)?
    let secondaryMetadataAccessibilityLabel: String?
    let artworkAction: (() -> Void)?
    let artworkAccessibilityLabel: String?
    let destinationAction: (() -> Void)?
    let destinationAccessibilityLabel: String?
    let openProfile: (() -> Void)?
    let actorAccessibilityIdentifier: String
    let destinationAccessibilityIdentifier: String
    let postcardAccessibilityIdentifier: String
    var artworkAccessibilityValue: String? = nil
    var artworkAccessibilityHint: String? = nil
    var showsCommentButton = true
    var showsEngagementActions = true
    var onSharePreviewPresentation: ((ActivitySharePreviewPresentation) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkDestination
                .overlay(alignment: .topLeading) {
                    ticketBadge
                        .padding(WanderTheme.spacing3)
                        .allowsHitTesting(false)
                }

            VStack(alignment: .leading, spacing: ActivityPostcardLayout.contentSpacing) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    destinationHeader
                    compactMetadata
                }

                actorAttribution

                if let note = context.note {
                    Text("“\(note)”")
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Note: \(note)")
                }

                if showsEngagementActions {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)

                    ActivityEngagementActionRow(
                        context: context,
                        visiblePlace: visiblePlace,
                        showsCommentButton: showsCommentButton,
                        onSharePreviewPresentation: onSharePreviewPresentation
                    )
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, ActivityPostcardLayout.contentVerticalPadding)
        }
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(postcardAccessibilityIdentifier)
    }

    @ViewBuilder
    private var artworkDestination: some View {
        if let artworkAction {
            Button(action: artworkAction) {
                postcardArtwork
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: ActivityPostcardLayout.artworkHeight)
            .clipped()
            .contentShape(Rectangle())
            .accessibilityLabel(artworkAccessibilityLabel ?? "Open activity")
            .accessibilityValue(artworkAccessibilityValue ?? "")
            .accessibilityHint(artworkAccessibilityHint ?? "")
        } else {
            postcardArtwork
        }
    }

    private var postcardArtwork: some View {
        ActivityPostcardArtwork(
            visiblePlace: visiblePlace,
            media: context.media,
            fallbackIcon: metadataIcon
        )
    }

    private var ticketBadge: some View {
        Label(context.ticketEyebrow, systemImage: ticketIcon)
            .font(.system(size: ticketBadgeFontSize, weight: .black, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(WanderTheme.surfaceBone.color.opacity(0.94))
            .clipShape(Capsule())
            .accessibilityLabel(context.ticketEyebrow.localizedCapitalized)
            .accessibilityIdentifier("\(postcardAccessibilityIdentifier).badge")
    }

    private var ticketBadgeFontSize: CGFloat {
        ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: context.ticketKind)
    }

    private var ticketIcon: String {
        switch context.ticketKind {
        case .checkIn: "checkmark"
        case .wanna: "plus"
        case .list: "list.bullet"
        case .saved: "mappin"
        }
    }

    private var destinationHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
                primaryDestinationTitle

                Spacer(minLength: WanderTheme.spacing1)

                ratingBadge
            }

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                primaryDestinationTitle
                ratingBadge
            }
        }
    }

    @ViewBuilder
    private var primaryDestinationTitle: some View {
        if let destinationAction {
            Button(action: destinationAction) {
                destinationTitle
            }
            .buttonStyle(.plain)
            .accessibilityLabel(destinationAccessibilityLabel ?? "Open \(context.placeName)")
            .accessibilityIdentifier(destinationAccessibilityIdentifier)
        } else {
            destinationTitle
        }
    }

    private var destinationTitle: some View {
        Text(context.placeName)
            .font(WanderTypography.editorialTitle)
            .foregroundStyle(WanderTheme.textInk.color)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if let rating = context.rating {
            Label(PlaceRating.averageDisplay(rating), systemImage: "star.fill")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .padding(.horizontal, 9)
                .frame(minHeight: 30)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Rating \(PlaceRating.averageDisplay(rating)) out of 5")
        }
    }

    private var compactMetadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WanderTheme.spacing1) {
                Label(context.placeDetail, systemImage: metadataIcon)
                    .lineLimit(1)

                if secondaryMetadataTitle != nil {
                    Text("·")
                        .accessibilityHidden(true)
                    secondaryMetadata
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Label(context.placeDetail, systemImage: metadataIcon)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                secondaryMetadata
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(WanderTheme.textMuted.color)
    }

    @ViewBuilder
    private var secondaryMetadata: some View {
        if let secondaryMetadataTitle {
            if let secondaryMetadataAction {
                Button(action: secondaryMetadataAction) {
                    Label(secondaryMetadataTitle, systemImage: "list.bullet")
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(secondaryMetadataAccessibilityLabel ?? secondaryMetadataTitle)
                .frame(minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Label(secondaryMetadataTitle, systemImage: "list.bullet")
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var actorAttribution: some View {
        if let openProfile {
            Button(action: openProfile) {
                actorContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actorAccessibilityLabel)
            .accessibilityHint("Opens profile")
            .accessibilityIdentifier(actorAccessibilityIdentifier)
        } else {
            actorContent
        }
    }

    private var actorContent: some View {
        HStack(spacing: WanderTheme.spacing2) {
            WanderAvatar(
                initials: activityInitials(for: context.actor.displayName),
                avatarURL: context.actor.avatarURL,
                size: 32,
                color: WanderTheme.skyTint.color
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(context.actor.displayName) \(context.attributionAction)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(2)

                Text("\(FeedPresentation.timestampText(for: context.occurredAt)) · someone you follow")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var actorAccessibilityLabel: String {
        "\(context.actor.displayName) \(context.attributionAction), "
            + "\(FeedPresentation.timestampText(for: context.occurredAt)), someone you follow"
    }
}

private struct ActivityPostcardArtwork: View {
    let visiblePlace: VisiblePlace?
    let media: [ActivityEngagementMedia]
    let fallbackIcon: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color.opacity(0.62))
            }
            .accessibilityHidden(true)

            if let visiblePlace {
                FeedResolvedPlacePhoto(place: visiblePlace)
            }

            if let preview = media.first {
                activityImage(preview)
            }

            if media.count > 1 {
                Text("+\(media.count - 1)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 20)
                    .background(Color.black.opacity(0.68))
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ActivityPostcardLayout.artworkHeight)
        .clipped()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func activityImage(_ media: ActivityEngagementMedia) -> some View {
        if let localImage = VisitPhotoLocalFileStore.image(from: media.localAssetRef) {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .accessibilityLabel(media.accessibilityLabel)
        } else if let remoteURL = media.urlString.flatMap(URL.init(string:)) {
            AsyncImage(url: remoteURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.clear
            }
            .accessibilityLabel(media.accessibilityLabel)
        }
    }
}

struct ActivityCommentsScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (String) -> Void
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
                content: presentation.content,
                analytics: store.productAnalytics
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
        ActivityPostcardView(
            context: context,
            visiblePlace: visiblePlace,
            metadataIcon: metadataIcon,
            secondaryMetadataTitle: secondaryListContext?.name,
            secondaryMetadataAction: secondaryMetadataAction,
            secondaryMetadataAccessibilityLabel: secondaryListContext.map { "View list \($0.name)" },
            artworkAction: artworkAction,
            artworkAccessibilityLabel: artworkAccessibilityLabel,
            destinationAction: destinationAction,
            destinationAccessibilityLabel: destinationAccessibilityLabel,
            openProfile: { openProfile(context.actor) },
            actorAccessibilityIdentifier: "comments.activity.actor",
            destinationAccessibilityIdentifier: "comments.activity.place",
            postcardAccessibilityIdentifier: "comments.activity.postcard",
            artworkAccessibilityValue: artworkAccessibilityValue,
            artworkAccessibilityHint: artworkAccessibilityHint,
            showsCommentButton: false,
            onSharePreviewPresentation: { presentation in
                sharePreviewPresentation = presentation
            }
        )
    }

    private var metadataIcon: String {
        if let visiblePlace {
            return categorySymbol(for: visiblePlace.effectiveCategory)
        }
        return switch context.ticketKind {
        case .list: "list.bullet"
        case .saved, .checkIn, .wanna: "mappin"
        }
    }

    private var artworkAction: (() -> Void)? {
        if let firstMediaID = context.media.first?.id {
            return { photoViewerRoute = ActivityCommentsPhotoViewerRoute(mediaID: firstMediaID) }
        }
        return destinationAction
    }

    private var artworkAccessibilityLabel: String? {
        if !context.media.isEmpty {
            return context.media.count == 1 ? "Open activity photo" : "Open activity photos"
        }
        return visiblePlace.map { "Open activity at \($0.place.canonicalName)" }
    }

    private var artworkAccessibilityValue: String? {
        guard !context.media.isEmpty else { return nil }
        return context.media.count == 1 ? "1 photo" : "\(context.media.count) photos"
    }

    private var artworkAccessibilityHint: String? {
        context.media.isEmpty ? nil : "Opens a full-screen photo viewer"
    }

    private var secondaryListContext: ActivityEngagementListContext? {
        guard visiblePlace != nil else { return nil }
        return context.listContext
    }

    private var secondaryMetadataAction: (() -> Void)? {
        guard let listContext = secondaryListContext else { return nil }
        return { openList(listContext.id) }
    }

    private var destinationAccessibilityLabel: String? {
        if let visiblePlace {
            return "Open \(visiblePlace.place.canonicalName)"
        }
        return context.listContext.map { "Open list \($0.name)" }
    }

    private var destinationAction: (() -> Void)? {
        if let visiblePlace {
            return { openPlace(visiblePlace) }
        }
        guard let listContext = context.listContext else { return nil }
        return { openList(listContext.id) }
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
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (String) -> Void
    @State private var isRetrying = false

    var body: some View {
        Group {
            if let route = currentRoute, let context = route.context {
                ActivityCommentsScreen(
                    context: context,
                    visiblePlace: route.visiblePlace,
                    openProfile: openProfile,
                    openPlace: openPlace,
                    openList: openList
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    guard value.startLocation.x <= 24,
                          value.translation.width >= 96,
                          abs(value.translation.height) <= 80
                    else { return }
                    activityNavigation.dismiss(requestID: requestID)
                }
        )
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
