import XCTest
@testable import Wander

@MainActor
final class FeedAudienceTests: XCTestCase {
    func testAudienceUsesActorIdentityAndMutualFollows() {
        for relationship in [ViewerRelationship.owner, .mutual, .follower, .nonFollower] {
            XCTAssertTrue(FeedAudience.everyone.includes(actorID: "other", currentUserID: "me", relationship: relationship))
            XCTAssertTrue(FeedAudience.onlyMe.includes(actorID: "me", currentUserID: "me", relationship: relationship))
            XCTAssertFalse(FeedAudience.onlyMe.includes(actorID: "other", currentUserID: "me", relationship: relationship))
            XCTAssertFalse(FeedAudience.onlyFriends.includes(actorID: "me", currentUserID: "me", relationship: relationship))
            XCTAssertEqual(FeedAudience.onlyFriends.includes(actorID: "other", currentUserID: "me", relationship: relationship), relationship == .mutual)
        }
    }

    func testLiveMapAudienceMatchesEagerOracleAcrossRelationshipsAndPrivacyMutations() {
        let relationships: [(own: Bool, outgoing: Bool, incoming: Bool, expected: ViewerRelationship)] = [
            (true, false, false, .owner),
            (false, true, true, .mutual),
            (false, true, false, .follower),
            (false, false, true, .nonFollower),
            (false, false, false, .nonFollower)
        ]
        let scenarios: [(name: String, envelopePrivate: Bool, storedPrivate: Bool, deleted: Bool, block: Int)] = [
            ("public", false, false, false, 0),
            ("private envelope", true, false, false, 0),
            ("private local profile", false, true, false, 0),
            ("deleted save", false, false, true, 0),
            ("outgoing block", false, false, false, 1),
            ("incoming block", false, false, false, 2)
        ]
        for relationship in relationships {
            let (store, actor, block) = liveMapAudienceStore(ownActor: relationship.own,
                outgoing: relationship.outgoing, incoming: relationship.incoming)
            XCTAssertEqual(store.relationship(to: actor.id), relationship.expected)
            let place = LocalPlace(localID: "place", canonicalName: "Example", category: "coffee",
                                   latitude: 0, longitude: 0)
            let save = LocalUserPlace(localID: "save", userID: actor.id, placeID: place.id,
                                      status: .been, visibility: .followers, sourceType: "manual")
            let visible = VisiblePlace(id: save.id, place: place, userPlace: save, owner: actor)
            for scenario in scenarios {
                // Mutate existing models without a collection-count or revision
                // change: authorization must still inspect current values.
                actor.isPrivateProfile = scenario.storedPrivate
                save.deletedAt = scenario.deleted ? .now : nil
                block.blockerUserID = scenario.block == 1 ? store.currentUser.id
                    : scenario.block == 2 ? actor.id : "unused-blocker"
                block.blockedUserID = scenario.block == 1 ? actor.id
                    : scenario.block == 2 ? store.currentUser.id : "unused-target"
                for visibility in PlaceVisibility.allCases {
                    save.visibilityRaw = visibility.rawValue
                    let shell = ProfileShell(id: actor.id, handle: actor.handle, displayName: actor.displayName,
                        avatarURL: nil, bio: nil, isPrivateProfile: scenario.envelopePrivate,
                        relationship: .nonFollower) // Envelope graph facts must not replace the live graph.
                    let event = FeedActivity(id: "event", kind: .placeBeen, actor: shell,
                                             place: visible, occurredAt: .now)
                    let privacyPermits = !scenario.deleted && scenario.block == 0
                        && (relationship.own || (!scenario.envelopePrivate && !scenario.storedPrivate))
                        && (relationship.own || visibility != .selfOnly)
                    XCTAssertEqual(store.canDisplayPlaceActivity(event), privacyPermits, scenario.name)
                    for audience in FeedAudience.allCases {
                        store.selectFeedAudience(audience)
                        let eager = store.canDisplayPlaceActivity(event)
                            && audience.includes(actorID: event.actor.id, currentUserID: store.currentUser.id,
                                relationship: store.relationship(to: event.actor.id))
                        XCTAssertEqual(store.canDisplayLiveMapActivity(event), eager, scenario.name)
                        if !privacyPermits {
                            XCTAssertFalse(store.canDisplayLiveMapActivity(event), scenario.name)
                        }
                    }
                }
            }
        }
    }

    func testLiveMapAudienceCannotBypassBlockedPlaceOwnerForOwnActor() {
        let (store, owner, block) = liveMapAudienceStore(ownActor: false, outgoing: true, incoming: true)
        let place = LocalPlace(localID: "place", canonicalName: "Example", category: "coffee",
                               latitude: 0, longitude: 0)
        let save = LocalUserPlace(localID: "save", userID: owner.id, placeID: place.id,
                                  status: .been, visibility: .followers, sourceType: "manual")
        let visible = VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
        let actor = ProfileShell(id: store.currentUser.id, handle: "viewer", displayName: "Viewer",
                                 avatarURL: nil, bio: nil, relationship: .owner)
        let event = FeedActivity(id: "event", kind: .placeBeen, actor: actor, place: visible, occurredAt: .now)
        for audience in [FeedAudience.everyone, .onlyMe] {
            store.selectFeedAudience(audience)
            XCTAssertTrue(store.canDisplayLiveMapActivity(event))
        }
        block.blockerUserID = owner.id
        block.blockedUserID = store.currentUser.id
        for audience in FeedAudience.allCases {
            store.selectFeedAudience(audience)
            XCTAssertFalse(store.canDisplayPlaceActivity(event))
            XCTAssertFalse(store.canDisplayLiveMapActivity(event))
        }
    }

    func testSelectionClearsPreviousPageAndRefreshKeepsSelection() async {
        let store = WanderStore(fixtures: .seed())
        let repository = AudienceRepository()
        let backend = WanderBackend(feedRepository: repository)
        XCTAssertEqual(store.feedAudience, .everyone)
        _ = await store.refreshFollowedFeed(backend: backend)
        store.selectFeedAudience(.onlyMe)
        XCTAssertNil(store.followedFeedPage)
        XCTAssertEqual(store.feedLoadState, .idle)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(repository.audiences, [.everyone, .onlyMe])
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertEqual(store.feedAudience, .onlyMe)
        XCTAssertEqual(repository.audiences, [.everyone, .onlyMe, .onlyMe])
        store.selectFeedAudience(.everyone)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(repository.audiences.last, .everyone)
    }

    func testAccountChangeResetsAudienceEvenBeforeAnyFeedLoad() {
        let store = WanderStore(fixtures: .empty())
        store.selectFeedAudience(.onlyFriends)
        store.apply(authState: .signedOut)
        XCTAssertEqual(store.feedAudience, .everyone)
    }

    func testLateContentAndCompletionCannotOverwriteNewAudience() async {
        let store = WanderStore(fixtures: .seed())
        let repository = AudienceRepository()
        repository.suspendEveryone = true
        let backend = WanderBackend(feedRepository: repository)
        let old = Task { await store.refreshFollowedFeed(backend: backend) }
        for _ in 0..<100 where repository.audiences.isEmpty { await Task.yield() }
        XCTAssertEqual(repository.audiences, [.everyone])
        store.selectFeedAudience(.onlyMe)
        _ = await store.refreshFollowedFeed(backend: backend)
        let currentDate = store.followedFeedPage?.fetchedAt
        repository.suspendEveryone = false
        let oldResult = await old.value
        XCTAssertFalse(oldResult)
        XCTAssertEqual(store.feedAudience, .onlyMe)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, currentDate)
        XCTAssertEqual(store.feedLoadState, .loaded)
    }

    private func liveMapAudienceStore(ownActor: Bool, outgoing: Bool, incoming: Bool)
        -> (WanderStore, LocalProfile, LocalBlock) {
        let viewer = LocalProfile(localID: "viewer", handle: "viewer", displayName: "Viewer")
        let actor = ownActor ? viewer : LocalProfile(localID: "actor", handle: "actor", displayName: "Actor")
        var follows: [LocalFollow] = []
        if outgoing {
            follows.append(LocalFollow(localID: "outgoing", followerUserID: viewer.id,
                                       followedUserID: actor.id, source: .profile))
        }
        if incoming {
            follows.append(LocalFollow(localID: "incoming", followerUserID: actor.id,
                                       followedUserID: viewer.id, source: .profile))
        }
        let block = LocalBlock(localID: "block", blockerUserID: "unused-blocker", blockedUserID: "unused-target")
        let fixtures = WanderFixtures(currentUser: viewer, profiles: ownActor ? [viewer] : [viewer, actor],
            places: [], userPlaces: [], placeAttributes: [], follows: follows, blocks: [block],
            placeLists: [], placeListMembers: [], placeListItems: [], contactProvider: FakeContactProvider(seededMatches: []))
        return (WanderStore(fixtures: fixtures), actor, block)
    }
}

@MainActor
private final class AudienceRepository: FeedRepository {
    var audiences: [FeedAudience] = []
    var suspendEveryone = false

    func activityFeed(
        audience: FeedAudience, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void
    ) async throws -> FollowedFeedPage {
        audiences.append(audience)
        // Deliberately ignore cancellation to exercise the store's generation guard.
        while audience == .everyone && suspendEveryone { await Task.yield() }
        let page = FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: nil,
                                    fetchedAt: Date(timeIntervalSince1970: audience == .everyone ? 1 : 2))
        onContent(page)
        return page
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("The audience-aware path must be used")
        throw URLError(.unsupportedURL)
    }
}
