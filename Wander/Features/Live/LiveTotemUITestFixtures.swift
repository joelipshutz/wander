#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Fictional, memory-only data exercised by the real Live map, filters and Feed.
/// Ordinary launches and device builds cannot activate this review fixture.
@MainActor
enum LiveTotemUITestFixtures {
    static var isEnabled: Bool {
        isEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static func isEnabled(arguments: [String]) -> Bool {
        ["-WanderLiveTotemUITest", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
         "-WanderUnifiedLiveUITest"].allSatisfy(arguments.contains)
    }

    static func fixtures(base: WanderFixtures, now: Date = .now) -> WanderFixtures {
        let owner = base.currentUser
        let community = LocalProfile(localID: FeaturedCommunityPlaceSignal.ownerID,
            handle: "featured_fixture", displayName: "Featured", syncState: .synced)
        let definitions: [(String, String, String, Double, Double)] = [
            ("coffee", "Woodcat Coffee", "coffee", 34.084, -118.265),
            ("tacos", "Mariposa Tacos", "restaurant", 34.076, -118.280),
            ("bar", "Bar Nido", "bar", 34.091, -118.276),
            ("noodles", "Larchmont Noodles", "restaurant", 34.080, -118.296),
            ("mixed", "Circuit Coffee", "coffee", 34.095, -118.292),
            ("list", "Echo Park Bookshop", "shopping", 34.068, -118.266),
            ("featured", "Sunday Studio", "arts_culture", 34.071, -118.299),
            ("featured_list", "Silver Lake Garden", "park", 34.102, -118.265)
        ]
        var places = definitions.map { id, name, category, latitude, longitude in
            LocalPlace(localID: "totem_\(id)", canonicalName: name, category: category,
                locality: "Los Angeles", region: "CA", latitude: latitude, longitude: longitude,
                sourceProvider: "mapkit", syncState: .synced)
        }
        // Legacy MapKit IDs and country code/name variants for the same venue.
        // The current save and Featured candidate must still share one marker.
        if let tacos = places.first(where: { $0.id == "totem_tacos" }) {
            tacos.address = "10 Example Street"; tacos.country = "US"
            tacos.sourceProviderPlaceID = "mapkit_mariposa-tacos"
            places.append(LocalPlace(localID: "totem_tacos_featured_alias", canonicalName: tacos.canonicalName,
                category: tacos.category, address: "10 Example St", locality: tacos.locality,
                region: tacos.region, country: "United States", latitude: tacos.latitude, longitude: tacos.longitude,
                sourceProvider: "mapkit", sourceProviderPlaceID: "mapkit_mariposa_tacos", syncState: .synced))
        }
        let saves: [(String, String, PlaceStatus, Double, String?)] = [
            ("coffee", owner.id, .been, 3, "The window seat, a flat white, and nowhere to rush."),
            ("tacos", owner.id, .wannaGo, 5, "Saving this for Saturday lunch."),
            ("bar", "user_maya", .been, 7, "A little courtyard worth coming back to."),
            ("noodles", "user_ryan", .wannaGo, 9, "Next rainy evening."),
            ("mixed", owner.id, .been, 50, "Excellent coffee. Keep this one."),
            ("mixed", "user_maya", .been, 13, "Coffee before the walk."),
            ("mixed", "user_ryan", .wannaGo, 1, "On my weekend shortlist.")
        ]
        var userPlaces = saves.map { id, userID, status, hours, note in
            LocalUserPlace(localID: "totem_save_\(id)_\(userID)", userID: userID,
                placeID: "totem_\(id)", status: status, visibility: .followers, note: note,
                visitedAt: status == .been ? now.addingTimeInterval(-hours * 3600) : nil,
                savedAt: now.addingTimeInterval(-hours * 3600), sourceType: "manual", syncState: .synced)
        }
        for id in ["featured", "featured_list", "tacos"] {
            userPlaces.append(LocalUserPlace(localID: "totem_aggregate_\(id)", userID: community.id,
                placeID: id == "tacos" ? "totem_tacos_featured_alias" : "totem_\(id)", status: .been, visibility: .followers,
                sourceType: "featured_community_aggregate", syncState: .synced))
        }
        let lists = [
            LocalPlaceList(localID: "totem_weekend", ownerUserID: owner.id, name: "Weekend spots",
                description: "A few places for an unhurried weekend.", syncState: .synced),
            LocalPlaceList(localID: "totem_favorites", ownerUserID: owner.id, name: "Worth returning to",
                description: "Keep these close.", syncState: .synced),
            LocalPlaceList(localID: "totem_maya_list", ownerUserID: "user_maya", name: "Maya's neighborhood",
                description: "Small discoveries around the neighborhood.", syncState: .synced)
        ]
        let memberships: [(String, String, String, Double)] = [
            ("coffee", "totem_favorites", owner.id, 90 * 24),
            ("tacos", "totem_weekend", owner.id, 5),
            ("list", "totem_weekend", owner.id, 2),
            ("mixed", "totem_favorites", owner.id, 50),
            ("mixed", "totem_weekend", owner.id, 49.9),
            ("mixed", "totem_maya_list", "user_maya", 12.9),
            ("featured_list", "totem_maya_list", "user_maya", 4)
        ]
        let items = memberships.map { id, listID, actorID, hours in
            LocalPlaceListItem(localID: "totem_item_\(id)_\(listID)", listID: listID,
                placeID: "totem_\(id)", addedByUserID: actorID, syncState: .synced,
                createdAt: now.addingTimeInterval(-hours * 3600), updatedAt: now.addingTimeInterval(-hours * 3600))
        }
        var follows = base.follows
        follows.append(LocalFollow(localID: "totem_featured_follow", followerUserID: owner.id,
            followedUserID: community.id, source: .profile, syncState: .synced))
        return WanderFixtures(currentUser: owner, profiles: base.profiles + [community],
            places: places, userPlaces: userPlaces, placeAttributes: [], follows: follows, blocks: [],
            placeLists: lists, placeListMembers: [], placeListItems: items, contactProvider: base.contactProvider)
    }

    static func feedPage(store: WanderStore, now: Date) -> FollowedFeedPage {
        let visible = store.visiblePlaces().filter { !$0.isCommunityAggregate }
        var activity = visible.map { place in
            FeedActivity(id: "totem_event_\(place.userPlace.id)",
                kind: place.userPlace.status == .been ? .placeBeen : .placeWannaGo,
                actor: store.shell(for: place.owner), place: place,
                occurredAt: place.userPlace.visitedAt ?? place.userPlace.savedAt, note: place.userPlace.note)
        }
        for item in store.liveReadableListItems() {
            guard let list = store.visiblePlaceLists.first(where: { $0.id == item.listID }),
                  let actor = store.profile(for: item.addedByUserID),
                  let place = store.places.first(where: { $0.id == item.placeID }) else { continue }
            // A list activity's envelope is structural. It creates no saved
            // userPlace and must not imply a Wanna rail in the Totem resolver.
            let envelope = visible.first { $0.place.id == place.id && $0.owner.id == actor.id }
                ?? VisiblePlace(id: "totem_list_envelope_\(item.id)", place: place,
                    userPlace: LocalUserPlace(localID: "totem_list_envelope_\(item.id)", userID: actor.id,
                        placeID: place.id, status: .wannaGo, visibility: .followers,
                        sourceType: "list", isPrivateListCompanion: true), owner: actor)
            activity.append(FeedActivity(id: "totem_list_event_\(item.id)", kind: .listItemAdded,
                actor: store.shell(for: actor), place: envelope, list: list, occurredAt: item.createdAt))
        }
        return FollowedFeedPage(activity: FeedPresentation.newestFirst(activity),
            featuredPlaces: [], nextCursor: nil, fetchedAt: now)
    }
}
#endif
