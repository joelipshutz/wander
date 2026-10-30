import XCTest
@testable import Wander

@MainActor
final class LiveTotemStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testCountryAliasesProduceOneSavedPinBeforeDensityWithAuthoritativeState() throws {
        for owner in ["me", "friend"] {
            for status in [PlaceStatus.been, .wannaGo] {
                let saved = row("66600000-0000-4000-8000-000000000001", ownerID: owner, status: status)
                let featured = row("66600000-0000-4000-8000-000000000002", ownerID: FeaturedCommunityPlaceSignal.ownerID)
                saved.place.sourceProviderPlaceID = "mapkit_shared-cafe_3405_-11824"
                featured.place.sourceProviderPlaceID = "mapkit_shared_cafe_3405_-11824"
                featured.place.country = "United States"
                let event = activity("saved-event", status == .been ? .placeBeen : .placeWannaGo, saved)
                let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                    currentSavedPlaces: [saved], currentListPlaces: [], authoritativeState: .init(states: [
                        .init(placeID: saved.place.id, saves: [.init(ownerID: owner,
                            hasBeen: status == .been, hasWanna: status == .wannaGo, isFriend: false)], hasListMembership: false),
                        .init(placeID: featured.place.id, saves: [], hasListMembership: false)
                    ], complete: true), allowsCachedAssociations: false)
                let previous = LiveMapProjection.pins(activities: [], featured: [featured], totemContext: context)
                for events in [[], [event]] {
                    let pins = LiveMapProjection.pins(activities: events, featured: [featured, featured],
                        totemContext: context, previousPins: previous)
                    XCTAssertEqual(pins.count, 1, "A country spelling must not create a second full pin or dense dot.")
                    let pin = try XCTUnwrap(pins.first)
                    XCTAssertEqual(pin.identity.persistedPlaceIDs, [saved.place.id, featured.place.id])
                    XCTAssertEqual(pin.id, previous.first?.id, "Late activity must preserve the selected identity.")
                    XCTAssertTrue(pin.totemState.hasSavedStatus)
                    XCTAssertFalse(pin.totemState.isFeatured)
                    XCTAssertEqual(pin.totemState.rails, [.init(ownership: owner == "me" ? .currentUser : .social, status: status)])
                    XCTAssertEqual(pin.activities.count, events.count)
                    let points = pins.map { (id: $0.id, point: CGPoint(x: 100, y: 100)) }
                    XCTAssertTrue(LivePinDensity.compactIDs(points: points, selectedID: nil).isEmpty)
                    XCTAssertEqual(LivePinDensity.compactIDs(points: [("0-neighbor", .init(x: 101, y: 101))] + points,
                        selectedID: nil), [pin.id], "A crowded place has exactly one compact representation.")
                }
            }
        }
    }

    func testCountryCanonicalizationKeepsConflictingAndUnprovenVenuesSeparate() {
        let first = row("first", ownerID: "me"), second = row("second", ownerID: "friend")
        first.place.sourceProviderPlaceID = "first-provider-id"
        second.place.sourceProviderPlaceID = "second-provider-id"
        for country in ["US", "USA", "United States", " U.S. "] {
            second.place.country = country
            XCTAssertTrue(LivePlaceIdentity(places: [first.place]).matches(second.place), country)
        }
        for country in ["CA", "Canada", "Unknown country", "", nil] {
            second.place.country = country
            XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
        }
        second.place.country = "United States"
        second.place.canonicalName = "Another Cafe"
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
        second.place.canonicalName = first.place.canonicalName
        second.place.address = "12 Main Street"
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
        second.place.address = first.place.address
        second.place.locality = nil
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
        second.place.locality = first.place.locality
        second.place.latitude += 0.01
        XCTAssertFalse(LivePlaceIdentity(places: [first.place]).matches(second.place))
    }

    func testFeaturedRequiresNoAuthorizedSaveOrCurrentListMembership() {
        let featured = row("featured", ownerID: FeaturedCommunityPlaceSignal.ownerID)
        let own = row("own", ownerID: "me", status: .wannaGo)
        let social = row("social", ownerID: "friend")
        for saves in [[], [own], [social], [own, social]] {
            for listed in [false, true] {
                let state = projection(featured: [featured], saves: saves,
                                       memberships: listed ? [featured.place] : []).first!.totemState
                XCTAssertEqual(state.isFeatured, saves.isEmpty && !listed)
                XCTAssertEqual(state.hasListMembership, listed)
                XCTAssertEqual(state.hasSavedStatus, !saves.isEmpty)
                XCTAssertEqual(state.rails.contains { $0.ownership == .featured }, state.isFeatured)
            }
        }
    }

    func testUnknownCurrentStateNeverTurnsGreenFromAnEmptyCache() {
        let featured = row("featured", ownerID: FeaturedCommunityPlaceSignal.ownerID)
        let unknown = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                                       currentSavedPlaces: [], currentListPlaces: [])
        let state = unknown.state(for: LivePlaceIdentity(places: [featured.place]), activities: [], featured: true)
        XCTAssertFalse(state.isFeatured)
        XCTAssertTrue(state.rails.isEmpty)
        XCTAssertFalse(state.accessibilitySummary.contains("Featured"))
    }

    func testCurrentListMembershipSurvivesDateWindowWithoutFabricatingActivities() {
        let place = row("place", ownerID: "friend", status: .wannaGo)
        let event = activity("list", .listItemAdded, place)
        let query = LiveFeedQuery(occurredAfter: now.addingTimeInterval(-60), occurredBefore: now)
        let pins = projection(events: [event], memberships: [place.place], query: query)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pins[0].activities.map(\.id), [event.id])
        XCTAssertTrue(pins[0].totemState.hasListMembership)
        XCTAssertFalse(pins[0].totemState.hasSavedStatus,
                       "A list event's required place status is not a Wanna action.")
        XCTAssertTrue(pins[0].totemState.rails.isEmpty)
        XCTAssertEqual(pins[0].totemState.accessibilitySummary, "On a list")
        XCTAssertTrue(projection(saves: [place], memberships: [place.place], query: query).isEmpty,
                      "Current state must not introduce a pin outside query results.")
    }

    func testNonAggregateFeaturedCandidateIsCurrentSaveEvidenceOutsideTheCache() {
        let saved = row("remote-featured", ownerID: "friend")
        let pin = projection(featured: [saved])[0]
        XCTAssertTrue(pin.totemState.hasSavedStatus)
        XCTAssertFalse(pin.totemState.isFeatured)
        XCTAssertEqual(pin.totemState.rails, [MapPinOutline(ownership: .social, status: .been)])
        XCTAssertFalse(pin.accessibilityLabel.contains("Featured"))
        XCTAssertTrue(pin.activities.isEmpty)
    }

    func testListsFilterKeepsSavedAssociationsAndListOnlyAccessibilityIsNotFeatured() {
        let saved = row("saved", ownerID: "me")
        let event = activity("list", .listItemAdded, saved)
        let pin = projection(events: [event], saves: [saved], memberships: [saved.place],
                             query: LiveFeedQuery(activityType: .lists))[0]
        XCTAssertEqual(pin.totemState.rails, [MapPinOutline(ownership: .currentUser, status: .been)])
        let featured = row("featured-list", ownerID: FeaturedCommunityPlaceSignal.ownerID)
        let listOnly = projection(featured: [featured], memberships: [featured.place])[0]
        XCTAssertTrue(listOnly.accessibilityLabel.contains("On a list"))
        XCTAssertFalse(listOnly.accessibilityLabel.contains("Featured"))
    }

    func testHistoricalListEventCannotKeepBadgeAfterCurrentMembershipRemoval() {
        let place = row("place", ownerID: "friend", status: .wannaGo)
        let event = activity("old-list-event", .listItemAdded, place)
        let before = projection(events: [event], memberships: [place.place])
        let after = projection(events: [event], previous: before)
        XCTAssertTrue(before[0].totemState.hasListMembership)
        XCTAssertFalse(after[0].totemState.hasListMembership)
        XCTAssertEqual(before[0].id, after[0].id)
        XCTAssertEqual(after[0].activities.map(\.id), [event.id])
    }

    func testPeopleAndActivityFiltersChangeRailsButNeverRestoreFeatured() {
        let featured = row("featured", ownerID: FeaturedCommunityPlaceSignal.ownerID)
        let own = row("own", ownerID: "me")
        let social = row("social", ownerID: "friend", status: .wannaGo)
        let queries = [
            LiveFeedQuery(activityType: .wannas, personIDs: ["me"]),
            LiveFeedQuery(activityType: .checkIns, personIDs: ["friend"]),
            LiveFeedQuery(personIDs: ["someone-else"])
        ]
        for query in queries {
            let state = projection(featured: [featured], saves: [own, social], query: query)[0].totemState
            XCTAssertTrue(state.hasSavedStatus)
            XCTAssertTrue(state.rails.isEmpty)
            XCTAssertFalse(state.isFeatured)
        }
        let wanna = projection(featured: [featured], saves: [own, social],
                               query: LiveFeedQuery(activityType: .wannas))[0].totemState
        XCTAssertEqual(wanna.rails, [MapPinOutline(ownership: .social, status: .wannaGo)])
    }

    func testOwnAndSocialRailsKeepStatusPrecedenceWithoutCountingPeopleAsEvents() {
        let ownBeen = row("own-been", ownerID: "me")
        let ownWanna = row("own-wanna", ownerID: "me", status: .wannaGo)
        let socialBeen = row("social-been", ownerID: "alex")
        let socialWanna = row("social-wanna", ownerID: "sam", status: .wannaGo)
        let event = activity("wanna", .placeWannaGo, socialWanna)
        let pin = projection(events: [event], saves: [ownBeen, ownWanna, socialBeen, socialWanna])[0]
        XCTAssertEqual(pin.totemState.rails, [
            MapPinOutline(ownership: .currentUser, status: .been),
            MapPinOutline(ownership: .social, status: .been, secondaryStatus: .wannaGo)
        ])
        XCTAssertEqual(pin.activities.count, 1)
        XCTAssertEqual(pin.activities[0].resolvedTicketKind, .wanna)
    }

    func testPriorOwnVisitRemainsAssociationEvidenceWithoutAddingAnEvent() {
        let active = row("active", ownerID: "me", status: .wannaGo)
        let prior = row("prior", ownerID: "me")
        let event = activity("new-wanna", .placeWannaGo, active)
        for (query, expected) in [(LiveFeedQuery(), PlaceStatus.been),
                                  (LiveFeedQuery(activityType: .wannas), PlaceStatus.wannaGo)] {
            let context = LiveTotemContext(currentUserID: "me", query: query,
                                          currentSavedPlaces: [active], currentListPlaces: [])
            let pin = LiveMapProjection.pins(activities: [event], featured: [], ownCheckInPlaces: [prior],
                                            totemContext: context)[0]
            XCTAssertEqual(pin.totemState.rails, [MapPinOutline(ownership: .currentUser, status: expected)])
            XCTAssertEqual(pin.activities.map(\.id), [event.id])
        }
    }

    func testAudienceFiltersRailsWithoutConflatingAuthorizationWithDiscovery() {
        let own = row("own", ownerID: "me")
        let friend = row("friend", ownerID: "friend", status: .wannaGo)
        let following = row("following", ownerID: "following")
        for (audience, expected) in [
            (FeedAudience.onlyMe, [MapPinOutline(ownership: .currentUser, status: .been)]),
            (FeedAudience.onlyFriends, [MapPinOutline(ownership: .social, status: .wannaGo)])
        ] {
            let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                currentSavedPlaces: [own, friend, following], currentListPlaces: [],
                audience: audience, friendIDs: ["friend"])
            let state = context.state(for: LivePlaceIdentity(places: [own.place]), activities: [], featured: true)
            XCTAssertEqual(state.rails, expected)
            XCTAssertFalse(state.isFeatured)
        }
    }

    func testStoreFriendEvidenceIsPreparedOnlyForFriendsWithoutChangingTotemResults() {
        let own = row("own", ownerID: "me")
        let friend = row("friend", ownerID: "friend", status: .wannaGo)
        let following = row("following", ownerID: "following")
        let rows = [own, friend, following]
        let incoming = LocalFollow(localID: "incoming", followerUserID: friend.owner.id,
                                   followedUserID: own.owner.id, source: .profile)
        let follows = [incoming] + [friend, following].map {
            LocalFollow(localID: "outgoing-\($0.owner.id)", followerUserID: own.owner.id,
                        followedUserID: $0.owner.id, source: .profile)
        }
        let store = WanderStore(fixtures: WanderFixtures(currentUser: own.owner,
            profiles: rows.map(\.owner), places: rows.map(\.place), userPlaces: rows.map(\.userPlace),
            placeAttributes: [], follows: follows, blocks: [], placeLists: [], placeListMembers: [],
            placeListItems: [], contactProvider: FakeContactProvider(seededMatches: [])))
        let identity = LivePlaceIdentity(places: rows.map(\.place))
        let events = rows.map { activity("event-\($0.id)", .placeBeen, $0) }
        for incomingTarget in [own.owner.id, "different-viewer", own.owner.id] {
            // A same-object graph edit must be included in the next synchronous
            // context even without a presentation revision or count change.
            incoming.followedUserID = incomingTarget
            let eagerFriends = Set(store.profiles.filter { store.relationship(to: $0.id) == .mutual }.map(\.id))
            for audience in FeedAudience.allCases {
                store.selectFeedAudience(audience)
                for query in [LiveFeedQuery(), .init(activityType: .checkIns),
                              .init(activityType: .wannas), .init(personIDs: [friend.owner.id])] {
                    let actual = store.liveTotemContext(query: query, currentStateIsComplete: true)
                    let eager = LiveTotemContext(currentUserID: store.currentUser.id, query: query,
                        currentSavedPlaces: actual.currentSavedPlaces, currentListPlaces: actual.currentListPlaces,
                        currentListPlaceIDs: actual.currentListPlaceIDs, audience: audience,
                        friendIDs: eagerFriends, currentStateIsComplete: true)
                    XCTAssertEqual(actual.friendIDs, audience == .onlyFriends ? eagerFriends : [])
                    for activity in [[], events] {
                        for featured in [false, true] {
                            XCTAssertEqual(actual.state(for: identity, activities: activity, featured: featured),
                                eager.state(for: identity, activities: activity, featured: featured))
                        }
                    }
                }
            }
        }
    }

    func testDeletedAndInconsistentSaveEvidenceCannotSuppressFeaturedOrProduceRails() {
        let featured = row("featured", ownerID: FeaturedCommunityPlaceSignal.ownerID)
        let deletedSave = row("deleted-save", ownerID: "friend")
        deletedSave.userPlace.deletedAt = now
        let deletedOwner = row("deleted-owner", ownerID: "friend")
        deletedOwner.owner.deletedAt = now
        let inconsistent = row("inconsistent", ownerID: "friend")
        inconsistent.userPlace.userID = "other"
        let state = projection(featured: [featured], saves: [deletedSave, deletedOwner, inconsistent])[0].totemState
        XCTAssertTrue(state.isFeatured)
        XCTAssertFalse(state.hasSavedStatus)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .featured, status: .been)])
    }

    func testCanonicalAliasesShareMembershipAndOneStablePinAcrossQueryChanges() {
        let first = row("first", ownerID: "me")
        let second = row("second", ownerID: "friend", status: .wannaGo)
        let listed = row("listed-alias", ownerID: "friend")
        let been = activity("been", .placeBeen, first)
        let wanna = activity("wanna", .placeWannaGo, second)
        let all = projection(events: [been, wanna], saves: [first, second], memberships: [listed.place])
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(Set(all[0].activities.map(\.id)), [been.id, wanna.id])
        XCTAssertTrue(all[0].totemState.hasListMembership)
        let filtered = projection(events: [wanna], saves: [first, second], memberships: [listed.place],
                                  query: LiveFeedQuery(activityType: .wannas), previous: all)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].id, all[0].id)
        XCTAssertEqual(filtered[0].activities.map(\.id), [wanna.id])
        XCTAssertEqual(filtered[0].totemState.rails, [MapPinOutline(ownership: .social, status: .wannaGo)])
    }

    func testIdentityEvidenceBridgesAliasesWithoutCreatingHiddenPlacePins() {
        let first = row("first", ownerID: "me")
        first.place.canonicalName = "Former name"
        first.place.sourceProviderPlaceID = "provider-first"
        let bridge = row("bridge", ownerID: "me")
        bridge.place.sourceProviderPlaceID = "provider-first"
        let second = row("second", ownerID: "friend")
        second.place.sourceProviderPlaceID = "provider-second"
        let unrelated = row("unrelated", ownerID: "me")
        unrelated.place.sourceProviderPlaceID = "unrelated"
        unrelated.place.address = "99 Other Street"
        let pins = projection(events: [activity("first", .placeBeen, first), activity("second", .placeBeen, second)],
                              saves: [bridge, unrelated])
        XCTAssertEqual(pins.count, 1, "The current save bridges provider and corroborated address aliases.")
        XCTAssertEqual(pins[0].activities.count, 2)
        XCTAssertFalse(pins[0].identity.matches(unrelated.place))
    }

    func testReadableListOnlyMembershipNeedsNoUserPlaceAndRemovalIsImmediate() throws {
        let place = row("list-only", ownerID: "me").place
        let list = LocalPlaceList(localID: "list", ownerUserID: "me", name: "List", description: "")
        let item = LocalPlaceListItem(localID: "item", listID: list.id, placeID: place.id,
                                     addedByUserID: "me", createdAt: now.addingTimeInterval(-1_000_000))
        let store = makeStore(places: [place], lists: [list], items: [item])
        XCTAssertTrue(store.visiblePlaces(in: list).isEmpty, "No fabricated companion save exists.")
        let identity = LivePlaceIdentity(places: [place])
        let before = store.liveTotemContext(query: LiveFeedQuery(occurredAfter: now), currentStateIsComplete: true)
            .state(for: identity, activities: [], featured: true)
        XCTAssertTrue(before.hasListMembership)
        XCTAssertFalse(before.hasSavedStatus)
        XCTAssertFalse(before.isFeatured)
        XCTAssertTrue(store.removePlace(placeID: place.id, from: list))
        let after = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true).state(for: identity, activities: [], featured: true)
        XCTAssertFalse(after.hasListMembership)
        XCTAssertTrue(after.isFeatured)
    }

    func testDeletedOrUnreadableListCannotSupplyMembership() {
        let place = row("place", ownerID: "me").place
        let hidden = LocalPlaceList(localID: "hidden", ownerUserID: "stranger", name: "Hidden", description: "", visibility: .stealth)
        let deleted = LocalPlaceList(localID: "deleted", ownerUserID: "me", name: "Deleted", description: "", deletedAt: now)
        let items = [hidden, deleted].map {
            LocalPlaceListItem(localID: "item-\($0.id)", listID: $0.id, placeID: place.id, addedByUserID: $0.ownerUserID)
        }
        let store = makeStore(places: [place], lists: [hidden, deleted], items: items)
        let state = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: LivePlaceIdentity(places: [place]), activities: [], featured: true)
        XCTAssertFalse(state.hasListMembership)
        XCTAssertTrue(state.isFeatured)
    }

    func testRemovedLastWannaRetainedOnlyForListDoesNotResurrectSavedRail() throws {
        let visible = row("retained", ownerID: "me", status: .wannaGo)
        let list = LocalPlaceList(localID: "list", ownerUserID: "me", name: "List", description: "")
        let item = LocalPlaceListItem(localID: "item", listID: list.id, placeID: visible.place.id,
                                     ownerUserPlaceID: visible.userPlace.id, addedByUserID: "me")
        let store = makeStore(places: [visible.place], saves: [visible.userPlace], lists: [list], items: [item])
        XCTAssertTrue(store.removeImportedWanna(userPlaceID: visible.userPlace.id, wannaID: nil, isOriginal: true))
        XCTAssertNil(visible.userPlace.deletedAt)
        let state = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: LivePlaceIdentity(places: [visible.place]), activities: [], featured: true)
        XCTAssertTrue(state.hasListMembership)
        XCTAssertFalse(state.hasSavedStatus)
        XCTAssertTrue(state.rails.isEmpty)
        XCTAssertFalse(state.isFeatured)
    }

    func testListAliasTombstoneWinsButMembershipInAnotherReadableListSurvives() {
        let place = row("local-place", ownerID: "me").place
        place.serverID = "server-place"
        var first = LocalPlaceList(localID: "local-list", serverID: "server-list", ownerUserID: "me", name: "First", description: "")
        first.createdAt = now.addingTimeInterval(-500)
        let second = LocalPlaceList(localID: "second", ownerUserID: "me", name: "Second", description: "")
        let active = LocalPlaceListItem(localID: "old", listID: first.localID, placeID: place.localID,
            addedByUserID: "me", createdAt: now.addingTimeInterval(-100), updatedAt: now.addingTimeInterval(-100))
        let removed = LocalPlaceListItem(localID: "removed", listID: first.id, placeID: place.id,
            addedByUserID: "me", createdAt: now.addingTimeInterval(-100), updatedAt: now, deletedAt: now)
        let surviving = LocalPlaceListItem(localID: "surviving", listID: second.id, placeID: place.id, addedByUserID: "me")
        let identity = LivePlaceIdentity(places: [place])
        let onlyRemoved = makeStore(places: [place], lists: [first], items: [active, removed])
        XCTAssertFalse(onlyRemoved.liveTotemContext(query: LiveFeedQuery()).state(for: identity, activities: [], featured: false).hasListMembership)
        let stillListed = makeStore(places: [place], lists: [first, second], items: [active, removed, surviving])
        XCTAssertTrue(stillListed.liveTotemContext(query: LiveFeedQuery()).state(for: identity, activities: [], featured: false).hasListMembership)
    }

    func testReadableMembershipCanMatchExactCanonicalIDBeforePlaceCacheHydrates() {
        let place = row("place", ownerID: "me").place
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [], currentListPlaces: [], currentListPlaceIDs: [place.id])
        XCTAssertTrue(context.state(for: LivePlaceIdentity(places: [place]), activities: [], featured: false).hasListMembership)
        let other = row("other", ownerID: "me").place
        XCTAssertFalse(context.state(for: LivePlaceIdentity(places: [other]), activities: [], featured: false).hasListMembership)
    }

    func testAuthoritativeDeletionRemovesStaleRailsMembershipAndPriorOwnHistory() {
        let stale = row("11111111-1111-4111-8111-111111111111", ownerID: "me")
        stale.userPlace.syncStateRaw = SyncState.synced.rawValue
        let event = activity("old-check-in", .placeBeen, stale)
        let snapshot = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: stale.place.id, saves: [], hasListMembership: false)
        ], complete: true)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [stale], currentListPlaces: [stale.place], authoritativeState: snapshot)
        let state = context.state(for: LivePlaceIdentity(places: [stale.place]), activities: [event],
                                  featured: true, additionalSavedPlaces: [stale], hasPriorOwnCheckIn: true)
        XCTAssertFalse(state.hasSavedStatus)
        XCTAssertFalse(state.hasListMembership)
        XCTAssertTrue(state.isFeatured)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .featured, status: .been)])
        let pins = LiveMapProjection.pins(activities: [event], featured: [stale],
                                         ownCheckInPlaces: [stale], totemContext: context)
        XCTAssertEqual(pins[0].activities.map(\.id), [event.id], "Current state does not rewrite the event set.")
        XCTAssertEqual(pins[0].totemState, state)
    }

    func testAuthoritativeIndependentBeenAndWannaRespectActivityAndPeopleFilters() {
        let place = row("22222222-2222-4222-8222-222222222222", ownerID: "me")
        let snapshot = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: place.place.id, saves: [
                LiveMapPinSaveState(ownerID: "me", hasBeen: true, hasWanna: true, isFriend: false),
                LiveMapPinSaveState(ownerID: "friend", hasBeen: true, hasWanna: true, isFriend: true)
            ], hasListMembership: true)
        ], complete: true)
        let cases: [(LiveFeedQuery, [MapPinOutline])] = [
            (LiveFeedQuery(), [MapPinOutline(ownership: .currentUser, status: .been),
                MapPinOutline(ownership: .social, status: .been, secondaryStatus: .wannaGo)]),
            (LiveFeedQuery(activityType: .wannas), [MapPinOutline(ownership: .currentUser, status: .wannaGo),
                MapPinOutline(ownership: .social, status: .wannaGo)]),
            (LiveFeedQuery(activityType: .checkIns, personIDs: ["friend"]),
                [MapPinOutline(ownership: .social, status: .been)]),
            (LiveFeedQuery(personIDs: ["excluded-person"]), [])
        ]
        for (query, expected) in cases {
            let context = LiveTotemContext(currentUserID: "me", query: query,
                currentSavedPlaces: [], currentListPlaces: [], authoritativeState: snapshot)
            let state = context.state(for: LivePlaceIdentity(places: [place.place]), activities: [], featured: true)
            XCTAssertEqual(state.rails, expected)
            XCTAssertTrue(state.hasSavedStatus)
            XCTAssertTrue(state.hasListMembership)
            XCTAssertFalse(state.isFeatured)
        }
    }

    func testAuthoritativeFriendRelationshipOverridesStaleLocalFriendIDs() {
        let place = row("33333333-3333-4333-8333-333333333333", ownerID: "former-friend")
        let snapshot = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: place.place.id, saves: [
                LiveMapPinSaveState(ownerID: "former-friend", hasBeen: true, hasWanna: false, isFriend: false),
                LiveMapPinSaveState(ownerID: "new-friend", hasBeen: false, hasWanna: true, isFriend: true)
            ], hasListMembership: false)
        ], complete: true)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [place], currentListPlaces: [], audience: .onlyFriends,
            friendIDs: ["former-friend"], authoritativeState: snapshot)
        let state = context.state(for: LivePlaceIdentity(places: [place.place]), activities: [], featured: true)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .social, status: .wannaGo)])
        XCTAssertTrue(state.hasSavedStatus)
        XCTAssertFalse(state.isFeatured)
    }

    func testIncompleteOrUncoveredAuthoritativeStateNeverEnablesGreen() {
        let first = row("44444444-4444-4444-8444-444444444444", ownerID: "me")
        let second = row("55555555-5555-4555-8555-555555555555", ownerID: "me")
        let empty = LiveMapPinState(placeID: first.place.id, saves: [], hasListMembership: false)
        let snapshots = [
            LiveMapPinStateSnapshot(states: [empty], complete: false),
            LiveMapPinStateSnapshot(states: [], complete: true),
            LiveMapPinStateSnapshot(states: [empty], complete: true),
            LiveMapPinStateSnapshot(states: [empty, empty], complete: true)
        ]
        for snapshot in snapshots {
            let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                currentSavedPlaces: [], currentListPlaces: [], currentStateIsComplete: true,
                authoritativeState: snapshot)
            let state = context.state(for: LivePlaceIdentity(places: [first.place, second.place]),
                                      activities: [], featured: true)
            XCTAssertFalse(state.isFeatured, "An offline fixture flag cannot bless an incomplete remote response.")
            XCTAssertTrue(state.rails.isEmpty)
        }
    }

    func testPartialAuthoritativeStateFallsBackToKnownEvidenceWithoutRemovingIt() {
        let place = row("66666666-6666-4666-8666-666666666666", ownerID: "me", status: .wannaGo)
        let snapshot = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: place.place.id, saves: [], hasListMembership: false)
        ], complete: false)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [place], currentListPlaces: [place.place], authoritativeState: snapshot)
        let state = context.state(for: LivePlaceIdentity(places: [place.place]), activities: [], featured: true)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .currentUser, status: .wannaGo)])
        XCTAssertTrue(state.hasListMembership)
        XCTAssertTrue(state.hasSavedStatus)
        XCTAssertFalse(state.isFeatured)
    }

    func testCompleteCanonicalAliasStatesUnionWithoutDuplicatingPinsOrEvents() {
        let first = row("77777777-7777-4777-8777-777777777777", ownerID: "me")
        first.userPlace.syncStateRaw = SyncState.synced.rawValue
        let alias = row("88888888-8888-4888-8888-888888888888", ownerID: "friend", status: .wannaGo)
        let facet = LiveMapPinSaveState(ownerID: "friend", hasBeen: false, hasWanna: true, isFriend: true)
        let snapshot = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: first.place.id.uppercased(), saves: [facet], hasListMembership: true),
            LiveMapPinState(placeID: alias.place.id, saves: [facet], hasListMembership: true)
        ], complete: true)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [first], currentListPlaces: [], authoritativeState: snapshot)
        let events = [activity("first", .placeBeen, first), activity("alias", .placeWannaGo, alias)]
        let pins = LiveMapProjection.pins(activities: events, featured: [], totemContext: context)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(Set(pins[0].activities.map(\.id)), Set(events.map(\.id)))
        XCTAssertEqual(pins[0].totemState.rails, [MapPinOutline(ownership: .social, status: .wannaGo)])
        XCTAssertTrue(pins[0].totemState.hasListMembership)
        XCTAssertFalse(pins[0].totemState.isFeatured)
    }

    func testRemoteNegativeSnapshotThenResetCannotResurrectStaleAssociations() {
        let stale = row("99999999-9999-4999-8999-999999999999", ownerID: "friend", status: .wannaGo)
        let event = activity("old-wanna", .placeWannaGo, stale)
        let negative = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: stale.place.id, saves: [], hasListMembership: false)
        ], complete: true)
        for snapshot in [negative, nil] {
            let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                currentSavedPlaces: [stale], currentListPlaces: [stale.place],
                authoritativeState: snapshot, allowsCachedAssociations: false)
            let pins = LiveMapProjection.pins(activities: [event], featured: [],
                                             ownCheckInPlaces: [stale], totemContext: context)
            XCTAssertEqual(pins[0].totemState, .empty,
                           "Refresh/expiry must not re-show a server-removed association from caches.")
            XCTAssertEqual(pins[0].activities.map(\.id), [event.id])
        }
    }

    func testRemoteIncompleteSnapshotStaysNeutralDespiteSyncedFallbackSources() {
        let stale = row("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ownerID: "me")
        stale.userPlace.syncStateRaw = SyncState.synced.rawValue
        let partial = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: stale.place.id, saves: [
                LiveMapPinSaveState(ownerID: "me", hasBeen: true, hasWanna: true, isFriend: false)
            ], hasListMembership: true)
        ], complete: false)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [stale], currentListPlaces: [stale.place], currentStateIsComplete: true,
            authoritativeState: partial, allowsCachedAssociations: false)
        let state = context.state(for: LivePlaceIdentity(places: [stale.place]),
            activities: [activity("old-check-in", .placeBeen, stale)], featured: true,
            additionalSavedPlaces: [stale], hasPriorOwnCheckIn: true)
        XCTAssertEqual(state, .empty)
    }

    func testRemoteCompleteSnapshotStillShowsVerifiedAssociationsWithCacheFallbackDisabled() {
        let place = row("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", ownerID: "me")
        place.userPlace.syncStateRaw = SyncState.synced.rawValue
        let verified = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: place.place.id, saves: [
                LiveMapPinSaveState(ownerID: "friend", hasBeen: false, hasWanna: true, isFriend: true)
            ], hasListMembership: true)
        ], complete: true)
        let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
            currentSavedPlaces: [place], currentListPlaces: [], authoritativeState: verified,
            allowsCachedAssociations: false)
        let state = context.state(for: LivePlaceIdentity(places: [place.place]), activities: [], featured: true)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .social, status: .wannaGo)])
        XCTAssertTrue(state.hasListMembership)
        XCTAssertTrue(state.hasSavedStatus)
        XCTAssertFalse(state.isFeatured)
    }

    func testActiveOwnUnsyncedSaveSuppressesGreenUntilItsWriteIsResolved() {
        let cases: [(SyncState, String?)] = [
            (.localOnly, nil), (.pendingCreate, nil),
            (.pendingUpdate, "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
            (.failed, nil), (.failed, "dddddddd-dddd-4ddd-8ddd-dddddddddddd")
        ]
        for (sync, serverID) in cases {
            for status in [PlaceStatus.been, .wannaGo] {
                let own = row("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", ownerID: "me", status: status)
                own.userPlace.syncStateRaw = sync.rawValue
                own.userPlace.serverID = serverID
                let empty = LiveMapPinStateSnapshot(states: [
                    LiveMapPinState(placeID: own.place.id, saves: [], hasListMembership: false)
                ], complete: true)
                let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(personIDs: ["someone-else"]),
                    currentSavedPlaces: [own], currentListPlaces: [], authoritativeState: empty,
                    allowsCachedAssociations: false)
                let state = context.state(for: LivePlaceIdentity(places: [own.place]), activities: [], featured: true)
                XCTAssertFalse(state.isFeatured, "Active own \(sync.rawValue) must suppress green even outside People filters.")
                XCTAssertTrue(state.hasSavedStatus)
                XCTAssertTrue(state.rails.isEmpty, "People filtering excludes the pending own rail without enabling green.")
                own.userPlace.syncStateRaw = SyncState.synced.rawValue
                let resolved = context.state(for: LivePlaceIdentity(places: [own.place]), activities: [], featured: true)
                XCTAssertTrue(resolved.isFeatured, "Once synced, authoritative absence overrides the old local summary.")
                XCTAssertFalse(resolved.hasSavedStatus)
            }
        }
    }

    func testDeletedDeniedOrOtherUsersPendingWritesCannotRestoreOwnOrSocialRails() {
        for sync in [SyncState.pendingCreate, .pendingUpdate, .failed, .pendingDelete, .serverDenied, .tombstoned] {
            let own = row("ffffffff-ffff-4fff-8fff-ffffffffffff", ownerID: "me", status: .wannaGo)
            own.userPlace.syncStateRaw = sync.rawValue
            if [.pendingCreate, .pendingUpdate, .failed].contains(sync) { own.userPlace.deletedAt = now }
            let social = row("ffffffff-ffff-4fff-8fff-ffffffffffff", ownerID: "friend", status: .wannaGo)
            social.userPlace.syncStateRaw = SyncState.pendingCreate.rawValue
            let empty = LiveMapPinStateSnapshot(states: [
                LiveMapPinState(placeID: own.place.id, saves: [], hasListMembership: false)
            ], complete: true)
            let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                currentSavedPlaces: [own, social], currentListPlaces: [], authoritativeState: empty,
                allowsCachedAssociations: false)
            let state = context.state(for: LivePlaceIdentity(places: [own.place]), activities: [], featured: true)
            XCTAssertFalse(state.hasSavedStatus)
            XCTAssertTrue(state.isFeatured)
            XCTAssertEqual(state.rails, [MapPinOutline(ownership: .featured, status: .been)])
        }
    }

    func testBarePrivateListCompanionDoesNotInventWannaButLaterExplicitVisitDoes() throws {
        let companion = row("private-list-companion", ownerID: "me", status: .wannaGo)
        companion.userPlace.isPrivateListCompanion = true
        let list = LocalPlaceList(localID: "private-list", ownerUserID: "me", name: "Private", description: "", visibility: .stealth)
        let item = LocalPlaceListItem(localID: "private-item", listID: list.id, placeID: companion.place.id,
                                     ownerUserPlaceID: companion.userPlace.id, addedByUserID: "me")
        let store = makeStore(places: [companion.place], saves: [companion.userPlace], lists: [list], items: [item])
        let identity = LivePlaceIdentity(places: [companion.place])
        let bare = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: identity, activities: [activity("list-event", .listItemAdded, companion)], featured: true)
        XCTAssertTrue(bare.hasListMembership)
        XCTAssertFalse(bare.hasSavedStatus)
        XCTAssertFalse(bare.isFeatured)
        XCTAssertTrue(bare.rails.isEmpty)

        let explicitEvent = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: identity, activities: [activity("explicit-wanna", .placeWannaGo, companion)], featured: true)
        XCTAssertEqual(explicitEvent.rails, [MapPinOutline(ownership: .currentUser, status: .wannaGo)])

        _ = try XCTUnwrap(store.createVisit(userPlaceID: companion.userPlace.id, note: nil, visibility: .selfOnly))
        XCTAssertTrue(companion.userPlace.isPrivateListCompanion, "The marker persists after a genuine check-in.")
        let visited = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: identity, activities: [], featured: true)
        XCTAssertEqual(visited.rails, [MapPinOutline(ownership: .currentUser, status: .been)])
        XCTAssertTrue(visited.hasSavedStatus)
    }

    func testPrivateListCompanionWithIndependentWannaHistoryRetainsWannaRail() async {
        let companion = row("private-repeat-wanna", ownerID: "me", status: .wannaGo)
        companion.userPlace.isPrivateListCompanion = true
        let store = makeStore(places: [companion.place], saves: [companion.userPlace], lists: [], items: [])
        let candidate = PlaceSheetPlace(visiblePlace: companion).saveCandidate
        _ = await store.saveNewWanna(candidate, visibility: .selfOnly, note: nil,
                                    plannedDate: nil, attributes: [], backend: nil)
        XCTAssertFalse(store.wannaSaves(for: companion.userPlace).isEmpty)
        XCTAssertTrue(companion.userPlace.isPrivateListCompanion)
        let state = store.liveTotemContext(query: LiveFeedQuery(), currentStateIsComplete: true)
            .state(for: LivePlaceIdentity(places: [companion.place]), activities: [], featured: true)
        XCTAssertTrue(state.hasSavedStatus)
        XCTAssertFalse(state.isFeatured)
        XCTAssertEqual(state.rails, [MapPinOutline(ownership: .currentUser, status: .wannaGo)])
    }

    func testPendingOwnListAdditionKeepsBadgeWithoutInventingCompanionWanna() {
        for sync in [SyncState.localOnly, .pendingCreate, .pendingUpdate, .failed] {
            let companion = row("12121212-1212-4212-8212-121212121212", ownerID: "me", status: .wannaGo)
            companion.userPlace.isPrivateListCompanion = true
            companion.userPlace.syncStateRaw = SyncState.pendingCreate.rawValue
            let list = LocalPlaceList(localID: "pending-list", ownerUserID: "me", name: "List", description: "", visibility: .stealth)
            let item = LocalPlaceListItem(localID: "pending-item", listID: list.id, placeID: companion.place.id,
                ownerUserPlaceID: companion.userPlace.id, addedByUserID: "me", syncState: sync,
                createdAt: now.addingTimeInterval(-90 * 86_400))
            let store = makeStore(places: [companion.place], saves: [companion.userPlace], lists: [list], items: [item])
            let absent = LiveMapPinStateSnapshot(states: [
                LiveMapPinState(placeID: companion.place.id, saves: [], hasListMembership: false)
            ], complete: true)
            for snapshot in [absent, nil] {
                let context = store.liveTotemContext(query: LiveFeedQuery(occurredAfter: now.addingTimeInterval(-86_400)),
                    authoritativeState: snapshot, allowsCachedAssociations: false)
                let state = context.state(for: LivePlaceIdentity(places: [companion.place]), activities: [], featured: true)
                XCTAssertTrue(state.hasListMembership, "Own \(sync.rawValue) membership remains visible locally.")
                XCTAssertFalse(state.isFeatured)
                XCTAssertFalse(state.hasSavedStatus)
                XCTAssertTrue(state.rails.isEmpty)
            }
        }
    }

    func testRemovingPendingOwnMembershipStopsLocalOverrideImmediately() {
        let place = row("13131313-1313-4313-8313-131313131313", ownerID: "me").place
        let list = LocalPlaceList(localID: "list", ownerUserID: "me", name: "List", description: "")
        let item = LocalPlaceListItem(localID: "item", listID: list.id, placeID: place.id,
                                     addedByUserID: "me", syncState: .pendingCreate)
        let store = makeStore(places: [place], lists: [list], items: [item])
        let absent = LiveMapPinStateSnapshot(states: [
            LiveMapPinState(placeID: place.id, saves: [], hasListMembership: false)
        ], complete: true)
        let identity = LivePlaceIdentity(places: [place])
        XCTAssertTrue(store.liveTotemContext(query: LiveFeedQuery(), authoritativeState: absent,
            allowsCachedAssociations: false).state(for: identity, activities: [], featured: true).hasListMembership)
        XCTAssertTrue(store.removePlace(placeID: place.id, from: list))
        let removed = store.liveTotemContext(query: LiveFeedQuery(), authoritativeState: absent,
            allowsCachedAssociations: false).state(for: identity, activities: [], featured: true)
        XCTAssertFalse(removed.hasListMembership)
        XCTAssertTrue(removed.isFeatured)
    }

    func testSyncedSocialRemovedAndUnreadableItemsCannotOverrideAuthoritativeMembershipAbsence() {
        let cases: [(String, SyncState, Bool, Bool, Bool)] = [
            ("me", .synced, false, true, false), ("friend", .pendingCreate, false, true, false),
            ("me", .pendingDelete, false, true, false), ("me", .serverDenied, false, true, false),
            ("me", .tombstoned, false, true, false), ("me", .failed, true, true, false),
            ("me", .pendingCreate, false, false, false), ("me", .pendingCreate, false, true, true)
        ]
        for (actor, sync, deletedItem, readable, deletedList) in cases {
            let place = row("14141414-1414-4414-8414-141414141414", ownerID: "me").place
            let list = LocalPlaceList(localID: "list", ownerUserID: readable ? "me" : "stranger",
                name: "List", description: "", visibility: .stealth, deletedAt: deletedList ? now : nil)
            let item = LocalPlaceListItem(localID: "item", listID: list.id, placeID: place.id,
                addedByUserID: actor, syncState: sync, deletedAt: deletedItem ? now : nil)
            let store = makeStore(places: [place], lists: [list], items: [item])
            let absent = LiveMapPinStateSnapshot(states: [
                LiveMapPinState(placeID: place.id, saves: [], hasListMembership: false)
            ], complete: true)
            let state = store.liveTotemContext(query: LiveFeedQuery(), authoritativeState: absent,
                allowsCachedAssociations: false).state(for: LivePlaceIdentity(places: [place]), activities: [], featured: true)
            XCTAssertFalse(state.hasListMembership)
            XCTAssertTrue(state.isFeatured)
        }
    }

    func testPendingOwnRailsRespectActivityFiltersAndDisappearAfterSyncedAbsence() {
        for status in [PlaceStatus.been, .wannaGo] {
            for sync in [SyncState.pendingCreate, .pendingUpdate, .failed] {
                let own = row("15151515-1515-4515-8515-151515151515", ownerID: "me", status: status)
                own.userPlace.syncStateRaw = sync.rawValue
                let absent = LiveMapPinStateSnapshot(states: [
                    LiveMapPinState(placeID: own.place.id, saves: [], hasListMembership: false)
                ], complete: true)
                let identity = LivePlaceIdentity(places: [own.place])
                for snapshot in [absent, nil] {
                    let context = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                        currentSavedPlaces: [own], currentListPlaces: [], authoritativeState: snapshot,
                        allowsCachedAssociations: false)
                    let state = context.state(for: identity, activities: [], featured: true)
                    XCTAssertEqual(state.rails, [MapPinOutline(ownership: .currentUser, status: status)])
                    XCTAssertFalse(state.isFeatured)
                    let excluded = LiveTotemContext(currentUserID: "me",
                        query: LiveFeedQuery(activityType: status == .been ? .wannas : .checkIns),
                        currentSavedPlaces: [own], currentListPlaces: [], authoritativeState: snapshot,
                        allowsCachedAssociations: false).state(for: identity, activities: [], featured: true)
                    XCTAssertTrue(excluded.rails.isEmpty)
                    XCTAssertTrue(excluded.hasSavedStatus)
                    XCTAssertFalse(excluded.isFeatured)
                }
                own.userPlace.syncStateRaw = SyncState.synced.rawValue
                let resolved = LiveTotemContext(currentUserID: "me", query: LiveFeedQuery(),
                    currentSavedPlaces: [own], currentListPlaces: [], authoritativeState: absent,
                    allowsCachedAssociations: false).state(for: identity, activities: [], featured: true)
                XCTAssertEqual(resolved.rails, [MapPinOutline(ownership: .featured, status: .been)])
                XCTAssertFalse(resolved.hasSavedStatus)
            }
        }
    }

    private func projection(events: [FeedActivity] = [], featured: [VisiblePlace] = [],
                            saves: [VisiblePlace] = [], memberships: [LocalPlace] = [],
                            query: LiveFeedQuery = LiveFeedQuery(), previous: [LivePlacePin] = []) -> [LivePlacePin] {
        LiveMapProjection.pins(activities: events, featured: featured,
            totemContext: LiveTotemContext(currentUserID: "me", query: query,
                currentSavedPlaces: saves, currentListPlaces: memberships, currentStateIsComplete: true), previousPins: previous)
    }

    private func row(_ id: String, ownerID: String, status: PlaceStatus = .been) -> VisiblePlace {
        let place = LocalPlace(localID: id, canonicalName: "Shared Cafe", category: "coffee", address: "10 Main Street",
            locality: "Sampleton", region: "CA", country: "US", latitude: 34.05, longitude: -118.24,
            sourceProvider: "mapkit", sourceProviderPlaceID: "same-cafe")
        let owner = LocalProfile(localID: ownerID, handle: ownerID, displayName: ownerID)
        let save = LocalUserPlace(localID: "save-\(id)", userID: ownerID, placeID: place.id,
            status: status, visibility: .followers, savedAt: now.addingTimeInterval(-1_000_000), sourceType: "manual")
        return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
    }

    private func activity(_ id: String, _ kind: FeedActivityKind, _ place: VisiblePlace) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
            actor: ProfileShell(id: place.owner.id, handle: place.owner.handle, displayName: place.owner.displayName,
                                avatarURL: nil, bio: nil, relationship: .mutual), place: place, occurredAt: now)
    }

    private func makeStore(places: [LocalPlace], saves: [LocalUserPlace] = [],
                           lists: [LocalPlaceList], items: [LocalPlaceListItem]) -> WanderStore {
        let me = LocalProfile(localID: "me", handle: "me", displayName: "Me")
        return WanderStore(fixtures: WanderFixtures(currentUser: me, profiles: [me], places: places,
            userPlaces: saves, placeAttributes: [], follows: [], blocks: [], placeLists: lists,
            placeListMembers: [], placeListItems: items, contactProvider: WanderFixtures.empty().contactProvider))
    }
}
