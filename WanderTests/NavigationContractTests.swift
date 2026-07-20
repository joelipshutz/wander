import XCTest
@testable import Wander

final class NavigationContractTests: XCTestCase {
    func testBottomNavigationUsesRequestedFiveItemOrder() {
        XCTAssertEqual(WanderTab.allCases, [.map, .discover, .add, .lists, .profile])
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
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "https://rec.me/profiles/user_joe"))))
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "recme://places/place_1"))))
    }

    @MainActor
    func testSharedProfileContentBuildsTheRegisteredDeepLinkAndCopy() throws {
        let content = try XCTUnwrap(
            WanderShareContent.profile(id: "user joe", displayName: "Joe Example", handle: "joe")
        )

        XCTAssertEqual(content.item.absoluteString, "recme://profiles/user%20joe")
        XCTAssertEqual(content.subject, "Joe Example")
        XCTAssertEqual(content.message, "See @joe on rec.me")
        XCTAssertEqual(WanderRootView.sharedProfileRoute(for: content.item), SharedProfileRoute(profileID: "user joe"))
    }

    func testSharedProfileMapContentUsesSharedNativeShareWorker() throws {
        let content = try XCTUnwrap(
            WanderShareContent.profileMap(id: "user maya", displayName: "Maya Chen", handle: "maya")
        )

        XCTAssertEqual(content.item.absoluteString, "recme://profiles/user%20maya")
        XCTAssertEqual(content.subject, "Maya Chen's map")
        XCTAssertEqual(content.message, "Explore @maya's saved places on rec.me")
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

        XCTAssertTrue(addScreen.contains("MapPlaceSaveFlowSheet(context: context)"))
        XCTAssertTrue(addScreen.contains("persistNewPlaceSaveSubmission("))
        XCTAssertFalse(addScreen.contains("store.saveCandidate("))
        XCTAssertFalse(addScreen.contains("private var detailsForm"))
        XCTAssertTrue(addScreen.contains("Search, paste a link, or add coordinates"))
        XCTAssertTrue(addScreen.contains("\"I'm here now\""))
        XCTAssertTrue(addScreen.contains("title: \"From a photo\""))
        XCTAssertFalse(addScreen.contains("SourceRow(title: AddSourceType.manual.title"))
    }

    func testRequestedMemberEntryPointsPresentTheFullProfileDetail() throws {
        let presentations = [
            ("Wander/App/WanderRootView.swift", ".fullScreenCover(item: $sharedProfile)"),
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
        XCTAssertTrue(source.contains(".onTapGesture { selectDate(date, day: day) }"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(source.contains(".accessibilityAction { selectDate(date, day: day) }"))
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
        XCTAssertFalse(mapSection.contains("\n            Map("))
        XCTAssertFalse(source.contains("LazyVStack"))
        XCTAssertFalse(source.contains("LazyVGrid"))
    }

    @MainActor
    func testNotificationDestinationsSelectTheirOwningTabs() {
        XCTAssertEqual(WanderRootView.notificationTab(for: .people(.friends)), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .drafts(extractionJobID: "job-1")), .profile)
        XCTAssertEqual(WanderRootView.notificationTab(for: .list(id: "list-1")), .lists)
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
        XCTAssertTrue(activeLists.contains(".prefix(4)"))
        XCTAssertTrue(source.contains("let renderedLists = activeLists"))
        XCTAssertTrue(source.contains("listGrid(lists: renderedLists)"))
        XCTAssertTrue(detailScreen.contains("let renderedList = displayList"))
        XCTAssertEqual(detailScreen.components(separatedBy: "let renderedList = displayList").count - 1, 1)
        XCTAssertTrue(richProjection.contains("VisiblePlaceGrouping.groups("))
        XCTAssertTrue(richProjection.contains("store.firstVisitPhotosByPlaceID()"))
        XCTAssertFalse(richProjection.contains("store.attributes(for:"))
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

    func testDiscoverUnboundedRowsAreLazyAndSearchWorkIsCancellable() throws {
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
            after: "private var friendsSection: some View",
            before: "private func beginSaveDiscoverPlace"
        )
        let memberResults = try sourceSection(
            source,
            after: "private var memberSearchResultsSection: some View",
            before: "private var friendsSection: some View"
        )

        XCTAssertTrue(placeResults.contains("LazyVStack"))
        XCTAssertTrue(friends.contains("LazyVStack"))
        XCTAssertTrue(memberResults.contains("LazyHStack"))
        XCTAssertFalse(source.contains("store.visiblePlaces(for: profile.id).count"))
        XCTAssertTrue(source.contains(".task(id: placesQuery)"))
        XCTAssertTrue(source.contains(".task(id: memberQuery)"))
        XCTAssertFalse(source.contains(".onChange(of: placesQuery)"))
        XCTAssertFalse(source.contains(".onChange(of: memberQuery)"))
    }

    func testDiscoverAuthAndVisibleDataRefreshesRerunActiveSearchesCancellably() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )
        let authRefresh = try sourceSection(
            source,
            after: ".task(id: auth.isSignedIn)",
            before: ".task(id: placesQuery)"
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
