import Photos
import UIKit
import XCTest
@testable import Wander

@MainActor
final class ActivityEngagementTests: XCTestCase {
    func testShareDestinationTrayUsesTheRequestedOrderAndRoutes() {
        XCTAssertEqual(
            ActivityShareDestination.allCases,
            [
                .messages,
                .copyLink,
                .instagramStory,
                .instagramPost,
                .tikTok,
                .snapchat,
                .save,
                .more,
            ]
        )
        XCTAssertEqual(ActivityShareDestination.messages.route, .messages)
        XCTAssertEqual(ActivityShareDestination.copyLink.route, .copyLink)
        XCTAssertEqual(ActivityShareDestination.instagramStory.route, .instagramStory)
        XCTAssertEqual(ActivityShareDestination.instagramPost.route, .instagramPost)
        XCTAssertEqual(ActivityShareDestination.tikTok.route, .tikTok)
        XCTAssertEqual(ActivityShareDestination.snapchat.route, .snapchat)
        XCTAssertEqual(ActivityShareDestination.save.route, .savePhoto)
        XCTAssertEqual(ActivityShareDestination.more.route, .systemShare)
    }

    func testSharePhotoPermissionPolicyRequestsOnceThenSavesOrRoutesToSettings() {
        XCTAssertEqual(
            ActivitySharePhotoPermissionPolicy.action(for: .notDetermined),
            .requestAuthorization
        )
        XCTAssertEqual(
            ActivitySharePhotoPermissionPolicy.action(for: .authorized),
            .save
        )
        XCTAssertEqual(
            ActivitySharePhotoPermissionPolicy.action(for: .limited),
            .save
        )
        XCTAssertEqual(
            ActivitySharePhotoPermissionPolicy.action(for: .denied),
            .showSettings
        )
        XCTAssertEqual(
            ActivitySharePhotoPermissionPolicy.action(for: .restricted),
            .showSettings
        )
    }

    func testShareProviderConfigurationRejectsMissingBuildSettingPlaceholders() {
        XCTAssertNil(ActivityShareProviderConfiguration.normalizedValue(nil))
        XCTAssertNil(ActivityShareProviderConfiguration.normalizedValue("   "))
        XCTAssertNil(
            ActivityShareProviderConfiguration.normalizedValue("$(WANDER_TIKTOK_CLIENT_KEY)")
        )
        XCTAssertNil(
            ActivityShareProviderConfiguration.normalizedValue("recme-tiktok-unconfigured")
        )
        XCTAssertEqual(
            ActivityShareProviderConfiguration.normalizedValue("  provider-client-key  "),
            "provider-client-key"
        )
        XCTAssertEqual(
            ActivityShareProviderConfiguration.tikTokRedirectURI,
            "https://getrec.me/share/tiktok"
        )
    }

    func testInstagramFeedPrefersLibraryDeepLinkAndKeepsDocumentFallback() throws {
        let localIdentifier = "A1B2C3/L0/001"
        let deepLink = try XCTUnwrap(
            ActivityShareInstagramFeedContract.deepLinkURL(localIdentifier: localIdentifier)
        )
        let components = try XCTUnwrap(
            URLComponents(url: deepLink, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "instagram")
        XCTAssertEqual(components.host, "library")
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "OpenInEditor", value: "1"),
                URLQueryItem(name: "LocalIdentifier", value: localIdentifier),
            ]
        )
        XCTAssertNil(ActivityShareInstagramFeedContract.deepLinkURL(localIdentifier: ""))
        XCTAssertEqual(ActivityShareInstagramFeedContract.fileExtension, "igo")
        XCTAssertEqual(
            ActivityShareInstagramFeedContract.uniformTypeIdentifier,
            "com.instagram.exclusivegram"
        )
    }

    func testInstagramPostDirectHandoffFixtureDocumentsFallback() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-271-instagram-post-direct-handoff-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(fixture["issue"] as? String, "REC-271")
        XCTAssertTrue(
            try XCTUnwrap(fixture["expected_behavior"] as? String)
                .contains("instagram://library")
        )
        XCTAssertTrue(
            try XCTUnwrap(fixture["fallback_behavior"] as? String)
                .contains("com.instagram.exclusivegram")
        )
    }

    func testTikTokOutcomePolicyReportsSuccessDraftCancellationAndProviderFailures() {
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: 0, shareState: 20_000),
            .shared
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: 0, shareState: 20_015),
            .savedAsDraft
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: -3, shareState: 20_015),
            .savedAsDraft
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: -2, shareState: 20_001),
            .cancelled
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: 0, shareState: 20_013),
            .cancelled
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: -3, shareState: 20_008),
            .failed(message: "TikTok rejected the share image resolution.")
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: -3, shareState: 20_004),
            .failed(
                message: "Sign in to the TikTok account enabled for this rec.me sandbox, then try again."
            )
        )
        XCTAssertEqual(
            ActivityShareTikTokOutcomePolicy.outcome(errorCode: -3, shareState: 20_001),
            .failed(
                message: "TikTok could not finish this share. Try again or use More to share another way."
            )
        )
    }

    func testActivitySharePNGAttachmentKeepsCanonicalLinkOutOfTheLocalMessagePath() throws {
        let activityID = "41000000-0000-0000-0000-000000000001"
        let fileURL = URL(fileURLWithPath: "/tmp/recme-activity-share.png")
        let content = try XCTUnwrap(
            WanderShareContent.activity(
                activityID: activityID,
                placeName: "Ada Street",
                message: "See Judy's check-in"
            )?.attachingPNG(at: fileURL)
        )

        XCTAssertEqual(content.items, [
            URL(string: "https://getrec.me/activities/\(activityID)")!,
            WanderShareContent.publicTestFlightURL,
            fileURL,
        ])
        XCTAssertTrue(content.messageBody.contains("https://getrec.me/activities/\(activityID)"))
        XCTAssertTrue(content.messageBody.contains(WanderShareContent.publicTestFlightURL.absoluteString))
        XCTAssertFalse(content.messageBody.contains(fileURL.absoluteString))
    }

    func testMessagesPresentationPolicyBlocksAReentrantLaunch() {
        XCTAssertTrue(
            ActivityShareMessagePresentationPolicy.shouldBeginPresentation(isPending: false)
        )
        XCTAssertFalse(
            ActivityShareMessagePresentationPolicy.shouldBeginPresentation(isPending: true)
        )
    }

    func testMessagesPresentationPolicyFallsBackOnlyWhenMessageUIFails() {
        XCTAssertEqual(
            ActivityShareMessagePresentationPolicy.completionAction(for: .cancelled),
            .dismiss
        )
        XCTAssertEqual(
            ActivityShareMessagePresentationPolicy.completionAction(for: .sent),
            .dismiss
        )
        XCTAssertEqual(
            ActivityShareMessagePresentationPolicy.completionAction(for: .failed),
            .openSystemShare
        )
    }

    func testSharePreviewPresentationCapturesAnImmutableRouteAtTapTime() throws {
        let context = ActivityEngagementContext(
            activityID: "41000000-0000-0000-0000-000000000274",
            actor: ProfileShell(
                id: "user_joe",
                handle: "joelipshutz",
                displayName: "Joe Lipshutz",
                avatarURL: nil,
                bio: nil,
                relationship: .owner
            ),
            placeName: "Jade Rabbit",
            placeServerID: "40000000-0000-0000-0000-000000000274",
            placeDetail: "Chinese · Santa Monica · CA",
            ticketKind: .checkIn,
            occurredAt: Date(timeIntervalSince1970: 1_775_520_000),
            note: "Did it again"
        )
        let routeID = UUID(uuidString: "51000000-0000-0000-0000-000000000274")!

        let presentation = try XCTUnwrap(
            ActivitySharePreviewPresentation(id: routeID, context: context)
        )
        let expectedContent = try XCTUnwrap(
            WanderShareContent.activity(
                activityID: context.activityID,
                placeName: context.placeName,
                message: context.shareMessage
            )
        )

        XCTAssertEqual(presentation.id, routeID)
        XCTAssertEqual(presentation.context, context)
        XCTAssertEqual(presentation.content, expectedContent)
    }

    func testShareArtworkRendererUsesTheResolvedAvatarImage() throws {
        let context = ActivityEngagementContext(
            activityID: "41000000-0000-0000-0000-000000000002",
            actor: ProfileShell(
                id: "user_friend",
                handle: "friend",
                displayName: "Judy",
                avatarURL: nil,
                bio: nil,
                relationship: .follower
            ),
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            status: .been,
            occurredAt: .now
        )
        let avatarImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image {
            UIColor.systemBlue.setFill()
            $0.fill(CGRect(origin: .zero, size: CGSize(width: 12, height: 12)))
        }

        let fallbackArtwork = try XCTUnwrap(
            ActivityShareArtworkRenderer.render(context: context)
        )
        let avatarArtwork = try XCTUnwrap(
            ActivityShareArtworkRenderer.render(
                context: context,
                avatarImage: avatarImage
            )
        )

        XCTAssertNotEqual(fallbackArtwork.pngData(), avatarArtwork.pngData())
        XCTAssertEqual(avatarArtwork.size, CGSize(width: 360, height: 640))
    }

    func testLikeMutationUpdatesTheVisibleCountAndCanUndo() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "local-activity"

        let didLike = await store.toggleActivityLike(activityID: activityID, backend: nil)
        XCTAssertTrue(didLike)
        XCTAssertEqual(
            store.activityEngagement(for: activityID),
            ActivityEngagementSummary(
                activityID: activityID,
                likeCount: 1,
                viewerHasLiked: true
            )
        )

        let didUnlike = await store.toggleActivityLike(activityID: activityID, backend: nil)
        XCTAssertTrue(didUnlike)
        XCTAssertEqual(store.activityEngagement(for: activityID), .empty(activityID: activityID))
    }

    func testFailedRemoteLikeRollsBackTheOptimisticCount() async {
        let activityID = "1efed494-8157-4ae9-9788-c605c3138214"
        let repository = ActivityEngagementRepositoryStub(setLikeError: ActivityEngagementTestError.expected)
        let store = WanderStore(fixtures: .empty())

        let succeeded = await store.toggleActivityLike(
            activityID: activityID,
            backend: WanderBackend(activityEngagementRepository: repository)
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(store.activityEngagement(for: activityID), .empty(activityID: activityID))
        XCTAssertNotNil(store.activityEngagementError(for: activityID))
    }

    func testLocalCommentAddsOneCommentAndOneVisibleCount() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "local-comment-activity"

        let didAddComment = await store.addActivityComment(
            activityID: activityID,
            body: "  Meet me on the patio.  ",
            backend: nil
        )
        XCTAssertTrue(didAddComment)

        XCTAssertEqual(store.activityComments(for: activityID).map(\.body), ["Meet me on the patio."])
        XCTAssertEqual(store.activityEngagement(for: activityID).commentCount, 1)
        XCTAssertFalse(try XCTUnwrap(store.activityComments(for: activityID).first).isPending)
    }

    func testDeletingOwnCommentOptimisticallyRemovesItAndUsesRemoteCount() async throws {
        let store = WanderStore(fixtures: .empty())
        let activityID = "40000000-0000-0000-0000-000000000101"
        let comment = activityComment(
            id: "50000000-0000-0000-0000-000000000101",
            activityID: activityID,
            authorID: store.currentUser.id,
            relationship: .owner
        )
        let repository = ActivityEngagementRepositoryStub(
            commentsPage: ActivityCommentsPage(
                comments: [comment],
                nextCursor: nil,
                engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
            ),
            deleteResult: .empty(activityID: activityID)
        )
        let backend = WanderBackend(activityEngagementRepository: repository)
        let didRefresh = await store.refreshActivityComments(activityID: activityID, backend: backend)
        XCTAssertTrue(didRefresh)

        let didDelete = await store.deleteActivityComment(comment, backend: backend)

        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.activityComments(for: activityID).isEmpty)
        XCTAssertEqual(store.activityEngagement(for: activityID).commentCount, 0)
        XCTAssertEqual(repository.deletedCommentIDs, [comment.id])
    }

    func testFailedRemoteCommentDeleteRestoresRowAndCount() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "40000000-0000-0000-0000-000000000102"
        let comment = activityComment(
            id: "50000000-0000-0000-0000-000000000102",
            activityID: activityID,
            authorID: store.currentUser.id,
            relationship: .owner
        )
        let repository = ActivityEngagementRepositoryStub(
            commentsPage: ActivityCommentsPage(
                comments: [comment],
                nextCursor: nil,
                engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
            ),
            deleteError: ActivityEngagementTestError.expected
        )
        let backend = WanderBackend(activityEngagementRepository: repository)
        let didRefresh = await store.refreshActivityComments(activityID: activityID, backend: backend)
        XCTAssertTrue(didRefresh)

        let didDelete = await store.deleteActivityComment(comment, backend: backend)

        XCTAssertFalse(didDelete)
        XCTAssertEqual(store.activityComments(for: activityID), [comment])
        XCTAssertEqual(store.activityEngagement(for: activityID).commentCount, 1)
        XCTAssertNotNil(store.activityEngagementError(for: activityID))
    }

    func testCommentDeleteIsUnavailableForAnotherAuthor() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "40000000-0000-0000-0000-000000000103"
        let comment = activityComment(
            id: "50000000-0000-0000-0000-000000000103",
            activityID: activityID,
            authorID: "user_friend",
            relationship: .follower
        )
        let repository = ActivityEngagementRepositoryStub(
            commentsPage: ActivityCommentsPage(
                comments: [comment],
                nextCursor: nil,
                engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
            )
        )
        let backend = WanderBackend(activityEngagementRepository: repository)
        let didRefresh = await store.refreshActivityComments(activityID: activityID, backend: backend)
        XCTAssertTrue(didRefresh)

        XCTAssertFalse(store.canDeleteActivityComment(comment))
        let didDelete = await store.deleteActivityComment(comment, backend: backend)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(store.activityComments(for: activityID), [comment])
        XCTAssertTrue(repository.deletedCommentIDs.isEmpty)
    }

    func testPlaceHistoryResolvesExplicitVisitBeforeParentEvent() async {
        let userPlaceID = "a0959fde-2e2b-40ae-9969-88d0983a5bc8"
        let visitID = "a940b2a4-605d-48d3-a5cd-b23d230b00ce"
        let parentActivity = PlaceActivityEngagementMatch(
            activityID: "a8778202-9fc3-4819-a66a-70bec42cd038",
            userPlaceID: userPlaceID,
            visitID: nil,
            kind: .placeBeen,
            occurredAt: Date(timeIntervalSince1970: 100),
            engagement: .empty(activityID: "a8778202-9fc3-4819-a66a-70bec42cd038")
        )
        let visitActivity = PlaceActivityEngagementMatch(
            activityID: "3223700f-cefc-4593-867e-d97f5830f428",
            userPlaceID: userPlaceID,
            visitID: visitID,
            kind: .placeBeen,
            occurredAt: Date(timeIntervalSince1970: 200),
            engagement: ActivityEngagementSummary(
                activityID: "3223700f-cefc-4593-867e-d97f5830f428",
                likeCount: 5,
                commentCount: 2
            )
        )
        let repository = ActivityEngagementRepositoryStub(
            placeMatches: [parentActivity, visitActivity]
        )
        let store = WanderStore(fixtures: .empty())

        await store.refreshPlaceActivityEngagement(
            userPlaceIDs: [userPlaceID],
            backend: WanderBackend(activityEngagementRepository: repository)
        )

        let resolved = store.placeActivityEngagementMatch(
            userPlaceID: userPlaceID,
            visitID: visitID,
            preferredKinds: [.placeBeen]
        )
        XCTAssertEqual(resolved, visitActivity)
        XCTAssertEqual(store.activityEngagement(for: visitActivity.activityID).likeCount, 5)
        XCTAssertEqual(store.activityEngagement(for: visitActivity.activityID).commentCount, 2)

        let resolvedWithoutMaterializedVisit = store.placeActivityEngagementMatch(
            userPlaceID: userPlaceID,
            visitID: nil,
            preferredKinds: [.placeBeen]
        )
        XCTAssertEqual(resolvedWithoutMaterializedVisit, visitActivity)
    }

    func testEngagementContextUsesCheckInAndWannaLanguage() {
        let actor = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Judy",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let checkIn = ActivityEngagementContext(
            activityID: "check-in",
            actor: actor,
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            status: .been,
            occurredAt: .now
        )
        let wanna = ActivityEngagementContext(
            activityID: "wanna",
            actor: actor,
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            status: .wannaGo,
            occurredAt: .now
        )

        XCTAssertEqual(checkIn.actionTitle, "checked in at")
        XCTAssertEqual(wanna.actionTitle, "added to Wanna")
        XCTAssertTrue(checkIn.shareMessage.contains("Judy's check-in at Ada Street"))
        XCTAssertTrue(wanna.shareMessage.contains("Judy's Wanna pick Ada Street"))

        let list = ActivityEngagementContext(
            activityID: "list",
            actor: actor,
            placeName: "Best of Chicago",
            placeServerID: nil,
            placeDetail: "12 places",
            ticketKind: .list,
            occurredAt: .now
        )
        XCTAssertEqual(list.actionTitle, "saved to")
        XCTAssertTrue(list.shareMessage.contains("list activity"))
    }

    func testCommentsContextPreservesNoteAndPhotosForEveryTicketKind() {
        let actor = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Judy",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let media = [
            ActivityEngagementMedia(
                id: "photo-1",
                urlString: "https://example.com/one.jpg",
                accessibilityLabel: "First activity photo"
            ),
            ActivityEngagementMedia(
                id: "photo-2",
                localAssetRef: "local_file:two.jpg",
                accessibilityLabel: "Second activity photo"
            ),
        ]

        for ticketKind in [FeedTicketKind.checkIn, .wanna, .list] {
            let context = ActivityEngagementContext(
                activityID: "activity-\(ticketKind)",
                actor: actor,
                placeName: "Ada Street",
                placeServerID: nil,
                placeDetail: "Restaurant · Chicago, IL",
                ticketKind: ticketKind,
                occurredAt: .now,
                note: "  Found god.  ",
                media: media
            )

            XCTAssertEqual(context.note, "Found god.")
            XCTAssertEqual(context.media, media)

            let coordinator = ActivityNavigationCoordinator()
            coordinator.openComments(context: context, visiblePlace: nil)
            XCTAssertEqual(coordinator.commentsRoute?.context?.note, "Found god.")
            XCTAssertEqual(coordinator.commentsRoute?.context?.media, media)
        }
    }

    func testCommentsContextCollapsesMissingNoteAndPhotos() {
        let context = ActivityEngagementContext(
            activityID: "empty-content",
            actor: ProfileShell(
                id: "user_friend",
                handle: "friend",
                displayName: "Judy",
                avatarURL: nil,
                bio: nil,
                relationship: .follower
            ),
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            ticketKind: .checkIn,
            occurredAt: .now,
            note: "  \n ",
            media: []
        )

        XCTAssertNil(context.note)
        XCTAssertTrue(context.media.isEmpty)
    }

    func testActivityNavigationKeepsExactTicketIdentityUntilDismissal() {
        let coordinator = ActivityNavigationCoordinator()
        let activityID = "40000000-0000-0000-0000-000000000001"

        coordinator.openComments(activityID: activityID)
        let requestID = coordinator.commentsRoute?.id
        XCTAssertEqual(coordinator.commentsRoute?.activityID, activityID)
        XCTAssertNil(coordinator.commentsRoute?.context)

        coordinator.dismiss(requestID: try! XCTUnwrap(requestID))
        XCTAssertNil(coordinator.commentsRoute)
    }

    func testFeedRefreshPreservesAnExactActivityLoadedForComments() async {
        let exactActivityID = "40000000-0000-0000-0000-000000000001"
        let pageActivityID = "40000000-0000-0000-0000-000000000002"
        let actor = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Friend",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let exactActivity = FeedActivity(
            id: exactActivityID,
            kind: .placeBeen,
            actor: actor,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let refreshedActivity = FeedActivity(
            id: pageActivityID,
            kind: .placeWannaGo,
            actor: actor,
            occurredAt: Date(timeIntervalSince1970: 200)
        )
        let feedRepository = SuspendedActivityFeedRepository(
            page: FollowedFeedPage(
                activity: [refreshedActivity],
                featuredPlaces: [],
                nextCursor: nil,
                fetchedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let activityRepository = ActivityEngagementRepositoryStub(activityResult: exactActivity)
        let backend = WanderBackend(
            feedRepository: feedRepository,
            activityEngagementRepository: activityRepository
        )
        let store = WanderStore(fixtures: .empty())

        let refresh = Task { @MainActor in
            await store.refreshFollowedFeed(
                backend: backend,
                preservingActivityID: exactActivityID
            )
        }
        for _ in 0..<20 where feedRepository.requestCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(feedRepository.requestCount, 1)

        let resolvedActivity = await store.activity(id: exactActivityID, backend: backend)
        XCTAssertEqual(resolvedActivity?.id, exactActivityID)

        feedRepository.finish()
        let didRefresh = await refresh.value
        XCTAssertTrue(didRefresh)
        XCTAssertEqual(
            store.followedFeedPage?.activity.map(\.id),
            [pageActivityID, exactActivityID]
        )
    }

    func testExactActivityResolutionCanRetryAfterATransientFailure() async {
        let activityID = "40000000-0000-0000-0000-000000000003"
        let activity = FeedActivity(
            id: activityID,
            kind: .placeBeen,
            actor: ProfileShell(
                id: "user_friend",
                handle: "friend",
                displayName: "Friend",
                avatarURL: nil,
                bio: nil,
                relationship: .follower
            ),
            occurredAt: .now
        )
        let repository = ActivityEngagementRepositoryStub(
            activityResponses: [
                .failure(ActivityEngagementTestError.expected),
                .success(activity)
            ]
        )
        let backend = WanderBackend(activityEngagementRepository: repository)
        let store = WanderStore(fixtures: .empty())

        let firstResolution = await store.activity(id: activityID, backend: backend)
        XCTAssertNil(firstResolution)
        XCTAssertNotNil(store.activityEngagementError(for: activityID))

        let retriedResolution = await store.activity(id: activityID, backend: backend)
        XCTAssertEqual(retriedResolution?.id, activityID)
        XCTAssertNil(store.activityEngagementError(for: activityID))
    }

    func testExactActivityRefreshesCachedFeedTicketToLoadPhotos() async {
        let activityID = "40000000-0000-0000-0000-000000000004"
        let actor = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Friend",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let cachedActivity = FeedActivity(
            id: activityID,
            kind: .placeBeen,
            actor: actor,
            occurredAt: .now,
            note: "A cached note",
            media: []
        )
        let exactActivity = FeedActivity(
            id: activityID,
            kind: .placeBeen,
            actor: actor,
            occurredAt: cachedActivity.occurredAt,
            note: cachedActivity.note,
            media: [
                FeedMediaPreview(
                    id: "photo_1",
                    urlString: "https://example.com/signed-photo.jpg",
                    accessibilityLabel: "Activity photo"
                )
            ]
        )
        let feedRepository = SuspendedActivityFeedRepository(
            page: FollowedFeedPage(
                activity: [cachedActivity],
                featuredPlaces: [],
                nextCursor: nil,
                fetchedAt: .now
            )
        )
        feedRepository.finish()
        let activityRepository = ActivityEngagementRepositoryStub(activityResult: exactActivity)
        let backend = WanderBackend(
            feedRepository: feedRepository,
            activityEngagementRepository: activityRepository
        )
        let store = WanderStore(fixtures: .empty())
        let didRefresh = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(didRefresh)

        let resolved = await store.activity(id: activityID, backend: backend)

        XCTAssertEqual(resolved?.media.map(\.id), ["photo_1"])
        XCTAssertEqual(store.followedFeedPage?.activity.first?.media.map(\.id), ["photo_1"])
        XCTAssertEqual(activityRepository.activityRequestCount, 1)
    }

    private func activityComment(
        id: String,
        activityID: String,
        authorID: String,
        relationship: ViewerRelationship
    ) -> ActivityComment {
        ActivityComment(
            id: id,
            activityID: activityID,
            author: ProfileShell(
                id: authorID,
                handle: "commenter",
                displayName: "Commenter",
                avatarURL: nil,
                bio: nil,
                relationship: relationship
            ),
            body: "Worth remembering.",
            createdAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private enum ActivityEngagementTestError: Error {
    case expected
}

@MainActor
private final class ActivityEngagementRepositoryStub: ActivityEngagementRepository {
    let placeMatches: [PlaceActivityEngagementMatch]
    let setLikeError: Error?
    let commentsPage: ActivityCommentsPage?
    let deleteResult: ActivityEngagementSummary?
    let deleteError: Error?
    private(set) var activityRequestCount = 0
    private(set) var deletedCommentIDs: [String] = []
    private var activityResponses: [Result<FeedActivity, Error>]

    init(
        placeMatches: [PlaceActivityEngagementMatch] = [],
        setLikeError: Error? = nil,
        commentsPage: ActivityCommentsPage? = nil,
        deleteResult: ActivityEngagementSummary? = nil,
        deleteError: Error? = nil,
        activityResult: FeedActivity? = nil,
        activityResponses: [Result<FeedActivity, Error>]? = nil
    ) {
        self.placeMatches = placeMatches
        self.setLikeError = setLikeError
        self.commentsPage = commentsPage
        self.deleteResult = deleteResult
        self.deleteError = deleteError
        self.activityResponses = activityResponses
            ?? activityResult.map { [.success($0)] }
            ?? []
    }

    func activity(id: String) async throws -> FeedActivity {
        activityRequestCount += 1
        guard !activityResponses.isEmpty else {
            throw ActivityEngagementTestError.expected
        }
        let activityResult = try activityResponses.removeFirst().get()
        guard activityResult.id == id else { throw ActivityEngagementTestError.expected }
        return activityResult
    }

    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] {
        activityIDs.map(ActivityEngagementSummary.empty(activityID:))
    }

    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] {
        placeMatches.filter { userPlaceIDs.contains($0.userPlaceID) }
    }

    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary {
        if let setLikeError { throw setLikeError }
        return ActivityEngagementSummary(
            activityID: activityID,
            likeCount: isLiked ? 1 : 0,
            viewerHasLiked: isLiked
        )
    }

    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        commentsPage ?? ActivityCommentsPage(
            comments: [],
            nextCursor: nil,
            engagement: .empty(activityID: activityID)
        )
    }

    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        let comment = ActivityComment(
            id: UUID().uuidString.lowercased(),
            activityID: activityID,
            author: ProfileShell(
                id: "user_current",
                handle: "current",
                displayName: "Current",
                avatarURL: nil,
                bio: nil,
                relationship: .owner
            ),
            body: body,
            createdAt: .now
        )
        return ActivityCommentPostResult(
            comment: comment,
            engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
        )
    }

    func deleteComment(commentID: String) async throws -> ActivityEngagementSummary {
        deletedCommentIDs.append(commentID)
        if let deleteError { throw deleteError }
        guard let deleteResult else { throw ActivityEngagementTestError.expected }
        return deleteResult
    }
}

@MainActor
private final class SuspendedActivityFeedRepository: FeedRepository {
    private let page: FollowedFeedPage
    private var isSuspended = true
    private(set) var requestCount = 0

    init(page: FollowedFeedPage) {
        self.page = page
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        requestCount += 1
        while isSuspended {
            await Task.yield()
        }
        return page
    }

    func finish() {
        isSuspended = false
    }
}
