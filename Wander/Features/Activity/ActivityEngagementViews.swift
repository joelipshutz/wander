import SwiftUI

enum ActivityPostcardVisualStyle: Equatable {
    case standard
    case astir
}

private struct ActivityPostcardVisualStyleKey: EnvironmentKey {
    static let defaultValue = ActivityPostcardVisualStyle.standard
}

extension EnvironmentValues {
    var activityPostcardVisualStyle: ActivityPostcardVisualStyle {
        get { self[ActivityPostcardVisualStyleKey.self] }
        set { self[ActivityPostcardVisualStyleKey.self] = newValue }
    }
}

struct ActivityEngagementActionRow: View {
    @Environment(\.activityPresentationHandoff) private var handoff
    @Environment(\.activityPostcardVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var astirBrandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    var sharedVisitGroupID: String? = nil
    var showsCommentButton = true
    var showsWannaButton = true
    var isEngagementEnabled = true
    var resolveContext: (@MainActor () async -> ActivityEngagementContext?)?
    var reportSubjectOverride: CommunityReportSubject?
    var onPrivateReply: (() -> Void)?
    var onSharePreviewPresentation: ((ActivitySharePreviewPresentation) -> Void)?
    @State private var wannaSaveContext: MapPlaceSaveContext?
    @State private var sharePreviewPresentation: ActivitySharePreviewPresentation?
    @State private var reportSubject: CommunityReportSubject?
    @State private var isResolvingAction = false
    @State private var actionGeneration = UUID()
    @State private var actionError: String?

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            likeButton

            if showsCommentButton {
                commentButton
            }

            shareButton

            activityMenu

            Spacer(minLength: WanderTheme.spacing3)

            if showsWannaButton {
                bookmarkButton
            }
        }
        .frame(minHeight: 44)
        .alert("Couldn't Load This Check-In", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Try Again In A Moment.")
        }
        .sheet(item: $wannaSaveContext, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
            handoff.onDidDismiss(.activitySave)
        }) { saveContext in
            WanderRootPresentationLifecycle(
                surface: .activitySave, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                MapPlaceSaveFlowSheet(context: saveContext) { submission in
                    await persistNewPlaceSaveSubmission(
                        submission, store: store, backend: auth.isSignedIn ? backend : nil
                    )
                } onRemove: { _ in false }
            }
        }
        .fullScreenCover(item: $sharePreviewPresentation, onDismiss: { handoff.onDidDismiss(.activityShare) }) { presentation in
            WanderRootPresentationLifecycle(
                surface: .activityShare, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                ActivitySharePreviewScreen(
                    context: presentation.context, content: presentation.content,
                    analytics: store.productAnalytics
                )
                .id(presentation.id)
            }
        }
        .sheet(item: $reportSubject, onDismiss: { handoff.onDidDismiss(.activityReport) }) { subject in
            WanderRootPresentationLifecycle(
                surface: .activityReport, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                CommunityReportSheet(subject: subject)
                    .environmentObject(backend)
            }
        }
        .onChange(of: handoff.resetID) { _, resetID in
            guard resetID != nil else { return }
            actionGeneration = UUID()
            wannaSaveContext = nil
            sharePreviewPresentation = nil
            reportSubject = nil
            actionError = nil
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
                performResolvedAction { resolved in
                    _ = await store.toggleActivityLike(
                        activityID: resolved.activityID,
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
                            ? accentColor
                            : primaryColor
                    )

                Text(engagement.likeCount.formatted())
                    .font(visualStyle == .astir ? AstirTypography.label : .system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryColor)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAttemptEngagement || isResolvingAction || store.isActivityLikePending(context.activityID))
        .opacity(canAttemptEngagement ? 1 : 0.45)
        .accessibilityLabel(engagement.viewerHasLiked ? "Unlike Activity" : "Like Activity")
        .accessibilityValue("\(engagement.likeCount) Likes")
    }

    private var commentButton: some View {
        Button {
            auth.requireSignIn(for: .socialActivity) {
                performResolvedAction { resolved in
                    activityNavigation.openComments(context: resolved, visiblePlace: visiblePlace, sharedVisitGroupID: sharedVisitGroupID)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(primaryColor)

                if sharedVisitGroupID == nil {
                    Text(engagement.commentCount.formatted())
                        .font(visualStyle == .astir ? AstirTypography.label : .system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAttemptEngagement || isResolvingAction)
        .opacity(canAttemptEngagement ? 1 : 0.45)
        .accessibilityLabel("Open Comments")
        .accessibilityValue(sharedVisitGroupID == nil ? "\(engagement.commentCount) Comments" : "All Readable Shared Check-In Discussions")
    }

    private var activityMenu: some View {
        ActivityActionsMenu(
            activityID: context.activityID,
            onPrivateReply: onPrivateReply,
            onReport: context.actor.id != store.currentUser.id && resolvedReportSubject != nil ? {
                auth.requireSignIn(for: .reportContent) {
                    reportSubject = resolvedReportSubject
                }
            } : nil
        )
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
            context: "Report \(context.actor.displayName)’s Activity At \(context.placeName)."
        )
    }

    @ViewBuilder
    private var shareButton: some View {
        if resolveContext != nil || (isEngagementEnabled && activityShareContent != nil) {
            Button {
                performResolvedAction { resolved in
                    guard let presentation = ActivitySharePreviewPresentation(context: resolved) else {
                        actionError = "This Check-In Is Still Syncing. Try Sharing Again In A Moment."
                        return
                    }
                    if let onSharePreviewPresentation {
                        onSharePreviewPresentation(presentation)
                    } else {
                        sharePreviewPresentation = presentation
                    }
                }
            } label: {
                shareLabel
            }
            .buttonStyle(.plain)
            .disabled(isResolvingAction)
        } else {
            Button(action: {}) {
                shareLabel
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.45)
            .accessibilityHint("Available When This Activity Finishes Loading.")
        }
    }

    private var canAttemptEngagement: Bool {
        isEngagementEnabled || resolveContext != nil
    }

    private func performResolvedAction(_ action: @escaping @MainActor (ActivityEngagementContext) async -> Void) {
        guard !isResolvingAction else { return }
        isResolvingAction = true
        let requestUserID = store.currentUser.id
        let requestGeneration = actionGeneration
        Task { @MainActor in
            defer { isResolvingAction = false }
            let resolved: ActivityEngagementContext?
            if let resolveContext {
                resolved = await resolveContext()
            } else {
                resolved = isEngagementEnabled ? context : nil
            }
            guard !Task.isCancelled, store.currentUser.id == requestUserID,
                  actionGeneration == requestGeneration else { return }
            guard let resolved else {
                actionError = "Check Your Connection And Tap The Action To Try Again. If The Owner Removed This Check-In, It Will Disappear When History Refreshes."
                return
            }
            await action(resolved)
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
            .foregroundStyle(primaryColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Share Activity")
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
                        .foregroundStyle(resolvedBookmarkState == .wanna ? accentColor : primaryColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(resolvedBookmarkState == .wanna ? "Remove From Wanna" : "Add To Wanna")
                .accessibilityValue(resolvedBookmarkState.accessibilityValue)
                .accessibilityHint(resolvedBookmarkState == .checkedIn ? "This Place Is Already In Your Check-Ins." : "")
            }
        }
    }

    private var primaryColor: Color {
        visualStyle == .astir ? astirBrandMode.primaryText : WanderTheme.textInk.color
    }

    private var accentColor: Color {
        visualStyle == .astir ? astirBrandMode.accent : WanderTheme.terracotta.color
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

/// Keep the menu visible even when this activity has no eligible actions.
/// Report eligibility and presentation remain owned by the engagement row.
struct ActivityActionsMenu: View {
    @Environment(\.activityPostcardVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var brand
    let activityID: String
    var onPrivateReply: (() -> Void)?
    var onReport: (() -> Void)?

    var body: some View {
        Menu {
            if let onPrivateReply {
                Button("Reply Privately", systemImage: "bubble.left", action: onPrivateReply)
            }
            if let onReport {
                Button(action: onReport) {
                    Label("Report Activity", systemImage: "exclamationmark.bubble")
                }
            }
            if onPrivateReply == nil && onReport == nil {
                Button("No Additional Actions", action: {}).disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(visualStyle == .astir ? brand.primaryText : WanderTheme.textInk.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Activity Actions")
        .accessibilityIdentifier("activity.\(activityID).actions")
    }
}

struct ActivityPostcardView: View {
    @Environment(\.activityPostcardVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var astirBrandMode
    @Environment(\.activityPresentationHandoff) private var handoff
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @StateObject private var sharedModel = SharedVisitDiscussionModel()
    @State private var sharedRenderedKey: String?
    @State private var sharedKnownVisitIDs: Set<String> = []
    @State private var sharedRetry = 0
    @State private var photoViewerRoute: ActivityCommentsPhotoViewerRoute?
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
    var allowsPlaceUserPhotoFallback = true
    var showsCommentButton = true
    var showsEngagementActions = true
    var showsActivityMenu = false
    var onPrivateReply: (() -> Void)?
    var onSharePreviewPresentation: ((ActivitySharePreviewPresentation) -> Void)?
    var activityGroup: FeedActivityGroup? = nil
    var openActivityList: ((LocalPlaceList) -> Void)? = nil
    var openPhotos: (() -> Void)? = nil
    var sharedVisitCompanions: [FeedSharedVisitCompanion] = []
    var sharedVisitCurrentUserID: String = ""
    var openSharedVisitProfile: ((String) -> Void)? = nil
    var sharedPostCollection: SharedVisitPostCollection? = nil
    var sharedGroupID: String? = nil

    private var activeSharedGroupID: String? { sharedGroupID ?? activityGroup?.sharedVisitGroupID }
    private var sharedMembershipKey: String {
        let known = Array(sharedKnownVisitIDs) + (activityGroup?.activities.compactMap { $0.sharedVisit?.visitID } ?? [])
            + (sharedPostCollection?.visitIDs ?? [])
        return SharedVisitMembershipSnapshot.key(visitIDs: known, cache: store.sharedVisitCompanionsByVisitID)
    }
    private var sharedAccessKey: String {
        guard let groupID = activeSharedGroupID else { return "ordinary" }
        return "\(groupID):\(context.activityID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase):\(store.presentationRevision):\(sharedRetry):\(sharedMembershipKey)"
    }
    private var sharedPresentation: SharedVisitPostcardPresentation? {
        guard activeSharedGroupID != nil, scenePhase == .active else { return nil }
        let collection = sharedPostCollection ?? (sharedRenderedKey == sharedAccessKey ? sharedModel.collection : nil)
        guard let collection else { return nil }
        return SharedVisitPostcardPresentation(collection: collection, viewerID: store.currentUser.id) { profile in
            SharedVisitLocalVisibility.permitsAuthor(authorID: profile.id, viewerID: store.currentUser.id,
                blocked: store.isBlockedBetweenCurrentUser(and: profile.id), muted: store.isMuted(userID: profile.id),
                privateProfile: profile.isPrivateProfile == true || store.isProfilePrivate(profile.id))
        }
    }
    private var displayContext: ActivityEngagementContext { sharedPresentation?.context ?? context }

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

                HStack(spacing: WanderTheme.spacing2) {
                    actorAttribution
                    if let firstPhoto = displayContext.media.first {
                        photoStack(firstPhoto: firstPhoto)
                    }
                }

                if activeSharedGroupID == nil, let note = displayContext.note {
                    Text("“\(note)”")
                        .font(visualStyle == .astir ? AstirTypography.bodySmall : .system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(noteBackground)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: visualStyle == .astir ? 14 : WanderTheme.radiusMedium,
                                style: .continuous
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Note: \(note)")
                }

                if activeSharedGroupID != nil {
                    sharedNotes
                }

                if let activityGroup, activeSharedGroupID == nil {
                    FeedActivityDisclosure(group: activityGroup, openList: openActivityList)
                }

                if showsEngagementActions {
                    Divider()
                        .overlay(borderColor)

                    ActivityEngagementActionRow(
                        context: displayContext,
                        visiblePlace: visiblePlace,
                        sharedVisitGroupID: activeSharedGroupID,
                        showsCommentButton: showsCommentButton,
                        onPrivateReply: onPrivateReply,
                        onSharePreviewPresentation: onSharePreviewPresentation
                    )
                } else if showsActivityMenu {
                    // An activity without place/list context previously had no
                    // engagement row. Give it the same menu without adding reporting.
                    ActivityActionsMenu(activityID: context.activityID, onPrivateReply: onPrivateReply)
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, ActivityPostcardLayout.contentVerticalPadding)
        }
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: visualStyle == .astir ? 22 : WanderTheme.radiusLarge,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: visualStyle == .astir ? 22 : WanderTheme.radiusLarge,
                style: .continuous
            )
            .stroke(borderColor, lineWidth: 1)
        }
        .shadow(
            color: visualStyle == .astir ? Color.black.opacity(0.18) : .clear,
            radius: visualStyle == .astir ? 16 : 0,
            y: visualStyle == .astir ? 8 : 0
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(postcardAccessibilityIdentifier)
        .fullScreenCover(item: $photoViewerRoute, onDismiss: { handoff.onDidDismiss(.activityPhoto) }) { route in
            WanderRootPresentationLifecycle(
                surface: .activityPhoto, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                if let groupID = activeSharedGroupID {
                    SharedVisitPhotoViewerScreen(activityID: context.activityID, groupID: groupID, initialMediaID: route.mediaID)
                } else {
                    ActivityPhotoViewerScreen(context: context, initialMediaID: route.mediaID)
                }
            }
        }
        .onChange(of: handoff.resetID) { _, resetID in
            if resetID != nil { photoViewerRoute = nil }
        }
        .onChange(of: context.activityID) { _, _ in photoViewerRoute = nil }
        .task(id: sharedAccessKey) {
            guard activeSharedGroupID != nil, sharedPostCollection == nil else { return }
            sharedModel.invalidate()
            guard scenePhase == .active, auth.isSignedIn, ActivitySessionReadiness(auth: auth) == .ready,
                  let groupID = activeSharedGroupID, let repository = backend.activityEngagementRepository else { return }
            let key = sharedAccessKey
            sharedRenderedKey = key
            await sharedModel.load(activityID: context.activityID, groupID: groupID, repository: repository,
                includeComments: false, isCurrent: { key == sharedAccessKey })
            guard key == sharedAccessKey else { return }
            sharedKnownVisitIDs.formUnion(sharedModel.collection?.visitIDs ?? [])
        }
        .onDisappear { sharedModel.invalidate(); sharedRenderedKey = nil }
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
            .accessibilityLabel(artworkAccessibilityLabel ?? "Open Activity")
            .accessibilityValue(artworkAccessibilityValue ?? "")
            .accessibilityHint(artworkAccessibilityHint ?? "")
        } else {
            postcardArtwork
        }
    }

    private var postcardArtwork: some View {
        ActivityPostcardArtwork(
            visiblePlace: visiblePlace,
            media: displayContext.media,
            fallbackIcon: metadataIcon,
            usesAstirPhotoFallback: visualStyle == .astir,
            allowsPlaceUserPhotoFallback: allowsPlaceUserPhotoFallback
        )
    }

    private var ticketBadge: some View {
        Label(displayContext.ticketEyebrow, systemImage: ticketIcon)
            .font(visualStyle == .astir ? AstirTypography.metadata : .system(size: ticketBadgeFontSize, weight: .black, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(visualStyle == .astir ? astirBrandMode.background : WanderTheme.textInk.color)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(
                visualStyle == .astir
                    ? astirBrandMode.primaryText.opacity(0.96)
                    : WanderTheme.surfaceBone.color.opacity(0.94)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: visualStyle == .astir ? 12 : WanderTheme.radiusPill,
                    style: .continuous
                )
            )
            .accessibilityLabel(displayContext.ticketEyebrow.localizedCapitalized)
            .accessibilityIdentifier("\(postcardAccessibilityIdentifier).badge")
    }

    private var ticketBadgeFontSize: CGFloat {
        ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: displayContext.ticketKind)
    }

    private var ticketIcon: String {
        switch displayContext.ticketKind {
        case .checkIn: "checkmark"
        case .wanna: "plus"
        case .list: PlaceListSymbol.systemImage
        case .saved: "mappin"
        }
    }

    private var destinationHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            primaryDestinationTitle
            ratingBadge
        }
    }

    @ViewBuilder
    private var primaryDestinationTitle: some View {
        if let destinationAction {
            Button(action: destinationAction) {
                destinationTitle
            }
            .buttonStyle(.plain)
            .accessibilityLabel(destinationAccessibilityLabel ?? "Open \(displayContext.placeName)")
            .accessibilityIdentifier(destinationAccessibilityIdentifier)
        } else {
            destinationTitle
        }
    }

    private var destinationTitle: some View {
        Text(displayContext.placeName)
            .font(visualStyle == .astir ? AstirTypography.sectionTitle : WanderTypography.editorialTitle)
            .foregroundStyle(primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .topLeading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if let rating = displayContext.rating {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .accessibilityHidden(true)
                Text(PlaceRating.averageDisplay(rating))
                    .accessibilityIdentifier("\(postcardAccessibilityIdentifier).rating.value")
                    .accessibilityLabel("Rating \(PlaceRating.averageDisplay(rating)) Out Of 5")
            }
                .font(visualStyle == .astir ? AstirTypography.label : .system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(visualStyle == .astir ? astirBrandMode.accentText : WanderTheme.terracottaDark.color)
                .padding(.horizontal, 9)
                .frame(minHeight: 30)
                .background(visualStyle == .astir ? Color.clear : WanderTheme.terracottaTint.color)
                .overlay(alignment: .bottom) {
                    if visualStyle == .astir {
                        Rectangle().fill(astirBrandMode.accent).frame(height: 1)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactMetadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WanderTheme.spacing1) {
                Label(displayContext.placeDetail, systemImage: metadataIcon)
                    .lineLimit(1)

                if secondaryMetadataTitle != nil {
                    Text("·")
                        .accessibilityHidden(true)
                    secondaryMetadata
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Label(displayContext.placeDetail, systemImage: metadataIcon)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                secondaryMetadata
            }
        }
        .font(visualStyle == .astir ? AstirTypography.metadata : .system(size: 11, weight: .semibold))
        .foregroundStyle(secondaryText)
    }

    @ViewBuilder
    private var secondaryMetadata: some View {
        if let secondaryMetadataTitle {
            if let secondaryMetadataAction {
                Button(action: secondaryMetadataAction) {
                    Label(secondaryMetadataTitle, systemImage: PlaceListSymbol.systemImage)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(secondaryMetadataAccessibilityLabel ?? secondaryMetadataTitle)
                .frame(minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Label(secondaryMetadataTitle, systemImage: PlaceListSymbol.systemImage)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var actorAttribution: some View {
        if let presentation = sharedPresentation {
            sharedActorAttribution(presentation)
        } else if let openProfile {
            Button(action: openProfile) {
                actorContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actorAccessibilityLabel)
            .accessibilityHint("Opens Profile")
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
                    .font(visualStyle == .astir ? AstirTypography.bodySmall : .system(size: 14, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)

                Text(FeedPresentation.timestampText(for: context.occurredAt))
                    .font(visualStyle == .astir ? AstirTypography.metadata : .caption.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sharedActorAttribution(_ presentation: SharedVisitPostcardPresentation) -> some View {
        HStack(spacing: WanderTheme.spacing2) {
            HStack(spacing: -20) {
                ForEach(Array(([presentation.context.actor] + presentation.companions).prefix(2))) { profile in
                    Button {
                        if profile.id == context.actor.id { openProfile?() }
                        else { openSharedVisitProfile?(profile.id) }
                    } label: {
                        WanderAvatar(initials: activityInitials(for: profile.displayName), avatarURL: profile.avatarURL,
                            size: 32, color: WanderTheme.skyTint.color)
                            .overlay(Circle().stroke(cardBackground, lineWidth: 2))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(profile.displayName)’s Profile")
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.attribution)
                    .font(visualStyle == .astir ? AstirTypography.bodySmall : .system(size: 14, weight: .bold))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(postcardAccessibilityIdentifier).companions")
                Text(FeedPresentation.timestampText(for: presentation.context.occurredAt))
                    .font(visualStyle == .astir ? AstirTypography.metadata : .caption.weight(.medium))
                    .foregroundStyle(secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(actorAccessibilityIdentifier)
    }

    @ViewBuilder private var sharedNotes: some View {
        if let presentation = sharedPresentation {
            ForEach(presentation.posts) { post in
                if let note = post.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.actor.displayName).font(AstirTypography.label)
                        Text("“\(note)”").font(AstirTypography.bodySmall)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, WanderTheme.spacing3).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(noteBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sharedVisit.post.\(post.id)")
                }
            }
        } else if sharedModel.failed {
            Button("Shared Check-Ins Couldn’t Load. Try Again") { sharedRetry += 1 }
                .font(AstirTypography.caption).frame(minHeight: 44)
        } else {
            ProgressView("Loading Shared Check-Ins…").font(AstirTypography.caption)
        }
    }

    private var actorAccessibilityLabel: String {
        "\(displayContext.actor.displayName) \(displayContext.attributionAction), "
            + FeedPresentation.timestampText(for: displayContext.occurredAt)
    }

    private func photoStack(firstPhoto: ActivityEngagementMedia) -> some View {
        Button {
            if activeSharedGroupID == nil, let openPhotos {
                openPhotos()
            } else {
                photoViewerRoute = ActivityCommentsPhotoViewerRoute(mediaID: firstPhoto.id)
            }
        } label: {
            ZStack {
                if displayContext.media.count > 1 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primaryText.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(primaryText.opacity(0.55), lineWidth: 1))
                        .frame(width: 42, height: 42)
                        .rotationEffect(.degrees(9))
                        .offset(x: 4, y: -3)
                }
                ZStack {
                    cardBackground
                    Image(systemName: "photo").foregroundStyle(secondaryText)
                    ActivityPostcardMediaImage(media: firstPhoto)
                }
                .frame(width: 46, height: 46)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 25)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(displayContext.media.count)")
                            .font(.custom("AvenirNext-DemiBold", size: 10))
                    }
                    .foregroundStyle(.white)
                    .padding(5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(primaryText.opacity(0.55), lineWidth: 1))
            }
            .frame(width: 54, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(displayContext.media.count == 1 ? "Photo" : "Photos") From \(displayContext.actor.displayName)’s \(displayContext.ticketKind == .checkIn ? "Check-In" : "Save")")
        .accessibilityValue(displayContext.media.count == 1 ? "1 Photo" : "\(displayContext.media.count) Photos")
        .accessibilityHint("Opens A Full-Screen Photo Viewer")
        .accessibilityIdentifier("\(postcardAccessibilityIdentifier).photos")
    }

    private var primaryText: Color {
        visualStyle == .astir ? astirBrandMode.primaryText : WanderTheme.textInk.color
    }

    private var secondaryText: Color {
        visualStyle == .astir ? astirBrandMode.secondaryText : WanderTheme.textMuted.color
    }

    private var cardBackground: Color {
        visualStyle == .astir
            ? astirBrandMode.raisedBackground.opacity(0.78)
            : WanderTheme.surfaceBone.color
    }

    private var noteBackground: Color {
        visualStyle == .astir
            ? astirBrandMode.primaryText.opacity(0.07)
            : WanderTheme.terracottaTint.color
    }

    private var borderColor: Color {
        visualStyle == .astir
            ? astirBrandMode.border.opacity(0.72)
            : WanderTheme.borderHairline.color
    }
}

private struct ActivityPostcardArtwork: View {
    let visiblePlace: VisiblePlace?
    let media: [ActivityEngagementMedia]
    let fallbackIcon: String
    let usesAstirPhotoFallback: Bool
    let allowsPlaceUserPhotoFallback: Bool

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

            if usesAstirPhotoFallback,
               ActivityPostcardArtworkPolicy.showsDecorativeFallback(
                   hasVisiblePlace: visiblePlace != nil,
                   mediaCount: media.count
               ) {
                AstirPlacePhotoAsset(
                    stableKey: visiblePlace?.place.id ?? fallbackIcon
                )
                .accessibilityHidden(true)
            }

            if ActivityPostcardArtworkPolicy.showsPlacePhoto(
                hasVisiblePlace: visiblePlace != nil,
                mediaCount: media.count
            ), let visiblePlace {
                FeedResolvedPlacePhoto(place: visiblePlace, allowsUserPhotoFallback: allowsPlaceUserPhotoFallback)
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

    private func activityImage(_ media: ActivityEngagementMedia) -> some View {
        ActivityPostcardMediaImage(media: media)
    }
}

private struct ActivityPostcardMediaImage: View {
    let media: ActivityEngagementMedia

    var body: some View {
        PlaceProfilePhotoImage(photo: media.placePhoto, canonicalPlaceKey: "activity-photo:\(media.id)",
                               placeName: media.accessibilityLabel, variant: .card)
    }
}

enum ActivityPostcardArtworkPolicy {
    static func showsPlacePhoto(hasVisiblePlace: Bool, mediaCount: Int) -> Bool {
        hasVisiblePlace && mediaCount == 0
    }

    static func showsDecorativeFallback(hasVisiblePlace: Bool, mediaCount: Int) -> Bool {
        !hasVisiblePlace && mediaCount == 0
    }
}

/// Share the root's physical dismissal acknowledgements with post-owned covers.
struct ActivityPresentationHandoff {
    var resetID: UUID?
    var onPresent: (WanderDeepLinkPresentationToken) -> Void = { _ in }
    var onWillDismiss: (WanderDeepLinkPresentationToken) -> Void = { _ in }
    var onDidDismiss: (WanderDeepLinkPresentationSurface) -> Void = { _ in }
}

private struct ActivityPresentationHandoffKey: EnvironmentKey {
    static var defaultValue: ActivityPresentationHandoff { ActivityPresentationHandoff() }
}

extension EnvironmentValues {
    var activityPresentationHandoff: ActivityPresentationHandoff {
        get { self[ActivityPresentationHandoffKey.self] }
        set { self[ActivityPresentationHandoffKey.self] = newValue }
    }
}

/// Composer state outlives temporary authorization/loading views, but belongs
/// to one viewer and activity. Revocation also retires any in-flight post.
struct ActivityCommentComposerState {
    struct Scope: Equatable {
        let viewerID: String
        let activityID: String
        let isSignedIn: Bool
    }

    struct PendingPost {
        let id: UUID
        let draft: String
        let mentions: [PersonMention]
        var body: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private(set) var scope: Scope?
    var draft = ""
    var mentions: [PersonMention] = []
    private(set) var pendingPostID: UUID?
    var isPosting: Bool { pendingPostID != nil }
    var preservesForegroundEntry: Bool { !draft.isEmpty || isPosting }

    mutating func prepare(for scope: Scope) {
        guard self.scope != scope else { return }
        self = Self()
        self.scope = scope
    }

    mutating func revokeAccess(for scope: Scope) {
        guard self.scope == scope else { return }
        self = Self()
        self.scope = scope
    }

    mutating func beginPost() -> PendingPost? {
        guard !isPosting, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let post = PendingPost(id: UUID(), draft: draft, mentions: mentions)
        pendingPostID = post.id
        draft = ""
        mentions = []
        return post
    }

    @discardableResult
    mutating func finishPost(_ post: PendingPost, succeeded: Bool) -> Bool {
        guard pendingPostID == post.id else { return false }
        pendingPostID = nil
        if !succeeded, draft.isEmpty {
            draft = post.draft
            mentions = post.mentions
        }
        return true
    }
}

/// Every entry point, including an already resolved navigation route, checks
/// the immutable source again before mounting its cached header or photo sheet.
struct ActivityCommentsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (String) -> Void
    @State private var retryID = 0
    @State private var composer = ActivityCommentComposerState()
    @State private var checkedKey: String?
    @State private var checkedGeneration = 0
    @State private var checkedContext: ActivityEngagementContext?
    @State private var checkedPlace: VisiblePlace?

    private var composerScope: ActivityCommentComposerState.Scope {
        .init(viewerID: store.currentUser.id, activityID: context.activityID, isSignedIn: auth.isSignedIn)
    }

    private var accessKey: String {
        "\(context.activityID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase):\(retryID)"
    }

    var body: some View {
        Group {
            if checkedKey == accessKey, checkedGeneration == store.activityAccessGeneration(for: context.activityID), let checkedContext {
                AuthorizedActivityCommentsScreen(context: checkedContext, visiblePlace: checkedPlace,
                    openProfile: openProfile, openPlace: openPlace, openList: openList,
                    recheckAccess: recheckAccess, composer: $composer)
            } else if checkedKey == accessKey {
                ContentUnavailableView("Activity Unavailable", systemImage: "lock",
                    description: Text("This Activity Is No Longer Available, Or Couldn’t Be Checked. Try Again When Connected."))
                    .safeAreaInset(edge: .bottom) {
                        Button("Try Again") { retryID += 1 }.padding()
                    }
            } else {
                ProgressView("Opening Activity…")
            }
        }
        .blocksProductUpsells(while: composer.preservesForegroundEntry, preservesForegroundEntry: true)
        .onChange(of: composerScope, initial: true) { _, scope in
            composer.prepare(for: scope)
        }
        .onChange(of: store.activityAccessGeneration(for: context.activityID)) { _, _ in
            composer.revokeAccess(for: composerScope)
        }
        .task(id: accessKey) {
            composer.prepare(for: composerScope)
            guard scenePhase == .active else { return }
            let key = accessKey
            checkedKey = nil
            if UUID(uuidString: context.activityID) == nil {
                checkedContext = context
                checkedPlace = visiblePlace
            } else {
                guard auth.isSignedIn else {
                    checkedContext = nil
                    checkedPlace = nil
                    checkedKey = key
                    return
                }
                let activity = await store.activity(id: context.activityID, backend: backend, authSession: auth)
                guard !Task.isCancelled, key == accessKey, ActivitySessionReadiness(auth: auth) != .validating else { return }
                checkedContext = activity?.activityEngagementContext
                checkedPlace = activity?.place
            }
            checkedGeneration = store.activityAccessGeneration(for: context.activityID)
            checkedKey = key
        }
        .onDisappear {
            checkedKey = nil
            checkedContext = nil
            checkedPlace = nil
        }
    }

    private func recheckAccess() async -> Bool {
        guard UUID(uuidString: context.activityID) != nil else { return true }
        let key = accessKey
        let activity = auth.isSignedIn ? await store.activity(id: context.activityID, backend: backend, authSession: auth) : nil
        guard !Task.isCancelled, key == accessKey, ActivitySessionReadiness(auth: auth) != .validating else { return false }
        checkedContext = activity?.activityEngagementContext
        checkedPlace = activity?.place
        checkedGeneration = store.activityAccessGeneration(for: context.activityID)
        return checkedContext != nil
    }
}

private struct AuthorizedActivityCommentsScreen: View {
    @Environment(\.activityPresentationHandoff) private var handoff
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let visiblePlace: VisiblePlace?
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (String) -> Void
    let recheckAccess: () async -> Bool
    @Binding var composer: ActivityCommentComposerState
    @State private var isLoading = true
    @State private var commentError: String?
    @State private var photoViewerRoute: ActivityCommentsPhotoViewerRoute?
    @State private var sharePreviewPresentation: ActivitySharePreviewPresentation?
    @State private var reportSubject: CommunityReportSubject?
    @State private var composerFocused = false

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
                    ProgressView("Loading Comments…")
                        .font(AstirTypography.bodySmall)
                        .tint(brandMode.accent)
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 140)
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
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text(commentError)
                        Button("Try Again") {
                            Task { await refreshComments() }
                        }
                        .frame(minHeight: 44)
                        .disabled(isLoading)
                    }
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.stateError.color)
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
        .background(brandMode.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerInput
        }
        .task(id: "\(context.activityID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase)") {
            guard scenePhase == .active else { return }
            await refreshComments()
        }
        .refreshable { await refreshComments() }
        .fullScreenCover(item: $photoViewerRoute, onDismiss: { handoff.onDidDismiss(.activityPhoto) }) { route in
            WanderRootPresentationLifecycle(
                surface: .activityPhoto, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                ActivityPhotoViewerScreen(context: context, initialMediaID: route.mediaID)
            }
        }
        .fullScreenCover(item: $sharePreviewPresentation, onDismiss: { handoff.onDidDismiss(.activityShare) }) { presentation in
            WanderRootPresentationLifecycle(
                surface: .activityShare, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                ActivitySharePreviewScreen(
                    context: presentation.context,
                    content: presentation.content,
                    analytics: store.productAnalytics
                )
                .id(presentation.id)
            }
        }
        .sheet(item: $reportSubject, onDismiss: { handoff.onDidDismiss(.activityReport) }) { subject in
            WanderRootPresentationLifecycle(
                surface: .activityReport, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                CommunityReportSheet(subject: subject)
                    .environmentObject(backend)
            }
        }
        .onChange(of: handoff.resetID) { _, resetID in
            guard resetID != nil else { return }
            composerFocused = false
            photoViewerRoute = nil
            sharePreviewPresentation = nil
            reportSubject = nil
        }
    }

    @MainActor
    private func refreshComments() async {
        isLoading = true
        commentError = nil
        guard await recheckAccess() else { isLoading = false; return }
        let didRefresh = await store.refreshActivityComments(
            activityID: context.activityID,
            backend: auth.isSignedIn ? backend : nil,
            authSession: auth
        )
        guard !Task.isCancelled, ActivitySessionReadiness(auth: auth) != .validating || UUID(uuidString: context.activityID) == nil else { return }
        commentError = didRefresh ? nil : "Comments Couldn't Refresh. Try Again."
        isLoading = false
    }

    private var comments: [ActivityComment] {
        store.activityComments(for: context.activityID)
    }

    @ViewBuilder
    private func commentRow(_ comment: ActivityComment) -> some View {
        if comment.author.id == store.currentUser.id {
            ActivityCommentRow(comment: comment,
                               canLike: store.canLikeActivityComment(comment),
                               isLikePending: store.isActivityCommentLikePending(comment.id),
                               onLike: { toggleLike(comment) },
                               onDelete: store.canDeleteActivityComment(comment) ? { delete(comment) } : nil)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        delete(comment)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete Comment")
                    .disabled(!store.canDeleteActivityComment(comment))
                }
                .accessibilityAction(named: "Delete Comment") {
                    delete(comment)
                }
        } else {
            ActivityCommentRow(comment: comment,
                               canLike: store.canLikeActivityComment(comment),
                               isLikePending: store.isActivityCommentLikePending(comment.id),
                               onLike: { toggleLike(comment) }, onReport: { presentReport(for: comment) })
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        presentReport(for: comment)
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
                    }
                    .tint(WanderTheme.stateWarning.color)
                    .accessibilityLabel("Report Comment")
                }
                .accessibilityAction(named: "Report Comment") {
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
            secondaryMetadataAccessibilityLabel: secondaryListContext.map { "View List \($0.name)" },
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
            },
            openPhotos: artworkAction
        )
    }

    private func toggleLike(_ comment: ActivityComment) {
        auth.requireSignIn(for: .socialActivity) {
            Task { @MainActor in
                let userID = store.currentUser.id
                let succeeded = await store.toggleActivityCommentLike(
                    comment, backend: auth.isSignedIn ? backend : nil
                )
                guard !Task.isCancelled, userID == store.currentUser.id else { return }
                commentError = succeeded ? nil : store.activityEngagementError(for: context.activityID)
            }
        }
    }

    private var metadataIcon: String {
        if let visiblePlace {
            return categorySymbol(for: visiblePlace.effectiveCategory)
        }
        return switch context.ticketKind {
        case .list: PlaceListSymbol.systemImage
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
            return context.media.count == 1 ? "Open Activity Photo" : "Open Activity Photos"
        }
        return visiblePlace.map { "Open Activity At \($0.place.canonicalName)" }
    }

    private var artworkAccessibilityValue: String? {
        guard !context.media.isEmpty else { return nil }
        return context.media.count == 1 ? "1 Photo" : "\(context.media.count) Photos"
    }

    private var artworkAccessibilityHint: String? {
        context.media.isEmpty ? nil : "Opens A Full-Screen Photo Viewer"
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
        return context.listContext.map { "Open List \($0.name)" }
    }

    private var destinationAction: (() -> Void)? {
        if let visiblePlace {
            return { openPlace(visiblePlace) }
        }
        guard let listContext = context.listContext else { return nil }
        return { openList(listContext.id) }
    }

    private var composerInput: some View {
        PersonMentionField(
            text: $composer.draft, mentions: $composer.mentions,
            focus: $composerFocused,
            placeholder: "Add A Comment…", accessibilityLabel: "Add A Comment",
            accessibilityIdentifier: "activity.comment.input", submitOnReturn: true,
            suggestionPlacement: .aboveInput, onSubmit: post,
            decorateInput: { AnyView(composerRow($0)) }
        )
    }

    private func composerRow(_ input: AnyView) -> some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(brandMode.border)

            HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: activityInitials(for: store.currentUser.displayName),
                    avatarURL: store.currentUser.avatarURL,
                    size: 36,
                    color: brandMode.accentWash
                )

                input
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.vertical, 10)
                    .background(brandMode.raisedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(brandMode.border, lineWidth: 1))

                Button(action: post) {
                    Group {
                        if composer.isPosting {
                            ProgressView().tint(brandMode.accentForeground)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 19, weight: .semibold))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .foregroundStyle(brandMode.accentForeground)
                    .background(brandMode.accent.opacity(normalizedDraft.isEmpty ? 0.35 : 1), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(composer.isPosting ? "Sending Comment" : "Send Comment")
                .accessibilityIdentifier("activity.comment.send")
                .disabled(normalizedDraft.isEmpty || normalizedDraft.count > 1_000 || composer.isPosting)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
        }
        .background(brandMode.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.comment.composer")
    }

    private var normalizedDraft: String {
        composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func post() {
        let body = normalizedDraft
        guard !body.isEmpty, body.count <= 1_000, !composer.isPosting else { return }
        do {
            try CommunityContentPolicy.validate(body)
        } catch {
            commentError = error.localizedDescription
            return
        }
        guard let post = composer.beginPost() else { return }
        commentError = nil
        Task {
            let didPost = await store.addActivityComment(
                activityID: context.activityID,
                body: post.body,
                backend: auth.isSignedIn ? backend : nil
            )
            guard composer.finishPost(post, succeeded: didPost) else { return }
            if !didPost {
                commentError = "Your Comment Couldn't Post. Try Again."
            }
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
                commentError = "Your Comment Couldn't Be Deleted. Try Again."
            }
        }
    }

    private func presentReport(for comment: ActivityComment) {
        auth.requireSignIn(for: .reportContent) {
            reportSubject = CommunityReportSubject(
                kind: .comment,
                subjectID: comment.id,
                reportedUserID: comment.author.id,
                context: "Report \(comment.author.displayName)’s Comment."
            )
        }
    }
}

private struct ActivityCommentsPhotoViewerRoute: Identifiable {
    let mediaID: String

    var id: String { mediaID }
}

/// Both Feed and comments must re-resolve the exact activity before mounting
/// its media. A cached card is not authorization to display protected photos.
struct ActivityPhotoViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let context: ActivityEngagementContext
    let initialMediaID: String
    @State private var access = ActivityPhotoViewerAccessState()
    @State private var retryID = 0
    @State private var attemptedScope: ActivityPhotoViewerAccessState.Scope?

    private var scope: ActivityPhotoViewerAccessState.Scope {
        .init(activityID: context.activityID, viewerID: store.currentUser.id,
              isSignedIn: auth.isSignedIn, sessionReadiness: ActivitySessionReadiness(auth: auth),
              sessionRevision: backend.photoSessionRevision,
              photoAccessRevision: backend.photoAccessRevision,
              activityGeneration: store.activityAccessGeneration(for: context.activityID),
              isActive: scenePhase == .active, retryID: retryID)
    }

    private var wasRevoked: Bool {
        guard let attemptedScope else { return false }
        return attemptedScope.activityGeneration != scope.activityGeneration
    }

    var body: some View {
        Group {
            if let checked = access.context(for: scope), !checked.media.isEmpty {
                ActivityCommentsPhotoViewer(
                    media: checked.media, initialMediaID: initialMediaID,
                    reportedUserID: checked.actor.id,
                    reportedUserName: checked.actor.displayName, placeName: checked.placeName
                )
            } else {
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    if access.isResolved(for: scope) || wasRevoked {
                        ContentUnavailableView {
                            Label("Photos Unavailable", systemImage: "photo")
                        } description: {
                            Text("These Photos Are No Longer Available, Or Couldn’t Be Checked.")
                        } actions: {
                            Button("Try Again") { retryID += 1 }
                                .frame(minHeight: WanderTheme.tapMinimum)
                        }
                        .accessibilityIdentifier("activity.photos.unavailable")
                    } else {
                        ProgressView("Opening Photos…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    WanderGlassActionButton(systemImage: "chevron.left", accessibilityLabel: "Back",
                                            tone: .darkOverlay, action: dismiss.callAsFunction)
                        .accessibilityIdentifier("activity.photos.back")
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.top, WanderTheme.spacing3)
                }
            }
        }
        .preferredColorScheme(.dark)
        .blocksProductUpsells(while: true, preservesForegroundEntry: true)
        .task(id: scope.refreshTrigger) {
            let current = scope
            attemptedScope = current
            let request = access.begin(scope: current)
            guard current.isActive else { return }
            let checked: ActivityEngagementContext?
            if UUID(uuidString: context.activityID) == nil {
                checked = context
            } else if current.isSignedIn {
                checked = await store.activity(
                    id: current.activityID, backend: backend, authSession: auth
                )?.activityEngagementContext
            } else {
                checked = nil
            }
            guard !Task.isCancelled,
                  ActivitySessionReadiness(auth: auth) != .validating || UUID(uuidString: context.activityID) == nil
            else { return }
            access.finish(request, context: checked, currentScope: scope)
        }
        .onDisappear {
            access.invalidate()
            attemptedScope = nil
        }
    }
}

/// Reauthorize every original before presenting a combined photo pile.
private struct SharedVisitPhotoViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let activityID: String
    let groupID: String
    let initialMediaID: String
    @StateObject private var model = SharedVisitDiscussionModel()
    @State private var renderedKey: String?
    @State private var knownVisitIDs: Set<String> = []
    @State private var retry = 0
    private var membershipKey: String {
        SharedVisitMembershipSnapshot.key(visitIDs: Array(knownVisitIDs), cache: store.sharedVisitCompanionsByVisitID)
    }
    private var accessKey: String {
        "\(activityID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase):\(store.presentationRevision):\(backend.photoSessionRevision):\(backend.photoAccessRevision):\(retry):\(membershipKey)"
    }
    private var presentation: SharedVisitPostcardPresentation? {
        guard scenePhase == .active, renderedKey == accessKey, let collection = model.collection else { return nil }
        return SharedVisitPostcardPresentation(collection: collection, viewerID: store.currentUser.id) { profile in
            SharedVisitLocalVisibility.permitsAuthor(authorID: profile.id, viewerID: store.currentUser.id,
                blocked: store.isBlockedBetweenCurrentUser(and: profile.id), muted: store.isMuted(userID: profile.id),
                privateProfile: profile.isPrivateProfile == true || store.isProfilePrivate(profile.id))
        }
    }
    var body: some View {
        Group {
            if let presentation, !presentation.context.media.isEmpty {
                ActivityCommentsPhotoViewer(media: presentation.context.media, initialMediaID: initialMediaID,
                    reportedUserID: presentation.context.actor.id, reportedUserName: presentation.context.actor.displayName,
                    placeName: presentation.context.placeName, mediaAuthors: presentation.mediaAuthors)
            } else {
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    if model.failed || model.collection != nil {
                        ContentUnavailableView("Photos Unavailable", systemImage: "photo",
                            description: Text("These Photos Are No Longer Available, Or Couldn’t Be Checked."))
                            .safeAreaInset(edge: .bottom) { Button("Try Again") { retry += 1 }.frame(minHeight: 44) }
                            .accessibilityIdentifier("activity.photos.unavailable")
                    } else { ProgressView("Opening Photos…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    WanderGlassActionButton(systemImage: "chevron.left", accessibilityLabel: "Back",
                        tone: .darkOverlay, action: dismiss.callAsFunction)
                        .accessibilityIdentifier("activity.photos.back")
                        .padding(.horizontal, WanderTheme.spacing4).padding(.top, WanderTheme.spacing3)
                }
            }
        }
        .preferredColorScheme(.dark).blocksProductUpsells(while: true, preservesForegroundEntry: true)
        .task(id: accessKey) {
            model.invalidate()
            guard scenePhase == .active, auth.isSignedIn, ActivitySessionReadiness(auth: auth) == .ready,
                  let repository = backend.activityEngagementRepository else { return }
            let key = accessKey
            renderedKey = key
            await model.load(activityID: activityID, groupID: groupID, repository: repository,
                includeComments: false, isCurrent: { key == accessKey })
            guard key == accessKey else { return }
            knownVisitIDs.formUnion(model.collection?.visitIDs ?? [])
        }
        .onDisappear { model.invalidate(); renderedKey = nil }
    }
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
    let mediaAuthors: [String: ProfileShell]
    @State private var selectedMediaID: String
    @State private var reportSubject: CommunityReportSubject?

    init(
        media: [ActivityEngagementMedia],
        initialMediaID: String,
        reportedUserID: String,
        reportedUserName: String,
        placeName: String,
        mediaAuthors: [String: ProfileShell] = [:]
    ) {
        self.media = media
        self.reportedUserID = reportedUserID
        self.reportedUserName = reportedUserName
        self.placeName = placeName
        self.mediaAuthors = mediaAuthors
        _selectedMediaID = State(initialValue: media.contains(where: { $0.id == initialMediaID })
            ? initialMediaID : (media.first?.id ?? initialMediaID))
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
                .accessibilityIdentifier("activity.photos.back")

                Spacer()

                Text("\((media.firstIndex(where: { $0.id == selectedMediaID }) ?? 0) + 1) Of \(media.count)")
                    .font(AstirTypography.caption)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("activity.photos.position")

                Spacer()

                if reportableSelectedPhoto != nil {
                    WanderGlassActionButton(
                        systemImage: "exclamationmark.bubble",
                        accessibilityLabel: "Report Photo",
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
        let authorID = mediaAuthors[selectedMediaID]?.id ?? reportedUserID
        let authorName = mediaAuthors[selectedMediaID]?.displayName ?? reportedUserName
        guard authorID != store.currentUser.id,
              UUID(uuidString: selectedMediaID) != nil
        else {
            return nil
        }
        return CommunityReportSubject(
            kind: .visitPhoto,
            subjectID: selectedMediaID,
            reportedUserID: authorID,
            context: "Report \(authorName)’s Photo From \(placeName)."
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
    @State private var failed = false

    var body: some View {
        ZStack {
            PlaceProfilePhotoImage(photo: media.placePhoto, canonicalPlaceKey: "activity-photo:\(media.id)",
                                   placeName: media.accessibilityLabel,
                                   variant: .profile, contentMode: .fit,
                                   onLoadFailure: { _ in failed = true })
            if failed {
                Label("Photo Unavailable", systemImage: "photo")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(.white)
            }
        }
        .onChange(of: media) { _, _ in failed = false }
    }
}

struct ActivityCommentsRouteScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    let requestID: UUID
    let retry: @MainActor () async -> Void
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (String) -> Void
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            if let route = currentRoute, let groupID = route.sharedVisitGroupID {
                SharedVisitCommentsScreen(activityID: route.activityID, groupID: groupID,
                    openProfile: openProfile, openPlace: openPlace)
            } else if let route = currentRoute, let context = route.context {
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
        .task(id: "\(requestID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase)") {
            // Once resolved, the child rechecks source access without replacing
            // the route and losing its scoped composer during foregrounding.
            guard scenePhase == .active, currentRoute?.context == nil else { return }
            await retry()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .tint(brandMode.accent)
        .toolbarBackground(brandMode.background, for: .navigationBar)
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
        guard let route = currentRoute else { return nil }
        return store.activityEngagementError(for: route.checkInTarget?.visitID ?? route.activityID)
    }

    private var resolutionState: some View {
        VStack(spacing: WanderTheme.spacing4) {
            if resolutionError == nil || isRetrying || ActivitySessionReadiness(auth: auth) == .validating {
                ProgressView("Opening Activity…")
                    .tint(brandMode.accent)
                    .foregroundStyle(brandMode.secondaryText)
            } else {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(brandMode.accentText)

                Text("This Activity Couldn’t Load")
                    .font(AstirTypography.sectionTitle)
                    .foregroundStyle(brandMode.primaryText)

                Text("Check Your Connection And Try Again.")
                    .font(AstirTypography.bodySmall)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(brandMode.secondaryText)

                Button("Try Again") {
                    Task { @MainActor in
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .frame(minWidth: 132, minHeight: 44)
                .background(brandMode.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isRetrying)
            }
        }
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(brandMode.background.ignoresSafeArea())
    }
}

private struct ActivityCommentRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let comment: ActivityComment
    let canLike: Bool
    let isLikePending: Bool
    let onLike: () -> Void
    var onDelete: (() -> Void)?
    var onReport: (() -> Void)?

    init(
        comment: ActivityComment,
        canLike: Bool,
        isLikePending: Bool,
        onLike: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil
    ) {
        self.comment = comment
        self.canLike = canLike
        self.isLikePending = isLikePending
        self.onLike = onLike
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
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.primaryText)
                    Text(FeedPresentation.timestampText(for: comment.createdAt))
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                }

                Text(comment.body)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(comment.author.displayName) Commented: \(comment.body)")
            .opacity(comment.isPending ? 0.58 : 1)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: comment.viewerHasLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                        Text(comment.likeCount.formatted())
                            .font(AstirTypography.metadata)
                            .monospacedDigit()
                    }
                    .foregroundStyle(comment.viewerHasLiked ? brandMode.accent : brandMode.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canLike || isLikePending)
                .opacity(isLikePending ? 0.6 : 1)
                .accessibilityIdentifier("activity.comment.like.\(comment.id)")
                .accessibilityLabel(comment.viewerHasLiked ? "Unlike Comment" : "Like Comment")
                .accessibilityValue(comment.likeCount == 1 ? "1 Like" : "\(comment.likeCount) Likes")
                if onDelete != nil || onReport != nil {
                    Menu {
                        if let onReport {
                            Button(action: onReport) {
                                Label("Report Comment", systemImage: "exclamationmark.bubble")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete Comment", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(brandMode.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Comment Actions")
                    .accessibilityIdentifier("activity.comment.actions.\(comment.id)")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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

/// One page over original discussions. Writes keep the original endpoint/ID;
/// supplemental originals never become synthetic merged comments or counts.
struct SharedVisitCommentsScreen: View {
    @Environment(\.activityPresentationHandoff) private var handoff
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let activityID: String
    let groupID: String
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    @StateObject private var model = SharedVisitDiscussionModel()
    @State private var draft = ""
    @State private var mentions: [PersonMention] = []
    @State private var focused = false
    @State private var posting = false
    @State private var error: String?
    @State private var reportSubject: CommunityReportSubject?
    @State private var retry = 0
    @State private var renderedKey: String?
    @State private var knownVisitIDs: Set<String> = []
    private var membershipKey: String {
        SharedVisitMembershipSnapshot.key(visitIDs: Array(knownVisitIDs), cache: store.sharedVisitCompanionsByVisitID)
    }
    private var accessKey: String {
        "\(activityID):\(store.currentUser.id):\(auth.isSignedIn):\(ActivitySessionReadiness(auth: auth)):\(scenePhase):\(store.presentationRevision):\(retry):\(membershipKey)"
    }

    private func permits(_ post: FeedActivity) -> Bool {
        SharedVisitLocalVisibility.permitsAuthor(authorID: post.actor.id, viewerID: store.currentUser.id,
            blocked: store.isBlockedBetweenCurrentUser(and: post.actor.id),
            muted: store.isMuted(userID: post.actor.id),
            privateProfile: post.actor.isPrivateProfile == true || store.isProfilePrivate(post.actor.id))
    }

    private var permittedCollection: SharedVisitPostCollection? {
        guard let collection = model.collection, let target = collection.commentTarget,
              permits(target) else { return nil }
        return collection
    }

    private func visiblePosts(_ collection: SharedVisitPostCollection) -> [FeedActivity] {
        collection.posts.filter(permits)
    }

    private func visibleComments(_ collection: SharedVisitPostCollection) -> [ActivityComment] {
        let ids = Set(visiblePosts(collection).map(\.id))
        return model.comments.filter {
            SharedVisitLocalVisibility.permitsComment($0, visibleActivityIDs: ids,
                blocked: store.isBlockedBetweenCurrentUser(and: $0.author.id),
                muted: store.isMuted(userID: $0.author.id))
        }
    }

    var body: some View {
        Group {
            if scenePhase == .active, renderedKey == accessKey, let collection = permittedCollection {
                ScrollViewReader { proxy in
                    List {
                        activityHeader(collection)
                            .listRowInsets(EdgeInsets(top: WanderTheme.spacing3, leading: WanderTheme.spacing4,
                                bottom: WanderTheme.spacing2, trailing: WanderTheme.spacing4))
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        if model.isLoading && visibleComments(collection).isEmpty {
                            ProgressView("Loading Comments…")
                                .font(AstirTypography.bodySmall).tint(brandMode.accent)
                                .frame(maxWidth: .infinity, minHeight: 140)
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        } else {
                            ForEach(visibleComments(collection)) { comment in
                                commentRow(comment)
                                    .id(comment.id)
                                    .padding(.horizontal, WanderTheme.spacing4)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            }
                        }
                        if model.hasMore {
                            Button(model.isLoading ? "Loading…" : "Load Earlier Comments") { Task { await loadMore() } }
                                .disabled(model.isLoading).frame(minHeight: 44)
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        }
                        if let error {
                            Text(error).font(AstirTypography.caption).foregroundStyle(WanderTheme.stateError.color)
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .contentMargins(.bottom, WanderTheme.spacing8, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.comments.map(\.id)) { _, ids in
                        guard let newestID = ids.last, focused else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newestID, anchor: .bottom) }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composerInput }
            } else if model.failed || model.collection != nil {
                ContentUnavailableView("Shared Check-In Unavailable", systemImage: "lock",
                    description: Text("The Shared Check-In Couldn’t Be Verified. Try Again When Connected."))
                    .safeAreaInset(edge: .bottom) { Button("Try Again") { retry += 1 }.padding() }
            } else { ProgressView("Opening Shared Check-In…") }
        }
        .background(brandMode.background.ignoresSafeArea())
        .task(id: accessKey) { await reload() }
        .onChange(of: model.collection?.visitIDs ?? []) { _, ids in knownVisitIDs.formUnion(ids) }
        .refreshable { await reload() }
        .onChange(of: store.currentUser.id) { _, _ in draft = ""; mentions = []; posting = false; model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.invalidate() } }
        .onDisappear { model.invalidate() }
        .sheet(item: $reportSubject, onDismiss: { handoff.onDidDismiss(.activityReport) }) { subject in
            WanderRootPresentationLifecycle(surface: .activityReport, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss) {
                CommunityReportSheet(subject: subject).environmentObject(backend)
            }
        }
        .onChange(of: handoff.resetID) { _, resetID in
            guard resetID != nil else { return }
            focused = false; reportSubject = nil
        }
    }

    @ViewBuilder private func activityHeader(_ collection: SharedVisitPostCollection) -> some View {
        if let post = collection.commentTarget, let context = post.activityEngagementContext {
            ActivityPostcardView(context: context, visiblePlace: post.place,
                metadataIcon: post.place.map { categorySymbol(for: $0.effectiveCategory) } ?? "mappin",
                secondaryMetadataTitle: nil, secondaryMetadataAction: nil, secondaryMetadataAccessibilityLabel: nil,
                artworkAction: post.place.map { place in { openPlace(place) } },
                artworkAccessibilityLabel: "Open \(context.placeName)",
                destinationAction: post.place.map { place in { openPlace(place) } },
                destinationAccessibilityLabel: "Open \(context.placeName)",
                openProfile: { openProfile(post.actor) }, actorAccessibilityIdentifier: "comments.activity.actor",
                destinationAccessibilityIdentifier: "comments.activity.place", postcardAccessibilityIdentifier: "comments.activity.postcard",
                showsCommentButton: false, sharedVisitCurrentUserID: store.currentUser.id,
                openSharedVisitProfile: { userID in
                    if let profile = collection.posts.map(\.actor).first(where: { $0.id == userID })
                        ?? collection.companions.first(where: { $0.profile.id == userID })?.profile { openProfile(profile) }
                }, sharedPostCollection: collection, sharedGroupID: groupID)
                .environment(\.activityPostcardVisualStyle, .astir)
        }
    }

    private func commentRow(_ comment: ActivityComment) -> some View {
        ActivityCommentRow(comment: comment,
            canLike: !comment.isPending && !store.isBlockedBetweenCurrentUser(and: comment.author.id),
            isLikePending: model.pendingCommentIDs.contains(comment.id),
            onLike: { updateComment(comment, deleting: false) },
            onDelete: store.canDeleteActivityComment(comment) ? { updateComment(comment, deleting: true) } : nil,
            onReport: comment.author.id == store.currentUser.id ? nil : { presentReport(comment) })
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if store.canDeleteActivityComment(comment) {
                Button(role: .destructive) { updateComment(comment, deleting: true) } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityLabel("Delete Comment")
            } else if comment.author.id != store.currentUser.id {
                Button { presentReport(comment) } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                    .tint(WanderTheme.stateWarning.color).accessibilityLabel("Report Comment")
            }
        }
    }

    private func presentReport(_ comment: ActivityComment) {
        reportSubject = CommunityReportSubject(kind: .comment, subjectID: comment.id,
            reportedUserID: comment.author.id, context: "Report Comment")
    }

    private var composerInput: some View {
        PersonMentionField(text: $draft, mentions: $mentions, focus: $focused,
            placeholder: "Add A Comment…", accessibilityLabel: "Add A Comment",
            accessibilityIdentifier: "activity.comment.input", submitOnReturn: true,
            suggestionPlacement: .aboveInput, onSubmit: post,
            decorateInput: { AnyView(composerRow($0)) })
    }

    private func composerRow(_ input: AnyView) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(brandMode.border)
            HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                WanderAvatar(initials: activityInitials(for: store.currentUser.displayName), avatarURL: store.currentUser.avatarURL,
                    size: 36, color: brandMode.accentWash)
                input.padding(.horizontal, WanderTheme.spacing3).padding(.vertical, 10)
                    .background(brandMode.raisedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border, lineWidth: 1))
                Button(action: post) {
                    Group {
                        if posting { ProgressView().tint(brandMode.accentForeground) }
                        else { Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)) }
                    }
                    .frame(width: 36, height: 36).foregroundStyle(brandMode.accentForeground)
                    .background(brandMode.accent.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: Circle())
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(posting ? "Sending Comment" : "Send Comment")
                .accessibilityIdentifier("activity.comment.send")
                .disabled(posting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1_000)
            }
            .padding(.horizontal, WanderTheme.spacing3).padding(.vertical, WanderTheme.spacing2)
        }
        .background(brandMode.background).accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.comment.composer")
    }

    private func reload() async {
        model.invalidate()
        guard scenePhase == .active, auth.isSignedIn,
              ActivitySessionReadiness(auth: auth) != .validating,
              let repository = backend.activityEngagementRepository else { return }
        let key = accessKey
        renderedKey = key
        await model.load(activityID: activityID, groupID: groupID, repository: repository,
            includeComments: true, isCurrent: { key == accessKey })
        if key == accessKey {
            renderedKey = key
            knownVisitIDs.formUnion(model.collection?.visitIDs ?? [])
        }
    }

    private func loadMore() async {
        guard let repository = backend.activityEngagementRepository else { return }
        let key = accessKey
        await model.loadMore(repository: repository, isCurrent: { key == accessKey })
    }

    private func post() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = permittedCollection?.commentActivityID, !posting, !body.isEmpty, body.count <= 1_000 else { return }
        do { try CommunityContentPolicy.validate(body) } catch { self.error = error.localizedDescription; return }
        let key = accessKey
        posting = true
        Task {
            guard key == accessKey, renderedKey == key, !Task.isCancelled,
                  permittedCollection?.commentActivityID == target else { posting = false; return }
            let success = await store.addActivityComment(activityID: target, body: body, backend: backend)
            guard key == accessKey, !Task.isCancelled else { posting = false; return }
            posting = false
            if success { draft = ""; mentions = []; await reload() }
            else { error = "Your Comment Couldn’t Post. Try Again." }
        }
    }

    private func updateComment(_ comment: ActivityComment, deleting: Bool) {
        guard let repository = backend.activityEngagementRepository,
              let collection = permittedCollection,
              visibleComments(collection).contains(where: { $0.id == comment.id }) else { return }
        let key = accessKey
        Task {
            guard key == accessKey, renderedKey == key, let collection = permittedCollection,
                  visibleComments(collection).contains(where: { $0.id == comment.id }) else { return }
            let success = await model.update(comment, deleting: deleting, repository: repository,
                isCurrent: { key == accessKey })
            guard key == accessKey, !Task.isCancelled else { return }
            if !success { error = "The Comment Couldn’t Update. Try Again." }
            else if !deleting {
                let liked = !comment.viewerHasLiked
                store.productAnalytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.activityCommentLikeChanged,
                    properties: ["is_liked": liked ? "true" : "false", "outcome": "succeeded"]))
                if liked { store.productAnalytics.track(.engagement(need: .connect, action: .activityCommentLiked,
                    surface: "activity_comments", properties: ["outcome": "succeeded"])) }
            }
        }
    }
}
