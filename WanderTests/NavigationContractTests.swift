import XCTest
import UIKit
import MapKit
import SwiftUI
@testable import Wander

final class NavigationContractTests: XCTestCase {
    func testAppRootRoutesSignedOutSessionsThroughLoggedOutOnboarding() throws {
        let app = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderApp.swift")
        )
        let entry = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/AppEntryView.swift")
        )
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let authStore = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Services/Auth/AuthSessionProviding.swift"
            )
        )

        XCTAssertTrue(app.contains("AppEntryView(coordinator: entryCoordinator, analytics: analytics, parser: discoverParser)"))
        XCTAssertTrue(entry.contains("case .signedOut:"))
        XCTAssertTrue(entry.contains("LoggedOutCarouselView(analytics: analytics)"))
        XCTAssertTrue(entry.contains("auth.beginSignIn(mode: .signUp)"))
        XCTAssertTrue(entry.contains("auth.beginSignIn(mode: .signIn)"))
        XCTAssertTrue(entry.contains("case .ready(let session):"))
        XCTAssertTrue(entry.contains("initialSession: session"))
        XCTAssertTrue(entry.contains("isSessionValidated: auth.isSessionValidated"))
        XCTAssertTrue(entry.contains(".sheet(isPresented: $auth.isPresentingNativeAuth"))
        XCTAssertTrue(entry.contains("ClerkNativeAuthView(mode: auth.activeNativeAuthMode)"))
        XCTAssertTrue(entry.contains("case .background:"))
        XCTAssertTrue(entry.contains("foregroundRefreshPolicy.didEnterBackground("))
        XCTAssertTrue(entry.contains("case .active:"))
        XCTAssertTrue(entry.contains("foregroundRefreshPolicy.shouldRefreshSession("))
        XCTAssertFalse(authStore.contains("willEnterForegroundNotification"))
        XCTAssertTrue(root.contains("store.apply(authState: .signedIn(initialSession))"))
        XCTAssertTrue(root.contains(".task(id: isSessionValidated)"))
        XCTAssertTrue(root.contains("guard phase == .active, isSessionValidated else { return }"))
        XCTAssertTrue(root.contains("guard isSessionValidated,"))
    }

    func testNavigationModelRetainsAddRouteWhileHeaderExperimentOwnsVisibleEntryPoint() throws {
        XCTAssertEqual(WanderTab.allCases, [.map, .discover, .add, .lists, .profile])

        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        XCTAssertFalse(root.contains("Label(WanderTab.add.title"))
        XCTAssertTrue(root.contains("private func presentAddSheet()"))
    }

    func testDiscoverTabPresentsTheDedicatedFeedWithPersistentSearchLauncher() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )

        XCTAssertTrue(root.contains("FeedScreen(onAdd: presentAddSheet)"))
        XCTAssertTrue(root.contains("case .discover: \"Feed\""))
        XCTAssertTrue(root.contains("case .discover: \"newspaper\""))
        XCTAssertFalse(feed.contains(".navigationTitle(\"Feed\")"))
        XCTAssertFalse(feed.contains("ToolbarItem(placement: .topBarTrailing)"))
        XCTAssertTrue(feed.contains("private struct FeedSearchLauncher"))
        XCTAssertTrue(feed.contains("FeedSearchLauncher(placeholders: tickerSuggestions)"))
        XCTAssertTrue(feed.contains("isShowingSearch = true"))
        XCTAssertTrue(feed.contains(".accessibilityLabel(\"Search places and people\")"))
        XCTAssertTrue(feed.contains(".accessibilityIdentifier(\"feed.searchLauncher\")"))
        XCTAssertTrue(feed.contains(".fullScreenCover(isPresented: $isShowingSearch)"))
        XCTAssertTrue(feed.contains("DiscoverScreen("))
        XCTAssertTrue(feed.contains("startsInPlaceSearch: true"))
        XCTAssertTrue(feed.contains("onClose: { isShowingSearch = false }"))
        let discover = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        XCTAssertTrue(discover.contains("if selectedMode == .places, isPlaceSearchPresented"))
        XCTAssertTrue(discover.contains("activePlaceSearchHeader"))
        XCTAssertTrue(discover.contains("searchFieldFocused = true"))
        XCTAssertTrue(discover.contains("onClose == nil ? \"Back to Discover\" : \"Back to Feed\""))
        XCTAssertTrue(discover.contains(".accessibilityIdentifier(\"discover.searchBack\")"))
        XCTAssertFalse(discover.contains(".accessibilityIdentifier(\"discover.close\")"))
        XCTAssertTrue(discover.contains(".accessibilityIdentifier(accessibilityIdentifier)"))
        XCTAssertFalse(discover.contains("DiscoverHeader"))
        XCTAssertTrue(discover.contains("suggestedSearchesSection"))
        XCTAssertTrue(feed.contains("private struct FeedActivityModule"))
        XCTAssertTrue(feed.contains("private struct FeedFeaturedCard"))
        XCTAssertTrue(feed.contains("private enum FeedSurface"))
        XCTAssertTrue(feed.contains("private struct FeedSurfaceTabs"))
        XCTAssertTrue(feed.contains("case .people:"))
        XCTAssertTrue(feed.contains("FeedPeopleSurface(openProfile: openProfile)"))
        XCTAssertTrue(feed.contains("PeopleRecommendationShelf("))
        XCTAssertTrue(feed.contains("store.discoverMembers(query: query, backend: backend)"))
        XCTAssertTrue(feed.contains("store.refreshDiscoverPeopleRecommendations(backend: backend, force: force)"))
    }

    func testPrimarySurfacesShareLiquidGlassHeaderNavigationWithoutLosingFilterState() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let lists = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )

        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(theme.contains(".glassEffect("))
        XCTAssertTrue(theme.contains(".background(.ultraThinMaterial"))
        XCTAssertTrue(theme.contains("struct WanderGlassHeader<Accessory: View>"))
        XCTAssertTrue(theme.contains("struct WanderGlassSegmentedSwitch"))

        XCTAssertTrue(root.contains("onAdd: presentAddSheet"))
        XCTAssertTrue(root.contains("private func presentAddSheet()"))
        XCTAssertFalse(root.contains("Label(WanderTab.add.title"))
        XCTAssertTrue(map.contains("accessibilityIdentifier: \"map.headerAdd\""))
        XCTAssertTrue(map.contains("tone: isSelected ? .selected : .neutral"))
        XCTAssertTrue(map.contains("filter.trimColor(isSelected: isSelected)"))

        XCTAssertFalse(feed.contains("WanderGlassHeader("))
        XCTAssertTrue(feed.contains("accessibilityIdentifier: \"feed.headerAdd\""))
        XCTAssertTrue(feed.contains("WanderGlassSegmentedSwitch("))
        XCTAssertTrue(feed.contains("-WanderFeedSurface"))
        let feedControlRow = try XCTUnwrap(
            feed.components(separatedBy: "NavigationStack {").last?
                .components(separatedBy: "switch selectedSurface").first
        )
        XCTAssertTrue(feedControlRow.contains("HStack(spacing: WanderTheme.spacing2) {"))
        XCTAssertTrue(feedControlRow.contains("FeedSurfaceTabs(selectedSurface: $selectedSurface)"))
        XCTAssertTrue(feedControlRow.contains("WanderGlassActionButton("))
        let feedSearch = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedSearchLauncher: View").last?
                .components(separatedBy: "private struct FeedSectionHeading: View").first
        )
        XCTAssertTrue(feedSearch.contains(".wanderGlassCapsule()"))
        XCTAssertFalse(feedSearch.contains(".background(WanderTheme.surfaceRaised.color)"))
        let peopleSearch = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedPeopleSearchField: View").last?
                .components(separatedBy: "private struct FeedPeopleValueNote: View").first
        )
        XCTAssertTrue(peopleSearch.contains(".wanderGlassCapsule()"))
        XCTAssertFalse(peopleSearch.contains(".background(WanderTheme.surfaceRaised.color)"))

        XCTAssertTrue(lists.contains("WanderGlassHeader("))
        XCTAssertTrue(lists.contains("accessibilityIdentifier: \"lists.headerAdd\""))
        XCTAssertTrue(lists.contains("WanderGlassSegmentedSwitch("))
    }

    @MainActor
    func testLiquidGlassVisualQAStatesResolveDeterministically() {
        XCTAssertEqual(
            MapScreen.resolvedInitialMapSearchQuery(
                from: ["Wander", "-WanderMapSearchQuery", "coffee"]
            ),
            "coffee"
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapSearchQuery(from: ["Wander"]),
            ""
        )
    }

    func testFocusedMapSearchKeepsSafeChromeAndUsesABoundedGlassMenu() throws {
        let fixtureURL = projectRoot.appendingPathComponent(
            "WanderTests/Fixtures/rec-191-map-search-menu-pre.json"
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        XCTAssertEqual(
            fixture["bug"] as? String,
            "focused Map search shifts its header behind the status bar and lets the typeahead menu consume the map"
        )

        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(map.contains("if isMapSearchFocused {\n                                MapSearchCancelButton(action: cancelMapSearch)"))
        XCTAssertTrue(map.contains(".accessibilityIdentifier(\"map.searchCancel\")"))
        XCTAssertTrue(map.contains("if !isMapSearchFocused {\n                            ScrollView(.horizontal"))
        XCTAssertTrue(map.contains(".ignoresSafeArea(.keyboard, edges: .bottom)"))
        let typeahead = try XCTUnwrap(
            map.components(separatedBy: "private struct MapTypeaheadList: View").last?
                .components(separatedBy: "private struct MapTypeaheadRow: View").first
        )
        XCTAssertTrue(typeahead.contains("let visibleSuggestions = Array(suggestions.prefix(4))"))
        XCTAssertTrue(typeahead.contains(".wanderGlassPanel(cornerRadius: WanderTheme.radiusLarge)"))
        XCTAssertFalse(typeahead.contains(".background(WanderTheme.surfaceRaised.color)"))
    }

    func testFeedSaveUsesTheCanonicalPlaceSaveFlowAndMakesEveryActivityACompactTicket() throws {
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )

        XCTAssertTrue(feed.contains("MapPlaceSaveFlowSheet(context: context)"))
        XCTAssertTrue(feed.contains("MapPlaceSaveContext.addVisiblePlace("))
        XCTAssertTrue(feed.contains("persistNewPlaceSaveSubmission("))
        XCTAssertFalse(feed.contains("store.saveVisiblePlace("))

        let feedAfterActivityList = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityList: View").last
        )
        let activityList = try XCTUnwrap(
            feedAfterActivityList.components(separatedBy: "private struct FeedActivityModule: View").first
        )
        XCTAssertTrue(activityList.contains("LazyVStack(spacing: WanderTheme.spacing3)"))
        XCTAssertFalse(activityList.contains("Divider()"))
        XCTAssertFalse(activityList.contains(".background(WanderTheme.surfaceBone.color)"))
        XCTAssertFalse(activityList.contains(".clipShape(RoundedRectangle"))

        XCTAssertTrue(feed.contains("private enum FeedFeaturedLayout"))

        let activityModule = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityModule: View").last
        )
        XCTAssertTrue(activityModule.contains("private var activityTicket: some View"))
        XCTAssertTrue(activityModule.contains("activity.resolvedTicketKind"))
        XCTAssertTrue(activityModule.contains(".checkInTicketSurface("))
        XCTAssertTrue(activityModule.contains("WanderTypography.editorialCardTitle"))
        XCTAssertTrue(activityModule.contains("activity.note"))
        XCTAssertTrue(activityModule.contains("activity.rating"))
        XCTAssertTrue(activityModule.contains("Text(\"“\\(note)”\")"))
        XCTAssertTrue(activityModule.contains("FeedActivityThumbnail(activity: activity)"))
        XCTAssertTrue(activityModule.contains("Button(action: openActivityDestination)"))
        XCTAssertTrue(activityModule.contains("if let place = activity.place"))
        XCTAssertTrue(activityModule.contains("openPlace(place)"))
        XCTAssertTrue(activityModule.contains("openList(list)"))
        XCTAssertTrue(activityModule.contains("castsShadow: false"))
        XCTAssertFalse(activityModule.contains("lightweightActivityRow"))
        XCTAssertFalse(activityModule.contains("Label(\"View place\""))
        XCTAssertFalse(activityModule.contains("FeedMediaRail"))
        XCTAssertFalse(activityModule.contains("FeedActivityLayout.rowHeight"))
        XCTAssertFalse(activityModule.contains("maxHeight:"))

        let featuredCard = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedFeaturedCard: View").last?
                .components(separatedBy: "private struct FeedActivityList: View").first
        )
        XCTAssertFalse(featuredCard.contains("height: FeedFeaturedLayout.cardHeight"))
        XCTAssertTrue(featuredCard.contains("width: FeedFeaturedLayout.cardWidth"))
        XCTAssertTrue(featuredCard.contains("private var featuredActivity: String"))
        XCTAssertTrue(featuredCard.contains("WanderAvatar("))
        XCTAssertTrue(featuredCard.contains("openProfile(featured.actor)"))
        XCTAssertTrue(featuredCard.contains("avatarURL: featured.actor.avatarURL"))
        XCTAssertTrue(featuredCard.contains("• \\(featured.actor.displayName) • \\(featuredActivity)"))
        XCTAssertFalse(featuredCard.contains("avatarURL: featured.visiblePlace.owner.avatarURL"))
        XCTAssertTrue(featuredCard.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(featuredCard.contains("Label(\"View place\""))
    }

    func testFeedFeaturedRailAndMapTicketResolveRealPhotosBeforeFallbackArtwork() throws {
        let fixtureURL = projectRoot
            .appendingPathComponent("WanderTests/Fixtures/rec-161-photo-fallback-pre.json")
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        XCTAssertEqual(
            fixture["bug"] as? String,
            "real place and check-in photos are replaced by category artwork"
        )

        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let featuredArtwork = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedPlaceArtwork: View").last?
                .components(separatedBy: "private struct FeedLoadingState: View").first
        )
        XCTAssertTrue(featuredArtwork.contains("@EnvironmentObject private var backend: WanderBackend"))
        XCTAssertTrue(featuredArtwork.contains("@State private var photo: PlacePhoto?"))
        XCTAssertTrue(featuredArtwork.contains("await backend.placePhoto("))
        XCTAssertTrue(featuredArtwork.contains("PlaceProfilePhotoImage("))
        XCTAssertTrue(featuredArtwork.contains("onLoadFailure:"))

        let activityThumbnail = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityThumbnail: View").last?
                .components(separatedBy: "private struct FeedActivityArtworkFallback: View").first
        )
        XCTAssertTrue(activityThumbnail.contains("FeedResolvedPlacePhoto(place: place)"))

        let mapSurface = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let localPhotoSelection = try XCTUnwrap(
            mapSurface.components(separatedBy: "private var localPhoto: PlacePhoto?").last?
                .components(separatedBy: "private var photoResolutionKey: String").first
        )
        XCTAssertTrue(localPhotoSelection.contains("PlaceProfilePreviewPhotoPolicy.canUseCurrentUserLocalPhoto("))
        XCTAssertFalse(localPhotoSelection.contains("!store.isPrivateProfile"))
        XCTAssertFalse(localPhotoSelection.contains("visibility == .followers"))

        let localPhotoPolicy = try XCTUnwrap(
            mapSurface.components(separatedBy: "enum PlaceProfilePreviewPhotoPolicy").last?
                .components(separatedBy: "private struct PlaceProfilePreviewCard: View").first
        )
        XCTAssertTrue(localPhotoPolicy.contains("owner.id == currentUserID"))
    }

    func testDebugRedesignCaptureUsesDeterministicPhotoBackendWithoutWeakeningProductionAuth() throws {
        let app = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderApp.swift")
        )
        let mapCaptureRoot = try XCTUnwrap(
            app.components(separatedBy: "private var mapCaptureRoot: some View").last?
                .components(separatedBy: "private static func makeDiscoverParser").first
        )

        XCTAssertTrue(app.contains("struct MapCapturePlacePhotoRepository: PlacePhotoRepository"))
        XCTAssertTrue(app.contains("WanderBackend(placePhotoRepository: MapCapturePlacePhotoRepository())"))
        XCTAssertTrue(mapCaptureRoot.contains(".environmentObject(mapCaptureBackend)"))
        XCTAssertFalse(mapCaptureRoot.contains(".environmentObject(backend)"))
        XCTAssertTrue(app.contains("provider: \"google_places\""))
        XCTAssertTrue(app.contains("provider: \"visit_photo\""))
        XCTAssertTrue(app.contains("UIImage(named: assetName)"))
    }

    func testFeedPlaceActionsAllRouteThroughCurrentPlaceProfile() throws {
        let feed = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift"))
        let featuredRail = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedFeaturedRail: View").last?
                .components(separatedBy: "private struct FeedFeaturedCard: View").first
        )
        let featuredCard = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedFeaturedCard: View").last?
                .components(separatedBy: "private struct FeedActivityList: View").first
        )
        let activityList = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityList: View").last?
                .components(separatedBy: "private enum FeedFeaturedLayout").first
        )
        let activityModule = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityModule: View").last
        )
        XCTAssertTrue(feed.contains("@State private var selectedPlace: VisiblePlace?"))
        XCTAssertTrue(feed.contains(".navigationDestination(isPresented: selectedPlaceDestinationBinding)"))
        XCTAssertTrue(feed.contains("PlaceProfileFullScreen("))
        XCTAssertTrue(feed.contains("openPlace: openPlace"))

        XCTAssertTrue(featuredRail.contains("let openPlace: (VisiblePlace) -> Void"))
        XCTAssertTrue(featuredRail.contains("openPlace: openPlace"))
        XCTAssertFalse(featuredRail.contains("let save:"))
        XCTAssertTrue(featuredCard.contains("let openPlace: (VisiblePlace) -> Void"))
        XCTAssertTrue(featuredCard.contains("openPlace(featured.visiblePlace)"))
        XCTAssertFalse(featuredCard.contains("Label(\"View place\""))
        XCTAssertFalse(featuredCard.contains("save(featured)"))

        XCTAssertTrue(activityList.contains("let openPlace: (VisiblePlace) -> Void"))
        XCTAssertFalse(activityList.contains("let save:"))
        XCTAssertTrue(activityModule.contains("openProfile(activity.actor)"))
        XCTAssertTrue(activityModule.contains("openPlace(place)"))
        XCTAssertTrue(activityModule.contains("Text(activity.actor.displayName)"))
        XCTAssertTrue(activityModule.contains("Text(place.place.canonicalName)"))
        XCTAssertTrue(activityModule.contains("private var primaryDestinationTitle: some View"))
        XCTAssertTrue(activityModule.contains("openList(list)"))
        XCTAssertFalse(activityModule.contains("private var actionButton"))
        XCTAssertFalse(activityModule.contains("Label(\"View place\""))
        XCTAssertFalse(activityModule.contains("save(activity)"))

        XCTAssertFalse(feed.contains("private func saveFeaturedPlace("))
        XCTAssertFalse(feed.contains("private func save(_ activity: FeedActivity)"))
    }

    func testFeedRefreshFailureKeepsTheFeedStructureInsteadOfShowingAnEmptyState() throws {
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )

        XCTAssertTrue(feed.contains(".task(id: auth.isSignedIn)"))
        XCTAssertTrue(feed.contains("FeedRefreshRecoveryState(retry: refresh)"))
        XCTAssertTrue(feed.contains("private struct FeedRecoveryFeaturedRail"))
        XCTAssertTrue(feed.contains("private struct FeedRecoveryActivityList"))
        XCTAssertTrue(feed.contains("title: \"Couldn’t load Feed\""))
        XCTAssertTrue(feed.contains("detail: \"Unavailable\""))
        XCTAssertFalse(feed.contains("Feed is reconnecting"))
    }

    @MainActor
    func testProfileShareLinksResolveOnlyStableRecmeProfileRoutes() throws {
        XCTAssertEqual(
            WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "recme://profiles/user_joe"))),
            SharedProfileRoute(profileID: "user_joe")
        )
        XCTAssertEqual(
            WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "recme://profiles/user%20joe"))),
            SharedProfileRoute(profileID: "user joe")
        )
        XCTAssertEqual(
            WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "https://getrec.me/profiles/user_joe"))),
            SharedProfileRoute(profileID: "user_joe")
        )
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "https://rec.me/profiles/user_joe"))))
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "recme://places/place_1"))))
    }

    @MainActor
    func testSharedProfileContentBuildsTheRegisteredDeepLinkAndCopy() throws {
        let content = try XCTUnwrap(
            WanderShareContent.profile(serverID: "user joe", displayName: "Joe Example", handle: "joe")
        )

        XCTAssertEqual(content.item.absoluteString, "https://getrec.me/profiles/user%20joe")
        XCTAssertEqual(content.items, [content.item])
        XCTAssertEqual(content.subject, "Joe Example")
        XCTAssertEqual(content.message, "See @joe on rec.me")
        XCTAssertEqual(WanderRootView.sharedProfileRoute(for: content.item), SharedProfileRoute(profileID: "user joe"))
        XCTAssertNil(WanderShareContent.profile(serverID: nil, displayName: "Guest", handle: "you"))
        XCTAssertNil(WanderShareContent.profile(serverID: "   ", displayName: "Guest", handle: "you"))
    }

    @MainActor
    func testPlaceListAndInviteSharesUseCanonicalGetRecMeURLs() throws {
        let placeID = "40000000-0000-0000-0000-000000000001"
        let listID = "44000000-0000-0000-0000-000000000001"
        let inviteToken = String(repeating: "ab", count: 24)

        XCTAssertEqual(
            WanderShareContent.place(
                serverID: placeID,
                name: "Ggiata",
                message: "Worth remembering"
            )?.item.absoluteString,
            "https://getrec.me/places/\(placeID)"
        )
        XCTAssertEqual(
            WanderShareContent.list(
                serverID: listID,
                name: "Saturday plan"
            )?.item.absoluteString,
            "https://getrec.me/lists/\(listID)"
        )
        XCTAssertEqual(
            WanderShareContent.listInvite(
                token: inviteToken,
                name: "Saturday plan"
            )?.item.absoluteString,
            "https://getrec.me/invites/\(inviteToken)"
        )
        XCTAssertNil(
            WanderShareContent.place(
                serverID: "local-place",
                name: "Unsynced",
                message: "Not shareable yet"
            )
        )
    }

    @MainActor
    func testSharedProfileMapContentUsesSharedNativeShareWorker() throws {
        let imageFileURL = URL(fileURLWithPath: "/tmp/maya-map.png")
        let content = try XCTUnwrap(
            WanderShareContent.profileMap(
                serverID: "user maya",
                displayName: "Maya Chen",
                handle: "maya",
                imageFileURL: imageFileURL
            )
        )

        XCTAssertEqual(content.item.absoluteString, "https://getrec.me/profiles/user%20maya")
        XCTAssertEqual(content.items, [content.item, imageFileURL])
        XCTAssertEqual(content.subject, "Maya Chen's map")
        XCTAssertEqual(content.message, "Explore @maya's saved places on rec.me")
        XCTAssertEqual(WanderRootView.sharedProfileRoute(for: content.item), SharedProfileRoute(profileID: "user maya"))
    }

    func testSharedProfileMapContentRequiresAStableProfileAndPNGFile() {
        let pngFileURL = URL(fileURLWithPath: "/tmp/profile-map.PNG")
        let jpegFileURL = URL(fileURLWithPath: "/tmp/profile-map.jpg")
        let remotePNGURL = URL(string: "https://example.com/profile-map.png")!

        XCTAssertNil(
            WanderShareContent.profileMap(
                serverID: nil,
                displayName: "Guest",
                handle: "you",
                imageFileURL: pngFileURL
            )
        )
        XCTAssertNil(
            WanderShareContent.profileMap(
                serverID: "user_guest",
                displayName: "Guest",
                handle: "you",
                imageFileURL: jpegFileURL
            )
        )
        XCTAssertNil(
            WanderShareContent.profileMap(
                serverID: "user_guest",
                displayName: "Guest",
                handle: "you",
                imageFileURL: remotePNGURL
            )
        )
        XCTAssertNotNil(
            WanderShareContent.profileMap(
                serverID: "user_guest",
                displayName: "Guest",
                handle: "you",
                imageFileURL: pngFileURL
            )
        )
    }

    @MainActor
    func testFilteredProfileMapShareNamesTheSelectionAndKeepsLinkAndPNG() throws {
        let imageFileURL = URL(fileURLWithPath: "/tmp/maya-santa-monica-map.png")
        let content = try XCTUnwrap(
            WanderShareContent.profileMap(
                serverID: "user_maya",
                displayName: "Maya Chen",
                handle: "maya",
                imageFileURL: imageFileURL,
                filterTitle: "Santa Monica"
            )
        )

        XCTAssertEqual(content.items, [
            URL(string: "https://getrec.me/profiles/user_maya")!,
            imageFileURL
        ])
        XCTAssertEqual(content.subject, "Maya Chen's Santa Monica map")
        XCTAssertEqual(content.message, "Explore Santa Monica on @maya's rec.me map")
    }

    @MainActor
    func testFilteredProfileMapShareUsesSupportedActivitySubjectSource() {
        let controller = UIActivityViewController(
            activityItems: ["placeholder"],
            applicationActivities: nil
        )
        let source = WanderShareActivityItemSource(
            message: "Explore Santa Monica on @maya's rec.me map",
            subject: "Maya Chen's Santa Monica map"
        )

        XCTAssertEqual(
            source.activityViewControllerPlaceholderItem(controller) as? String,
            "Explore Santa Monica on @maya's rec.me map"
        )
        XCTAssertEqual(
            source.activityViewController(controller, itemForActivityType: nil) as? String,
            "Explore Santa Monica on @maya's rec.me map"
        )
        XCTAssertEqual(
            source.activityViewController(controller, subjectForActivityType: nil),
            "Maya Chen's Santa Monica map"
        )
    }

    @MainActor
    func testProfileMapPNGAttachmentsAreLosslessUniqueAndPruneOnlyExpiredFiles() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("wander-share-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: baseDirectory) }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 3),
            format: rendererFormat
        )
        let pngData = renderer.pngData { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }
        let now = Date()
        let attachmentDirectory = baseDirectory.appendingPathComponent(
            WanderShareAttachmentStore.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)

        let expiredFileURL = attachmentDirectory.appendingPathComponent("expired.png")
        let freshFileURL = attachmentDirectory.appendingPathComponent("fresh.png")
        try pngData.write(to: expiredFileURL)
        try pngData.write(to: freshFileURL)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-WanderShareAttachmentStore.retentionInterval - 1)],
            ofItemAtPath: expiredFileURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-WanderShareAttachmentStore.retentionInterval + 1)],
            ofItemAtPath: freshFileURL.path
        )

        let firstFileURL = try WanderShareAttachmentStore.persistPNG(
            pngData,
            baseDirectory: baseDirectory,
            now: now,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            fileManager: fileManager
        )
        let secondFileURL = try WanderShareAttachmentStore.persistPNG(
            pngData,
            baseDirectory: baseDirectory,
            now: now,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            fileManager: fileManager
        )

        XCTAssertNotEqual(firstFileURL, secondFileURL)
        XCTAssertEqual(firstFileURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: firstFileURL), pngData)
        let decodedImage = try XCTUnwrap(UIImage(contentsOfFile: firstFileURL.path)?.cgImage)
        XCTAssertEqual(decodedImage.width, 4)
        XCTAssertEqual(decodedImage.height, 3)
        XCTAssertFalse(fileManager.fileExists(atPath: expiredFileURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: freshFileURL.path))

        XCTAssertThrowsError(
            try WanderShareAttachmentStore.persistPNG(
                Data("not a PNG".utf8),
                baseDirectory: baseDirectory,
                fileManager: fileManager
            )
        ) { error in
            guard case WanderShareAttachmentStore.AttachmentError.invalidPNG = error else {
                return XCTFail("Expected invalidPNG, got \(error)")
            }
        }
    }

    func testOtherMemberProfileUsesSharedHomeWithoutOwnerEditActions() throws {
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )

        XCTAssertTrue(profileScreen.contains("mode: .member("))
        XCTAssertTrue(profileScreen.contains("placesInCommon(with: profileID)"))
        XCTAssertTrue(home.contains("if mode.isOwner"))
        XCTAssertTrue(home.contains("label: \"IN COMMON\""))
        XCTAssertTrue(home.contains("WanderShareContent.profileMap("))
    }

    func testSharedProfileHomeHidesUnusedNavigationBar() throws {
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )

        XCTAssertTrue(home.contains(".toolbar(.hidden, for: .navigationBar)"))
    }

    func testOwnPlaceActivityAttributionIsStaticInsteadOfDisabled() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let activityCard = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private struct PlaceActivityCard: View")
                .last?
                .components(separatedBy: "private struct VisitPhotoThumbnail: View")
                .first
        )

        XCTAssertTrue(activityCard.contains("if entry.isCurrentUser"))
        XCTAssertTrue(activityCard.contains("activityIdentityLabel"))
        XCTAssertFalse(activityCard.contains(".disabled(entry.isCurrentUser)"))
    }

    func testMapFeedAndPlaceHistoryShareTheDirectionATicketSurface() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let ticketSurface = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/CheckInTicketSurface.swift")
        )
        let activityCard = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private struct PlaceActivityCard: View")
                .last?
                .components(separatedBy: "private struct VisitPhotoThumbnail: View")
                .first
        )

        XCTAssertTrue(ticketSurface.contains("func checkInTicketSurface("))
        XCTAssertTrue(ticketSurface.contains("struct CheckInTicketShape: InsettableShape"))
        XCTAssertTrue(ticketSurface.contains("borderWidth: CGFloat = 1"))
        XCTAssertTrue(ticketSurface.contains(".clipShape(ticketShape)"))
        XCTAssertTrue(ticketSurface.contains("addTrailingNotch("))
        XCTAssertFalse(ticketSurface.contains("Circle()\n            .fill(surroundingSurface)"))
        XCTAssertFalse(ticketSurface.contains(".compositingGroup()"))
        XCTAssertTrue(ticketSurface.contains("case trailing"))
        XCTAssertTrue(ticketSurface.contains("case both"))
        XCTAssertTrue(placeProfile.contains(".checkInTicketSurface("))
        let previewCard = try XCTUnwrap(
            placeProfile
                .components(separatedBy: "private struct PlaceProfilePreviewCard: View")
                .last?
                .components(separatedBy: "private struct PlaceProfileFullView: View")
                .first
        )
        XCTAssertFalse(previewCard.contains("ticketEyebrow"))
        XCTAssertFalse(previewCard.contains("YOUR CHECK-IN"))
        XCTAssertFalse(previewCard.contains("YOUR WANNA"))
        XCTAssertTrue(mapScreen.contains("Text(\"check-in history\")"))
        XCTAssertTrue(activityCard.contains(".checkInTicketSurface("))
        XCTAssertTrue(activityCard.contains("ticketAccentColor"))
        XCTAssertTrue(activityCard.contains("WanderTypography.editorialCardTitle"))
        XCTAssertTrue(activityCard.contains("StatusBadge(status: entry.status)"))
        XCTAssertTrue(activityCard.contains("if let note = entry.note"))
        XCTAssertTrue(activityCard.contains("ForEach(entry.tags.prefix(6)"))
        XCTAssertTrue(activityCard.contains("photoThumbnails"))
        XCTAssertTrue(activityCard.contains("addPhotoControl"))

        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        XCTAssertTrue(feed.contains("WanderTheme.stateInfo.color"))
        XCTAssertTrue(feed.contains("borderWidth: 1.5"))
        XCTAssertTrue(feed.contains("activity.resolvedTicketKind"))
        XCTAssertFalse(feed.contains("DROPPED A PIN"))
    }

    func testTicketShapeUsesAConcaveCutoutInsteadOfAnAddedCircle() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let trailingPath = CheckInTicketShape(notchEdges: .trailing).path(in: rect)

        XCTAssertFalse(trailingPath.contains(CGPoint(x: 199, y: 50)))
        XCTAssertFalse(trailingPath.contains(CGPoint(x: 195, y: 50)))
        XCTAssertTrue(trailingPath.contains(CGPoint(x: 180, y: 50)))
        XCTAssertTrue(trailingPath.contains(CGPoint(x: 199, y: 30)))
        XCTAssertTrue(trailingPath.contains(CGPoint(x: 199, y: 70)))

        let bothEdgesPath = CheckInTicketShape(notchEdges: .both).path(in: rect)
        XCTAssertFalse(bothEdgesPath.contains(CGPoint(x: 1, y: 50)))
        XCTAssertTrue(bothEdgesPath.contains(CGPoint(x: 20, y: 50)))
    }

    func testEditorialTypographyUsesSemanticRolesAndNativeChromeWithoutChangingStreak() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let streak = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Streak/SaveStreakCelebrationView.swift")
        )

        let typography = try XCTUnwrap(
            theme.components(separatedBy: "enum WanderTypography").last?
                .components(separatedBy: "private extension Color").first
        )
        XCTAssertTrue(typography.contains("Font.system(.largeTitle, design: .serif"))
        XCTAssertTrue(typography.contains("Font.system(.title3, design: .serif"))
        XCTAssertTrue(typography.contains("Font.system(.body, design: .default"))
        XCTAssertFalse(typography.contains("size:"))

        XCTAssertFalse(feed.contains(".navigationTitle(\"Feed\")"))
        XCTAssertTrue(feed.contains("FeedSearchLauncher(placeholders: tickerSuggestions)"))
        XCTAssertTrue(feed.contains("WanderGlassSegmentedSwitch("))
        XCTAssertFalse(feed.contains("Picker(\"Feed section\", selection: $selectedSurface)"))

        XCTAssertTrue(placeProfile.contains(".navigationTitle(place.name)"))
        XCTAssertTrue(placeProfile.contains("ToolbarItem(placement: .topBarLeading)"))
        XCTAssertTrue(placeProfile.contains("ToolbarItemGroup(placement: .topBarTrailing)"))
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(mapScreen.contains("NavigationStack {\n                    selectedPlaceProfileDestination"))
        let mapHeader = try XCTUnwrap(
            placeProfile.components(separatedBy: "private struct PlaceProfileMapHeader: View").last
        )
        XCTAssertFalse(mapHeader.contains("Button(action: onBack)"))
        XCTAssertFalse(mapHeader.contains("WanderShareButton"))

        XCTAssertFalse(streak.contains("WanderTypography"))
        XCTAssertTrue(streak.contains(".font(.system(size: 29, weight: .black, design: .serif))"))
    }

    func testDirectionCTypographyTargetsNamedContentHeadingsAndCustomMastheads() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let lists = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let discover = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let profile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let streak = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Streak/SaveStreakCelebrationView.swift")
        )

        let typography = try XCTUnwrap(
            theme.components(separatedBy: "enum WanderTypography").last?
                .components(separatedBy: "private extension Color").first
        )
        XCTAssertTrue(typography.contains("editorialMasthead = Font.system(.title, design: .serif, weight: .bold)"))
        XCTAssertTrue(typography.contains("editorialNamedContent = Font.system(.headline, design: .serif, weight: .bold)"))
        XCTAssertTrue(typography.contains("editorialSmallNamedContent = Font.system(.subheadline, design: .serif, weight: .bold)"))
        XCTAssertTrue(typography.contains("editorialMajorSectionTitle = Font.system(.title2, design: .serif, weight: .semibold)"))

        XCTAssertEqual(lists.components(separatedBy: "WanderTypography.editorialMasthead").count - 1, 1)
        XCTAssertEqual(lists.components(separatedBy: "WanderTypography.editorialNamedContent").count - 1, 4)
        XCTAssertEqual(lists.components(separatedBy: "WanderTypography.editorialSmallNamedContent").count - 1, 2)
        XCTAssertTrue(lists.contains("subtitle: \"save places into a plan you can actually use\""))
        XCTAssertTrue(lists.contains("WanderGlassHeader("))

        let discoverMastheadUses = discover.components(separatedBy: "WanderTypography.editorialMasthead").count - 1
        XCTAssertEqual(discoverMastheadUses, 1)
        XCTAssertFalse(discover.contains("Text(\"Ask for a place the way you'd ask a friend\")"))
        XCTAssertEqual(discover.components(separatedBy: "WanderTypography.editorialNamedContent").count - 1, 2)
        let discoverSearch = try XCTUnwrap(
            discover.components(separatedBy: "private struct DiscoverSearchField: View").last?
                .components(separatedBy: "private struct DiscoverPlaceResultCard: View").first
        )
        XCTAssertTrue(discoverSearch.contains("TextField(\"\", text: $text)\n                    .font(.system(size: 15, weight: .bold))"))
        XCTAssertFalse(discoverSearch.contains("WanderTypography.editorial"))
        XCTAssertTrue(discoverSearch.contains(".wanderGlassCapsule()"))
        XCTAssertFalse(discoverSearch.contains(".background(WanderTheme.surfaceRaised.color)"))

        XCTAssertTrue(profile.contains("Text(profile.displayName)\n                        .font(WanderTypography.editorialDisplay)"))
        XCTAssertEqual(profile.components(separatedBy: "WanderTypography.editorialMajorSectionTitle").count - 1, 3)
        let profileStreak = try XCTUnwrap(
            profile.components(separatedBy: "private struct ProfileSaveStreakRow: View").last?
                .components(separatedBy: "#if DEBUG").first
        )
        XCTAssertFalse(profileStreak.contains("editorialMasthead"))
        XCTAssertFalse(profileStreak.contains("editorialNamedContent"))
        XCTAssertFalse(profileStreak.contains("editorialMajorSectionTitle"))

        for source in [feed, streak] {
            XCTAssertFalse(source.contains("editorialMasthead"))
            XCTAssertFalse(source.contains("editorialNamedContent"))
            XCTAssertFalse(source.contains("editorialSmallNamedContent"))
            XCTAssertFalse(source.contains("editorialMajorSectionTitle"))
        }
    }

    func testOverallPlaceProfileRatingsUseEditorialSerifWithoutChangingCheckInRatings() throws {
        let fixtureURL = projectRoot
            .appendingPathComponent("WanderTests/Fixtures/rec-161-profile-ratings-pre.json")
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        XCTAssertEqual(
            fixture["bug"] as? String,
            "overall place-profile rating values use the same heavy sans treatment as utility labels"
        )

        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let ratingSlider = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/PlaceRatingSlider.swift")
        )

        let typography = try XCTUnwrap(
            theme.components(separatedBy: "enum WanderTypography").last?
                .components(separatedBy: "private extension Color").first
        )
        XCTAssertTrue(typography.contains("editorialRatingDisplay"))
        XCTAssertTrue(typography.contains("editorialRatingSuffix"))
        XCTAssertTrue(typography.contains("design: .serif"))
        XCTAssertTrue(typography.contains(".monospacedDigit()"))

        let overallRatingTiles = try XCTUnwrap(
            placeProfile.components(separatedBy: "private struct PlaceProfileRatingTile: View").last?
                .components(separatedBy: "private struct PlaceProfileTagRail: View").first
        )
        XCTAssertTrue(overallRatingTiles.contains("WanderTypography.editorialRatingDisplay"))
        XCTAssertTrue(overallRatingTiles.contains("WanderTypography.editorialRatingSuffix"))
        XCTAssertFalse(overallRatingTiles.contains(".font(.system(size: valueFontSize, weight: .black))"))

        let checkInRatings = try XCTUnwrap(
            placeProfile.components(separatedBy: "private struct PlaceProfileSaveCard: View").last?
                .components(separatedBy: "private enum PlaceProfileCopy").first
        )
        XCTAssertFalse(checkInRatings.contains("editorialRatingDisplay"))
        XCTAssertFalse(checkInRatings.contains("editorialRatingSuffix"))
        XCTAssertFalse(feed.contains("editorialRatingDisplay"))
        XCTAssertFalse(feed.contains("editorialRatingSuffix"))
        XCTAssertFalse(ratingSlider.contains("editorialRatingDisplay"))
        XCTAssertFalse(ratingSlider.contains("editorialRatingSuffix"))
    }

    func testUnavailableContentAvoidsStackedOpacityTreatments() throws {
        let privateProfileFiles = [
            "Wander/Features/Add/AddScreen.swift",
            "Wander/Features/Map/MapScreen.swift",
            "Wander/Features/Settings/ProfileSettingsViews.swift",
            "Wander/Features/Settings/SettingsScreen.swift",
            "Wander/Features/Lists/ListsScreen.swift"
        ]

        for file in privateProfileFiles {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(file))
            XCTAssertFalse(
                source.contains(".opacity(store.isPrivateProfile ? 0.56 : 1)"),
                "Private Profile controls should not compound disabled-state opacity in \(file)"
            )
        }

        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Settings/SettingsScreen.swift")
        )
        XCTAssertFalse(settings.contains(".opacity(notificationsEnabled ? 1 : 0.45)"))
        XCTAssertFalse(settings.contains(".disabled(action == nil)"))

        let staticAvatarFiles = [
            "Wander/Features/Lists/ListsScreen.swift",
            "Wander/Features/SharedVisits/SharedVisitComponents.swift"
        ]
        for file in staticAvatarFiles {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(file))
            XCTAssertFalse(
                source.contains(".disabled(onSelect == nil)"),
                "Static avatars should not be rendered through disabled buttons in \(file)"
            )
        }
    }

    func testAddTabPresentsTheCanonicalMapSaveFlowInsteadOfOwningASecondSavePath() throws {
        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        let suggestedSection = try XCTUnwrap(
            addScreen
                .components(separatedBy: "private var suggestedPlaces: some View")
                .last?
                .components(separatedBy: "private var confirmPlace: some View")
                .first
        )

        XCTAssertTrue(addScreen.contains("MapPlaceSaveFlowSheet(context: context)"))
        XCTAssertTrue(addScreen.contains("persistNewPlaceSaveSubmission("))
        XCTAssertFalse(addScreen.contains("store.saveCandidate("))
        XCTAssertFalse(addScreen.contains("private var detailsForm"))
        XCTAssertTrue(addScreen.contains("Text(\"Suggested\")"))
        XCTAssertTrue(addScreen.contains("Search for a place"))
        XCTAssertTrue(addScreen.contains("Label(\"Take a Photo\", systemImage: \"camera\")"))
        XCTAssertTrue(addScreen.contains("Label(\"Photo Library\", systemImage: \"photo.on.rectangle\")"))
        XCTAssertTrue(addScreen.contains("AddSuggestedPlaces.limited(nearby)"))
        XCTAssertTrue(addScreen.contains("static let maximumCount = 7"))
        XCTAssertTrue(suggestedSection.contains("Text(\"Suggested\")"))
        XCTAssertTrue(suggestedSection.contains("searchField"))
        XCTAssertTrue(suggestedSection.contains("AddSuggestedPlaces.previewCount("))
        XCTAssertTrue(suggestedSection.contains("Label(\"See more\", systemImage: \"arrow.up.right\")"))
        XCTAssertTrue(suggestedSection.contains("await resolveCurrentLocationCandidates()"))
        XCTAssertFalse(suggestedSection.contains("ScrollView(.vertical"))
        XCTAssertFalse(suggestedSection.contains("ScrollView(.horizontal"))
        XCTAssertTrue(addScreen.contains("if showsPinnedImportEntry"))
        XCTAssertTrue(addScreen.contains("private var compactSheetContent: some View"))
        XCTAssertTrue(addScreen.contains("private var compactSourceContent: some View"))
        XCTAssertTrue(addScreen.contains("isShowingHereNowResults ? \"I'm here now\""))
        XCTAssertTrue(addScreen.contains("\"choose the place you're at\""))
        XCTAssertFalse(addScreen.contains("title: \"From a photo\""))
        XCTAssertFalse(addScreen.contains("SourceRow(title: AddSourceType.manual.title"))
    }

    func testSuccessfulMapSaveWaitsForSheetDismissalBeforeSelectingSavedPlace() throws {
        let result = SaveResult(userPlaceID: "saved-place", syncState: .synced)
        var coordinator = MapSaveFlowSelectionCoordinator()

        XCTAssertNil(coordinator.saveFlowDidDismiss())

        coordinator.saveDidSucceed(result)

        XCTAssertEqual(coordinator.saveFlowDidDismiss(), result)
        XCTAssertNil(coordinator.saveFlowDidDismiss())

        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let saveSubmission = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private func saveMapFlowSubmission")
                .last?
                .components(separatedBy: "private func scopedSaveMessage")
                .first
        )
        XCTAssertEqual(
            saveSubmission.components(separatedBy: "mapSaveFlowSelection.saveDidSucceed(result)").count - 1,
            2
        )
        XCTAssertFalse(saveSubmission.contains("selectSavedResult(result)"))
        XCTAssertTrue(mapScreen.contains("if let result = mapSaveFlowSelection.saveFlowDidDismiss()"))
    }

    func testAddSuggestedPlacesScalePreviewCountByScreenHeight() {
        let candidates = (0..<8).map { index in
            PlaceCandidate(
                id: "candidate_\(index)",
                name: "Candidate \(index)",
                category: "coffee",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.9
            )
        }
        let limited = AddSuggestedPlaces.limited(candidates)

        XCTAssertEqual(limited.count, 7)
        XCTAssertEqual(AddSuggestedPlaces.previewCount(screenHeight: 956), 3)
        XCTAssertEqual(AddSuggestedPlaces.previewCount(screenHeight: 874), 2)
        XCTAssertEqual(AddSuggestedPlaces.previewCount(screenHeight: 667), 1)
        XCTAssertEqual(AddSuggestedPlaces.visible(limited, count: 3).count, 3)
        XCTAssertEqual(AddSuggestedPlaces.visible(limited, count: 2).count, 2)
        XCTAssertEqual(AddSuggestedPlaces.visible(limited, count: 1).count, 1)
    }

    func testCurrentLocationCandidateActionFloatsAboveScrollableResults() throws {
        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        let confirmPlace = try XCTUnwrap(
            addScreen
                .components(separatedBy: "private var confirmPlace: some View")
                .last?
                .components(separatedBy: "private var draftView: some View")
                .first
        )

        XCTAssertTrue(addScreen.contains("private var showsFloatingCurrentLocationAction: Bool"))
        XCTAssertTrue(addScreen.contains("selectedSource == .currentLocation"))
        XCTAssertTrue(addScreen.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(addScreen.contains("if showsFloatingCurrentLocationAction"))
        XCTAssertTrue(confirmPlace.contains("if !showsFloatingCurrentLocationAction"))
        XCTAssertEqual(
            addScreen.components(separatedBy: "WanderPrimaryButton(title: \"Save\"").count - 1,
            1,
            "The floating and in-flow layouts should share one Save action implementation."
        )
        XCTAssertFalse(addScreen.contains("WanderPrimaryButton(title: \"continue\""))
    }

    func testAddOwnsPlaceImportsAndOnlyRendersReviewForPendingItems() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        let importViews = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileImportViews.swift")
        )
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let profileHome = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )

        XCTAssertTrue(root.contains("@StateObject private var importStore: PlaceImportStore"))
        XCTAssertTrue(root.contains("importStore: importStore"))
        XCTAssertTrue(addScreen.contains("AddImportEntrySection("))
        XCTAssertTrue(addScreen.contains("PlaceImportHubScreen("))
        XCTAssertFalse(addScreen.contains("PlaceImportSourceScreen("))
        XCTAssertTrue(addScreen.contains("PlaceImportInboxScreen(importStore: importStore)"))
        XCTAssertTrue(addScreen.contains("emptyRestingHeight: CGFloat = 520"))
        XCTAssertTrue(addScreen.contains("pendingReviewRestingHeight: CGFloat = 570"))
        XCTAssertTrue(
            root.contains(
                "AddSheetLayout.detents(\n                        hasPendingImports: importStore.summary.hasPendingImports"
            )
        )
        XCTAssertTrue(root.contains(".onChange(of: importStore.summary.hasPendingImports)"))
        XCTAssertTrue(importViews.contains("if summary.hasPendingImports"))
        XCTAssertTrue(importViews.contains("Text(\"Import from\")"))
        XCTAssertTrue(importViews.contains("TextEditor(text: $input)"))
        XCTAssertTrue(importViews.contains("enqueueUnified(text: input)"))
        XCTAssertTrue(importViews.contains("private let sources: [PlaceImportSource] = [.googleMaps, .instagram, .tiktok]"))
        XCTAssertFalse(importViews.contains("ForEach(PlaceImportSource.allCases)"))
        XCTAssertTrue(importViews.contains("Image(systemName: \"questionmark.circle\")"))
        XCTAssertTrue(importViews.contains("https://getrec.me/import-help"))
        XCTAssertFalse(profileScreen.contains("PlaceImportStore"))
        XCTAssertFalse(profileHome.contains("ImportSection"))
    }

    func testChoosePlaceUsesEmojiCardsWithProfileNavigationAndCompactActions() throws {
        let importViews = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileImportViews.swift")
        )

        XCTAssertTrue(importViews.contains("PlaceImportCandidateCard("))
        XCTAssertTrue(importViews.contains("private var candidateArtwork: some View"))
        XCTAssertTrue(importViews.contains("WanderCategoryEmoji(emoji: candidate.categoryEmoji"))
        XCTAssertTrue(importViews.contains("profileCandidate = candidate"))
        XCTAssertTrue(importViews.contains("PlaceProfileFullScreen("))
        XCTAssertTrue(importViews.contains("place: PlaceSheetPlace(candidate: profileCandidate)"))
        XCTAssertTrue(importViews.contains("action: .choose"))
        XCTAssertTrue(importViews.contains("Shows the place profile and photo"))
        XCTAssertTrue(importViews.contains("Text(candidate.importCategoryTitle)"))
        XCTAssertTrue(importViews.contains("Text(candidate.importLocationSummary)"))
        XCTAssertTrue(importViews.contains("Capsule()"))
        XCTAssertTrue(importViews.contains(".frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)"))
        XCTAssertTrue(importViews.contains("-WanderPlaceImportCandidateMockup"))
        XCTAssertFalse(importViews.contains("PlaceImportCandidatePhoto"))
        XCTAssertFalse(importViews.contains("candidate.importPhotoRequest"))
        XCTAssertFalse(importViews.contains("backend.placePhoto(for: candidate.importPhotoRequest)"))

        let cardSource = try XCTUnwrap(
            importViews
                .components(separatedBy: "private struct PlaceImportCandidateCard: View")
                .last?
                .components(separatedBy: "private extension PlaceCandidate")
                .first
        )
        XCTAssertTrue(cardSource.contains(".font(.headline.weight(.heavy))"))
        XCTAssertTrue(cardSource.contains(".font(.caption.weight(.medium))"))
        XCTAssertFalse(cardSource.contains(".font(.system(size:"))
    }

    func testCanonicalSaveDetailsStayCompactAndCollapseNotesWithOptionalQuestions() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertEqual(mapScreen.components(separatedBy: "private var detailsContent: some View").count, 2)
        XCTAssertEqual(mapScreen.components(separatedBy: "private var noteSection: some View").count, 2)
        XCTAssertEqual(mapScreen.components(separatedBy: "private var optionalDetailsDisclosure: some View").count, 2)
        XCTAssertEqual(mapScreen.components(separatedBy: "private var saveFooter: some View").count, 2)
        XCTAssertEqual(mapScreen.components(separatedBy: "private var removeSaveSection: some View").count, 2)
        let detailsContent = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private var detailsContent: some View")
                .last?
                .components(separatedBy: "private var noteSection: some View")
                .first
        )
        let optionalDetails = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private var optionalDetailsDisclosure: some View")
                .last?
                .components(separatedBy: "private var removeSaveSection: some View")
                .first
        )

        XCTAssertFalse(detailsContent.contains("saveAsSection"))
        XCTAssertTrue(detailsContent.contains("placeTypeSection"))
        XCTAssertTrue(detailsContent.contains("if selectedStatus == .been"))
        XCTAssertTrue(detailsContent.contains("checkInDateSection"))
        XCTAssertTrue(detailsContent.contains("ratingSection"))
        XCTAssertTrue(detailsContent.contains("sharedVisitInviteSection"))
        XCTAssertTrue(detailsContent.contains("MapSaveVisitPhotoSection("))
        XCTAssertFalse(detailsContent.contains("noteSection"))
        XCTAssertTrue(detailsContent.contains("optionalDetailsDisclosure"))
        XCTAssertFalse(detailsContent.contains("questionAndLabelSections"))
        XCTAssertFalse(detailsContent.contains("visibilitySection"))

        XCTAssertFalse(optionalDetails.contains("saveAsSection"))
        XCTAssertTrue(optionalDetails.contains("noteSection"))
        XCTAssertTrue(optionalDetails.contains("questionAndLabelSections"))
        XCTAssertTrue(optionalDetails.contains("visibilitySection"))
        XCTAssertTrue(optionalDetails.contains("note, tags & privacy"))
        XCTAssertEqual(
            mapScreen.components(separatedBy: "MapSavePickerBlock(title: \"what do you want to do?\")").count - 1,
            1
        )
        XCTAssertTrue(mapScreen.contains("if step == .details && context.requiresStatusConfirmation"))
        XCTAssertEqual(mapScreen.components(separatedBy: "Text(flowTitle)").count - 1, 1)
        XCTAssertTrue(mapScreen.contains("ZStack {"))
        XCTAssertTrue(mapScreen.contains(".multilineTextAlignment(.center)"))
        XCTAssertTrue(mapScreen.contains("alignment: .center"))
        XCTAssertTrue(mapScreen.contains("Spacer(minLength: 0)"))
        XCTAssertTrue(mapScreen.contains("minWidth: WanderTheme.tapMinimum"))
        XCTAssertTrue(mapScreen.contains("minHeight: WanderTheme.tapMinimum"))
        XCTAssertFalse(mapScreen.contains(".frame(width: 32, height: 32)"))
        XCTAssertTrue(mapScreen.contains("@State private var isShowingOptionalDetails = false"))
        XCTAssertFalse(mapScreen.contains("didSelectStatus"))
        XCTAssertTrue(mapScreen.contains(".padding(.top, WanderTheme.spacing1)"))
        XCTAssertTrue(mapScreen.contains("return status == .wannaGo ? \"Wanna go\" : \"Check in\""))
        XCTAssertTrue(mapScreen.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertFalse(mapScreen.contains("detailsSubtitle"))
        XCTAssertFalse(mapScreen.contains("add a few details"))

        let orderedMarkers = [
            "placeTypeSection",
            "ratingSection",
            "sharedVisitInviteSection",
            "MapSaveVisitPhotoSection(",
            "optionalDetailsDisclosure"
        ]
        let offsets = try orderedMarkers.map { marker in
            let range = try XCTUnwrap(detailsContent.range(of: marker), "Missing \(marker)")
            return detailsContent.distance(from: detailsContent.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(offsets, offsets.sorted())

        let optionalMarkers = [
            "noteSection",
            "questionAndLabelSections",
            "visibilitySection"
        ]
        let optionalOffsets = try optionalMarkers.map { marker in
            let range = try XCTUnwrap(optionalDetails.range(of: marker), "Missing \(marker)")
            return optionalDetails.distance(from: optionalDetails.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(optionalOffsets, optionalOffsets.sorted())

        let sharedVisitComponents = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/SharedVisits/SharedVisitComponents.swift")
        )
        XCTAssertTrue(sharedVisitComponents.contains("Text(\"friends\")"))
        XCTAssertTrue(sharedVisitComponents.contains("minHeight: WanderTheme.tapMinimum"))
        XCTAssertFalse(sharedVisitComponents.contains("They will get their own editable copy of this visit."))
    }

    func testEveryMoreOptionsQuestionUsesTheStructuredTagShelfTileLanguage() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let questionOptions = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private struct MapSaveQuestionOptions: View")
                .last?
                .components(separatedBy: "private struct MapSaveUnifiedTagsSection: View")
                .first
        )

        XCTAssertTrue(questionOptions.contains("LazyVGrid(columns: gridColumns"))
        XCTAssertTrue(questionOptions.contains("dynamicTypeSize.isAccessibilitySize ? 1 : standardCount"))
        XCTAssertTrue(questionOptions.contains("block.kind == .singleChoice && displayOptions.count == 3 ? 3 : 2"))
        XCTAssertTrue(questionOptions.contains("minHeight: 52"))
        XCTAssertTrue(questionOptions.contains("\"checkmark.circle.fill\""))
        XCTAssertTrue(questionOptions.contains("\"plus.circle\" : \"circle\""))
        XCTAssertTrue(questionOptions.contains("Text(\"add your own\")"))
        XCTAssertTrue(questionOptions.contains("style: StrokeStyle(lineWidth: 1, dash: [5, 4])"))
        XCTAssertFalse(questionOptions.contains("MapSaveWrappingChipLayout"))
        XCTAssertFalse(questionOptions.contains("WanderChip"))
        XCTAssertFalse(questionOptions.contains("Capsule()"))
    }

    func testWannaGoDatePickerStaysEmptyUntilTheUserChoosesADate() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let plannedDateSection = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private var plannedDateSection: some View")
                .last?
                .components(separatedBy: "private var questionAndLabelSections: some View")
                .first
        )

        XCTAssertTrue(plannedDateSection.contains("Text(\"add a date\")"))
        XCTAssertTrue(plannedDateSection.contains("MultiDatePicker("))
        XCTAssertTrue(
            plannedDateSection.contains(
                "If notifications are on, rec.me will remind you three days before."
            )
        )
        XCTAssertFalse(plannedDateSection.contains("Someday is okay"))
        XCTAssertFalse(plannedDateSection.contains("Text(\"OPTIONAL\")"))
        XCTAssertFalse(mapScreen.contains("@State private var datePickerSelection"))
        XCTAssertFalse(
            mapScreen.contains(
                "let suggestedDate = Calendar.autoupdatingCurrent.date(byAdding: .day"
            )
        )
    }

    func testRequestedMemberEntryPointsPresentTheFullProfileDetail() throws {
        let presentations = [
            ("Wander/App/WanderRootView.swift", ".fullScreenCover(item: $sharedProfile)"),
            ("Wander/Features/Feed/FeedScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Discover/DiscoverScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Lists/ListsScreen.swift", ".fullScreenCover(isPresented: profileDestinationBinding)"),
            ("Wander/Features/Map/MapScreen.swift", ".fullScreenCover(isPresented: profileDestinationBinding)"),
            ("Wander/Features/Profile/ProfileScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Profile/ProfileSocialGraphScreen.swift", ".fullScreenCover(item: $selectedProfileID)")
        ]

        for (file, presentation) in presentations {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(file))
            XCTAssertTrue(source.contains("ProfileDetailView("), "Missing full member profile destination in \(file)")
            XCTAssertTrue(source.contains(presentation), "Member profile must use a full-screen presentation in \(file)")
        }
    }

    func testCheckInPickerUsesDateOnlyWithoutInstructionalCopy() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let fixtureData = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "WanderTests/Fixtures/rec-168-check-in-date-reselection-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let checkInDateSection = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "private var checkInDateSection: some View")
                .last?
                .components(separatedBy: "private var canInviteFriends: Bool")
                .first
        )

        XCTAssertEqual(fixture["issue"] as? String, "REC-168")
        XCTAssertEqual(
            fixture["pre_fix_control"] as? String,
            "single-value graphical DatePicker"
        )
        XCTAssertTrue(checkInDateSection.contains("\"Check-in date\""))
        XCTAssertTrue(checkInDateSection.contains("MultiDatePicker("))
        XCTAssertTrue(
            checkInDateSection.contains(
                "CheckInDatePickerSelection.calendarSelection(for: visitedAt)"
            )
        )
        XCTAssertTrue(checkInDateSection.contains("CheckInDatePickerSelection.resolvedDate("))
        XCTAssertTrue(checkInDateSection.contains("isShowingCheckInDatePicker.toggle()"))
        XCTAssertTrue(checkInDateSection.contains("isShowingCheckInDatePicker = false"))
        XCTAssertTrue(mapScreen.contains("@State private var isShowingCheckInDatePicker = false"))
        XCTAssertFalse(checkInDateSection.contains(".datePickerStyle(.compact)"))
        XCTAssertFalse(checkInDateSection.contains(".hourAndMinute"))
        XCTAssertFalse(checkInDateSection.contains("Defaults to now."))
        XCTAssertFalse(checkInDateSection.contains("Pick an earlier date for a past check-in."))
    }

    func testCheckInDatePickerSelectionConfirmsTheCurrentDayWithoutChangingItsTimestamp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let currentDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: 17,
                    minute: 42,
                    second: 11
                )
            )
        )

        let confirmedDate = CheckInDatePickerSelection.resolvedDate(
            from: [],
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(confirmedDate, currentDate)
    }

    func testCheckInDatePickerSelectionReplacesTheDayAndPreservesTheCheckInTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let currentDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: 17,
                    minute: 42,
                    second: 11
                )
            )
        )
        let replacementDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))
        )
        let selection = CheckInDatePickerSelection.calendarSelection(
            for: currentDate,
            calendar: calendar
        ).union(
            CheckInDatePickerSelection.calendarSelection(
                for: replacementDate,
                calendar: calendar
            )
        )

        let resolvedDate = CheckInDatePickerSelection.resolvedDate(
            from: selection,
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: resolvedDate
            ),
            DateComponents(
                year: 2026,
                month: 7,
                day: 20,
                hour: 17,
                minute: 42,
                second: 11
            )
        )
    }

    func testMemberProfileBackAndActionPopoverStayAttachedToTheSharedHeader() throws {
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )

        XCTAssertTrue(home.contains("systemImage: \"chevron.left\""))
        XCTAssertTrue(home.contains(".popover("))
        XCTAssertTrue(home.contains("attachmentAnchor: .rect(.bounds)"))
        XCTAssertTrue(home.contains("arrowEdge: .top"))
        XCTAssertTrue(home.contains(".presentationCompactAdaptation(.popover)"))
        XCTAssertFalse(profileScreen.contains(".confirmationDialog(\"Profile actions\""))
        XCTAssertTrue(profileScreen.contains("if profile == nil"), "Full-screen loading and unavailable states need a dismiss control")
    }

    func testNativeSharingStaysBehindTheSharedShareComponent() throws {
        let appRoot = projectRoot.appendingPathComponent("Wander")
        let sharedComponent = appRoot.appendingPathComponent("DesignSystem/WanderShareButton.swift").standardizedFileURL
        let directShareLinkFiles = try swiftFiles(in: appRoot).filter { file in
            guard file.standardizedFileURL != sharedComponent else { return false }
            return try String(contentsOf: file).contains("ShareLink(")
        }

        XCTAssertEqual(
            directShareLinkFiles.map(\.lastPathComponent),
            [],
            "Use WanderShareButton so native sharing copy and behavior stay consistent."
        )
    }

    func testProfileCalendarDatesUseScrollCompatibleTapHandling() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )

        XCTAssertTrue(source.contains("ScrollView {"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: WanderTheme.spacing6)"))
        XCTAssertTrue(source.contains("Grid(horizontalSpacing: 6, verticalSpacing: WanderTheme.spacing2)"))
        XCTAssertFalse(source.contains("LazyVStack"))
        XCTAssertFalse(source.contains("LazyVGrid"))
        XCTAssertTrue(source.contains(".onTapGesture { dateAction(summary) }"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(source.contains(".accessibilityAction { dateAction(summary) }"))
        XCTAssertTrue(source.contains("ProfileCalendarActivityMarker("))
        XCTAssertTrue(source.contains("ProfileCalendarLegend()"))
        XCTAssertTrue(source.contains(".scrollTargetLayout()"))
        XCTAssertTrue(source.contains(".scrollPosition(id: $profileScrollPosition, anchor: .top)"))
        XCTAssertFalse(source.contains("style: StrokeStyle("))
        XCTAssertFalse(source.contains("dash: [0.1, max(3, size * 0.14)]"))
        XCTAssertTrue(source.contains("item(state: .visit, title: CheckInCopy.pluralNoun)"))
        XCTAssertFalse(source.contains("item(state: .wanna, title: \"wanna\")"))
        XCTAssertTrue(source.contains(".offset(y: -6)"))
        XCTAssertFalse(source.contains("visitCount > 1"), "Calendar cells should keep state visuals stable and move counts into day detail")
    }

    func testProfileCalendarDayDetailAvoidsRedundantActivityTags() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )

        XCTAssertFalse(source.contains("ProfileCalendarPlaceActivityLabel"))
        XCTAssertFalse(source.contains("visited this day"))
        XCTAssertFalse(source.contains("saved as wanna this day"))
        XCTAssertTrue(source.contains("metric(value: summary.visitCount, singular: CheckInCopy.noun, plural: CheckInCopy.pluralNoun"))
        XCTAssertFalse(source.contains("metric(value: summary.wannaCount, singular: \"wanna\", plural: \"wanna\""))
        XCTAssertTrue(source.contains("var includesAllStatuses: Bool {\n        false\n    }"))
    }

    func testProfileCalendarDayDetailUsesSideBySideDropdownsWithoutSearch() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let calendarControls = try XCTUnwrap(
            source
                .components(separatedBy: "private var calendarDayFilterControls: some View")
                .last?
                .components(separatedBy: "private var searchField: some View")
                .first
        )

        XCTAssertTrue(source.contains("if collection?.calendarDay != nil {\n                        calendarDayFilterControls"))
        XCTAssertTrue(calendarControls.contains("HStack(alignment: .top, spacing: WanderTheme.spacing3)"))
        XCTAssertTrue(calendarControls.contains("title: \"type\""))
        XCTAssertTrue(calendarControls.contains("title: \"tags\""))
        XCTAssertTrue(calendarControls.contains("allTitle: \"all types\""))
        XCTAssertTrue(calendarControls.contains("allTitle: \"all tags\""))
        XCTAssertTrue(calendarControls.contains("Menu {"))
        XCTAssertTrue(calendarControls.contains("minHeight: WanderTheme.tapMinimum"))
        XCTAssertFalse(calendarControls.contains("TextField("))
        XCTAssertFalse(calendarControls.contains("searchField"))
    }

    func testProfileScrollUsesAStaticMapSnapshotWithoutReintroducingLazyContainers() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let mapSection = try XCTUnwrap(
            source
                .components(separatedBy: "private struct ProfileMapSection: View")
                .last?
                .components(separatedBy: "private struct ProfileMapSummaryRow: View")
                .first
        )

        XCTAssertTrue(mapSection.contains("ProfileMapSnapshotView("))
        XCTAssertTrue(mapSection.contains("shareImageFileURL = nil"))
        XCTAssertTrue(mapSection.contains("renderedSnapshot = ProfileMapRenderedSnapshot(key: request.cacheKey, image: image)"))
        XCTAssertTrue(mapSection.contains("let pngData = image.pngData()"))
        XCTAssertTrue(mapSection.contains("shareImageFileURL = imageFileURL"))
        XCTAssertFalse(mapSection.contains("\n            Map("))
        XCTAssertFalse(source.contains("LazyVStack"))
        XCTAssertFalse(source.contains("LazyVGrid"))
    }

    func testProfileMapSummaryRowsExposeSeparateNavigationAndFilteredShareActions() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let mapSection = try XCTUnwrap(
            source
                .components(separatedBy: "private struct ProfileMapSection: View")
                .last?
                .components(separatedBy: "private struct ProfileMapSnapshotView: View")
                .first
        )
        let shareButton = try XCTUnwrap(
            source
                .components(separatedBy: "private struct ProfileMapSummaryShareButton: View")
                .last
        )

        XCTAssertTrue(mapSection.contains("\\(insights.mapPlaceCount) checked-in \\(placeLabel)"))
        XCTAssertTrue(mapSection.contains("ProfileMapSummaryShareButton("))
        XCTAssertTrue(mapSection.contains("points: insights.mapPoints(matching: item)"))
        XCTAssertTrue(shareButton.contains(".accessibilityLabel(\"Share \\(item.title)\")"))
        XCTAssertTrue(shareButton.contains("filterTitle: item.title"))
        XCTAssertTrue(shareButton.contains("WanderShareSheet(content: shareContent)"))
        XCTAssertTrue(shareButton.contains(".alert(\"Couldn't prepare this map\""))
        XCTAssertTrue(shareButton.contains(".onDisappear(perform: cancelSharePreparation)"))
    }

    @MainActor
    func testNotificationDestinationsSelectTheirOwningTabs() {
        XCTAssertEqual(WanderRootView.notificationTab(for: .people(.friends)), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .drafts(extractionJobID: "job-1")), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .list(id: "list-1")), .lists)
        XCTAssertEqual(WanderRootView.notificationTab(for: .listInvite(token: "invite-1")), .lists)
        XCTAssertEqual(WanderRootView.notificationTab(for: .place(id: "place-1")), .map)
        XCTAssertEqual(
            WanderRootView.notificationTab(for: .sharedVisit(participantID: "participant-1", generation: 2)),
            .map
        )
        XCTAssertEqual(WanderRootView.notificationTab(for: .discover), .discover)
    }

    @MainActor
    func testRootViewCanResolveInitialTabForVisualQA() {
        XCTAssertEqual(
            WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "discover"]),
            .discover
        )
        XCTAssertEqual(
            WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "lists"]),
            .lists
        )
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "add"]), .map)
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "nope"]), .map)
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab"]), .map)
    }

    @MainActor
    func testRootViewCanResolveSettingsPresentationForVisualQA() {
        XCTAssertEqual(
            WanderRootView.resolvedInitialPresentation(from: ["Wander", "-WanderOpenSettings"]),
            .settings
        )
        XCTAssertNil(WanderRootView.resolvedInitialPresentation(from: ["Wander"]))
    }

    @MainActor
    func testRootViewCanResolveAddPresentationForVisualQA() {
        XCTAssertTrue(
            WanderRootView.resolvedInitialAddPresentation(from: ["Wander", "-WanderOpenAdd"])
        )
        XCTAssertFalse(WanderRootView.resolvedInitialAddPresentation(from: ["Wander"]))
    }

    func testListsScreenCanResolveInteractiveVisualQAScenarios() {
        XCTAssertEqual(ListsScreenScenario.resolved(from: ["Wander"]), .live)
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collaboratorsSheet"]),
            .collaboratorsSheet
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "mapPreview"]),
            .mapPreview
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "mapSelectedPlace"]),
            .mapSelectedPlace
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "createCollaboratorsSearch"]),
            .createCollaboratorsSearch
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "editDeleteConfirm"]),
            .editDeleteConfirm
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collabEdit"]),
            .collabEdit
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collabEditDeleteConfirm"]),
            .collabEditDeleteConfirm
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "placeDetail"]),
            .placeDetail
        )
        XCTAssertEqual(ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "unknown"]), .populated)
    }

    func testNewListEditorHasTheRequestedDismissAffordance() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let editor = try sourceSection(
            source,
            after: "private struct ListEditorSheet: View",
            before: "private struct ListDestructiveButton: View"
        )

        XCTAssertTrue(editor.contains("ToolbarItem(placement: .cancellationAction)"))
        XCTAssertTrue(editor.contains("ToolbarItem(placement: .topBarLeading)"), "Older iOS versions should keep the leading placement")
        XCTAssertTrue(editor.contains("if !isEditing"), "Edit-list navigation should remain unchanged")
        XCTAssertTrue(editor.contains("Image(systemName: \"chevron.left\")"))
        XCTAssertTrue(editor.contains(".font(.system(size: 17, weight: .regular))"))
        XCTAssertTrue(editor.contains(".sharedBackgroundVisibility(.hidden)"))

        let backButton = try sourceSection(
            editor,
            after: "private var newListBackButton: some View",
            before: "private var isEditing: Bool"
        )
        XCTAssertTrue(backButton.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(backButton.contains(".accessibilityLabel(\"Back to lists\")"))
        XCTAssertTrue(backButton.contains("Button {\n            dismiss()"))
        XCTAssertFalse(backButton.contains(".background("), "The native back chevron should not draw a custom background")
    }

    func testListMapVisualQAScenariosResolveDeterministically() {
        let scenarios: [(argument: String, expected: ListsScreenScenario)] = [
            ("mapEmpty", .mapEmpty),
            ("mapSingle", .mapSingle),
            ("mapClustered", .mapClustered),
            ("mapDispersed", .mapDispersed),
            ("mapPartial", .mapPartial),
            ("mapUnresolved", .mapUnresolved),
            ("mapUnmapped", .mapUnmapped),
            ("mapError", .mapError),
            ("mapOffline", .mapOffline),
            ("mapLongNames", .mapLongNames)
        ]

        for scenario in scenarios {
            let resolved = ListsScreenScenario.resolved(
                from: ["Wander", "-WanderListsScenario", scenario.argument]
            )

            XCTAssertEqual(resolved, scenario.expected, scenario.argument)
            XCTAssertTrue(resolved.showsDetailRoot, scenario.argument)
            XCTAssertTrue(resolved.opensMapOnLaunch, scenario.argument)
            XCTAssertTrue(resolved.usesMockData, scenario.argument)
        }
    }

    func testListMapUsesFocusThenDirectOpenWithoutIntermediatePlaceSurface() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let fullScreen = try XCTUnwrap(
            source
                .components(separatedBy: "private struct ListMapFullScreen: View")
                .last?
                .components(separatedBy: "private struct ListMapMarker: View")
                .first
        )
        let rail = try XCTUnwrap(
            source
                .components(separatedBy: "private struct ListMapPlaceRail: View")
                .last?
                .components(separatedBy: "private struct ListMapCompactMedia: View")
                .first
        )

        XCTAssertFalse(source.contains("PlaceProfileMapSurface("))
        XCTAssertFalse(fullScreen.contains("saves: []"))
        XCTAssertFalse(fullScreen.contains("currentUserID: \"you\""))
        XCTAssertTrue(fullScreen.contains("focus(place)"), "A pin should focus its rail tile")
        XCTAssertTrue(rail.contains("let onSelect: (ListPlaceMock) -> Void"))
        XCTAssertTrue(rail.contains("onSelect(place)"), "Rail selection should open the place directly")
        XCTAssertTrue(rail.contains("let onOpen: () -> Void"))
        XCTAssertTrue(rail.contains("Button(action: onOpen)"), "The whole tile should open on its first tap")
        XCTAssertTrue(rail.contains(".accessibilityHint(\"Opens place\")"))
    }

    func testListHomeKeepsRichMapProjectionOutOfTheGridHotPath() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let activeLists = try sourceSection(
            source,
            after: "private var activeLists: [PlaceListMock]",
            before: "private var selectedScope: ListsScope"
        )
        let detailScreen = try sourceSection(
            source,
            after: "private struct ListDetailScreen: View",
            before: "private struct ListSuggestionsSection: View"
        )
        let richProjection = try sourceSection(
            source,
            after: "private struct ListPlaceProjectionContext",
            before: "private struct ListPlaceMock: Identifiable"
        )

        XCTAssertTrue(activeLists.contains("summary: list"))
        XCTAssertTrue(activeLists.contains("ListPreviewPlaceSelector.distinctPrefix("))
        XCTAssertTrue(activeLists.contains("limit: 4"))
        XCTAssertTrue(activeLists.contains("store.firstVisitPhotosByPlaceID()"))
        XCTAssertTrue(source.contains("let renderedLists = activeLists"))
        XCTAssertTrue(source.contains("listGrid(lists: renderedLists)"))
        XCTAssertTrue(detailScreen.contains("let renderedList = displayList"))
        XCTAssertEqual(detailScreen.components(separatedBy: "let renderedList = displayList").count - 1, 1)
        XCTAssertTrue(richProjection.contains("VisiblePlaceGrouping.groups("))
        XCTAssertTrue(richProjection.contains("store.firstVisitPhotosByPlaceID()"))
        XCTAssertFalse(richProjection.contains("store.attributes(for:"))
    }

    func testListGridTopAlignsTilesWhileNamesGrowDownward() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let listGrid = try sourceSection(
            source,
            after: "private func listGrid(lists: [PlaceListMock]) -> some View",
            before: "private var activeLists: [PlaceListMock]"
        )
        let listTile = try sourceSection(
            source,
            after: "private struct ListTile: View",
            before: "private struct ListPreviewMosaic: View"
        )
        let previewMosaic = try sourceSection(
            source,
            after: "private struct ListPreviewMosaic: View",
            before: "private struct ListSuggestionsSection: View"
        )
        let photoMedia = try sourceSection(
            source,
            after: "private struct ListPlacePhotoMedia: View",
            before: "private struct ListMapAvailabilityNotice: View"
        )

        XCTAssertEqual(
            listGrid.components(separatedBy: "alignment: .top").count - 1,
            2,
            "Both list-grid columns should pin each row's tiles to the same top edge"
        )
        XCTAssertTrue(
            listTile.contains(".lineLimit(2)"),
            "Long list names should keep wrapping below the aligned preview mosaic"
        )
        XCTAssertTrue(photoMedia.contains("targetPixelSize"))
        XCTAssertTrue(photoMedia.contains("store.currentUser.id"))
        XCTAssertTrue(photoMedia.contains("store.follows"))
        XCTAssertTrue(photoMedia.contains("store.blocks"))
        XCTAssertTrue(photoMedia.contains("WanderCategoryEmoji(emoji: place.emoji"))
        XCTAssertTrue(photoMedia.contains("eligibleUserIDs: eligibleUserIDs"))
        XCTAssertTrue(previewMosaic.contains("Image(systemName: \"bookmark.fill\")"))
        XCTAssertFalse(previewMosaic.contains("String(list.name.prefix(1))"))
        XCTAssertTrue(previewMosaic.contains("eligibleUserIDs: list.photoContributorUserIDs"))
        XCTAssertTrue(source.contains("photoContributorUserIDs.contains(store.currentUser.id)"))
        XCTAssertTrue(
            photoMedia.contains("resolvedPhotoKey == resolutionKey"),
            "A relationship or account change should synchronously hide stale user photos"
        )
    }

    func testListsScreenOnlyUsesMockDataForExplicitVisualQAScenarios() {
        XCTAssertFalse(ListsScreenScenario.live.usesMockData)
        XCTAssertFalse(ListsScreenScenario.empty.usesMockData)
        XCTAssertTrue(ListsScreenScenario.populated.usesMockData)
        XCTAssertTrue(ListsScreenScenario.collaboratorsSheet.usesMockData)
    }

    func testVisitFriendMockupsHaveDeterministicLaunchPages() {
        XCTAssertEqual(
            PlaceActivityMockupPage.resolved(from: ["Wander", "-WanderPlaceActivityMockup", "visitFriendsEditor"]),
            .visitFriendsEditor
        )
        XCTAssertEqual(
            PlaceActivityMockupPage.resolved(from: ["Wander", "-WanderPlaceActivityMockup", "visitWithFriend"]),
            .visitWithFriend
        )
    }

    func testRetiredSharedVisitInvitationMockCannotReplaceTheProductionApp() throws {
        let retiredIdentifiers = [
            "WanderSharedVisitInvitationMockup",
            "SharedVisitInvitationMockData",
            "SharedVisitInvitationMockupRoot"
        ]
        let matches = try swiftFiles(in: projectRoot.appendingPathComponent("Wander")).filter { file in
            let source = try String(contentsOf: file)
            return retiredIdentifiers.contains { source.contains($0) }
        }

        XCTAssertEqual(matches.map(\.lastPathComponent), [])
    }

    @MainActor
    func testSharedVisitBannerUsesTaggedCopyAndOpensTheProfileInbox() {
        XCTAssertEqual(
            SharedVisitBannerCopy.title(inviterName: "Joe Lipshutz", placeName: "RVR"),
            "Joe Lipshutz tagged you at RVR"
        )
        XCTAssertEqual(WanderRootView.sharedVisitBannerDestinationTab, .profile)
    }

    func testSharedVisitCompanionPresentationUsesViewerAvatarOrderAndYouCopy() {
        let joe = SharedVisitCompanion(
            visitID: "visit-joe",
            userID: "user-joe",
            handle: "joe",
            displayName: "Joe Lipshutz",
            avatarURL: "https://example.com/joe.jpg"
        )
        let ryan = SharedVisitCompanion(
            visitID: "visit-joe",
            userID: "user-ryan",
            handle: "ryan",
            displayName: "Ryan L",
            avatarURL: "https://example.com/ryan.jpg"
        )

        XCTAssertEqual(
            SharedVisitCompanionPresentation.ordered([joe, ryan], currentUserID: ryan.userID),
            [ryan, joe]
        )
        XCTAssertEqual(
            SharedVisitCompanionPresentation.text(companions: [ryan], currentUserID: ryan.userID),
            "with You"
        )
        XCTAssertEqual(
            SharedVisitCompanionPresentation.text(companions: [], currentUserID: ryan.userID),
            ""
        )
        XCTAssertEqual(
            SharedVisitCompanionPresentation.text(companions: [joe, ryan], currentUserID: ryan.userID),
            "with You and Joe Lipshutz"
        )
        XCTAssertEqual(
            SharedVisitCompanionPresentation.ordered([joe, ryan], currentUserID: ryan.userID).first?.avatarURL,
            "https://example.com/ryan.jpg"
        )
    }

    func testSharedVisitBannerOnlySurfacesNewInvitationGenerations() {
        let generationOne = SharedVisitBannerTracker.key(participantID: "participant-1", generation: 1)
        let generationTwo = SharedVisitBannerTracker.key(participantID: "participant-1", generation: 2)
        var tracker = SharedVisitBannerTracker()

        tracker.seed(invitationKeys: [generationOne])

        XCTAssertNil(tracker.nextUnseenKey(in: [generationOne]))
        XCTAssertEqual(tracker.nextUnseenKey(in: [generationTwo, generationOne]), generationTwo)
        XCTAssertNil(tracker.nextUnseenKey(in: [generationTwo, generationOne]))
    }

    func testSharedVisitBannerPresentsOnlyNewestInviteWhenRefreshAddsSeveral() {
        let newest = SharedVisitBannerTracker.key(participantID: "participant-newest", generation: 1)
        let older = SharedVisitBannerTracker.key(participantID: "participant-older", generation: 1)
        var tracker = SharedVisitBannerTracker()

        XCTAssertEqual(tracker.nextUnseenKey(in: [newest, older]), newest)
        XCTAssertNil(tracker.nextUnseenKey(in: [newest, older]))
    }

    @MainActor
    func testRootViewUsesEmptyFixturesByDefaultAndExplicitProfilingFixturesWhenRequested() {
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander"]), .empty)
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander", "-WanderUseDemoFixtures"]), .demo)
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(from: ["Wander", "-WanderUsePerformanceFixtures"]),
            .performance
        )
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander", "-WanderUseDemoFixtures", "-WanderUsePerformanceFixtures"]
            ),
            .performance
        )
    }

    @MainActor
    func testRootViewCanOpenMemberProfileForVisualQA() {
        XCTAssertEqual(
            WanderRootView.resolvedInitialSharedProfile(
                from: ["Wander", "-WanderOpenProfile", "user_maya"]
            ),
            SharedProfileRoute(profileID: "user_maya")
        )
        XCTAssertNil(WanderRootView.resolvedInitialSharedProfile(from: ["Wander"]))
        XCTAssertNil(
            WanderRootView.resolvedInitialSharedProfile(
                from: ["Wander", "-WanderOpenProfile", "   "]
            )
        )
    }

    func testProfileRedesignMockupLaunchArgumentResolvesEveryApprovalState() {
        for page in ProfileRedesignMockupPage.allCases {
            XCTAssertEqual(
                ProfileRedesignMockupPage.resolved(
                    from: ["Wander", "-WanderProfileRedesignMockup", page.rawValue]
                ),
                page
            )
        }
    }

    func testProfileRedesignMockupLaunchArgumentFallsBackWithoutAValidPage() {
        XCTAssertNil(ProfileRedesignMockupPage.resolved(from: ["Wander"]))
        XCTAssertEqual(
            ProfileRedesignMockupPage.resolved(from: ["Wander", "-WanderProfileRedesignMockup"]),
            .ownerProfile
        )
        XCTAssertEqual(
            ProfileRedesignMockupPage.resolved(
                from: ["Wander", "-WanderProfileRedesignMockup", "not-a-page"]
            ),
            .ownerProfile
        )
    }

    @MainActor
    func testMapScreenCanResolvePlaceProfileLaunchArgumentsForVisualQA() {
        XCTAssertEqual(
            MapScreen.resolvedInitialMapPlaceQuery(from: ["Wander", "-WanderMapPlace", "Woodcat Coffee"]),
            "Woodcat Coffee"
        )
        XCTAssertNil(MapScreen.resolvedInitialMapPlaceQuery(from: ["Wander", "-WanderMapPlace"]))
        XCTAssertTrue(MapScreen.resolvedInitialPlaceProfilePresentation(from: ["Wander", "-WanderMapSheetExpanded"]))
        XCTAssertFalse(MapScreen.resolvedInitialPlaceProfilePresentation(from: ["Wander"]))
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilters(from: ["Wander", "-WanderMapCaptureMode", "diary"]),
            [.you, .been]
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilters(from: ["Wander", "-WanderMapCaptureMode", "friends"]),
            [.social, .been, .wanna]
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilters(from: ["Wander", "-WanderMapCaptureMode", "trusted"]),
            [.social, .been]
        )
    }

    @MainActor
    func testMapScreenDefaultsToAnUnselectedCurrentCityCamera() throws {
        let center = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let region = MapScreen.initialCityRegion(center: center)

        XCTAssertEqual(region.center.latitude, center.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, center.longitude, accuracy: 0.000_001)
        XCTAssertEqual(region.span.latitudeDelta, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(region.span.longitudeDelta, 0.14, accuracy: 0.000_001)

        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let initialSelection = try XCTUnwrap(
            source
                .components(separatedBy: "private func resolveInitialSelection()")
                .last?
                .components(separatedBy: "private func centerMapOnCurrentCityIfNeeded()")
                .first
        )

        XCTAssertTrue(initialSelection.contains("let initialPlaceQuery"))
        XCTAssertFalse(initialSelection.contains("firstVisiblePlace"))
        XCTAssertFalse(source.contains("centerMapOnInitialPlacesIfNeeded"))
        XCTAssertTrue(source.contains(".userLocation(followsHeading: false, fallback: .automatic)"))
        XCTAssertFalse(source.contains("MapCameraPosition = .region(Self.defaultSearchRegion)"))

        let viewport = MapScreen.viewport(for: region)
        XCTAssertEqual(viewport.minLatitude, 37.7149, accuracy: 0.000_001)
        XCTAssertEqual(viewport.maxLatitude, 37.8349, accuracy: 0.000_001)
        XCTAssertEqual(viewport.minLongitude, -122.4894, accuracy: 0.000_001)
        XCTAssertEqual(viewport.maxLongitude, -122.3494, accuracy: 0.000_001)
    }

    func testMapPlaceProfileUsesFullScreenCoverInsteadOfNavigationPush() throws {
        let mapScreen = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift"))

        XCTAssertTrue(mapScreen.contains(".fullScreenCover(isPresented: placeProfileDestinationBinding)"))
        XCTAssertFalse(mapScreen.contains(".navigationDestination(isPresented: placeProfileDestinationBinding)"))
    }

    func testDiscoverTickerStateIsOwnedBySearchField() throws {
        let discoverScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let sections = discoverScreen.components(separatedBy: "private struct DiscoverSearchField: View")

        XCTAssertEqual(sections.count, 2)
        XCTAssertFalse(sections[0].contains("@State private var tickerIndex"))
        XCTAssertFalse(sections[0].contains("runTicker()"))
        XCTAssertTrue(sections[1].contains("@State private var placeholderIndex"))
        XCTAssertTrue(sections[1].contains("await runPlaceholderTicker()"))
    }

    func testDiscoverFromFeedIsPlaceOnlyFocusedAndUsesSuggestedSearches() throws {
        let discoverScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let body = try sourceSection(
            discoverScreen,
            after: "struct DiscoverScreen: View {",
            before: "private func applyRequestedSection"
        )
        let placesContent = try sourceSection(
            discoverScreen,
            after: "private var placesContent: some View",
            before: "private var suggestedSearchesSection: some View"
        )

        XCTAssertFalse(discoverScreen.contains("Text(\"Discover\")"))
        XCTAssertTrue(discoverScreen.contains("\"Back to Discover\" : \"Back to Feed\""))
        XCTAssertTrue(discoverScreen.contains("startsInPlaceSearch: Bool = false"))
        XCTAssertTrue(discoverScreen.contains("searchFieldFocused = true"))
        XCTAssertTrue(discoverScreen.contains("private let suggestedSearches"))
        XCTAssertTrue(discoverScreen.contains("LazyHGrid("))
        XCTAssertTrue(discoverScreen.contains("placesQuery = suggestion.query"))
        XCTAssertFalse(discoverScreen.contains("private let startsFocused: Bool"))
        XCTAssertTrue(body.contains("if selectedMode == .places, isPlaceSearchPresented"))
        XCTAssertTrue(body.contains("activePlaceSearchHeader"))
        XCTAssertTrue(body.contains("activePlaceSearchContent"))
        XCTAssertTrue(body.contains("ScrollView"))
        XCTAssertTrue(placesContent.contains("suggestedSearchesSection"))
        XCTAssertFalse(placesContent.contains("latestActivitySection"))

        let resultCard = try sourceSection(
            discoverScreen,
            after: "private struct DiscoverPlaceResultCard: View",
            before: "private struct DiscoverResultActionButton: View"
        )
        XCTAssertTrue(resultCard.contains("rec.me rating"))
        XCTAssertTrue(resultCard.contains("case nil:\n            \"Wanna go\""))
        XCTAssertTrue(resultCard.contains("case .wannaGo:\n            \"In Wanna\""))
        XCTAssertTrue(resultCard.contains("case .been:\n            \"Visited\""))
        XCTAssertTrue(resultCard.contains("action: addToWanna"))
        XCTAssertTrue(resultCard.contains("isDisabled: currentUserStatus != nil"))
        XCTAssertFalse(resultCard.contains("\"Add visit\""))
        XCTAssertTrue(resultCard.contains("title: \"Add to list\""))
        XCTAssertTrue(resultCard.contains("WanderShareButton(content: shareContent)"))
        XCTAssertTrue(resultCard.contains("serverID: place.id"))
        XCTAssertFalse(resultCard.contains("googleMapsSearchURL"))
        XCTAssertTrue(discoverScreen.contains("guard currentUserSave(matching: visiblePlace) == nil"))
        XCTAssertTrue(discoverScreen.contains("store.saveVisiblePlace("))
        XCTAssertTrue(discoverScreen.contains("status: .wannaGo"))
        XCTAssertTrue(discoverScreen.contains("store.addVisiblePlace("))
    }

    func testDiscoverUnboundedRowsAreLazyAndPlaceSearchIsSubmitDriven() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let placeResults = try sourceSection(
            source,
            after: "private var placeResultsSection: some View",
            before: "private var latestActivitySection: some View"
        )
        let friends = try sourceSection(
            source,
            after: "private var peopleSection: some View",
            before: "private func beginSaveDiscoverPlace"
        )
        let memberResults = try sourceSection(
            source,
            after: "private var memberSearchResultsSection: some View",
            before: "private var peopleSection: some View"
        )

        XCTAssertTrue(placeResults.contains("LazyVStack"))
        XCTAssertTrue(friends.contains("LazyVStack"))
        XCTAssertTrue(memberResults.contains("LazyHStack"))
        XCTAssertFalse(source.contains("store.visiblePlaces(for: profile.id).count"))
        XCTAssertFalse(source.contains(".task(id: placesQuery)"))
        XCTAssertTrue(source.contains(".task(id: memberQuery)"))
        XCTAssertTrue(source.contains(".onChange(of: placesQuery)"))
        XCTAssertTrue(source.contains(".onSubmit(onSubmit)"))
        XCTAssertTrue(source.contains("private func submitPlaceSearch()"))
        XCTAssertFalse(source.contains(".onChange(of: memberQuery)"))
    }

    func testDiscoverPlaceSearchIsReversibleAndTeachesNaturalLanguageQueries() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let feedSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )

        XCTAssertTrue(source.contains("activePlaceSearchHeader"))
        XCTAssertTrue(source.contains("Back to Discover"))
        XCTAssertTrue(source.contains("private func exitPlaceSearch()"))
        XCTAssertTrue(source.contains("private func clearPlaceSearch()"))
        XCTAssertTrue(source.contains("placeSearchTask?.cancel()"))
        XCTAssertTrue(source.contains("activePlaceSearchSubmissionID == submissionID"))
        XCTAssertTrue(source.contains("Try a search"))
        XCTAssertTrue(source.contains("coffee worth crossing town for"))
        XCTAssertTrue(source.contains("quiet cafes with wifi"))
        XCTAssertTrue(source.contains("Understood as"))
        XCTAssertTrue(source.contains("evidence.summary"))
        XCTAssertTrue(source.contains("Search visited instead"))
        XCTAssertTrue(source.contains("Nothing was broadened automatically"))
        XCTAssertTrue(feedSource.contains("startsInPlaceSearch: true"))
        XCTAssertTrue(feedSource.contains("onClose: { isShowingSearch = false }"))
    }

    func testDiscoverAuthAndVisibleDataRefreshesRerunActiveSearchesCancellably() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let authRefresh = try sourceSection(
            source,
            after: ".task(id: auth.isSignedIn)",
            before: ".task(id: memberQuery)"
        )
        let visibleDataRefresh = try sourceSection(
            source,
            after: ".task(id: visiblePlaceSignature)",
            before: ".navigationDestination"
        )

        XCTAssertTrue(authRefresh.contains("previousAuthState != requestedAuthState"))
        XCTAssertTrue(authRefresh.contains("await refreshPlaces(query: placesQuery)"))
        XCTAssertTrue(authRefresh.contains("await refreshMembers(query: memberQuery)"))
        XCTAssertTrue(authRefresh.contains("guard !Task.isCancelled"))
        XCTAssertTrue(visibleDataRefresh.contains("await refreshPlaces(query: placesQuery)"))
        XCTAssertTrue(visibleDataRefresh.contains("await refreshMembers(query: memberQuery)"))
        XCTAssertTrue(visibleDataRefresh.contains("guard !Task.isCancelled"))
        XCTAssertFalse(source.contains(".onChange(of: visiblePlaceSignature)"))
    }

    @MainActor
    func testPlaceProfileEdgeSwipeBackGestureOnlyTriggersFromLeftEdge() {
        XCTAssertTrue(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 52,
                translation: CGSize(width: 120, height: 4)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 40, height: 2)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 110, height: 110)
            )
        )
    }

    @MainActor
    func testPlaceProfileFullBleedHeaderKeepsMinimumTopInset() {
        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: 0),
            54
        )

        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: 62),
            62
        )
    }

    @MainActor
    func testPlaceProfileFullViewKeepsScrollableBottomInset() {
        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullViewBottomContentInset(from: 0),
            64
        )

        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullViewBottomContentInset(from: 34),
            66
        )
    }

    func testRestaurantPlaceTypeUsesCuisineInsteadOfSubcategory() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let placeTypeSection = try sourceSection(
            mapScreen,
            after: "private var placeTypeSection: some View {",
            before: "private var candidateCard: some View {"
        )

        XCTAssertTrue(placeTypeSection.contains("if isRestaurantsFoodSelected"))
        XCTAssertTrue(placeTypeSection.contains("placeTypePickerMode = .cuisine"))
        XCTAssertTrue(placeTypeSection.contains("title: \"cuisine\""))
        XCTAssertTrue(placeTypeSection.contains("} else {"))
        XCTAssertTrue(placeTypeSection.contains("placeTypePickerMode = .subcategory"))
        XCTAssertTrue(placeTypeSection.contains("PlaceTypeRow(title: \"subcategory\""))
        XCTAssertTrue(
            mapScreen.contains(
                "mode = category == WanderPlaceCategory.restaurantsFood ? .cuisine : .subcategory"
            )
        )
        XCTAssertTrue(
            mapScreen.contains(
                "let noun = category == WanderPlaceCategory.restaurantsFood ? \"cuisines\" : \"types\""
            )
        )

        let mockups = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/CategoryTaxonomyMockups.swift")
        )
        XCTAssertFalse(
            mockups.contains("MockupDetailRow(title: \"subcategory\", value: \"Restaurant\"")
        )
    }

    func testSubcategoryPickerUsesAtlasLayoutAcrossNonRestaurantCategories() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let picker = try sourceSection(
            mapScreen,
            after: "private var subcategoryPickerContent: some View {",
            before: "private var cuisinePickerContent: some View {"
        )

        XCTAssertTrue(picker.contains("title: \"explore types\""))
        XCTAssertTrue(picker.contains("selectedCategoryPills"))
        XCTAssertTrue(picker.contains("CategoryPickerSearchField"))
        XCTAssertTrue(picker.contains("SubcategoryAtlasFilters"))
        XCTAssertTrue(picker.contains("LazyVGrid"))
        XCTAssertTrue(picker.contains("PlaceTypeAtlasTile"))
        XCTAssertFalse(picker.contains("SubcategoryGroupSection"))

        XCTAssertTrue(mapScreen.contains("PlaceTypeSelectionFooter"))
        XCTAssertTrue(mapScreen.contains("selectedSubcategoryGroup = \"All\""))
        XCTAssertTrue(
            mapScreen.contains(
                "WanderCategoryEmoji(\n                            category: category,\n                            subcategory: subcategory"
            )
        )
    }

    func testOwnerProfileKeepsMobileLayoutWhileReorderingOnlyRequestedModules() throws {
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let screen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let body = try sourceSection(
            home,
            after: "struct ProfileOwnerHome: View {",
            before: "private var identitySection: some View"
        )
        let identity = try sourceSection(
            home,
            after: "private var identitySection: some View {",
            before: "private var profileAvatar: some View"
        )
        let recentActivity = try sourceSection(
            home,
            after: "private struct ProfileRecentActivitySection: View",
            before: "struct ProfileActivityRow: View"
        )

        let identityIndex = try XCTUnwrap(body.range(of: "identitySection")?.lowerBound)
        let streakIndex = try XCTUnwrap(body.range(of: "ProfileSaveStreakRow")?.lowerBound)
        let invitationsIndex = try XCTUnwrap(body.range(of: "ProfileSharedVisitInboxRow")?.lowerBound)
        let activityIndex = try XCTUnwrap(body.range(of: "ProfileRecentActivitySection")?.lowerBound)
        let calendarIndex = try XCTUnwrap(body.range(of: "ProfileCalendarSection")?.lowerBound)

        XCTAssertLessThan(identityIndex, streakIndex)
        XCTAssertLessThan(streakIndex, invitationsIndex)
        XCTAssertLessThan(invitationsIndex, activityIndex)
        XCTAssertLessThan(activityIndex, calendarIndex)
        XCTAssertFalse(identity.contains("Text(\"profile\")"))
        XCTAssertTrue(recentActivity.contains("ProfileActivityFilterControl("))
        XCTAssertTrue(home.contains("case checkIns = \"check_ins\""))
        XCTAssertTrue(home.contains("case .checkIns: CheckInCopy.pluralTitle"))
        XCTAssertFalse(home.contains("case .been: \"Been\""))
        XCTAssertFalse(screen.contains("No Been activity"))
        XCTAssertTrue(recentActivity.contains("filteredItems.prefix(6)"))
        XCTAssertTrue(recentActivity.contains("Text(\"See more\")"))
        XCTAssertTrue(screen.contains("ProfileActivityHistoryScreen("))
        XCTAssertTrue(screen.contains("initialSection: .activity"))
        XCTAssertTrue(
            placeProfile.contains(
                "scrollProxy.scrollTo(PlaceProfileScrollAnchor.activity, anchor: .top)"
            )
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceSection(_ source: String, after start: String, before end: String) throws -> String {
        let suffix = try XCTUnwrap(source.components(separatedBy: start).last)
        return try XCTUnwrap(suffix.components(separatedBy: end).first)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let file = item as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { return nil }
            return file
        }
    }
}
