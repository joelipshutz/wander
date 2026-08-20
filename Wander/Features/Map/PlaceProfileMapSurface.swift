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
    let viewerLocation: CLLocation?
    let action: PlaceSheetAction
    let onOpen: () -> Void
    let onAction: () -> Void
    let onReady: () -> Void

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
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                PlaceProfilePreviewCard(
                    place: place,
                    presentation: presentation,
                    saves: saves,
                    currentUserID: currentUserID,
                    viewerLocation: viewerLocation,
                    cardWidth: MapChromeLayout.contentWidth(
                        containerWidth: proxy.size.width,
                        safeAreaInsets: proxy.safeAreaInsets
                    ),
                    action: action,
                    onOpen: onOpen,
                    onAction: onAction,
                    onReady: onReady
                )
                .walkthroughTarget(.mapMemory)
                .walkthroughEmphasis(.mapMemory)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        .toolbar(.hidden, for: .navigationBar)
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

struct PlaceProfileVerticalContainer<Content: View>: View {
    let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(WanderTheme.surfaceBone.color)
        }
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
    private static let cardHeight: CGFloat = 232

    let place: PlaceSheetPlace
    let presentation: PlaceProfilePresentation
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    let viewerLocation: CLLocation?
    let cardWidth: CGFloat
    let action: PlaceSheetAction
    let onOpen: () -> Void
    let onAction: () -> Void
    let onReady: () -> Void
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @State private var photo: PlacePhoto? = nil
    @State private var preparedImage: UIImage?
    @State private var isShareSheetPresented = false
    @State private var activeCardAction: PlaceCardPreviewAction?
    @State private var isCardPressed = false
    @State private var cardPressStartedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                cardSurface
                    .scaleEffect(isCardPressed ? 0.975 : 1)
                    .opacity(isCardPressed ? 0.78 : 1)
                    .saturation(isCardPressed ? 0.82 : 1)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.34), .clear, .black.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(isCardPressed ? 1 : 0)
                        .allowsHitTesting(false)
                    }
                    .animation(
                        reduceMotion
                            ? .linear(duration: 0.01)
                            : isCardPressed
                                ? .easeOut(duration: 0.16)
                                : .spring(response: 0.46, dampingFraction: 0.72),
                        value: isCardPressed
                    )
                    .accessibilityHidden(true)
                    .overlay {
                        if ProcessInfo.processInfo.arguments.contains("-WanderMapChromeInsetProbe") {
                            Color.clear
                                .allowsHitTesting(false)
                                .accessibilityElement()
                                .accessibilityIdentifier("map.selectedPlaceCardSurface")
                                .accessibilityHidden(false)
                        }
                    }

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.cardHeight)
                    .contentShape(Rectangle())
                    .gesture(cardPressGesture)
                    .padding(.trailing, 74)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("map.selectedPlaceCard")
                    .accessibilityLabel(cardAccessibilityLabel)
                    .accessibilityHint("Opens the full place page")
                    .accessibilityAction {
                        onOpen()
                    }

                droppedPinCoordinateAccessibilityOverlay

                actionButtonCluster
                    .padding(14)
                    .zIndex(2)
            }
        }
        .frame(width: cardWidth)
        .onAppear(perform: onReady)
        .task(id: photoResolutionKey) {
            await resolvePhoto()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let shareContent {
                WanderShareSheet(content: shareContent) { completed in
                    Task { @MainActor in
                        store.trackPlaceShareCompletion(completed: completed)
                        isShareSheetPresented = false
                    }
                }
            }
        }
    }

    private var cardPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard activeCardAction == nil else {
                    isCardPressed = false
                    return
                }
                if cardPressStartedAt == nil {
                    cardPressStartedAt = Date()
                }
                isCardPressed = hypot(value.translation.width, value.translation.height) < 18
            }
            .onEnded { value in
                let pressDuration = cardPressStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                let translation = hypot(value.translation.width, value.translation.height)
                let shouldOpen = activeCardAction == nil
                    && pressDuration < 0.45
                    && translation < 18
                cardPressStartedAt = nil
                isCardPressed = false
                if shouldOpen {
                    onOpen()
                }
            }
    }

    private var cardSurface: some View {
        cardPhoto
            .frame(width: cardWidth, height: Self.cardHeight)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.58),
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(place.name)
                        .font(WanderTypography.editorialTitle)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.leading)
                        .padding(.trailing, hasCardActions ? 58 : 0)

                    if place.isDroppedPin {
                        droppedPinMetadata
                    } else {
                        Text(place.compactPlaceType)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .accessibilityIdentifier("map.selectedPlaceCategory")
                    }

                    if ratingPresentation != nil || distanceText != nil {
                        PlaceCardRatingDistanceRow(
                            rating: ratingPresentation,
                            distanceText: distanceText
                        )
                    }

                    if let hoursPresentation {
                        PlaceCardHoursBadge(presentation: hoursPresentation)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 0)

                    if isSavedDroppedPin {
                        Text("Saved from a dropped pin")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .accessibilityIdentifier("map.selectedPlaceDroppedPinSource")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var droppedPinCoordinateAccessibilityOverlay: some View {
        if place.isDroppedPin, let coordinates = place.droppedPinCoordinateDisplay {
            VStack(alignment: .leading, spacing: 7) {
                Text(place.name)
                    .font(WanderTypography.editorialTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .padding(.trailing, hasCardActions ? 58 : 0)
                    .hidden()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(PlaceProfileCopy.trimmed(place.locality) ?? "Finding city…")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .hidden()
                        .allowsHitTesting(false)

                    Text(coordinates)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.clear)
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionButtonCluster: some View {
        ZStack {
            WanderGlassButtonCluster(mergeSpacing: 0) {
                actionButtons
            }

            actionButtonGlyphs
                .allowsHitTesting(false)
                .zIndex(3)
        }
    }

    private var actionButtonGlyphs: some View {
        VStack(spacing: 4) {
            if action != .none {
                actionButtonGlyph(systemName: action.systemImage, size: 17)
            }

            if shareContent != nil {
                actionButtonGlyph(systemName: "square.and.arrow.up", size: 16)
            }
        }
    }

    private func actionButtonGlyph(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .black))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white)
            .opacity(1)
            .frame(width: 44, height: 44, alignment: .center)
    }

    private var actionButtons: some View {
        VStack(spacing: 4) {
            if action != .none {
                Button {
                    activeCardAction = .primary
                    onAction()
                } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 17, weight: .black))
                }
                .buttonStyle(
                    PlaceCardGlassActionButtonStyle(
                        actionID: .primary,
                        activeAction: $activeCardAction
                    )
                )
                .accessibilityIdentifier("map.selectedPlaceAction")
                .accessibilityLabel(action.accessibilityLabel)
            }

            if shareContent != nil {
                Button {
                    activeCardAction = .share
                    isShareSheetPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .black))
                }
                .buttonStyle(
                    PlaceCardGlassActionButtonStyle(
                        actionID: .share,
                        activeAction: $activeCardAction
                    )
                )
                .accessibilityIdentifier("map.selectedPlaceShare")
                .accessibilityLabel("Share place")
            }
        }
    }

    @ViewBuilder
    private var cardPhoto: some View {
        ZStack {
            if place.isDroppedPin {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        colors: [
                            WanderTheme.terracottaDark.color,
                            WanderTheme.textInk.color,
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 112, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.13))
                        .padding(.trailing, 20)
                        .padding(.bottom, 14)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LinearGradient(
                    colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                PlaceProfileCategoryThumb(emoji: place.categoryEmoji, size: 72)
            }

            if let preparedImage {
                Image(uiImage: preparedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityLabel("Photo of \(place.name)")
            }
        }
    }

    private var isSavedDroppedPin: Bool {
        place.isDroppedPin && !saves.isEmpty
    }

    private var hasCardActions: Bool {
        action != .none || shareContent != nil
    }

    private var shareContent: WanderShareContent? {
        guard let shareURL else { return nil }
        return .place(
            item: shareURL,
            name: place.name,
            message: PlaceProfileCopy.shareText(for: place)
        )
    }

    private var shareURL: URL? {
        if let deepLink = PlaceProfileCopy.shareURL(for: place) {
            return deepLink
        }
        guard let latitude = place.latitude,
              let longitude = place.longitude
        else { return nil }
        return PlaceExternalLinks.directionsAction(
            placeName: place.name,
            latitude: latitude,
            longitude: longitude
        )?.url
    }

    private var ratingPresentation: PlaceCardRatingPresentation? {
        PlaceCardPresentation.rating(
            providerScore: photo?.providerRating,
            providerCount: photo?.providerUserRatingCount,
            recmeRating: presentation.overallRating ?? presentation.ownRating,
            providerName: photo?.provider
        )
    }

    private var distanceText: String? {
        PlaceCardPresentation.distanceText(
            viewerLocation: viewerLocation,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    private var hoursPresentation: PlaceCardHoursPresentation? {
        PlaceCardPresentation.hours(
            isOpen: photo?.providerOpenNow,
            nextOpenTimeString: photo?.providerNextOpenTimeString,
            nextCloseTimeString: photo?.providerNextCloseTimeString,
            utcOffsetMinutes: photo?.providerUTCOffsetMinutes
        )
    }

    private var cardAccessibilityLabel: String {
        [
            place.name,
            place.compactPlaceType,
            ratingPresentation.map { "Rated \($0.scoreText) out of 5" },
            distanceText,
            hoursPresentation.map { [$0.statusText, $0.detailText].compactMap { $0 }.joined(separator: ", ") }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private var droppedPinMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlaceProfileCopy.trimmed(place.locality) ?? "Finding city…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            if let coordinates = place.droppedPinCoordinateDisplay {
                Text(coordinates)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
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
        "\(place.photoLookupKey)|\(localPhoto?.providerPlaceID ?? "none")"
    }

    private func resolvePhoto() async {
        let resolutionKey = photoResolutionKey
        let localPhoto = localPhoto
        guard !Task.isCancelled, resolutionKey == photoResolutionKey else { return }

        photo = nil
        preparedImage = nil

        if place.isDroppedPin {
            let didPreparePhoto = await prepareCard(using: localPhoto, resolutionKey: resolutionKey)
            if !didPreparePhoto, !Task.isCancelled, resolutionKey == photoResolutionKey {
                onReady()
            }
            return
        }

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
            }

            if await prepareCard(using: remotePhoto, resolutionKey: resolutionKey) {
                return
            }

            if remotePhoto.isGooglePlacesPhoto {
                let visibleUserPhoto = try await backend.visibleUserPlacePhoto(for: place.photoRequest)
                if await prepareCard(using: visibleUserPhoto, resolutionKey: resolutionKey) {
                    return
                }
            }

            await prepareCard(using: localPhoto, resolutionKey: resolutionKey)
        } catch is CancellationError {
            return
        } catch {
            await prepareCard(using: localPhoto, resolutionKey: resolutionKey)
        }
    }

    @discardableResult
    private func prepareCard(using candidate: PlacePhoto?, resolutionKey: String) async -> Bool {
        guard let candidate,
              let image = await preparedImage(for: candidate),
              !Task.isCancelled,
              resolutionKey == photoResolutionKey
        else { return false }

        photo = candidate
        preparedImage = image
        await Task.yield()
        guard !Task.isCancelled, resolutionKey == photoResolutionKey else { return false }
        onReady()
        return true
    }

    private func preparedImage(for photo: PlacePhoto) async -> UIImage? {
        let data: Data?
        if let localAssetRef = photo.localAssetRef,
           let localData = await Task.detached(priority: .utility, operation: {
               VisitPhotoLocalFileStore.data(from: localAssetRef)
           }).value {
            data = localData
        } else {
            data = try? await backend.placePhotoImageData(for: photo)
        }

        guard !Task.isCancelled, let data else { return nil }
        let targetPixelSize = max(
            1,
            Int(ceil(430 * displayScale))
        )
        return await PlacePhotoImagePipeline.shared.image(
            from: data,
            photoKey: photo.cacheKey,
            targetPixelSize: targetPixelSize
        )?.image
    }

}

private enum PlaceCardPreviewAction: Hashable {
    case primary
    case share
}

private struct PlaceCardGlassActionButtonStyle: ButtonStyle {
    let actionID: PlaceCardPreviewAction
    @Binding var activeAction: PlaceCardPreviewAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    configuration.isPressed
                        ? WanderTheme.terracotta.color.opacity(0.18)
                        : Color.clear
                )
                .frame(width: 44, height: 44)
                .wanderGlassRoundedRectangle(
                    tone: configuration.isPressed ? .accent : .darkOverlay,
                    cornerRadius: 15,
                    material: .clear,
                    interactive: true,
                    showsBorder: false
                )
                .shadow(
                    color: configuration.isPressed
                        ? WanderTheme.terracotta.color.opacity(0.96)
                        : Color.black.opacity(0.22),
                    radius: configuration.isPressed ? 20 : 7,
                    x: 0,
                    y: configuration.isPressed ? 0 : 4
                )
                .scaleEffect(
                    configuration.isPressed && !reduceMotion ? 1.3 : 1,
                    anchor: .center
                )

            configuration.label
                .opacity(0.001)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44, alignment: .center)
                .zIndex(2)
        }
        .frame(width: 44, height: 44, alignment: .center)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .zIndex(configuration.isPressed ? 1 : 0)
        .onChange(of: configuration.isPressed, initial: true) { _, isPressed in
            if isPressed {
                activeAction = actionID
            } else if activeAction == actionID {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(160))
                    if activeAction == actionID {
                        activeAction = nil
                    }
                }
            }
        }
        .onDisappear {
            if activeAction == actionID {
                activeAction = nil
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.68),
            value: configuration.isPressed
        )
    }
}

private struct PlaceCardRatingDistanceRow: View {
    let rating: PlaceCardRatingPresentation?
    let distanceText: String?

    var body: some View {
        HStack(spacing: 6) {
            if let rating {
                Text(rating.scoreText)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityIdentifier("map.selectedPlaceRating")

                HStack(spacing: 1) {
                    ForEach(0 ..< 5, id: \.self) { index in
                        Image(systemName: starSymbol(index: index, score: rating.score))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    }
                }

                if let count = rating.count {
                    Text("(\(count))")
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let providerName = rating.providerDisplayName {
                    PlaceCardProviderRatingBadge(providerName: providerName)
                }
            }

            if rating != nil, distanceText != nil {
                Text("·")
                    .foregroundStyle(.white.opacity(0.76))
            }

            if let distanceText {
                Text(distanceText)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.34), radius: 2, x: 0, y: 1)
    }

    private func starSymbol(index: Int, score: Double) -> String {
        let remainder = score - Double(index)
        if remainder >= 0.75 { return "star.fill" }
        if remainder >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

private struct PlaceCardProviderRatingBadge: View {
    let providerName: String

    var body: some View {
        Group {
            switch providerName {
            case "Yelp":
                HStack(spacing: 2) {
                    Image(systemName: "burst.fill")
                    Text("Yelp")
                }
                .foregroundStyle(Color(red: 0.84, green: 0.12, blue: 0.16))
            case "Google Maps":
                Image("BrandGoogleMaps")
                    .resizable()
                    .scaledToFit()
            case "Apple Maps":
                Image(systemName: "apple.logo")
                    .foregroundStyle(.white)
            default:
                Image(systemName: "building.2.crop.circle")
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .font(.system(size: 10, weight: .bold))
        .frame(maxWidth: 34, maxHeight: 14)
        .accessibilityLabel("\(providerName) rating")
        .accessibilityIdentifier("map.selectedPlaceRatingProvider")
    }
}

private struct PlaceCardHoursBadge: View {
    let presentation: PlaceCardHoursPresentation

    private var tint: Color {
        presentation.isOpen ? WanderTheme.stateSuccess.color : WanderTheme.stateError.color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(presentation.statusText)
                .fontWeight(.bold)
                .accessibilityIdentifier("map.selectedPlaceHoursStatus")

            if let detailText = presentation.detailText {
                Text("·")
                    .opacity(0.7)
                Text(detailText)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.24))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.58), lineWidth: 1)
        }
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
            .overlay(alignment: .top) {
                headerNavigationControls(topInset: headerTopInset)
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
        .task(id: place.photoLookupKey) {
            await reloadProviderPhoto()
        }
        .task(id: place.id) {
            await reloadVisibleUserPhotos()
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
            guard requestedSurface == .map || requestedSurface == .feed else { return }
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

    private func headerNavigationControls(topInset: CGFloat) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            if walkthroughs.activeSurface != .placeDetail {
                Button(action: onBack) {
                    headerNavigationLabel(systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("place-profile.back")
            }

            Spacer(minLength: 0)

            if let shareURL {
                WanderShareButton(
                    content: .place(item: shareURL, name: place.name, message: shareText)
                ) {
                    headerNavigationLabel(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share place")
                .accessibilityIdentifier("place-profile.share")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.top, topInset)
    }

    private func headerNavigationLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .foregroundStyle(WanderTheme.terracotta.color)
            .contentShape(Circle())
            .wanderGlassCapsule(tone: .lightAction, interactive: true)
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

    private func reloadProviderPhoto() async {
        if place.id.hasPrefix("walkthrough_place_") {
            providerPhoto = nil
            reconcileSelectedPhoto()
            return
        }

        providerPhoto = nil
        let resolvedProvider = await resolvedProviderPhoto()
        guard !Task.isCancelled else { return }
        providerPhoto = resolvedProvider
        reconcileSelectedPhoto()
    }

    private func reloadVisibleUserPhotos() async {
        if place.id.hasPrefix("walkthrough_place_") {
            userPhotos = []
            galleryCursor = nil
            galleryHasMore = false
            isLoadingGallery = false
            reconcileSelectedPhoto()
            return
        }
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
            WanderGlassButtonCluster {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(actionItems) { item in
                        walkthroughActionButton(item)
                    }
                }
            }
            .padding(.vertical, 1)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                WanderGlassButtonCluster {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(actionItems) { item in
                            standardActionButton(item)
                        }
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

    private var displayTags: [String] {
        PlaceProfileCopy.displayTags(presentation: presentation)
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

    private var displayRating: PlaceActualRating? {
        presentation.overallRating ?? presentation.ownRating
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
            clusteredActionLayout
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.vertical, WanderTheme.spacing3)
                .wanderGlassRoundedRectangle(
                    tone: .darkOverlay,
                    cornerRadius: Self.charcoalRailCornerRadius,
                    interactive: false,
                    showsBorder: true
                )
        } else {
            clusteredActionLayout
        }
    }

    private var clusteredActionLayout: some View {
        WanderGlassButtonCluster {
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
                    if let authorURL = photo.authorProfileURL {
                        Link("Photo by \(authorName)", destination: authorURL)
                            .underline()
                    } else {
                        Text("Photo by \(authorName)")
                    }
                } else {
                    Text("Place photo")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WanderTheme.textMuted.color)

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
        if let contributor = item.contributor {
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
        return "Open place photo of \(place.name) full screen"
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

struct PlaceProfilePhotoImage: View {
    let photo: PlacePhoto
    let placeName: String
    var contentMode: ContentMode = .fill
    var onLoadFailure: ((PlacePhoto) -> Void)? = nil
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?

    var body: some View {
        GeometryReader { proxy in
            let targetPixelSize = max(
                1,
                Int(ceil(max(proxy.size.width, proxy.size.height) * displayScale))
            )
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
            .task(id: "\(photo.cacheKey)|target-px:\(targetPixelSize)") {
                await loadImage(targetPixelSize: targetPixelSize)
            }
        }
        .clipped()
    }

    private func loadImage(targetPixelSize: Int) async {
        image = nil
        let data: Data?
        if let localAssetRef = photo.localAssetRef,
           let localData = await Task.detached(priority: .utility, operation: {
               VisitPhotoLocalFileStore.data(from: localAssetRef)
           }).value {
            data = localData
        } else {
            data = try? await backend.placePhotoImageData(for: photo)
        }

        guard !Task.isCancelled,
              let data,
              let decodedImage = await PlacePhotoImagePipeline.shared.image(
                  from: data,
                  photoKey: photo.cacheKey,
                  targetPixelSize: targetPixelSize
              ),
              !Task.isCancelled
        else {
            if !Task.isCancelled {
                onLoadFailure?(photo)
            }
            return
        }

        withAnimation(.easeOut(duration: 0.10)) {
            image = Image(uiImage: decodedImage.image)
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

    static func displayTags(presentation: PlaceProfilePresentation) -> [String] {
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
