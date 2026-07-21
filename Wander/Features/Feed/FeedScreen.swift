import SwiftUI

struct FeedScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var isShowingSearch = false
    @State private var selectedProfile: FeedProfileRoute?
    @State private var savingActivityIDs = Set<String>()
    @State private var savedActivityIDs = Set<String>()
    @State private var failedActivityIDs = Set<String>()
    @State private var followingProfileIDs = Set<String>()

    private let tickerSuggestions = [
        "Joe's favorite coffee shops in LA",
        "Maya's date night spots",
        "quiet work cafes with wifi",
        "friends' sunset hikes"
    ]

    private var page: FollowedFeedPage? { store.followedFeedPage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    FeedSearchLauncher(placeholders: tickerSuggestions) {
                        isShowingSearch = true
                    }

                    content
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wanderScreen()
            .refreshable {
                await refresh()
            }
            .task {
                await refresh()
            }
            .fullScreenCover(isPresented: $isShowingSearch) {
                DiscoverScreen()
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .fullScreenCover(item: $selectedProfile) { route in
                ProfileDetailView(profileID: route.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.feedLoadState == .loading, page == nil {
            FeedLoadingState()
        } else if let page, !page.activity.isEmpty {
            if !page.featuredPlaces.isEmpty {
                FeedSectionHeading(title: "Featured for you")
                FeedFeaturedRail(
                    places: page.featuredPlaces,
                    openProfile: openProfile,
                    save: saveFeaturedPlace
                )
            }

            FeedSectionHeading(title: "Your feed", detail: freshnessDetail)
            FeedActivityList(
                activity: page.activity,
                savingActivityIDs: savingActivityIDs,
                savedActivityIDs: savedActivityIDs,
                failedActivityIDs: failedActivityIDs,
                openProfile: openProfile,
                save: save,
                openList: openList
            )

            if store.feedLoadState == .stale {
                FeedRetryRow(
                    title: "Updated earlier",
                    subtitle: "We’ll keep this cached Feed until it reconnects.",
                    actionTitle: "Retry",
                    retry: refresh
                )
            }
        } else {
            FeedSectionHeading(title: "Your feed")
            FeedEmptyState(
                recommendations: peopleRecommendations,
                followingProfileIDs: followingProfileIDs,
                openSearch: { isShowingSearch = true },
                openProfile: openProfile,
                follow: follow
            )

            if store.feedLoadState == .failed {
                FeedRetryRow(
                    title: "Couldn’t update Feed",
                    subtitle: "Search still works while we reconnect.",
                    actionTitle: "Retry",
                    retry: refresh
                )
            }
        }
    }

    private var freshnessDetail: String? {
        guard store.feedLoadState == .stale else { return nil }
        return "Updated earlier"
    }

    private var peopleRecommendations: [DiscoverPeopleRecommendation] {
        guard case .loaded(let recommendations) = store.discoverPeopleRecommendationsState else {
            return []
        }
        return Array(recommendations.prefix(3))
    }

    private func refresh() async {
        _ = await store.refreshFollowedFeed(backend: auth.isSignedIn ? backend : nil)
        guard store.followedFeedPage?.activity.isEmpty != false else { return }
        await store.refreshDiscoverPeopleRecommendations(backend: auth.isSignedIn ? backend : nil)
    }

    private func openProfile(_ profile: ProfileShell) {
        selectedProfile = FeedProfileRoute(id: profile.id)
    }

    private func openList(_ list: LocalPlaceList) {
        pushNotifications.route(to: .list(id: list.id))
    }

    private func saveFeaturedPlace(_ featured: FeedFeaturedPlace) {
        save(place: featured.visiblePlace, activityID: "featured-\(featured.id)")
    }

    private func save(_ activity: FeedActivity) {
        guard let place = activity.place else { return }
        save(place: place, activityID: activity.id)
    }

    private func save(place: VisiblePlace, activityID: String) {
        guard !savingActivityIDs.contains(activityID), !savedActivityIDs.contains(activityID) else { return }

        auth.requireSignIn(for: .socialSave) {
            Task { @MainActor in
                savingActivityIDs.insert(activityID)
                failedActivityIDs.remove(activityID)
                let result = await store.saveVisiblePlace(
                    place,
                    status: .wannaGo,
                    backend: auth.isSignedIn ? backend : nil
                )
                savingActivityIDs.remove(activityID)
                if result.syncState == .failed {
                    failedActivityIDs.insert(activityID)
                } else {
                    savedActivityIDs.insert(activityID)
                }
            }
        }
    }

    private func follow(_ recommendation: DiscoverPeopleRecommendation) {
        guard !followingProfileIDs.contains(recommendation.profile.id) else { return }
        auth.requireSignIn(for: .followPeople) {
            Task { @MainActor in
                followingProfileIDs.insert(recommendation.profile.id)
                _ = await store.follow(
                    userID: recommendation.profile.id,
                    source: .profile,
                    backend: auth.isSignedIn ? backend : nil
                )
                followingProfileIDs.remove(recommendation.profile.id)
                await refresh()
            }
        }
    }
}

private struct FeedProfileRoute: Identifiable {
    let id: String
}

private struct FeedSearchLauncher: View {
    let placeholders: [String]
    let action: () -> Void
    @State private var placeholderIndex = 0

    private var placeholder: String {
        guard !placeholders.isEmpty else { return "Search places and people" }
        return placeholders[placeholderIndex % placeholders.count]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Text(placeholder)
                    .id(placeholder)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .lineLimit(1)
                    .transition(.push(from: .bottom).combined(with: .opacity))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 44)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search places and people")
        .task {
            guard placeholders.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }
}

private struct FeedSectionHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.textInk.color)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }
}

private struct FeedFeaturedRail: View {
    let places: [FeedFeaturedPlace]
    let openProfile: (ProfileShell) -> Void
    let save: (FeedFeaturedPlace) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ForEach(places) { featured in
                    FeedFeaturedCard(featured: featured, openProfile: openProfile, save: save)
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel("Featured places from people you follow")
    }
}

private struct FeedFeaturedCard: View {
    let featured: FeedFeaturedPlace
    let openProfile: (ProfileShell) -> Void
    let save: (FeedFeaturedPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                FeedPlaceArtwork(place: featured.visiblePlace, height: 92)
                Spacer(minLength: 0)
            }

            Text(featured.visiblePlace.place.canonicalName)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(2)

            Text(placeDetail(for: featured.visiblePlace))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)

            Button {
                openProfile(ProfileShell(
                    id: featured.visiblePlace.owner.id,
                    handle: featured.visiblePlace.owner.handle,
                    displayName: featured.visiblePlace.owner.displayName,
                    avatarURL: featured.visiblePlace.owner.avatarURL,
                    bio: featured.visiblePlace.owner.bio,
                    relationship: .follower
                ))
            } label: {
                Label(featured.reason, systemImage: "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.skyTint.color)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                save(featured)
            } label: {
                Label("Save", systemImage: "plus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save \(featured.visiblePlace.place.canonicalName) to my map")
        }
        .padding(WanderTheme.spacing3)
        .frame(width: 184, alignment: .leading)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedActivityList: View {
    let activity: [FeedActivity]
    let savingActivityIDs: Set<String>
    let savedActivityIDs: Set<String>
    let failedActivityIDs: Set<String>
    let openProfile: (ProfileShell) -> Void
    let save: (FeedActivity) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(activity.enumerated()), id: \.element.id) { index, event in
                FeedActivityModule(
                    activity: event,
                    isSaving: savingActivityIDs.contains(event.id),
                    isSaved: savedActivityIDs.contains(event.id),
                    didFailSave: failedActivityIDs.contains(event.id),
                    openProfile: openProfile,
                    save: save,
                    openList: openList
                )

                if index < activity.count - 1 {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                }
            }
        }
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedActivityModule: View {
    let activity: FeedActivity
    let isSaving: Bool
    let isSaved: Bool
    let didFailSave: Bool
    let openProfile: (ProfileShell) -> Void
    let save: (FeedActivity) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Button {
                    openProfile(activity.actor)
                } label: {
                    WanderAvatar(
                        initials: initials(for: activity.actor.displayName),
                        avatarURL: activity.actor.avatarURL,
                        size: 48,
                        color: WanderTheme.skyTint.color
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(activity.actor.displayName)'s profile")

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(headline)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: WanderTheme.spacing1) {
                        Image(systemName: activity.list == nil ? "fork.knife" : "list.bullet")
                        Text(metadata)
                            .lineLimit(1)
                        Text("·")
                            .accessibilityHidden(true)
                        Text(FeedPresentation.timestampText(for: activity.occurredAt))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing1)

                if let rating = activity.rating {
                    Text(PlaceRating.averageDisplay(rating))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(minHeight: 32)
                        .overlay {
                            Capsule().stroke(WanderTheme.terracotta.color.opacity(0.45), lineWidth: 1)
                        }
                        .accessibilityLabel("Rating \(PlaceRating.averageDisplay(rating))")
                }
            }

            if let note = activity.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 60)
            }

            if !activity.media.isEmpty {
                FeedMediaRail(media: activity.media)
                    .padding(.leading, 60)
            }

            HStack {
                Spacer(minLength: 0)
                actionButton
            }
        }
        .padding(WanderTheme.spacing3)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let list = activity.list, !activity.kind.isPlaceActivity || activity.kind == .listItemAdded {
            Button {
                openList(list)
            } label: {
                Label("View list", systemImage: "list.bullet")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View list \(list.name)")
        } else if activity.place != nil {
            Button {
                save(activity)
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(WanderTheme.textOnAction.color)
                    } else if isSaved {
                        Label("Saved", systemImage: "checkmark")
                    } else if didFailSave {
                        Label("Retry", systemImage: "arrow.clockwise")
                    } else {
                        Label("Save to my map", systemImage: "plus")
                    }
                }
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(isSaved ? WanderTheme.terracotta.color : WanderTheme.textOnAction.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 38)
                .background(isSaved ? WanderTheme.surfaceSand.color : WanderTheme.terracotta.color)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || isSaved)
            .accessibilityLabel(isSaved ? "Saved to my map" : "Save to my map")
        }
    }

    private var headline: String {
        let actor = activity.actor.displayName
    return switch activity.kind {
        case .placeSaved:
            "\(actor) saved \(activity.place?.place.canonicalName ?? "a place")"
        case .placeBeen:
            "\(actor) marked \(activity.place?.place.canonicalName ?? "a place") Been"
        case .placeWannaGo:
            "\(actor) added \(activity.place?.place.canonicalName ?? "a place") to Want to go"
        case .listCreated:
            "\(actor) created \(activity.list?.name ?? "a list")"
        case .listItemAdded:
            "\(actor) added \(activity.place?.place.canonicalName ?? "a place") to \(activity.list?.name ?? "a list")"
        }
    }

    private var metadata: String {
        if let place = activity.place {
            return placeDetail(for: place)
        }
        if let list = activity.list {
            let count = list.cachedItemCount ?? 0
            return count == 1 ? "1 place" : "\(count) places"
        }
        return "From someone you follow"
    }
}

private struct FeedMediaRail: View {
    let media: [FeedMediaPreview]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(media) { preview in
                    Group {
                        if let url = preview.urlString.flatMap(URL.init(string:)) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                FeedMediaPlaceholder()
                            }
                        } else {
                            FeedMediaPlaceholder()
                        }
                    }
                    .frame(width: 152, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    .accessibilityLabel(preview.accessibilityLabel)
                }
            }
        }
    }
}

private struct FeedMediaPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(WanderTheme.textOnAction.color.opacity(0.82))
        }
    }
}

private struct FeedPlaceArtwork: View {
    let place: VisiblePlace
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: categorySymbol(for: place.effectiveCategory))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private struct FeedLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            FeedSectionHeading(title: "Featured for you")
            HStack(spacing: WanderTheme.spacing3) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: 184, height: 218)
                }
            }
            FeedSectionHeading(title: "Your feed")
            VStack(spacing: WanderTheme.spacing3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(height: 142)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading Feed")
    }
}

private struct FeedEmptyState: View {
    let recommendations: [DiscoverPeopleRecommendation]
    let followingProfileIDs: Set<String>
    let openSearch: () -> Void
    let openProfile: (ProfileShell) -> Void
    let follow: (DiscoverPeopleRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("Your Feed fills up from people you follow.")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Find people whose place memory you’d actually use, then come back here to catch up.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if recommendations.isEmpty {
                Button("Find people", action: openSearch)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(minHeight: 44)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
                    .accessibilityLabel("Find people to follow")
            } else {
                ForEach(recommendations) { recommendation in
                    HStack(spacing: WanderTheme.spacing3) {
                        Button {
                            openProfile(recommendation.profile)
                        } label: {
                            WanderAvatar(
                                initials: initials(for: recommendation.profile.displayName),
                                avatarURL: recommendation.profile.avatarURL,
                                size: 44,
                                color: WanderTheme.skyTint.color
                            )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.profile.displayName)
                                .font(.system(size: 15, weight: .black))
                            Text(recommendation.reason.displayText(for: recommendation.profile))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Button {
                            follow(recommendation)
                        } label: {
                            if followingProfileIDs.contains(recommendation.profile.id) {
                                ProgressView()
                                    .tint(WanderTheme.terracotta.color)
                                    .frame(width: 44, height: 44)
                            } else {
                                Text("Follow")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(WanderTheme.terracotta.color)
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(followingProfileIDs.contains(recommendation.profile.id))
                    }
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedRetryRow: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer(minLength: 0)

            Button(actionTitle) {
                Task { await retry() }
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(minHeight: 44)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private func initials(for name: String) -> String {
    name
        .split(separator: " ")
        .prefix(2)
        .compactMap(\.first)
        .map(String.init)
        .joined()
        .uppercased()
}

private func placeDetail(for place: VisiblePlace) -> String {
    [
        place.effectiveCategoryDisplay.compactTitle,
        place.place.locality,
        place.place.region
    ]
    .compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    .joined(separator: " · ")
}

private func categorySymbol(for category: String) -> String {
    switch WanderPlaceCategory.normalizedPrimaryCategory(category) {
    case WanderPlaceCategory.coffeeTeaSweets:
        "cup.and.saucer.fill"
    case WanderPlaceCategory.restaurantsFood:
        "fork.knife"
    case WanderPlaceCategory.outdoorsNature:
        "mountain.2.fill"
    case WanderPlaceCategory.barsNightlife:
        "wineglass.fill"
    default:
        "mappin.and.ellipse"
    }
}
