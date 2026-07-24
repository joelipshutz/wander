import XCTest
import UIKit
import MapKit
@testable import Wander

final class NavigationContractTests: XCTestCase {
    func testBottomNavigationUsesRequestedFiveItemOrder() {
        XCTAssertEqual(WanderTab.allCases, [.map, .discover, .add, .lists, .profile])
    }

    func testDiscoverTabPresentsTheDedicatedFeedWithTheCompactSearchLauncher() throws {
        let root = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/App/WanderRootView.swift")
        )
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )

        XCTAssertTrue(root.contains("FeedScreen()"))
        XCTAssertTrue(root.contains("case .discover: \"Feed\""))
        XCTAssertTrue(root.contains("case .discover: \"newspaper\""))
        XCTAssertTrue(feed.contains("private struct FeedSearchLauncher"))
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

    func testFeedSaveUsesTheCanonicalPlaceSaveFlowAndKeepsOnlyFeaturedCardsUniform() throws {
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
        XCTAssertTrue(activityList.contains("Divider()"))
        XCTAssertTrue(activityList.contains(".padding(.horizontal, -WanderTheme.spacing4)"))
        XCTAssertFalse(activityList.contains(".background(WanderTheme.surfaceBone.color)"))
        XCTAssertFalse(activityList.contains(".clipShape(RoundedRectangle"))

        XCTAssertTrue(feed.contains("private enum FeedFeaturedLayout"))

        let activityModule = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedActivityModule: View").last
        )
        XCTAssertFalse(activityModule.contains("FeedActivityLayout.rowHeight"))
        XCTAssertFalse(activityModule.contains("maxHeight:"))

        let featuredCard = try XCTUnwrap(
            feed.components(separatedBy: "private struct FeedFeaturedCard: View").last?
                .components(separatedBy: "private struct FeedActivityList: View").first
        )
        XCTAssertTrue(featuredCard.contains("height: FeedFeaturedLayout.cardHeight"))
        XCTAssertTrue(featuredCard.contains("width: FeedFeaturedLayout.cardWidth"))
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
        let activityAction = try XCTUnwrap(
            activityModule.components(separatedBy: "private var actionButton: some View").last?
                .components(separatedBy: "private var activityVerb: String").first
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
        XCTAssertTrue(featuredCard.contains("Label(\"View place\""))
        XCTAssertFalse(featuredCard.contains("save(featured)"))

        XCTAssertTrue(activityList.contains("let openPlace: (VisiblePlace) -> Void"))
        XCTAssertFalse(activityList.contains("let save:"))
        XCTAssertTrue(activityModule.contains("openProfile(activity.actor)"))
        XCTAssertTrue(activityModule.contains("openPlace(place)"))
        XCTAssertTrue(activityModule.contains("Text(activity.actor.displayName)"))
        XCTAssertTrue(activityModule.contains("Text(place.place.canonicalName)"))
        XCTAssertTrue(activityAction.contains("else if let place = activity.place"))
        XCTAssertTrue(activityAction.contains("openPlace(place)"))
        XCTAssertTrue(activityAction.contains("Label(\"View place\""))
        XCTAssertFalse(activityAction.contains("save(activity)"))

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
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "https://rec.me/profiles/user_joe"))))
        XCTAssertNil(WanderRootView.sharedProfileRoute(for: try XCTUnwrap(URL(string: "recme://places/place_1"))))
    }

    @MainActor
    func testSharedProfileContentBuildsTheRegisteredDeepLinkAndCopy() throws {
        let content = try XCTUnwrap(
            WanderShareContent.profile(serverID: "user joe", displayName: "Joe Example", handle: "joe")
        )

        XCTAssertEqual(content.item.absoluteString, "recme://profiles/user%20joe")
        XCTAssertEqual(content.items, [content.item])
        XCTAssertEqual(content.subject, "Joe Example")
        XCTAssertEqual(content.message, "See @joe on rec.me")
        XCTAssertEqual(WanderRootView.sharedProfileRoute(for: content.item), SharedProfileRoute(profileID: "user joe"))
        XCTAssertNil(WanderShareContent.profile(serverID: nil, displayName: "Guest", handle: "you"))
        XCTAssertNil(WanderShareContent.profile(serverID: "   ", displayName: "Guest", handle: "you"))
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

        XCTAssertEqual(content.item.absoluteString, "recme://profiles/user%20maya")
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
        XCTAssertTrue(addScreen.contains("AddImportSection("))
        XCTAssertTrue(addScreen.contains("PlaceImportSourceScreen("))
        XCTAssertTrue(addScreen.contains("PlaceImportInboxScreen(importStore: importStore)"))
        XCTAssertTrue(addScreen.contains("emptyRestingHeight: CGFloat = 410"))
        XCTAssertTrue(addScreen.contains("pendingReviewRestingHeight: CGFloat = 480"))
        XCTAssertTrue(
            root.contains(
                "AddSheetLayout.detents(\n                        hasPendingImports: importStore.summary.hasPendingImports"
            )
        )
        XCTAssertTrue(root.contains(".onChange(of: importStore.summary.hasPendingImports)"))
        XCTAssertTrue(importViews.contains("if summary.hasPendingImports"))
        XCTAssertFalse(profileScreen.contains("PlaceImportStore"))
        XCTAssertFalse(profileHome.contains("ImportSection"))
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
        XCTAssertTrue(optionalDetails.contains("note, tags, labels & privacy"))
        XCTAssertEqual(
            mapScreen.components(separatedBy: "MapSavePickerBlock(title: \"save as\")").count - 1,
            1
        )
        XCTAssertTrue(mapScreen.contains("if step == .details && context.requiresStatusConfirmation"))
        XCTAssertTrue(mapScreen.contains("@State private var isShowingOptionalDetails = false"))
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
        XCTAssertTrue(mapSection.contains("shareImageFileURL = nil"))
        XCTAssertTrue(mapSection.contains("renderedSnapshot = ProfileMapRenderedSnapshot(key: request.cacheKey, image: image)"))
        XCTAssertTrue(mapSection.contains("let pngData = image.pngData()"))
        XCTAssertTrue(mapSection.contains("shareImageFileURL = imageFileURL"))
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

    func testDiscoverColdStartKeepsTabsAndBuildsThePeopleNetwork() throws {
        let discoverScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Discover/DiscoverScreen.swift")
        )

        XCTAssertTrue(discoverScreen.contains("ForEach(DiscoverMode.allCases)"))
        XCTAssertTrue(discoverScreen.contains("case .loaded where latestActivityPlaces.isEmpty"))
        XCTAssertTrue(discoverScreen.contains("DiscoverActivityEmptyPanel"))
        XCTAssertTrue(discoverScreen.contains("selectedMode = .members"))
        XCTAssertTrue(discoverScreen.contains("PeopleRecommendationShelf"))
        XCTAssertTrue(discoverScreen.contains("ScrollView(.horizontal"))
        XCTAssertTrue(discoverScreen.contains("store.hasAcknowledgedFollow(to: $0)"))
        XCTAssertTrue(discoverScreen.contains("if isMemberSearchActive"))
        XCTAssertTrue(discoverScreen.contains("SectionTitle(\"People\")"))
        XCTAssertTrue(discoverScreen.contains("SectionTitle(\"People worth following\")"))
        XCTAssertFalse(discoverScreen.contains("SectionTitle(\"Following\")"))

        let recommendationCard = try XCTUnwrap(
            discoverScreen
                .components(separatedBy: "private struct PeopleRecommendationCard")
                .dropFirst()
                .first?
                .components(separatedBy: "private struct DiscoverSearchField")
                .first
        )
        XCTAssertTrue(recommendationCard.contains("size: 52"))
        XCTAssertTrue(recommendationCard.contains(".lineLimit(2)"))
        XCTAssertTrue(recommendationCard.contains(".frame(minHeight: 238)"))
        XCTAssertFalse(recommendationCard.contains("size: 58"))
        XCTAssertFalse(recommendationCard.contains(".lineLimit(3)"))
        XCTAssertFalse(recommendationCard.contains(".frame(minHeight: 264)"))
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
