import Combine
import Photos
import UIKit
import XCTest
@testable import Wander

@MainActor
final class ActivityEngagementTests: XCTestCase {
    func testPostcardUploadedMediaUsesProtectedStorageIdentityEvenWithLegacyURL() {
        let media = ActivityEngagementMedia(id: "photo", urlString: "https://example.com/old-signed.jpg",
            localAssetRef: "local_file:old.jpg", storageBucket: "visit-photos",
            storagePath: "owner/place/visit/photo.jpg", accessibilityLabel: "Photo")
        XCTAssertTrue(media.placePhoto.requiresAccessCheck)
        XCTAssertEqual(media.placePhoto.storagePath, "owner/place/visit/photo.jpg")
    }

    func testPostcardPendingOwnerCaptureRemainsAvailableOffline() {
        let media = ActivityEngagementMedia(id: "photo", localAssetRef: "local_file:pending.jpg",
            storageBucket: "visit-photos", storagePath: "owner/visit/pending.jpg",
            isPendingLocalCapture: true, accessibilityLabel: "Photo")
        XCTAssertFalse(media.placePhoto.requiresAccessCheck)
    }

    func testPostcardArtworkWaitsForVerifiedActivityMedia() {
        XCTAssertFalse(
            ActivityPostcardArtworkPolicy.showsPlacePhoto(
                hasVisiblePlace: true,
                mediaCount: 1
            ),
            "A pending or resolved activity-media item must suppress the unrelated place fallback"
        )
        XCTAssertFalse(
            ActivityPostcardArtworkPolicy.showsDecorativeFallback(
                hasVisiblePlace: true,
                mediaCount: 1
            )
        )
        XCTAssertTrue(
            ActivityPostcardArtworkPolicy.showsPlacePhoto(
                hasVisiblePlace: true,
                mediaCount: 0
            ),
            "The verified no-activity-photo result may use the place photo"
        )
    }

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
            "https://astirmovement.com/share/tiktok"
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

    func testInstagramPostExplainsFullAccessOnceBeforeDirectSharing() {
        XCTAssertEqual(
            ActivityShareInstagramPhotoAccessGuidance.action(
                hasAcknowledgedFullAccess: false
            ),
            .showPhotoAccessGuidance
        )
        XCTAssertEqual(
            ActivityShareInstagramPhotoAccessGuidance.action(
                hasAcknowledgedFullAccess: true
            ),
            .openDirectEditor
        )
        XCTAssertEqual(
            ActivityShareInstagramPhotoAccessGuidance.settingsPath,
            "Settings → Apps → Instagram → Photos → Full Access"
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
                message: "Sign in to the TikTok account enabled for this Astir sandbox, then try again."
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
            URL(string: "https://astirmovement.com/activities/\(activityID)")!,
            fileURL,
        ])
        XCTAssertTrue(content.messageBody.contains("https://astirmovement.com/activities/\(activityID)"))
        XCTAssertFalse(content.messageBody.contains(WanderShareContent.publicTestFlightURL.absoluteString))
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

    func testShareCardCopyAndDatesFollowApprovedVariants() {
        let profile = ShareCardContent(kind: .profile, name: "Ryan Lieblein", ownerName: "Ryan Lieblein", detail: "@ryan")
        XCTAssertEqual(profile.headline, "Discover Ryan’s world")
        XCTAssertNil(profile.subtitle)
        let invitation = ShareCardContent(kind: .invitation, name: "Good nights, great tables", ownerName: "Ryan Lieblein", count: 4)
        XCTAssertNil(invitation.subtitle)
        XCTAssertEqual(invitation.action, "Join")
        XCTAssertEqual(ShareCardContent(kind: .list, name: "A long list name with many places", count: 4).action, "View")
        var wanna = ShareCardContent(kind: .wanna, name: "Bar Chelou", ownerName: "Ryan Lieblein")
        XCTAssertEqual(wanna.subtitle, "Bar Chelou · On Ryan’s radar")
        XCTAssertEqual(wanna.action, "Let’s Go")
        wanna.date = Date(timeIntervalSince1970: 1_789_754_400)
        XCTAssertEqual(wanna.subtitle, "Bar Chelou · \(wanna.dateLabel!)")
        XCTAssertFalse(wanna.socialTitle.contains("radar"))
        wanna.date = nil
        XCTAssertEqual(wanna.socialTitle, "On Ryan’s radar.")
    }

    func testShareCardWannaDateUsesExactEventAndRespectsExplicitlyUndatedRepeats() {
        let date = Date(timeIntervalSince1970: 1_789_754_400)
        let context = ActivityEngagementContext(activityID: "event-a",
            actor: ProfileShell(id: "user", handle: "ryan", displayName: "Ryan", avatarURL: nil, bio: nil, relationship: .owner),
            placeName: "Bar Chelou", placeServerID: nil, placeDetail: "Pasadena", status: .wannaGo,
            occurredAt: date, plannedDate: date)
        let other = PlaceWannaSave(id: "event-b", ownerID: "user", userPlaceID: "parent", occurredAt: date,
            visibility: .followers, plannedDate: date.addingTimeInterval(86_400), attributeAnswersJSON: "[]")
        var exact = PlaceWannaSave(id: "EVENT-A", ownerID: "user", userPlaceID: "parent", occurredAt: date,
            visibility: .followers, plannedDate: nil, attributeAnswersJSON: "[]")
        XCTAssertEqual(context.shareCard(resolving: [other]).date, date)
        XCTAssertNil(context.shareCard(resolving: [other, exact]).date)
        exact.plannedDate = date.addingTimeInterval(172_800)
        XCTAssertEqual(context.shareCard(resolving: [other, exact]).date, exact.plannedDate)
    }

    func testShareCardFormatsExportCorrectPixelDimensions() throws {
        for format in ShareCardFormat.allCases {
            let image = try XCTUnwrap(ShareCardRenderer.render(
                ShareCardContent(kind: .list, name: "An empty list", ownerName: "Ryan"),
                images: ShareCardImages(), format: format))
            XCTAssertEqual(image.cgImage?.width, Int(format.size.width * 3))
            XCTAssertEqual(image.cgImage?.height, Int(format.size.height * 3))
            XCTAssertNotNil(image.pngData())
        }
    }

    func testListCollageUsesSecondPlaceOnlyWhenAtLeastTwoPlacesExist() throws {
        func photo(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image {
                color.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        }
        let first = photo(.red)
        let second = photo(.blue)
        for count in 0...4 {
            let card = ShareCardContent(kind: .list, name: "Favorites", ownerName: "Ryan", count: count)
            let one = try XCTUnwrap(ShareCardRenderer.render(card, images: ShareCardImages(photos: [first, nil])))
            let two = try XCTUnwrap(ShareCardRenderer.render(card, images: ShareCardImages(photos: [first, second])))
            if count < 2 { XCTAssertEqual(one.pngData(), two.pngData()) }
            else { XCTAssertNotEqual(one.pngData(), two.pngData()) }
        }
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

    func testEngagementRefreshPublishesAConstantNumberOfStoreChanges() async {
        let activityIDs = (0..<25).map {
            String(format: "40000000-0000-0000-0000-%012d", $0)
        }
        let summaries = activityIDs.enumerated().map { index, activityID in
            ActivityEngagementSummary(
                activityID: activityID,
                likeCount: index,
                commentCount: index / 2
            )
        }
        let repository = ActivityEngagementRepositoryStub(summariesResult: summaries)
        let store = WanderStore(fixtures: .empty())
        var publicationCount = 0
        let observation = store.objectWillChange.sink {
            publicationCount += 1
        }

        await store.refreshActivityEngagement(
            activityIDs: activityIDs,
            backend: WanderBackend(activityEngagementRepository: repository)
        )

        withExtendedLifetime(observation) {}
        XCTAssertLessThanOrEqual(publicationCount, 2)
        XCTAssertEqual(store.activityEngagement(for: activityIDs[0]).likeCount, 0)
        XCTAssertEqual(store.activityEngagement(for: activityIDs[24]).likeCount, 24)
    }

    func testPerformanceFixtureBuildsPopulatedFeedAndReusesBookmarkIndex() async throws {
        let store = WanderStore(fixtures: WanderFixtures.performanceScale())

        let didRefresh = await store.refreshFollowedFeed(backend: nil)
        XCTAssertTrue(didRefresh)
        let page = try XCTUnwrap(store.followedFeedPage)

        XCTAssertEqual(page.activity.count, 25)
        XCTAssertEqual(page.featuredPlaces.count, 8)
        XCTAssertEqual(page.activity.first?.id, "perf-feed-000")
        XCTAssertEqual(page.activity.last?.id, "perf-feed-024")
        XCTAssertEqual(page.activity.compactMap(\.place).count, 20)

        for _ in 0..<5 {
            for visiblePlace in page.activity.compactMap(\.place) {
                XCTAssertEqual(store.activityBookmarkState(for: visiblePlace), .notSaved)
            }
        }
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, 1)

        let ownPlace = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let expectedState: ActivityBookmarkState = ownPlace.userPlace.status == .wannaGo
            ? .wanna
            : .checkedIn
        XCTAssertEqual(store.activityBookmarkState(for: ownPlace), expectedState)
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, 1)
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

    func testDeletingOwnCommentAfterHiddenBlockedCommentRemovesCorrectRow() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = UUID().uuidString
        let hidden = activityComment(id: UUID().uuidString, activityID: activityID,
                                     authorID: "blocked_author", relationship: .follower)
        let own = activityComment(id: UUID().uuidString, activityID: activityID,
                                  authorID: store.currentUser.id, relationship: .owner)
        let repository = ActivityEngagementRepositoryStub(
            commentsPage: ActivityCommentsPage(comments: [hidden, own], nextCursor: nil,
                                              engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 2)),
            deleteResult: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
        )
        let backend = WanderBackend(activityEngagementRepository: repository)
        _ = await store.refreshActivityComments(activityID: activityID, backend: backend)
        store.block(userID: hidden.author.id)
        XCTAssertEqual(store.activityComments(for: activityID), [own])

        let deleted = await store.deleteActivityComment(own, backend: backend)

        XCTAssertTrue(deleted)
        XCTAssertTrue(store.activityComments(for: activityID).isEmpty)
        XCTAssertEqual(repository.deletedCommentIDs, [own.id])
        store.unblock(userID: hidden.author.id)
        XCTAssertEqual(store.activityComments(for: activityID), [hidden])
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

    func testPlaceHistoryMatchesUUIDsRegardlessOfCase() async {
        let parentID = "A0959FDE-2E2B-40AE-9969-88D0983A5BC8"
        let visitID = "A940B2A4-605D-48D3-A5CD-B23D230B00CE"
        let match = PlaceActivityEngagementMatch(
            activityID: "a8778202-9fc3-4819-a66a-70bec42cd038",
            userPlaceID: parentID.lowercased(), visitID: visitID.lowercased(),
            kind: .placeBeen, occurredAt: .now,
            engagement: .empty(activityID: "a8778202-9fc3-4819-a66a-70bec42cd038")
        )
        let store = WanderStore(fixtures: .empty())
        await store.refreshPlaceActivityEngagement(
            userPlaceIDs: [parentID],
            backend: WanderBackend(activityEngagementRepository: ActivityEngagementRepositoryStub(placeMatches: [match]))
        )
        XCTAssertEqual(store.placeActivityEngagementMatch(
            userPlaceID: parentID, visitID: visitID, preferredKinds: [.placeBeen]
        ), match)
        XCTAssertNil(store.placeActivityEngagementMatch(
            userPlaceID: parentID, visitID: UUID().uuidString, preferredKinds: [.placeBeen]
        ), "A missing or deleted repeat visit must never borrow another visit's conversation")
    }

    func testPlaceHistoryEngagementRetriesAndClearsLoadingError() async {
        let id = "a0959fde-2e2b-40ae-9969-88d0983a5bc8"
        let match = PlaceActivityEngagementMatch(activityID: UUID().uuidString,
            userPlaceID: id, visitID: UUID().uuidString, kind: .placeBeen,
            occurredAt: .now, engagement: .empty(activityID: "test"))
        let repository = ActivityEngagementRepositoryStub(placeMatches: [match])
        repository.placeFailuresRemaining = 1
        let store = WanderStore(fixtures: .empty())
        let backend = WanderBackend(activityEngagementRepository: repository)
        await store.refreshPlaceActivityEngagement(userPlaceIDs: [id], backend: backend)
        XCTAssertTrue(store.placeActivityEngagementMatches.isEmpty)
        XCTAssertNotNil(store.activityEngagementError(for: "user-place:\(id)"))
        await store.refreshPlaceActivityEngagement(userPlaceIDs: [id], backend: backend)
        XCTAssertEqual(store.placeActivityEngagementMatches, [match])
        XCTAssertNil(store.activityEngagementError(for: "user-place:\(id)"))
    }

    func testPlaceHistoryEngagementBatchesWithinRPCLimit() async {
        let repository = ActivityEngagementRepositoryStub()
        let ids = (0..<201).map { _ in UUID().uuidString }
        await WanderStore(fixtures: .empty()).refreshPlaceActivityEngagement(
            userPlaceIDs: ids + ids,
            backend: WanderBackend(activityEngagementRepository: repository)
        )
        XCTAssertEqual(repository.placeRequests.map(\.count), [100, 100, 1])
        XCTAssertEqual(Set(repository.placeRequests.flatMap { $0 }), Set(ids.map { $0.lowercased() }))
    }

    func testPlaceHistoryEngagementDiscardsAccountChangesAndCancellation() async {
        for changesAccount in [false, true] {
            let parentID = UUID().uuidString.lowercased()
            let repository = ActivityEngagementRepositoryStub(placeMatches: [
                PlaceActivityEngagementMatch(activityID: UUID().uuidString,
                    userPlaceID: parentID, visitID: UUID().uuidString, kind: .placeBeen,
                    occurredAt: .now, engagement: .empty(activityID: "test"))
            ])
            repository.suspendPlaceRequests = true
            let store = WanderStore(fixtures: .empty())
            let task = Task { @MainActor in
                await store.refreshPlaceActivityEngagement(userPlaceIDs: [parentID],
                    backend: WanderBackend(activityEngagementRepository: repository))
            }
            for _ in 0..<100 where repository.placeRequests.isEmpty { await Task.yield() }
            XCTAssertFalse(repository.placeRequests.isEmpty)
            if changesAccount {
                store.apply(authState: .signedOut)
                store.apply(authState: .signedIn(AuthSession(userID: "new_account", displayName: "New", handle: "new")))
            } else {
                task.cancel()
            }
            repository.suspendPlaceRequests = false
            await task.value
            XCTAssertTrue(store.placeActivityEngagementMatches.isEmpty)
        }
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
            occurredAt: .now,
            rating: 4.5,
            listContext: ActivityEngagementListContext(id: "list-chicago", name: "Best of Chicago")
        )
        XCTAssertEqual(list.actionTitle, "saved to")
        XCTAssertTrue(list.shareMessage.contains("list activity"))
        XCTAssertEqual(list.rating, 4.5)
        XCTAssertEqual(list.listContext, ActivityEngagementListContext(id: "list-chicago", name: "Best of Chicago"))
    }

    func testWannaBadgeOpticallyMatchesTheAllCapsTicketBadges() {
        XCTAssertEqual(ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: .wanna), 12)
        XCTAssertEqual(ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: .checkIn), 10)
        XCTAssertEqual(ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: .list), 10)
        XCTAssertEqual(ActivityPostcardTypographyPolicy.ticketBadgeFontSize(for: .saved), 10)
    }

    func testCommentsContextPreservesPostcardFieldsForEveryTicketKind() {
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
                rating: 4.5,
                media: media
            )

            XCTAssertEqual(context.note, "Found god.")
            XCTAssertEqual(context.media, media)

            let coordinator = ActivityNavigationCoordinator()
            coordinator.openComments(context: context, visiblePlace: nil)
            XCTAssertEqual(coordinator.commentsRoute?.context?.note, "Found god.")
            XCTAssertEqual(coordinator.commentsRoute?.context?.media, media)
            XCTAssertEqual(coordinator.commentsRoute?.context?.rating, 4.5)
            XCTAssertEqual(coordinator.commentsRoute?.context?.placeName, context.placeName)
            XCTAssertEqual(coordinator.commentsRoute?.context?.placeDetail, context.placeDetail)
            XCTAssertEqual(coordinator.commentsRoute?.context?.actor, actor)
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
            place: privacyActivity(ownerID: actor.id, visibility: .followers).place,
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
        let activityRepository = ActivityEngagementRepositoryStub(
            activityResponses: [.success(exactActivity), .success(exactActivity)]
        )
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
            place: privacyActivity(ownerID: "user_friend", visibility: .followers).place,
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
        let place = privacyActivity(ownerID: actor.id, visibility: .followers).place
        let cachedActivity = FeedActivity(
            id: activityID,
            kind: .placeBeen,
            actor: actor,
            place: place,
            occurredAt: .now,
            note: "A cached note",
            media: []
        )
        let exactActivity = FeedActivity(
            id: activityID,
            kind: .placeBeen,
            actor: actor,
            place: place,
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

    func testFeedRejectsOtherUsersStealthSaveAndFeaturedAttribution() async {
        let store = WanderStore(fixtures: .empty())
        let stealth = privacyActivity(ownerID: "friend", visibility: .selfOnly)
        let own = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let shared = privacyActivity(ownerID: "friend", visibility: .followers)
        let repository = SuspendedActivityFeedRepository(page: FollowedFeedPage(
            activity: [stealth, own, shared],
            featuredPlaces: [FeedFeaturedPlace(visiblePlace: stealth.place!, actor: stealth.actor, reason: "Private attribution")],
            nextCursor: "next", fetchedAt: .now
        ))
        repository.finish()
        let refreshed = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertTrue(refreshed)
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), [own.id, shared.id])
        XCTAssertTrue(store.followedFeedPage?.featuredPlaces.isEmpty == true)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "next")
    }

    func testExactStealthActivityIsVisibleOnlyToOwner() async {
        let store = WanderStore(fixtures: .empty())
        let own = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let other = privacyActivity(ownerID: "friend", visibility: .selfOnly)
        let repository = ActivityEngagementRepositoryStub(activityResponses: [.success(own), .success(other)])
        let backend = WanderBackend(activityEngagementRepository: repository)
        let ownResult = await store.activity(id: own.id, backend: backend)
        XCTAssertEqual(ownResult?.id, own.id)
        let otherResult = await store.activity(id: other.id, backend: backend)
        XCTAssertNil(otherResult)
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), [own.id])
    }

    func testExactActivityAllowsOfflineCacheButNeverResurrectsAfterDenial() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: "friend", visibility: .followers)
        let repository = ActivityEngagementRepositoryStub(activityResponses: [
            .success(activity), .failure(URLError(.notConnectedToInternet)),
            .failure(WanderRemoteError.invalidResponse("activity_not_visible")),
            .failure(URLError(.notConnectedToInternet))
        ])
        let backend = WanderBackend(activityEngagementRepository: repository)
        let initial = await store.activity(id: activity.id, backend: backend)
        XCTAssertNotNil(initial)
        let offline = await store.activity(id: activity.id, backend: backend)
        XCTAssertEqual(offline?.id, activity.id)
        let denied = await store.activity(id: activity.id, backend: backend)
        XCTAssertNil(denied)
        let offlineAfterDenial = await store.activity(id: activity.id, backend: backend)
        XCTAssertNil(offlineAfterDenial)
    }

    func testCachedCheckInLinkUsesOnlyItsPreviouslyResolvedVisitWhileOffline() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: "friend", visibility: .followers)
        let parent = UUID().uuidString, visit = UUID().uuidString
        let repository = ActivityEngagementRepositoryStub(placeMatches: [
            PlaceActivityEngagementMatch(activityID: activity.id, userPlaceID: parent, visitID: visit,
                kind: .placeBeen, occurredAt: .now, engagement: .empty(activityID: activity.id))
        ], activityResponses: [.success(activity), .failure(URLError(.notConnectedToInternet))])
        let backend = WanderBackend(activityEngagementRepository: repository)
        let target = ActivityCheckInTarget(userPlaceID: parent, visitID: visit)
        let initial = await store.activity(checkIn: target, backend: backend)
        XCTAssertEqual(initial?.id, activity.id)
        repository.placeError = URLError(.notConnectedToInternet)
        let offline = await store.activity(checkIn: target, backend: backend)
        XCTAssertEqual(offline?.id, activity.id)
        let otherVisit = await store.activity(checkIn: .init(userPlaceID: parent, visitID: UUID().uuidString), backend: backend)
        XCTAssertNil(otherVisit)
        repository.placeError = WanderRemoteError.notAuthenticated
        let denied = await store.activity(checkIn: target, backend: backend)
        XCTAssertNil(denied)
        repository.placeError = URLError(.notConnectedToInternet)
        let reopened = await store.activity(checkIn: target, backend: backend)
        XCTAssertNil(reopened)
    }

    func testExactActivityFailureEvictsPreviouslyVisibleTicketAndAllowsRetry() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: "friend", visibility: .followers)
        let repository = ActivityEngagementRepositoryStub(activityResponses: [
            .success(activity), .failure(WanderRemoteError.invalidResponse("activity_not_visible")), .success(activity)
        ])
        let feedRepository = SuspendedActivityFeedRepository(page: FollowedFeedPage(
            activity: [activity],
            featuredPlaces: [FeedFeaturedPlace(visiblePlace: activity.place!, actor: activity.actor, reason: "Shared save")],
            nextCursor: nil, fetchedAt: .now
        ))
        feedRepository.finish()
        let backend = WanderBackend(feedRepository: feedRepository, activityEngagementRepository: repository)
        let refreshed = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(refreshed)
        let first = await store.activity(id: activity.id, backend: backend)
        XCTAssertNotNil(first)
        let denied = await store.activity(id: activity.id, backend: backend)
        XCTAssertNil(denied)
        XCTAssertTrue(store.followedFeedPage?.activity.isEmpty == true)
        XCTAssertTrue(store.followedFeedPage?.featuredPlaces.isEmpty == true)
        XCTAssertNil(store.activityEngagementByID[activity.id])
        let retry = await store.activity(id: activity.id, backend: backend)
        XCTAssertEqual(retry?.id, activity.id)
    }

    func testFeedRefreshDoesNotResurrectPinnedActivityAfterStealthRevocation() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: "friend", visibility: .followers)
        let activityRepository = ActivityEngagementRepositoryStub(activityResponses: [
            .success(activity), .failure(WanderRemoteError.invalidResponse("activity_not_visible"))
        ])
        let feedRepository = SuspendedActivityFeedRepository(page: FollowedFeedPage(
            activity: [], featuredPlaces: [], nextCursor: nil, fetchedAt: .now
        ))
        feedRepository.finish()
        let backend = WanderBackend(feedRepository: feedRepository, activityEngagementRepository: activityRepository)
        let initial = await store.activity(id: activity.id, backend: backend)
        XCTAssertNotNil(initial)
        let refreshed = await store.refreshFollowedFeed(backend: backend, preservingActivityID: activity.id)
        XCTAssertTrue(refreshed)
        XCTAssertTrue(store.followedFeedPage?.activity.isEmpty == true)
        XCTAssertEqual(activityRepository.activityRequestCount, 2)
    }

    func testExactActivityResponseCannotCrossAccountBoundary() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let repository = ActivityEngagementRepositoryStub(activityResult: activity, suspendActivity: true)
        let task = Task { @MainActor in
            let resolved = await store.activity(id: activity.id, backend: WanderBackend(activityEngagementRepository: repository))
            return resolved?.id
        }
        for _ in 0..<100 where repository.activityRequestCount == 0 { await Task.yield() }
        XCTAssertEqual(repository.activityRequestCount, 1)
        store.apply(authState: .signedOut)
        store.apply(authState: .signedIn(AuthSession(userID: "new_account", displayName: "New", handle: "new")))
        repository.finishActivity()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(store.followedFeedPage)
    }

    func testExactActivityDoesNotWaitForEngagementSummariesBeforeOpeningComments() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let repository = ActivityEngagementRepositoryStub(activityResult: activity, suspendSummaries: true)
        let resolved = await store.activity(
            id: activity.id, backend: WanderBackend(activityEngagementRepository: repository)
        )
        XCTAssertEqual(resolved?.id, activity.id)
        XCTAssertEqual(repository.summariesRequestCount, 0)
    }

    func testCheckInNotificationResolvesExactVisitWithoutFetchingFeedOrExtraSummaries() async throws {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let parent = UUID().uuidString.lowercased(), visit = UUID().uuidString.lowercased()
        let target = ActivityCheckInTarget(userPlaceID: parent.uppercased(), visitID: visit.uppercased())
        let matches = [
            PlaceActivityEngagementMatch(activityID: UUID().uuidString, userPlaceID: parent,
                visitID: UUID().uuidString, kind: .placeBeen, occurredAt: .now,
                engagement: .empty(activityID: "unrelated")),
            PlaceActivityEngagementMatch(activityID: activity.id, userPlaceID: parent,
                visitID: visit, kind: .placeBeen, occurredAt: .distantPast,
                engagement: .empty(activityID: activity.id))
        ]
        let repository = ActivityEngagementRepositoryStub(placeMatches: matches, activityResult: activity)
        let result = await store.activity(checkIn: target, backend: WanderBackend(activityEngagementRepository: repository))
        XCTAssertEqual(result?.id, activity.id)
        XCTAssertEqual(repository.placeRequests.count, 1)
        XCTAssertEqual(repository.activityRequestCount, 1)
        XCTAssertEqual(repository.summariesRequestCount, 0)
        let navigation = ActivityNavigationCoordinator()
        navigation.openCheckIn(userPlaceID: parent, visitID: visit)
        let requestID = try XCTUnwrap(navigation.commentsRoute?.id)
        navigation.resolve(requestID: requestID, activity: result)
        XCTAssertEqual(navigation.commentsRoute?.activityID, activity.id)
        XCTAssertEqual(navigation.commentsRoute?.context?.activityID, activity.id)
    }

    func testMissingCheckInNeverSubstitutesNewestVisitAndSurfacesError() async {
        let store = WanderStore(fixtures: .empty())
        let parent = UUID().uuidString, visit = UUID().uuidString
        let repository = ActivityEngagementRepositoryStub(placeMatches: [
            PlaceActivityEngagementMatch(activityID: UUID().uuidString, userPlaceID: parent,
                visitID: UUID().uuidString, kind: .placeBeen, occurredAt: .now,
                engagement: .empty(activityID: "other"))
        ])
        let result = await store.activity(checkIn: .init(userPlaceID: parent, visitID: visit),
            backend: WanderBackend(activityEngagementRepository: repository))
        XCTAssertNil(result)
        XCTAssertEqual(repository.activityRequestCount, 0)
        XCTAssertNotNil(store.activityEngagementError(for: visit))
    }

    func testCheckInLookupCannotFinishAfterAccountChangeOrCancellation() async {
        for changesAccount in [false, true] {
            let store = WanderStore(fixtures: .empty())
            let parent = UUID().uuidString, visit = UUID().uuidString
            let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
            let repository = ActivityEngagementRepositoryStub(placeMatches: [
                PlaceActivityEngagementMatch(activityID: activity.id, userPlaceID: parent,
                    visitID: visit, kind: .placeBeen, occurredAt: .now,
                    engagement: .empty(activityID: activity.id))
            ], activityResult: activity)
            repository.suspendPlaceRequests = true
            let task = Task { @MainActor in
                let result = await store.activity(checkIn: .init(userPlaceID: parent, visitID: visit),
                    backend: WanderBackend(activityEngagementRepository: repository))
                return result?.id
            }
            for _ in 0..<100 where repository.placeRequests.isEmpty { await Task.yield() }
            XCTAssertEqual(repository.placeRequests.count, 1)
            if changesAccount {
                store.apply(authState: .signedOut)
                store.apply(authState: .signedIn(AuthSession(userID: "another", displayName: "Another", handle: "another")))
            } else { task.cancel() }
            repository.suspendPlaceRequests = false
            let result = await task.value
            XCTAssertNil(result)
            XCTAssertEqual(repository.activityRequestCount, 0)
            XCTAssertNil(store.activityEngagementError(for: visit))
        }
    }

    func testCheckInLookupAndDetailErrorsStayVisibleAndRetryable() async {
        let store = WanderStore(fixtures: .empty())
        let parent = UUID().uuidString, visit = UUID().uuidString
        let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let repository = ActivityEngagementRepositoryStub(placeMatches: [
            PlaceActivityEngagementMatch(activityID: activity.id, userPlaceID: parent,
                visitID: visit, kind: .placeBeen, occurredAt: .now,
                engagement: .empty(activityID: activity.id))
        ], activityResponses: [.failure(ActivityEngagementTestError.expected), .success(activity)])
        repository.placeFailuresRemaining = 1
        let target = ActivityCheckInTarget(userPlaceID: parent, visitID: visit)
        let backend = WanderBackend(activityEngagementRepository: repository)
        let lookupFailure = await store.activity(checkIn: target, backend: backend)
        XCTAssertNil(lookupFailure)
        XCTAssertNotNil(store.activityEngagementError(for: visit))
        let detailFailure = await store.activity(checkIn: target, backend: backend)
        XCTAssertNil(detailFailure)
        XCTAssertNotNil(store.activityEngagementError(for: visit))
        let recovered = await store.activity(checkIn: target, backend: backend)
        XCTAssertEqual(recovered?.id, activity.id)
        XCTAssertNil(store.activityEngagementError(for: visit))
    }

    func testActivityWithoutReadablePostContentFailsInsteadOfSpinning() async {
        let store = WanderStore(fixtures: .empty())
        let activity = FeedActivity(id: UUID().uuidString, kind: .placeBeen,
            actor: privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly).actor, occurredAt: .now)
        let result = await store.activity(id: activity.id,
            backend: WanderBackend(activityEngagementRepository: ActivityEngagementRepositoryStub(activityResult: activity)))
        XCTAssertNil(result)
        XCTAssertNotNil(store.activityEngagementError(for: activity.id))
    }

    func testNotificationActivityRecoversInterruptedConnectionWithoutReopening() async {
        let store = WanderStore(fixtures: .empty())
        let activity = privacyActivity(ownerID: store.currentUser.id, visibility: .selfOnly)
        let repository = ActivityEngagementRepositoryStub(activityResponses: [
            .failure(URLError(.networkConnectionLost)), .success(activity)
        ])
        let resolved = await store.activity(
            id: activity.id, backend: WanderBackend(activityEngagementRepository: repository)
        )
        XCTAssertEqual(resolved?.id, activity.id)
        XCTAssertEqual(repository.activityRequestCount, 2)
        XCTAssertNil(store.activityEngagementError(for: activity.id))
    }

    func testCommentsRecoverTimeoutAndStopAfterOneRetry() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = UUID().uuidString
        let comment = activityComment(id: "comment", activityID: activityID, authorID: store.currentUser.id, relationship: .owner)
        let page = ActivityCommentsPage(comments: [comment], nextCursor: nil,
                                       engagement: .empty(activityID: activityID))
        let repository = ActivityEngagementRepositoryStub(commentsResponses: [
            .failure(URLError(.timedOut)), .success(page),
            .failure(URLError(.timedOut)), .failure(URLError(.timedOut))
        ])
        let backend = WanderBackend(activityEngagementRepository: repository)
        let recovered = await store.refreshActivityComments(activityID: activityID, backend: backend)
        XCTAssertTrue(recovered)
        XCTAssertEqual(store.activityComments(for: activityID), [comment])
        XCTAssertEqual(repository.commentsRequestCount, 2)
        let failed = await store.refreshActivityComments(activityID: activityID, backend: backend)
        XCTAssertFalse(failed)
        XCTAssertEqual(repository.commentsRequestCount, 4)
        XCTAssertNotNil(store.activityEngagementError(for: activityID))
    }

    func testCommentsDoNotRetryAuthorizationFailure() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = UUID().uuidString
        let repository = ActivityEngagementRepositoryStub(commentsResponses: [
            .failure(WanderRemoteError.notAuthenticated)
        ])
        let refreshed = await store.refreshActivityComments(
            activityID: activityID, backend: WanderBackend(activityEngagementRepository: repository)
        )
        XCTAssertFalse(refreshed)
        XCTAssertEqual(repository.commentsRequestCount, 1)
    }

    func testCommentsResponseCannotCrossAccountBoundaryOrCancellation() async {
        for changesAccount in [false, true] {
            let store = WanderStore(fixtures: .empty())
            let activityID = UUID().uuidString
            let comment = activityComment(id: "comment", activityID: activityID, authorID: store.currentUser.id, relationship: .owner)
            let repository = ActivityEngagementRepositoryStub(
                commentsPage: ActivityCommentsPage(comments: [comment], nextCursor: nil,
                                                  engagement: .empty(activityID: activityID)),
                suspendComments: true
            )
            let task = Task { @MainActor in
                await store.refreshActivityComments(
                    activityID: activityID, backend: WanderBackend(activityEngagementRepository: repository)
                )
            }
            for _ in 0..<100 where repository.commentsRequestCount == 0 { await Task.yield() }
            XCTAssertEqual(repository.commentsRequestCount, 1)
            if changesAccount {
                store.apply(authState: .signedOut)
                store.apply(authState: .signedIn(AuthSession(userID: "new_account", displayName: "New", handle: "new")))
            } else {
                task.cancel()
            }
            repository.finishComments()
            let refreshed = await task.value
            XCTAssertFalse(refreshed)
            XCTAssertTrue(store.activityComments(for: activityID).isEmpty)
            XCTAssertNil(store.activityEngagementError(for: activityID))
        }
    }

    func testDeniedRemoteCommentsResolutionClearsCachedPreviewAndCanRetry() throws {
        let coordinator = ActivityNavigationCoordinator()
        let activity = privacyActivity(ownerID: "friend", visibility: .followers)
        coordinator.openComments(context: try XCTUnwrap(activity.activityEngagementContext), visiblePlace: activity.place)
        let requestID = try XCTUnwrap(coordinator.commentsRoute?.id)

        coordinator.resolve(requestID: requestID, activity: nil)
        XCTAssertEqual(coordinator.commentsRoute?.id, requestID)
        XCTAssertNil(coordinator.commentsRoute?.context)
        XCTAssertNil(coordinator.commentsRoute?.visiblePlace)

        coordinator.resolve(requestID: requestID, activity: activity)
        XCTAssertEqual(coordinator.commentsRoute?.context?.activityID, activity.id)
        XCTAssertEqual(coordinator.commentsRoute?.visiblePlace?.id, activity.place?.id)
    }

    func testLocalCommentsResolutionKeepsPreviewAndIgnoresStaleRequests() throws {
        let coordinator = ActivityNavigationCoordinator()
        let activity = privacyActivity(ownerID: "owner", visibility: .selfOnly)
        coordinator.openComments(context: try XCTUnwrap(activity.activityEngagementContext), visiblePlace: activity.place)
        let requestID = try XCTUnwrap(coordinator.commentsRoute?.id)
        coordinator.resolve(requestID: requestID, activity: nil, allowsCachedContext: true)
        XCTAssertEqual(coordinator.commentsRoute?.context?.activityID, activity.id)
        coordinator.resolve(requestID: UUID(), activity: nil)
        XCTAssertEqual(coordinator.commentsRoute?.context?.activityID, activity.id)
    }

    func testCommentLikesAreIndependentAndCanBeUndone() async throws {
        let store = WanderStore(fixtures: .empty())
        _ = await store.addActivityComment(activityID: "local-comment-activity", body: "A comment", backend: nil)
        let comment = try XCTUnwrap(store.activityComments(for: "local-comment-activity").first)
        let activityBefore = store.activityEngagement(for: comment.activityID)
        let liked = await store.toggleActivityCommentLike(comment, backend: nil)
        XCTAssertTrue(liked)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, true)
        // A stale row passed by the UI must still toggle the current stored state.
        let unliked = await store.toggleActivityCommentLike(comment, backend: nil)
        XCTAssertTrue(unliked)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 0)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, false)
        XCTAssertEqual(store.activityEngagement(for: comment.activityID), activityBefore)
    }

    func testRemoteCommentLikeRollsBackAndCanRetry() async throws {
        let (store, repository, comment, backend) = await commentLikeFixture()
        repository.commentLikeError = ActivityEngagementTestError.expected
        let failed = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first, comment)
        XCTAssertNotNil(store.activityEngagementError(for: comment.activityID))
        XCTAssertFalse(store.isActivityCommentLikePending(comment.id))
        repository.commentLikeError = nil
        let retried = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertTrue(retried)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
        XCTAssertNil(store.activityEngagementError(for: comment.activityID))
        let refreshed = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, true)
        let reloadedStore = WanderStore(fixtures: .empty())
        _ = await reloadedStore.refreshActivityComments(activityID: comment.activityID, backend: backend)
        XCTAssertEqual(reloadedStore.activityComments(for: comment.activityID).first?.viewerHasLiked, true)
        repository.commentLikeError = ActivityEngagementTestError.expected
        let failedUnlike = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertFalse(failedUnlike)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, true)
        repository.commentLikeError = nil
        let unlike = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertTrue(unlike)
        XCTAssertEqual(repository.commentLikeRequests.map(\.isLiked), [true, true, false, false])
    }

    func testCommentLikeWithoutRemoteRepositoryFailsClosed() async {
        let (store, repository, comment, _) = await commentLikeFixture()
        let result = await store.toggleActivityCommentLike(comment, backend: nil)
        XCTAssertFalse(result)
        XCTAssertTrue(repository.commentLikeRequests.isEmpty)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, false)
    }

    func testConcurrentCommentTapsIssueOneWriteAndPreventDeletionWhilePending() async {
        let (store, repository, comment, backend) = await commentLikeFixture()
        repository.suspendCommentLikes = true
        let task = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
        for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
        XCTAssertTrue(store.isActivityCommentLikePending(comment.id))
        XCTAssertFalse(store.canDeleteActivityComment(comment))
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
        let duplicate = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(repository.commentLikeRequests.count, 1)
        repository.suspendCommentLikes = false
        let result = await task.value
        XCTAssertTrue(result)
        XCTAssertFalse(store.isActivityCommentLikePending(comment.id))
        XCTAssertTrue(store.canDeleteActivityComment(comment))
    }

    func testRefreshCannotOverwriteLikeStartedBeforeOrDuringTheRead() async {
        for startsDuringWrite in [false, true] {
            let (store, repository, comment, backend) = await commentLikeFixture()
            repository.beginSuspendingComments()
            repository.suspendCommentLikes = true
            var write: Task<Bool, Never>?
            if startsDuringWrite {
                write = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
                for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
            }
            let read = Task { await store.refreshActivityComments(activityID: comment.activityID, backend: backend) }
            for _ in 0..<100 where repository.commentsRequestCount < 2 { await Task.yield() }
            if !startsDuringWrite {
                write = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
                for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
            }
            repository.suspendCommentLikes = false
            let written = await write?.value
            XCTAssertEqual(written, true)
            repository.finishComments()
            let refreshed = await read.value
            XCTAssertTrue(refreshed)
            XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
            XCTAssertEqual(store.activityComments(for: comment.activityID).first?.viewerHasLiked, true)
        }
    }

    func testPendingCommentLikeSurvivesRefreshAndUsesAuthoritativeCount() async {
        let (store, repository, comment, backend) = await commentLikeFixture()
        repository.suspendCommentLikes = true
        repository.commentLikeCountOverride = 7
        let task = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
        for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
        _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 1)
        repository.suspendCommentLikes = false
        _ = await task.value
        XCTAssertEqual(store.activityComments(for: comment.activityID).first?.likeCount, 7)
    }

    func testAccountResetRejectsOldCommentLikeSuccessAndFailureIncludingSameUser() async {
        for fail in [false, true] {
            for sameUser in [false, true] {
                let (store, repository, comment, backend) = await commentLikeFixture()
                let userID = store.currentUser.id
                repository.suspendCommentLikes = true
                repository.commentLikeError = fail ? ActivityEngagementTestError.expected : nil
                let task = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
                for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
                store.apply(authState: .signedOut)
                store.apply(authState: .signedIn(AuthSession(userID: sameUser ? userID : "new_account", displayName: "New", handle: "new")))
                repository.suspendCommentLikes = false
                let result = await task.value
                XCTAssertFalse(result)
                XCTAssertTrue(store.activityComments(for: comment.activityID).isEmpty)
                XCTAssertFalse(store.isActivityCommentLikePending(comment.id))
                XCTAssertNil(store.activityEngagementError(for: comment.activityID))
            }
        }
    }

    func testDeletedCommentIsNotResurrectedByLikeCompletion() async {
        let (store, repository, comment, backend) = await commentLikeFixture()
        repository.suspendCommentLikes = true
        let task = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
        for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
        repository.commentsPage = ActivityCommentsPage(comments: [], nextCursor: nil, engagement: .empty(activityID: comment.activityID))
        _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        repository.suspendCommentLikes = false
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(store.activityComments(for: comment.activityID).isEmpty)
    }

    func testBlockedAndPendingCommentsCannotBeLiked() async throws {
        let store = WanderStore(fixtures: .empty())
        let comment = activityComment(id: UUID().uuidString, activityID: UUID().uuidString,
                                      authorID: "blocked_author", relationship: .follower)
        let repository = ActivityEngagementRepositoryStub(commentsPage: ActivityCommentsPage(
            comments: [comment], nextCursor: nil, engagement: .empty(activityID: comment.activityID)))
        let backend = WanderBackend(activityEngagementRepository: repository)
        _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        store.block(userID: comment.author.id)
        XCTAssertTrue(store.activityComments(for: comment.activityID).isEmpty)
        let blocked = await store.toggleActivityCommentLike(comment, backend: backend)
        XCTAssertFalse(blocked)
        XCTAssertTrue(repository.commentLikeRequests.isEmpty)
        let pending = ActivityComment(id: "pending", activityID: comment.activityID, author: comment.author,
                                      body: "Pending", createdAt: .now, isPending: true)
        repository.commentsPage = ActivityCommentsPage(comments: [pending], nextCursor: nil,
                                                      engagement: .empty(activityID: comment.activityID))
        store.unblock(userID: comment.author.id)
        _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        XCTAssertFalse(store.canLikeActivityComment(pending))
        let pendingResult = await store.toggleActivityCommentLike(pending, backend: backend)
        XCTAssertFalse(pendingResult)
        XCTAssertTrue(repository.commentLikeRequests.isEmpty)
    }

    func testBlockDuringCommentLikeDoesNotRestoreAnOptimisticRowAfterUnblock() async {
        for fail in [false, true] {
            let store = WanderStore(fixtures: .empty())
            let comment = activityComment(id: UUID().uuidString, activityID: UUID().uuidString,
                                          authorID: "comment_author", relationship: .follower)
            let repository = ActivityEngagementRepositoryStub(commentsPage: ActivityCommentsPage(
                comments: [comment], nextCursor: nil, engagement: .empty(activityID: comment.activityID)))
            let backend = WanderBackend(activityEngagementRepository: repository)
            _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
            repository.suspendCommentLikes = true
            repository.commentLikeError = fail ? ActivityEngagementTestError.expected : nil
            let task = Task { await store.toggleActivityCommentLike(comment, backend: backend) }
            for _ in 0..<100 where repository.commentLikeRequests.isEmpty { await Task.yield() }
            store.block(userID: comment.author.id)
            repository.suspendCommentLikes = false
            let result = await task.value
            XCTAssertFalse(result)
            store.unblock(userID: comment.author.id)
            XCTAssertTrue(store.activityComments(for: comment.activityID).isEmpty)
            XCTAssertFalse(store.isActivityCommentLikePending(comment.id))
        }
    }

    private func commentLikeFixture() async -> (WanderStore, ActivityEngagementRepositoryStub, ActivityComment, WanderBackend) {
        let store = WanderStore(fixtures: .empty())
        let comment = activityComment(id: UUID().uuidString, activityID: UUID().uuidString,
                                      authorID: store.currentUser.id, relationship: .owner)
        let repository = ActivityEngagementRepositoryStub(commentsPage: ActivityCommentsPage(
            comments: [comment], nextCursor: nil, engagement: .empty(activityID: comment.activityID)))
        let backend = WanderBackend(activityEngagementRepository: repository)
        _ = await store.refreshActivityComments(activityID: comment.activityID, backend: backend)
        return (store, repository, comment, backend)
    }

    private func privacyActivity(ownerID: String, visibility: PlaceVisibility) -> FeedActivity {
        let id = UUID().uuidString.lowercased()
        let owner = LocalProfile(localID: ownerID, handle: ownerID, displayName: "Owner")
        let place = LocalPlace(localID: "place_\(id)", canonicalName: "Test Place", category: "coffee", latitude: 34, longitude: -118)
        let userPlace = LocalUserPlace(localID: "save_\(id)", userID: ownerID, placeID: place.id, status: .been, visibility: visibility, sourceType: "manual")
        return FeedActivity(
            id: id, kind: .placeBeen,
            actor: ProfileShell(id: ownerID, handle: ownerID, displayName: "Owner", avatarURL: nil, bio: nil, relationship: .follower),
            place: VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner, attributes: []),
            occurredAt: .now, note: "Private note"
        )
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
    var placeError: Error?
    var placeFailuresRemaining = 0
    var suspendPlaceRequests = false
    private(set) var placeRequests: [[String]] = []
    let summariesResult: [ActivityEngagementSummary]?
    let setLikeError: Error?
    var commentsPage: ActivityCommentsPage?
    var commentLikeError: Error?
    var suspendCommentLikes = false
    var commentLikeCountOverride: Int?
    private(set) var commentLikeRequests: [(commentID: String, isLiked: Bool)] = []
    let deleteResult: ActivityEngagementSummary?
    let deleteError: Error?
    private(set) var activityRequestCount = 0
    private(set) var summariesRequestCount = 0
    private(set) var commentsRequestCount = 0
    private var commentsResponses: [Result<ActivityCommentsPage, Error>]
    private var areCommentsSuspended: Bool
    private(set) var deletedCommentIDs: [String] = []
    private var activityResponses: [Result<FeedActivity, Error>]
    private var isActivitySuspended: Bool
    private var areSummariesSuspended: Bool

    init(
        placeMatches: [PlaceActivityEngagementMatch] = [],
        summariesResult: [ActivityEngagementSummary]? = nil,
        setLikeError: Error? = nil,
        commentsPage: ActivityCommentsPage? = nil,
        deleteResult: ActivityEngagementSummary? = nil,
        deleteError: Error? = nil,
        activityResult: FeedActivity? = nil,
        activityResponses: [Result<FeedActivity, Error>]? = nil,
        suspendActivity: Bool = false,
        suspendSummaries: Bool = false,
        commentsResponses: [Result<ActivityCommentsPage, Error>] = [],
        suspendComments: Bool = false
    ) {
        self.commentsResponses = commentsResponses
        self.areCommentsSuspended = suspendComments
        self.placeMatches = placeMatches
        self.summariesResult = summariesResult
        self.setLikeError = setLikeError
        self.commentsPage = commentsPage
        self.deleteResult = deleteResult
        self.deleteError = deleteError
        self.isActivitySuspended = suspendActivity
        self.areSummariesSuspended = suspendSummaries
        self.activityResponses = activityResponses
            ?? activityResult.map { [.success($0)] }
            ?? []
    }

    func activity(id: String) async throws -> FeedActivity {
        activityRequestCount += 1
        while isActivitySuspended { await Task.yield() }
        guard !activityResponses.isEmpty else {
            throw ActivityEngagementTestError.expected
        }
        let activityResult = try activityResponses.removeFirst().get()
        guard activityResult.id == id else { throw ActivityEngagementTestError.expected }
        return activityResult
    }

    func finishActivity() {
        isActivitySuspended = false
    }

    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] {
        summariesRequestCount += 1
        while areSummariesSuspended { await Task.yield() }
        return summariesResult ?? activityIDs.map(ActivityEngagementSummary.empty(activityID:))
    }

    func finishSummaries() {
        areSummariesSuspended = false
    }

    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] {
        placeRequests.append(userPlaceIDs)
        while suspendPlaceRequests { await Task.yield() }
        if let placeError { throw placeError }
        if placeFailuresRemaining > 0 {
            placeFailuresRemaining -= 1
            throw ActivityEngagementTestError.expected
        }
        return placeMatches.filter { match in userPlaceIDs.contains { $0.caseInsensitiveCompare(match.userPlaceID) == .orderedSame } }
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
        let snapshot = commentsPage
        commentsRequestCount += 1
        while areCommentsSuspended { await Task.yield() }
        if !commentsResponses.isEmpty { return try commentsResponses.removeFirst().get() }
        return snapshot ?? ActivityCommentsPage(
            comments: [],
            nextCursor: nil,
            engagement: .empty(activityID: activityID)
        )
    }

    func beginSuspendingComments() { areCommentsSuspended = true }
    func finishComments() { areCommentsSuspended = false }

    func setCommentLike(commentID: String, isLiked: Bool) async throws -> ActivityCommentLikeSummary {
        commentLikeRequests.append((commentID, isLiked))
        let original = commentsPage?.comments.first { $0.id == commentID }
        while suspendCommentLikes { await Task.yield() }
        if let commentLikeError { throw commentLikeError }
        guard let original else { throw ActivityEngagementTestError.expected }
        let updated = original.withLikes(count: commentLikeCountOverride ?? (isLiked ? 1 : 0), isLiked: isLiked)
        if let page = commentsPage {
            commentsPage = ActivityCommentsPage(comments: page.comments.map { $0.id == commentID ? updated : $0 },
                                               nextCursor: page.nextCursor, engagement: page.engagement)
        }
        return ActivityCommentLikeSummary(commentID: commentID, activityID: original.activityID,
                                          likeCount: updated.likeCount, viewerHasLiked: isLiked)
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
