@preconcurrency import MapKit
import SwiftUI
import UIKit

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
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing3)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct PlaceProfileFullScreen: View {
    private static let edgeSwipeActivationWidth: CGFloat = 28
    private static let edgeSwipeMinimumTranslation: CGFloat = 80
    private static let edgeSwipeMaximumVerticalDrift: CGFloat = 80
    private static let minimumFullViewBottomContentInset: CGFloat = 64

    let place: PlaceSheetPlace
    let saves: [PlaceSaveSummary]
    let tasteSaves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let onBack: () -> Void
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
        PlaceProfileFullView(
            place: place,
            presentation: presentation,
            saves: saves,
            currentUserID: currentUserID,
            action: action,
            onBack: onBack,
            onAction: onAction
        )
        .preferredColorScheme(.light)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .simultaneousGesture(edgeSwipeBackGesture)
    }

    static func shouldTriggerEdgeSwipeBack(startX: CGFloat, translation: CGSize) -> Bool {
        startX <= edgeSwipeActivationWidth
            && translation.width >= edgeSwipeMinimumTranslation
            && abs(translation.height) <= edgeSwipeMaximumVerticalDrift
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
                if Self.shouldTriggerEdgeSwipeBack(
                    startX: value.startLocation.x,
                    translation: value.translation
                ) {
                    onBack()
                }
            }
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
                    size: 82,
                    onLoadFailure: handlePhotoLoadFailure
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    if let previewSignal {
                        HStack(spacing: WanderTheme.spacing1) {
                            Circle()
                                .fill(WanderTheme.pinSocial.color)
                                .frame(width: 8, height: 8)
                            Text(previewSignal)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                    }

                    Text(place.name)
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if let heroMetadata {
                        Text(heroMetadata)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
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
                                .frame(width: 36, height: 36)
                                .background(action.isPrimaryAction ? WanderTheme.textInk.color : WanderTheme.terracotta.color)
                                .foregroundStyle(WanderTheme.textOnAction.color)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.accessibilityLabel)
                    }

                    if let shareURL {
                        WanderShareButton(content: .place(item: shareURL, name: place.name, message: shareText)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .black))
                                .frame(width: 36, height: 36)
                                .background(WanderTheme.surfaceSand.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Share place")
                    }
                }
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 26, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(place.name)")
        .task(id: photoResolutionKey) {
            await resolvePhoto()
        }
    }

    private var localPhoto: PlacePhoto? {
        store.firstVisitPhoto(forPlaceID: place.id).map(PlacePhoto.init(localVisitPhoto:))
    }

    private var photoResolutionKey: String {
        "\(place.photoLookupKey)|\(localPhoto?.providerPlaceID ?? "none")|\(failedGooglePhotoID ?? "ready")"
    }

    private func resolvePhoto() async {
        let resolutionKey = photoResolutionKey
        let localPhoto = localPhoto
        guard !Task.isCancelled, resolutionKey == photoResolutionKey else { return }
        photo = localPhoto
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
            let names = participantNames(limit: 2)
            let prefix = names.isEmpty ? rating.title : names.joined(separator: " + ")
            return "\(prefix) · ★ \(rating.displayScore)"
        }

        if let rating = presentation.ownRating {
            return "You · ★ \(rating.displayScore)"
        }

        let names = participantNames(limit: 2)
        if !names.isEmpty {
            return "\(names.joined(separator: " + ")) saved this"
        }

        return nil
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

    private var shareURL: URL? {
        PlaceProfileCopy.shareURL(for: place)
    }

    private var shareText: String {
        PlaceProfileCopy.shareText(for: place)
    }

    private func participantNames(limit: Int) -> [String] {
        saves
            .filter { $0.visiblePlace.owner.id != currentUserID }
            .map { $0.visiblePlace.owner.id == currentUserID ? "You" : $0.visiblePlace.owner.displayName.components(separatedBy: " ").first ?? $0.visiblePlace.owner.displayName }
            .uniquePreservingOrder()
            .prefix(limit)
            .map { $0 }
    }
}

private struct PlaceProfileFullView: View {
    let place: PlaceSheetPlace
    let presentation: PlaceProfilePresentation
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    let onBack: () -> Void
    let onAction: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @State private var photo: PlacePhoto?
    @State private var failedGooglePhotoID: String?

    var body: some View {
        GeometryReader { proxy in
            let headerTopInset = PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: proxy.safeAreaInsets.top)
            let bottomContentInset = PlaceProfileFullScreen.resolvedFullViewBottomContentInset(from: proxy.safeAreaInsets.bottom)

            VStack(spacing: 0) {
                PlaceProfileMapHeader(
                    place: place,
                    photo: photo,
                    action: action,
                    shareURL: shareURL,
                    shareText: shareText,
                    topInset: headerTopInset,
                    onBack: onBack,
                    onAction: onAction,
                    onPhotoLoadFailure: handlePhotoLoadFailure
                )

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

                        if !actionItems.isEmpty {
                            actionRow
                        }

                        whyItFitsSection
                        bestForSection
                        PlaceActivitySection(saves: saves, currentUserID: currentUserID)
                        detailsSection
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing4)
                    .padding(.bottom, bottomContentInset)
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
        .task(id: photoResolutionKey) {
            await resolvePhoto()
        }
    }

    private var localPhoto: PlacePhoto? {
        store.firstVisitPhoto(forPlaceID: place.id).map(PlacePhoto.init(localVisitPhoto:))
    }

    private var photoResolutionKey: String {
        "\(place.photoLookupKey)|\(localPhoto?.providerPlaceID ?? "none")|\(failedGooglePhotoID ?? "ready")"
    }

    private func resolvePhoto() async {
        let resolutionKey = photoResolutionKey
        let localPhoto = localPhoto
        guard !Task.isCancelled, resolutionKey == photoResolutionKey else { return }
        photo = localPhoto
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
            #if DEBUG
            WanderDebugLog.remote.debug(
                "place photo unavailable place=\(WanderDebugLog.shortID(place.id), privacy: .public) error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
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

    private var heading: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(place.name)
                    .font(.system(size: 34, weight: .black))
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
            HStack(spacing: WanderTheme.spacing2) {
                PlaceProfileRatingTile(
                    value: presentation.ownRating?.displayScore ?? "No visits yet",
                    suffix: presentation.ownRating == nil ? nil : "/5",
                    title: "Your rating",
                    subtitle: presentation.ownRating?.subtitle ?? "0 visits",
                    systemImage: "star.fill",
                    tint: WanderTheme.stateWarning.color,
                    explanation: nil
                )

                PlaceProfileRatingTile(
                    value: presentation.overallRating?.displayScore ?? "No ratings yet",
                    suffix: presentation.overallRating == nil ? nil : "/5",
                    title: "rec.me rating",
                    subtitle: presentation.overallRating?.subtitle ?? "0 ratings",
                    systemImage: "person.2.fill",
                    tint: WanderTheme.pinSocial.color,
                    explanation: .recMe
                )

                PlaceProfileRatingTile(
                    value: presentation.fitRating?.displayScore ?? "Not enough yet",
                    suffix: presentation.fitRating == nil ? nil : "/10",
                    title: "Fit Rating",
                    subtitle: presentation.fitRating == nil ? "keep saving" : "based on places you like",
                    systemImage: "sparkles",
                    tint: WanderTheme.terracotta.color,
                    explanation: .fit
                )
            }
        } else {
            PlaceProfileSubtleCard(
                text: "Add your rating and tags when this place belongs on your map."
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ForEach(actionItems) { item in
                Button {
                    openURL(item.url)
                } label: {
                    HStack(spacing: WanderTheme.spacing1) {
                        Image(systemName: iconName(for: item.kind))
                            .font(.system(size: 14, weight: .black))
                        Text(item.title)
                            .font(.system(size: 13, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .background(item.kind == .directions ? WanderTheme.terracotta.color : WanderTheme.surfaceRaised.color)
                    .foregroundStyle(item.kind == .directions ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(item.kind == .directions ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
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
        PlaceProfileCopy.actionItems(for: place)
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
        saves.filter { $0.visiblePlace.owner.id != currentUserID }
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
            return "\(trustedSaves.count) people you follow saved this place."
        }
        return "Save it to make this place yours."
    }

    private var whyItFitsSecondary: String {
        if presentation.fitRating != nil {
            return "Based on places you saved and people you follow."
        }
        if presentation.overallRating != nil || presentation.ownRating != nil {
            return "Your map gets more personal as you save places."
        }
        if displayTags.count >= 2 {
            return "People mention: \(displayTags.prefix(3).joined(separator: ", "))."
        }
        if let category = PlaceProfileCopy.categoryDisplay(for: place) {
            return "Category: \(category)."
        }
        return "Save it to add your own context."
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
        return "Saved place"
    }

    private func iconName(for kind: PlaceExternalAction.Kind) -> String {
        switch kind {
        case .directions:
            "location.fill"
        case .website:
            "globe"
        case .call:
            "phone.fill"
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

private struct PlaceProfileMapHeader: View {
    static let minimumFullBleedTopInset: CGFloat = 54

    let place: PlaceSheetPlace
    let photo: PlacePhoto?
    let action: PlaceSheetAction
    let shareURL: URL?
    let shareText: String
    let topInset: CGFloat
    let onBack: () -> Void
    let onAction: () -> Void
    let onPhotoLoadFailure: (PlacePhoto) -> Void

    var body: some View {
        ZStack {
            mapFallback

            if let photo {
                PlaceProfilePhotoImage(
                    photo: photo,
                    placeName: place.name,
                    onLoadFailure: onPhotoLoadFailure
                )
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

            if let photo, photo.isGooglePlacesPhoto {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PlacePhotoAttribution(photo: photo)
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing3)
                }
            }

            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .black))
                            .frame(width: 44, height: 44)
                            .background(WanderTheme.surfaceBone.color.opacity(0.96))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Circle())
                            .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close place profile")

                    Spacer()

                    HStack(spacing: WanderTheme.spacing2) {
                        if action != .none {
                            Button(action: onAction) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: action.isPrimaryAction ? 20 : 17, weight: .black))
                                    .frame(width: 44, height: 44)
                                    .background(action.isPrimaryAction ? WanderTheme.textInk.color : WanderTheme.terracotta.color)
                                    .foregroundStyle(WanderTheme.textOnAction.color)
                                    .clipShape(Circle())
                                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 10, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(action.accessibilityLabel)
                        }

                        if let shareURL {
                            WanderShareButton(content: .place(item: shareURL, name: place.name, message: shareText)) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .black))
                                    .frame(width: 44, height: 44)
                                    .background(WanderTheme.surfaceBone.color.opacity(0.96))
                                    .foregroundStyle(WanderTheme.textInk.color)
                                    .clipShape(Circle())
                                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 10, x: 0, y: 4)
                            }
                            .accessibilityLabel("Share place")
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing4 + topInset)
        }
        .frame(height: 214 + topInset)
        .background(WanderTheme.surfaceSand.color)
        .clipped()
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
                        .scaledToFill()
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

private struct PlaceProfileRatingTile: View {
    let value: String
    let suffix: String?
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let explanation: PlaceRatingExplanation?

    var body: some View {
        VStack(alignment: .center, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .textCase(.uppercase)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)
            }
            .foregroundStyle(WanderTheme.textMuted.color)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: valueFontSize, weight: .black))
                    .foregroundStyle(tint)
                    .lineLimit(suffix == nil ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)

            Text(subtitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .center)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if let explanation {
                PlaceRatingInfoButton(explanation: explanation, tint: tint)
                    .offset(x: 6, y: 2)
            }
        }
    }

    private var valueFontSize: CGFloat {
        suffix == nil ? 13 : 24
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
        Array(saves.prefix(3))
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
        PlaceProfileCopy.trimmed(userPlace.note)
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
        Text(status == .been ? "been" : "wanna")
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
        let display = WanderPlaceCategory.display(for: place.categoryAssignment).compactTitle
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
            return "Strong fit based on your saved places."
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

    static func actionItems(for place: PlaceSheetPlace) -> [PlaceExternalAction] {
        var actions: [PlaceExternalAction] = []
        if let latitude = place.latitude,
           let longitude = place.longitude,
           let directions = PlaceExternalLinks.directionsAction(placeName: place.name, latitude: latitude, longitude: longitude) {
            actions.append(directions)
        }

        let businessActions = PlaceExternalLinks.visibleBusinessActions(
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            actionLinksJSON: place.actionLinksJSON
        )
        .filter { $0.kind == .website || $0.kind == .call }

        actions.append(contentsOf: businessActions)
        return actions
    }

    static func shareURL(for place: PlaceSheetPlace) -> URL? {
        PlaceExternalLinks.googleMapsSearchURL(
            placeName: place.name,
            address: place.address,
            locality: place.locality
        )
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
