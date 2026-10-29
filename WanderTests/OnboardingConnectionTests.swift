import XCTest
import UIKit
@testable import Wander

@MainActor
final class OnboardingConnectionTests: XCTestCase {
    private func person(_ id: String) -> ProfileShell {
        ProfileShell(id: id, handle: id, displayName: id.capitalized, avatarURL: nil, bio: nil, relationship: .nonFollower)
    }

    func testLoadingSuggestionsNeverFollowsAndPreservesExistingFollowing() async {
        let ryan = person("ryan")
        var writes = 0
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { [DiscoverPeopleRecommendation(profile: ryan, reason: .suggested, rank: 1)] },
            search: { _ in [ryan] }, following: { [ryan] }, follow: { _ in writes += 1 }
        )
        await model.load()
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(model.isFollowed(ryan))
        let changed = await model.follow(ryan)
        XCTAssertFalse(changed)
        XCTAssertEqual(writes, 0)
    }

    func testClearingContactsRemovesBothDirectAndContactGraphSuggestions() async {
        let suggestions: [DiscoverPeopleRecommendation] = [
            .init(profile: person("contact"), reason: .contacts, rank: 1),
            .init(profile: person("social"), reason: .contactFollows(3), rank: 2),
            .init(profile: person("local"), reason: .nearby, rank: 3)]
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { suggestions }, search: { _ in [] }, following: { [] }, follow: { _ in }
        )
        await model.load()
        XCTAssertEqual(model.recommendations, suggestions)
        XCTAssertEqual(suggestions[1].reason.displayText(for: person("social")), "3 of your contacts follow Social")
        model.clearContactRecommendations()
        XCTAssertEqual(model.recommendations.map(\.id), ["local"])
    }

    func testFailedFollowCanRetryAndSuccessIsNeverRepeated() async {
        let ryan = person("ryan")
        var attempts = 0
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { [DiscoverPeopleRecommendation(profile: ryan, reason: .suggested, rank: 1)] },
            search: { _ in [] }, following: { [] },
            follow: { _ in
                attempts += 1
                if attempts == 1 { throw WanderRemoteError.notConfigured }
            }
        )
        await model.load()
        let failed = await model.follow(ryan)
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.followErrors[ryan.id])
        XCTAssertFalse(model.isFollowed(ryan))
        XCTAssertFalse(model.isFollowing)
        let succeeded = await model.follow(ryan)
        XCTAssertTrue(succeeded)
        XCTAssertNil(model.followErrors[ryan.id])
        XCTAssertTrue(model.isFollowed(ryan))
        let duplicate = await model.follow(ryan)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(model.completedFollowCount, 1)
    }

    func testConcurrentTapDoesNotCreateTwoFollowRequests() async throws {
        let ryan = person("ryan")
        let followStarted = expectation(description: "First follow request is suspended")
        var continuation: CheckedContinuation<Void, Never>?
        var attempts = 0
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { [] }, search: { _ in [] }, following: { [] },
            follow: { _ in
                attempts += 1
                await withCheckedContinuation {
                    continuation = $0
                    followStarted.fulfill()
                }
            }
        )
        await model.load()
        let first = Task { await model.follow(ryan) }
        await fulfillment(of: [followStarted], timeout: 5)
        let completion = try XCTUnwrap(continuation)
        XCTAssertTrue(model.isFollowing)
        XCTAssertTrue(model.pendingIDs.contains(ryan.id), "The shared control must show Following while the write is suspended")
        XCTAssertEqual(model.completedFollowCount, 0, "Optimistic display must not count as a saved follow")
        let duplicate = await model.follow(ryan)
        XCTAssertFalse(duplicate)
        completion.resume()
        let succeeded = await first.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(attempts, 1)
    }

    func testSearchRequiresTwoCharactersAndRejectsLateResults() async throws {
        let oldProfile = person("old")
        let newProfile = person("new")
        let oldSearchStarted = expectation(description: "Old search request is suspended")
        var oldSearch: CheckedContinuation<[ProfileShell], Never>?
        var queries: [String] = []
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { [] },
            search: { term in
                queries.append(term)
                if term == "old" {
                    return await withCheckedContinuation {
                        oldSearch = $0
                        oldSearchStarted.fulfill()
                    }
                }
                return [newProfile]
            }, following: { [] }, follow: { _ in }
        )
        model.query = "a"
        await model.search(debounce: .zero)
        XCTAssertTrue(queries.isEmpty)
        model.query = "@Old"
        let first = Task { await model.search(debounce: .zero) }
        await fulfillment(of: [oldSearchStarted], timeout: 5)
        let completion = try XCTUnwrap(oldSearch)
        model.query = "new"
        await model.search(debounce: .zero)
        XCTAssertEqual(model.searchResults.map(\.id), ["new"])
        completion.resume(returning: [oldProfile])
        await first.value
        XCTAssertEqual(model.searchResults.map(\.id), ["new"])
        XCTAssertEqual(queries, ["old", "new"])
    }

    func testUnknownFollowingGraphDoesNotOfferWrites() async {
        let ryan = person("ryan")
        var writes = 0
        let model = OnboardingFriendSuggestionsModel(
            recommendations: { [] }, search: { _ in [ryan] },
            following: { throw WanderRemoteError.notConfigured }, follow: { _ in writes += 1 }
        )
        await model.load()
        XCTAssertEqual(model.loadingState, .failed)
        let changed = await model.follow(ryan)
        XCTAssertFalse(changed)
        XCTAssertEqual(writes, 0)
    }
}

@MainActor
final class OnboardingIdentitySubmissionTests: XCTestCase {
    private let draft = ProfileIdentityDraft(displayName: " Maya Chen ", handle: " @MAYA ")

    func testAuthNameAndHandleCannotBypassUnsavedIdentityOffline() {
        let session = AuthSession(userID: "new-user", displayName: "Maya", handle: "maya")
        XCTAssertEqual(
            AppEntryStateResolver.offlineState(session: session, localState: .fresh, message: "Offline"),
            .recoverableFailure(session: session, message: "Offline", canContinueOffline: false)
        )
        var savedIdentity = OnboardingLocalState.fresh
        savedIdentity.nextStep = .location
        savedIdentity.hasSavedRequiredIdentity = true
        XCTAssertEqual(
            AppEntryStateResolver.offlineState(session: session, localState: savedIdentity, message: "Offline"),
            .recoverableFailure(session: session, message: "Offline", canContinueOffline: true)
        )
    }

    func testAppleIdentityCanContinueWithoutARequiredPhoto() async throws {
        var writes: [ProfileDetailsUpdate] = []
        try await OnboardingIdentitySubmission.save(
            draft: ProfileIdentityDraft(displayName: "", handle: "apple_user", usesAppleSignIn: true),
            photoData: nil, existingAvatarURL: nil,
            updateIdentity: { writes.append($0) },
            uploadPhoto: { _ in XCTFail("An absent optional Apple photo must not be uploaded") }
        )
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.displayName, "apple_user")
    }

    func testIdentityWithoutPhotoSavesAndDoesNotUpload() async throws {
        var writes: [ProfileDetailsUpdate] = []
        try await OnboardingIdentitySubmission.save(
            draft: draft, photoData: nil, existingAvatarURL: nil,
            updateIdentity: { writes.append($0) },
            uploadPhoto: { _ in XCTFail("An optional absent photo must not be uploaded") }
        )
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.displayName, "Maya Chen")
        XCTAssertEqual(writes.first?.handle, "maya")
    }

    func testAvatarUploadFailureBlocksSuccessAndSupportsRetry() async throws {
        var uploadAttempts = 0
        var updates: [ProfileDetailsUpdate] = []
        let upload: (Data) async throws -> Void = { _ in
            uploadAttempts += 1
            if uploadAttempts == 1 { throw WanderRemoteError.notConfigured }
        }
        do {
            try await OnboardingIdentitySubmission.save(
                draft: draft, photoData: Data([1]), existingAvatarURL: nil,
                updateIdentity: { updates.append($0) }, uploadPhoto: upload
            )
            XCTFail("Upload failure must not count as completed identity")
        } catch let error as OnboardingIdentityPhotoError {
            guard case .uploadFailed = error else { return XCTFail("Expected upload failure") }
        }
        try await OnboardingIdentitySubmission.save(
            draft: draft, photoData: Data([1]), existingAvatarURL: nil,
            updateIdentity: { updates.append($0) }, uploadPhoto: upload
        )
        XCTAssertEqual(uploadAttempts, 2)
        XCTAssertEqual(updates.last?.displayName, "Maya Chen")
        XCTAssertEqual(updates.last?.handle, "maya")
    }

    func testExistingAvatarAllowsResumedProfileWithoutReupload() async throws {
        var uploads = 0
        try await OnboardingIdentitySubmission.save(
            draft: draft, photoData: nil, existingAvatarURL: "https://example.invalid/stored-avatar.jpg",
            updateIdentity: { _ in }, uploadPhoto: { _ in uploads += 1 }
        )
        XCTAssertEqual(uploads, 0)
    }

    func testInvalidIdentityBlocksAvatarUpload() async {
        var uploads = 0
        do {
            try await OnboardingIdentitySubmission.save(
                draft: ProfileIdentityDraft(displayName: "", handle: "valid"), photoData: Data([1]), existingAvatarURL: nil,
                updateIdentity: { _ in XCTFail("Invalid identity must not be submitted") }, uploadPhoto: { _ in uploads += 1 }
            )
            XCTFail("Expected validation error")
        } catch {
            XCTAssertEqual(error as? ProfileIdentityValidationError, .displayNameRequired)
        }
        XCTAssertEqual(uploads, 0)
    }
}

@MainActor
final class OnboardingEntryRegressionTests: XCTestCase {
    func testProfileFetchFailureCannotBypassUnsavedIdentityWithAuthIdentity() async throws {
        let session = AuthSession(userID: "new-user", displayName: "Maya", handle: "maya")
        let provider = PreviewAuthSessionProvider(state: .signedIn(session))
        let auth = AuthSessionStore(provider: provider)
        let suite = "OnboardingEntryRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AppEntryCoordinator(
            auth: auth, backend: WanderBackend(profileRepository: FailingOnboardingReviewProfileRepository()),
            completionStore: OnboardingCompletionStore(defaults: defaults)
        )
        await coordinator.start()
        guard case .recoverableFailure(_, _, let canContinue) = coordinator.state else {
            return XCTFail("Expected recoverable profile failure")
        }
        XCTAssertFalse(canContinue)
        let failure = coordinator.state
        coordinator.continueOffline()
        XCTAssertEqual(coordinator.state, failure)
    }

    func testValidIdentityWithoutPhotoPreservesProgressAndCompletedUsersRemainReady() throws {
        let session = AuthSession(userID: "legacy-user", displayName: "Maya", handle: "maya")
        let legacy = try JSONDecoder().decode(OnboardingLocalState.self, from: Data(
            #"{"nextStep":"friends","isComplete":false,"needsServerCompletion":false}"#.utf8
        ))
        let profile = LocalProfile(localID: session.userID, handle: "maya", displayName: "Maya")
        XCTAssertNil(legacy.hasSavedRequiredIdentity)
        XCTAssertFalse(AppEntryStateResolver.canContinueOffline(localState: legacy))
        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: legacy, remoteProfile: profile),
            .onboarding(session: session, step: .friends)
        )
        profile.onboardingCompletedAt = .now
        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: legacy, remoteProfile: profile),
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
    }

    func testRequiredIdentityProofPersistsOnlyAfterSavedIdentityProgress() throws {
        let suite = "OnboardingEntryRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let completion = OnboardingCompletionStore(defaults: defaults)
        completion.setNextStep(.location, for: "new-user")
        let restored = OnboardingCompletionStore(defaults: defaults).state(for: "new-user")
        XCTAssertTrue(AppEntryStateResolver.canContinueOffline(localState: restored))
        completion.setNextStep(.identity, for: "new-user")
        XCTAssertFalse(AppEntryStateResolver.canContinueOffline(localState: completion.state(for: "new-user")))
    }

    func testReturningFromMailPreservesVerificationUntilCompletion() async {
        let session = AuthSession(userID: "verified-user", displayName: "Maya", handle: "maya")
        let provider = PreviewAuthSessionProvider(
            state: .signedOut, canPresentNativeAuth: true, emailVerificationSession: session
        )
        let auth = AuthSessionStore(provider: provider)
        auth.beginSignIn(mode: .signUp)
        let sent = await auth.sendEmailCode(to: "maya@example.invalid")
        XCTAssertTrue(sent)
        XCTAssertFalse(AppEntryForegroundRefreshPolicy.canRefreshEntry(isPresentingNativeAuth: auth.isPresentingNativeAuth))
        // The provider's existing auth attempt fence must retain its pending
        // challenge even if another lifecycle caller asks it to refresh.
        await auth.refreshSession()
        XCTAssertTrue(auth.isPresentingNativeAuth)
        XCTAssertEqual(auth.emailVerificationAddress, "maya@example.invalid")
        XCTAssertFalse(provider.didResetPendingEmailVerification)
        let result = await auth.verifyEmailCode("123456")
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(auth.isSessionValidated)
        XCTAssertEqual(auth.state, .signedIn(session))
        XCTAssertTrue(AppEntryForegroundRefreshPolicy.canRefreshEntry(isPresentingNativeAuth: auth.isPresentingNativeAuth))
    }
}

@MainActor
private final class FailingOnboardingReviewProfileRepository: ProfileRepository {
    func currentProfile() async throws -> LocalProfile? { throw WanderRemoteError.notConfigured }
    func profile(id: String) async throws -> ProfileViewState { throw WanderRemoteError.notConfigured }
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] { [] }
}

@MainActor
final class CategoryGlyphFallbackTests: XCTestCase {
    func testHealthyEmojiFontPreservesExactSelectedGlyph() {
        XCTAssertEqual(
            WanderCategoryGlyph.resolve(emoji: "☕️", supportsEmoji: true),
            .emoji("☕️")
        )
    }

    func testUnavailableEmojiFontUsesCategorySymbolsAndNormalizesVariationSelector() {
        XCTAssertEqual(WanderCategoryGlyph.resolve(emoji: "☕️", supportsEmoji: false), .systemImage("cup.and.saucer.fill"))
        XCTAssertEqual(WanderCategoryGlyph.resolve(emoji: "☕", supportsEmoji: false), .systemImage("cup.and.saucer.fill"))
        XCTAssertEqual(WanderCategoryGlyph.resolve(emoji: "🍸", supportsEmoji: false), .systemImage("wineglass.fill"))
        XCTAssertEqual(WanderCategoryGlyph.resolve(emoji: "🍜", supportsEmoji: false), .systemImage("fork.knife"))
        XCTAssertEqual(WanderCategoryGlyph.resolve(emoji: "unknown", supportsEmoji: false), .systemImage("mappin"))
    }

    func testEveryBroadCategoryFallbackNamesAnAvailableNativeSymbol() {
        for category in WanderPlaceCategory.taxonomy {
            let symbol = WanderPlaceEmojiResolver.fallbackSystemImage(forCategory: category.id)
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing native symbol for \(category.id): \(symbol)")
        }
    }

    func testNativeMapFallbackDrawsTheResolvedSymbolCenteredWithRequestedTint() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format)
        let glyph = WanderCategoryGlyph.resolve(emoji: "☕️", supportsEmoji: false)
        let actual = renderer.image { _ in
            glyph.draw(center: CGPoint(x: 30, y: 30), pointSize: 20, foregroundColor: .red)
        }
        let symbol = try XCTUnwrap(UIImage(
            systemName: "cup.and.saucer.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )).withTintColor(.red, renderingMode: .alwaysOriginal)
        let expected = renderer.image { _ in
            symbol.draw(at: CGPoint(x: 30 - symbol.size.width / 2, y: 30 - symbol.size.height / 2))
        }
        let blank = renderer.image { _ in }
        XCTAssertEqual(actual.pngData(), expected.pngData())
        XCTAssertNotEqual(actual.pngData(), blank.pngData())
    }
}
