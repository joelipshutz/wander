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
        let walkthrough = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Onboarding/FirstVisitWalkthrough.swift"
            )
        )
        let authStore = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Services/Auth/AuthSessionProviding.swift"
            )
        )

        XCTAssertTrue(app.contains("AppEntryView("))
        XCTAssertTrue(app.contains("analyticsLifecycle: analyticsLifecycle"))
        XCTAssertTrue(entry.contains("case .signedOut:"))
        XCTAssertTrue(entry.contains("LoggedOutCarouselView(analytics: analytics)"))
        XCTAssertTrue(entry.contains("auth.beginSignIn(mode: .signUp)"))
        XCTAssertTrue(entry.contains("auth.beginSignIn(mode: .signIn)"))
        XCTAssertTrue(entry.contains("case .ready(let session, let firstVisitWalkthroughEligible):"))
        XCTAssertTrue(entry.contains("initialSession: session"))
        XCTAssertTrue(entry.contains("isSessionValidated: auth.isSessionValidated"))
        XCTAssertTrue(entry.contains("isFirstVisitWalkthroughEligible: firstVisitWalkthroughEligible"))
        XCTAssertTrue(entry.contains("coordinator.completeFirstVisitWalkthrough(forUserID: completedUserID)"))
        XCTAssertTrue(entry.contains(".sheet(isPresented: $auth.isPresentingNativeAuth"))
        XCTAssertTrue(entry.contains("ClerkNativeAuthView(mode: auth.activeNativeAuthMode)"))
        XCTAssertTrue(entry.contains("case .background:"))
        XCTAssertTrue(entry.contains("foregroundRefreshPolicy.didEnterBackground("))
        XCTAssertTrue(entry.contains("case .active:"))
        XCTAssertTrue(entry.contains("foregroundRefreshPolicy.shouldRefreshSession("))
        XCTAssertTrue(entry.contains("let notificationGateState = AppEntryNotificationGateState("))
        XCTAssertTrue(entry.contains(".onChange(of: notificationGateState, initial: true)"))
        XCTAssertTrue(entry.contains("state.synchronize()"))
        XCTAssertFalse(authStore.contains("willEnterForegroundNotification"))
        XCTAssertTrue(root.contains("store.apply(authState: .signedIn(initialSession))"))
        XCTAssertTrue(root.contains("FirstVisitWalkthroughFeatureFlag.isEnabled("))
        XCTAssertTrue(root.contains("FirstVisitWalkthroughEligibilityContext("))
        XCTAssertTrue(
            root.contains("firstVisitWalkthroughEligibilityContext.applies(to: userID)")
        )
        XCTAssertTrue(
            root.contains("firstVisitWalkthroughEligibilityContext.shouldRetire(")
        )
        XCTAssertTrue(root.contains(".onChange(of: firstVisitWalkthroughEligibilityContext)"))
        XCTAssertTrue(
            root.contains(
                "FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement("
            )
        )
        XCTAssertTrue(root.contains("retiredWalkthroughUserIDs.insert(userID).inserted"))
        XCTAssertFalse(walkthrough.contains("isRolloutEnabledByDefault"))
        XCTAssertTrue(root.contains(".task(id: featureFlagLoadUserID)"))
        XCTAssertTrue(root.contains("backend.resolvedFeatureFlag(.firstVisitNUX, for: userID)"))
        XCTAssertTrue(root.contains("resolvedFlag?.explicitAccountOverride"))
        XCTAssertTrue(root.contains("refreshWalkthroughFeatureFlagsAfterForeground()"))
        XCTAssertTrue(root.contains("if auth.state.session == nil {"))
        XCTAssertTrue(root.contains("backend.clearFeatureFlags()"))
        XCTAssertTrue(walkthrough.contains("launchArguments.contains(\"-WanderEnableWalkthroughs\")"))
        XCTAssertTrue(root.contains(".task(id: isSessionValidated)"))
        XCTAssertTrue(root.contains("guard phase == .active, isSessionValidated else { return }"))
        XCTAssertTrue(root.contains("guard isSessionValidated,"))
    }

    func testNativeAuthPresentsAppleGoogleEmailAndPasswordWithoutGenericClerkSheet() throws {
        let authView = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Auth/NativeAuthFlowView.swift"
            )
        )
        let authGate = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Auth/AuthGateSheet.swift"
            )
        )
        let clerkService = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Services/Auth/ClerkAuthService.swift"
            )
        )

        let methodPickerStart = try XCTUnwrap(authView.range(of: "private var methodPicker"))
        let methodPickerEnd = try XCTUnwrap(authView.range(of: "private var authHeader"))
        let methodPicker = String(authView[methodPickerStart.lowerBound..<methodPickerEnd.lowerBound])
        let appleCTA = try XCTUnwrap(methodPicker.range(of: "appleButton"))
        let googleCTA = try XCTUnwrap(methodPicker.range(of: "googleButton"))
        let emailField = try XCTUnwrap(methodPicker.range(of: "TextField("))

        XCTAssertLessThan(appleCTA.lowerBound, googleCTA.lowerBound)
        XCTAssertLessThan(googleCTA.lowerBound, emailField.lowerBound)
        XCTAssertTrue(authView.contains("auth.continueWithApple"))
        XCTAssertTrue(authView.contains("auth.continueWithGoogle"))
        XCTAssertTrue(authView.contains("accessibilityIdentifier(\"auth.email\")"))
        XCTAssertTrue(authView.contains("auth.authenticate(with: provider)"))
        XCTAssertTrue(authView.contains("ASAuthorizationAppleIDButton"))
        XCTAssertTrue(authView.contains("style: .black"))
        XCTAssertFalse(authView.contains("style: brandMode.prefersDarkInterface ? .white : .black"))
        XCTAssertTrue(authView.contains("Sign in with Google"))
        XCTAssertTrue(authView.contains("Continue with email"))
        XCTAssertTrue(authView.contains("Button(\"Use a password\")"))
        XCTAssertTrue(authView.contains("SecureField(\"Password\""))
        XCTAssertTrue(authView.contains("auth.signInWithPassword"))
        XCTAssertTrue(authView.contains("accessibilityIdentifier(\"auth.password\")"))
        XCTAssertFalse(authGate.contains("AuthView("))
        XCTAssertTrue(clerkService.contains("signInWithApple(transferable: false)"))
        XCTAssertTrue(clerkService.contains("signInWithOAuth("))
        XCTAssertTrue(clerkService.contains("provider: .google"))
        XCTAssertTrue(clerkService.contains("transferable: false"))
        XCTAssertTrue(clerkService.contains("signInWithPassword("))
        XCTAssertTrue(clerkService.contains("identifier: emailAddress"))
    }

    func testNavigationModelRetainsAddRouteWhileHeaderExperimentOwnsVisibleEntryPoint() throws {
        XCTAssertEqual(WanderTab.allCases, [.map, .discover, .add, .lists, .profile])

        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        XCTAssertFalse(root.contains("Label(WanderTab.add.title"))
        XCTAssertTrue(root.contains("private func presentAddSheet()"))
    }

    func testPrimaryTabsUseStaticNativeSymbolsAndSystemSelectionFeedback() throws {
        XCTAssertEqual(WanderTab.primaryTabs, [.map, .discover, .lists, .profile])
        XCTAssertEqual(WanderTab.map.systemImage, "map")
        XCTAssertEqual(WanderTab.discover.systemImage, "newspaper")
        XCTAssertEqual(WanderTab.lists.systemImage, "bookmark.square")
        XCTAssertEqual(WanderTab.profile.systemImage, "person.crop.circle")

        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        XCTAssertFalse(root.contains(".toolbar(.hidden, for: .tabBar)"))
        XCTAssertFalse(root.contains("WanderPrimaryTabBar"))
        XCTAssertFalse(root.contains("WanderNativeTabBarIconConfigurator"))
        XCTAssertEqual(root.components(separatedBy: ".tabItem { tabItemLabel(for:").count - 1, 4)
        XCTAssertTrue(root.contains("Label(tab.title, systemImage: tab.systemImage)"))
        XCTAssertFalse(root.contains("WanderNativeTabTouchObserver"))
        XCTAssertFalse(root.contains("tabBarImage("))
        XCTAssertTrue(root.contains("withTransaction(Transaction(animation: nil))"))
        XCTAssertTrue(root.contains("Let the native tab selection render before analytics work begins"))
        XCTAssertFalse(root.contains("WanderTabPressInteraction"))
        XCTAssertFalse(root.contains("handleTouchDown"))
    }

    func testWalkthroughTabTargetUsesVisibleUnionOfNativeItemControls() throws {
        let visibleBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controlFrames = [
            CGRect(x: 24, y: 752, width: 82, height: 56),
            CGRect(x: 106, y: 750, width: 86, height: 58),
            CGRect(x: 192, y: 751, width: 86, height: 57),
            CGRect(x: 278, y: 752, width: 88, height: 56)
        ]

        let target = try XCTUnwrap(
            WanderTabBarWalkthroughTargetGeometry.targetFrame(
                controlFrames: controlFrames,
                visibleBounds: visibleBounds
            )
        )

        XCTAssertEqual(target, CGRect(x: 24, y: 750, width: 342, height: 58))
        XCTAssertEqual(target.minY, controlFrames.map(\.minY).min())
        XCTAssertEqual(target.maxY, controlFrames.map(\.maxY).max())
        XCTAssertLessThan(target.maxY, visibleBounds.maxY, "The home-indicator area stays scrimmed.")

        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        XCTAssertTrue(root.contains("window.convert($0.bounds, from: $0)"))
        XCTAssertTrue(root.contains("externalTargetFrames: nativeTabItemControlsFrame.map { [.mapTabs: $0] }"))
        XCTAssertTrue(root.contains("if walkthroughs.currentStep?.target == .mapTabs"))
        XCTAssertTrue(root.contains("WanderNativeTabFrameReader("))
        XCTAssertTrue(root.contains("scheduleAttachmentRetry(for: anchorView)"))
        XCTAssertTrue(root.contains("control.accessibilityLabel?.caseInsensitiveCompare(tab.title)"))
        XCTAssertTrue(root.contains("contains(\"UITabBarButton\")"))
        XCTAssertTrue(root.contains("let visibleControls = descendantControls(in: tabBar)"))
        XCTAssertTrue(root.contains("WanderTabBarWalkthroughTargetGeometry.targetFrame("))
        XCTAssertTrue(root.contains("@State private var nativeTabItemControlsFrame: CGRect?"))
        XCTAssertFalse(root.contains("walkthroughTabBarTargetHeight"))
        XCTAssertFalse(root.contains("walkthroughTabBarTargetVerticalOffset"))
        XCTAssertFalse(root.contains("walkthroughTabBarTargetHorizontalInset"))
    }

    func testWalkthroughTabTargetRejectsMissingOrOffscreenControls() {
        let visibleBounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        XCTAssertNil(
            WanderTabBarWalkthroughTargetGeometry.targetFrame(
                controlFrames: [],
                visibleBounds: visibleBounds
            )
        )
        XCTAssertNil(
            WanderTabBarWalkthroughTargetGeometry.targetFrame(
                controlFrames: [CGRect(x: 20, y: 900, width: 80, height: 50)],
                visibleBounds: visibleBounds
            )
        )
        XCTAssertEqual(
            WanderTabBarWalkthroughTargetGeometry.targetFrame(
                controlFrames: [
                    .zero,
                    CGRect(x: -12, y: 780, width: 420, height: 44)
                ],
                visibleBounds: visibleBounds
            ),
            CGRect(x: 0, y: 780, width: 390, height: 44)
        )
    }

    func testDiscoverTabPresentsInlineFeedSearchWithPersistentFeedState() throws {
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
        XCTAssertTrue(feed.contains("FeedSearchLauncher("))
        XCTAssertTrue(feed.contains("placeholders: tickerSuggestions"))
        XCTAssertTrue(feed.contains("setSearchPresented(true)"))
        XCTAssertTrue(feed.contains(".accessibilityLabel(\"Search trusted places\")"))
        XCTAssertTrue(feed.contains(".accessibilityIdentifier(\"feed.searchLauncher\")"))
        XCTAssertFalse(feed.contains(".fullScreenCover(isPresented: $isShowingSearch)"))
        XCTAssertFalse(feed.contains(".sheet(isPresented: $isShowingSearch)"))
        XCTAssertTrue(feed.contains("if isShowingSearch"))
        XCTAssertTrue(feed.contains(".opacity(isShowingSearch ? 0 : 1)"))
        XCTAssertTrue(feed.contains(".accessibilityHidden(isShowingSearch)"))
        XCTAssertTrue(feed.contains("DiscoverScreen("))
        XCTAssertTrue(feed.contains("startsInPlaceSearch: true"))
        XCTAssertTrue(feed.contains("embedsInHostNavigation: true"))
        XCTAssertTrue(feed.contains("searchTransitionNamespace: searchTransitionNamespace"))
        XCTAssertTrue(feed.contains("onClose: closeDiscoverSearch"))
        XCTAssertTrue(feed.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertNil(FeedSearchTransitionPolicy.animation(reduceMotion: true))
        XCTAssertNotNil(FeedSearchTransitionPolicy.animation(reduceMotion: false))
        let feedSearchLauncher = try sourceSection(
            feed,
            after: "private var floatingHeaderContent: some View",
            before: "private var placesSurface: some View"
        )
        XCTAssertTrue(feedSearchLauncher.contains(".feedSearchMatchedGeometry("))
        XCTAssertTrue(feedSearchLauncher.contains("isSource: !isShowingSearch"))
        let searchPresentation = try sourceSection(
            feed,
            after: "private func setSearchPresented(_ isPresented: Bool)",
            before: "private func restoreFeedWalkthroughAfterDiscoverDismissal()"
        )
        XCTAssertTrue(
            searchPresentation.contains(
                "FeedSearchTransitionPolicy.animation(reduceMotion: reduceMotion)"
            )
        )
        let discover = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        XCTAssertTrue(discover.contains("if embedsInHostNavigation"))
        XCTAssertTrue(discover.contains("searchTransitionNamespace: Namespace.ID?"))
        XCTAssertTrue(discover.contains("if selectedMode == .places, isPlaceSearchPresented"))
        XCTAssertTrue(discover.contains("activePlaceSearchHeader"))
        XCTAssertTrue(discover.contains("searchFieldFocused = true"))
        XCTAssertTrue(discover.contains("private var walkthroughSearchBackLabel: String"))
        XCTAssertTrue(discover.contains("\"Back to Feed\""))
        XCTAssertTrue(discover.contains(".accessibilityIdentifier(\"discover.searchBack\")"))
        XCTAssertFalse(discover.contains(".accessibilityIdentifier(\"discover.close\")"))
        XCTAssertTrue(discover.contains(".accessibilityIdentifier(accessibilityIdentifier)"))
        XCTAssertFalse(discover.contains("DiscoverHeader"))
        XCTAssertTrue(discover.contains("suggestedSearchesSection"))
        let activeSearchHeader = try sourceSection(
            discover,
            after: "private var activePlaceSearchHeader: some View",
            before: "private var hidesSearchBackDuringWalkthroughChoice: Bool"
        )
        XCTAssertTrue(activeSearchHeader.contains(".feedSearchMatchedGeometry("))
        XCTAssertTrue(activeSearchHeader.contains("isSource: true"))
        let searchExit = try sourceSection(
            discover,
            after: "private func exitPlaceSearch()",
            before: "private func clearPlaceSearch"
        )
        XCTAssertTrue(searchExit.contains("cancelPlaceSearchWork()"))
        XCTAssertTrue(searchExit.contains("searchFieldFocused = false"))
        XCTAssertTrue(feed.contains("private struct FeedActivityModule"))
        XCTAssertTrue(feed.contains("private struct FeedFeaturedCard"))
        XCTAssertTrue(feed.contains("enum FeedSurface"))
        XCTAssertTrue(feed.contains("private struct FeedSurfaceTabs"))
        XCTAssertTrue(feed.contains("case .people:"))
        XCTAssertTrue(feed.contains("FeedPeopleSurface("))
        XCTAssertTrue(feed.contains("memberQuery: $peopleQuery"))
        XCTAssertTrue(feed.contains("dismissSearchFocus: { peopleSearchFieldFocused = false }"))
        let surfaceChange = try sourceSection(
            feed,
            after: ".onChange(of: selectedSurface)",
            before: ".onChange(of: walkthroughs.currentStep?.target"
        )
        XCTAssertTrue(surfaceChange.contains("if surface != .people"))
        XCTAssertTrue(surfaceChange.contains("peopleQuery = \"\""))
        XCTAssertTrue(feed.contains("PeopleRecommendationShelf("))
        XCTAssertTrue(feed.contains("store.discoverMembers(query: query, backend: backend)"))
        XCTAssertTrue(feed.contains("store.refreshDiscoverPeopleRecommendations(backend: backend, force: force)"))
    }

    func testActivityCommentsPhotoPreviewOpensSwipeableFullScreenViewer() throws {
        let fixtureURL = projectRoot.appendingPathComponent(
            "WanderTests/Fixtures/ios-fix/rec-268-comment-delete-photo-back-pre.json"
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: String]
        )
        let activityViews = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Activity/ActivityEngagementViews.swift"
            )
        )
        XCTAssertEqual(fixture["issue"], "REC-268")
        XCTAssertEqual(fixture["destructive_gesture_policy"], "full-swipe deletion is disabled")
        XCTAssertTrue(activityViews.contains("artworkAction: artworkAction"))
        XCTAssertTrue(activityViews.contains("photoViewerRoute = ActivityCommentsPhotoViewerRoute(mediaID: firstMediaID)"))
        XCTAssertTrue(activityViews.contains("context.media.count == 1 ? \"Open activity photo\" : \"Open activity photos\""))
        XCTAssertTrue(activityViews.contains(".fullScreenCover(item: $photoViewerRoute)"))
        XCTAssertTrue(activityViews.contains("TabView(selection: $selectedMediaID)"))
        XCTAssertTrue(activityViews.contains(".tabViewStyle(.page(indexDisplayMode: .automatic))"))
        XCTAssertTrue(activityViews.contains("WanderGlassActionButton("))
        XCTAssertTrue(activityViews.contains("accessibilityLabel: \"Back\""))
        XCTAssertTrue(activityViews.contains("tone: .darkOverlay"))
        XCTAssertTrue(activityViews.contains(".swipeActions(edge: .trailing, allowsFullSwipe: false)"))
        XCTAssertTrue(activityViews.contains("store.canDeleteActivityComment(comment)"))
    }

    func testActivityCommentsUseNativeNavigationDestinationForInteractiveBackSwipe() throws {
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let activityViews = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Activity/ActivityEngagementViews.swift"
            )
        )
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(feed.contains(".navigationDestination(item: commentsRouteBinding)"))
        XCTAssertFalse(feed.contains(".fullScreenCover(item: commentsRouteBinding)"))
        XCTAssertTrue(activityViews.contains(".navigationTitle(\"comments\")"))
        XCTAssertFalse(activityViews.contains(".navigationBarBackButtonHidden(true)"))
        XCTAssertTrue(activityViews.contains(".toolbar(.hidden, for: .tabBar)"))

        let commentsScreen = try sourceSection(
            activityViews,
            after: "struct ActivityCommentsScreen: View",
            before: "private struct ActivityCommentsPhotoViewerRoute"
        )
        XCTAssertFalse(commentsScreen.contains("NavigationStack"))
        XCTAssertTrue(commentsScreen.contains("ActivityPostcardView("))
        XCTAssertTrue(commentsScreen.contains("showsCommentButton: false"))
        XCTAssertTrue(commentsScreen.contains("postcardAccessibilityIdentifier: \"comments.activity.postcard\""))
        XCTAssertTrue(commentsScreen.contains("secondaryMetadataTitle: secondaryListContext?.name"))
        XCTAssertTrue(commentsScreen.contains("openList(listContext.id)"))
        XCTAssertTrue(mapScreen.contains("rating: entry.ratingScore"))
    }

    func testPrimarySurfacesUseAstirFloatingHeadersAndIndependentGlassNavigationWithoutLosingFilterState() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let astir = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/AstirVisualSystem.swift")
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
        XCTAssertTrue(theme.contains("struct WanderGlassButtonCluster<Content: View>"))
        XCTAssertTrue(theme.contains("GlassEffectContainer(spacing: mergeSpacing)"))
        XCTAssertTrue(astir.contains("struct AstirFloatingHeaderSurface<Content: View>"))
        XCTAssertTrue(astir.contains("struct AstirIconActionButton: View"))
        XCTAssertTrue(astir.contains("struct AstirEditorialSegmentedSwitch: View"))
        XCTAssertTrue(astir.contains(".saturation(0)"))
        XCTAssertTrue(astir.contains("if dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(astir.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertTrue(astir.contains("optionsRow(usesAccessibilityWidths: true)"))
        XCTAssertTrue(astir.contains("HStack(spacing: usesAccessibilityWidths ? 6 : 0)"))
        XCTAssertTrue(astir.contains("minWidth: usesAccessibilityWidths ? 148 : nil"))
        XCTAssertTrue(astir.contains(".astirGlassSurface(cornerRadius: 17, castsShadow: true)"))

        XCTAssertTrue(root.contains("onAdd: presentAddSheet"))
        XCTAssertTrue(root.contains("private func presentAddSheet()"))
        XCTAssertFalse(root.contains("Label(WanderTab.add.title"))
        XCTAssertTrue(map.contains("accessibilityIdentifier: \"map.headerAdd\""))
        XCTAssertTrue(map.contains("struct MapSourceFilterChip"))
        XCTAssertTrue(map.contains(".astirGlassSurface(cornerRadius: 18, selected: isSelected, castsShadow: true)"))
        XCTAssertTrue(map.contains(".astirGlassSurface(cornerRadius: 18, selected: isActive, castsShadow: true)"))
        let mapAddButton = try sourceSection(
            map,
            after: "private struct MapGlassAddButton: View",
            before: "private struct SearchBar: View"
        )
        XCTAssertTrue(mapAddButton.contains("AstirIconActionButton("))
        XCTAssertTrue(mapAddButton.contains("accessibilityIdentifier: \"map.headerAdd\""))
        XCTAssertFalse(mapAddButton.contains(".wanderGlassCapsule("))
        XCTAssertFalse(mapAddButton.contains(".background(WanderTheme.terracotta.color, in: Circle())"))
        let nearbyButton = try sourceSection(
            map,
            after: "private struct RecenterButton: View",
            before: "private struct MapLocationEducationPrompt: View"
        )
        XCTAssertTrue(nearbyButton.contains(".wanderGlassCapsule(tone: appearance.neutralGlassTone)"))
        XCTAssertFalse(nearbyButton.contains(".background(appearance.isDark"))
        let mapSearchSurface = try sourceSection(
            map,
            after: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier",
            before: "private extension View"
        )
        XCTAssertTrue(mapSearchSurface.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(mapSearchSurface.contains("let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)"))
        XCTAssertTrue(mapSearchSurface.contains(".glassEffect("))
        XCTAssertTrue(mapSearchSurface.contains(".tint(astirBrandMode.background.opacity(0.74))"))
        XCTAssertTrue(mapSearchSurface.contains(".interactive(true)"))
        XCTAssertTrue(mapSearchSurface.contains(".background(.ultraThinMaterial, in: shape)"))

        XCTAssertFalse(feed.contains("WanderGlassHeader("))
        XCTAssertTrue(feed.contains("accessibilityIdentifier: \"feed.headerAdd\""))
        XCTAssertTrue(feed.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertTrue(feed.contains("-WanderFeedSurface"))
        XCTAssertTrue(feed.contains("ZStack(alignment: .top)"))
        let rootComposition = try sourceSection(
            feed,
            after: "ZStack(alignment: .top) {",
            before: ".background(astirBrandMode.background.ignoresSafeArea())"
        )
        XCTAssertTrue(rootComposition.contains("floatingHeader"))
        XCTAssertTrue(rootComposition.contains(".zIndex(3)"))
        XCTAssertTrue(rootComposition.contains("FeedFloatingHeaderHeightPreferenceKey.self"))
        XCTAssertTrue(feed.contains(".onPreferenceChange(FeedFloatingHeaderHeightPreferenceKey.self)"))
        XCTAssertFalse(feed.contains("WanderGlassButtonCluster"))
        let floatingHeader = try sourceSection(
            feed,
            after: "private var floatingHeaderContent: some View",
            before: "private var placesSurface: some View"
        )
        let mastheadPosition = try XCTUnwrap(
            floatingHeader.range(of: "AstirMastheadLockup(presentation: .localizedBlur)")
        )
        let searchPosition = try XCTUnwrap(floatingHeader.range(of: "switch selectedSurface"))
        let controlsPosition = try XCTUnwrap(
            floatingHeader.range(
                of: "HStack(spacing: WanderTheme.spacing2) {",
                range: searchPosition.upperBound..<floatingHeader.endIndex
            )
        )
        XCTAssertLessThan(mastheadPosition.lowerBound, searchPosition.lowerBound)
        XCTAssertLessThan(searchPosition.lowerBound, controlsPosition.lowerBound)
        XCTAssertTrue(floatingHeader.contains("FeedSearchLauncher("))
        XCTAssertTrue(floatingHeader.contains("FeedPeopleSearchField(text: $peopleQuery)"))
        XCTAssertTrue(floatingHeader.contains("FeedSurfaceTabs(selectedSurface: $selectedSurface)"))
        XCTAssertTrue(floatingHeader.contains("AstirIconActionButton("))
        XCTAssertTrue(floatingHeader.contains(".focused($peopleSearchFieldFocused)"))
        let placesSurface = try sourceSection(
            feed,
            after: "private var placesSurface: some View",
            before: "private func openDiscoverSearch()"
        )
        XCTAssertFalse(placesSurface.contains("FeedSearchLauncher("))
        XCTAssertTrue(placesSurface.contains(".padding(.top, feedContentTopInset)"))
        let peopleSurface = try sourceSection(
            feed,
            after: "private struct FeedPeopleSurface: View",
            before: "private struct FeedPeopleSearchField: View"
        )
        XCTAssertTrue(peopleSurface.contains("@Binding var memberQuery: String"))
        XCTAssertTrue(peopleSurface.contains("let contentTopInset: CGFloat"))
        XCTAssertFalse(peopleSurface.contains("FeedPeopleSearchField("))
        XCTAssertFalse(peopleSurface.contains("FeedPeopleValueNote("))
        XCTAssertFalse(peopleSurface.contains("Follow people whose taste you trust"))
        XCTAssertTrue(peopleSurface.contains(".padding(.top, contentTopInset)"))
        let feedSearch = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedSearchLauncher: View").last?
                .components(separatedBy: "private struct FeedSectionHeading: View").first
        )
        XCTAssertTrue(feedSearch.contains(".astirOutlinedSurface(castsShadow: true)"))
        XCTAssertFalse(feedSearch.contains(".background(WanderTheme.surfaceRaised.color)"))
        let peopleSearch = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedPeopleSearchField: View").last?
                .components(separatedBy: "private struct FeedPeopleLoadingPanel: View").first
        )
        XCTAssertTrue(peopleSearch.contains(".astirOutlinedSurface(castsShadow: true)"))
        XCTAssertFalse(peopleSearch.contains(".background(WanderTheme.surfaceRaised.color)"))

        XCTAssertFalse(lists.contains("WanderGlassHeader("))
        XCTAssertTrue(lists.contains("accessibilityIdentifier: \"lists.headerAdd\""))
        XCTAssertTrue(lists.contains("AstirFloatingHeaderSurface"))
        XCTAssertTrue(lists.contains("AstirIconActionButton("))
        XCTAssertTrue(lists.contains("AstirEditorialSegmentedSwitch("))
    }

    func testPrimaryFloatingGlassControlsStayIndependentWhileTrueGroupsKeepClusters() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let profile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let walkthrough = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Onboarding/FirstVisitWalkthrough.swift")
        )

        XCTAssertTrue(theme.contains("struct WanderGlassButtonCluster<Content: View>"))
        XCTAssertTrue(theme.contains("mergeSpacing: CGFloat = WanderTheme.spacing1"))
        XCTAssertTrue(theme.contains("GlassEffectContainer(spacing: mergeSpacing)"))
        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *)"))

        XCTAssertEqual(map.components(separatedBy: "WanderGlassButtonCluster").count - 1, 0)
        XCTAssertTrue(map.contains("MapGlassAddButton"))
        XCTAssertTrue(map.contains("SearchBar("))
        XCTAssertTrue(map.contains("RecenterButton("))
        XCTAssertTrue(map.contains(".padding(.bottom, nearbyClusterBottomPadding)"))
        XCTAssertEqual(placeProfile.components(separatedBy: "WanderGlassButtonCluster").count - 1, 2)
        XCTAssertTrue(placeProfile.contains("WanderGlassButtonCluster(mergeSpacing: 0)"))
        XCTAssertTrue(placeProfile.contains("WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing2)"))
        XCTAssertEqual(profile.components(separatedBy: "WanderGlassButtonCluster").count - 1, 2)
        XCTAssertTrue(walkthrough.contains("WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing2)"))
    }

    func testListsHeaderKeepsItsAddActionWithoutAFullWidthGlassPanel() throws {
        let lists = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let home = try sourceSection(
            lists,
            after: "private var homeScreen: some View",
            before: "private var scopeSwitch: some View"
        )

        XCTAssertFalse(home.contains("AstirMastheadLockup("))
        XCTAssertFalse(home.contains("Text(\"lists\")"))
        XCTAssertFalse(home.contains("save places into a plan you can actually use"))
        XCTAssertTrue(lists.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertTrue(home.contains("AstirIconActionButton("))
        XCTAssertTrue(home.contains("accessibilityIdentifier: \"lists.headerAdd\""))
        XCTAssertTrue(home.contains(".astirScrollTracking("))
        XCTAssertTrue(home.contains("AstirFloatingHeaderBehavior.animation"))
        XCTAssertFalse(home.contains("WanderGlassHeader("))
        XCTAssertFalse(home.contains(".wanderGlassPanel("))
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
        XCTAssertEqual(
            MapScreen.resolvedInitialMapSearchMessage(
                from: ["Wander", "-WanderMapSearchMessage", "Map result"]
            ),
            "Map result"
        )
        XCTAssertNil(
            MapScreen.resolvedInitialMapSearchMessage(
                from: ["Wander", "-WanderMapSearchMessage"]
            )
        )
    }

    func testMapSearchSuccessDoesNotRenderARedundantResultMessage() throws {
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertFalse(map.contains("Map result. Tap + to add it."))
        XCTAssertFalse(map.contains("Map place. Tap + to add it."))
        XCTAssertFalse(map.contains("Also showing new map results."))
        XCTAssertTrue(map.contains("No places on your map or map results found."))
        XCTAssertTrue(map.contains("That shared place could not be opened. Try the link again."))
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
        XCTAssertTrue(map.contains("MapSearchCancelButton(action: cancelMapSearch)"))
        XCTAssertTrue(map.contains(".accessibilityIdentifier(\"map.searchCancel\")"))
        XCTAssertTrue(map.contains("if !isMapSearchFocused {"))
        XCTAssertTrue(map.contains("HStack(spacing: WanderTheme.spacing1)"))
        XCTAssertTrue(map.contains("MapControlLayout.searchDockClearance"))
        XCTAssertTrue(map.contains("mapSearchDockClearance"))
        XCTAssertTrue(map.contains("edges: isMapSearchFocused ? [] : .bottom"))
        let typeahead = try XCTUnwrap(
            map.components(separatedBy: "private struct MapTypeaheadList: View").last?
                .components(separatedBy: "private struct MapTypeaheadRow: View").first
        )
        XCTAssertTrue(typeahead.contains("let visibleSuggestions = Array(suggestions.prefix(4))"))
        XCTAssertTrue(typeahead.contains(".astirGlassSurface("))
        XCTAssertFalse(typeahead.contains(".wanderGlassPanel("))
        XCTAssertFalse(typeahead.contains(".background(WanderTheme.surfaceRaised.color)"))
    }

    func testFeedSaveUsesTheCanonicalPlaceSaveFlowAndMakesEveryActivityAPlacePostcard() throws {
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let activityViews = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Activity/ActivityEngagementViews.swift"
            )
        )
        let activityModels = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Services/ActivityEngagementModels.swift"
            )
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
        let postcard = try sourceSection(
            activityViews,
            after: "struct ActivityPostcardView: View",
            before: "private struct ActivityPostcardArtwork"
        )
        let postcardArtwork = try sourceSection(
            activityViews,
            after: "private struct ActivityPostcardArtwork: View",
            before: "struct ActivityCommentsScreen: View"
        )
        XCTAssertTrue(activityModule.contains("ActivityPostcardView("))
        XCTAssertTrue(activityModule.contains("let engagementContext = activity.activityEngagementContext"))
        XCTAssertTrue(activityModule.contains("context: engagementContext ?? fallbackPostcardContext"))
        XCTAssertTrue(activityModule.contains("activity.note"))
        XCTAssertTrue(activityModule.contains("activity.rating"))
        XCTAssertTrue(postcard.contains("visualStyle == .astir ? AstirTypography.sectionTitle : WanderTypography.editorialTitle"))
        XCTAssertTrue(postcard.contains("Text(\"“\\(note)”\")"))
        XCTAssertTrue(postcard.contains("visualStyle == .astir ? AstirTypography.bodySmall : .system(.subheadline, design: .serif, weight: .medium)"))
        XCTAssertTrue(postcard.contains(".background(noteBackground)"))
        XCTAssertTrue(postcard.contains("ActivityPostcardArtwork("))
        XCTAssertTrue(postcard.contains("Button(action: artworkAction)"))
        XCTAssertTrue(postcard.contains(".frame(height: ActivityPostcardLayout.artworkHeight)"))
        XCTAssertTrue(postcard.contains(".clipped()"))
        XCTAssertTrue(postcard.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(postcard.contains("ActivityPostcardTypographyPolicy.ticketBadgeFontSize"))
        XCTAssertTrue(postcardArtwork.contains("FeedResolvedPlacePhoto(place: visiblePlace)"))
        XCTAssertTrue(activityModule.contains("if let place = activity.place"))
        XCTAssertTrue(activityModule.contains("openPlace(place)"))
        XCTAssertTrue(activityModule.contains("openList(list)"))
        XCTAssertTrue(activityModule.contains("openProfile(activity.actor)"))
        XCTAssertTrue(activityModule.contains("feed.activity.\\(activity.id).actor"))
        XCTAssertTrue(activityModule.contains("feed.activity.\\(activity.id).place"))
        XCTAssertTrue(postcard.contains("private var actorAttribution: some View"))
        XCTAssertTrue(postcard.contains("private var destinationHeader: some View"))
        XCTAssertTrue(postcard.contains("cornerRadius: visualStyle == .astir ? 22 : WanderTheme.radiusLarge"))
        XCTAssertTrue(postcard.contains(".stroke(borderColor, lineWidth: 1)"))
        XCTAssertTrue(postcard.contains("showsCommentButton: showsCommentButton"))
        XCTAssertFalse(activityModule.contains("lightweightActivityRow"))
        XCTAssertFalse(activityModule.contains("Label(\"View place\""))
        XCTAssertFalse(activityModule.contains("FeedMediaRail"))
        XCTAssertFalse(activityModule.contains(".checkInTicketSurface("))
        XCTAssertFalse(activityModule.contains("arrow.up.right"))
        XCTAssertFalse(activityModule.contains(".underline("))
        XCTAssertTrue(activityModule.contains("resolvedTicketKind.defaultTicketEyebrow"))
        XCTAssertTrue(activityModels.contains("case .wanna: \"Wanna\""))
        XCTAssertTrue(feed.contains("private var selectedPlaceDestination: some View"))
        XCTAssertTrue(feed.contains("PlaceProfileFullScreen("))

        let featuredCard = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedFeaturedCard: View").last?
                .components(separatedBy: "private struct FeedActivityList: View").first
        )
        XCTAssertFalse(featuredCard.contains("height: FeedFeaturedLayout.cardHeight"))
        XCTAssertTrue(featuredCard.contains("width: FeedFeaturedLayout.cardWidth"))
        XCTAssertTrue(featuredCard.contains("height: FeedFeaturedLayout.fullBleedArtworkHeight"))
        XCTAssertTrue(
            featuredCard.contains(".padding(.horizontal, -FeedFeaturedLayout.cardContentInset)")
        )
        XCTAssertTrue(featuredCard.contains(".padding(.top, -FeedFeaturedLayout.cardContentInset)"))
        XCTAssertTrue(featuredCard.contains(".padding(FeedFeaturedLayout.cardContentInset)"))
        XCTAssertTrue(featuredCard.contains("private var featuredActivity: String"))
        XCTAssertTrue(featuredCard.contains("WanderAvatar("))
        XCTAssertTrue(featuredCard.contains("openProfile(featured.actor)"))
        XCTAssertTrue(featuredCard.contains("avatarURL: featured.actor.avatarURL"))
        XCTAssertTrue(featuredCard.contains("• \\(featured.actor.displayName) • \\(featuredActivity)"))
        XCTAssertFalse(featuredCard.contains("avatarURL: featured.visiblePlace.owner.avatarURL"))
        XCTAssertTrue(featuredCard.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(featuredCard.contains("Label(\"View place\""))

        let featuredLayout = try XCTUnwrap(
            feed.components(separatedBy: "private enum FeedFeaturedLayout").last?
                .components(separatedBy: "private enum FeedActivityLayout").first
        )
        XCTAssertTrue(featuredLayout.contains("static let insetArtworkHeight: CGFloat = 88"))
        XCTAssertTrue(
            featuredLayout.contains(
                "static let fullBleedArtworkHeight = insetArtworkHeight + cardContentInset"
            )
        )
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
        let activityViews = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Activity/ActivityEngagementViews.swift"
            )
        )
        let featuredArtwork = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedPlaceArtwork: View").last?
                .components(separatedBy: "struct FeedResolvedPlacePhoto: View").first
        )
        XCTAssertTrue(featuredArtwork.contains("FeedResolvedPlacePhoto(place: place)"))
        XCTAssertTrue(featuredArtwork.contains(".clipped()"))
        XCTAssertFalse(featuredArtwork.contains(".clipShape(RoundedRectangle"))

        let resolvedPhoto = try XCTUnwrap(
            feed.components(separatedBy: "struct FeedResolvedPlacePhoto: View").last?
                .components(separatedBy: "private struct FeedLoadingState: View").first
        )
        XCTAssertTrue(resolvedPhoto.contains("@EnvironmentObject private var backend: WanderBackend"))
        XCTAssertTrue(resolvedPhoto.contains("@State private var photo: PlacePhoto?"))
        XCTAssertTrue(resolvedPhoto.contains("@State private var failedGooglePhotoID: String?"))
        XCTAssertTrue(resolvedPhoto.contains("await backend.placePhoto("))
        XCTAssertTrue(resolvedPhoto.contains("await backend.visibleUserPlacePhoto("))
        XCTAssertTrue(resolvedPhoto.contains("photoRequest: sheetPlace.photoRequest"))
        XCTAssertTrue(resolvedPhoto.contains("variant: .feed"))
        XCTAssertTrue(resolvedPhoto.contains("PlaceProfilePhotoImage("))
        XCTAssertTrue(resolvedPhoto.contains("onLoadFailure:"))
        XCTAssertFalse(resolvedPhoto.contains("Text(\"Google Maps\")"))

        let activityArtwork = try XCTUnwrap(
            activityViews.components(separatedBy: "private struct ActivityPostcardArtwork: View").last?
                .components(separatedBy: "struct ActivityCommentsScreen: View").first
        )
        XCTAssertTrue(activityArtwork.contains("FeedResolvedPlacePhoto(place: visiblePlace)"))

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
        XCTAssertTrue(mapCaptureRoot.contains("initialSession: auth.state.session"))
        XCTAssertTrue(mapCaptureRoot.contains(".environmentObject(mapCaptureBackend)"))
        XCTAssertFalse(mapCaptureRoot.contains(".environmentObject(backend)"))
        XCTAssertTrue(app.contains("provider: \"google_places\""))
        XCTAssertTrue(app.contains("provider: \"visit_photo\""))
        XCTAssertTrue(app.contains("UIImage(named: assetName)"))
    }

    func testFeedPlaceActionsAllRouteThroughCurrentPlaceProfile() throws {
        let feed = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift"))
        let activityEngagement = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Activity/ActivityEngagementViews.swift")
        )
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
        XCTAssertTrue(activityModule.contains("ActivityPostcardView("))
        XCTAssertTrue(activityEngagement.contains("Text(\"\\(context.actor.displayName) \\(context.attributionAction)\")"))
        XCTAssertTrue(activityEngagement.contains("Text(context.placeName)"))
        XCTAssertTrue(activityEngagement.contains("private var primaryDestinationTitle: some View"))
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
    func testAppInviteContainsTestFlightAndSenderProfileLinks() {
        let content = WanderShareContent.appInvite(senderProfileID: "user sender")

        XCTAssertEqual(content.item, WanderShareContent.publicTestFlightURL)
        XCTAssertEqual(content.items.map(\.absoluteString), [
            "https://testflight.apple.com/join/knEhRa6t",
            "https://getrec.me/profiles/user%20sender"
        ])
        XCTAssertTrue(content.messageBody.contains("Install the TestFlight beta"))
        XCTAssertTrue(content.messageBody.contains("https://testflight.apple.com/join/knEhRa6t"))
        XCTAssertTrue(content.messageBody.contains("https://getrec.me/profiles/user%20sender"))

        let anonymousContent = WanderShareContent.appInvite(senderProfileID: nil)
        XCTAssertEqual(anonymousContent.items, [WanderShareContent.publicTestFlightURL])
    }

    @MainActor
    func testPlaceListAndInviteSharesUseCanonicalGetRecMeURLs() throws {
        let placeID = "40000000-0000-0000-0000-000000000001"
        let activityID = "41000000-0000-0000-0000-000000000001"
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
            WanderShareContent.activity(
                activityID: activityID,
                placeName: "Ggiata",
                message: "See this check-in"
            )?.item.absoluteString,
            "https://getrec.me/activities/\(activityID)"
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
            WanderShareContent.activity(
                activityID: "local-activity",
                placeName: "Unsynced",
                message: "Not shareable yet"
            )
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
        XCTAssertTrue(home.contains("ProfileInCommonPlacesRow("))
        XCTAssertTrue(home.contains("See where your maps overlap"))
        XCTAssertTrue(home.contains("WanderShareContent.profileMap("))
    }

    func testInCommonVisibilityPersistsForMembersButNeverAppearsOnSelfProfile() {
        let memberMode = ProfileHomeMode.member(relationship: .mutual, inCommonCount: 0)

        XCTAssertEqual(
            memberMode.visibleInCommonCount(profileID: "user_maya", viewerID: "user_joe"),
            0
        )
        XCTAssertNil(
            memberMode.visibleInCommonCount(profileID: "user_joe", viewerID: "user_joe")
        )
        XCTAssertNil(
            ProfileHomeMode.owner.visibleInCommonCount(
                profileID: "user_joe",
                viewerID: "user_joe"
            )
        )
    }

    func testInCommonOverlapScoreUsesTheVisiblePlaceUnion() {
        XCTAssertEqual(
            InCommonReleaseProjection.overlapScore(
                sharedCount: 4,
                viewerCount: 10,
                profileCount: 8
            ),
            29
        )
        XCTAssertEqual(
            InCommonReleaseProjection.overlapScore(
                sharedCount: 5,
                viewerCount: 5,
                profileCount: 5
            ),
            100
        )
        XCTAssertEqual(
            InCommonReleaseProjection.overlapScore(
                sharedCount: 0,
                viewerCount: 0,
                profileCount: 0
            ),
            0
        )
    }

    func testInCommonProductionSurfaceIsReleaseVisibleAndUsesRealData() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let releaseSurfaceRange = try XCTUnwrap(source.range(of: "enum InCommonReleaseProjection"))
        let sourceBeforeReleaseSurface = String(source[..<releaseSurfaceRange.lowerBound])
        let releaseSurface = String(source[releaseSurfaceRange.lowerBound...])

        if let lastDebugStart = sourceBeforeReleaseSurface.range(of: "#if DEBUG", options: .backwards) {
            let lastDebugEnd = try XCTUnwrap(
                sourceBeforeReleaseSurface.range(of: "#endif", options: .backwards)
            )
            XCTAssertGreaterThan(lastDebugEnd.lowerBound, lastDebugStart.lowerBound)
        }
        XCTAssertTrue(releaseSurface.contains("store.placesInCommon(with: profileID)"))
        XCTAssertTrue(releaseSurface.contains("InCommonReleaseHero("))
        XCTAssertTrue(releaseSurface.contains("TextField(\"search \\(navigationTitle.lowercased())\""))
        XCTAssertTrue(releaseSurface.contains("Label(\"Open your shared map\", systemImage: \"map.fill\")"))
        XCTAssertTrue(releaseSurface.contains("InCommonReleaseMapScreen("))
        XCTAssertTrue(releaseSurface.contains("ProfilePlaceCollectionMap("))
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

    func testPlaceHistoryKeepsVariableHeightCardsMountedDuringScroll() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let activitySection = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "struct PlaceActivitySection: View")
                .last?
                .components(separatedBy: "private struct PlaceActivityFilterControl: View")
                .first
        )

        XCTAssertTrue(activitySection.contains("VStack(spacing: WanderTheme.spacing2)"))
        XCTAssertTrue(activitySection.contains("ForEach(filteredEntries)"))
        XCTAssertFalse(activitySection.contains("LazyVStack"))
    }

    func testMapPlaceCardUsesPhotoBackedRoundedSurfaceWhileHistoryKeepsTicketsAndFeedUsesPostcards() throws {
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
        XCTAssertFalse(previewCard.contains(".checkInTicketSurface("))
        XCTAssertFalse(previewCard.contains("PlaceProfilePhotoImage("))
        XCTAssertTrue(previewCard.contains("Image(uiImage: displayedImage)"))
        XCTAssertFalse(previewCard.contains("image.byPreparingForDisplay()"))
        XCTAssertTrue(previewCard.contains("PlacePhotoImagePipeline.shared.image("))
        XCTAssertTrue(previewCard.contains("onReady()"))
        XCTAssertFalse(previewCard.contains("Text(place.categoryEmoji)"))
        XCTAssertTrue(previewCard.contains("AstirTypography.sheetTitle"))
        XCTAssertTrue(previewCard.contains("cornerRadius: 30"))
        XCTAssertTrue(previewCard.contains("PlaceCardRatingDistanceRow("))
        XCTAssertTrue(previewCard.contains("providerName: displayedPhoto?.provider"))
        XCTAssertTrue(previewCard.contains("PlaceCardHoursBadge("))
        XCTAssertTrue(previewCard.contains("private var cardPressGesture: some Gesture"))
        XCTAssertTrue(previewCard.contains("PlaceProfilePreviewCardPressPolicy.shouldOpen("))
        XCTAssertTrue(previewCard.contains(".padding(.trailing, 74)"))
        XCTAssertFalse(previewCard.contains("PlaceCardPhotoAttribution"))
        XCTAssertFalse(previewCard.contains("map.selectedPlaceAttribution"))
        XCTAssertTrue(placeProfile.contains("private struct PlaceCardProviderRatingBadge: View"))
        XCTAssertTrue(placeProfile.contains("case \"Yelp\":"))
        XCTAssertTrue(placeProfile.contains("Text(\"Yelp\")"))
        XCTAssertTrue(placeProfile.contains("map.selectedPlaceRatingProvider"))
        XCTAssertTrue(previewCard.contains("WanderGlassButtonCluster(mergeSpacing: 0)"))
        XCTAssertTrue(previewCard.contains("VStack(spacing: 4)"))
        XCTAssertTrue(previewCard.contains("activeCardAction: PlaceCardPreviewAction?"))
        XCTAssertTrue(previewCard.contains("guard activeCardAction == nil else"))
        XCTAssertTrue(previewCard.contains("PlaceCardGlassActionButtonStyle("))
        XCTAssertTrue(previewCard.contains("configuration.label"))
        XCTAssertTrue(previewCard.contains("private var actionButtonGlyphs: some View"))
        XCTAssertTrue(previewCard.contains("actionButtonGlyphs\n                .allowsHitTesting(false)"))
        XCTAssertTrue(previewCard.contains(".foregroundStyle(Color.white)"))
        XCTAssertTrue(previewCard.contains(".opacity(1)"))
        XCTAssertTrue(previewCard.contains(".contentShape(RoundedRectangle(cornerRadius: 15"))
        XCTAssertFalse(previewCard.contains("configuration.label\n                .allowsHitTesting(false)"))
        XCTAssertTrue(previewCard.contains(".zIndex(2)"))
        XCTAssertTrue(previewCard.contains("showsBorder: false"))
        XCTAssertTrue(previewCard.contains("Image(systemName: \"square.and.arrow.up\")"))
        XCTAssertTrue(previewCard.contains("Image(systemName: \"mappin.and.ellipse\")"))
        XCTAssertTrue(previewCard.contains("Text(\"Saved from a dropped pin\")"))
        XCTAssertTrue(previewCard.contains("configuration.isPressed && !reduceMotion ? 1.3 : 1"))
        XCTAssertTrue(previewCard.contains("anchor: .center"))
        XCTAssertTrue(previewCard.contains("frame(width: 44, height: 44, alignment: .center)"))
        XCTAssertTrue(previewCard.contains("WanderTheme.terracotta.color.opacity(0.18)"))
        XCTAssertFalse(previewCard.contains("configuration.isPressed && !reduceMotion ? 1.4 : 1"))
        XCTAssertFalse(previewCard.contains("scaleEffect(configuration.isPressed && !reduceMotion ? 1.6 : 1)"))
        XCTAssertTrue(mapScreen.contains(".overlay(alignment: .topTrailing)"))
        XCTAssertFalse(mapScreen.contains(".overlay(alignment: .topLeading) {\n                    if showsAttentionBadge"))
        XCTAssertTrue(mapScreen.contains("handleCompactCardReady(for:"))
        XCTAssertFalse(mapScreen.contains("prepareCompactCardForPhoto()"))
        XCTAssertTrue(mapScreen.contains("let keepsPresentedCardMounted = previous != nil"))
        XCTAssertFalse(mapScreen.contains("replacementFadeOutDuration"))
        XCTAssertTrue(mapScreen.contains("private func replayActivePinBounce()"))
        XCTAssertTrue(mapScreen.contains("if descriptor.bounceRevision != bounceRevision"))
        XCTAssertTrue(placeProfile.contains("PlaceProfilePreviewCardPressSession"))
        XCTAssertTrue(placeProfile.contains("PlaceProfilePreviewCardPressPolicy.shouldOpen("))
        XCTAssertFalse(placeProfile.contains("cardPressStartedAt"))
        XCTAssertTrue(mapScreen.contains("Text(\"check-in history\")"))
        XCTAssertTrue(activityCard.contains(".checkInTicketSurface("))
        XCTAssertTrue(activityCard.contains("ticketAccentColor"))
        XCTAssertTrue(activityCard.contains("AstirTypography.sectionTitle"))
        XCTAssertTrue(activityCard.contains("StatusBadge(status: entry.status)"))
        XCTAssertTrue(activityCard.contains("if let note = entry.note"))
        XCTAssertTrue(activityCard.contains("ForEach(entry.tags.prefix(6)"))
        XCTAssertTrue(activityCard.contains("photoThumbnails"))
        XCTAssertTrue(activityCard.contains("addPhotoControl"))

        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let activityViews = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Activity/ActivityEngagementViews.swift"
            )
        )
        XCTAssertTrue(feed.contains(".environment(\\.activityPostcardVisualStyle, .astir)"))
        XCTAssertTrue(activityViews.contains("ActivityPostcardLayout.artworkHeight"))
        XCTAssertTrue(activityViews.contains(".stroke(borderColor, lineWidth: 1)"))
        XCTAssertTrue(feed.contains("activity.resolvedTicketKind"))
        XCTAssertFalse(activityViews.contains(".checkInTicketSurface("))
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

    func testAstirTypographyUsesSemanticRolesAcrossPrimaryAndStreakSurfaces() throws {
        let astir = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/AstirVisualSystem.swift")
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

        let typography = try sourceSection(
            astir,
            after: "enum AstirTypography {",
            before: "private struct AstirScreenSurface"
        )
        XCTAssertTrue(typography.contains("screenTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)"))
        XCTAssertTrue(typography.contains("sectionTitle = Font.system(.title3, design: .serif).weight(.semibold)"))
        XCTAssertTrue(typography.contains("relativeTo: .body"))
        XCTAssertTrue(typography.contains("relativeTo: .caption"))

        XCTAssertFalse(feed.contains(".navigationTitle(\"Feed\")"))
        XCTAssertTrue(feed.contains("FeedSearchLauncher("))
        XCTAssertTrue(feed.contains("placeholders: tickerSuggestions"))
        XCTAssertTrue(feed.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertFalse(feed.contains("Picker(\"Feed section\", selection: $selectedSurface)"))

        XCTAssertFalse(placeProfile.contains(".navigationTitle(\"\")"))
        XCTAssertFalse(placeProfile.contains(".navigationTitle(place.name)"))
        XCTAssertTrue(placeProfile.contains("headerNavigationControls(topInset: headerTopInset)"))
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(mapScreen.contains("NavigationStack {\n                    selectedPlaceProfileDestination"))
        XCTAssertTrue(mapScreen.contains("\\.placeProfileFloatingActionVariant"))
        XCTAssertTrue(mapScreen.contains(".id(compactSelectionIdentity)"))
        let mapHeader = try XCTUnwrap(
            placeProfile.components(separatedBy: "private struct PlaceProfileMapHeader: View").last
        )
        XCTAssertFalse(mapHeader.contains("Button(action: onBack)"))
        XCTAssertFalse(mapHeader.contains("WanderShareButton"))

        XCTAssertFalse(streak.contains("WanderTypography"))
        XCTAssertTrue(streak.contains(".font(AstirTypography.sheetTitle)"))
        XCTAssertTrue(streak.contains("weight: .semibold, design: .serif"))
    }

    func testPlaceProfileHeaderIsFullBleedAcrossSaveStatesAndLongNames() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let astir = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/AstirVisualSystem.swift")
        )
        let fullView = try sourceSection(
            placeProfile,
            after: "private struct PlaceProfileFullView: View {",
            before: "struct PlaceProfileFloatingActions: View {"
        )
        let navigationControls = try sourceSection(
            fullView,
            after: "private func headerNavigationControls(topInset: CGFloat) -> some View {",
            before: "private func headerNavigationLabel(systemImage: String) -> some View {"
        )

        // The same chrome is used for unsaved (.add), checked-in (.addVisit),
        // and arbitrarily long place names, so state cannot restore stale copy.
        XCTAssertTrue(fullView.contains("let action: PlaceSheetAction"))
        XCTAssertTrue(fullView.contains("Text(place.name)"))
        XCTAssertTrue(fullView.contains(".lineLimit(3)"))
        XCTAssertFalse(fullView.contains(".navigationTitle(\"\")"))
        XCTAssertFalse(fullView.contains(".navigationTitle(place.name)"))
        XCTAssertFalse(fullView.contains(".toolbarColorScheme(.dark, for: .navigationBar)"))
        XCTAssertFalse(fullView.contains(".toolbarBackground(.hidden, for: .navigationBar)"))
        XCTAssertTrue(placeProfile.contains(".toolbar(.hidden, for: .navigationBar)"))

        XCTAssertTrue(fullView.contains(".ignoresSafeArea(.container, edges: .top)"))
        XCTAssertTrue(fullView.contains(".overlay(alignment: .top)"))
        XCTAssertTrue(fullView.contains("headerNavigationControls(topInset: headerTopInset)"))
        XCTAssertTrue(navigationControls.contains("Button(action: onBack)"))
        XCTAssertTrue(navigationControls.contains("headerNavigationLabel(systemImage: \"chevron.left\")"))
        XCTAssertTrue(navigationControls.contains("headerNavigationLabel(systemImage: \"square.and.arrow.up\")"))
        XCTAssertTrue(navigationControls.contains(".accessibilityLabel(\"Back\")"))
        XCTAssertTrue(navigationControls.contains(".accessibilityLabel(\"Share place\")"))
        XCTAssertTrue(navigationControls.contains(".padding(.top, topInset)"))
        XCTAssertTrue(fullView.contains(".foregroundStyle(astirBrandMode.primaryText)"))
        XCTAssertTrue(fullView.contains(".astirGlassSurface(cornerRadius: WanderTheme.tapMinimum / 2)"))

        let glassSurface = try sourceSection(
            astir,
            after: "private struct AstirGlassSurface: ViewModifier {",
            before: "extension View {"
        )
        XCTAssertTrue(glassSurface.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(glassSurface.contains(".glassEffect("))
        XCTAssertTrue(glassSurface.contains(".background(.ultraThinMaterial, in: shape)"))
        XCTAssertTrue(glassSurface.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(glassSurface.contains("if reduceTransparency"))
        XCTAssertTrue(glassSurface.contains("selected ? brandMode.accent : brandMode.raisedBackground"))
        XCTAssertTrue(glassSurface.contains("brandMode.prefersDarkInterface"))
        XCTAssertTrue(glassSurface.contains("brandMode.raisedBackground.opacity(0.82)"))
        XCTAssertTrue(glassSurface.contains("@Environment(\\.colorSchemeContrast)"))
        XCTAssertTrue(glassSurface.contains("colorSchemeContrast == .increased"))
    }

    func testSharedGlassAndMapSearchProvideOpaqueReduceTransparencyFallbacks() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertEqual(
            theme.components(separatedBy: "@Environment(\\.accessibilityReduceTransparency)").count - 1,
            3
        )
        XCTAssertTrue(theme.contains("var opaqueFallbackBase: Color"))
        XCTAssertEqual(
            theme.components(separatedBy: ".background(tone.opaqueFallbackBase").count - 1,
            3
        )

        let mapSearchSurface = try sourceSection(
            map,
            after: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier",
            before: "private extension View"
        )
        XCTAssertTrue(mapSearchSurface.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(mapSearchSurface.contains("if reduceTransparency"))
        XCTAssertTrue(mapSearchSurface.contains(".background(astirBrandMode.raisedBackground, in: shape)"))
        XCTAssertTrue(mapSearchSurface.contains("@Environment(\\.colorSchemeContrast)"))
    }

    func testPlaceProfileHeaderOnlyShowsRecMeUserAttribution() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let viewerAttribution = try sourceSection(
            placeProfile,
            after: "private var attributionCard: some View {",
            before: "private func userAttributionCard("
        )
        let mapHeader = try sourceSection(
            placeProfile,
            after: "private struct PlaceProfileMapHeader: View {",
            before: "struct PlaceProfilePhotoImage: View {"
        )
        let headerAttribution = try sourceSection(
            mapHeader,
            after: "private func photoSource(for item: PlacePhotoGalleryItem) -> some View {",
            before: "private var selectedPhoto: PlacePhotoGalleryItem?"
        )

        XCTAssertTrue(viewerAttribution.contains("userAttributionCard(item: selectedItem, contributor: contributor)"))
        XCTAssertFalse(viewerAttribution.contains("googleAttributionCard(photo: selectedItem.photo)"))
        XCTAssertFalse(placeProfile.contains("private func googleAttributionCard"))
        XCTAssertFalse(placeProfile.contains(".accessibilityLabel(\"Open photo in Google Maps\")"))

        XCTAssertTrue(headerAttribution.contains("if let contributor = item.contributor"))
        XCTAssertTrue(headerAttribution.contains("Photo by \\(contributor.displayName)"))
        XCTAssertFalse(headerAttribution.contains("item.isGooglePlacesPhoto"))
        XCTAssertFalse(headerAttribution.contains("PlacePhotoAttribution"))
        XCTAssertFalse(mapHeader.contains("Open Google Maps photo"))
        XCTAssertFalse(placeProfile.contains("private struct PlacePhotoAttribution"))
    }

    func testCheckInAndWannaFlowUsesAstirPlaceNameAndControlRoles() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let saveFlow = try sourceSection(
            mapScreen,
            after: "struct MapPlaceSaveFlowSheet: View",
            before: "private struct MapSaveVisitPhotoSection: View"
        )
        let typography = try XCTUnwrap(
            theme.components(separatedBy: "enum WanderTypography").last?
                .components(separatedBy: "private extension Color").first
        )

        XCTAssertTrue(
            typography.contains(
                "actionScreenTitle = Font.system(.title, design: .default, weight: .bold)"
            )
        )
        XCTAssertTrue(
            saveFlow.contains(
                "Text(droppedPinDisplayName)\n                    .font(AstirTypography.sectionTitle)"
            )
        )
        XCTAssertFalse(saveFlow.contains("WanderTypography.editorial"))
        XCTAssertTrue(saveFlow.contains(".font(AstirTypography.label)"))
        XCTAssertTrue(saveFlow.contains(".font(AstirTypography.metadata)"))
        XCTAssertFalse(saveFlow.contains(".font(.system(size: 28, weight: .black))"))
        XCTAssertFalse(saveFlow.contains(".font(.system(size: 17, weight: .bold))"))
        XCTAssertFalse(saveFlow.contains("WanderTypography.editorialRatingDisplay"))
        XCTAssertFalse(saveFlow.contains("WanderTypography.editorialRatingSuffix"))
    }

    func testAstirTypographyTargetsNamedContentHeadingsAndCustomMastheads() throws {
        let astir = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/AstirVisualSystem.swift")
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

        let typography = try sourceSection(
            astir,
            after: "enum AstirTypography {",
            before: "private struct AstirScreenSurface"
        )
        XCTAssertTrue(typography.contains("screenTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)"))
        XCTAssertTrue(typography.contains("sheetTitle = Font.system(.title2, design: .serif).weight(.semibold)"))
        XCTAssertTrue(typography.contains("sectionTitle = Font.system(.title3, design: .serif).weight(.semibold)"))
        XCTAssertTrue(typography.contains("cardTitle = Font.custom(\"AvenirNext-DemiBold\", size: 16, relativeTo: .body)"))

        XCTAssertTrue(lists.contains("AstirFloatingHeaderSurface {"))
        XCTAssertTrue(lists.contains(".font(AstirTypography.cardTitle)"))
        XCTAssertTrue(lists.contains(".font(AstirTypography.caption)"))
        XCTAssertFalse(lists.contains("WanderTypography.editorial"))
        XCTAssertFalse(lists.contains("save places into a plan you can actually use"))
        XCTAssertFalse(lists.contains("WanderGlassHeader("))

        XCTAssertFalse(discover.contains("WanderTypography.editorialMasthead"))
        XCTAssertFalse(discover.contains("Text(\"Ask for a place the way you'd ask a friend\")"))
        XCTAssertGreaterThanOrEqual(
            discover.components(separatedBy: "AstirTypography.sectionTitle").count - 1,
            2
        )
        XCTAssertGreaterThanOrEqual(
            discover.components(separatedBy: "AstirTypography.cardTitle").count - 1,
            2
        )
        let discoverSearch = try XCTUnwrap(
            discover.components(separatedBy: "private struct DiscoverSearchField: View").last?
                .components(separatedBy: "private struct DiscoverPlaceResultCard: View").first
        )
        XCTAssertTrue(discoverSearch.contains("@State private var draftText"))
        XCTAssertTrue(discoverSearch.contains("TextField(\"\", text: $draftText)\n                    .font(AstirTypography.bodySmall)"))
        XCTAssertTrue(discoverSearch.contains("Task.sleep(for: .milliseconds(80))"))
        XCTAssertFalse(discoverSearch.contains("WanderTypography.editorial"))
        XCTAssertTrue(discoverSearch.contains(".astirOutlinedSurface(castsShadow: true)"))
        XCTAssertFalse(discoverSearch.contains(".background(WanderTheme.surfaceRaised.color)"))

        XCTAssertTrue(profile.contains("Text(profile.displayName)\n                        .font(AstirTypography.sheetTitle)"))
        XCTAssertTrue(profile.contains(".font(AstirTypography.sectionTitle)"))
        XCTAssertFalse(profile.contains("WanderTypography.editorial"))
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
        let ratingExplanation = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/PlaceRatingExplanation.swift")
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

        let ratingsRail = try XCTUnwrap(
            ratingExplanation.components(separatedBy: "struct PlaceProfileRatingsRail: View").last?
                .components(separatedBy: "struct PlaceRatingInfoButton: View").first
        )
        XCTAssertTrue(ratingsRail.contains("WanderTypography.editorialRatingDisplay"))
        XCTAssertTrue(ratingsRail.contains("WanderTypography.editorialRatingSuffix"))
        XCTAssertTrue(ratingsRail.contains("WanderTheme.borderHairline.color"))
        XCTAssertFalse(ratingsRail.contains("WanderTheme.surfaceSand.color"))
        XCTAssertTrue(placeProfile.contains("PlaceProfileRatingsRail(presentation: presentation)"))

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

    func testNotificationSettingsDoNotExposeTheStreakValidationControl() throws {
        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/SettingsScreen.swift"
            )
        )

        XCTAssertTrue(settings.contains("title: \"Save streak reminders\""))
        XCTAssertFalse(settings.contains("send test streak reminder"))
        XCTAssertFalse(settings.contains("settings.notifications.testSaveStreakReminder"))
        XCTAssertFalse(settings.contains("scheduleDebugSaveStreakReminder"))
    }

    func testAppleCalendarPermissionLivesInPrivacySettings() throws {
        let notificationSettingsSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/SettingsScreen.swift"
            )
        )
        let profileSettingsSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/ProfileSettingsViews.swift"
            )
        )

        let notificationSettings = try XCTUnwrap(
            notificationSettingsSource.components(separatedBy: "struct NotificationSettingsSheet: View").last?
                .components(separatedBy: "struct SettingsTrustSurface").first
        )
        let privacySettings = try XCTUnwrap(
            profileSettingsSource.components(separatedBy: "struct ProfilePrivacyTrustScreen: View").last?
                .components(separatedBy: "enum ProfileRelationshipFilter").first
        )

        XCTAssertFalse(notificationSettings.contains("Apple Calendar"))
        XCTAssertFalse(notificationSettings.contains("connect calendar"))
        XCTAssertTrue(notificationSettings.contains("title: \"Reservation check-in reminders\""))

        XCTAssertTrue(privacySettings.contains("Text(\"Permissions\")"))
        XCTAssertTrue(privacySettings.contains("Text(\"Apple Calendar\")"))
        XCTAssertTrue(privacySettings.contains("connectOrSyncCalendar()"))
        XCTAssertTrue(privacySettings.contains("settings.privacy.calendar.action"))
        XCTAssertFalse(privacySettings.contains("NotificationPreferencesUpdate"))
    }

    func testDebugSettingsAreSimulatorOrServerEntitledAndDoNotShipAnIdentityAllowlist() throws {
        let profileSettings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/ProfileSettingsViews.swift"
            )
        )
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let backend = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderBackend.swift")
        )

        XCTAssertTrue(profileSettings.contains("Text(\"Feature flags\")"))
        XCTAssertTrue(profileSettings.contains("DebugSettingsAccessPolicy.isEntitled("))
        XCTAssertTrue(profileSettings.contains("Every Simulator build exposes this local tester surface"))
        XCTAssertTrue(backend.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(backend.contains("isSimulator || serverFlag == true"))
        XCTAssertTrue(profileSettings.contains("ForEach(FeatureFlagKey.allCases"))
        XCTAssertTrue(profileSettings.contains("settings.flags.\\(key.rawValue)"))
        XCTAssertTrue(profileSettings.contains("booleanOverrideBinding(for: key)"))
        XCTAssertTrue(profileSettings.contains("integerFeatureFlagControl(for: key"))
        XCTAssertTrue(profileSettings.contains("Reset all to defaults"))
        XCTAssertTrue(profileSettings.contains("Restart rec.me to apply these changes"))
        XCTAssertTrue(profileSettings.contains("backend.remoteFeatureFlag(.debugSettings"))
        XCTAssertTrue(profileSettings.contains("featureFlagOverrideStore.setOverride"))
        XCTAssertFalse(profileSettings.contains("jolipshutz"))
        XCTAssertFalse(profileSettings.contains("ryan_lieblein"))
        XCTAssertFalse(profileSettings.contains("@gmail.com"))
        XCTAssertTrue(root.contains("FirstVisitWalkthroughDebugReplayPolicy.resolve("))
        XCTAssertTrue(root.contains("debugReplay.shouldPreserveLocalJourney"))
        XCTAssertTrue(root.contains("walkthroughDebugPreferences.clearReplayRequest"))
        XCTAssertFalse(root.contains("onNUXDebugSettingsChanged"))
        XCTAssertTrue(root.contains("@State private var placeProfileFloatingActionVariant"))
        XCTAssertTrue(root.contains("backend.integerFeatureFlag(.placeProfileActionVariant"))
        XCTAssertTrue(root.contains("backend.deviceFeatureFlagOverride(.firstVisitNUX"))
        XCTAssertTrue(root.contains(".environment("))
        XCTAssertTrue(root.contains("\\.placeProfileFloatingActionVariant"))
        XCTAssertTrue(root.contains("placeProfileFloatingActionVariant = .productionDefault"))
        XCTAssertTrue(root.contains("walkthroughDebugPreferenceSnapshot.shouldStartReplay"))
        let foregroundRefresh = try XCTUnwrap(
            root
                .components(separatedBy: "private func refreshWalkthroughFeatureFlagsAfterForeground()")
                .last?
                .components(separatedBy: "private func presentLaunchLessonIfAppropriate()")
                .first
        )
        XCTAssertTrue(
            foregroundRefresh.contains(
                "placeProfileFloatingActionVariant = resolvedPlaceProfileFloatingActionVariant("
            )
        )
    }

    func testAddTabAdvancesToTheCanonicalEditorInsideItsExistingSheet() throws {
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

        XCTAssertTrue(addScreen.contains("private func inlineSaveFlow("))
        XCTAssertTrue(addScreen.contains("MapPlaceSaveEditor("))
        XCTAssertFalse(addScreen.contains("MapPlaceSaveFlowSheet("))
        XCTAssertFalse(addScreen.contains(".sheet(item: $addSaveFlow"))
        XCTAssertTrue(addScreen.contains("return [MapPlaceSaveFlowSheet.compactDetent, .large]"))
        XCTAssertTrue(addScreen.contains("selectedDetent = MapPlaceSaveFlowSheet.compactDetent"))
        XCTAssertTrue(addScreen.contains("contentSwap.disablesAnimations = true"))
        XCTAssertFalse(addScreen.contains(".transition(.opacity)"))
        XCTAssertTrue(addScreen.contains("context: context"))
        XCTAssertTrue(addScreen.contains("persistAddPlaceSaveSubmission("))
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

    func testAddCameraUsesFullScreenCaptureWithRecoverableGalleryHandoff() throws {
        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        let cameraCapture = try sourceSection(
            addScreen,
            after: "private struct AddCameraCaptureScreen: View",
            before: "private enum AddCameraRecoveryState"
        )
        let cameraPickerStart = try XCTUnwrap(
            addScreen.range(of: "private struct AddCameraPicker: UIViewControllerRepresentable")
        )
        let cameraPicker = String(addScreen[cameraPickerStart.lowerBound...])

        XCTAssertTrue(addScreen.contains(".fullScreenCover("))
        XCTAssertTrue(addScreen.contains("item: $cameraPresentation.route"))
        XCTAssertFalse(addScreen.contains(".sheet(isPresented: $showsCamera)"))
        XCTAssertTrue(addScreen.contains("AddCameraCaptureScreen("))
        XCTAssertTrue(cameraCapture.contains("Image(systemName: \"photo.on.rectangle\")"))
        XCTAssertTrue(cameraCapture.contains("Image(systemName: \"arrow.triangle.2.circlepath.camera\")"))
        XCTAssertTrue(cameraCapture.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(cameraCapture.contains("captureRequest += 1"))
        XCTAssertTrue(cameraCapture.contains("GeometryReader { geometry in"))
        XCTAssertTrue(cameraPicker.contains("picker.showsCameraControls = false"))
        XCTAssertTrue(cameraPicker.contains("updatePreviewTransform(on: uiViewController)"))
        XCTAssertTrue(cameraPicker.contains("picker.cameraViewTransform = CGAffineTransform"))
        XCTAssertTrue(cameraPicker.contains("uiViewController.takePicture()"))
        XCTAssertTrue(cameraPicker.contains("uiViewController.cameraDevice = requestedCameraDevice"))
        XCTAssertTrue(addScreen.contains("case .permissionDenied:"))
        XCTAssertTrue(addScreen.contains("case .restricted:"))
        XCTAssertTrue(addScreen.contains("case .unavailable:"))
        XCTAssertTrue(addScreen.contains("handleCameraPresentationDismissal"))
        XCTAssertTrue(addScreen.contains("cameraSessionID == sessionID else { return }"))
        XCTAssertTrue(addScreen.contains("onGallery: switchCameraToPhotoLibrary"))
        XCTAssertTrue(addScreen.contains("onCancel: cancelCameraCapture"))
        XCTAssertTrue(addScreen.contains("cameraPresentation.refreshAuthorization("))
        XCTAssertTrue(addScreen.contains("Task.detached(priority: .userInitiated"))
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
            confirmPlace.components(separatedBy: "title: \"Save\",").count - 1,
            1,
            "The floating and in-flow layouts should share one Save action implementation."
        )
        XCTAssertTrue(confirmPlace.contains("AstirAddPrimaryButton("))
        XCTAssertTrue(confirmPlace.contains("systemImage: \"arrow.right\""))
        XCTAssertFalse(confirmPlace.contains("tone: .espressoConfirmation"))
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
        XCTAssertTrue(importViews.contains("PlaceImportHubScreen("))
        XCTAssertTrue(addScreen.contains("PlaceImportAdaptiveReviewScreen("))
        XCTAssertTrue(addScreen.contains("case .importReview(let batchIDs):"))
        XCTAssertFalse(addScreen.contains("PlaceImportSourceScreen("))
        XCTAssertTrue(addScreen.contains("PlaceImportInboxScreen(importStore: importStore)"))
        XCTAssertTrue(addScreen.contains("emptyRestingHeight: CGFloat = 520"))
        XCTAssertTrue(addScreen.contains("pendingReviewRestingHeight: CGFloat = 570"))
        XCTAssertTrue(addScreen.contains(".presentationDetents(activeSheetDetents, selection: $selectedDetent)"))
        XCTAssertTrue(addScreen.contains("AddSheetLayout.detents("))
        XCTAssertTrue(addScreen.contains(".onChange(of: importStore.summary.hasPendingImports)"))
        XCTAssertTrue(importViews.contains("if summary.hasPendingImports"))
        XCTAssertTrue(importViews.contains("Text(\"Import from\")"))
        XCTAssertTrue(
            importViews.contains(
                "Text(\"Import your places and lists from Google Maps, Instagram, TikTok, and more here\")"
            )
        )
        XCTAssertTrue(
            importViews.contains(
                ".accessibilityLabel(\"Import your places and lists from Google Maps, Instagram, TikTok, and more here\")"
            )
        )
        XCTAssertTrue(importViews.contains("TextField(\"Paste a link…\", text: $input, axis: .vertical)"))
        XCTAssertTrue(
            importViews.contains(
                "Text(\"Paste a link from Instagram, Google Maps, or TikTok\")"
            )
        )
        XCTAssertFalse(importViews.contains("Runs in background"))
        XCTAssertTrue(importViews.contains("Label(\"Paste from clipboard\", systemImage: \"doc.on.clipboard\")"))
        XCTAssertTrue(importViews.contains("enqueueUnified(text: input)"))
        XCTAssertTrue(importViews.contains("completionAction(batchIDs)"))
        XCTAssertFalse(importViews.contains("reviewAction(batchIDs)"))
        XCTAssertTrue(importViews.contains("The primary import experience"))
        XCTAssertTrue(root.contains(".importReview(batchIDs: batchIDs)"))
        XCTAssertTrue(root.contains("completionAction: beginInteractivePlaceImport"))
        XCTAssertTrue(root.contains("selectedTab = .map"))
        XCTAssertTrue(root.contains("PlaceImportCompletionBanner(notice: notice)"))
        XCTAssertTrue(root.contains("notifyImportMatchingFinished("))
        XCTAssertTrue(root.contains("addLaunchRequest = WanderAddLaunchRequest(destination: .importInbox)"))
        XCTAssertTrue(importViews.contains("private let sources: [PlaceImportSource] = [.googleMaps, .instagram, .tiktok]"))
        XCTAssertFalse(importViews.contains("ForEach(PlaceImportSource.allCases)"))
        XCTAssertTrue(importViews.contains("WanderCategoryEmoji("))
        XCTAssertTrue(addScreen.contains("importEntryHeight: CGFloat = 410"))
        XCTAssertTrue(importViews.contains("struct PlaceImportHubOverlay: View"))
        XCTAssertTrue(importViews.contains("bottomLeadingRadius: 0"))
        XCTAssertTrue(importViews.contains(".ignoresSafeArea(.container, edges: [.horizontal, .bottom])"))
        XCTAssertTrue(root.contains("onOpenImportHub: presentImportHub"))
        XCTAssertTrue(addScreen.contains("importCompletionHeight: CGFloat = 710"))
        XCTAssertTrue(importViews.contains("Image(systemName: \"questionmark.circle\")"))
        XCTAssertTrue(importViews.contains("https://getrec.me/import-help"))
        XCTAssertFalse(profileScreen.contains("PlaceImportStore"))
        XCTAssertFalse(profileHome.contains("ImportSection"))
    }

    func testAdaptiveImportReviewUsesSelectableNativeRows() throws {
        let fixtureURL = projectRoot.appendingPathComponent(
            "WanderTests/Fixtures/ios-fix/rec-228-bulk-status-coupling-pre.json"
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let importViews = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileImportViews.swift")
        )
        let adaptiveReview = try XCTUnwrap(
            importViews
                .components(separatedBy: "struct PlaceImportAdaptiveReviewScreen: View")
                .last?
                .components(separatedBy: "private struct PlaceImportSourceIconStack: View")
                .first
        )

        XCTAssertEqual(fixture["issue"] as? String, "REC-228")
        XCTAssertEqual(fixture["pre_fix_bulk_selection"] as? String, "wanna_go")
        XCTAssertEqual(fixture["expected_bulk_selection"] as? String, "neutral_action")
        XCTAssertTrue(adaptiveReview.contains("setIncludedInImport"))
        XCTAssertTrue(adaptiveReview.contains("checkmark.circle.fill"))
        XCTAssertTrue(adaptiveReview.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertTrue(adaptiveReview.contains("selectedReadyItems.first?.stagedStatus"))
        XCTAssertTrue(adaptiveReview.contains("selectedReadyItems.allSatisfy"))
        XCTAssertTrue(adaptiveReview.contains("PlaceImportBulkStatusAction.idleSelectionID"))
        XCTAssertTrue(adaptiveReview.contains("AstirTypography.sectionTitle"))
        XCTAssertTrue(adaptiveReview.contains("WanderPrimaryButton("))
        XCTAssertTrue(adaptiveReview.contains("title: \"Done\""))
        XCTAssertTrue(adaptiveReview.contains("systemImage: \"checkmark\""))
        XCTAssertTrue(adaptiveReview.contains("action: onDone"))
        XCTAssertFalse(adaptiveReview.contains("View on map"))
        XCTAssertTrue(adaptiveReview.contains("let placeItems = activeItems.filter { !$0.isSourceRetry }"))
        XCTAssertTrue(adaptiveReview.contains("let excludedItems = placeItems.filter { !$0.isSelectedForImport }"))
        XCTAssertTrue(adaptiveReview.contains("let items = placeItems.filter(\\.isSelectedForImport)"))
        XCTAssertTrue(adaptiveReview.contains("importStore.dismiss(itemID: item.id)"))
        XCTAssertFalse(adaptiveReview.contains("PlaceImportStatusSelector("))
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
        XCTAssertTrue(importViews.contains("RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)"))
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
        XCTAssertTrue(cardSource.contains(".font(AstirTypography.cardTitle)"))
        XCTAssertTrue(cardSource.contains(".font(AstirTypography.caption)"))
        XCTAssertFalse(cardSource.contains(".font(.system(size:"))
    }

    func testCanonicalSaveDetailsKeepOptionalNoteAboveCollapsedSecondaryQuestions() throws {
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
        XCTAssertTrue(detailsContent.contains("MapCheckInDateSection("))
        XCTAssertTrue(detailsContent.contains("ratingSection"))
        XCTAssertTrue(detailsContent.contains("sharedVisitInviteSection"))
        XCTAssertTrue(detailsContent.contains("MapSaveVisitPhotoSection("))
        XCTAssertTrue(detailsContent.contains("noteSection"))
        XCTAssertTrue(detailsContent.contains("optionalDetailsDisclosure"))
        XCTAssertFalse(detailsContent.contains("questionAndLabelSections"))
        XCTAssertFalse(detailsContent.contains("visibilitySection"))

        XCTAssertFalse(optionalDetails.contains("saveAsSection"))
        XCTAssertFalse(optionalDetails.contains("noteSection"))
        XCTAssertTrue(optionalDetails.contains("questionAndLabelSections"))
        XCTAssertTrue(optionalDetails.contains("visibilitySection"))
        XCTAssertTrue(optionalDetails.contains("fit, tags & privacy"))
        XCTAssertFalse(optionalDetails.contains("date, note"))
        XCTAssertTrue(optionalDetails.contains("walkthroughs.activeSurface == .saveFlow"))
        XCTAssertFalse(optionalDetails.contains("WanderTheme.sunTint.color"))
        XCTAssertTrue(optionalDetails.contains(".walkthroughTarget(.saveMoreOptions)"))
        XCTAssertTrue(optionalDetails.contains("isMoreOptionsArrowPulsing"))
        XCTAssertFalse(optionalDetails.contains(".walkthroughEmphasis(.saveMoreOptions)"))
        XCTAssertFalse(optionalDetails.contains("Circle()\n                                .stroke(WanderTheme.categorySun.color"))
        XCTAssertEqual(
            mapScreen.components(separatedBy: "MapSavePickerBlock(title: \"what do you want to do?\")").count - 1,
            1
        )
        XCTAssertTrue(mapScreen.contains("private var singleScreenContent: some View"))
        XCTAssertTrue(mapScreen.contains("if sourceContext.requiresStatusConfirmation"))
        XCTAssertTrue(mapScreen.contains("if isReadyForDetails"))
        XCTAssertTrue(mapScreen.contains(".accessibilityIdentifier(\"save.statusSelector\")"))
        XCTAssertTrue(mapScreen.contains("private struct MapSaveChoiceButton: View"))
        XCTAssertTrue(mapScreen.contains("HStack(spacing: 0)"))
        XCTAssertTrue(mapScreen.contains(".padding(4)\n                    .astirGlassSurface(cornerRadius: 17)"))
        XCTAssertTrue(mapScreen.contains(".frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)"))
        let statusChoice = try sourceSection(
            mapScreen,
            after: "private struct MapSaveChoiceButton: View",
            before: "private struct MapSaveDestructiveButton: View"
        )
        XCTAssertTrue(statusChoice.contains("VStack(spacing: 0)"))
        XCTAssertTrue(statusChoice.contains(".fill(isSelected ? astirBrandMode.accent : Color.clear)"))
        XCTAssertTrue(statusChoice.contains(".frame(height: 1.5)"))
        XCTAssertFalse(statusChoice.contains(".wanderGlassCapsule("))
        XCTAssertFalse(mapScreen.contains("private struct MapSaveChoicePill: View"))
        XCTAssertTrue(mapScreen.contains("modeDrafts.store(currentModeDraft, for: selectedStatus)"))
        XCTAssertTrue(mapScreen.contains("sourceContext.preselectingStatus(status)"))
        XCTAssertTrue(mapScreen.contains("restoreModeDraft(cachedDraft)"))
        XCTAssertTrue(mapScreen.contains("MapPlaceSaveSubmissionPolicy.checkInValues("))
        XCTAssertTrue(mapScreen.contains("MapPlaceSaveSubmissionPolicy.wannaGoValue("))
        XCTAssertFalse(mapScreen.contains("private var confirmContent: some View"))
        XCTAssertFalse(mapScreen.contains("title: \"continue to details\""))
        XCTAssertFalse(mapScreen.contains("returnToStatusSelection"))
        XCTAssertTrue(mapScreen.contains("walkthroughs.activeSurface != .saveFlow"))
        XCTAssertFalse(mapScreen.contains("Text(flowTitle)"))
        XCTAssertFalse(mapScreen.contains("private var candidateCard: some View"))
        XCTAssertTrue(mapScreen.contains(".accessibilityIdentifier(\"save.placeHeader\")"))
        XCTAssertTrue(mapScreen.contains("CategoryThumb("))
        XCTAssertTrue(mapScreen.contains("Text(candidateSubtitle)"))
        XCTAssertTrue(mapScreen.contains("Spacer(minLength: WanderTheme.spacing1)"))
        XCTAssertTrue(mapScreen.contains("minWidth: WanderTheme.tapMinimum"))
        XCTAssertTrue(mapScreen.contains("minHeight: WanderTheme.tapMinimum"))
        XCTAssertFalse(mapScreen.contains(".frame(width: 32, height: 32)"))
        XCTAssertTrue(mapScreen.contains("@State private var isShowingOptionalDetails = true"))
        XCTAssertFalse(mapScreen.contains("didSelectStatus"))
        XCTAssertTrue(mapScreen.contains(".padding(.top, WanderTheme.spacing1)"))
        XCTAssertTrue(mapScreen.contains("action.displayTitle("))
        XCTAssertTrue(mapScreen.contains("return currentUserSave.userPlace.status == .been ? .addVisit : .reselectWant"))
        XCTAssertTrue(mapScreen.contains(".overlay(alignment: .bottom)"))
        XCTAssertTrue(mapScreen.contains("WanderTheme.spacing16 + WanderTheme.spacing12"))
        XCTAssertTrue(mapScreen.contains(".shadow(color: Color.black.opacity(0.2), radius: 16, y: 8)"))
        XCTAssertFalse(mapScreen.contains("detailsSubtitle"))
        XCTAssertFalse(mapScreen.contains("add a few details"))

        let orderedMarkers = [
            "ratingSection",
            "noteSection",
            "MapCheckInDateSection(",
            "placeTypeSection",
            "visitParticipationSections",
            "optionalDetailsDisclosure"
        ]
        let offsets = try orderedMarkers.map { marker in
            let range = try XCTUnwrap(detailsContent.range(of: marker), "Missing \(marker)")
            return detailsContent.distance(from: detailsContent.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(offsets, offsets.sorted())

        let attachedEssentialMarkers = [
            "ratingSection",
            "noteSection",
            "MapCheckInDateSection(",
            "optionalDetailsDisclosure"
        ]
        let attachedEssentialOffsets = try attachedEssentialMarkers.map { marker in
            let range = try XCTUnwrap(detailsContent.range(of: marker), "Missing \(marker)")
            return detailsContent.distance(from: detailsContent.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(attachedEssentialOffsets, attachedEssentialOffsets.sorted())
        XCTAssertFalse(optionalDetails.contains("presentation == .attached"))
        XCTAssertFalse(optionalDetails.contains("placeTypeSection"))
        XCTAssertFalse(optionalDetails.contains("visitParticipationSections"))

        let optionalMarkers = [
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

    func testEditSaveDeleteActionIsLightweightWithoutChangingRemovalFlow() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let removeSection = try sourceSection(
            mapScreen,
            after: "private var removeSaveSection: some View",
            before: "private var ratingSection: some View"
        )
        let destructiveButton = try sourceSection(
            mapScreen,
            after: "private struct MapSaveDestructiveButton: View",
            before: "private struct PlaceTypeRow: View"
        )
        let removalConfirmation = try sourceSection(
            mapScreen,
            after: ".alert(context.removeConfirmationTitle",
            before: "} message:"
        )

        XCTAssertTrue(removeSection.contains("title: isRemoving ? \"removing...\" : \"delete\""))
        XCTAssertTrue(
            removeSection.contains(
                "accessibilityLabel: isRemoving ? \"removing...\" : context.removeTitle"
            )
        )
        XCTAssertTrue(removeSection.contains("systemImage: \"trash\""))
        XCTAssertTrue(removeSection.contains("isDisabled: isSaving || isRemoving"))
        XCTAssertTrue(removeSection.contains("isShowingRemoveConfirmation = true"))

        XCTAssertTrue(destructiveButton.contains("let action: () -> Void"))
        XCTAssertTrue(destructiveButton.contains("Button(action: action)"))
        XCTAssertTrue(destructiveButton.contains(".font(.system(size: 14, weight: .semibold))"))
        XCTAssertTrue(destructiveButton.contains(".foregroundStyle(WanderTheme.stateError.color)"))
        XCTAssertTrue(
            destructiveButton.contains(
                ".frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)"
            )
        )
        XCTAssertTrue(destructiveButton.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(destructiveButton.contains(".disabled(isDisabled)"))
        XCTAssertTrue(destructiveButton.contains(".accessibilityLabel(accessibilityLabel)"))
        XCTAssertFalse(destructiveButton.contains(".background(WanderTheme.stateError.color)"))
        XCTAssertFalse(destructiveButton.contains(".clipShape(Capsule())"))

        XCTAssertTrue(removalConfirmation.contains("Button(context.removeTitle, role: .destructive)"))
        XCTAssertTrue(removalConfirmation.contains("removeSave()"))
        XCTAssertTrue(mapScreen.contains("Text(context.removeConfirmationMessage)"))
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
        XCTAssertTrue(plannedDateSection.contains("isShowingPlannedDatePicker = false"))
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

        let dateAssignment = try XCTUnwrap(
            plannedDateSection.range(of: "plannedDate = WannaGoDate.singleDate(")
        )
        let collapseAssignment = try XCTUnwrap(
            plannedDateSection.range(of: "isShowingPlannedDatePicker = false")
        )
        XCTAssertLessThan(dateAssignment.lowerBound, collapseAssignment.lowerBound)
    }

    func testRequestedMemberEntryPointsPresentTheFullProfileDetail() throws {
        let presentations = [
            ("Wander/App/WanderRootView.swift", ".fullScreenCover(item: $sharedProfile)"),
            ("Wander/Features/Feed/FeedScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Discover/DiscoverScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Lists/ListsScreen.swift", ".fullScreenCover(isPresented: profileDestinationBinding)"),
            ("Wander/Features/Map/MapScreen.swift", ".fullScreenCover(isPresented: profileDestinationBinding)"),
            ("Wander/Features/Map/PlaceProfileMapSurface.swift", ".fullScreenCover(item: $selectedProfileRoute)"),
            ("Wander/Features/Profile/ProfileScreen.swift", ".fullScreenCover(item: $selectedProfile)"),
            ("Wander/Features/Profile/ProfileSocialGraphScreen.swift", ".fullScreenCover(item: $selectedProfileID)")
        ]

        for (file, presentation) in presentations {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(file))
            XCTAssertTrue(source.contains("ProfileDetailView("), "Missing full member profile destination in \(file)")
            XCTAssertTrue(source.contains(presentation), "Member profile must use a full-screen presentation in \(file)")
        }
    }

    @MainActor
    func testMemberProfileEntryPathsShareInteractiveEdgeBackNavigation() throws {
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Profile/ProfileScreen.swift"
            )
        )
        let detail = try sourceSection(
            profileScreen,
            after: "struct ProfileDetailView: View {",
            before: "private enum GraphListMode"
        )

        XCTAssertTrue(detail.contains(".offset(x: backSwipeOffset)"))
        XCTAssertTrue(detail.contains(".simultaneousGesture(interactiveBackSwipeGesture"))
        XCTAssertTrue(detail.contains("DragGesture(minimumDistance: 8, coordinateSpace: .global)"))
        XCTAssertTrue(detail.contains("guard !hasNestedNavigationDestination"))
        XCTAssertTrue(detail.contains("backSwipeOffset = 0"))
        XCTAssertTrue(detail.contains("backSwipeOffset = containerWidth"))
        XCTAssertTrue(detail.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(detail.contains("backAction: { dismiss() }"))
        XCTAssertTrue(detail.contains("accessibilityLabel: \"Back\""))
    }

    @MainActor
    func testMemberProfileEdgeBackTracksOnlyRightwardHorizontalMotionFromLeftEdge() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                ProfileDetailBackSwipePolicy.interactiveOffset(
                    startX: 12,
                    translation: CGSize(width: 42, height: 8),
                    containerWidth: 390
                )
            ),
            42
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ProfileDetailBackSwipePolicy.interactiveOffset(
                    startX: 12,
                    translation: CGSize(width: 500, height: 4),
                    containerWidth: 390
                )
            ),
            390
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ProfileDetailBackSwipePolicy.interactiveOffset(
                    startX: 12,
                    translation: CGSize(width: -12, height: 0),
                    containerWidth: 390
                )
            ),
            0
        )
        XCTAssertNil(
            ProfileDetailBackSwipePolicy.interactiveOffset(
                startX: 48,
                translation: CGSize(width: 80, height: 4),
                containerWidth: 390
            )
        )
        XCTAssertNil(
            ProfileDetailBackSwipePolicy.interactiveOffset(
                startX: 12,
                translation: CGSize(width: 20, height: 32),
                containerWidth: 390
            )
        )
    }

    @MainActor
    func testMemberProfileEdgeBackCompletesByDistanceOrProjectedVelocityAndCancelsOtherwise() {
        XCTAssertTrue(
            ProfileDetailBackSwipePolicy.shouldComplete(
                startX: 12,
                translation: CGSize(width: 120, height: 8),
                predictedEndTranslation: CGSize(width: 130, height: 10),
                containerWidth: 390
            )
        )
        XCTAssertTrue(
            ProfileDetailBackSwipePolicy.shouldComplete(
                startX: 12,
                translation: CGSize(width: 44, height: 5),
                predictedEndTranslation: CGSize(width: 220, height: 8),
                containerWidth: 390
            )
        )
        XCTAssertFalse(
            ProfileDetailBackSwipePolicy.shouldComplete(
                startX: 12,
                translation: CGSize(width: 44, height: 5),
                predictedEndTranslation: CGSize(width: 180, height: 8),
                containerWidth: 390
            )
        )
        XCTAssertFalse(
            ProfileDetailBackSwipePolicy.shouldComplete(
                startX: 50,
                translation: CGSize(width: 140, height: 4),
                predictedEndTranslation: CGSize(width: 250, height: 5),
                containerWidth: 390
            )
        )
        XCTAssertFalse(
            ProfileDetailBackSwipePolicy.shouldComplete(
                startX: 12,
                translation: CGSize(width: 140, height: 180),
                predictedEndTranslation: CGSize(width: 260, height: 300),
                containerWidth: 390
            )
        )
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
                .components(separatedBy: "private struct MapCheckInDateSection: View")
                .last?
                .components(separatedBy: "struct MapPlaceSaveFlowSheet: View")
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
        XCTAssertTrue(mapScreen.contains("@State private var checkInDateTrayPresentation"))
        XCTAssertTrue(checkInDateSection.contains("@ObservedObject var presentation"))
        XCTAssertTrue(checkInDateSection.contains("presentation.isExpanded.toggle()"))
        XCTAssertTrue(checkInDateSection.contains("presentation.isExpanded = false"))
        XCTAssertTrue(checkInDateSection.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(mapScreen.contains("presentation: checkInDateTrayPresentation"))
        XCTAssertFalse(mapScreen.contains("@State private var isShowingCheckInDatePicker"))
        XCTAssertFalse(checkInDateSection.contains(".datePickerStyle(.compact)"))
        XCTAssertFalse(checkInDateSection.contains(".hourAndMinute"))
        XCTAssertFalse(checkInDateSection.contains("Defaults to now."))
        XCTAssertFalse(checkInDateSection.contains("Pick an earlier date for a past check-in."))

        let dateAssignment = try XCTUnwrap(
            checkInDateSection.range(of: "visitedAt = CheckInDatePickerSelection.resolvedDate(")
        )
        let collapseAssignment = try XCTUnwrap(
            checkInDateSection.range(of: "presentation.isExpanded = false")
        )
        XCTAssertLessThan(dateAssignment.lowerBound, collapseAssignment.lowerBound)
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

    func testOwnProfilePhotoSeparatesFullScreenViewingFromEditingActions() throws {
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let profileHome = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let profileEdit = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileEditScreen.swift")
        )

        XCTAssertTrue(profileScreen.contains("avatarAction: presentProfilePhotoViewer"))
        XCTAssertTrue(profileScreen.contains(".fullScreenCover(isPresented: $showsProfilePhotoViewer)"))
        XCTAssertTrue(profileEdit.contains("Color.black.ignoresSafeArea()"))
        XCTAssertTrue(profileHome.contains("\"View profile photo\""))
        XCTAssertFalse(profileHome.contains("\"Change profile photo\""))

        XCTAssertTrue(profileEdit.contains("showsPhotoMenu = true"))
        XCTAssertTrue(profileEdit.contains(".confirmationDialog(\"Profile photo\""))
        XCTAssertTrue(profileEdit.contains("Button(\"Take Photo\")"))
        XCTAssertTrue(profileEdit.contains("Button(\"Choose from Library\")"))
        XCTAssertTrue(profileEdit.contains("Button(\"Delete Photo\", role: .destructive)"))
        XCTAssertTrue(profileEdit.contains("isPresented: $showsPhotoLibrary"))
        XCTAssertTrue(profileEdit.contains(".sheet(isPresented: $showsCamera)"))
        XCTAssertTrue(profileEdit.contains("Could not load profile photo"))
        XCTAssertFalse(profileEdit.contains("PhotosPicker(selection:"))
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
        XCTAssertEqual(WanderRootView.notificationTab(for: .quickCapture), .map)
        XCTAssertEqual(WanderRootView.notificationTab(for: .profile(id: "profile-1")), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .people(.friends)), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .drafts(extractionJobID: "job-1")), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .list(id: "list-1")), .lists)
        XCTAssertEqual(WanderRootView.notificationTab(for: .listInvite(token: "invite-1")), .lists)
        XCTAssertEqual(WanderRootView.notificationTab(for: .place(id: "place-1")), .map)
        XCTAssertEqual(WanderRootView.notificationTab(for: .activityComments(id: "activity-1")), .discover)
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
    func testStorefrontFixturesArePublicSafeAndExplicitlySelected() {
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander", "-WanderUseDemoFixtures", "-WanderUseStorefrontFixtures"]
            ),
            .storefront
        )
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(from: ["Wander", "-WanderUseDemoFixtures"]),
            .demo
        )
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander"],
                usesSimulatorTestSession: true
            ),
            .demo
        )
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander", "-WanderAuthenticatedUITest", "-WanderUseEphemeralEmptyFixtures"],
                usesSimulatorTestSession: true
            ),
            .ephemeralEmpty
        )
        let ephemeralEmptyFixtures = WanderRootView.resolvedFixtures(mode: .ephemeralEmpty)
        XCTAssertTrue(ephemeralEmptyFixtures.places.isEmpty)
        XCTAssertTrue(ephemeralEmptyFixtures.userPlaces.isEmpty)
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander"],
                usesSimulatorTestSession: false
            ),
            .empty
        )

        let fixtures = WanderFixtures.storefront()
        XCTAssertEqual(fixtures.currentUser.displayName, "Avery")
        XCTAssertEqual(Set(fixtures.profiles.map(\.displayName)), ["Avery", "Mina", "Theo", "June"])
        XCTAssertTrue(fixtures.places.contains { $0.canonicalName == "Hearthline Coffee" })
        XCTAssertTrue(fixtures.placeLists.contains { $0.name == "Mina's sunset walks" })

        let store = WanderStore(fixtures: fixtures)
        let coffeeResults = store.searchTrustedPlaces(query: "coffee", scope: .everyone)
        XCTAssertGreaterThanOrEqual(coffeeResults.places.count, 2)
        XCTAssertTrue(coffeeResults.places.contains { $0.place.canonicalName == "Willow Desk Coffee" })
        XCTAssertTrue(coffeeResults.places.contains { $0.place.canonicalName == "Fern & Found Coffee" })

        let forbiddenVisibleCopy = [
            "Joe", "Maya", "Ryan", "Demo", "Woodcat Coffee", "Griffith Observatory Trail",
            "Larchmont Noodles", "Circuit Coffee", "Bar Nido", "Elysian Picnic Steps",
        ]
        let visibleCopy = fixtures.profiles.flatMap {
            [$0.displayName, $0.handle, $0.bio ?? "", $0.homeArea ?? ""]
        } + fixtures.places.flatMap {
            [$0.canonicalName, $0.address ?? "", $0.websiteURLString ?? "", $0.phoneNumber ?? ""]
        } + fixtures.placeLists.flatMap {
            [$0.name, $0.description]
        }
        for forbidden in forbiddenVisibleCopy {
            XCTAssertFalse(
                visibleCopy.contains { $0.localizedCaseInsensitiveContains(forbidden) },
                "Storefront fixture leaked visible demo copy: \(forbidden)"
            )
        }
    }

    @MainActor
    func testStorefrontFixtureBuildsDenseFriendFeedAfterVenueRenaming() async {
        let store = WanderStore(fixtures: WanderFixtures.storefront())
        _ = await store.refreshFollowedFeed(backend: nil)

        XCTAssertGreaterThanOrEqual(store.followedFeedPage?.activity.count ?? 0, 4)
        let placeNames = store.followedFeedPage?.activity.compactMap {
            $0.place?.place.canonicalName
        } ?? []
        XCTAssertTrue(placeNames.contains("Marigold Table"))
        XCTAssertTrue(placeNames.contains("Lantern Noodles"))
        XCTAssertTrue(placeNames.contains("Fern & Found Coffee"))
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
    func testRootViewCanResolveDarkMapForVisualQA() {
        XCTAssertTrue(
            WanderRootView.resolvedInitialDarkMap(from: ["Wander", "-WanderDarkMap"])
        )
        XCTAssertFalse(WanderRootView.resolvedInitialDarkMap(from: ["Wander"]))
    }

    func testRootAstirColorSchemeAdaptsToSystemWhileDarkMapStaysScopedToTiles() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )

        XCTAssertTrue(root.contains("@Environment(\\.colorScheme) private var systemColorScheme"))
        XCTAssertTrue(root.contains("systemColorScheme == .dark ? .editorial : .editorialLight"))
        XCTAssertTrue(root.contains(".toolbarColorScheme(astirBrandMode.prefersDarkInterface ? .dark : .light, for: .tabBar)"))
        XCTAssertTrue(root.contains(".toolbarBackground(astirBrandMode.background, for: .tabBar)"))
        XCTAssertFalse(root.contains(".preferredColorScheme(.light)"))
        XCTAssertFalse(root.contains(".preferredColorScheme(mapAppearanceColorScheme)"))

        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(
            map.contains("isDark: store.isDarkMapEnabled || astirBrandMode.prefersDarkInterface")
        )
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

    func testListEditorKeepsStealthSectionBelowCollaborators() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let editor = try sourceSection(
            source,
            after: "private struct ListEditorSheet: View",
            before: "private struct ListDestructiveButton: View"
        )
        let form = try sourceSection(
            editor,
            after: "VStack(alignment: .leading, spacing: WanderTheme.spacing6) {",
            before: "                }\n                .padding(WanderTheme.spacing4)"
        )
        let endingLines = form
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        XCTAssertEqual(
            Array(endingLines.suffix(4)),
            [
                "collaboratorsBlock",
                ".id(ListEditorWalkthroughAnchor.collaborators)",
                "stealthToggle",
                ".id(ListEditorWalkthroughAnchor.privacy)"
            ],
            "Collaborators should precede stealth, and stealth should remain the final list-editor section"
        )
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

    func testListMapViewsRespectThePersistedDarkMapSetting() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let preview = try sourceSection(
            source,
            after: "private struct ListMapPreview: View",
            before: "private struct ListMapFullScreen: View"
        )
        let fullScreen = try sourceSection(
            source,
            after: "private struct ListMapFullScreen: View",
            before: "private struct ListMapMarker: View"
        )
        let colorSchemeOverride = "store.isDarkMapEnabled ? ColorScheme.dark : ColorScheme.light"

        XCTAssertTrue(preview.contains("@EnvironmentObject private var store: WanderStore"))
        XCTAssertTrue(preview.contains(colorSchemeOverride))
        XCTAssertTrue(fullScreen.contains("@EnvironmentObject private var store: WanderStore"))
        XCTAssertTrue(fullScreen.contains(colorSchemeOverride))
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
        XCTAssertTrue(fullScreen.contains("focusFromRail(place)"), "A rail swipe should focus the map camera")
        XCTAssertTrue(rail.contains("let onFocus: (ListPlaceMock) -> Void"))
        XCTAssertTrue(rail.contains(".scrollPosition(id: railScrollPositionBinding, anchor: .center)"))
        XCTAssertTrue(rail.contains("onFocus(place)"), "Only rail scroll-position changes should focus the camera")
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
        let detailProjection = try sourceSection(
            source,
            after: "init(list: LocalPlaceList, visiblePlaces: [VisiblePlace], store: WanderStore)",
            before: "@MainActor\nprivate struct ListPlaceProjectionContext"
        )
        let addPlacesScreen = try sourceSection(
            source,
            after: "private struct ListAddPlacesScreen: View",
            before: "private struct ListAddPlacesUnavailableScreen: View"
        )
        let collaboratorSearch = try sourceSection(
            source,
            after: "private struct FriendCollaboratorSearchContent: View",
            before: "private struct ExistingCollaboratorsSummary: View"
        )
        let listEditor = try sourceSection(
            source,
            after: "private struct ListEditorSheet: View",
            before: "private struct ListDestructiveButton: View"
        )

        XCTAssertTrue(activeLists.contains("summary: list"))
        XCTAssertTrue(activeLists.contains("ListPreviewPlaceSelector.distinctPrefix("))
        XCTAssertTrue(activeLists.contains("limit: 4"))
        XCTAssertTrue(activeLists.contains("store.firstVisitPhotosByPlaceID()"))
        XCTAssertTrue(source.contains("let renderedLists = activeLists"))
        XCTAssertTrue(source.contains("listGrid(lists: renderedLists)"))
        XCTAssertTrue(detailScreen.contains("let renderedList = displayList"))
        XCTAssertEqual(detailScreen.components(separatedBy: "let renderedList = displayList").count - 1, 1)
        XCTAssertTrue(detailScreen.contains("Text(\"There are no places added to this list yet.\")"))
        XCTAssertFalse(detailScreen.contains("Loading places in this list."))
        XCTAssertTrue(detailProjection.contains("itemCountOverride: visiblePlaces.count"))
        XCTAssertFalse(detailProjection.contains("itemCountOverride: list.cachedItemCount"))
        XCTAssertTrue(source.contains("@State private var homeProjectionCache"))
        XCTAssertTrue(source.contains("@State private var projectionCache"))
        XCTAssertTrue(detailScreen.contains("LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3)"))
        XCTAssertEqual(addPlacesScreen.components(separatedBy: "LazyVStack(spacing: WanderTheme.spacing2)").count - 1, 2)
        XCTAssertGreaterThanOrEqual(
            collaboratorSearch.components(separatedBy: "LazyVStack(alignment: .leading, spacing: WanderTheme.spacing2)").count - 1,
            2
        )
        XCTAssertTrue(listEditor.contains("LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3)"))
        XCTAssertTrue(richProjection.contains("store.visiblePlaceGroups()"))
        XCTAssertFalse(richProjection.contains("VisiblePlaceGrouping.groups("))
        XCTAssertTrue(richProjection.contains("store.firstVisitPhotosByPlaceID()"))
        XCTAssertFalse(richProjection.contains("store.attributes(for:"))
    }

    func testMapListPickerCachesPresentationAndLazyLoadsRows() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/MapPlaceListPickerSheet.swift")
        )
        let listSection = try sourceSection(
            source,
            after: "private func listSection(title: String, lists: [LocalPlaceList]) -> some View",
            before: "private func listRow(_ list: LocalPlaceList) -> some View"
        )
        let listRow = try sourceSection(
            source,
            after: "private func listRow(_ list: LocalPlaceList) -> some View",
            before: "private func listDetail(_ list: LocalPlaceList) -> String"
        )
        let presentationRefresh = try sourceSection(
            source,
            after: "private func refreshPresentation()",
            before: "@MainActor\n    private func applyPendingLists() async"
        )

        XCTAssertTrue(source.contains("@State private var presentation = MapPlaceListPickerPresentation.empty"))
        XCTAssertTrue(listSection.contains("LazyVStack(spacing: 0)"))
        XCTAssertTrue(listRow.contains("selection.existingListIDs.contains(list.id)"))
        XCTAssertFalse(listRow.contains("target.isAlreadyInList"))
        XCTAssertTrue(presentationRefresh.contains("for list in eligibleLists"))
        XCTAssertTrue(presentationRefresh.contains("target.isAlreadyInList(list, store: store)"))
        XCTAssertTrue(presentationRefresh.contains("detailByListID[list.id] = makeListDetail(list)"))
        XCTAssertTrue(source.contains("if presentation.needsCompanionWanna"))
    }

    func testCollaboratorsLeaveListsFromNativeOverflowConfirmation() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )
        let detailScreen = try sourceSection(
            source,
            after: "private struct ListDetailScreen: View",
            before: "private struct ListSuggestionsSection: View"
        )

        XCTAssertTrue(detailScreen.contains("if canLeaveList"))
        XCTAssertTrue(detailScreen.contains("Menu {"))
        XCTAssertTrue(detailScreen.contains("Button(role: .destructive)"))
        XCTAssertTrue(detailScreen.contains("Label(\"Leave List\""))
        XCTAssertTrue(detailScreen.contains(".alert(\"Leave List?\""))
        XCTAssertTrue(
            detailScreen.contains(
                "Are you sure? You’ll lose collaborator access. You may still see this list in Friends if the owner continues sharing it."
            )
        )
        XCTAssertTrue(detailScreen.contains("sourceList.map(store.canLeave)"))
        XCTAssertTrue(detailScreen.contains(".alert(\"Couldn't leave list\""))
        XCTAssertTrue(detailScreen.contains("Text(\"Try again later\")"))
        XCTAssertFalse(detailScreen.contains("store.lastRemoteError"))
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
        XCTAssertTrue(photoMedia.contains("@Environment(\\.listPhotoAuthorizationScopeKey)"))
        XCTAssertFalse(photoMedia.contains("@EnvironmentObject private var store"))
        XCTAssertFalse(photoMedia.contains("store.follows"))
        XCTAssertFalse(photoMedia.contains("store.blocks"))
        XCTAssertTrue(source.contains("store.listPhotoAuthorizationScopeKey()"))
        XCTAssertTrue(photoMedia.contains("AstirPlacePhotoAsset(stableKey: place.id)"))
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
        XCTAssertEqual(
            WanderRootView.resolvedFixtureMode(
                from: ["Wander"],
                usesSimulatorTestSession: false
            ),
            .empty
        )
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
            MapScreen.resolvedInitialMapFilterState(from: ["Wander"]).source,
            .featured
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilterState(
                defaultSource: .friends,
                from: ["Wander"]
            ).source,
            .friends
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilterState(
                defaultSource: .featured,
                from: ["Wander", "-WanderMapCaptureMode", "friends"]
            ).source,
            .friends
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilterState(
                defaultSource: .friends,
                from: ["Wander", "-WanderMapCaptureMode", "featured"]
            ).source,
            .featured
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilterState(
                defaultSource: .featured,
                from: ["Wander", "-WanderMapCaptureMode", "you"]
            ).source,
            .you
        )
        XCTAssertEqual(
            MapScreen.resolvedInitialMapFilterState(from: ["Wander", "-WanderMapCaptureMode", "trusted"]).source,
            .featured
        )
        XCTAssertTrue(
            MapScreen.resolvedInitialMoreFiltersPresentation(from: ["Wander", "-WanderMapMoreFiltersOpen"])
        )
        XCTAssertFalse(MapScreen.resolvedInitialMoreFiltersPresentation(from: ["Wander"]))
    }

    func testProfileSettingsExposePersistedDefaultMapFilterSelector() throws {
        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/ProfileSettingsViews.swift"
            )
        )

        XCTAssertTrue(settings.contains("Label(\"Default map filter\", systemImage: \"map\")"))
        XCTAssertTrue(settings.contains("DefaultMapFilterSettingsScreen()"))
        XCTAssertTrue(settings.contains("ForEach(MapSource.allCases)"))
        XCTAssertTrue(settings.contains("Text(source.subtitle)"))
        XCTAssertTrue(settings.contains("store.defaultMapFilter = source"))
        XCTAssertTrue(settings.contains("settings.map.defaultFilter"))
        XCTAssertTrue(settings.contains("Used whenever the map opens or resets on this device."))
    }

    func testProfileSettingsUseBrandTintProfileBackedOverlayAndRequestedHierarchy() throws {
        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/ProfileSettingsViews.swift"
            )
        )
        let legacySettings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Settings/SettingsScreen.swift"
            )
        )
        let profileMockups = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Profile/ProfileRedesignMockups.swift"
            )
        )
        let profile = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Profile/ProfileScreen.swift"
            )
        )
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let authGate = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Auth/AuthGateSheet.swift"
            )
        )

        XCTAssertFalse(profile.contains(".navigationDestination(isPresented: $showsSettings)"))
        XCTAssertTrue(profile.contains("if showsSettings {"))
        XCTAssertTrue(profile.contains("SettingsScreen(onDismiss: dismissSettings)"))
        XCTAssertTrue(profile.contains(".accessibilityHidden(showsSettings)"))
        XCTAssertTrue(profile.contains(".allowsHitTesting(!showsSettings)"))
        XCTAssertTrue(profile.contains(".transition(.move(edge: .trailing))"))
        XCTAssertTrue(profile.contains(".toolbar(showsSettings ? .hidden : .visible, for: .tabBar)"))
        XCTAssertTrue(profile.contains("onSettingsDidDismiss()"))
        XCTAssertTrue(root.contains("NavigationStack {\n                        SettingsScreen("))

        XCTAssertTrue(settings.contains(".tint(brandMode.accent)"))
        XCTAssertTrue(settings.contains("Text(\"Settings\")"))
        XCTAssertTrue(settings.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertFalse(settings.contains(".toolbar(.hidden, for: .tabBar)"))
        XCTAssertTrue(settings.contains("Image(systemName: \"chevron.left\")"))
        XCTAssertTrue(settings.contains(".accessibilityLabel(\"Back\")"))
        XCTAssertFalse(settings.contains("Button(\"done\")"))
        XCTAssertTrue(settings.contains("DragGesture(minimumDistance: 8, coordinateSpace: .global)"))
        XCTAssertTrue(settings.contains("value.startLocation.x <= 28"))
        XCTAssertTrue(settings.contains("settingsDragOffset = value.translation.width"))
        XCTAssertTrue(settings.contains("settingsDragOffset = containerWidth"))
        XCTAssertTrue(settings.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(settings.contains("if let onDismiss"))

        let header = try XCTUnwrap(
            settings.components(separatedBy: "private var settingsHeader").last?
                .components(separatedBy: "private var settingsList").first
        )
        XCTAssertLessThan(
            try XCTUnwrap(header.range(of: "Button(action: closeSettings)")).lowerBound,
            try XCTUnwrap(header.range(of: "Text(\"Settings\")")).lowerBound
        )

        XCTAssertTrue(settings.contains("Section(\"Account\")"))
        XCTAssertTrue(settings.contains("Section(\"Privacy and safety\")"))
        XCTAssertTrue(settings.contains("Section(\"Notifications\")"))
        XCTAssertFalse(settings.contains("Section(\"App\")"))
        XCTAssertTrue(settings.contains("Section(\"Account actions\")"))
        XCTAssertTrue(settings.contains("Label(\"Resources\", systemImage: \"books.vertical\")"))

        let list = try XCTUnwrap(
            settings.components(separatedBy: "private var settingsList").last?
                .components(separatedBy: "private func interactiveDismissGesture").first
        )
        XCTAssertLessThan(
            try XCTUnwrap(list.range(of: "notificationsSection")).lowerBound,
            try XCTUnwrap(list.range(of: "privacySection")).lowerBound
        )

        let actions = try XCTUnwrap(
            settings.components(separatedBy: "private var accountActionsSection").last?
                .components(separatedBy: "private var resourcesSection").first
        )
        XCTAssertLessThan(
            try XCTUnwrap(actions.range(of: "\"Sign out\"")).lowerBound,
            try XCTUnwrap(actions.range(of: "\"Delete my account\"")).lowerBound
        )
        XCTAssertTrue(actions.contains("icon: \"trash\""))
        XCTAssertTrue(actions.contains("color: .red"))
        XCTAssertTrue(settings.contains(".font(.system(size: 16, weight: .regular))"))

        let privacy = try XCTUnwrap(
            settings.components(separatedBy: "private var privacySection").last?
                .components(separatedBy: "private var mapSection").first
        )
        XCTAssertLessThan(
            try XCTUnwrap(privacy.range(of: "Blocked and muted accounts")).lowerBound,
            try XCTUnwrap(privacy.range(of: "Privacy choices")).lowerBound
        )

        let resources = try XCTUnwrap(
            settings.components(separatedBy: "private struct SettingsResourcesScreen").last?
                .components(separatedBy: "private enum RecmeSettingsWebDestination").first
        )
        for title in [
            "Import help",
            "Help and support",
            "Privacy policy",
            "Terms of use",
            "Community guidelines"
        ] {
            XCTAssertTrue(resources.contains("title: \"\(title)\""))
        }
        XCTAssertFalse(resources.contains("Privacy choices"))

        XCTAssertFalse(settings.localizedCaseInsensitiveContains("data and sync"))
        XCTAssertFalse(legacySettings.localizedCaseInsensitiveContains("data and sync"))
        XCTAssertFalse(profileMockups.localizedCaseInsensitiveContains("data & sync"))
        XCTAssertTrue(settings.contains("ProfileSettingsAccountActions(session: session)"))
        XCTAssertTrue(settings.contains("showsAccountManagement = true"))
        XCTAssertTrue(settings.contains(".sheet(isPresented: $showsAccountManagement)"))
        XCTAssertTrue(settings.contains("ClerkAccountManagementView()"))
        XCTAssertTrue(authGate.contains("struct ClerkAccountManagementView: View"))
        XCTAssertTrue(authGate.contains("UserProfileView()"))
        XCTAssertTrue(authGate.contains(".environment(Clerk.shared)"))
        XCTAssertTrue(settings.contains("title: \"Change email\""))
        XCTAssertTrue(settings.contains("title: \"Change phone number\""))
        XCTAssertTrue(settings.contains("title: \"Change password\""))
        XCTAssertTrue(settings.contains("Button(action: onSelect)"))
        XCTAssertTrue(settings.contains("HStack(spacing: 0)"))
        XCTAssertTrue(settings.contains("Divider()"))
        XCTAssertTrue(settings.contains(".overlay(brandMode.border)"))
        XCTAssertTrue(settings.contains(".multilineTextAlignment(.center)"))
        XCTAssertTrue(settings.contains("Text(emailAddress)"))
        XCTAssertTrue(settings.contains("Text(phoneNumber)"))
        XCTAssertTrue(settings.contains(".font(AstirTypography.caption)"))
        XCTAssertTrue(settings.contains(".truncationMode(.tail)"))
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
        XCTAssertTrue(initialSelection.contains("store.visiblePlaces().first"))
        XCTAssertTrue(initialSelection.contains("routedVisiblePlace = initialPlace"))
        XCTAssertTrue(initialSelection.contains("centerCompactSelection(on: initialPlace)"))
        XCTAssertFalse(initialSelection.contains("center(on: initialPlace)"))
        XCTAssertFalse(initialSelection.contains("firstVisiblePlace"))
        XCTAssertFalse(source.contains("centerMapOnInitialPlacesIfNeeded"))
    }

    func testMapPlaceProfileSlidesTheEntireNavigationSurfaceUpFromTheBottom() throws {
        let mapScreen = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift"))
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )

        XCTAssertFalse(mapScreen.contains(".fullScreenCover(isPresented: placeProfileDestinationBinding)"))
        XCTAssertTrue(mapScreen.contains("PlaceProfileVerticalContainer"))
        XCTAssertTrue(mapScreen.contains("NavigationStack {\n                    selectedPlaceProfileDestination"))
        XCTAssertTrue(mapScreen.contains(".overlay {\n            selectedPlaceProfileOverlay"))
        XCTAssertTrue(mapScreen.contains(".allowsHitTesting(!isPlaceProfileOverlayBlockingInteraction)"))
        XCTAssertTrue(mapScreen.contains(".accessibilityHidden(isPlaceProfileOverlayBlockingInteraction)"))
        XCTAssertTrue(mapScreen.contains("if isPlaceProfileMounted && hasSelectedProfile {"))
        XCTAssertTrue(mapScreen.contains("hasSelectedProfile && (isPlaceProfilePresented || placeProfileDismissalID != nil)"))
        XCTAssertTrue(mapScreen.contains(".onChange(of: hasSelectedProfile)"))
        XCTAssertTrue(mapScreen.contains("isPlaceProfilePresented = false"))
        XCTAssertTrue(mapScreen.contains("placeProfileDismissalID = nil"))
        XCTAssertTrue(mapScreen.contains(".accessibilityAddTraits(.isModal)"))
        XCTAssertTrue(mapScreen.contains(".accessibilityAction(.escape)"))
        XCTAssertTrue(mapScreen.contains("guard walkthroughs.activeSurface != .placeDetail else { return }"))
        XCTAssertTrue(mapScreen.contains("onTransitionCompleted: handlePlaceProfileTransitionCompleted"))
        XCTAssertTrue(mapScreen.contains("finishPlaceProfileDismissal(id: dismissalID)"))
        XCTAssertTrue(mapScreen.contains(".accessibilityHidden(!isPlaceProfilePresented)"))
        XCTAssertTrue(mapScreen.contains("mountTransaction.disablesAnimations = true"))
        XCTAssertTrue(mapScreen.contains("preloadSelectedPlaceProfile(for: identity)"))
        XCTAssertTrue(mapScreen.contains("setPlaceProfilePresentedWithoutSwiftUIAnimation(true)"))
        XCTAssertTrue(mapScreen.contains("setPlaceProfilePresentedWithoutSwiftUIAnimation(false)"))
        XCTAssertTrue(mapScreen.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertTrue(mapScreen.contains("usesInteractiveHorizontalDismissal: true"))
        XCTAssertFalse(mapScreen.contains("@State private var placeProfileHorizontalOffset"))
        XCTAssertFalse(mapScreen.contains(".offset(x: placeProfileHorizontalOffset)"))

        XCTAssertTrue(placeProfile.contains("struct PlaceProfileVerticalContainer<Content: View>: UIViewControllerRepresentable"))
        XCTAssertTrue(placeProfile.contains("let isPresented: Bool"))
        XCTAssertTrue(placeProfile.contains("let content: Content"))
        XCTAssertTrue(placeProfile.contains("onTransitionCompleted: onTransitionCompleted"))
        XCTAssertTrue(placeProfile.contains("controller.setPresented(isPresented, animated: !reduceMotion)"))
        XCTAssertTrue(placeProfile.contains("controller.updateRootView(content)"))
        XCTAssertTrue(placeProfile.contains("UIHostingController<Content>"))
        XCTAssertTrue(placeProfile.contains("UIViewPropertyAnimator("))
        XCTAssertTrue(placeProfile.contains("hostingController.view.transform = targetTransform(isPresented: isPresented)"))
        XCTAssertTrue(placeProfile.contains("hostingController.view.layer.shouldRasterize = isEnabled"))
        XCTAssertTrue(placeProfile.contains("hostingController.view.removeFromSuperview()"))
        XCTAssertTrue(placeProfile.contains("view.accessibilityElementsHidden = !isPresented"))
        XCTAssertFalse(placeProfile.contains("struct PlaceProfileSlideContainer<Content: View>: View"))
        XCTAssertFalse(placeProfile.contains("@State private var horizontalOffset: CGFloat = 0"))
        XCTAssertFalse(placeProfile.contains(".offset(x: horizontalOffset)"))
        XCTAssertTrue(placeProfile.contains("if usesInteractiveHorizontalDismissal {\n                profileContent"))
        XCTAssertFalse(placeProfile.contains(".simultaneousGesture(edgeSwipeGesture(containerWidth: proxy.size.width))"))
        XCTAssertTrue(placeProfile.contains(".toolbar(.hidden, for: .navigationBar)"))
    }

    @MainActor
    func testPlacePreviewCardPressSessionAcceptsTheInitialQuickTap() {
        let session = PlaceProfilePreviewCardPressSession()

        XCTAssertEqual(session.finish(at: 10), 0)
        XCTAssertTrue(
            PlaceProfilePreviewCardPressPolicy.shouldOpen(
                actionInProgress: false,
                duration: 0,
                translation: 0
            )
        )

        session.beginIfNeeded(at: 10)
        XCTAssertEqual(session.finish(at: 10.8), 0.8, accuracy: 0.001)
        XCTAssertFalse(
            PlaceProfilePreviewCardPressPolicy.shouldOpen(
                actionInProgress: false,
                duration: 0.8,
                translation: 0
            )
        )

        session.beginIfNeeded(at: 12)
        session.beginIfNeeded(at: 13)
        session.cancel()
        XCTAssertEqual(session.finish(at: 20), 0)

        XCTAssertFalse(
            PlaceProfilePreviewCardPressPolicy.shouldOpen(
                actionInProgress: true,
                duration: 0,
                translation: 0
            )
        )
        XCTAssertFalse(
            PlaceProfilePreviewCardPressPolicy.shouldOpen(
                actionInProgress: false,
                duration: PlaceProfilePreviewCardPressPolicy.maximumDuration,
                translation: 0
            )
        )
        XCTAssertFalse(
            PlaceProfilePreviewCardPressPolicy.shouldOpen(
                actionInProgress: false,
                duration: 0,
                translation: PlaceProfilePreviewCardPressPolicy.maximumTranslation
            )
        )
    }

    @MainActor
    func testPlaceProfileSlidingHostingControllerAttachesAndDetachesWithoutAnimation() {
        var completedStates: [Bool] = []
        let controller = PlaceProfileSlidingHostingController(
            rootView: Text("Profile"),
            isPresented: false,
            onTransitionCompleted: { completedStates.append($0) }
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        guard let hostedView = controller.view.subviews.first else {
            XCTFail("Expected the hosted profile view to be attached")
            return
        }

        XCTAssertTrue(controller.view.accessibilityElementsHidden)
        XCTAssertNotEqual(hostedView.transform, CGAffineTransform.identity)

        controller.setPresented(true, animated: false)

        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(hostedView.transform, CGAffineTransform.identity)
        XCTAssertFalse(controller.view.accessibilityElementsHidden)
        XCTAssertEqual(completedStates, [true])

        controller.setPresented(false, animated: false)

        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(controller.view.accessibilityElementsHidden)
        XCTAssertNil(hostedView.superview)
        XCTAssertEqual(completedStates, [true, false])
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
        XCTAssertTrue(discoverScreen.contains(".sheet(item: $listSelectionPlace"))
        XCTAssertTrue(discoverScreen.contains("MapPlaceListPickerSheet("))
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
        XCTAssertTrue(source.contains(".onSubmit {"))
        XCTAssertTrue(source.contains("onSubmit()"))
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
        XCTAssertTrue(source.contains("private func clearPlaceSearch(focusField: Bool = true)"))
        XCTAssertTrue(source.contains("placeSearchTask?.cancel()"))
        XCTAssertTrue(source.contains("communityPlaceSearchTask?.cancel()"))
        XCTAssertTrue(source.contains("startCommunityPlaceSearch(query: query, submissionID: submissionID)"))
        XCTAssertTrue(source.contains("backend.searchRecmePlaces("))
        XCTAssertTrue(source.contains("includesSemanticProvider: semanticEnabled"))
        XCTAssertTrue(source.contains("backend.featureFlag(.semanticPlaceSearchV1"))
        XCTAssertTrue(source.contains("SemanticPlaceSearchAccessPolicy.isEnabled("))
        XCTAssertTrue(source.contains("Saved on rec.me"))
        XCTAssertTrue(source.contains("activePlaceSearchSubmissionID == submissionID"))
        XCTAssertTrue(source.contains("Try a search"))
        XCTAssertTrue(source.contains("coffee worth crossing town for"))
        XCTAssertTrue(source.contains("quiet cafes with wifi"))
        XCTAssertTrue(source.contains("Understood as"))
        XCTAssertTrue(source.contains("evidence.summary"))
        XCTAssertTrue(source.contains("Search visited instead"))
        XCTAssertTrue(source.contains("Nothing was broadened automatically"))
        XCTAssertTrue(feedSource.contains("startsInPlaceSearch: true"))
        XCTAssertTrue(feedSource.contains("onClose: closeDiscoverSearch"))
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
            after: ".task(id: store.presentationRevision)",
            before: ".navigationDestination"
        )

        XCTAssertTrue(authRefresh.contains("previousAuthState != requestedAuthState"))
        XCTAssertTrue(authRefresh.contains("await refreshPlaces(query: placesQuery)"))
        XCTAssertTrue(authRefresh.contains("startCommunityPlaceSearch("))
        XCTAssertTrue(authRefresh.contains("await refreshMembers(query: memberQuery)"))
        XCTAssertTrue(authRefresh.contains("guard !Task.isCancelled"))
        XCTAssertTrue(visibleDataRefresh.contains("await refreshPlaces(query: placesQuery)"))
        XCTAssertTrue(visibleDataRefresh.contains("await refreshMembers(query: memberQuery)"))
        XCTAssertTrue(visibleDataRefresh.contains("guard !Task.isCancelled"))
        XCTAssertFalse(source.contains("visiblePlaceSignature"))
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
    func testPlaceProfileInteractiveEdgeSwipeTracksOnlyRightwardHorizontalMotion() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                    startX: 12,
                    translation: CGSize(width: 42, height: 8),
                    containerWidth: 390
                )
            ),
            42
        )
        XCTAssertEqual(
            try XCTUnwrap(
                PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                    startX: 12,
                    translation: CGSize(width: 500, height: 4),
                    containerWidth: 390
                )
            ),
            390
        )
        XCTAssertEqual(
            try XCTUnwrap(
                PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                    startX: 12,
                    translation: CGSize(width: -12, height: 0),
                    containerWidth: 390
                )
            ),
            0
        )
        XCTAssertNil(
            PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                startX: 48,
                translation: CGSize(width: 80, height: 4),
                containerWidth: 390
            )
        )
        XCTAssertNil(
            PlaceProfileFullScreen.interactiveEdgeSwipeOffset(
                startX: 12,
                translation: CGSize(width: 20, height: 32),
                containerWidth: 390
            )
        )
    }

    @MainActor
    func testPlaceProfileInteractiveEdgeSwipeCompletesByDistanceOrProjectedVelocity() {
        XCTAssertTrue(
            PlaceProfileFullScreen.shouldCompleteInteractiveEdgeSwipe(
                startX: 12,
                translation: CGSize(width: 96, height: 8),
                predictedEndTranslation: CGSize(width: 110, height: 10)
            )
        )
        XCTAssertTrue(
            PlaceProfileFullScreen.shouldCompleteInteractiveEdgeSwipe(
                startX: 12,
                translation: CGSize(width: 44, height: 5),
                predictedEndTranslation: CGSize(width: 190, height: 8)
            )
        )
        XCTAssertFalse(
            PlaceProfileFullScreen.shouldCompleteInteractiveEdgeSwipe(
                startX: 12,
                translation: CGSize(width: 44, height: 5),
                predictedEndTranslation: CGSize(width: 100, height: 8)
            )
        )
        XCTAssertFalse(
            PlaceProfileFullScreen.shouldCompleteInteractiveEdgeSwipe(
                startX: 50,
                translation: CGSize(width: 120, height: 4),
                predictedEndTranslation: CGSize(width: 200, height: 5)
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
    func testPlaceProfileFullViewUsesCompactBottomSpacing() {
        XCTAssertEqual(
            PlaceProfileFullScreen.fullViewBottomContentInset,
            16
        )
    }

    func testFullPagePlaceViewOmitsRedundantPlaceDetailsCard() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )

        XCTAssertFalse(placeProfile.contains("Place details"))
        XCTAssertFalse(placeProfile.contains("PlaceProfileDetailRow"))
        XCTAssertFalse(placeProfile.contains("Map/business search details"))
    }

    func testFullPagePlaceViewOmitsFitRationaleContent() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let fullView = try sourceSection(
            placeProfile,
            after: "private struct PlaceProfileFullView: View {",
            before: "struct PlaceProfileFloatingActions: View {"
        )

        XCTAssertFalse(fullView.contains("fitSentence"))
        XCTAssertFalse(fullView.contains("whyItFitsSection"))
        XCTAssertFalse(fullView.contains("Why it fits"))
        XCTAssertFalse(fullView.contains("Strong fit based on your check-ins"))
        XCTAssertTrue(fullView.contains("bestForSection"))
        XCTAssertTrue(fullView.contains("PlaceActivitySection"))
    }

    func testPhotoSurfacesRequestTheirCrispDeliveryTiers() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Map/PlaceProfileMapSurface.swift"
            )
        )
        let lists = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Lists/ListPlacePhotoResolver.swift"
            )
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Feed/FeedScreen.swift"
            )
        )
        let imports = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Profile/ProfileImportViews.swift"
            )
        )

        XCTAssertTrue(placeProfile.contains("place.photoRequest.rendering(.card)"))
        XCTAssertTrue(placeProfile.contains("variant: .card"))
        XCTAssertTrue(placeProfile.contains("place.photoRequest.rendering(.profile)"))
        XCTAssertTrue(placeProfile.contains("variant: .profile"))
        XCTAssertTrue(placeProfile.contains("variant: .fullscreen"))
        XCTAssertTrue(lists.contains("request.rendering(.listThumbnail)"))
        XCTAssertTrue(lists.contains("variant: .listThumbnail"))
        XCTAssertTrue(feed.contains("sheetPlace.photoRequest.rendering(.feed)"))
        XCTAssertTrue(feed.contains("variant: .feed"))
        XCTAssertTrue(imports.contains("request.rendering(.listThumbnail)"))
        XCTAssertTrue(imports.contains("variant: .listThumbnail"))
    }

    func testPlaceProfileActionsKeepTheStandardRailAndExposeEveryWalkthroughAction() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let actionRow = try sourceSection(
            placeProfile,
            after: "private var actionRow: some View {",
            before: "private var primaryPlaceAction: some View {"
        )

        XCTAssertTrue(actionRow.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertTrue(actionRow.contains("HStack(spacing: WanderTheme.spacing2)"))
        XCTAssertTrue(actionRow.contains(".frame(width: 136, height: 48)"))
        XCTAssertTrue(actionRow.contains(".astirOutlinedSurface()"))
        XCTAssertTrue(actionRow.contains(".padding(.horizontal, -WanderTheme.spacing4)"))
        XCTAssertTrue(actionRow.contains("walkthroughs.activeSurface == .placeDetail"))
        XCTAssertTrue(actionRow.contains("walkthroughActionButton(item)"))
        XCTAssertTrue(actionRow.contains(".frame(maxWidth: .infinity, minHeight: 56)"))
        XCTAssertTrue(actionRow.contains("VStack(spacing: 3)"))
        XCTAssertTrue(actionRow.contains("minimumScaleFactor(0.68)"))
    }

    func testFlaggedPlaceProfileUsesSafeAreaFloatingActionsWithoutRemovingLegacyFallback() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let fullView = try sourceSection(
            placeProfile,
            after: "private struct PlaceProfileFullView: View {",
            before: "struct PlaceProfileFloatingActions: View {"
        )
        let floatingActions = try sourceSection(
            placeProfile,
            after: "struct PlaceProfileFloatingActions: View {",
            before: "private struct PlacePhotoGalleryViewerRoute: Identifiable"
        )

        XCTAssertTrue(fullView.contains("if !usesFloatingActions, action != .none"))
        XCTAssertTrue(fullView.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(fullView.contains("if attachedSaveContext == nil, usesFloatingActions, !floatingActions.isEmpty"))
        XCTAssertTrue(fullView.contains("saveActionSnapshot?.usesFloatingActions == true"))
        XCTAssertTrue(fullView.contains("saveActionSnapshot?.presentation.actions ?? []"))
        XCTAssertTrue(fullView.contains("variant: floatingActionVariant"))
        XCTAssertTrue(placeProfile.contains("@State private var saveActionSnapshot: PlaceProfileSaveActionSnapshot?"))
        XCTAssertTrue(placeProfile.contains("_saveActionSnapshot = State(initialValue: saveActionSnapshot)"))
        XCTAssertTrue(fullView.contains("@Environment(\\.placeProfileFloatingActionVariant)"))
        XCTAssertFalse(fullView.contains("PlaceProfileFloatingActionDebugPreferences()"))
        XCTAssertTrue(placeProfile.contains("case option5 = 5"))
        XCTAssertTrue(floatingActions.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(floatingActions.contains(".frame(maxWidth: .infinity, minHeight: Self.minimumActionHeight)"))
        XCTAssertTrue(floatingActions.contains("PlaceProfileActionClusterSurface(isAstir: visualStyle == .astir)"))
        XCTAssertTrue(floatingActions.contains("content.astirGlassSurface(cornerRadius: 22, castsShadow: true)"))
        XCTAssertTrue(floatingActions.contains("content.astirOutlinedSurface(selected: isSelected)"))
        XCTAssertTrue(floatingActions.contains(".wanderGlassRoundedRectangle("))
        XCTAssertTrue(floatingActions.contains("tone: Self.glassTone(for: action, variant: variant)"))
        XCTAssertTrue(floatingActions.contains("interactive: false"))
        XCTAssertTrue(floatingActions.contains("showsBorder: true"))
        XCTAssertTrue(floatingActions.contains("case .option5:"))
        XCTAssertTrue(floatingActions.contains(".deepBlackAction"))
        XCTAssertTrue(floatingActions.contains("private var clusteredActionLayout: some View"))
        XCTAssertTrue(floatingActions.contains("WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing2)"))
        XCTAssertTrue(floatingActions.contains("tone: tone"))
        XCTAssertTrue(floatingActions.contains("static let compactActionHeight: CGFloat = 60"))
        XCTAssertTrue(floatingActions.contains("static let compactActionFrameWidth: CGFloat = 124"))
        XCTAssertTrue(floatingActions.contains("static let accessibilityCompactActionFrameWidth: CGFloat = 280"))
        XCTAssertTrue(floatingActions.contains("variant: PlaceProfileFloatingActionVariant = .resolved()"))
        XCTAssertTrue(placeProfile.contains("#if DEBUG"))
        XCTAssertTrue(placeProfile.contains("-WanderPlaceActionVariant"))
        XCTAssertFalse(floatingActions.contains(".background(WanderTheme.surfaceBone.color)"))
        XCTAssertFalse(floatingActions.contains("RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)"))
        XCTAssertTrue(floatingActions.contains(".accessibilityLabel(action.title)"))
        XCTAssertTrue(floatingActions.contains(".accessibilityAddTraits(action.isSelected ? .isSelected : [])"))

        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        XCTAssertTrue(theme.contains("case blackAction"))
        XCTAssertTrue(theme.contains("case deepBlackAction"))
        XCTAssertTrue(theme.contains("case lightAction"))
        XCTAssertTrue(theme.contains("Color.white.opacity(0.56)"))
        XCTAssertTrue(theme.contains("func wanderGlassRoundedRectangle("))
        XCTAssertTrue(theme.contains("let glass: Glass = material == .clear ? .clear : .regular"))
        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(theme.contains(".glassEffect("))
        XCTAssertTrue(theme.contains(".background(.ultraThinMaterial, in: shape)"))

        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(mapScreen.contains("saveActionSnapshot: saveActionSnapshot("))
        XCTAssertTrue(mapScreen.contains("onFloatingAction: { saveAction in"))
        XCTAssertTrue(mapScreen.contains("handleFloatingAction(saveAction, for: selectedPlace)"))
        XCTAssertTrue(mapScreen.contains(".preselectingStatus(status)"))
        XCTAssertTrue(mapScreen.contains("resolvedFlagValue: backend.featureFlag("))
        XCTAssertTrue(mapScreen.contains(".placeProfileSaveTrayV1"))
    }

    func testPlaceSaveConfirmationCTAsUseAstirBrandAcrossPrimaryFlows() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        let importViews = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileImportViews.swift")
        )
        let loggedOut = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Onboarding/LoggedOutCarouselView.swift")
        )
        let authGate = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Auth/AuthGateSheet.swift")
        )
        let mapEditor = try XCTUnwrap(
            mapScreen
                .components(separatedBy: "struct MapPlaceSaveEditor: View")
                .last?
                .components(separatedBy: "private struct MapSaveVisitPhotoSection: View")
                .first
        )
        let adaptiveImport = try XCTUnwrap(
            importViews
                .components(separatedBy: "struct PlaceImportAdaptiveReviewScreen: View")
                .last?
                .components(separatedBy: "private struct PlaceImportSourceIconStack: View")
                .first
        )
        XCTAssertTrue(theme.contains("case espressoConfirmation"))
        XCTAssertTrue(theme.contains("case solidBlackConfirmation"))
        XCTAssertTrue(theme.contains("private struct WanderPrimaryButtonPressStyle: ButtonStyle"))
        XCTAssertTrue(theme.contains(".buttonStyle(WanderPrimaryButtonPressStyle())"))
        XCTAssertTrue(theme.contains(".wanderGlassRoundedRectangle("))
        XCTAssertTrue(theme.contains("cornerRadius: WanderTheme.radiusLarge"))
        XCTAssertEqual(
            mapEditor.components(separatedBy: "tone: .brand").count - 1,
            1,
            "The unified save flow has one final Astir brand confirmation."
        )
        XCTAssertTrue(addScreen.contains("private var candidateSaveAction: some View"))
        XCTAssertTrue(addScreen.contains("AstirAddPrimaryButton("))
        XCTAssertFalse(addScreen.contains("tone: .espressoConfirmation"))
        XCTAssertEqual(
            adaptiveImport.components(separatedBy: "tone: .brand").count - 1,
            2,
            "Import commit and completion confirmations use the shared Astir brand treatment."
        )
        XCTAssertFalse(adaptiveImport.contains("tone: .espressoConfirmation"))
        XCTAssertFalse(loggedOut.contains(".espressoConfirmation"))
        XCTAssertFalse(authGate.contains(".espressoConfirmation"))
    }

    func testEverySaveEntryPointUsesOneSharedBottomSheet() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let policy = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileSaveActionPolicy.swift")
        )
        let sheetWrapper = try sourceSection(
            mapScreen,
            after: "struct MapPlaceSaveFlowSheet: View {",
            before: "struct MapPlaceSaveEditor: View {"
        )
        let sharedEditor = try sourceSection(
            mapScreen,
            after: "struct MapPlaceSaveEditor: View {",
            before: "private struct MapSaveVisitPhotoSection: View"
        )

        let directSheetEntryPointCallCounts = [
            "Wander/Features/Activity/ActivityEngagementViews.swift": 1,
            "Wander/Features/Discover/DiscoverScreen.swift": 1,
            "Wander/Features/Feed/FeedScreen.swift": 1,
            "Wander/Features/Profile/ProfileImportViews.swift": 2,
            "Wander/Features/Profile/ProfileScreen.swift": 1,
            "Wander/Features/Map/PlaceProfileMapSurface.swift": 1,
            "Wander/Features/Map/MapScreen.swift": 2
        ]

        for (path, expectedCallCount) in directSheetEntryPointCallCounts {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertEqual(
                source.components(separatedBy: "MapPlaceSaveFlowSheet(").count - 1,
                expectedCallCount,
                "\(path) must route every save entry point through the shared bottom sheet."
            )
            XCTAssertTrue(source.contains(".sheet(item:"), "\(path) must present saves as a bottom sheet.")
        }

        let addScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )
        XCTAssertTrue(addScreen.contains("private func inlineSaveFlow("))
        XCTAssertTrue(addScreen.contains("MapPlaceSaveEditor("))
        XCTAssertFalse(addScreen.contains("MapPlaceSaveFlowSheet("))
        XCTAssertFalse(addScreen.contains(".sheet(item: $addSaveFlow"))
        XCTAssertTrue(addScreen.contains("onClose: dismissInlineSaveFlow"))
        XCTAssertTrue(addScreen.contains("onContentExpansionRequested: expandSheet"))
        XCTAssertTrue(addScreen.contains("completeInlineSaveFlow(result, sourceContextID: context.id)"))
        XCTAssertTrue(addScreen.contains("guard addSaveFlow?.id == sourceContextID else { return }"))
        XCTAssertTrue(addScreen.contains("return [MapPlaceSaveFlowSheet.compactDetent, .large]"))
        XCTAssertTrue(addScreen.contains(".presentationDetents(activeSheetDetents, selection: $selectedDetent)"))
        let restoredAddFlow = try sourceSection(
            addScreen,
            after: "private func restoreActiveSaveFlowIfNeeded()",
            before: "private func restoreLegacyWalkthroughSaveWithoutDraftIfNeeded()"
        )
        XCTAssertFalse(restoredAddFlow.contains("resolvingExistingSave"))

        XCTAssertTrue(sheetWrapper.contains("MapPlaceSaveEditor("))
        XCTAssertFalse(placeProfile.contains("struct PlaceSaveAttachedSheet: View"))
        XCTAssertTrue(placeProfile.contains("MapPlaceSaveFlowSheet("))
        XCTAssertFalse(placeProfile.contains("MapPlaceSaveEditor("))
        XCTAssertFalse(mapScreen.contains("MapPlaceSaveEditorPresentation"))
        XCTAssertFalse(placeProfile.contains("presentation: .attached"))
        XCTAssertTrue(placeProfile.contains(".sheet(item: attachedSaveSheetContext)"))
        XCTAssertTrue(placeProfile.contains("draft: resolvedAttachedSaveDraft(for: context)"))
        XCTAssertTrue(placeProfile.contains(".id(context.id)"))
        XCTAssertTrue(placeProfile.contains("if attachedSaveContext == nil"))
        XCTAssertTrue(placeProfile.contains("onAttachedClose()"))
        XCTAssertTrue(placeProfile.contains("\"place-profile.attached-check-in\""))
        XCTAssertTrue(placeProfile.contains("\"place-profile.attached-wanna\""))
        XCTAssertTrue(placeProfile.contains(".accessibilityIdentifier(saveSheetAccessibilityIdentifier(for: context))"))
        XCTAssertTrue(sheetWrapper.contains("static let compactHeight: CGFloat = 560"))
        XCTAssertTrue(sheetWrapper.contains("static let compactDetent = PresentationDetent.height(compactHeight)"))
        XCTAssertTrue(sheetWrapper.contains("[Self.compactDetent, .large]"))
        XCTAssertTrue(sheetWrapper.contains("selection: $selectedDetent"))
        XCTAssertTrue(sheetWrapper.contains(".presentationDragIndicator(.visible)"))
        XCTAssertTrue(sheetWrapper.contains(".presentationBackgroundInteraction(.enabled(upThrough: Self.compactDetent))"))
        XCTAssertTrue(sheetWrapper.contains(".presentationContentInteraction(.resizes)"))
        XCTAssertTrue(placeProfile.contains("onClose: onAttachedClose"))
        XCTAssertTrue(placeProfile.contains("guard attachedSaveContext?.id == context.id else { return }"))
        XCTAssertFalse(placeProfile.contains("compactDetent"))
        XCTAssertFalse(placeProfile.contains("presentationBackgroundInteraction"))

        XCTAssertTrue(sharedEditor.contains("let onSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?"))
        XCTAssertTrue(sharedEditor.contains("let onRemove: @MainActor (MapPlaceSaveContext) async -> Bool"))
        XCTAssertTrue(sharedEditor.contains("onDraftChange(draftID, update.form, update.submittedAt)"))
        XCTAssertTrue(sharedEditor.contains("onSaveCompleted(result)"))
        XCTAssertTrue(sharedEditor.contains("guard !isSaving else { return }"))
        XCTAssertTrue(sharedEditor.contains("guard saveAttemptedAt == nil else { return }"))
        XCTAssertTrue(sharedEditor.contains("walkthroughs.activeSurface == .saveFlow || isSaving || isRemoving"))
        XCTAssertTrue(sharedEditor.contains(".disabled(isSaving || isRemoving)"))
        XCTAssertTrue(sharedEditor.contains(".overlay(alignment: .bottom)"))
        XCTAssertTrue(sharedEditor.contains(".accessibilityIdentifier(\"save.placeHeader\")"))
        XCTAssertTrue(sharedEditor.contains("placeTypeSection"))
        XCTAssertTrue(sharedEditor.contains("visitParticipationSections"))
        XCTAssertFalse(sharedEditor.contains("presentation == .attached"))
        XCTAssertFalse(sharedEditor.contains("presentation == .sheet"))
        XCTAssertTrue(sharedEditor.contains("onContentExpansionRequested"))

        XCTAssertTrue(policy.contains("static func attachedFirstSaveContext("))
        XCTAssertTrue(policy.contains("static func attachedExistingWannaContext("))
        XCTAssertTrue(policy.contains("static func attachedSaveContext("))
        XCTAssertFalse(policy.contains("if isSimulator {"))
        XCTAssertTrue(policy.contains("Simulator builds follow the same flag as TestFlight"))
        XCTAssertTrue(policy.contains("route == .floatingActions"))
        XCTAssertTrue(policy.contains("state == .unsaved"))
        XCTAssertTrue(policy.contains("state == .wanna"))
        XCTAssertTrue(policy.contains("action.isSelected"))
        XCTAssertTrue(policy.contains("case (.checkIn, false, .been):"))
        XCTAssertTrue(policy.contains("isSupportedFirstSaveAction(action.kind, status: destinationStatus)"))
        XCTAssertTrue(policy.contains("case (.checkIn, .been), (.wanna, .wannaGo):"))
        XCTAssertTrue(mapScreen.contains("let currentUserSave = currentUserSave(matching: visiblePlace)"))
        XCTAssertTrue(mapScreen.contains("MapPlaceSaveContext.reselectCurrentUserSave("))
        XCTAssertTrue(mapScreen.contains("PlaceSaveDraft.restorableFlow("))
        XCTAssertTrue(mapScreen.contains("case .addVisit(let visiblePlace):"))
        XCTAssertTrue(mapScreen.contains("currentUserSave: currentUserSave(matching: selectedPlace)"))
        XCTAssertTrue(mapScreen.contains(".currentUserSaveByGroupKey[group.key]"))
        XCTAssertTrue(mapScreen.contains("?? indexedCurrentUserSave(matching: group.primary)"))
        XCTAssertTrue(mapScreen.contains("summaries.insert(saveSummary(for: currentUserSave), at: 0)"))
        XCTAssertTrue(mapScreen.contains("existingDraft.form.selectedStatus != context.initialStatus"))
        XCTAssertTrue(mapScreen.contains("switchedForm.selectedStatus = context.initialStatus"))
        XCTAssertTrue(mapScreen.contains("submittedAt: nil"))
        XCTAssertTrue(mapScreen.contains("presentAttachedSaveFlow(attachedContext)"))
        XCTAssertTrue(mapScreen.contains("dismissPlaceProfileThen {\n            performFloatingAction"))

        let visiblePlaceHandler = try sourceSection(
            mapScreen,
            after: "private func handleFloatingAction(\n        _ saveAction: PlaceProfileSaveAction,\n        for visiblePlace: VisiblePlace",
            before: "private func performFloatingAction(\n        _ saveAction: PlaceProfileSaveAction,\n        for candidate: PlaceCandidate"
        )
        let candidateHandler = try sourceSection(
            mapScreen,
            after: "private func handleFloatingAction(\n        _ saveAction: PlaceProfileSaveAction,\n        for candidate: PlaceCandidate",
            before: "private var attachedSaveDraft: PlaceSaveDraft?"
        )
        for handler in [visiblePlaceHandler, candidateHandler] {
            XCTAssertTrue(handler.contains("route: .floatingActions"))
            XCTAssertTrue(handler.contains("attachedSaveContext("))
            XCTAssertFalse(handler.contains("saveActionSnapshot(saves: saves).route"))
        }

        let attachedCompletion = try sourceSection(
            mapScreen,
            after: "private func completeAttachedSaveFlow(_ result: SaveResult) {",
            before: "private func performAction(\n        for candidate: PlaceCandidate"
        )
        let selectResultOffset = try XCTUnwrap(
            attachedCompletion.range(of: "selectSavedResult(selectedResult)")?.lowerBound
        )
        let clearCandidateOffset = try XCTUnwrap(
            attachedCompletion.range(of: "selectedSearchCandidateID = nil")?.lowerBound
        )
        XCTAssertLessThan(selectResultOffset, clearCandidateOffset)
        XCTAssertTrue(attachedCompletion.contains("mapSearchCandidates.removeAll"))

        let saveCallback = try sourceSection(
            mapScreen,
            after: "private func saveMapFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {",
            before: "private func scopedSaveMessage("
        )
        XCTAssertTrue(saveCallback.contains("let isAttachedSubmission = attachedMapSaveFlow?.id == submission.context.id"))
        XCTAssertTrue(saveCallback.contains("if !isAttachedSubmission {\n                selectedSearchCandidateID = nil"))
        XCTAssertTrue(saveCallback.contains("if !isAttachedSubmission {\n                mapSearchCandidates.removeAll"))

        let fixtureURL = projectRoot.appendingPathComponent(
            "WanderTests/Fixtures/ios-fix/rec-284-attached-sheet-detents-pre.json"
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        XCTAssertEqual(fixture["issue"] as? String, "REC-284")
        XCTAssertTrue(
            (fixture["root_cause"] as? String)?.contains("fixed maximumHeight") == true
        )
    }

    func testPlaceProfileDiscoversDirectReservationProviderLinks() throws {
        let placeProfile = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let fullView = try sourceSection(
            placeProfile,
            after: "private struct PlaceProfileFullView: View {",
            before: "private struct PlacePhotoGalleryViewerRoute: Identifiable {"
        )

        XCTAssertTrue(fullView.contains("@State private var discoveredReservationAction: PlaceExternalAction?"))
        XCTAssertTrue(fullView.contains("@State private var recoveredBusinessMetadata: PlaceBusinessMetadata?"))
        XCTAssertTrue(fullView.contains(".task(id: businessActionLookupKey)"))
        XCTAssertTrue(fullView.contains("MapKitPlaceBusinessMetadataResolver().resolve(businessMetadataRequest)"))
        XCTAssertTrue(fullView.contains("PlaceExternalLinks.discoverReservationAction("))
        XCTAssertTrue(fullView.contains("reservationAction: discoveredReservationAction"))
    }

    func testRestaurantPlaceTypeUsesCuisineInsteadOfSubcategory() throws {
        let mapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let placeTypeSection = try sourceSection(
            mapScreen,
            after: "private var placeTypeSection: some View {",
            before: "private var candidateSubtitle: String {"
        )

        XCTAssertTrue(placeTypeSection.contains("if isRestaurantsFoodSelected"))
        XCTAssertTrue(placeTypeSection.contains("placeTypePickerMode = .cuisine"))
        XCTAssertTrue(placeTypeSection.contains("title: \"food type\""))
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
                "let noun = category == WanderPlaceCategory.restaurantsFood ? \"food types\" : \"types\""
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

    func testOwnerProfileUsesCompactInstagramStyleHeaderAndRequestedSectionOrder() throws {
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
        let navigationRow = try sourceSection(
            home,
            after: "private var profileNavigationRow: some View {",
            before: "private var profileIdentityBlock: some View"
        )
        let identityBlock = try sourceSection(
            home,
            after: "private var profileIdentityBlock: some View {",
            before: "private var profileAvatar: some View"
        )
        let backButton = try sourceSection(
            home,
            after: "private struct ProfileBackButton: View {",
            before: "struct ProfileInvitationBadgeState: Equatable"
        )
        let recentActivity = try sourceSection(
            home,
            after: "private struct ProfileRecentActivitySection: View",
            before: "struct ProfileActivityRow: View"
        )

        let identityIndex = try XCTUnwrap(body.range(of: "identitySection")?.lowerBound)
        let streakIndex = try XCTUnwrap(body.range(of: "ProfileSaveStreakRow")?.lowerBound)
        let activityIndex = try XCTUnwrap(body.range(of: "ProfileRecentActivitySection")?.lowerBound)
        let mapIndex = try XCTUnwrap(body.range(of: "ProfileMapSection")?.lowerBound)
        let calendarIndex = try XCTUnwrap(body.range(of: "ProfileCalendarSection")?.lowerBound)
        let invitationButtonIndex = try XCTUnwrap(navigationRow.range(of: "ProfileInvitationButton(")?.lowerBound)
        let editButtonIndex = try XCTUnwrap(navigationRow.range(of: "accessibilityLabel: \"Edit profile\"")?.lowerBound)
        let invitationButton = try sourceSection(
            home,
            after: "private struct ProfileInvitationButton: View",
            before: "private struct ProfileHeaderActionLabel: View"
        )

        XCTAssertLessThan(identityIndex, streakIndex)
        XCTAssertLessThan(streakIndex, activityIndex)
        XCTAssertLessThan(activityIndex, mapIndex)
        XCTAssertLessThan(mapIndex, calendarIndex)
        XCTAssertFalse(body.contains("ProfileSharedVisitInboxRow"))
        XCTAssertLessThan(invitationButtonIndex, editButtonIndex)
        XCTAssertFalse(identity.contains("Text(\"profile\")"))
        XCTAssertTrue(navigationRow.contains("ProfileBackButton(action: backAction)"))
        XCTAssertTrue(navigationRow.contains("Text(\"@\\(profile.handle)\")"))
        XCTAssertLessThan(
            try XCTUnwrap(navigationRow.range(of: "ProfileBackButton(action: backAction)")?.lowerBound),
            try XCTUnwrap(navigationRow.range(of: "Text(\"@\\(profile.handle)\")")?.lowerBound)
        )
        XCTAssertTrue(navigationRow.contains("pendingInvitationCount: sharedVisitInvitationCount"))
        XCTAssertFalse(navigationRow.contains("WanderTheme.surfaceRaised.color"))
        XCTAssertTrue(identityBlock.contains("HStack(alignment: .top, spacing: WanderTheme.spacing3)"))
        XCTAssertTrue(identityBlock.contains("Text(profile.displayName)"))
        XCTAssertTrue(identityBlock.contains("ProfileGraphCountButton(value: followerCount"))
        XCTAssertTrue(identityBlock.contains("normalized(profile.homeArea)"))
        XCTAssertTrue(identityBlock.contains(".font(AstirTypography.sheetTitle)"))
        XCTAssertTrue(identityBlock.contains(".font(AstirTypography.control)"))
        XCTAssertTrue(identityBlock.contains("normalized(profile.bio)"))
        XCTAssertTrue(identityBlock.contains("Text(memberSinceText)"))
        XCTAssertLessThan(
            try XCTUnwrap(identityBlock.range(of: "normalized(profile.homeArea)")?.lowerBound),
            try XCTUnwrap(identityBlock.range(of: "normalized(profile.bio)")?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(identityBlock.range(of: "normalized(profile.bio)")?.lowerBound),
            try XCTUnwrap(identityBlock.range(of: "Text(memberSinceText)")?.lowerBound)
        )
        XCTAssertFalse(identityBlock.contains(".background(WanderTheme.surfaceRaised.color)"))
        XCTAssertFalse(identityBlock.contains(".padding(.horizontal, -WanderTheme.spacing4)"))
        XCTAssertTrue(backButton.contains("Image(systemName: \"chevron.left\")"))
        XCTAssertTrue(backButton.contains("width: WanderTheme.tapMinimum"))
        XCTAssertTrue(backButton.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(backButton.contains(".wanderGlassCapsule"))
        XCTAssertTrue(home.contains("private let profileAvatarSize: CGFloat = 86"))
        XCTAssertTrue(invitationButton.contains("ProfileHeaderActionLabel(systemImage: \"envelope\")"))
        XCTAssertTrue(invitationButton.contains("if badgeState.isVisible"))
        XCTAssertTrue(invitationButton.contains("Circle()"))
        XCTAssertTrue(invitationButton.contains("Color(uiColor: .systemRed)"))
        XCTAssertTrue(invitationButton.contains(".zIndex(1)"))
        XCTAssertFalse(invitationButton.contains(".stroke("))
        XCTAssertTrue(invitationButton.contains("profile.checkInInvitations"))
        XCTAssertFalse(invitationButton.contains("Text("))
        XCTAssertTrue(screen.contains("sharedVisitInvitationsAction: { showsVisitInvitations = true }"))
        XCTAssertTrue(screen.contains(".navigationDestination(isPresented: $showsVisitInvitations)"))
        XCTAssertTrue(recentActivity.contains("ProfileActivityFilterControl("))
        XCTAssertTrue(home.contains("case checkIns = \"check_ins\""))
        XCTAssertTrue(home.contains("case .checkIns: CheckInCopy.pluralTitle"))
        XCTAssertFalse(home.contains("case .been: \"Been\""))
        XCTAssertFalse(screen.contains("No Been activity"))
        XCTAssertTrue(recentActivity.contains("filteredItems.prefix(6)"))
        XCTAssertTrue(recentActivity.contains("Text(\"See more\")"))
        XCTAssertTrue(recentActivity.contains("Text(\"Activity\")"))
        XCTAssertFalse(recentActivity.contains("Text(\"Recent activity\")"))
        XCTAssertTrue(screen.contains("Saved places and check-ins will appear here"))
        XCTAssertFalse(screen.contains("Your saved places and check-ins will appear here"))
        XCTAssertTrue(screen.contains("ProfileActivityHistoryScreen("))
        XCTAssertTrue(screen.contains("initialSection: .activity"))
        XCTAssertTrue(
            placeProfile.contains(
                "scrollProxy.scrollTo(PlaceProfileScrollAnchor.activity, anchor: .top)"
            )
        )
    }

    func testProfileInvitationBadgeStateTracksPendingInvitationCount() {
        XCTAssertFalse(ProfileInvitationBadgeState(pendingInvitationCount: 0).isVisible)
        XCTAssertEqual(
            ProfileInvitationBadgeState(pendingInvitationCount: 0).accessibilityValue,
            "No pending invitations"
        )

        XCTAssertTrue(ProfileInvitationBadgeState(pendingInvitationCount: 1).isVisible)
        XCTAssertEqual(
            ProfileInvitationBadgeState(pendingInvitationCount: 1).accessibilityValue,
            "1 pending"
        )
        XCTAssertEqual(
            ProfileInvitationBadgeState(pendingInvitationCount: 4).accessibilityValue,
            "4 pending"
        )
        XCTAssertFalse(ProfileInvitationBadgeState(pendingInvitationCount: -1).isVisible)
    }

    func testProfileActivityAndMapFiltersUseSharedAstirUnderlineSegments() throws {
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let astir = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/DesignSystem/AstirVisualSystem.swift")
        )
        let activityFilter = try sourceSection(
            home,
            after: "struct ProfileActivityFilterControl: View",
            before: "private struct ProfileRecentActivitySection: View"
        )
        let mapPicker = try sourceSection(
            home,
            after: "private struct ProfileMapSummaryPicker: View",
            before: "private struct ProfileMapSnapshotView: View"
        )
        let editorialSegmentedSwitch = try sourceSection(
            astir,
            after: "struct AstirEditorialSegmentedSwitch: View",
            before: "struct AstirOutlinedSurface: ViewModifier"
        )

        XCTAssertTrue(activityFilter.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertTrue(activityFilter.contains("ProfileActivityFilter.allCases.map"))
        XCTAssertTrue(activityFilter.contains("accessibilityLabel: accessibilityLabel(for: filter)"))
        XCTAssertTrue(activityFilter.contains("selection: selectedFilterID"))
        XCTAssertTrue(activityFilter.contains(".accessibilityIdentifier(\"profile.activityFilter\")"))
        XCTAssertFalse(activityFilter.contains("RoundedRectangle"))
        XCTAssertTrue(editorialSegmentedSwitch.contains(".accessibilityLabel(option.accessibilityLabel ?? option.title)"))
        XCTAssertTrue(editorialSegmentedSwitch.contains("Rectangle()"))
        XCTAssertTrue(editorialSegmentedSwitch.contains(".frame(height: 1.5)"))
        XCTAssertTrue(editorialSegmentedSwitch.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(editorialSegmentedSwitch.contains(".astirGlassSurface(cornerRadius: 17, castsShadow: true)"))
        XCTAssertTrue(mapPicker.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertFalse(mapPicker.contains("WanderGlassButtonCluster"))
    }

    func testOtherUserProfileUsesDividerOnlyInCommonRowAndOwnerParity() throws {
        let home = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let screen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
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
        let inCommonRow = try sourceSection(
            home,
            after: "private struct ProfileInCommonPlacesRow: View",
            before: "private struct ProfileGraphCountButton: View"
        )
        let monthButton = try sourceSection(
            home,
            after: "private struct ProfileMonthButton: View",
            before: "private struct ProfileCalendarMetric: View"
        )
        let mapPicker = try sourceSection(
            home,
            after: "private struct ProfileMapSummaryPicker: View",
            before: "private struct ProfileMapSnapshotView: View"
        )

        let identityIndex = try XCTUnwrap(body.range(of: "identitySection")?.lowerBound)
        let inCommonIndex = try XCTUnwrap(body.range(of: "ProfileInCommonPlacesRow")?.lowerBound)
        let activityIndex = try XCTUnwrap(body.range(of: "ProfileRecentActivitySection")?.lowerBound)

        XCTAssertLessThan(identityIndex, inCommonIndex)
        XCTAssertLessThan(inCommonIndex, activityIndex)
        XCTAssertTrue(body.contains("mode.visibleInCommonCount("))
        XCTAssertTrue(body.contains("profileID: profile.id"))
        XCTAssertTrue(body.contains("viewerID: viewerProfile.id"))
        XCTAssertFalse(body.contains("savedPlacesSection"))
        XCTAssertTrue(inCommonRow.contains("See where your maps overlap"))
        XCTAssertFalse(inCommonRow.contains(".wanderGlassPanel("))
        XCTAssertTrue(inCommonRow.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(inCommonRow.contains(".overlay(alignment: .bottom)"))
        XCTAssertTrue(inCommonRow.contains(".fill(brandMode.border)"))
        XCTAssertTrue(inCommonRow.contains("viewerProfile.avatarURL"))
        XCTAssertTrue(inCommonRow.contains("profile.avatarURL"))
        XCTAssertTrue(identity.contains("HStack(alignment: .top, spacing: WanderTheme.spacing3)"))
        XCTAssertTrue(identity.contains("ProfileGraphCountButton(value: followerCount"))
        XCTAssertTrue(identity.contains(".astirOutlinedSurface("))
        XCTAssertTrue(home.contains("private struct ProfileHeaderActionLabel: View"))
        XCTAssertTrue(home.contains(".wanderGlassCapsule()"))
        XCTAssertTrue(monthButton.contains(".wanderGlassCapsule()"))
        XCTAssertTrue(mapPicker.contains("AstirEditorialSegmentedSwitch("))
        XCTAssertEqual(screen.components(separatedBy: "recentActivity: profileActivityItems").count - 1, 2)
        XCTAssertEqual(screen.components(separatedBy: "viewerProfile: store.currentUser").count - 1, 2)
    }

    func testOtherUserProfileBuildsActivityForTheViewedMember() throws {
        let screen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let memberProfile = try sourceSection(
            screen,
            after: "struct ProfileDetailView: View {",
            before: "private struct ProfileActivityHistoryScreen: View"
        )
        let activityItems = try sourceSection(
            memberProfile,
            after: "private var profileActivityItems: [ProfileActivityItem] {",
            before: "private var selectedActivityItem: ProfileActivityItem?"
        )

        XCTAssertTrue(activityItems.contains("currentUserID: profileID"))
        XCTAssertFalse(activityItems.contains("currentUserID: store.currentUser.id"))
    }

    func testThirdLaunchDeviceLessonUsesACompactNonScrollingEditorialPanel() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Onboarding/FirstVisitWalkthrough.swift"
            )
        )
        let overlay = try sourceSection(
            source,
            after: "private struct DeviceFeaturesWalkthroughOverlay: View",
            before: "private struct DeviceFeatureInstruction: View"
        )

        XCTAssertFalse(overlay.contains("ScrollView"))
        XCTAssertTrue(overlay.contains(".font(AstirTypography.sectionTitle)"))
        XCTAssertTrue(overlay.contains(".frame(maxWidth: 344)"))
        XCTAssertTrue(overlay.contains(".background(brandMode.accent)"))
        XCTAssertFalse(overlay.contains(".wanderGlassCapsule(tone: .accent)"))
        XCTAssertTrue(overlay.contains(".scaleEffect("))
        XCTAssertFalse(
            source.contains(
                ".animation(.easeInOut(duration: 0.2), value: coordinator.isPresentingDeviceFeaturesLesson)"
            )
        )
    }

    func testFeedFeaturedRailBleedsToBothScreenEdgesWithoutMovingRestingCards() throws {
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let rail = try sourceSection(
            feed,
            after: "private struct FeedFeaturedRail: View",
            before: "private struct FeedFeaturedCard: View"
        )

        XCTAssertTrue(feed.contains("static let screenEdgeBleed = WanderTheme.spacing4"))
        XCTAssertTrue(rail.contains(".contentMargins("))
        XCTAssertTrue(rail.contains("FeedFeaturedLayout.screenEdgeBleed"))
        XCTAssertTrue(rail.contains("for: .scrollContent"))
        XCTAssertTrue(
            rail.contains(".padding(.horizontal, -FeedFeaturedLayout.screenEdgeBleed)")
        )
        XCTAssertTrue(rail.contains(".padding(.vertical, 1)"))
        XCTAssertFalse(rail.contains(".padding(.horizontal, 1)"))
    }

    func testFirstVisitSurfacePolishUsesWalkthroughOnlyMapAndSingleBackContracts() throws {
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let discover = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let lists = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Lists/ListsScreen.swift")
        )

        let mapFilters = try sourceSection(
            map,
            after: "if !isMapSearchFocused {",
            before: "if let mapFilterEmptyMessage"
        )
        XCTAssertEqual(
            mapFilters.components(separatedBy: ".walkthroughTarget(.mapFeatured)").count - 1,
            1
        )
        XCTAssertFalse(mapFilters.contains(".walkthroughEmphasis("))
        XCTAssertTrue(map.contains("walkthroughs.isAwaitingEligibilityResolution"))
        XCTAssertTrue(map.contains("walkthroughs.activeSurface != nil"))
        XCTAssertTrue(map.contains("walkthroughs.requestedSurface != nil"))
        XCTAssertFalse(map.contains("No featured check-ins here yet."))

        let optionalDetails = try sourceSection(
            map,
            after: "private var optionalDetailsDisclosure: some View",
            before: "private var removeSaveSection: some View"
        )
        XCTAssertTrue(optionalDetails.contains("isMoreOptionsArrowPulsing"))
        XCTAssertTrue(optionalDetails.contains(".walkthroughTarget(.saveMoreOptions)"))
        XCTAssertFalse(optionalDetails.contains(".walkthroughEmphasis(.saveMoreOptions)"))
        XCTAssertFalse(optionalDetails.contains(".stroke(WanderTheme.categorySun.color"))

        XCTAssertEqual(
            feed.components(separatedBy: "FeedSectionHeading(title: \"Recent\"").count - 1,
            4
        )
        XCTAssertEqual(
            feed.components(separatedBy: ".walkthroughTarget(.feedActivity)").count - 1,
            1,
            "The empty Feed state must provide a stable activity walkthrough target."
        )
        XCTAssertTrue(feed.contains("event.id == activity.first?.id ? .feedActivity : nil"))
        XCTAssertFalse(feed.contains("FeedSectionHeading(title: \"See your friends’ check-ins here\""))

        let backHandler = try sourceSection(
            discover,
            after: "private func handlePlaceSearchBack()",
            before: "private func submitPlaceSearch()"
        )
        let resultsBack = try sourceSection(
            backHandler,
            after: "case .feedSearchResultsBack:",
            before: "default:"
        )
        XCTAssertTrue(resultsBack.contains("walkthroughs.perform(.feedSearchResultsBack)"))
        XCTAssertTrue(feed.contains("onClose: closeDiscoverSearch"))
        XCTAssertTrue(feed.contains("walkthroughs.consumeRequestedSurface(.feed)"))
        XCTAssertTrue(feed.contains("selectedSurface = .people"))
        XCTAssertTrue(feed.contains("restoreFeedWalkthroughAfterDiscoverDismissal()"))
        XCTAssertTrue(feed.contains("FeedSurface.walkthroughDestination("))
        XCTAssertTrue(feed.contains("guard activeSurface == .feed else { return nil }"))
        XCTAssertTrue(resultsBack.contains("exitPlaceSearch()"))
        XCTAssertTrue(discover.contains("DiscoverWalkthroughTargetPolicy.searchBackTarget("))
        XCTAssertFalse(
            discover.contains("case .feedSearchResultsBack where isWalkthroughSearchResultReady")
        )
        XCTAssertFalse(discover.contains("feedSearchExitBack"))

        let listsAnimation = try sourceSection(
            lists,
            after: "private func runListsWalkthroughAnimationIfNeeded() async",
            before: "private var activeLists: [PlaceListMock]"
        )
        XCTAssertTrue(listsAnimation.contains(".milliseconds(900)"))
        XCTAssertTrue(listsAnimation.contains(".milliseconds(1_400)"))
        XCTAssertTrue(listsAnimation.contains(".milliseconds(4_000)"))
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
