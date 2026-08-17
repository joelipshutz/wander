@preconcurrency import MapKit
import SwiftUI
import UIKit

enum PlaceProfileInitialSection: Hashable {
    case top
    case activity
}

private enum PlaceProfileScrollAnchor {
    static let activity = "place-profile.activity"
}

struct PlaceProfileMapSurface: View {
    let place: PlaceSheetPlace
    let saves: [PlaceSaveSummary]
    let tasteSaves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let onOpen: () -> Void
    let onAction: () -> Void

    private var presentation: PlaceProfilePresentation {
        PlaceProfilePresenter.presentation(
            placeID: place.id,
            category: place.primaryCategory,
            saves: saves,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID
        )
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            PlaceProfilePreviewCard(
                place: place,
                presentation: presentation,
                saves: saves,
                currentUserID: currentUserID,
                action: action,
                onOpen: onOpen,
                onAction: onAction
            )
            .walkthroughTarget(.mapMemory)
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing3)
        }
    }
}

struct PlaceProfileFullScreen: View {
    private static let edgeSwipeActivationWidth: CGFloat = 28
    private static let edgeSwipeMinimumTranslation: CGFloat = 80
    private static let edgeSwipeMaximumVerticalDrift: CGFloat = 80
    private static let edgeSwipeProjectedTranslation: CGFloat = 160
    private static let minimumFullViewBottomContentInset: CGFloat = 64

    let place: PlaceSheetPlace
    let saves: [PlaceSaveSummary]
    let tasteSaves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let initialSection: PlaceProfileInitialSection
    let usesInteractiveHorizontalDismissal: Bool
    let onBack: () -> Void
    let onAction: () -> Void
    let onFloatingAction: (PlaceProfileSaveAction) -> Void
    @Binding private var attachedSaveContext: MapPlaceSaveContext?
    let attachedSaveDraft: PlaceSaveDraft?
    let onAttachedDraftChange: @MainActor (UUID, PlaceSaveDraftForm, Date?) -> Void
    let onAttachedSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?
    let onAttachedRemove: @MainActor (MapPlaceSaveContext) async -> Bool
    let onAttachedClose: @MainActor () -> Void
    let onAttachedSaveCompleted: @MainActor (SaveResult) -> Void
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @State private var saveActionSnapshot: PlaceProfileSaveActionSnapshot?

    init(
        place: PlaceSheetPlace,
        saves: [PlaceSaveSummary],
        tasteSaves: [PlaceSaveSummary],
        currentUserID: String,
        action: PlaceSheetAction,
        saveActionSnapshot: PlaceProfileSaveActionSnapshot? = nil,
        attachedSaveContext: Binding<MapPlaceSaveContext?> = .constant(nil),
        attachedSaveDraft: PlaceSaveDraft? = nil,
        initialSection: PlaceProfileInitialSection = .top,
        usesInteractiveHorizontalDismissal: Bool = false,
        onBack: @escaping () -> Void,
        onAction: @escaping () -> Void,
        onFloatingAction: ((PlaceProfileSaveAction) -> Void)? = nil,
        onAttachedDraftChange: @escaping @MainActor (UUID, PlaceSaveDraftForm, Date?) -> Void = { _, _, _ in },
        onAttachedSave: @escaping @MainActor (MapPlaceSaveSubmission) async -> SaveResult? = { _ in nil },
        onAttachedRemove: @escaping @MainActor (MapPlaceSaveContext) async -> Bool = { _ in false },
        onAttachedClose: @escaping @MainActor () -> Void = {},
        onAttachedSaveCompleted: @escaping @MainActor (SaveResult) -> Void = { _ in }
    ) {
        self.place = place
        self.saves = saves
        self.tasteSaves = tasteSaves
        self.currentUserID = currentUserID
        self.action = action
        self.initialSection = initialSection
        self.usesInteractiveHorizontalDismissal = usesInteractiveHorizontalDismissal
        self.onBack = onBack
        self.onAction = onAction
        self.onFloatingAction = onFloatingAction ?? { _ in onAction() }
        _attachedSaveContext = attachedSaveContext
        self.attachedSaveDraft = attachedSaveDraft
        self.onAttachedDraftChange = onAttachedDraftChange
        self.onAttachedSave = onAttachedSave
        self.onAttachedRemove = onAttachedRemove
        self.onAttachedClose = onAttachedClose
        self.onAttachedSaveCompleted = onAttachedSaveCompleted
        _saveActionSnapshot = State(initialValue: saveActionSnapshot)
    }

    private var presentation: PlaceProfilePresentation {
        PlaceProfilePresenter.presentation(
            placeID: place.id,
            category: place.primaryCategory,
            saves: saves,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID
        )
    }

    var body: some View {
        Group {
            if usesInteractiveHorizontalDismissal {
                profileContent
            } else {
                profileContent
                    .simultaneousGesture(edgeSwipeBackGesture)
            }
        }
    }

    private var profileContent: some View {
        PlaceProfileFullView(
            place: place,
            presentation: presentation,
            saves: saves,
            currentUserID: currentUserID,
            action: action,
            saveActionSnapshot: saveActionSnapshot,
            attachedSaveContext: $attachedSaveContext,
            attachedSaveDraft: attachedSaveDraft,
            initialSection: initialSection,
            onBack: onBack,
            onAction: onAction,
            onFloatingAction: onFloatingAction,
            onAttachedDraftChange: onAttachedDraftChange,
            onAttachedSave: onAttachedSave,
            onAttachedRemove: onAttachedRemove,
            onAttachedClose: onAttachedClose,
            onAttachedSaveCompleted: onAttachedSaveCompleted
        )
        .preferredColorScheme(.light)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentUserActionState) { _, state in
            guard let snapshot = saveActionSnapshot,
                  snapshot.usesFloatingActions,
                  snapshot.presentation != .empty
            else { return }
            saveActionSnapshot = snapshot.refreshingPresentation(for: state)
        }
    }

    private var currentUserActionState: PlaceProfileSaveActionState {
        PlaceProfileSaveActionPolicy.state(
            saves: saves,
            currentUserID: currentUserID,
            hasSharedVisitInvitation: false,
            isReadOnly: false
        )
    }

    static func shouldTriggerEdgeSwipeBack(startX: CGFloat, translation: CGSize) -> Bool {
        startX <= edgeSwipeActivationWidth
            && translation.width >= edgeSwipeMinimumTranslation
            && abs(translation.height) <= edgeSwipeMaximumVerticalDrift
    }

    static func interactiveEdgeSwipeOffset(
        startX: CGFloat,
        translation: CGSize,
        containerWidth: CGFloat
    ) -> CGFloat? {
        guard startX <= edgeSwipeActivationWidth, containerWidth > 0 else { return nil }
        guard translation.width > 0 else { return 0 }
        guard translation.width >= abs(translation.height) else { return nil }

        return min(translation.width, containerWidth)
    }

    static func shouldCompleteInteractiveEdgeSwipe(
        startX: CGFloat,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard startX <= edgeSwipeActivationWidth,
              translation.width > 0,
              abs(translation.height) <= edgeSwipeMaximumVerticalDrift
        else { return false }

        return translation.width >= edgeSwipeMinimumTranslation
            || (
                predictedEndTranslation.width >= edgeSwipeProjectedTranslation
                    && predictedEndTranslation.width >= abs(predictedEndTranslation.height)
            )
    }

    static func resolvedFullBleedHeaderTopInset(from safeAreaTopInset: CGFloat) -> CGFloat {
        PlaceProfileMapHeader.resolvedTopInset(from: safeAreaTopInset)
    }

    static func resolvedFullViewBottomContentInset(from safeAreaBottomInset: CGFloat) -> CGFloat {
        max(minimumFullViewBottomContentInset, safeAreaBottomInset + WanderTheme.spacing8)
    }

    private var edgeSwipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard !usesInteractiveHorizontalDismissal else { return }
                guard walkthroughs.activeSurface != .placeDetail else { return }
                if Self.shouldTriggerEdgeSwipeBack(
                    startX: value.startLocation.x,
                    translation: value.translation
                ) {
                    onBack()
                }
            }
    }
}

struct PlaceProfileSlideContainer<Content: View>: View {
    let reduceMotion: Bool
    let isGestureDismissEnabled: Bool
    let onDismissed: () -> Void
    let content: Content

    @State private var horizontalOffset: CGFloat = 0
    @State private var isTrackingEdgeSwipe = false
    @State private var isCompletingDismissal = false
    @GestureState private var isEdgeSwipeGestureActive = false

    init(
        reduceMotion: Bool,
        isGestureDismissEnabled: Bool,
        onDismissed: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.reduceMotion = reduceMotion
        self.isGestureDismissEnabled = isGestureDismissEnabled
        self.onDismissed = onDismissed
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(WanderTheme.surfaceBone.color)
                .scrollDisabled(isTrackingEdgeSwipe)
                .offset(x: horizontalOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(edgeSwipeGesture(containerWidth: proxy.size.width))
                .onChange(of: isEdgeSwipeGestureActive) { wasActive, isActive in
                    guard wasActive, !isActive else { return }
                    Task { @MainActor in
                        await Task.yield()
                        guard !isEdgeSwipeGestureActive,
                              isTrackingEdgeSwipe,
                              !isCompletingDismissal
                        else { return }
                        isTrackingEdgeSwipe = false
                        restoreAfterCancelledSwipe()
                    }
                }
        }
    }

    private func edgeSwipeGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($isEdgeSwipeGestureActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                guard isGestureDismissEnabled,
                      !isCompletingDismissal
                else { return }

                if isTrackingEdgeSwipe {
                    horizontalOffset = min(max(value.translation.width, 0), containerWidth)
                    return
                }

                guard value.translation.width > 0,
                      let offset = PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                          startX: value.startLocation.x,
                          translation: value.translation,
                          containerWidth: containerWidth
                      )
                else { return }

                isTrackingEdgeSwipe = true
                horizontalOffset = offset
            }
            .onEnded { value in
                guard !isCompletingDismissal else { return }
                let wasTrackingEdgeSwipe = isTrackingEdgeSwipe
                isTrackingEdgeSwipe = false
                guard isGestureDismissEnabled, wasTrackingEdgeSwipe else {
                    restoreAfterCancelledSwipe()
                    return
                }

                if PlaceProfileFullScreen.shouldCompleteInteractiveEdgeSwipe(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    collapse(containerWidth: containerWidth)
                } else {
                    restoreAfterCancelledSwipe()
                }
            }
    }

    private func restoreAfterCancelledSwipe() {
        guard horizontalOffset > 0 else { return }
        if reduceMotion {
            horizontalOffset = 0
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                horizontalOffset = 0
            }
        }
    }

    private func collapse(containerWidth: CGFloat) {
        guard !isCompletingDismissal else { return }
        isCompletingDismissal = true

        guard !reduceMotion else {
            finishCollapse()
            return
        }

        let dismissalWidth = max(containerWidth, 1)
        withAnimation(.easeOut(duration: 0.22)) {
            horizontalOffset = dismissalWidth
        } completion: {
            guard isCompletingDismissal else { return }
            finishCollapse()
        }
    }

    private func finishCollapse() {
        onDismissed()
        horizontalOffset = 0
        isTrackingEdgeSwipe = false
        isCompletingDismissal = false
    }
}

enum PlaceProfilePreviewPhotoPolicy {
    static func canUseCurrentUserLocalPhoto(
        saves: [PlaceSaveSummary],
        currentUserID: String
    ) -> Bool {
        saves.contains { $0.visiblePlace.owner.id == currentUserID }
    }
}

private struct PlaceProfilePreviewCard: View {
    let place: PlaceSheetPlace
    let presentation: PlaceProfilePresentation
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let onOpen: () -> Void
    let onAction: () -> Void
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @State private var photo: PlacePhoto? = nil
    @State private var failedGooglePhotoID: String?

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                PlaceProfilePhotoThumb(
                    place: place,
                    photo: photo,
                    size: 88,
                    onLoadFailure: handlePhotoLoadFailure
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(place.name)
                        .font(WanderTypography.editorialTitle)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if place.isDroppedPin {
                        droppedPinMetadata
                    } else if let heroMetadata {
                        Text(heroMetadata)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }

                    if let previewSignal {
                        HStack(spacing: WanderTheme.spacing1) {
                            Circle()
                                .fill(ticketAccentColor)
                                .frame(width: 8, height: 8)
                            Text(previewSignal)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                    }

                    if let fitSentence {
                        Text(fitSentence)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(2)
                    }

                    PlaceProfileTagRail(tags: displayTags, compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: WanderTheme.spacing2) {
                    if action != .none {
                        Button(action: onAction) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 17, weight: .black))
                                .frame(width: 44, height: 44)
                                .background(WanderTheme.surfaceRaised.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(ticketAccentColor.opacity(0.82), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.accessibilityLabel)
                    }

                    if let shareURL {
                        WanderShareButton(content: .place(item: shareURL, name: place.name, message: shareText)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .black))
                                .frame(width: 44, height: 44)
                                .background(WanderTheme.surfaceSand.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Share place")
                    }
                }
            }
            .padding(WanderTheme.spacing3)
            .checkInTicketSurface(
                accent: ticketAccentColor,
                surface: WanderTheme.surfaceBone.color.opacity(0.98),
                surroundingSurface: WanderTheme.canvasWarm.color,
                notchEdges: .trailing
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(place.name)")
        .task(id: photoResolutionKey) {
            await resolvePhoto()
        }
    }

    private var localPhoto: PlacePhoto? {
        guard PlaceProfilePreviewPhotoPolicy.canUseCurrentUserLocalPhoto(
            saves: saves,
            currentUserID: currentUserID
        )
        else {
            return nil
        }
        return store.firstVisitPhoto(forPlaceID: place.id).map(PlacePhoto.init(localVisitPhoto:))
    }

    private var photoResolutionKey: String {
        "\(place.photoLookupKey)|\(localPhoto?.providerPlaceID ?? "none")|\(failedGooglePhotoID ?? "ready")"
    }

    private func resolvePhoto() async {
        let resolutionKey = photoResolutionKey
        let localPhoto = localPhoto
        guard !Task.isCancelled, resolutionKey == photoResolutionKey else { return }
        photo = localPhoto
        guard !place.isDroppedPin else { return }
        do {
            let remotePhoto = try await backend.placePhoto(for: place.photoRequest)
            try Task.checkCancellation()
            let resolvedPhoto: PlacePhoto
            if remotePhoto.isGooglePlacesPhoto,
               remotePhoto.providerPlaceID == failedGooglePhotoID {
                resolvedPhoto = try await backend.visibleUserPlacePhoto(for: place.photoRequest)
            } else {
                resolvedPhoto = remotePhoto
            }
            try Task.checkCancellation()
            guard resolutionKey == photoResolutionKey else { return }
            if resolvedPhoto.providerPlaceID != localPhoto?.providerPlaceID {
                photo = resolvedPhoto
            }
            if resolvedPhoto.isGooglePlacesPhoto {
                await store.applyProviderCategoryEnrichment(
                    placeID: place.id,
                    primaryType: resolvedPhoto.providerPrimaryType,
                    types: resolvedPhoto.providerTypes ?? [],
                    backend: backend
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard resolutionKey == photoResolutionKey else { return }
            photo = localPhoto
        }
    }

    private func handlePhotoLoadFailure(_ failedPhoto: PlacePhoto) {
        guard failedPhoto.providerPlaceID == photo?.providerPlaceID else { return }
        if failedPhoto.isGooglePlacesPhoto {
            failedGooglePhotoID = failedPhoto.providerPlaceID
        } else if localPhoto?.providerPlaceID == failedPhoto.providerPlaceID {
            photo = nil
        } else {
            photo = localPhoto
        }
    }

    private var previewSignal: String? {
        if let rating = presentation.overallRating {
            let prefix = socialStatusSignal ?? rating.title
            return "\(prefix) · ★ \(rating.displayScore)"
        }

        if let rating = presentation.ownRating {
            let prefix = ownStatus == .been ? "You checked in" : "You"
            return "\(prefix) · ★ \(rating.displayScore)"
        }

        let names = participantNames(limit: 2)
        if !names.isEmpty {
            return socialStatusSignal
        }

        return nil
    }

    private var ownStatus: PlaceStatus? {
        saves.first { $0.visiblePlace.owner.id == currentUserID }?.visiblePlace.userPlace.status
    }

    private var socialSaves: [PlaceSaveSummary] {
        saves.filter {
            $0.visiblePlace.owner.id != currentUserID
                && !$0.visiblePlace.isCommunityAggregate
        }
    }

    private var ticketAccentColor: Color {
        if ownStatus != nil {
            return WanderTheme.pinYou.color
        }
        if !socialSaves.isEmpty {
            return WanderTheme.pinSocial.color
        }
        return WanderTheme.textInk.color
    }

    private var socialStatusSignal: String? {
        let checkedInNames = socialSaves
            .filter { $0.visiblePlace.userPlace.status == .been }
            .map { firstName(for: $0.visiblePlace.owner) }
            .uniquePreservingOrder()
        let wannaNames = socialSaves
            .filter { $0.visiblePlace.userPlace.status == .wannaGo }
            .map { firstName(for: $0.visiblePlace.owner) }
            .uniquePreservingOrder()

        if !checkedInNames.isEmpty, !wannaNames.isEmpty {
            return "\(checkedInNames.prefix(2).joined(separator: " + ")) checked in · \(wannaNames.prefix(2).joined(separator: " + ")) wanna"
        }
        if !checkedInNames.isEmpty {
            return "\(checkedInNames.prefix(2).joined(separator: " + ")) checked in"
        }
        if !wannaNames.isEmpty {
            return "\(wannaNames.prefix(2).joined(separator: " + ")) wanna"
        }
        return nil
    }

    private var heroMetadata: String? {
        PlaceProfileCopy.heroMetadata(for: place)
    }

    private var droppedPinMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlaceProfileCopy.trimmed(place.locality) ?? "Finding city…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)

            if let coordinates = place.droppedPinCoordinateDisplay {
                Text(coordinates)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = coordinates
                        } label: {
                            Label("Copy coordinates", systemImage: "doc.on.doc")
                        }
                    }
                    .accessibilityIdentifier("map.droppedPinCoordinates")
                    .accessibilityLabel("Coordinates \(coordinates)")
                    .accessibilityHint("Touch and hold to copy")
            }
        }
    }

    private var fitSentence: String? {
        PlaceProfileCopy.fitSentence(place: place, presentation: presentation)
    }

    private var displayTags: [String] {
        PlaceProfileCopy.displayTags(place: place, presentation: presentation)
    }

    private var shareURL: URL? {
        PlaceProfileCopy.shareURL(for: place)
    }

    private var shareText: String {
        PlaceProfileCopy.shareText(for: place)
    }

    private func participantNames(limit: Int) -> [String] {
        saves
            .filter {
                $0.visiblePlace.owner.id != currentUserID
                    && !$0.visiblePlace.isCommunityAggregate
            }
            .map { firstName(for: $0.visiblePlace.owner) }
            .uniquePreservingOrder()
            .prefix(limit)
            .map { $0 }
    }

    private func firstName(for profile: LocalProfile) -> String {
        profile.displayName.components(separatedBy: " ").first ?? profile.displayName
    }
}

private struct PlaceProfileFullView: View {
    let place: PlaceSheetPlace
    let presentation: PlaceProfilePresentation
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let saveActionSnapshot: PlaceProfileSaveActionSnapshot?
    @Binding var attachedSaveContext: MapPlaceSaveContext?
    let attachedSaveDraft: PlaceSaveDraft?
    let initialSection: PlaceProfileInitialSection
    let onBack: () -> Void
    let onAction: () -> Void
    let onFloatingAction: (PlaceProfileSaveAction) -> Void
    let onAttachedDraftChange: @MainActor (UUID, PlaceSaveDraftForm, Date?) -> Void
    let onAttachedSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?
    let onAttachedRemove: @MainActor (MapPlaceSaveContext) async -> Bool
    let onAttachedClose: @MainActor () -> Void
    let onAttachedSaveCompleted: @MainActor (SaveResult) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.placeProfileFloatingActionVariant) private var floatingActionVariant
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @State private var providerPhoto: PlacePhoto?
    @State private var userPhotos: [PlacePhotoGalleryItem] = []
    @State private var galleryCursor: PlacePhotoGalleryCursor?
    @State private var galleryHasMore = true
    @State private var isLoadingGallery = false
    @State private var selectedHeaderPhotoID: String?
    @State private var viewerRoute: PlacePhotoGalleryViewerRoute?
    @State private var discoveredReservationAction: PlaceExternalAction?
    @State private var recoveredBusinessMetadata: PlaceBusinessMetadata?
    @State private var floatingActivityScrollRequest = 0

    private var attachedSaveSheetContext: Binding<MapPlaceSaveContext?> {
        Binding(
            get: { attachedSaveContext },
            set: { nextContext in
                if let nextContext {
                    attachedSaveContext = nextContext
                } else {
                    onAttachedClose()
                }
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let headerTopInset = PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: proxy.safeAreaInsets.top)
            let bottomContentInset = PlaceProfileFullScreen.resolvedFullViewBottomContentInset(from: proxy.safeAreaInsets.bottom)

            VStack(spacing: 0) {
                PlaceProfileMapHeader(
                    place: place,
                    photos: galleryItems,
                    selectedPhotoID: $selectedHeaderPhotoID,
                    topInset: headerTopInset,
                    onOpenPhoto: { photoID in
                        viewerRoute = PlacePhotoGalleryViewerRoute(photoID: photoID)
                    },
                    onNearEnd: loadMoreIfNeeded,
                    onPhotoLoadFailure: handlePhotoLoadFailure
                )

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                            heading

                            if let fitSentence {
                                Text(fitSentence)
                                    .font(.system(size: 19, weight: .black))
                                    .foregroundStyle(WanderTheme.textInk.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            PlaceProfileTagRail(tags: displayTags, compact: false)

                            ratingSection
                                .id(WalkthroughTargetID.placeRatings)
                                .walkthroughTarget(.placeRatings)

                            if !usesFloatingActions, action != .none {
                                primaryPlaceAction
                            }

                            if !actionItems.isEmpty {
                                actionRow
                                    .id(WalkthroughTargetID.placeActions)
                                    .walkthroughTarget(.placeActions)
                            }

                            whyItFitsSection
                            bestForSection
                            VStack(spacing: 0) {
                                PlaceActivitySection(saves: saves, currentUserID: currentUserID)
                                    .id(PlaceProfileScrollAnchor.activity)
                            }
                            .id(WalkthroughTargetID.placeHistory)
                            .walkthroughTarget(.placeHistory)
                            detailsSection
                        }
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.top, WanderTheme.spacing4)
                        .padding(.bottom, bottomContentInset)
                    }
                    .task(id: place.id) {
                        guard initialSection == .activity else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scrollProxy.scrollTo(PlaceProfileScrollAnchor.activity, anchor: .top)
                    }
                    .onChange(of: walkthroughs.currentStep?.target, initial: true) { _, target in
                        scrollToWalkthroughTarget(target, using: scrollProxy)
                    }
                    .onChange(of: floatingActivityScrollRequest) { _, _ in
                        withAnimation(.easeInOut(duration: 0.24)) {
                            scrollProxy.scrollTo(PlaceProfileScrollAnchor.activity, anchor: .top)
                        }
                    }
                }
                .background(WanderTheme.surfaceBone.color)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background(WanderTheme.surfaceBone.color)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WanderTheme.surfaceBone.color)
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if attachedSaveContext == nil, usesFloatingActions, !floatingActions.isEmpty {
                PlaceProfileFloatingActions(
                    actions: floatingActions,
                    variant: floatingActionVariant,
                    onAction: handleFloatingAction
                )
            }
        }
        .sheet(item: attachedSaveSheetContext) { context in
            PlaceSaveAttachedSheet(
                context: context,
                draft: attachedSaveDraft,
                onDraftChange: onAttachedDraftChange,
                onSave: onAttachedSave,
                onRemove: onAttachedRemove,
                onClose: onAttachedClose,
                onSaveCompleted: onAttachedSaveCompleted
            )
            .id(context.id)
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WanderTheme.surfaceBone.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if walkthroughs.activeSurface != .placeDetail {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if !usesFloatingActions, action != .none {
                    Button(action: onAction) {
                        Label(action.accessibilityLabel, systemImage: action.systemImage)
                            .labelStyle(.iconOnly)
                    }
                }

                if let shareURL {
                    WanderShareButton(
                        content: .place(item: shareURL, name: place.name, message: shareText)
                    ) {
                        Label("Share place", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .task(id: place.photoLookupKey) {
            await reloadGallery()
        }
        .task(id: businessActionLookupKey) {
            await resolveBusinessActions()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await reloadVisibleUserPhotos()
            }
        }
        .onChange(of: walkthroughs.requestedSurface, initial: true) { _, requestedSurface in
            guard requestedSurface == .map else { return }
            onBack()
        }
        .fullScreenCover(item: $viewerRoute) { route in
            PlacePhotoGalleryViewer(
                placeName: place.name,
                photos: galleryItems,
                initialPhotoID: route.photoID,
                currentUserID: currentUserID,
                onNearEnd: loadMoreIfNeeded,
                onRefresh: reloadVisibleUserPhotos,
                onPhotoLoadFailure: handlePhotoLoadFailure
            )
        }
    }

    private var usesFloatingActions: Bool {
        saveActionSnapshot?.usesFloatingActions == true
    }

    private var floatingActions: [PlaceProfileSaveAction] {
        saveActionSnapshot?.presentation.actions ?? []
    }

    private func handleFloatingAction(_ action: PlaceProfileSaveAction) {
        if action.kind == .editHistory {
            floatingActivityScrollRequest += 1
            return
        }
        onFloatingAction(action)
    }

    private func scrollToWalkthroughTarget(
        _ target: WalkthroughTargetID?,
        using proxy: ScrollViewProxy
    ) {
        guard walkthroughs.activeSurface == .placeDetail,
              let target,
              [WalkthroughTargetID.placeRatings, .placeActions, .placeHistory].contains(target)
        else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard walkthroughs.currentStep?.target == target else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(target, anchor: target == .placeHistory ? .top : .center)
            }
        }
    }

    private var galleryItems: [PlacePhotoGalleryItem] {
        PlacePhotoGalleryPresenter.items(
            providerPhoto: providerPhoto,
            userPhotos: userPhotos,
            excludingUserPhotoIDs: store.deletedVisitPhotoReferenceIDs
        )
    }

    private func reloadGallery() async {
        if place.id.hasPrefix("walkthrough_place_") {
            providerPhoto = nil
            userPhotos = []
            galleryCursor = nil
            galleryHasMore = false
            return
        }
        guard !isLoadingGallery else { return }
        isLoadingGallery = true

        async let providerResult = resolvedProviderPhoto()
        async let firstPageResult = resolvedUserPhotoPage(after: nil)
        let (resolvedProvider, firstPage) = await (providerResult, firstPageResult)

        guard !Task.isCancelled else {
            isLoadingGallery = false
            return
        }

        providerPhoto = resolvedProvider
        userPhotos = firstPage?.items ?? []
        galleryCursor = firstPage?.nextCursor
        galleryHasMore = firstPage?.hasMore ?? false
        isLoadingGallery = false
        reconcileSelectedPhoto()
    }

    private func reloadVisibleUserPhotos() async {
        guard !isLoadingGallery else { return }
        isLoadingGallery = true
        let firstPage = await resolvedUserPhotoPage(after: nil)
        guard !Task.isCancelled else {
            isLoadingGallery = false
            return
        }
        userPhotos = firstPage?.items ?? []
        galleryCursor = firstPage?.nextCursor
        galleryHasMore = firstPage?.hasMore ?? false
        isLoadingGallery = false
        reconcileSelectedPhoto()
    }

    private func resolvedProviderPhoto() async -> PlacePhoto? {
        do {
            let remotePhoto = try await backend.placePhoto(for: place.photoRequest)
            try Task.checkCancellation()
            if remotePhoto.isGooglePlacesPhoto {
                await store.applyProviderCategoryEnrichment(
                    placeID: place.id,
                    primaryType: remotePhoto.providerPrimaryType,
                    types: remotePhoto.providerTypes ?? [],
                    backend: backend
                )
                return remotePhoto
            }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            WanderDebugLog.remote.debug(
                "place photo unavailable place=\(WanderDebugLog.shortID(place.id), privacy: .public) error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            return nil
        }
    }

    private func resolvedUserPhotoPage(
        after cursor: PlacePhotoGalleryCursor?
    ) async -> PlacePhotoGalleryPage? {
        guard UUID(uuidString: place.id) != nil else { return nil }
        do {
            return try await backend.visiblePlacePhotoGalleryPage(
                placeID: place.id,
                after: cursor
            )
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            WanderDebugLog.remote.debug(
                "place photo gallery unavailable place=\(WanderDebugLog.shortID(place.id), privacy: .public) error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            return nil
        }
    }

    private func loadMoreIfNeeded(_ visiblePhotoID: String) {
        guard galleryHasMore,
              !isLoadingGallery,
              PlacePhotoGalleryPresenter.shouldLoadMore(
                visibleItemID: visiblePhotoID,
                items: galleryItems
              )
        else {
            return
        }

        Task {
            await loadNextUserPhotoPage()
        }
    }

    private func loadNextUserPhotoPage() async {
        guard galleryHasMore, !isLoadingGallery, let galleryCursor else { return }
        isLoadingGallery = true
        let page = await resolvedUserPhotoPage(after: galleryCursor)
        guard !Task.isCancelled else {
            isLoadingGallery = false
            return
        }

        if let page {
            userPhotos = PlacePhotoGalleryPresenter.merging(
                existing: userPhotos,
                incoming: page.items
            )
            self.galleryCursor = page.nextCursor
            galleryHasMore = page.hasMore && !page.items.isEmpty
        } else {
            galleryHasMore = false
        }
        isLoadingGallery = false
        reconcileSelectedPhoto()
    }

    private func handlePhotoLoadFailure(_ failedPhoto: PlacePhoto) {
        if failedPhoto.isGooglePlacesPhoto {
            if providerPhoto?.providerPlaceID == failedPhoto.providerPlaceID {
                providerPhoto = nil
            }
        } else {
            userPhotos.removeAll {
                $0.photo.providerPlaceID == failedPhoto.providerPlaceID
            }
        }
        reconcileSelectedPhoto()
    }

    private func reconcileSelectedPhoto() {
        let ids = Set(galleryItems.map(\.id))
        if let selectedHeaderPhotoID, ids.contains(selectedHeaderPhotoID) {
            return
        }
        selectedHeaderPhotoID = galleryItems.first?.id
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(place.name)
                    .font(WanderTypography.editorialDisplay)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(3)
                    .minimumScaleFactor(0.74)

                if let heroMetadata {
                    Text(heroMetadata)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }

            Spacer(minLength: WanderTheme.spacing3)

            if let status = place.status, action == .addVisit {
                PlaceProfileStatusPill(status: status)
            }
        }
    }

    @ViewBuilder
    private var ratingSection: some View {
        if hasRatingSection {
            PlaceProfileRatingsRail(presentation: presentation)
        } else {
            PlaceProfileSubtleCard(
                text: "Add your rating and tags when this place belongs on your map."
            )
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if walkthroughs.activeSurface == .placeDetail {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(actionItems) { item in
                    walkthroughActionButton(item)
                }
            }
            .padding(.vertical, 1)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(actionItems) { item in
                        standardActionButton(item)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, 1)
            }
            .padding(.horizontal, -WanderTheme.spacing4)
        }
    }

    private func standardActionButton(_ item: PlaceExternalAction) -> some View {
        Button {
            openURL(item.url)
        } label: {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: iconName(for: item.kind))
                    .font(.system(size: 15, weight: .black))
                Text(item.title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
            }
            .frame(width: 136, height: 48)
            .foregroundStyle(WanderTheme.textInk.color)
            .contentShape(Capsule())
            .wanderGlassCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private func walkthroughActionButton(_ item: PlaceExternalAction) -> some View {
        Button {
            openURL(item.url)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: iconName(for: item.kind))
                    .font(.system(size: 14, weight: .black))
                Text(item.title)
                    .font(.system(size: 10, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(WanderTheme.textInk.color)
            .contentShape(Capsule())
            .wanderGlassCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private var primaryPlaceAction: some View {
        Button(action: onAction) {
            Label(primaryActionTitle, systemImage: action.systemImage)
                .font(.system(size: 15, weight: .black))
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.terracotta.color)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryActionTitle)
    }

    private var primaryActionTitle: String {
        action.displayTitle(
            placeName: place.name,
            hasPriorCheckIn: saves.contains { summary in
                summary.visiblePlace.userPlace.userID == currentUserID
                    && summary.visiblePlace.userPlace.status == .been
            }
        )
    }

    @ViewBuilder
    private var whyItFitsSection: some View {
        if hasWhyItFitsEvidence {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                sectionLabel("Why it fits")
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    PlaceProfileFacepile(saves: saves, currentUserID: currentUserID)
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(whyItFitsPrimary)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(whyItFitsSecondary)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceSand.color)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var bestForSection: some View {
        if !displayTags.isEmpty {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                sectionLabel("Best for")
                PlaceProfileWrappingTags(tags: displayTags)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            sectionLabel("Place details")
            VStack(spacing: 0) {
                ForEach(Array(detailRows.enumerated()), id: \.element.id) { index, detail in
                    PlaceProfileDetailRow(title: detail.title, value: detail.value)
                    if index < detailRows.count - 1 {
                        Divider()
                            .overlay(WanderTheme.borderHairline.color.opacity(0.72))
                            .padding(.leading, 88)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }

    private var heroMetadata: String? {
        PlaceProfileCopy.heroMetadata(for: place)
    }

    private var fitSentence: String? {
        PlaceProfileCopy.fitSentence(place: place, presentation: presentation)
    }

    private var displayTags: [String] {
        PlaceProfileCopy.displayTags(place: place, presentation: presentation)
    }

    private var hasWhyItFitsEvidence: Bool {
        !presentation.whyItFits.isEmpty
            || presentation.overallRating != nil
            || presentation.ownRating != nil
            || !displayTags.isEmpty
            || trustedSaves.count >= 2
    }

    private var hasRatingSection: Bool {
        !saves.isEmpty || presentation.fitRating != nil || displayRating != nil
    }

    private var actionItems: [PlaceExternalAction] {
        let resolved = PlaceProfileCopy.actionItems(
            for: place,
            businessMetadata: effectiveBusinessMetadata,
            reservationAction: discoveredReservationAction
        )
        guard walkthroughs.activeSurface == .placeDetail else { return resolved }

        var byKind: [PlaceExternalAction.Kind: PlaceExternalAction] = [:]
        for item in resolved where byKind[item.kind] == nil {
            byKind[item.kind] = item
        }
        for item in walkthroughDisplayActions where byKind[item.kind] == nil {
            byKind[item.kind] = item
        }
        return [
            PlaceExternalAction.Kind.directions,
            .call,
            .website,
            .reserve
        ].compactMap { byKind[$0] }
    }

    private var walkthroughDisplayActions: [PlaceExternalAction] {
        [
            PlaceExternalAction(
                kind: .directions,
                title: "Directions",
                systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                url: URL(string: "https://maps.google.com")!
            ),
            PlaceExternalAction(
                kind: .call,
                title: "Call",
                systemImage: "phone.fill",
                url: URL(string: "tel:+10000000000")!
            ),
            PlaceExternalAction(
                kind: .website,
                title: "Website",
                systemImage: "globe",
                url: URL(string: "https://getrec.me")!
            ),
            PlaceExternalAction(
                kind: .reserve,
                title: "Reservation",
                systemImage: "calendar.badge.plus",
                url: URL(string: "https://getrec.me")!
            )
        ]
    }

    private var storedBusinessMetadata: PlaceBusinessMetadata {
        PlaceBusinessMetadata(
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            timeZoneIdentifier: nil
        )
    }

    private var effectiveBusinessMetadata: PlaceBusinessMetadata {
        guard let recoveredBusinessMetadata else { return storedBusinessMetadata }
        return storedBusinessMetadata.mergingMissingValues(from: recoveredBusinessMetadata)
    }

    private var businessMetadataRequest: PlaceBusinessMetadataRequest {
        PlaceBusinessMetadataRequest(
            placeID: place.id,
            name: place.name,
            address: place.address,
            locality: place.locality,
            region: place.region,
            latitude: place.latitude,
            longitude: place.longitude,
            sourceProvider: place.sourceProvider,
            sourceProviderPlaceID: place.sourceProviderPlaceID
        )
    }

    private var businessActionLookupKey: String {
        [
            businessMetadataRequest.lookupKey,
            place.websiteURLString,
            place.phoneNumber,
            place.actionLinksJSON,
            place.category,
            place.primaryCategory,
            place.subcategory,
            place.rawProviderType
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private var allowsOfficialNatureReservationPageFallback: Bool {
        if place.primaryCategory == WanderPlaceCategory.outdoorsNature {
            return true
        }
        let classification = [place.category, place.subcategory, place.rawProviderType]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return ["campground", "camping", "national park", "state park", "rv park"]
            .contains { classification.contains($0) }
    }

    private func resolveBusinessActions() async {
        discoveredReservationAction = nil
        recoveredBusinessMetadata = nil
        var metadata = storedBusinessMetadata

        if metadata.needsRecovery,
           let recovered = try? await MapKitPlaceBusinessMetadataResolver().resolve(businessMetadataRequest) {
            guard !Task.isCancelled else { return }
            metadata = metadata.mergingMissingValues(from: recovered)
            recoveredBusinessMetadata = metadata
            store.applyProviderBusinessMetadata(placeID: place.id, metadata: metadata)
        }

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: place.actionLinksJSON,
            websiteURLString: metadata.websiteURLString,
            placeName: place.name,
            locality: place.locality,
            region: place.region,
            allowsOfficialReservationPageFallback: allowsOfficialNatureReservationPageFallback
        )
        guard !Task.isCancelled else { return }
        discoveredReservationAction = action
    }

    private var shareURL: URL? {
        PlaceProfileCopy.shareURL(for: place)
    }

    private var shareText: String {
        PlaceProfileCopy.shareText(for: place)
    }

    private var ownSave: PlaceSaveSummary? {
        saves.first { $0.visiblePlace.owner.id == currentUserID }
    }

    private var trustedSaves: [PlaceSaveSummary] {
        saves.filter {
            $0.visiblePlace.owner.id != currentUserID && $0.viewerFollowsOwner
        }
    }

    private var displayRating: PlaceActualRating? {
        presentation.overallRating ?? presentation.ownRating
    }

    private var whyItFitsPrimary: String {
        if let firstReason = presentation.whyItFits.first {
            return firstReason
        }
        if let overallRating = presentation.overallRating {
            if let trustedName = trustedSaves.first?.visiblePlace.owner.displayName.components(separatedBy: " ").first {
                return "\(trustedName) rated this \(overallRating.displayScore)/5."
            }
            return "\(overallRating.subtitle.capitalized) average \(overallRating.displayScore)/5."
        }
        if let ownRating = presentation.ownRating {
            return "You rated this \(ownRating.displayScore)/5."
        }
        if trustedSaves.count >= 2 {
            return "\(trustedSaves.count) people you follow checked in here."
        }
        return "Check in to add your own take."
    }

    private var whyItFitsSecondary: String {
        if presentation.fitRating != nil {
            return "Based on your check-ins and people you follow."
        }
        if presentation.overallRating != nil || presentation.ownRating != nil {
            return "Your map gets more personal with every check-in."
        }
        if displayTags.count >= 2 {
            return "People mention: \(displayTags.prefix(3).joined(separator: ", "))."
        }
        if let category = PlaceProfileCopy.categoryDisplay(for: place) {
            return "Category: \(category)."
        }
        return "Check in to add your own context."
    }

    private var addressLine: String? {
        PlaceProfileCopy.detailsAddress(for: place)
    }

    private var detailRows: [PlaceProfileDetailItem] {
        var rows: [PlaceProfileDetailItem] = []
        if let addressLine {
            rows.append(PlaceProfileDetailItem(title: "Address", value: addressLine))
        }
        if let category = PlaceProfileCopy.categoryDisplay(for: place) {
            rows.append(PlaceProfileDetailItem(title: "Category", value: category.capitalized))
        }
        rows.append(PlaceProfileDetailItem(title: "Source", value: sourceDisplay))
        return rows
    }

    private var sourceDisplay: String {
        if place.websiteURLString != nil || place.phoneNumber != nil {
            return "Map/business search details"
        }
        return "Place on \(AppBrand.displayName)"
    }

    private func iconName(for kind: PlaceExternalAction.Kind) -> String {
        switch kind {
        case .directions:
            "location.fill"
        case .website:
            "globe"
        case .call:
            "phone.fill"
        case .reserve, .reservationSearch:
            "calendar"
        default:
            "link"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(WanderTheme.textMuted.color)
    }
}

enum PlaceProfileFloatingActionVariant: Int, CaseIterable, Equatable {
    case option1 = 1
    case option2 = 2
    case option3 = 3
    case option4 = 4
    case option5 = 5

    static let productionDefault = PlaceProfileFloatingActionVariant.option5
    static let selectionLaunchArgument = "-WanderPlaceActionVariant"

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        storedRawValue: Int? = nil
    ) -> PlaceProfileFloatingActionVariant {
        #if DEBUG
        if let argumentIndex = arguments.firstIndex(of: selectionLaunchArgument) {
            let valueIndex = arguments.index(after: argumentIndex)
            guard arguments.indices.contains(valueIndex),
                  let rawValue = Int(arguments[valueIndex]),
                  let variant = PlaceProfileFloatingActionVariant(rawValue: rawValue) else {
                return productionDefault
            }
            return variant
        }
        #endif

        guard let storedRawValue,
              let variant = PlaceProfileFloatingActionVariant(rawValue: storedRawValue) else {
            return productionDefault
        }
        return variant
    }

    var usesCompactButtons: Bool {
        switch self {
        case .option3, .option4, .option5:
            true
        case .option1, .option2:
            false
        }
    }

    var usesCharcoalRail: Bool {
        self == .option4
    }

    var testerLabel: String {
        switch self {
        case .option1:
            "1 — current"
        case .option2:
            "2 — full-width black"
        case .option3:
            "3 — compact black"
        case .option4:
            "4 — compact dark rail"
        case .option5:
            "5 — selected · compact deep black"
        }
    }
}

struct PlaceProfileFloatingActionDebugPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activeVariant(
        for userID: String,
        isDebugSettingsEntitled: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> PlaceProfileFloatingActionVariant {
        #if DEBUG
        if arguments.contains(PlaceProfileFloatingActionVariant.selectionLaunchArgument) {
            return PlaceProfileFloatingActionVariant.resolved(from: arguments)
        }
        #endif

        guard isDebugSettingsEntitled else { return .productionDefault }
        return storedVariant(for: userID)
    }

    func storedVariant(for userID: String) -> PlaceProfileFloatingActionVariant {
        PlaceProfileFloatingActionVariant.resolved(
            from: [],
            storedRawValue: storedRawValue(for: userID)
        )
    }

    func setVariant(_ variant: PlaceProfileFloatingActionVariant, for userID: String) {
        defaults.set(variant.rawValue, forKey: selectionKey(userID: userID))
    }

    private func storedRawValue(for userID: String) -> Int? {
        let key = selectionKey(userID: userID)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private func selectionKey(userID: String) -> String {
        "wander.debugSettings.\(userID).placeActionVariant"
    }
}

private struct PlaceProfileFloatingActionVariantEnvironmentKey: EnvironmentKey {
    static let defaultValue = PlaceProfileFloatingActionVariant.productionDefault
}

extension EnvironmentValues {
    var placeProfileFloatingActionVariant: PlaceProfileFloatingActionVariant {
        get { self[PlaceProfileFloatingActionVariantEnvironmentKey.self] }
        set { self[PlaceProfileFloatingActionVariantEnvironmentKey.self] = newValue }
    }
}

struct PlaceProfileFloatingActions: View {
    static let minimumActionHeight: CGFloat = 48
    static let compactActionHeight: CGFloat = 60
    static let compactActionFrameWidth: CGFloat = 124
    static let accessibilityCompactActionFrameWidth: CGFloat = 280
    static let compactCornerRadius: CGFloat = 16
    static let charcoalRailCornerRadius: CGFloat = 30

    let actions: [PlaceProfileSaveAction]
    let variant: PlaceProfileFloatingActionVariant
    let onAction: (PlaceProfileSaveAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        actions: [PlaceProfileSaveAction],
        variant: PlaceProfileFloatingActionVariant = .resolved(),
        onAction: @escaping (PlaceProfileSaveAction) -> Void
    ) {
        self.actions = actions
        self.variant = variant
        self.onAction = onAction
    }

    var body: some View {
        actionCluster
        .frame(maxWidth: .infinity)
        .padding(.horizontal, variant.usesCompactButtons ? WanderTheme.spacing6 : WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionCluster: some View {
        if variant.usesCharcoalRail {
            option4InnerActions
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.vertical, WanderTheme.spacing3)
                .wanderGlassRoundedRectangle(
                    tone: .darkOverlay,
                    cornerRadius: Self.charcoalRailCornerRadius,
                    interactive: false,
                    showsBorder: true
                )
        } else {
            actionLayout
        }
    }

    @ViewBuilder
    private var option4InnerActions: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: WanderTheme.spacing2) {
                actionLayout
            }
        } else {
            actionLayout
        }
    }

    @ViewBuilder
    private var actionLayout: some View {
        if usesVerticalLayout {
            VStack(spacing: WanderTheme.spacing2) {
                actionButtons
            }
        } else {
            HStack(spacing: WanderTheme.spacing2) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(actions) { action in
            Button {
                onAction(action)
            } label: {
                if variant.usesCompactButtons {
                    actionLabel(for: action)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: Self.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .wanderGlassRoundedRectangle(
                            tone: Self.glassTone(for: action, variant: variant),
                            cornerRadius: Self.compactCornerRadius,
                            material: variant == .option4 ? .clear : .regular,
                            interactive: true,
                            showsBorder: true
                        )
                } else {
                    actionLabel(for: action)
                        .contentShape(Capsule())
                        .wanderGlassCapsule(
                            tone: Self.glassTone(for: action, variant: variant),
                            interactive: true,
                            showsBorder: true
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-profile.floating-action.\(action.kind.rawValue)")
            .accessibilityLabel(action.title)
            .accessibilityAddTraits(action.isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func actionLabel(for action: PlaceProfileSaveAction) -> some View {
        if variant.usesCompactButtons {
            VStack(spacing: 3) {
                Image(systemName: systemImage(for: action))
                    .accessibilityHidden(true)
                HStack(spacing: WanderTheme.spacing1) {
                    Text(action.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if action.isSelected {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, WanderTheme.spacing1)
            .frame(
                minWidth: compactActionWidth,
                maxWidth: compactActionWidth,
                minHeight: Self.compactActionHeight
            )
            .foregroundStyle(Self.glassTone(for: action, variant: variant).foregroundStyle)
        } else {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: systemImage(for: action))
                    .accessibilityHidden(true)
                Text(action.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if action.isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: Self.minimumActionHeight)
            .padding(.horizontal, WanderTheme.spacing2)
            .foregroundStyle(Self.glassTone(for: action, variant: variant).foregroundStyle)
        }
    }

    private var compactActionWidth: CGFloat {
        return dynamicTypeSize.isAccessibilitySize
            ? Self.accessibilityCompactActionFrameWidth
            : Self.compactActionFrameWidth
    }

    private var usesVerticalLayout: Bool {
        Self.shouldStackActions(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            actionCount: actions.count
        )
    }

    static func shouldStackActions(isAccessibilitySize: Bool, actionCount: Int) -> Bool {
        isAccessibilitySize && actionCount > 1
    }

    static func glassTone(
        for action: PlaceProfileSaveAction,
        variant: PlaceProfileFloatingActionVariant = .productionDefault
    ) -> WanderGlassTone {
        guard action.kind == .checkIn else {
            return variant == .option4 ? .lightAction : .neutral
        }
        switch variant {
        case .option1:
            return .accent
        case .option5:
            return .deepBlackAction
        case .option2, .option3, .option4:
            return .blackAction
        }
    }

    private func systemImage(for action: PlaceProfileSaveAction) -> String {
        switch action.kind {
        case .checkIn:
            "checkmark.circle"
        case .wanna:
            action.isSelected ? "bookmark.fill" : "bookmark"
        case .editHistory:
            "clock.arrow.circlepath"
        }
    }

}

struct PlaceSaveAttachedSheet: View {
    static let compactHeight: CGFloat = 430
    static let compactDetent = PresentationDetent.height(compactHeight)

    let context: MapPlaceSaveContext
    let draft: PlaceSaveDraft?
    let onDraftChange: @MainActor (UUID, PlaceSaveDraftForm, Date?) -> Void
    let onSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?
    let onRemove: @MainActor (MapPlaceSaveContext) async -> Bool
    let onClose: @MainActor () -> Void
    let onSaveCompleted: @MainActor (SaveResult) -> Void
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @EnvironmentObject private var placeSaveDraftStore: PlaceSaveDraftStore
    @State private var selectedDetent = PlaceSaveAttachedSheet.compactDetent

    private var resolvedDraft: PlaceSaveDraft? {
        guard let liveDraft = placeSaveDraftStore.draft,
              liveDraft.candidate.id == context.candidate.id
        else { return draft }
        return liveDraft
    }

    private var selectedStatus: PlaceStatus {
        resolvedDraft?.form.selectedStatus ?? context.initialStatus
    }

    private var trayTitle: String {
        selectedStatus == .wannaGo ? "Wanna" : CheckInCopy.verb
    }

    private var traySystemImage: String {
        selectedStatus == .wannaGo ? "bookmark.fill" : "star.fill"
    }

    private var collapseAccessibilityLabel: String {
        selectedStatus == .wannaGo ? "Collapse Wanna" : "Collapse check-in"
    }

    private var trayAccessibilityIdentifier: String {
        selectedStatus == .wannaGo
            ? "place-profile.attached-wanna"
            : "place-profile.attached-check-in"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WanderTheme.spacing2) {
                Label(trayTitle, systemImage: traySystemImage)
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .accessibilityAddTraits(.isSelected)

                Spacer()

                Button(action: onClose) {
                    Label(collapseAccessibilityLabel, systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .bold))
                        .frame(
                            minWidth: WanderTheme.tapMinimum,
                            minHeight: WanderTheme.tapMinimum
                        )
                        .foregroundStyle(WanderTheme.textInk.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapseAccessibilityLabel)
            }
            .padding(.horizontal, WanderTheme.spacing4)

            Divider()
                .background(WanderTheme.borderHairline.color)

            GeometryReader { proxy in
                MapPlaceSaveEditor(
                    context: context,
                    draft: resolvedDraft,
                    presentation: .attached,
                    onDraftChange: onDraftChange,
                    onSave: onSave,
                    onRemove: onRemove,
                    onClose: onClose,
                    onContentExpansionRequested: expand,
                    onSaveCompleted: onSaveCompleted
                )
                .id(context.id)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WanderTheme.surfaceBone.color)
        .presentationDetents(
            [Self.compactDetent, .large],
            selection: $selectedDetent
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(WanderTheme.radiusSheet)
        .presentationBackground(WanderTheme.surfaceBone.color)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.compactDetent))
        .presentationContentInteraction(.resizes)
        .interactiveDismissDisabled(walkthroughs.activeSurface == .saveFlow)
        .accessibilityIdentifier(trayAccessibilityIdentifier)
    }

    private func expand() {
        withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
            selectedDetent = .large
        }
    }
}

private struct PlacePhotoGalleryViewerRoute: Identifiable {
    let photoID: String

    var id: String { photoID }
}

private struct PlacePhotoContributorProfileRoute: Identifiable {
    let id: String
}

private struct PlacePhotoGalleryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore

    let placeName: String
    let photos: [PlacePhotoGalleryItem]
    let currentUserID: String
    let onNearEnd: (String) -> Void
    let onRefresh: @MainActor () async -> Void
    let onPhotoLoadFailure: (PlacePhoto) -> Void

    @State private var selectedPhotoID: String?
    @State private var selectedProfileRoute: PlacePhotoContributorProfileRoute?
    @State private var reportSubject: CommunityReportSubject?

    init(
        placeName: String,
        photos: [PlacePhotoGalleryItem],
        initialPhotoID: String,
        currentUserID: String,
        onNearEnd: @escaping (String) -> Void,
        onRefresh: @escaping @MainActor () async -> Void,
        onPhotoLoadFailure: @escaping (PlacePhoto) -> Void
    ) {
        self.placeName = placeName
        self.photos = photos
        self.currentUserID = currentUserID
        self.onNearEnd = onNearEnd
        self.onRefresh = onRefresh
        self.onPhotoLoadFailure = onPhotoLoadFailure
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        viewerButton(systemImage: "xmark", action: dismiss.callAsFunction)
                        Spacer()
                        if let selectedItem,
                           let contributor = selectedItem.contributor,
                           contributor.userID != currentUserID {
                            Menu {
                                Button {
                                    presentPhotoReport(item: selectedItem, contributor: contributor)
                                } label: {
                                    Label("Report photo", systemImage: "exclamationmark.bubble")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Photo actions")
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing3)

                    Spacer(minLength: WanderTheme.spacing3)

                    photoPager
                        .frame(
                            height: max(
                                240,
                                min(proxy.size.height * 0.62, 680)
                            )
                        )

                    positionIndicator
                        .frame(minHeight: 44)
                        .padding(.vertical, WanderTheme.spacing2)

                    attributionCard
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.bottom, max(WanderTheme.spacing4, proxy.safeAreaInsets.bottom))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await onRefresh()
            if let selectedPhotoID {
                onNearEnd(selectedPhotoID)
            }
        }
        .onChange(of: selectedPhotoID) { _, photoID in
            if let photoID {
                onNearEnd(photoID)
            }
        }
        .onChange(of: photos.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                dismiss()
                return
            }
            if let selectedPhotoID, ids.contains(selectedPhotoID) {
                return
            }
            selectedPhotoID = ids.first
        }
        .fullScreenCover(item: $selectedProfileRoute) { route in
            ProfileDetailView(profileID: route.id)
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
        }
        .sheet(item: $reportSubject) { subject in
            CommunityReportSheet(subject: subject)
                .environmentObject(backend)
        }
    }

    private var photoPager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(photos) { item in
                        ZoomablePhoto {
                            PlaceProfilePhotoImage(
                                photo: item.photo,
                                placeName: placeName,
                                contentMode: .fit,
                                onLoadFailure: onPhotoLoadFailure
                            )
                        }
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(item.id)
                        .onAppear {
                            onNearEnd(item.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedPhotoID, anchor: .center)
        }
    }

    @ViewBuilder
    private var positionIndicator: some View {
        if photos.count <= 5 {
            HStack(spacing: 10) {
                ForEach(photos) { item in
                    Circle()
                        .fill(item.id == selectedItem?.id ? Color.white : Color.white.opacity(0.34))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel(positionAccessibilityLabel)
        } else if let positionLabel {
            Text(positionLabel)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
                .accessibilityLabel("Photo \(positionLabel)")
        }
    }

    @ViewBuilder
    private var attributionCard: some View {
        if let selectedItem {
            if let contributor = selectedItem.contributor {
                userAttributionCard(item: selectedItem, contributor: contributor)
            } else {
                googleAttributionCard(photo: selectedItem.photo)
            }
        }
    }

    private func userAttributionCard(
        item: PlacePhotoGalleryItem,
        contributor: PlacePhotoContributor
    ) -> some View {
        let displayName = contributor.userID == currentUserID ? "You" : contributor.displayName
        let timestamp = timestampText(item.capturedAt)

        return HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(
                initials: contributor.initials,
                avatarURL: contributor.avatarURLString,
                size: 48,
                color: WanderTheme.pinSocial.color
            )

            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        attributionDisplayName(displayName)

                        if let timestamp {
                            attributionTimestamp(timestamp)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 2) {
                        attributionDisplayName(displayName)

                        if let timestamp {
                            attributionTimestamp(timestamp)
                        }
                    }
                }

                Button {
                    selectedProfileRoute = PlacePhotoContributorProfileRoute(id: contributor.userID)
                } label: {
                    Text("@\(contributor.handle)")
                        .font(.system(size: 14, weight: .bold))
                        .underline()
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(contributor.displayName)'s profile")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: WanderTheme.spacing2)

            if let status = item.status {
                statusPill(status)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func attributionDisplayName(_ displayName: String) -> some View {
        Text(displayName)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func attributionTimestamp(_ timestamp: String) -> some View {
        Text(timestamp)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WanderTheme.textMuted.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func googleAttributionCard(photo: PlacePhoto) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "map.fill")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .frame(width: 48, height: 48)
                .background(WanderTheme.categorySage.color.opacity(0.22))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Google Maps")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)

                if let authorName = photo.authorName, !authorName.isEmpty {
                    Text("Photo by \(authorName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                } else {
                    Text("Place photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }

            Spacer()

            if let sourceURL = photo.sourcePhotoURL {
                Link(destination: sourceURL) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .frame(width: 44, height: 44)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open photo in Google Maps")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func statusPill(_ status: PlaceStatus) -> some View {
        Text(status == .been ? CheckInCopy.noun : "wanna go")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.stateSuccess.color)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(WanderTheme.categorySage.color.opacity(0.24))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private func viewerButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close photo viewer")
    }

    private func presentPhotoReport(
        item: PlacePhotoGalleryItem,
        contributor: PlacePhotoContributor
    ) {
        auth.requireSignIn(for: .reportContent) {
            reportSubject = CommunityReportSubject(
                kind: .visitPhoto,
                subjectID: item.photo.providerPlaceID,
                reportedUserID: contributor.userID,
                context: "Report \(contributor.displayName)’s photo from \(placeName)."
            )
        }
    }

    private var selectedItem: PlacePhotoGalleryItem? {
        if let selectedPhotoID,
           let selected = photos.first(where: { $0.id == selectedPhotoID }) {
            return selected
        }
        return photos.first
    }

    private var positionLabel: String? {
        PlacePhotoGalleryPresenter.positionLabel(
            selectedID: selectedPhotoID,
            items: photos
        )
    }

    private var positionAccessibilityLabel: String {
        guard let positionLabel else { return "Photo viewer" }
        return "Photo \(positionLabel)"
    }

    private func timestampText(_ date: Date?) -> String? {
        date?.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )
    }
}

private struct PlaceProfileMapHeader: View {
    static let minimumFullBleedTopInset: CGFloat = 54

    let place: PlaceSheetPlace
    let photos: [PlacePhotoGalleryItem]
    @Binding var selectedPhotoID: String?
    let topInset: CGFloat
    let onOpenPhoto: (String) -> Void
    let onNearEnd: (String) -> Void
    let onPhotoLoadFailure: (PlacePhoto) -> Void

    var body: some View {
        ZStack {
            mapFallback

            if !photos.isEmpty {
                photoPager
            }

            LinearGradient(
                colors: [
                    WanderTheme.surfaceBone.color.opacity(0.16),
                    WanderTheme.surfaceBone.color.opacity(0.0),
                    WanderTheme.surfaceBone.color.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if let selectedPhoto {
                VStack {
                    Spacer()

                    HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                        photoSource(for: selectedPhoto)
                        Spacer()

                        if let positionLabel {
                            Text(positionLabel)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(Color.black.opacity(0.68))
                                .clipShape(Capsule())
                                .accessibilityLabel("Photo \(positionLabel)")
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing3)
                }
            }

        }
        .frame(height: 214 + topInset)
        .background(WanderTheme.surfaceSand.color)
        .clipped()
    }

    private var photoPager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(photos) { item in
                        Button {
                            onOpenPhoto(item.id)
                        } label: {
                            PlaceProfilePhotoImage(
                                photo: item.photo,
                                placeName: place.name,
                                onLoadFailure: onPhotoLoadFailure
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: item))
                        .id(item.id)
                        .onAppear {
                            onNearEnd(item.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedPhotoID)
        }
    }

    @ViewBuilder
    private func photoSource(for item: PlacePhotoGalleryItem) -> some View {
        if item.isGooglePlacesPhoto {
            PlacePhotoAttribution(photo: item.photo)
        } else if let contributor = item.contributor {
            HStack(spacing: 7) {
                WanderAvatar(
                    initials: contributor.initials,
                    avatarURL: contributor.avatarURLString,
                    size: 24,
                    color: WanderTheme.pinSocial.color
                )
                Text("@\(contributor.handle)")
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .background(Color.black.opacity(0.68))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .accessibilityLabel("Photo by \(contributor.displayName)")
        }
    }

    private var selectedPhoto: PlacePhotoGalleryItem? {
        if let selectedPhotoID,
           let selected = photos.first(where: { $0.id == selectedPhotoID }) {
            return selected
        }
        return photos.first
    }

    private var positionLabel: String? {
        PlacePhotoGalleryPresenter.positionLabel(
            selectedID: selectedPhotoID,
            items: photos
        )
    }

    private func accessibilityLabel(for item: PlacePhotoGalleryItem) -> String {
        if let contributor = item.contributor {
            return "Open place photo by \(contributor.displayName) full screen"
        }
        return "Open Google Maps photo of \(place.name) full screen"
    }

    @ViewBuilder
    private var mapFallback: some View {
        if let latitude = place.latitude, let longitude = place.longitude {
            Map(position: .constant(.region(headerRegion(latitude: latitude, longitude: longitude)))) {
                Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                    PlaceProfileCategoryThumb(emoji: place.categoryEmoji, size: 54)
                        .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: 8, x: 0, y: 4)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .allowsHitTesting(false)
        } else {
            PlaceProfileMapFallback()
        }
    }

    static func resolvedTopInset(from safeAreaTopInset: CGFloat) -> CGFloat {
        max(safeAreaTopInset, minimumFullBleedTopInset)
    }

    private func headerRegion(latitude: Double, longitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }
}

private struct PlacePhotoAttribution: View {
    let photo: PlacePhoto

    var body: some View {
        HStack(spacing: 5) {
            if let authorName = photo.authorName, !authorName.isEmpty {
                if let authorURL = photo.authorProfileURL {
                    Link("Photo by \(authorName)", destination: authorURL)
                } else {
                    Text("Photo by \(authorName)")
                }

                Text("·")
            }

            if let sourceURL = photo.sourcePhotoURL {
                Link("Google Maps", destination: sourceURL)
            } else {
                Text("Google Maps")
            }
        }
        .font(.system(size: 12, weight: .regular))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(minHeight: 44)
        .background(Color.black.opacity(0.68))
        .foregroundStyle(Color.white)
        .tint(Color.white)
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        if let authorName = photo.authorName, !authorName.isEmpty {
            return "Photo by \(authorName) · Google Maps"
        }
        return "Google Maps"
    }

    private var accessibilityLabel: String {
        if photo.sourcePhotoURL != nil {
            return "\(label). Open source photo in Google Maps."
        }
        return label
    }
}

struct PlaceProfilePhotoImage: View {
    let photo: PlacePhoto
    let placeName: String
    var contentMode: ContentMode = .fill
    var onLoadFailure: ((PlacePhoto) -> Void)? = nil
    @EnvironmentObject private var backend: WanderBackend
    @State private var image: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                if let image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                        .accessibilityLabel("Photo of \(placeName)")
                }
            }
        }
        .clipped()
        .task(id: photo) {
            image = nil
            let uiImage: UIImage?
            if let localAssetRef = photo.localAssetRef,
               let localImage = VisitPhotoLocalFileStore.image(from: localAssetRef) {
                uiImage = localImage
            } else if let data = try? await backend.placePhotoImageData(for: photo) {
                uiImage = UIImage(data: data)
            } else {
                uiImage = nil
            }

            guard !Task.isCancelled else { return }
            guard let uiImage else {
                onLoadFailure?(photo)
                return
            }

            withAnimation(.easeOut(duration: 0.24)) {
                image = Image(uiImage: uiImage)
            }
        }
    }
}

private struct PlaceProfilePhotoThumb: View {
    let place: PlaceSheetPlace
    let photo: PlacePhoto?
    let size: CGFloat
    let onLoadFailure: (PlacePhoto) -> Void

    var body: some View {
        ZStack {
            PlaceProfileCategoryThumb(emoji: place.categoryEmoji, size: size)
            if let photo {
                PlaceProfilePhotoImage(
                    photo: photo,
                    placeName: place.name,
                    onLoadFailure: onLoadFailure
                )
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size >= 70 ? 16 : size / 2))

                if photo.isGooglePlacesPhoto {
                    VStack {
                        Spacer()
                        Text("Google Maps")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(Color.black.opacity(0.68))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: size >= 70 ? 16 : size / 2))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PlaceProfileMapFallback: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [WanderTheme.surfaceSand.color, WanderTheme.skyTint.color.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Canvas { context, size in
                    let gridColor = WanderTheme.textInk.color.opacity(0.08)
                    for x in stride(from: 0, through: size.width, by: 42) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(gridColor), lineWidth: 1)
                    }
                    for y in stride(from: 0, through: size.height, by: 42) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(gridColor), lineWidth: 1)
                    }
                }
            )
    }
}

private struct PlaceProfileCategoryThumb: View {
    let emoji: String
    var status: PlaceStatus? = nil
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WanderCategoryEmoji(emoji: emoji, size: max(17, size * 0.34))
                .frame(width: size, height: size)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: size >= 70 ? 16 : size / 2))
                .overlay(
                    RoundedRectangle(cornerRadius: size >= 70 ? 16 : size / 2)
                        .stroke(WanderTheme.surfaceBone.color, lineWidth: size >= 70 ? 0 : 4)
                )

            if let status {
                SavedStatusBadge(status: status, size: max(20, size * 0.25))
                    .offset(x: size >= 70 ? 7 : 5, y: size >= 70 ? -7 : -5)
            }
        }
    }
}

private struct PlaceProfileTagRail: View {
    let tags: [String]
    var compact: Bool

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: compact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: compact ? 12 : 13, weight: .black))
                            .lineLimit(1)
                            .padding(.horizontal, compact ? WanderTheme.spacing2 : WanderTheme.spacing3)
                            .frame(height: compact ? 28 : 34)
                            .background(WanderTheme.surfaceSand.color)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(WanderTheme.borderHairline.color.opacity(compact ? 0 : 1), lineWidth: 1))
                    }
                }
            }
            .scrollClipDisabled(false)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: compact ? 0.80 : 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

private struct PlaceProfileWrappingTags: View {
    let tags: [String]

    var body: some View {
        FlowLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 13, weight: .black))
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(height: 34)
                    .background(WanderTheme.surfaceSand.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows.items {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> LayoutRows {
        var rows: [LayoutRow] = []
        var currentItems: [LayoutItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        let effectiveMaxWidth = max(1, maxWidth)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if nextWidth > effectiveMaxWidth, !currentItems.isEmpty {
                rows.append(LayoutRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            if !currentItems.isEmpty {
                currentWidth += horizontalSpacing
            }
            currentItems.append(LayoutItem(index: index, size: size))
            currentWidth += size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(LayoutRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat(0)) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return LayoutRows(items: rows, width: width, height: height)
    }
}

private struct LayoutRows {
    let items: [LayoutRow]
    let width: CGFloat
    let height: CGFloat
}

private struct LayoutRow {
    let items: [LayoutItem]
    let width: CGFloat
    let height: CGFloat
}

private struct LayoutItem {
    let index: Int
    let size: CGSize
}

private struct PlaceProfileFacepile: View {
    let saves: [PlaceSaveSummary]
    let currentUserID: String

    var body: some View {
        HStack(spacing: -9) {
            if displaySaves.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(WanderTheme.surfaceSand.color, lineWidth: 2))
            } else {
                ForEach(displaySaves) { save in
                    WanderAvatar(
                        initials: save.visiblePlace.owner.id == currentUserID ? "Y" : save.visiblePlace.owner.initials,
                        avatarURL: save.visiblePlace.owner.avatarURL,
                        size: 34,
                        color: color(for: save.visiblePlace.owner)
                    )
                }
            }
        }
        .frame(minWidth: 58, alignment: .leading)
    }

    private var displaySaves: [PlaceSaveSummary] {
        Array(saves.filter { !$0.visiblePlace.isCommunityAggregate }.prefix(3))
    }

    private func color(for owner: LocalProfile) -> Color {
        if owner.id == currentUserID { return WanderTheme.terracotta.color }
        switch owner.handle.lowercased() {
        case "ryan":
            return WanderTheme.avatarRyan.color
        case "andrew":
            return WanderTheme.avatarAndrew.color
        case "sofia", "maya":
            return WanderTheme.avatarSofia.color
        default:
            return WanderTheme.pinSocial.color
        }
    }
}

private struct PlaceProfileSaveCard: View {
    let summary: PlaceSaveSummary
    let currentUserID: String
    let emphasis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: owner.id == currentUserID ? "Y" : owner.initials,
                    avatarURL: owner.avatarURL,
                    size: 34,
                    color: avatarColor
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(owner.id == currentUserID ? "You" : owner.displayName)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(noteSubtitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                if let ratingScore = displayedRatingScore {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(PlaceRating.display(ratingScore)) / 5")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                        Text("rating")
                            .font(.system(size: 10, weight: .black))
                            .textCase(.uppercase)
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                } else {
                    PlaceProfileStatusPill(status: userPlace.status)
                }
            }

            if let note {
                Text("\"\(note)\"")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let tags = facts.map(\.title)
            if !tags.isEmpty {
                PlaceProfileWrappingTags(tags: tags)
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasis ? WanderTheme.surfaceSand.color : WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(emphasis ? WanderTheme.borderStrong.color.opacity(0.58) : WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var owner: LocalProfile {
        summary.visiblePlace.owner
    }

    private var userPlace: LocalUserPlace {
        summary.visiblePlace.userPlace
    }

    private var displayedRatingScore: Double? {
        guard userPlace.status == .been else { return nil }
        return userPlace.ratingScore
    }

    private var note: String? {
        PlaceProfileCopy.trimmed(summary.displayNoteOverride)
            ?? PlaceProfileCopy.trimmed(userPlace.note)
    }

    private var noteSubtitle: String {
        if owner.id == currentUserID {
            return "@you · \(userPlace.visibility.displayTitle.lowercased())"
        }
        return "@\(owner.handle)"
    }

    private var facts: [PlaceFact] {
        var facts: [PlaceFact] = []
        facts.append(PlaceFact(title: userPlace.status.displayTitle, systemImage: "mappin.circle.fill"))
        if userPlace.visibility.showsTileLockIndicator {
            facts.append(PlaceFact(title: "stealth", systemImage: "lock.fill"))
        }
        facts.append(contentsOf: summary.attributes.flatMap(PlaceProfileCopy.attributeFacts(for:)))
        return facts
    }

    private var avatarColor: Color {
        if owner.id == currentUserID { return WanderTheme.terracotta.color }
        return owner.handle.lowercased() == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }
}

private struct PlaceProfileStatusPill: View {
    let status: PlaceStatus

    var body: some View {
        Text(status == .been ? CheckInCopy.noun : "wanna")
            .font(.system(size: 12, weight: .black))
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 30)
            .background(status == .been ? WanderTheme.stateSuccess.color.opacity(0.16) : WanderTheme.sunTint.color)
            .foregroundStyle(status == .been ? WanderTheme.stateSuccess.color : WanderTheme.stateWarning.color)
            .clipShape(Capsule())
    }
}

private struct PlaceProfileSubtleCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WanderTheme.textMuted.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceSand.color.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(WanderTheme.borderStrong.color.opacity(0.72), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }
}

private struct PlaceProfileDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.trailing)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct PlaceProfileDetailItem: Identifiable {
    var id: String { title.lowercased() }
    let title: String
    let value: String
}

private struct PlaceFact: Identifiable {
    var id: String { "\(systemImage)-\(title)" }
    let title: String
    let systemImage: String
}

private enum PlaceProfileCopy {
    static func heroMetadata(for place: PlaceSheetPlace) -> String? {
        joinedText([place.locality, categoryDisplay(for: place)])
    }

    static func detailsAddress(for place: PlaceSheetPlace) -> String? {
        if let address = trimmed(place.address) {
            return address
        }
        return joinedText([place.locality, place.region])
    }

    static func categoryDisplay(for place: PlaceSheetPlace) -> String? {
        let display = place.compactPlaceType
        guard let display = trimmed(display), place.primaryCategory != "place" else { return nil }
        return display
    }

    static func fitSentence(place: PlaceSheetPlace, presentation: PlaceProfilePresentation) -> String? {
        let tags = displayTags(place: place, presentation: presentation).map { $0.lowercased() }
        let questionCategory = WanderPlaceCategory.questionCategory(for: place.categoryAssignment)

        if tags.contains("quiet"),
           questionCategory == "coffee" || tags.contains("coffee"),
           tags.contains(where: { $0.contains("laptop") || $0.contains("wifi") }) {
            return "Good for quiet coffee + laptop time."
        }

        if !tags.isEmpty {
            return "Good for \(phrase(from: Array(tags.prefix(3))))."
        }

        if presentation.fitRating != nil {
            return "Strong fit based on your check-ins."
        }

        if let overallRating = presentation.overallRating {
            return "Trusted rating: \(overallRating.displayScore)/5."
        }

        if let ownRating = presentation.ownRating {
            return "You rated this \(ownRating.displayScore)/5."
        }

        return nil
    }

    static func displayTags(place: PlaceSheetPlace, presentation: PlaceProfilePresentation) -> [String] {
        presentation.commonTags.map(\.title)
    }

    static func actionItems(
        for place: PlaceSheetPlace,
        businessMetadata: PlaceBusinessMetadata? = nil,
        reservationAction: PlaceExternalAction? = nil
    ) -> [PlaceExternalAction] {
        let metadata = businessMetadata ?? PlaceBusinessMetadata(
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            timeZoneIdentifier: nil
        )
        return PlaceExternalLinks.placeProfileActions(
            placeName: place.name,
            latitude: place.latitude,
            longitude: place.longitude,
            websiteURLString: metadata.websiteURLString,
            phoneNumber: metadata.phoneNumber,
            actionLinksJSON: place.actionLinksJSON,
            reservationAction: reservationAction
        )
    }

    static func shareURL(for place: PlaceSheetPlace) -> URL? {
        guard UUID(uuidString: place.id) != nil else { return nil }
        return WanderDeepLinkRoute.sharedPlace(placeID: place.id).url
    }

    static func shareText(for place: PlaceSheetPlace) -> String {
        PlaceExternalLinks.shareSummary(
            placeName: place.name,
            locality: place.locality,
            status: place.status
        )
    }

    static func attributeFacts(for attribute: LocalPlaceAttribute) -> [PlaceFact] {
        PlaceAttributeValuePresentation.strings(from: attribute.valueJSON).map { value in
            PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
        }
    }

    static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func joinedText(_ values: [String?]) -> String? {
        let parts = values.compactMap(trimmed)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func phrase(from tags: [String]) -> String {
        guard !tags.isEmpty else { return "this place" }
        if tags.count == 1 { return tags[0] }
        if tags.count == 2 { return "\(tags[0]) + \(tags[1])" }
        return "\(tags[0]), \(tags[1]) + \(tags[2])"
    }

    private static func icon(for questionKey: String) -> String {
        switch questionKey {
        case "interest_signal", "rating_signal":
            "heart.fill"
        case "work_setup":
            "laptopcomputer"
        case "strenuousness":
            "figure.hiking"
        case "price":
            "dollarsign.circle.fill"
        case "occasion", "best_for":
            "sparkles"
        case PlaceMemoryAttributeKeys.restaurantCuisine:
            "fork.knife"
        default:
            "tag.fill"
        }
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
