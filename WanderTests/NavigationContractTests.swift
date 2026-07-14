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
    func testRootViewUsesEmptyFixturesByDefaultAndDemoFixturesOnlyWhenRequested() {
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander"]), .empty)
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander", "-WanderUseDemoFixtures"]), .demo)
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
