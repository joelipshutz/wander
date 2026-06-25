import Foundation
import SwiftData

struct WanderFixtures {
    let currentUser: LocalProfile
    let profiles: [LocalProfile]
    let places: [LocalPlace]
    let userPlaces: [LocalUserPlace]
    let placeAttributes: [LocalPlaceAttribute]
    let follows: [LocalFollow]
    let blocks: [LocalBlock]
    let contactProvider: FakeContactProvider

    @MainActor
    static func empty() -> WanderFixtures {
        let currentUser = LocalProfile(
            localID: "local_profile_current",
            handle: "you",
            displayName: "You",
            syncState: .localOnly
        )

        return WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser],
            places: [],
            userPlaces: [],
            placeAttributes: [],
            follows: [],
            blocks: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        )
    }

    @MainActor
    static func seed() -> WanderFixtures {
        let currentUser = LocalProfile(localID: "local_profile_joe", serverID: "user_joe", handle: "joe", displayName: "Joe", bio: "Coffee, hikes, good tables.", syncState: .synced)
        let maya = LocalProfile(localID: "local_profile_maya", serverID: "user_maya", handle: "maya", displayName: "Maya", homeArea: "LA", syncState: .synced)
        let ryan = LocalProfile(localID: "local_profile_ryan", serverID: "user_ryan", handle: "ryan", displayName: "Ryan", homeArea: "Brooklyn", syncState: .synced)

        let coffee = LocalPlace(localID: "local_place_woodcat", serverID: "place_woodcat", canonicalName: "Woodcat Coffee", category: "coffee", latitude: 34.077, longitude: -118.260, sourceProvider: "mapkit", syncState: .synced)
        let hike = LocalPlace(localID: "local_place_griffith", serverID: "place_griffith", canonicalName: "Griffith Observatory Trail", category: "hike", latitude: 34.119, longitude: -118.300, sourceProvider: "mapkit", syncState: .synced)
        let noodles = LocalPlace(localID: "local_place_noodles", serverID: "place_noodles", canonicalName: "Larchmont Noodles", category: "restaurant", latitude: 34.073, longitude: -118.323, sourceProvider: "mapkit", syncState: .synced)

        let userPlaces = [
            LocalUserPlace(localID: "local_up_joe_woodcat", serverID: "up_joe_woodcat", userID: currentUser.id, placeID: coffee.id, status: .been, visibility: .followers, note: "Good morning table by the window.", ratingScore: 4, recommendedScore: 4, recommendedCount: 1, nearbyConfirmed: true, sourceType: "manual", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_griffith", serverID: "up_maya_griffith", userID: maya.id, placeID: hike.id, status: .been, visibility: .followers, note: "Easy sunset win.", ratingScore: 5, recommendedScore: 5, recommendedCount: 1, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_noodles", serverID: "up_ryan_noodles", userID: ryan.id, placeID: noodles.id, status: .wannaGo, visibility: .mutuals, note: "Saved for a rainy night.", sourceType: "social_seed", syncState: .synced)
        ]

        let placeAttributes = [
            LocalPlaceAttribute(localID: "local_attr_joe_woodcat_work", serverID: "attr_joe_woodcat_work", userPlaceID: "up_joe_woodcat", questionKey: "work_setup", valueType: "single_choice", valueJSON: "\"yes\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_woodcat_tags", serverID: "attr_joe_woodcat_tags", userPlaceID: "up_joe_woodcat", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"wifi solid\",\"quiet\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_griffith_strenuousness", serverID: "attr_maya_griffith_strenuousness", userPlaceID: "up_maya_griffith", questionKey: "strenuousness", valueType: "single_choice", valueJSON: "\"easy\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_griffith_tags", serverID: "attr_maya_griffith_tags", userPlaceID: "up_maya_griffith", questionKey: "hike_tags", valueType: "multi_tag", valueJSON: "[\"sunset\",\"views\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_interest", serverID: "attr_ryan_noodles_interest", userPlaceID: "up_ryan_noodles", questionKey: "interest_signal", valueType: "emoji_scale", valueJSON: "\"excited\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_price", serverID: "attr_ryan_noodles_price", userPlaceID: "up_ryan_noodles", questionKey: "price", valueType: "price_scale", valueJSON: "\"$$\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_occasion", serverID: "attr_ryan_noodles_occasion", userPlaceID: "up_ryan_noodles", questionKey: "occasion", valueType: "single_choice", valueJSON: "\"rainy night\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_tags", serverID: "attr_ryan_noodles_tags", userPlaceID: "up_ryan_noodles", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"cozy\",\"worth it\"]", syncState: .synced)
        ]

        let follows = [
            LocalFollow(localID: "local_follow_joe_maya", serverID: "follow_joe_maya", followerUserID: currentUser.id, followedUserID: maya.id, source: .contacts, syncState: .synced),
            LocalFollow(localID: "local_follow_ryan_joe", serverID: "follow_ryan_joe", followerUserID: ryan.id, followedUserID: currentUser.id, source: .profile, syncState: .synced),
            LocalFollow(localID: "local_follow_joe_ryan", serverID: "follow_joe_ryan", followerUserID: currentUser.id, followedUserID: ryan.id, source: .profile, syncState: .synced)
        ]

        let contacts = FakeContactProvider(seededMatches: [
            ContactMatch(id: "contact_maya", displayName: "Maya", handle: "maya", userID: maya.id, isAlreadyFollowing: true, followsCurrentUser: false),
            ContactMatch(id: "contact_sam", displayName: "Sam", handle: nil, userID: nil, isAlreadyFollowing: false, followsCurrentUser: false)
        ])

        return WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser, maya, ryan],
            places: [coffee, hike, noodles],
            userPlaces: userPlaces,
            placeAttributes: placeAttributes,
            follows: follows,
            blocks: [],
            contactProvider: contacts
        )
    }
}

enum WanderModelContainer {
    static var preview: ModelContainer {
        let schema = Schema([
            LocalProfile.self,
            LocalFollow.self,
            LocalBlock.self,
            LocalPlace.self,
            LocalUserPlace.self,
            LocalPlaceAttribute.self,
            LocalSourceArtifact.self,
            LocalExtractionJob.self,
            SyncOperation.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create preview model container: \(error)")
        }
    }
}
