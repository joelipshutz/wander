import SwiftUI

/// A preview of a selected Live pin. The caller supplies only currently authorized,
/// filter-matching events; opening the preview does not fetch unrelated activity.
struct LivePlacePreviewCard: View {
    private let visiblePlace: VisiblePlace?
    private let sheetPlace: PlaceSheetPlace
    let activities: [FeedActivity]
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onShare: () -> Void
    let onAddToList: () -> Void
    let onClose: () -> Void

    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @State private var resolvedPhoto: ListPlaceResolvedPhoto?
    @State private var resolvedPhotoKey: String?
    @State private var providerDetails = LivePlacePreviewProviderDetails()
    @State private var providerDetailsKey: String?
    @State private var photoViewer: LivePreviewPhotoRoute?
    @State private var hydratedActivity: [FeedActivity] = []
    @State private var hydratedActivityKey: String?

    init(place: VisiblePlace, activities: [FeedActivity], onOpen: @escaping () -> Void,
         onAdd: @escaping () -> Void, onShare: @escaping () -> Void,
         onAddToList: @escaping () -> Void, onClose: @escaping () -> Void) {
        visiblePlace = place
        sheetPlace = PlaceSheetPlace(visiblePlace: place)
        self.activities = activities
        self.onOpen = onOpen
        self.onAdd = onAdd
        self.onShare = onShare
        self.onAddToList = onAddToList
        self.onClose = onClose
    }

    init(candidate: PlaceCandidate, onOpen: @escaping () -> Void,
         onAdd: @escaping () -> Void, onShare: @escaping () -> Void,
         onAddToList: @escaping () -> Void, onClose: @escaping () -> Void) {
        visiblePlace = nil
        sheetPlace = PlaceSheetPlace(candidate: candidate)
        // A native POI has no authorized activity or save of its own.
        activities = []
        self.onOpen = onOpen
        self.onAdd = onAdd
        self.onShare = onShare
        self.onAddToList = onAddToList
        self.onClose = onClose
    }

    private var selectedActivity: [FeedActivity] {
        LivePlacePreviewPresentation.hydrationCandidates(activities, placeID: sheetPlace.id)
    }
    private var recentActivity: [FeedActivity] {
        let rows = hydratedActivityKey == activityHydrationKey ? hydratedActivity : selectedActivity
        return LivePlacePreviewPresentation.recentActivity(rows, placeID: sheetPlace.id)
    }
    private var activityHydrationKey: String {
        "\(sheetPlace.id)|\(store.currentUser.id)|\(auth.state.session?.userID ?? "signed-out")|\(backend.photoAccessRevision)|\(scenePhase)|"
            + selectedActivity.map { "\($0.id):\(store.activityAccessGeneration(for: $0.id))" }.joined(separator: ",")
    }
    private var providerDetailsRequestKey: String {
        "\(sheetPlace.photoLookupKey)|\(store.currentUser.id)|\(backend.photoSessionRevision)"
    }
    private var currentProviderDetails: LivePlacePreviewProviderDetails {
        providerDetailsKey == providerDetailsRequestKey ? providerDetails : LivePlacePreviewProviderDetails()
    }
    private var photoResolutionKey: String {
        "\(sheetPlace.photoLookupKey)|\(store.currentUser.id)|\(backend.photoSessionRevision)|\(backend.photoAccessRevision)|\(scenePhase)"
    }

    var body: some View {
        VStack(spacing: 0) {
            photoHeader
            details
        }
        .background(brand.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(brand.border.opacity(0.7), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.placePreview")
        .task(id: photoResolutionKey) { await resolvePhoto() }
        .task(id: "\(providerDetailsRequestKey)|\(scenePhase)") { await resolveProviderDetails() }
        .task(id: activityHydrationKey) { await hydrateSelectedActivity() }
        .onDisappear {
            if resolvedPhoto?.photo.requiresAccessCheck == true {
                resolvedPhoto = nil; resolvedPhotoKey = nil
            }
        }
        .fullScreenCover(item: $photoViewer) { route in
            ActivityPhotoViewerScreen(context: route.context, initialMediaID: route.mediaID)
        }
    }

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(colors: [brand.raisedBackground, brand.secondaryText.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(brand.secondaryText.opacity(0.5))
                if resolvedPhotoKey == photoResolutionKey, let resolvedPhoto {
                    Image(uiImage: resolvedPhoto.image).resizable().scaledToFill()
                }
            }
            .accessibilityHidden(true)

            LinearGradient(colors: [.clear, .black.opacity(0.78)],
                           startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    Spacer(minLength: 0)
                    Text(sheetPlace.name)
                        .font(AstirTypography.sheetTitle)
                        .foregroundStyle(.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                }
                .padding(.leading, 16)
                .padding(.trailing, 68)
                .padding(.bottom, 15)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(sheetPlace.name)")
            .accessibilityHint("Opens the full place page")
            .accessibilityIdentifier("live.placePreview.open")

            actionRail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            action("Close place preview", symbol: "xmark", identifier: "close", perform: onClose)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 236 : 196)
        .clipped()
    }

    private var actionRail: some View {
        VStack(spacing: 0) {
            action("Save place", symbol: "plus", identifier: "add", signal: true, perform: onAdd)
            action("Share place", symbol: "square.and.arrow.up", identifier: "share", perform: onShare)
            action("Add place to list", symbol: "text.badge.plus", identifier: "list", perform: onAddToList)
        }
    }

    private func action(_ title: String, symbol: String, identifier: String,
                        signal: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(signal ? brand.accentForeground : brand.primaryText)
                .frame(width: 34, height: 34)
                // A photo can be much darker/lighter than the selected app theme.
                // Keep the glyph's backing legible while retaining the glass edge.
                .background(signal ? brand.accent : brand.raisedBackground.opacity(0.88), in: Circle())
                .astirGlassSurface(cornerRadius: 17, castsShadow: true,
                                   interactive: true, accentAction: signal)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, brand.prefersDarkInterface ? .dark : .light)
        .accessibilityLabel(title)
        .accessibilityIdentifier("live.placePreview.\(identifier)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { category; Spacer(minLength: 4); rating }
                        VStack(alignment: .leading, spacing: 4) { category; rating }
                    }
                    if let hours {
                        Text([hours.statusText, hours.detailText].compactMap { $0 }.joined(separator: " · "))
                            .font(AstirTypography.caption)
                            .foregroundStyle(brand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("live.placePreview.hours")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full place page")

            if !recentActivity.isEmpty {
                Rectangle().fill(brand.border.opacity(0.7)).frame(height: 0.5)
                    .accessibilityHidden(true)
                ForEach(recentActivity) { activity in
                    activityRow(activity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var category: some View {
        Text(sheetPlace.compactPlaceType)
            .font(AstirTypography.label)
            .foregroundStyle(brand.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rating: some View {
        if let rating = ratingPresentation {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.caption2)
                Text(rating.scoreText).font(AstirTypography.label)
                if let count = rating.count, count > 0 {
                    Text("(\(count))").font(AstirTypography.caption)
                }
                if let provider = rating.providerDisplayName {
                    Text(provider).font(AstirTypography.caption)
                } else if rating.source == .featured {
                    Text("Featured").font(AstirTypography.caption)
                }
            }
            .foregroundStyle(brand.primaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([rating.accessibilityLabel, rating.providerDisplayName,
                                 rating.count.map { "\($0) ratings" }].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("live.placePreview.rating")
        }
    }

    private func activityRow(_ activity: FeedActivity) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 8) {
                    WanderAvatar(initials: initials(activity.actor.displayName),
                                 avatarURL: activity.actor.avatarURL, size: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(activity.actor.displayName)
                                .font(AstirTypography.label)
                                .lineLimit(1)
                            Text(LivePlacePreviewPresentation.emoji(for: activity))
                                .font(.caption)
                                .accessibilityLabel(LivePlacePreviewPresentation.actionLabel(for: activity))
                            Spacer(minLength: 0)
                            Text(FeedPresentation.timestampText(for: activity.occurredAt))
                                .font(AstirTypography.caption)
                                .foregroundStyle(brand.secondaryText)
                                .lineLimit(1)
                        }
                        Text(LivePlacePreviewPresentation.highlight(for: activity))
                        .font(AstirTypography.caption)
                        .foregroundStyle(brand.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the full place page")
            let media = previewMedia(activity)
            if !media.isEmpty {
                photoPile(activity, media: media)
            }
        }
        .foregroundStyle(brand.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.placePreview.activity.\(activity.id)")
    }

    private func previewMedia(_ activity: FeedActivity) -> [FeedMediaPreview] {
        activity.media.filter {
            !$0.id.hasPrefix("pending:") && ($0.urlString?.isEmpty == false
                || ($0.storageBucket?.isEmpty == false && $0.storagePath?.isEmpty == false))
        }
    }

    private func photoPile(_ activity: FeedActivity, media: [FeedMediaPreview]) -> some View {
        Button {
            guard let first = media.first, let context = activity.activityEngagementContext else { return }
            photoViewer = LivePreviewPhotoRoute(context: context, mediaID: first.id)
        } label: {
            ZStack {
                ForEach(Array(media.prefix(3).enumerated()), id: \.element.id) { index, item in
                    PlaceProfilePhotoImage(
                        photo: ActivityEngagementMedia(id: item.id, urlString: item.urlString,
                                                      storageBucket: item.storageBucket, storagePath: item.storagePath,
                                                      accessibilityLabel: item.accessibilityLabel).placePhoto,
                        canonicalPlaceKey: "activity-photo:\(item.id)",
                        placeName: item.accessibilityLabel,
                        variant: .card
                    )
                    .frame(width: 36, height: 36)
                    .background(brand.background)
                    .overlay(alignment: .bottomTrailing) {
                        if index == 0 {
                            Text("\(media.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                .padding(3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(brand.raisedBackground, lineWidth: 1.5))
                    .rotationEffect(.degrees(Double(index) * 7))
                    .offset(x: CGFloat(index) * 3, y: CGFloat(index) * -2)
                    .zIndex(Double(3 - index))
                }
            }.frame(width: 48, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("View \(media.count) \(media.count == 1 ? "photo" : "photos") from \(activity.actor.displayName)’s activity")
        .accessibilityHint("Opens the photo gallery")
        .accessibilityIdentifier("live.placePreview.photos.\(activity.id)")
    }

    private var ratingPresentation: PlaceCardRatingPresentation? {
        var seen = Set<String>()
        let summaries = ([visiblePlace].compactMap { $0 } + activities.compactMap(\.place)).filter {
            $0.place.id == sheetPlace.id && seen.insert($0.userPlace.id).inserted
        }.map {
            PlaceSaveSummary(visiblePlace: $0, attributes: $0.attributes,
                             viewerFollowsOwner: store.viewerFollows($0.owner.id))
        }
        let presentation = PlaceProfilePresenter.presentation(
            placeID: sheetPlace.id, category: sheetPlace.category, saves: summaries,
            tasteSaves: [], currentUserID: store.currentUser.id
        )
        return PlaceCardPresentation.rating(
            providerScore: currentProviderDetails.photo?.providerRating,
            providerCount: currentProviderDetails.photo?.providerUserRatingCount,
            recmeRating: presentation.overallRating ?? presentation.ownRating,
            providerName: currentProviderDetails.photo?.provider, isUnratedFeatured: presentation.isUnratedFeatured
        )
    }

    private var hours: PlaceCardHoursPresentation? {
        currentProviderDetails.hours
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func hydrateSelectedActivity() async {
        let key = activityHydrationKey
        hydratedActivity = []; hydratedActivityKey = key
        guard scenePhase == .active, auth.isSignedIn else { return }
        // Candidate identity is independent of hydrated notes/media. Resolve a
        // bounded prefix until three distinct, still-authorized rows are ready.
        await LivePlacePreviewPresentation.hydrateRecentActivity(
            selectedActivity, placeID: sheetPlace.id,
            isCurrent: { key == activityHydrationKey },
            resolve: { event in
                guard UUID(uuidString: event.id) != nil else { return event }
                guard event.activityEngagementContext != nil,
                      let fresh = await store.activity(id: event.id, backend: backend, authSession: auth),
                      store.canDisplayLiveMapActivity(fresh), store.liveFeedQuery?.includes(fresh) ?? true
                else { return nil }
                return fresh
            },
            onUpdate: { hydratedActivity = $0 }
        )
    }

    private func resolvePhoto() async {
        resolvedPhoto = nil; resolvedPhotoKey = nil
        guard scenePhase == .active else { return }
        let key = photoResolutionKey
        let request = sheetPlace.photoRequest.rendering(.card)
        let resolved = await LivePinPhotoResolver.resolveImage(request: request,
            authorizationScopeKey: "\(store.currentUser.id)|\(backend.photoSessionRevision)|\(backend.photoAccessRevision)",
            backend: backend, targetPixelSize: PlacePhotoRenderVariant.card.maximumPixelDimension ?? 1_440,
            batcher: LivePinPhotoResolver.previewBatcher)
        guard !Task.isCancelled, key == photoResolutionKey else { return }
        resolvedPhoto = resolved; resolvedPhotoKey = key
    }

    private func resolveProviderDetails() async {
        let key = providerDetailsRequestKey
        if providerDetailsKey != key {
            providerDetails = LivePlacePreviewProviderDetails()
            providerDetailsKey = key
        }
        guard scenePhase == .active else { return }
        // Hours and ratings must load even when a venue has no usable photo.
        let request = sheetPlace.photoRequest.metadataOnly()
        let cached = backend.cachedPlacePhoto(for: request)
        providerDetails.prepareForRefresh(cached: cached)
        if cached != nil { return }
        do {
            let details = try await backend.placePhoto(for: request)
            guard !Task.isCancelled, key == providerDetailsRequestKey else { return }
            providerDetails.receive(details)
        } catch {
            // Unknown provider facts stay unknown; image failure is independent.
        }
    }

}

private struct LivePreviewPhotoRoute: Identifiable {
    let id = UUID()
    let context: ActivityEngagementContext
    let mediaID: String
}

enum LivePlacePreviewPresentation {
    static let maximumHydrationCandidates = 20
    private static let maximumRecentActivity = 3

    /// Map rows do not yet carry authoritative media. Only event identity and
    /// ordering choose the hydration candidates; content dedup happens later.
    static func hydrationCandidates(_ activities: [FeedActivity], placeID: String) -> [FeedActivity] {
        Array(sortedUniqueActivities(activities, placeID: placeID).prefix(maximumHydrationCandidates))
    }

    @MainActor
    @discardableResult
    static func hydrateRecentActivity(
        _ activities: [FeedActivity], placeID: String,
        isCurrent: @MainActor () -> Bool,
        resolve: @MainActor (FeedActivity) async -> FeedActivity?,
        onUpdate: @MainActor ([FeedActivity]) -> Void = { _ in }
    ) async -> [FeedActivity] {
        var accepted: [FeedActivity] = []
        var rows: [FeedActivity] = []
        for candidate in hydrationCandidates(activities, placeID: placeID) {
            guard !Task.isCancelled, isCurrent() else { return [] }
            let fresh = await resolve(candidate)
            guard !Task.isCancelled, isCurrent() else { return [] }
            if let fresh, fresh.place?.place.id == placeID { accepted.append(fresh) }
            rows = recentActivity(accepted, placeID: placeID)
            onUpdate(rows)
            if rows.count == maximumRecentActivity { break }
        }
        return rows
    }

    static func recentActivity(_ activities: [FeedActivity], placeID: String) -> [FeedActivity] {
        let matching = sortedUniqueActivities(activities, placeID: placeID)
        let originals = Set(matching.filter {
            $0.kind == .placeBeen || $0.kind == .placeWannaGo || $0.kind == .placeSaved
        }.compactMap(listEchoKey))
        var seenListEchoes = Set<ListEchoKey>()
        return Array(matching.filter { activity in
            // List additions can repeat their source save's note across lists.
            // Keep the original event and every distinct visit/Wanna untouched.
            guard activity.kind == .listItemAdded, let key = listEchoKey(activity) else { return true }
            return !originals.contains(key) && seenListEchoes.insert(key).inserted
        }.prefix(maximumRecentActivity))
    }

    private static func sortedUniqueActivities(_ activities: [FeedActivity], placeID: String) -> [FeedActivity] {
        var seen = Set<String>()
        return activities.filter {
            $0.place?.place.id == placeID && seen.insert($0.id).inserted
        }.sorted { lhs, rhs in
            let lhsFollowed = lhs.actor.relationship == .follower || lhs.actor.relationship == .mutual
            let rhsFollowed = rhs.actor.relationship == .follower || rhs.actor.relationship == .mutual
            if lhsFollowed != rhsFollowed { return lhsFollowed }
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.id < rhs.id
        }
    }

    private struct ListEchoKey: Hashable {
        let actorID: String
        let placeID: String
        let sourceID: String
        let note: String
        let mediaIDs: [String]
    }

    private static func listEchoKey(_ activity: FeedActivity) -> ListEchoKey? {
        guard let place = activity.place,
              let note = activity.note?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "),
              !note.isEmpty else { return nil }
        return ListEchoKey(actorID: activity.actor.id, placeID: place.place.id,
            sourceID: place.userPlace.id, note: note, mediaIDs: Set(activity.media.map(\.id)).sorted())
    }

    static func emoji(for activity: FeedActivity) -> String {
        switch activity.resolvedTicketKind {
        case .checkIn: "📍"
        case .wanna: "✨"
        case .list: "📋"
        case .saved: "🔖"
        }
    }

    static func actionLabel(for activity: FeedActivity) -> String {
        switch activity.resolvedTicketKind {
        case .checkIn: "Checked in"
        case .wanna: "Wanna"
        case .list: "Added to a list"
        case .saved: "Saved"
        }
    }

    static func highlight(for activity: FeedActivity) -> String {
        if let note = activity.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return note.replacingOccurrences(of: "\n", with: " ")
        }
        if activity.resolvedTicketKind == .list, let list = activity.list { return list.name }
        return actionLabel(for: activity)
    }
}

/// Provider facts remain valid when image delivery fails or a user photo is used.
/// The card resets this state for a different place or account/session.
struct LivePlacePreviewProviderDetails {
    private(set) var photo: PlacePhoto?

    mutating func prepareForRefresh(cached: PlacePhoto?) {
        // An expired Open/Closed value must not survive a failed foreground refresh.
        photo = nil
        if let cached { receive(cached) }
    }

    mutating func receive(_ photo: PlacePhoto) {
        guard photo.isGooglePlacesPhoto else { return }
        self.photo = photo
    }

    var hours: PlaceCardHoursPresentation? {
        PlaceCardPresentation.hours(isOpen: photo?.providerOpenNow,
            nextOpenTimeString: photo?.providerNextOpenTimeString,
            nextCloseTimeString: photo?.providerNextCloseTimeString,
            utcOffsetMinutes: photo?.providerUTCOffsetMinutes)
    }
}
