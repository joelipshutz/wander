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
    var showsCommentButton = true
    var showsWannaButton = true
    var isEngagementEnabled = true
    var resolveContext: (@MainActor () async -> ActivityEngagementContext?)?
    var reportSubjectOverride: CommunityReportSubject?
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

            if context.actor.id != store.currentUser.id, resolvedReportSubject != nil {
                reportMenu
            }

            Spacer(minLength: WanderTheme.spacing3)

            if showsWannaButton {
                bookmarkButton
            }
        }
        .frame(minHeight: 44)
        .alert("Couldn't load this check-in", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Try again in a moment.")
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
        .accessibilityLabel(engagement.viewerHasLiked ? "Unlike activity" : "Like activity")
        .accessibilityValue("\(engagement.likeCount) likes")
    }

    private var commentButton: some View {
        Button {
            auth.requireSignIn(for: .socialActivity) {
                performResolvedAction { resolved in
                    activityNavigation.openComments(context: resolved, visiblePlace: visiblePlace)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(primaryColor)

                Text(engagement.commentCount.formatted())
                    .font(visualStyle == .astir ? AstirTypography.label : .system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryColor)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAttemptEngagement || isResolvingAction)
        .opacity(canAttemptEngagement ? 1 : 0.45)
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
                .foregroundStyle(primaryColor)
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
        if resolveContext != nil || (isEngagementEnabled && activityShareContent != nil) {
            Button {
                performResolvedAction { resolved in
                    guard let presentation = ActivitySharePreviewPresentation(context: resolved) else {
                        actionError = "This check-in is still syncing. Try sharing again in a moment."
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
            .accessibilityHint("Available when this activity finishes loading.")
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
                actionError = "Check your connection and tap the action to try again. If the owner removed this check-in, it will disappear when history refreshes."
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
                        .foregroundStyle(resolvedBookmarkState == .wanna ? accentColor : primaryColor)
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

/// The same contribution section renders inside every activity postcard.
/// Server filtering supplies the entire visible roster; no total-member hint
/// or optimistic pending person is rendered here.
private struct JointCheckInContributionSection: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let projection: JointCheckInProjection
    let profileSubjectUserID: String?
    let openProfile: ((ProfileShell) -> Void)?
    @State private var expanded = false

    private var people: [JointCheckInContribution] { projection.ordered(for: profileSubjectUserID) }
    private var displayed: [JointCheckInContribution] { expanded ? people : Array(people.prefix(3)) }
    private var needsExpansion: Bool { people.count > 3 || people.contains { ($0.note?.count ?? 0) > 180 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { facePile; attribution }
                VStack(alignment: .leading, spacing: 8) { facePile; attribution }
            }
            ForEach(displayed) { person in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        profileName(person.person)
                        Spacer(minLength: 6)
                        if let rating = person.rating {
                            Label(PlaceRating.averageDisplay(rating), systemImage: "star.fill")
                                .font(AstirTypography.label)
                                .foregroundStyle(brand.accentText)
                                .accessibilityLabel("\(person.person.displayName)'s rating: \(PlaceRating.averageDisplay(rating)) out of 5")
                        }
                    }
                    if let note = person.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note)
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brand.primaryText)
                            // Short notes have no expansion control, so never
                            // truncate them at large accessibility text sizes.
                            .lineLimit(expanded || note.count <= 180 ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(person.person.displayName)'s note: \(note)")
                    }
                    if !person.media.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(person.media) { photo in
                                    ActivityPostcardArtwork(visiblePlace: nil, media: [photo], fallbackIcon: "photo", usesAstirPhotoFallback: false)
                                        .frame(width: 76, height: 76)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .accessibilityLabel("Photo by \(person.person.displayName)")
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(brand.primaryText.opacity(0.15)).frame(width: 2)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("joint.contribution.\(person.person.id)")
            }
            if needsExpansion {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack {
                        Text(expanded ? "Show less" : people.count > 3 ? "View all \(people.count) check-ins" : "Read full notes")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(AstirTypography.label)
                    .foregroundStyle(brand.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("joint.expand")
            }
        }
    }

    private var facePile: some View {
        HStack(spacing: -10) {
            ForEach(Array(people.prefix(4))) { person in
                WanderAvatar(initials: activityInitials(for: person.person.displayName),
                    avatarURL: person.person.avatarURL, size: 34, color: WanderTheme.skyTint.color)
                    .overlay(Circle().stroke(brand.background, lineWidth: 2))
                    .accessibilityHidden(true)
            }
            if people.count > 4 {
                Text("+\(people.count - 4)")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brand.primaryText)
                    .frame(width: 34, height: 34)
                    .background(brand.background, in: Circle())
                    .overlay(Circle().stroke(brand.primaryText.opacity(0.2), lineWidth: 1))
                    .accessibilityHidden(true)
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(projection.attribution(for: profileSubjectUserID))
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brand.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(FeedPresentation.timestampText(for: projection.occurredAt))
                .font(AstirTypography.metadata)
                .foregroundStyle(brand.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func profileName(_ person: ProfileShell) -> some View {
        if let openProfile {
            Button { openProfile(person) } label: {
                Text(person.displayName).font(AstirTypography.label).foregroundStyle(brand.primaryText)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(person.displayName)'s profile")
        } else {
            Text(person.displayName).font(AstirTypography.label).foregroundStyle(brand.primaryText)
        }
    }
}

struct ActivityPostcardView: View {
    @Environment(\.activityPostcardVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var astirBrandMode
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
    var openContributorProfile: ((ProfileShell) -> Void)? = nil
    var activityGroup: FeedActivityGroup? = nil
    var openActivityList: ((LocalPlaceList) -> Void)? = nil

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

                if let joint = context.jointCheckIn {
                    JointCheckInContributionSection(projection: joint,
                        profileSubjectUserID: context.profileSubjectUserID,
                        openProfile: openContributorProfile)
                } else {
                    actorAttribution

                    if let note = context.note {
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

                }

                if let activityGroup {
                    FeedActivityDisclosure(group: activityGroup, openList: openActivityList)
                }

                if showsEngagementActions {
                    Divider()
                        .overlay(borderColor)

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
            fallbackIcon: metadataIcon,
            usesAstirPhotoFallback: visualStyle == .astir
        )
    }

    private var ticketBadge: some View {
        Label(context.ticketEyebrow, systemImage: ticketIcon)
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
        case .list: PlaceListSymbol.systemImage
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
            .font(visualStyle == .astir ? AstirTypography.sectionTitle : WanderTypography.editorialTitle)
            .foregroundStyle(primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if context.jointCheckIn == nil, let rating = context.rating {
            Label(PlaceRating.averageDisplay(rating), systemImage: "star.fill")
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
                    .font(visualStyle == .astir ? AstirTypography.bodySmall : .system(size: 14, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)

                Text("\(FeedPresentation.timestampText(for: context.occurredAt)) · someone you follow")
                    .font(visualStyle == .astir ? AstirTypography.metadata : .caption.weight(.medium))
                    .foregroundStyle(secondaryText)
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

    private func activityImage(_ media: ActivityEngagementMedia) -> some View {
        ActivityPostcardMediaImage(media: media)
    }
}

/// The original visit image can be much larger than its 154-point Feed slot.
/// Match the decode to the display and retain the existing local-first fallback.
struct ActivityPostcardImageRequest: Hashable, Sendable {
    let mediaID: String
    let sources: [WanderAvatarImageRequest]

    init?(media: ActivityEngagementMedia, size: CGSize, displayScale: CGFloat) {
        let pixels = max(size.width, size.height) * displayScale
        guard size.width > 0, size.height > 0, displayScale > 0,
              size.width.isFinite, size.height.isFinite, pixels.isFinite else { return nil }
        // Quantization avoids new decodes for fractional layout changes.
        let target = max(64, Int(ceil(min(pixels, 2_048) / 64)) * 64)
        var urls = [URL]()
        if let localURL = VisitPhotoLocalFileStore.fileURL(from: media.localAssetRef) {
            urls.append(localURL)
        }
        if let remoteURL = media.urlString.flatMap(URL.init(string:)), !urls.contains(remoteURL) {
            urls.append(remoteURL)
        }
        let sources = urls.compactMap {
            WanderAvatarImageRequest(avatarURL: $0.absoluteString, targetPixelSize: target)
        }
        guard !sources.isEmpty else { return nil }
        mediaID = media.id
        self.sources = sources
    }
}

enum ActivityPostcardImages {
    // Reuse the proven background decoder and request coalescing. Larger visit
    // thumbnails have their own bounded cache so they cannot evict avatars.
    static let sharedPipeline = WanderAvatarImagePipeline(
        countLimit: 24, totalCostLimit: 48 * 1_024 * 1_024
    )

    static func image(
        for request: ActivityPostcardImageRequest,
        using pipeline: WanderAvatarImagePipeline = sharedPipeline
    ) async -> WanderAvatarDecodedImage? {
        for source in request.sources {
            guard !Task.isCancelled else { return nil }
            if let image = await pipeline.image(for: source) {
                return image
            }
        }
        return nil
    }
}

private struct ActivityPostcardMediaImage: View {
    let media: ActivityEngagementMedia
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedImage?

    private struct LoadedImage {
        let request: ActivityPostcardImageRequest
        let image: UIImage
    }

    var body: some View {
        GeometryReader { proxy in
            let request = ActivityPostcardImageRequest(
                media: media, size: proxy.size, displayScale: displayScale
            )
            ZStack {
                Color.clear
                if let loaded, loaded.request == request {
                    Image(uiImage: loaded.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityLabel(media.accessibilityLabel)
                }
            }
            .task(id: request) {
                guard let request else { loaded = nil; return }
                let image = await ActivityPostcardImages.image(for: request)
                guard !Task.isCancelled else { return }
                loaded = image.map { LoadedImage(request: request, image: $0.image) }
            }
        }
        .clipped()
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

struct ActivityCommentsScreen: View {
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
    @State private var draft = ""
    @State private var restoredDraft = false
    @State private var presentationOwnerID: String?
    @State private var presentedPrivacyRevision: UInt64?
    private var canPresentActivity: Bool {
        isJointAvailable && presentationOwnerID == store.currentUser.id
            && (activeContext.jointCheckIn == nil || presentedPrivacyRevision == store.jointPrivacyRevision)
    }
    @State private var isJointAvailable = true
    @State private var refreshedContext: ActivityEngagementContext?
    private var activeContext: ActivityEngagementContext { refreshedContext ?? context }
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
                if canPresentActivity {
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
                }

                if isLoading, comments.isEmpty {
                    ProgressView("Loading comments…")
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
                        Button("Refresh check-in") {
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
            if canPresentActivity { composer }
        }
        .task(id: "\(activeContext.activityID):\(store.currentUser.id):\(auth.isSignedIn):\(scenePhase):\(store.jointPrivacyRevision)") {
            guard scenePhase == .active else { return }
            if presentationOwnerID == nil { presentationOwnerID = store.currentUser.id }
            guard presentationOwnerID == store.currentUser.id else { return }
            if !restoredDraft {
                draft = store.pendingActivityCommentDrafts.last(where: { $0.ownerUserID == store.currentUser.id && $0.activityID == activeContext.activityID })?.body ?? ""
                restoredDraft = true
            }
            await refreshComments()
        }
        .refreshable { await refreshComments() }
        .onChange(of: store.currentUser.id) { _, _ in
            draft = ""
            refreshedContext = nil
            isJointAvailable = false
            isPosting = false
            isLoading = false
            commentError = "Reopen this activity from your current account."
            clearNestedPresentations()
        }
        .onChange(of: store.jointPrivacyRevision) { _, _ in
            if activeContext.jointCheckIn != nil { isJointAvailable = false }
            isPosting = false
            clearNestedPresentations()
        }
        .fullScreenCover(item: $photoViewerRoute, onDismiss: { handoff.onDidDismiss(.activityPhoto) }) { route in
            WanderRootPresentationLifecycle(
                surface: .activityPhoto, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
            ) {
                ActivityCommentsPhotoViewer(
                    media: activeContext.media,
                    initialMediaID: route.mediaID,
                    reportedUserID: activeContext.actor.id,
                    reportedUserName: activeContext.actor.displayName,
                    placeName: activeContext.placeName
                )
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

    private func clearNestedPresentations() {
        composerFocused = false
        photoViewerRoute = nil
        sharePreviewPresentation = nil
        reportSubject = nil
    }

    @MainActor
    private func refreshComments() async {
        let ownerID = store.currentUser.id
        let privacyRevision = store.jointPrivacyRevision
        guard presentationOwnerID == ownerID else { return }
        isLoading = true
        commentError = nil
        if activeContext.jointCheckIn != nil {
            let refreshed = await store.activity(id: activeContext.activityID, backend: auth.isSignedIn ? backend : nil)
            guard ownerID == store.currentUser.id, privacyRevision == store.jointPrivacyRevision, !Task.isCancelled else { return }
            guard let updated = refreshed?.activityEngagementContext, updated.activityID == activeContext.activityID else {
                isJointAvailable = false
                commentError = "This shared check-in is no longer available. Your draft is kept."
                isLoading = false
                return
            }
            refreshedContext = updated
            presentedPrivacyRevision = privacyRevision
            isJointAvailable = true
        }
        let didRefresh = await store.refreshActivityComments(
            activityID: activeContext.activityID,
            backend: auth.isSignedIn ? backend : nil
        )
        guard ownerID == store.currentUser.id, privacyRevision == store.jointPrivacyRevision, !Task.isCancelled else { return }
        commentError = didRefresh ? nil : "Comments couldn't refresh. Try again."
        isLoading = false
    }

    private var comments: [ActivityComment] {
        canPresentActivity ? store.activityComments(for: activeContext.activityID) : []
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
            context: activeContext,
            visiblePlace: visiblePlace,
            metadataIcon: metadataIcon,
            secondaryMetadataTitle: secondaryListContext?.name,
            secondaryMetadataAction: secondaryMetadataAction,
            secondaryMetadataAccessibilityLabel: secondaryListContext.map { "View list \($0.name)" },
            artworkAction: artworkAction,
            artworkAccessibilityLabel: artworkAccessibilityLabel,
            destinationAction: destinationAction,
            destinationAccessibilityLabel: destinationAccessibilityLabel,
            openProfile: { openProfile(activeContext.actor) },
            actorAccessibilityIdentifier: "comments.activity.actor",
            destinationAccessibilityIdentifier: "comments.activity.place",
            postcardAccessibilityIdentifier: "comments.activity.postcard",
            artworkAccessibilityValue: artworkAccessibilityValue,
            artworkAccessibilityHint: artworkAccessibilityHint,
            showsCommentButton: false,
            onSharePreviewPresentation: { presentation in
                sharePreviewPresentation = presentation
            },
            openContributorProfile: openProfile
        )
    }

    private var metadataIcon: String {
        if let visiblePlace {
            return categorySymbol(for: visiblePlace.effectiveCategory)
        }
        return switch activeContext.ticketKind {
        case .list: PlaceListSymbol.systemImage
        case .saved, .checkIn, .wanna: "mappin"
        }
    }

    private var artworkAction: (() -> Void)? {
        if let firstMediaID = activeContext.media.first?.id {
            return { photoViewerRoute = ActivityCommentsPhotoViewerRoute(mediaID: firstMediaID) }
        }
        return destinationAction
    }

    private var artworkAccessibilityLabel: String? {
        if !activeContext.media.isEmpty {
            return activeContext.media.count == 1 ? "Open activity photo" : "Open activity photos"
        }
        return visiblePlace.map { "Open activity at \($0.place.canonicalName)" }
    }

    private var artworkAccessibilityValue: String? {
        guard !activeContext.media.isEmpty else { return nil }
        return activeContext.media.count == 1 ? "1 photo" : "\(activeContext.media.count) photos"
    }

    private var artworkAccessibilityHint: String? {
        activeContext.media.isEmpty ? nil : "Opens a full-screen photo viewer"
    }

    private var secondaryListContext: ActivityEngagementListContext? {
        guard visiblePlace != nil else { return nil }
        return activeContext.listContext
    }

    private var secondaryMetadataAction: (() -> Void)? {
        guard let listContext = secondaryListContext else { return nil }
        return { openList(listContext.id) }
    }

    private var destinationAccessibilityLabel: String? {
        if let visiblePlace {
            return "Open \(visiblePlace.place.canonicalName)"
        }
        return activeContext.listContext.map { "Open list \($0.name)" }
    }

    private var destinationAction: (() -> Void)? {
        if let visiblePlace {
            return { openPlace(visiblePlace) }
        }
        guard let listContext = activeContext.listContext else { return nil }
        return { openList(listContext.id) }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(brandMode.border)

            if activeContext.jointCheckIn != nil {
                Text(JointCheckInProjection.discussionAudience)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: activityInitials(for: store.currentUser.displayName),
                    avatarURL: store.currentUser.avatarURL,
                    size: 36,
                    color: brandMode.accentWash
                )

                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .accessibilityIdentifier("activity.comment.input")
                    .font(AstirTypography.body)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(post)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.vertical, 10)
                    .background(brandMode.raisedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(brandMode.border, lineWidth: 1)
                    )

                Button(action: post) {
                    Group {
                        if isPosting {
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
                .accessibilityLabel(isPosting ? "Sending comment" : "Send comment")
                .accessibilityIdentifier("activity.comment.send")
                .disabled(normalizedDraft.isEmpty || normalizedDraft.count > 1_000 || isPosting)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
        }
        .background(brandMode.background)
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func post() {
        let body = normalizedDraft
        guard canPresentActivity, !body.isEmpty, body.count <= 1_000, !isPosting else { return }
        let ownerID = store.currentUser.id
        let privacyRevision = store.jointPrivacyRevision
        let activityID = activeContext.activityID
        let jointConsent = activeContext.jointCheckIn != nil
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
            guard ownerID == store.currentUser.id, privacyRevision == store.jointPrivacyRevision else { return }
            let didPost = await store.addActivityComment(
                activityID: activityID,
                body: body,
                jointConsent: jointConsent,
                backend: auth.isSignedIn ? backend : nil
            )
            guard ownerID == store.currentUser.id, privacyRevision == store.jointPrivacyRevision else { return }
            if !didPost {
                if draft.isEmpty { draft = body }
                commentError = store.activityEngagementError(for: activeContext.activityID) ?? "Your comment couldn't post. Try again."
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
                .font(AstirTypography.control)
        }
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(title)
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
        .task(id: "\(requestID):\(store.currentUser.id):\(auth.isSignedIn):\(scenePhase)") {
            guard scenePhase == .active else { return }
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
            if resolutionError == nil || isRetrying {
                ProgressView("Opening activity…")
                    .tint(brandMode.accent)
                    .foregroundStyle(brandMode.secondaryText)
            } else {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(brandMode.accentText)

                Text("This activity couldn’t load")
                    .font(AstirTypography.sectionTitle)
                    .foregroundStyle(brandMode.primaryText)

                Text("Check your connection and try again.")
                    .font(AstirTypography.bodySmall)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(brandMode.secondaryText)

                Button("Try again") {
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
                        .foregroundStyle(brandMode.secondaryText)
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


struct JointCheckInUnavailableCard: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    let visitID: String
    let placeName: String
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(placeName).font(AstirTypography.cardTitle)
            Text("Refresh to view this shared check-in.")
                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
            Button(isRefreshing ? "Refreshing…" : "Refresh") {
                isRefreshing = true
                Task {
                    await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
                    isRefreshing = false
                }
            }
            .disabled(isRefreshing)
            .frame(minHeight: 44)
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .accessibilityIdentifier("joint.unavailable")
    }
}

struct JointCheckInPostcard: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    let projection: JointCheckInProjection
    let visiblePlace: VisiblePlace
    let profileSubjectUserID: String?
    var destinationAction: (() -> Void)? = nil
    var editAction: (() -> Void)? = nil
    @State private var selectedProfileID: String?
    @State private var confirmsDeparture = false
    @State private var departureError: String?

    private var context: ActivityEngagementContext {
        ActivityEngagementContext(activityID: projection.canonicalActivityID,
            actor: projection.ordered(for: profileSubjectUserID).first?.person ?? store.shell(for: visiblePlace.owner),
            placeName: visiblePlace.place.canonicalName,
            placeServerID: visiblePlace.place.serverID ?? visiblePlace.place.id,
            placeDetail: placeDetail(for: visiblePlace),
            status: .been, occurredAt: projection.occurredAt, note: nil, rating: nil,
            media: projection.contributions.flatMap(\.media), jointCheckIn: projection,
            profileSubjectUserID: profileSubjectUserID)
    }

    var body: some View {
        VStack(spacing: 0) {
            ActivityPostcardView(context: context, visiblePlace: visiblePlace, metadataIcon: categorySymbol(for: visiblePlace.effectiveCategory),
                secondaryMetadataTitle: nil, secondaryMetadataAction: nil, secondaryMetadataAccessibilityLabel: nil,
                artworkAction: destinationAction, artworkAccessibilityLabel: "Open place",
                destinationAction: destinationAction, destinationAccessibilityLabel: "Open place",
                openProfile: nil, actorAccessibilityIdentifier: "joint.people",
                destinationAccessibilityIdentifier: "joint.place", postcardAccessibilityIdentifier: "joint.card",
                openContributorProfile: { selectedProfileID = $0.id })
            if let editAction {
                Button("Edit your check-in", action: editAction)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brand.secondaryText)
                    .frame(minHeight: 44)
            }
            if projection.contributions.contains(where: { $0.person.id == store.currentUser.id }) {
                Button(projection.viewerCanManage ? "Close shared check-in" : "Leave shared check-in") {
                    confirmsDeparture = true
                }
                .font(AstirTypography.caption)
                .foregroundStyle(brand.secondaryText)
                .frame(minHeight: 44)
            }
        }
        .alert("Couldn't update this check-in", isPresented: Binding(get: { departureError != nil }, set: { if !$0 { departureError = nil } })) {
            Button("OK") { departureError = nil }
        } message: { Text(departureError ?? "Please refresh and try again.") }
        .confirmationDialog(projection.viewerCanManage ? "Close this shared check-in?" : "Leave this shared check-in?", isPresented: $confirmsDeparture, titleVisibility: .visible) {
            Button(projection.viewerCanManage ? "Close shared check-in" : "Leave shared check-in", role: .destructive) {
                Task {
                    if !(await store.leaveJointCheckIn(projection, backend: backend)) {
                        departureError = store.lastRemoteError ?? "Please refresh and try again."
                    }
                }
            }
        } message: {
            Text(projection.viewerCanManage
                ? "Everyone keeps their own check-in. The shared conversation will close."
                : "Your check-in stays on your map with its own conversation. Comments you've posted stay in the shared conversation unless you delete them.")
        }
        .sheet(isPresented: Binding(get: { selectedProfileID != nil }, set: { if !$0 { selectedProfileID = nil } })) {
            if let selectedProfileID { ProfileDetailView(profileID: selectedProfileID) }
        }
        .task(id: projection.canonicalActivityID) {
            await store.refreshActivityEngagement(activityIDs: [projection.canonicalActivityID], backend: backend)
        }
    }
}
