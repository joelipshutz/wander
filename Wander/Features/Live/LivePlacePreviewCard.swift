import SwiftUI

/// A preview of a selected Live pin. The caller supplies only currently authorized,
/// place events; discovery filters do not reorder the selected place’s history.
struct LivePlacePreviewCard: View {
    private let visiblePlace: VisiblePlace?
    private let sheetPlace: PlaceSheetPlace
    private let identity: LivePlaceIdentity?
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
    @State private var hydratedAccessGenerations: [String: Int] = [:]
    @State private var activityLoadFailed = false
    @State private var activityRetry = 0
    @State private var activityDisplayLease = LiveFeedDisplayLease()
    @State private var activityLeaseRevision: UInt64 = 0

    init(place: VisiblePlace, activities: [FeedActivity], identity: LivePlaceIdentity? = nil, onOpen: @escaping () -> Void,
         onAdd: @escaping () -> Void, onShare: @escaping () -> Void,
         onAddToList: @escaping () -> Void, onClose: @escaping () -> Void) {
        visiblePlace = place
        sheetPlace = PlaceSheetPlace(visiblePlace: place)
        self.identity = identity ?? LivePlaceIdentity(places: [place.place])
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
        identity = nil
        // A native POI has no authorized activity or save of its own.
        activities = []
        self.onOpen = onOpen
        self.onAdd = onAdd
        self.onShare = onShare
        self.onAddToList = onAddToList
        self.onClose = onClose
    }

    private var selectedActivity: [FeedActivity] {
        LivePlacePreviewPresentation.hydrationCandidates(activities, placeID: sheetPlace.id, identity: identity)
    }
    private var recentActivity: [FeedActivity] {
        let isHydrated = hydratedActivityKey == activityHydrationKey
        let rows = LivePlacePreviewPresentation.displayableActivity(
            isHydrated ? hydratedActivity : selectedActivity, viewerID: store.currentUser.id,
            lease: isHydrated ? activityDisplayLease : LiveFeedDisplayLease(), at: .now).filter {
                store.canDisplayPlaceActivity($0) && (!isHydrated
                    || hydratedAccessGenerations[$0.id] == store.activityAccessGeneration(for: $0.id))
            }
        let rowIdentity = isHydrated ? LivePlaceIdentity(places: rows.compactMap { $0.place?.place }) : identity
        return LivePlacePreviewPresentation.recentActivity(rows, placeID: sheetPlace.id, identity: rowIdentity)
    }
    private var activityHydrationKey: String {
        "\(identity?.cacheKey ?? sheetPlace.id)|\(store.currentUser.id)|\(auth.state.session?.userID ?? "signed-out")|\(backend.photoSessionRevision)|\(backend.photoAccessRevision)|\(scenePhase)|\(activityRetry)|"
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
        .task(id: "\(activityHydrationKey)|\(activityLeaseRevision)") { await expireActivityLease() }
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
        LivePlacePreviewHeader(name: sheetPlace.name,
            image: resolvedPhotoKey == photoResolutionKey ? resolvedPhoto?.image : nil,
            onOpen: onOpen, onAdd: onAdd, onShare: onShare,
            onAddToList: onAddToList, onClose: onClose)
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

            if activityLoadFailed, recentActivity.isEmpty {
                HStack {
                    Text("Recent activity couldn’t load.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brand.secondaryText)
                    Spacer(minLength: 4)
                    Button("Try again") { activityRetry += 1 }
                        .font(AstirTypography.label)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("live.placePreview.retryActivity")
                }
            }
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
                            Group {
                                if activity.resolvedTicketKind == .wanna {
                                    Image(systemName: LivePinKind.wanna.symbol)
                                } else {
                                    Text(LivePlacePreviewPresentation.emoji(for: activity))
                                }
                            }
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
        let userID = store.currentUser.id
        let usesRemoteHistory = backend.feedRepository != nil && !(identity?.persistedPlaceIDs.isEmpty ?? true)
        hydratedActivity = []; hydratedActivityKey = key
        hydratedAccessGenerations = [:]; activityLoadFailed = false
        activityDisplayLease = LiveFeedDisplayLease(); activityLeaseRevision &+= 1
        guard scenePhase == .active, auth.isSignedIn else { return }
        func isCurrent() -> Bool {
            !Task.isCancelled && key == activityHydrationKey && auth.isSignedIn
                && auth.state.session?.userID == userID && store.currentUser.id == userID
                && (!usesRemoteHistory || auth.isSessionValidated)
        }
        var generations: [String: Int] = [:]
        func resolve(_ event: FeedActivity) async -> FeedActivity? {
            let generation = store.activityAccessGeneration(for: event.id)
            let fresh: FeedActivity
            if UUID(uuidString: event.id) != nil {
                guard let repository = backend.activityEngagementRepository else { return nil }
                do {
                    fresh = try await repository.activity(id: event.id)
                    guard fresh.activityEngagementContext != nil else { return nil }
                } catch {
                    if isCurrent() { activityLoadFailed = true }
                    return nil
                }
            } else { fresh = event }
            guard isCurrent(), fresh.id == event.id,
                  generation == store.activityAccessGeneration(for: event.id),
                  store.canDisplayPlaceActivity(fresh) else { return nil }
            generations[fresh.id] = generation
            if fresh.actor.id != userID {
                // Only this successful source read renews this row's receipt.
                // Publishing later siblings must not extend older authorization.
                activityDisplayLease.accept(activityIDs: [fresh.id], at: .now, replacing: false)
                activityLeaseRevision &+= 1
            }
            return fresh
        }
        func publish(_ rows: [FeedActivity]) {
            guard isCurrent() else { return }
            hydratedAccessGenerations = generations
            hydratedActivity = rows.filter {
                generations[$0.id] == store.activityAccessGeneration(for: $0.id)
                    && store.canDisplayPlaceActivity($0)
            }
        }
        do {
            if let repository = backend.feedRepository, let identity, !identity.persistedPlaceIDs.isEmpty {
                try await auth.ensureSessionValidated(for: userID)
                guard isCurrent(), auth.isSessionValidated else { return }
                try await LivePlacePreviewPresentation.loadRecentActivity(
                    placeID: sheetPlace.id, identity: identity, isCurrent: isCurrent,
                    loadPage: { cursor in
                        try await repository.placeActivity(placeIDs: identity.persistedPlaceIDs,
                            before: cursor, limit: LivePlacePreviewPresentation.maximumHydrationCandidates)
                    }, resolve: resolve, onUpdate: publish)
            } else {
                // Fixture/native-local rows do not have persisted venue IDs.
                await LivePlacePreviewPresentation.hydrateRecentActivity(
                    selectedActivity, placeID: sheetPlace.id, identity: identity,
                    isCurrent: isCurrent, resolve: resolve, onUpdate: publish)
            }
        } catch {
            guard isCurrent() else { return }
            activityLoadFailed = true
        }
    }

    private func expireActivityLease() async {
        guard scenePhase == .active, let expiry = activityDisplayLease.nextExpiry(after: .now) else { return }
        let key = activityHydrationKey
        let revision = activityLeaseRevision
        do { try await ContinuousClock().sleep(until: expiry) } catch { return }
        guard !Task.isCancelled, scenePhase == .active, key == activityHydrationKey,
              revision == activityLeaseRevision else { return }
        let allowed = LivePlacePreviewPresentation.displayableActivity(hydratedActivity,
            viewerID: store.currentUser.id, lease: activityDisplayLease, at: .now)
        let expired = allowed.count != hydratedActivity.count
        hydratedActivity = allowed
        // Re-arm for later receipts even if the expired row was deduplicated.
        activityLeaseRevision &+= 1
        if expired { activityRetry += 1 }
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

/// Background image dimensions cannot displace the title or action controls.
struct LivePlacePreviewHeader: View {
    let name: String
    let image: UIImage?
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onShare: () -> Void
    let onAddToList: () -> Void
    let onClose: () -> Void
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Color.clear
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 236 : 196)
            .background {
                GeometryReader { geometry in
                    ZStack {
                        LinearGradient(colors: [brand.raisedBackground, brand.secondaryText.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(brand.secondaryText.opacity(0.5))
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.78)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Button(action: onOpen) {
                    Text(name)
                        .font(AstirTypography.sheetTitle)
                        .foregroundStyle(.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.top, 54)
                        .padding(.leading, 16)
                        .padding(.trailing, 68)
                        .padding(.bottom, 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(name)")
                .accessibilityHint("Opens the full place page")
                .accessibilityIdentifier("live.placePreview.open")
            }
            .overlay(alignment: .topTrailing) { actionRail.padding(10) }
            .overlay(alignment: .topLeading) {
                action("Close place preview", symbol: "xmark", identifier: "close", perform: onClose)
                    .padding(10)
            }
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

}

private struct LivePreviewPhotoRoute: Identifiable {
    let id = UUID()
    let context: ActivityEngagementContext
    let mediaID: String
}

enum LivePlacePreviewPresentation {
    static let maximumHydrationCandidates = 20
    static let maximumHistoryPages = 3
    private static let maximumRecentActivity = 3

    /// The continuous-time lease also gates the first foreground frame before
    /// its refresh task resumes; cached payload timestamps grant no extension.
    static func displayableActivity(_ activities: [FeedActivity], viewerID: String,
                                    lease: LiveFeedDisplayLease, at now: ContinuousClock.Instant) -> [FeedActivity] {
        activities.filter { lease.permits(activityID: $0.id, isOwn: $0.actor.id == viewerID, at: now) }
    }

    /// Map rows do not yet carry authoritative media. Only event identity and
    /// ordering choose the hydration candidates; content dedup happens later.
    static func hydrationCandidates(_ activities: [FeedActivity], placeID: String,
                                    identity: LivePlaceIdentity? = nil) -> [FeedActivity] {
        Array(sortedUniqueActivities(activities, placeID: placeID, identity: identity).prefix(maximumHydrationCandidates))
    }

    @MainActor
    @discardableResult
    static func hydrateRecentActivity(
        _ activities: [FeedActivity], placeID: String, identity: LivePlaceIdentity? = nil,
        isCurrent: @MainActor () -> Bool,
        resolve: @MainActor (FeedActivity) async -> FeedActivity?,
        onUpdate: @MainActor ([FeedActivity]) -> Void = { _ in }
    ) async -> [FeedActivity] {
        var accepted: [FeedActivity] = []
        var rows: [FeedActivity] = []
        for candidate in hydrationCandidates(activities, placeID: placeID, identity: identity) {
            guard !Task.isCancelled, isCurrent() else { return [] }
            let fresh = await resolve(candidate)
            guard !Task.isCancelled, isCurrent() else { return [] }
            if let fresh, matches(fresh, placeID: placeID, identity: identity) { accepted.append(fresh) }
            rows = recentActivity(accepted, placeID: placeID, identity: identity)
            onUpdate(rows)
            if rows.count == maximumRecentActivity { break }
        }
        return rows
    }

    /// This bounded read is independent of map discovery filters and never
    /// inserts history into the map or the shared Feed’s pagination state.
    @MainActor
    @discardableResult
    static func loadRecentActivity(
        placeID: String, identity: LivePlaceIdentity,
        isCurrent: @MainActor () -> Bool,
        loadPage: @MainActor (String?) async throws -> FollowedFeedPage,
        resolve: @MainActor (FeedActivity) async -> FeedActivity?,
        onUpdate: @MainActor ([FeedActivity]) -> Void = { _ in }
    ) async throws -> [FeedActivity] {
        guard !identity.aliases.isEmpty else { return [] }
        var accepted: [FeedActivity] = []
        var rows: [FeedActivity] = []
        var cursor: String?
        var requestedCursors = Set<String>()
        var seenEvents = Set<String>()
        for _ in 0..<maximumHistoryPages {
            guard !Task.isCancelled, isCurrent() else { return [] }
            let page = try await loadPage(cursor)
            guard !Task.isCancelled, isCurrent() else { return [] }
            // The endpoint has already resolved the complete canonical place
            // component. A transitive server alias may be absent from the pin.
            let pageIdentity = LivePlaceIdentity(places: page.activity.compactMap { $0.place?.place })
            for candidate in hydrationCandidates(page.activity, placeID: placeID, identity: pageIdentity)
                where seenEvents.insert(candidate.id).inserted {
                guard !Task.isCancelled, isCurrent() else { return [] }
                let fresh = await resolve(candidate)
                guard !Task.isCancelled, isCurrent() else { return [] }
                // Hydration may not retarget an authorized event to a different
                // venue or event while the request is in flight.
                if let fresh, fresh.id == candidate.id,
                   let sourcePlaceID = candidate.place?.place.id,
                   fresh.place?.place.id == sourcePlaceID { accepted.append(fresh) }
                let acceptedIdentity = LivePlaceIdentity(places: accepted.compactMap { $0.place?.place })
                rows = recentActivity(accepted, placeID: placeID, identity: acceptedIdentity)
                onUpdate(rows)
                if rows.count == maximumRecentActivity { return rows }
            }
            guard let next = page.nextCursor, requestedCursors.insert(next).inserted else { break }
            cursor = next
        }
        return rows
    }

    static func recentActivity(_ activities: [FeedActivity], placeID: String,
                               identity: LivePlaceIdentity? = nil) -> [FeedActivity] {
        let matching = sortedUniqueActivities(activities, placeID: placeID, identity: identity)
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

    private static func sortedUniqueActivities(_ activities: [FeedActivity], placeID: String,
                                               identity: LivePlaceIdentity?) -> [FeedActivity] {
        var seen = Set<String>()
        return activities.filter {
            matches($0, placeID: placeID, identity: identity) && seen.insert($0.id).inserted
        }.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.id > rhs.id
        }
    }

    private static func matches(_ activity: FeedActivity, placeID: String,
                                identity: LivePlaceIdentity?) -> Bool {
        guard let place = activity.place?.place else { return false }
        return identity?.matches(place) ?? (place.id == placeID)
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
        case .wanna: "🔖"
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
