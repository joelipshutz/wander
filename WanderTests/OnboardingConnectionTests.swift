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

