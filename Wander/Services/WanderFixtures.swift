import Foundation
import SwiftData

struct WanderFixtures {
    let currentUser: LocalProfile
    let profiles: [LocalProfile]
    let places: [LocalPlace]
    let userPlaces: [LocalUserPlace]
    let placeAttributes: [LocalPlaceAttribute]
    var placeVisits: [LocalPlaceVisit] = []
    var visitPhotos: [LocalVisitPhoto] = []
    let follows: [LocalFollow]
    let blocks: [LocalBlock]
    var mutes: [LocalMute] = []
    let placeLists: [LocalPlaceList]
    let placeListMembers: [LocalPlaceListMember]
    let placeListItems: [LocalPlaceListItem]
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
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        )
    }

    @MainActor
    static func seed() -> WanderFixtures {
        let currentUser = LocalProfile(localID: "local_profile_joe", serverID: "user_joe", handle: "joe", displayName: "Joe", bio: "Coffee, hikes, good tables.", syncState: .synced)
        let maya = LocalProfile(localID: "local_profile_maya", serverID: "user_maya", handle: "maya", displayName: "Maya", homeArea: "LA", syncState: .synced)
        let ryan = LocalProfile(localID: "local_profile_ryan", serverID: "user_ryan", handle: "ryan", displayName: "Ryan", homeArea: "Brooklyn", syncState: .synced)
        let demo = LocalProfile(localID: "local_profile_demo", serverID: "user_demo", handle: "demo", displayName: "Demo", homeArea: "LA", syncState: .synced)

        let coffee = LocalPlace(localID: "local_place_woodcat", serverID: "place_woodcat", canonicalName: "Woodcat Coffee", category: "coffee", latitude: 34.077, longitude: -118.260, sourceProvider: "mapkit", syncState: .synced)
        let hike = LocalPlace(localID: "local_place_griffith", serverID: "place_griffith", canonicalName: "Griffith Observatory Trail", category: "hike", latitude: 34.119, longitude: -118.300, sourceProvider: "mapkit", syncState: .synced)
        let noodles = LocalPlace(localID: "local_place_noodles", serverID: "place_noodles", canonicalName: "Larchmont Noodles", category: "restaurant", latitude: 34.073, longitude: -118.323, sourceProvider: "mapkit", syncState: .synced)
        let laptopCoffee = LocalPlace(localID: "local_place_circuit_coffee", serverID: "place_circuit_coffee", canonicalName: "Circuit Coffee", category: "coffee", address: "1824 Hyperion Ave", locality: "Los Angeles", region: "CA", latitude: 34.094, longitude: -118.273, sourceProvider: "mapkit", websiteURLString: "https://example.com/circuit-coffee", phoneNumber: "+1 (323) 555-0182", syncState: .synced)
        let dinner = LocalPlace(localID: "local_place_bar_nido", serverID: "place_bar_nido", canonicalName: "Bar Nido", category: "restaurant", address: "1280 Glendale Blvd", locality: "Los Angeles", region: "CA", latitude: 34.079, longitude: -118.260, sourceProvider: "mapkit", websiteURLString: "https://example.com/bar-nido", phoneNumber: "+1 (323) 555-0148", syncState: .synced)
        let picnic = LocalPlace(localID: "local_place_elysian_picnic", serverID: "place_elysian_picnic", canonicalName: "Elysian Picnic Steps", category: "park", address: "929 Academy Rd", locality: "Los Angeles", region: "CA", latitude: 34.082, longitude: -118.237, sourceProvider: "mapkit", syncState: .synced)
        let demoCoffee = LocalPlace(localID: "local_place_fern_desk_coffee", serverID: "place_fern_desk_coffee", canonicalName: "Fern Desk Coffee", category: "coffee", address: "744 Virgil Ave", locality: "Los Angeles", region: "CA", latitude: 34.085, longitude: -118.287, sourceProvider: "mapkit", websiteURLString: "https://example.com/fern-desk-coffee", phoneNumber: "+1 (323) 555-0119", syncState: .synced)
        let demoDinner = LocalPlace(localID: "local_place_juniper_table", serverID: "place_juniper_table", canonicalName: "Juniper Table", category: "restaurant", address: "2106 Sunset Blvd", locality: "Los Angeles", region: "CA", latitude: 34.078, longitude: -118.266, sourceProvider: "mapkit", websiteURLString: "https://example.com/juniper-table", phoneNumber: "+1 (323) 555-0127", syncState: .synced)

        let userPlaces = [
            LocalUserPlace(localID: "local_up_joe_woodcat", serverID: "up_joe_woodcat", userID: currentUser.id, placeID: coffee.id, status: .been, visibility: .followers, note: "Good morning table by the window.", ratingScore: 4, recommendedScore: 4, recommendedCount: 1, nearbyConfirmed: true, sourceType: "manual", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_griffith", serverID: "up_maya_griffith", userID: maya.id, placeID: hike.id, status: .been, visibility: .followers, note: "Easy sunset win.", ratingScore: 5, recommendedScore: 5, recommendedCount: 1, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_noodles", serverID: "up_ryan_noodles", userID: ryan.id, placeID: noodles.id, status: .wannaGo, visibility: .mutuals, note: "Saved for a rainy night.", sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_joe_circuit_coffee", serverID: "up_joe_circuit_coffee", userID: currentUser.id, placeID: laptopCoffee.id, status: .been, visibility: .followers, note: "Quiet back table, outlets, laptop time.", ratingScore: 5, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "manual", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_circuit_coffee", serverID: "up_maya_circuit_coffee", userID: maya.id, placeID: laptopCoffee.id, status: .been, visibility: .followers, note: "Quiet enough for heads-down work.", ratingScore: 5, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_circuit_coffee", serverID: "up_ryan_circuit_coffee", userID: ryan.id, placeID: laptopCoffee.id, status: .been, visibility: .mutuals, note: "Good outlets, no awkward laptop energy.", ratingScore: 4, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_joe_bar_nido", serverID: "up_joe_bar_nido", userID: currentUser.id, placeID: dinner.id, status: .been, visibility: .followers, note: "Date-night pasta, warm room, not too loud.", ratingScore: 4, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "manual", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_bar_nido", serverID: "up_maya_bar_nido", userID: maya.id, placeID: dinner.id, status: .been, visibility: .followers, note: "Good service and easy to talk.", ratingScore: 4, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_bar_nido", serverID: "up_ryan_bar_nido", userID: ryan.id, placeID: dinner.id, status: .been, visibility: .mutuals, note: "Cozy, good for a longer dinner.", ratingScore: 5, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_joe_elysian_picnic", serverID: "up_joe_elysian_picnic", userID: currentUser.id, placeID: picnic.id, status: .wannaGo, visibility: .followers, note: "Saved for a low-effort sunset picnic.", sourceType: "manual", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_elysian_picnic", serverID: "up_maya_elysian_picnic", userID: maya.id, placeID: picnic.id, status: .been, visibility: .followers, note: "Easy sunset view without a real hike.", ratingScore: 5, recommendedScore: 4.5, recommendedCount: 2, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_elysian_picnic", serverID: "up_ryan_elysian_picnic", userID: ryan.id, placeID: picnic.id, status: .been, visibility: .mutuals, note: "Low effort, great views.", ratingScore: 4, recommendedScore: 4.5, recommendedCount: 2, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_demo_fern_desk", serverID: "up_demo_fern_desk", userID: demo.id, placeID: demoCoffee.id, status: .been, visibility: .followers, note: "Quiet side room, lots of outlets, easy laptop morning.", ratingScore: 5, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_fern_desk", serverID: "up_maya_fern_desk", userID: maya.id, placeID: demoCoffee.id, status: .been, visibility: .followers, note: "Good Wi-Fi and not too crowded before noon.", ratingScore: 4, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_fern_desk", serverID: "up_ryan_fern_desk", userID: ryan.id, placeID: demoCoffee.id, status: .been, visibility: .mutuals, note: "Long-table setup is actually workable.", ratingScore: 5, recommendedScore: 4.7, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_demo_juniper_table", serverID: "up_demo_juniper_table", userID: demo.id, placeID: demoDinner.id, status: .been, visibility: .followers, note: "Cozy date-night room with good service.", ratingScore: 4, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_maya_juniper_table", serverID: "up_maya_juniper_table", userID: maya.id, placeID: demoDinner.id, status: .been, visibility: .followers, note: "Not too loud, easy conversation.", ratingScore: 5, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced),
            LocalUserPlace(localID: "local_up_ryan_juniper_table", serverID: "up_ryan_juniper_table", userID: ryan.id, placeID: demoDinner.id, status: .been, visibility: .mutuals, note: "Bar seats are better than the tables.", ratingScore: 4, recommendedScore: 4.3, recommendedCount: 3, nearbyConfirmed: true, sourceType: "social_seed", syncState: .synced)
        ]

        let placeAttributes = [
            LocalPlaceAttribute(localID: "local_attr_joe_woodcat_work", serverID: "attr_joe_woodcat_work", userPlaceID: "up_joe_woodcat", questionKey: "work_setup", valueType: "single_choice", valueJSON: "\"yes\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_woodcat_tags", serverID: "attr_joe_woodcat_tags", userPlaceID: "up_joe_woodcat", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"wifi solid\",\"quiet\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_griffith_strenuousness", serverID: "attr_maya_griffith_strenuousness", userPlaceID: "up_maya_griffith", questionKey: "strenuousness", valueType: "single_choice", valueJSON: "\"easy\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_griffith_tags", serverID: "attr_maya_griffith_tags", userPlaceID: "up_maya_griffith", questionKey: "hike_tags", valueType: "multi_tag", valueJSON: "[\"sunset\",\"views\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_interest", serverID: "attr_ryan_noodles_interest", userPlaceID: "up_ryan_noodles", questionKey: "interest_signal", valueType: "emoji_scale", valueJSON: "\"excited\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_price", serverID: "attr_ryan_noodles_price", userPlaceID: "up_ryan_noodles", questionKey: "price", valueType: "price_scale", valueJSON: "\"$$\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_occasion", serverID: "attr_ryan_noodles_occasion", userPlaceID: "up_ryan_noodles", questionKey: "occasion", valueType: "single_choice", valueJSON: "\"rainy night\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_noodles_tags", serverID: "attr_ryan_noodles_tags", userPlaceID: "up_ryan_noodles", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"cozy\",\"worth it\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_circuit_work", serverID: "attr_joe_circuit_work", userPlaceID: "up_joe_circuit_coffee", questionKey: "work_setup", valueType: "single_choice", valueJSON: "\"yes\"", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_circuit_tags", serverID: "attr_joe_circuit_tags", userPlaceID: "up_joe_circuit_coffee", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\",\"laptop friendly\",\"wifi solid\",\"outlets\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_circuit_tags", serverID: "attr_maya_circuit_tags", userPlaceID: "up_maya_circuit_coffee", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\",\"laptop friendly\",\"wifi solid\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_circuit_tags", serverID: "attr_ryan_circuit_tags", userPlaceID: "up_ryan_circuit_coffee", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\",\"wifi solid\",\"outlets\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_bar_nido_tags", serverID: "attr_joe_bar_nido_tags", userPlaceID: "up_joe_bar_nido", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"date night\",\"cozy\",\"great service\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_bar_nido_tags", serverID: "attr_maya_bar_nido_tags", userPlaceID: "up_maya_bar_nido", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"date night\",\"great service\",\"easy conversation\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_bar_nido_tags", serverID: "attr_ryan_bar_nido_tags", userPlaceID: "up_ryan_bar_nido", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"cozy\",\"date night\",\"easy conversation\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_joe_elysian_tags", serverID: "attr_joe_elysian_tags", userPlaceID: "up_joe_elysian_picnic", questionKey: "park_tags", valueType: "multi_tag", valueJSON: "[\"sunset\",\"views\",\"low effort\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_elysian_tags", serverID: "attr_maya_elysian_tags", userPlaceID: "up_maya_elysian_picnic", questionKey: "park_tags", valueType: "multi_tag", valueJSON: "[\"sunset\",\"views\",\"low effort\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_elysian_tags", serverID: "attr_ryan_elysian_tags", userPlaceID: "up_ryan_elysian_picnic", questionKey: "park_tags", valueType: "multi_tag", valueJSON: "[\"sunset\",\"views\",\"low effort\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_demo_fern_desk_tags", serverID: "attr_demo_fern_desk_tags", userPlaceID: "up_demo_fern_desk", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\",\"laptop friendly\",\"wifi solid\",\"outlets\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_fern_desk_tags", serverID: "attr_maya_fern_desk_tags", userPlaceID: "up_maya_fern_desk", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\",\"wifi solid\",\"not crowded\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_fern_desk_tags", serverID: "attr_ryan_fern_desk_tags", userPlaceID: "up_ryan_fern_desk", questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"laptop friendly\",\"outlets\",\"long tables\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_demo_juniper_table_tags", serverID: "attr_demo_juniper_table_tags", userPlaceID: "up_demo_juniper_table", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"date night\",\"cozy\",\"great service\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_maya_juniper_table_tags", serverID: "attr_maya_juniper_table_tags", userPlaceID: "up_maya_juniper_table", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"date night\",\"not too loud\",\"easy conversation\"]", syncState: .synced),
            LocalPlaceAttribute(localID: "local_attr_ryan_juniper_table_tags", serverID: "attr_ryan_juniper_table_tags", userPlaceID: "up_ryan_juniper_table", questionKey: "restaurant_tags", valueType: "multi_tag", valueJSON: "[\"cozy\",\"bar seats\",\"great service\"]", syncState: .synced)
        ]

        let follows = [
            LocalFollow(localID: "local_follow_joe_demo", serverID: "follow_joe_demo", followerUserID: currentUser.id, followedUserID: demo.id, source: .profile, syncState: .synced),
            LocalFollow(localID: "local_follow_joe_maya", serverID: "follow_joe_maya", followerUserID: currentUser.id, followedUserID: maya.id, source: .contacts, syncState: .synced),
            LocalFollow(localID: "local_follow_ryan_joe", serverID: "follow_ryan_joe", followerUserID: ryan.id, followedUserID: currentUser.id, source: .profile, syncState: .synced),
            LocalFollow(localID: "local_follow_joe_ryan", serverID: "follow_joe_ryan", followerUserID: currentUser.id, followedUserID: ryan.id, source: .profile, syncState: .synced)
        ]

        let contacts = FakeContactProvider(seededMatches: [
            ContactMatch(id: "contact_maya", displayName: "Maya", handle: "maya", userID: maya.id, isAlreadyFollowing: true, followsCurrentUser: false),
            ContactMatch(id: "contact_sam", displayName: "Sam", handle: nil, userID: nil, isAlreadyFollowing: false, followsCurrentUser: false)
        ])

        let placeLists = [
            LocalPlaceList(localID: "local_list_laptop", serverID: "list_laptop", ownerUserID: currentUser.id, name: "LA laptop mornings", description: "Quiet tables, outlets, and coffee that does not turn into a scene.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_date", serverID: "list_date", ownerUserID: currentUser.id, name: "Date night short list", description: "Warm rooms where conversation is easy.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_sunset", serverID: "list_sunset", ownerUserID: currentUser.id, name: "Low-effort sunsets", description: "Places that feel planned without becoming a project.", visibility: .stealth, syncState: .synced),
            LocalPlaceList(localID: "local_list_maya_sunset", serverID: "list_maya_sunset", ownerUserID: maya.id, name: "Maya's sunset walks", description: "Soft landings around LA.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_ryan_brooklyn_tables", serverID: "list_ryan_brooklyn_tables", ownerUserID: ryan.id, name: "Ryan's Brooklyn tables", description: "Dinner ideas from Ryan that still feel useful from your map.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_demo_laptop", serverID: "list_demo_laptop", ownerUserID: demo.id, name: "Demo's laptop mornings", description: "Follower-visible coffee saves with enough signal to judge the list experience.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_saturday", serverID: "list_saturday", ownerUserID: currentUser.id, name: "Saturday plan", description: "A shared shortlist for where the day can go next.", visibility: .followers, syncState: .synced),
            LocalPlaceList(localID: "local_list_launch", serverID: "list_launch", ownerUserID: ryan.id, name: "Launch week meals", description: "Places near the office where nobody has to decide too hard.", visibility: .stealth, syncState: .synced)
        ]

        let placeListMembers = [
            LocalPlaceListMember(localID: "local_list_member_date_maya", serverID: "list_member_date_maya", listID: "list_date", userID: maya.id, role: .collaborator),
            LocalPlaceListMember(localID: "local_list_member_saturday_maya", serverID: "list_member_saturday_maya", listID: "list_saturday", userID: maya.id, role: .collaborator),
            LocalPlaceListMember(localID: "local_list_member_saturday_ryan", serverID: "list_member_saturday_ryan", listID: "list_saturday", userID: ryan.id, role: .collaborator),
            LocalPlaceListMember(localID: "local_list_member_launch_joe", serverID: "list_member_launch_joe", listID: "list_launch", userID: currentUser.id, role: .collaborator)
        ]

        let placeListItems = [
            LocalPlaceListItem(localID: "local_list_item_laptop_circuit", serverID: "list_item_laptop_circuit", listID: "list_laptop", placeID: laptopCoffee.id, ownerUserPlaceID: "up_joe_circuit_coffee", sourceUserPlaceID: "up_joe_circuit_coffee", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_laptop_fern", serverID: "list_item_laptop_fern", listID: "list_laptop", placeID: demoCoffee.id, sourceUserPlaceID: "up_demo_fern_desk", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_laptop_woodcat", serverID: "list_item_laptop_woodcat", listID: "list_laptop", placeID: coffee.id, ownerUserPlaceID: "up_joe_woodcat", sourceUserPlaceID: "up_joe_woodcat", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_laptop_elysian", serverID: "list_item_laptop_elysian", listID: "list_laptop", placeID: picnic.id, ownerUserPlaceID: "up_joe_elysian_picnic", sourceUserPlaceID: "up_joe_elysian_picnic", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_date_bar_nido", serverID: "list_item_date_bar_nido", listID: "list_date", placeID: dinner.id, ownerUserPlaceID: "up_joe_bar_nido", sourceUserPlaceID: "up_joe_bar_nido", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_date_juniper", serverID: "list_item_date_juniper", listID: "list_date", placeID: demoDinner.id, sourceUserPlaceID: "up_demo_juniper_table", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_date_noodles", serverID: "list_item_date_noodles", listID: "list_date", placeID: noodles.id, sourceUserPlaceID: "up_ryan_noodles", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_sunset_griffith", serverID: "list_item_sunset_griffith", listID: "list_sunset", placeID: hike.id, sourceUserPlaceID: "up_maya_griffith", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_sunset_elysian", serverID: "list_item_sunset_elysian", listID: "list_sunset", placeID: picnic.id, ownerUserPlaceID: "up_joe_elysian_picnic", sourceUserPlaceID: "up_joe_elysian_picnic", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_maya_sunset_griffith", serverID: "list_item_maya_sunset_griffith", listID: "list_maya_sunset", placeID: hike.id, sourceUserPlaceID: "up_maya_griffith", addedByUserID: maya.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_maya_sunset_elysian", serverID: "list_item_maya_sunset_elysian", listID: "list_maya_sunset", placeID: picnic.id, sourceUserPlaceID: "up_maya_elysian_picnic", addedByUserID: maya.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_ryan_brooklyn_noodles", serverID: "list_item_ryan_brooklyn_noodles", listID: "list_ryan_brooklyn_tables", placeID: noodles.id, sourceUserPlaceID: "up_ryan_noodles", addedByUserID: ryan.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_ryan_brooklyn_bar_nido", serverID: "list_item_ryan_brooklyn_bar_nido", listID: "list_ryan_brooklyn_tables", placeID: dinner.id, sourceUserPlaceID: "up_ryan_bar_nido", addedByUserID: ryan.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_ryan_brooklyn_juniper", serverID: "list_item_ryan_brooklyn_juniper", listID: "list_ryan_brooklyn_tables", placeID: demoDinner.id, sourceUserPlaceID: "up_ryan_juniper_table", addedByUserID: ryan.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_demo_laptop_fern", serverID: "list_item_demo_laptop_fern", listID: "list_demo_laptop", placeID: demoCoffee.id, sourceUserPlaceID: "up_demo_fern_desk", addedByUserID: demo.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_demo_laptop_circuit", serverID: "list_item_demo_laptop_circuit", listID: "list_demo_laptop", placeID: laptopCoffee.id, sourceUserPlaceID: "up_maya_circuit_coffee", addedByUserID: demo.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_demo_laptop_woodcat", serverID: "list_item_demo_laptop_woodcat", listID: "list_demo_laptop", placeID: coffee.id, ownerUserPlaceID: "up_joe_woodcat", sourceUserPlaceID: "up_joe_woodcat", addedByUserID: demo.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_saturday_circuit", serverID: "list_item_saturday_circuit", listID: "list_saturday", placeID: laptopCoffee.id, ownerUserPlaceID: "up_joe_circuit_coffee", sourceUserPlaceID: "up_joe_circuit_coffee", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_saturday_elysian", serverID: "list_item_saturday_elysian", listID: "list_saturday", placeID: picnic.id, ownerUserPlaceID: "up_joe_elysian_picnic", sourceUserPlaceID: "up_joe_elysian_picnic", addedByUserID: currentUser.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_launch_fern", serverID: "list_item_launch_fern", listID: "list_launch", placeID: demoCoffee.id, sourceUserPlaceID: "up_demo_fern_desk", addedByUserID: ryan.id, syncState: .synced),
            LocalPlaceListItem(localID: "local_list_item_launch_juniper", serverID: "list_item_launch_juniper", listID: "list_launch", placeID: demoDinner.id, sourceUserPlaceID: "up_demo_juniper_table", addedByUserID: ryan.id, syncState: .synced)
        ]

        return WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser, maya, ryan, demo],
            places: [coffee, hike, noodles, laptopCoffee, dinner, picnic, demoCoffee, demoDinner],
            userPlaces: userPlaces,
            placeAttributes: placeAttributes,
            follows: follows,
            blocks: [],
            placeLists: placeLists,
            placeListMembers: placeListMembers,
            placeListItems: placeListItems,
            contactProvider: contacts
        )
    }

    /// A deterministic power-user dataset for simulator profiling. This is only
    /// selected through `-WanderUsePerformanceFixtures`; production launches
    /// continue to restore the persisted account or use the empty fixture.
    @MainActor
    static func performanceScale() -> WanderFixtures {
        let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)
        let currentUser = LocalProfile(
            localID: "perf_profile_000",
            serverID: "perf_user_000",
            handle: "joe_perf",
            displayName: "Joe Performance",
            bio: "A realistic power-user account for simulator profiling.",
            homeArea: "Los Angeles",
            syncState: .synced,
            createdAt: referenceDate.addingTimeInterval(-1_200 * 86_400),
            updatedAt: referenceDate
        )

        var profiles = [currentUser]
        for index in 1..<64 {
            let suffix = String(format: "%03d", index)
            profiles.append(
                LocalProfile(
                    localID: "perf_profile_\(suffix)",
                    serverID: "perf_user_\(suffix)",
                    handle: "friend_\(suffix)",
                    displayName: "Friend \(suffix)",
                    homeArea: performanceLocations[index % performanceLocations.count].locality,
                    syncState: .synced,
                    createdAt: referenceDate.addingTimeInterval(-Double(200 + index * 11) * 86_400),
                    updatedAt: referenceDate
                )
            )
        }

        let categoryInputs: [(category: String, subcategory: String)] = [
            ("restaurant", "Restaurant"),
            ("coffee", "Coffee Shop"),
            ("bakery", "Bakery"),
            ("bar", "Bar"),
            ("park", "Park"),
            ("museum", "Museum"),
            ("gym", "Gym"),
            ("hike", "Hiking Trail")
        ]
        let cuisines = ["Italian", "Thai", "Japanese", "Mexican", "French", "Korean"]
        var places: [LocalPlace] = []
        places.reserveCapacity(900)
        for index in 0..<900 {
            let suffix = String(format: "%04d", index)
            let location = performanceLocations[index % performanceLocations.count]
            let category = categoryInputs[index % categoryInputs.count]
            let row = Double((index / performanceLocations.count) % 20)
            let column = Double(index % 20)
            places.append(
                LocalPlace(
                    localID: "perf_place_\(suffix)",
                    serverID: "perf_place_server_\(suffix)",
                    canonicalName: "\(category.subcategory) \(suffix)",
                    category: category.category,
                    subcategory: category.subcategory,
                    rawProviderType: category.category,
                    address: "\(100 + index) Fixture Avenue",
                    locality: location.locality,
                    region: location.region,
                    country: location.country,
                    latitude: location.latitude + row * 0.002,
                    longitude: location.longitude + column * 0.002,
                    sourceProvider: "mapkit",
                    sourceProviderPlaceID: "perf_provider_\(suffix)",
                    websiteURLString: "https://example.com/places/\(suffix)",
                    timeZoneIdentifier: location.timeZoneIdentifier,
                    syncState: .synced,
                    createdAt: referenceDate.addingTimeInterval(-Double(index % 700) * 86_400),
                    updatedAt: referenceDate
                )
            )
        }

        var userPlaces: [LocalUserPlace] = []
        var placeAttributes: [LocalPlaceAttribute] = []
        var placeVisits: [LocalPlaceVisit] = []
        var savesByPlaceID: [String: [LocalUserPlace]] = [:]
        userPlaces.reserveCapacity(1_620)
        placeAttributes.reserveCapacity(3_240)
        placeVisits.reserveCapacity(1_300)

        func appendSave(owner: LocalProfile, place: LocalPlace, placeIndex: Int, variant: Int) {
            let placeSuffix = String(format: "%04d", placeIndex)
            let ownerSuffix = String(format: "%03d", profiles.firstIndex(where: { $0 === owner }) ?? 0)
            let suffix = "\(ownerSuffix)_\(placeSuffix)_\(variant)"
            let isBeen = (placeIndex + variant) % 4 != 0
            let status: PlaceStatus = isBeen ? .been : .wannaGo
            let userPlace = LocalUserPlace(
                localID: "perf_user_place_\(suffix)",
                serverID: "perf_user_place_server_\(suffix)",
                userID: owner.id,
                placeID: place.id,
                status: status,
                visibility: owner === currentUser || placeIndex % 5 != 0 ? .followers : .mutuals,
                note: "Realistic saved-place note \(placeSuffix) from \(owner.displayName).",
                ratingScore: isBeen ? Double(3 + ((placeIndex + variant) % 3)) : nil,
                recommendedScore: isBeen ? 3.5 + Double((placeIndex + variant) % 4) * 0.4 : nil,
                recommendedCount: isBeen ? 1 + ((placeIndex + variant) % 5) : 0,
                nearbyConfirmed: isBeen,
                visitedAt: isBeen
                    ? referenceDate.addingTimeInterval(-Double((placeIndex + variant * 17) % 720) * 86_400)
                    : nil,
                savedAt: referenceDate.addingTimeInterval(-Double((placeIndex + variant * 13) % 850) * 86_400),
                sourceType: owner === currentUser ? "manual" : "social_seed",
                syncState: .synced,
                createdAt: referenceDate.addingTimeInterval(-Double((placeIndex + variant * 13) % 850) * 86_400),
                updatedAt: referenceDate
            )
            userPlaces.append(userPlace)
            savesByPlaceID[place.id, default: []].append(userPlace)

            let attributePrefix = "perf_attribute_\(suffix)"
            placeAttributes.append(
                LocalPlaceAttribute(
                    localID: "\(attributePrefix)_tags",
                    serverID: "\(attributePrefix)_tags_server",
                    userPlaceID: userPlace.id,
                    questionKey: "place_tags",
                    valueType: "multi_tag",
                    valueJSON: "[\"trusted\",\"useful\",\"fixture-\((placeIndex + variant) % 12)\"]",
                    syncState: .synced,
                    createdAt: userPlace.createdAt,
                    updatedAt: referenceDate
                )
            )
            let isRestaurant = place.primaryCategory == WanderPlaceCategory.restaurantsFood
            placeAttributes.append(
                LocalPlaceAttribute(
                    localID: "\(attributePrefix)_detail",
                    serverID: "\(attributePrefix)_detail_server",
                    userPlaceID: userPlace.id,
                    questionKey: isRestaurant ? PlaceMemoryAttributeKeys.restaurantCuisine : "occasion",
                    valueType: "single_choice",
                    valueJSON: isRestaurant
                        ? "\"\(cuisines[(placeIndex + variant) % cuisines.count])\""
                        : "\"everyday\"",
                    syncState: .synced,
                    createdAt: userPlace.createdAt,
                    updatedAt: referenceDate
                )
            )

            guard isBeen else { return }
            let visitDate = userPlace.visitedAt ?? referenceDate
            placeVisits.append(
                LocalPlaceVisit(
                    localID: "perf_visit_\(suffix)_0",
                    serverID: "perf_visit_server_\(suffix)_0",
                    userPlaceID: userPlace.id,
                    visitedAt: visitDate,
                    note: "Visit memory for \(place.canonicalName).",
                    ratingScore: userPlace.ratingScore,
                    tags: ["trusted", "memory"],
                    syncState: .synced,
                    createdAt: visitDate,
                    updatedAt: referenceDate
                )
            )
            if (placeIndex + variant) % 12 == 0 {
                placeVisits.append(
                    LocalPlaceVisit(
                        localID: "perf_visit_\(suffix)_1",
                        serverID: "perf_visit_server_\(suffix)_1",
                        userPlaceID: userPlace.id,
                        visitedAt: visitDate.addingTimeInterval(-45 * 86_400),
                        note: "A repeat visit used to exercise visit history.",
                        ratingScore: userPlace.ratingScore,
                        tags: ["repeat"],
                        syncState: .synced,
                        createdAt: visitDate.addingTimeInterval(-45 * 86_400),
                        updatedAt: referenceDate
                    )
                )
            }
        }

        for (index, place) in places.enumerated() {
            appendSave(
                owner: profiles[1 + (index % (profiles.count - 1))],
                place: place,
                placeIndex: index,
                variant: 0
            )
            if index < 420 {
                appendSave(owner: currentUser, place: place, placeIndex: index, variant: 1)
            }
            if index % 3 == 0 {
                appendSave(
                    owner: profiles[1 + ((index + 19) % (profiles.count - 1))],
                    place: place,
                    placeIndex: index,
                    variant: 2
                )
            }
        }

        var follows: [LocalFollow] = []
        for index in 1..<profiles.count {
            let suffix = String(format: "%03d", index)
            let profile = profiles[index]
            follows.append(
                LocalFollow(
                    localID: "perf_follow_out_\(suffix)",
                    serverID: "perf_follow_out_server_\(suffix)",
                    followerUserID: currentUser.id,
                    followedUserID: profile.id,
                    source: .profile,
                    syncState: .synced
                )
            )
            if index % 3 == 0 {
                follows.append(
                    LocalFollow(
                        localID: "perf_follow_in_\(suffix)",
                        serverID: "perf_follow_in_server_\(suffix)",
                        followerUserID: profile.id,
                        followedUserID: currentUser.id,
                        source: .profile,
                        syncState: .synced
                    )
                )
            }
        }

        var placeLists: [LocalPlaceList] = []
        var placeListMembers: [LocalPlaceListMember] = []
        var placeListItems: [LocalPlaceListItem] = []
        placeLists.reserveCapacity(72)
        placeListItems.reserveCapacity(2_016)
        for listIndex in 0..<72 {
            let listSuffix = String(format: "%03d", listIndex)
            let owner = listIndex < 24
                ? currentUser
                : profiles[1 + ((listIndex - 24) % (profiles.count - 1))]
            let list = LocalPlaceList(
                localID: "perf_list_\(listSuffix)",
                serverID: "perf_list_server_\(listSuffix)",
                ownerUserID: owner.id,
                name: "Realistic list \(listSuffix)",
                description: "A high-data fixture list with enough places to exercise scrolling and projection work.",
                visibility: listIndex % 7 == 0 ? .stealth : .followers,
                syncState: .synced,
                cachedItemCount: 28,
                createdAt: referenceDate.addingTimeInterval(-Double(listIndex * 5) * 86_400),
                updatedAt: referenceDate
            )
            placeLists.append(list)

            if listIndex % 5 == 0 {
                for memberOffset in 1...2 {
                    let member = profiles[1 + ((listIndex + memberOffset) % (profiles.count - 1))]
                    placeListMembers.append(
                        LocalPlaceListMember(
                            localID: "perf_list_member_\(listSuffix)_\(memberOffset)",
                            serverID: "perf_list_member_server_\(listSuffix)_\(memberOffset)",
                            listID: list.id,
                            userID: member.id,
                            role: .collaborator,
                            createdAt: list.createdAt
                        )
                    )
                }
            }

            for itemIndex in 0..<28 {
                let placeIndex = (listIndex * 13 + itemIndex * 17) % places.count
                let place = places[placeIndex]
                guard let sourceSave = savesByPlaceID[place.id]?.first else { continue }
                let itemSuffix = String(format: "%02d", itemIndex)
                placeListItems.append(
                    LocalPlaceListItem(
                        localID: "perf_list_item_\(listSuffix)_\(itemSuffix)",
                        serverID: "perf_list_item_server_\(listSuffix)_\(itemSuffix)",
                        listID: list.id,
                        placeID: place.id,
                        ownerUserPlaceID: sourceSave.userID == currentUser.id ? sourceSave.id : nil,
                        sourceUserPlaceID: sourceSave.id,
                        addedByUserID: owner.id,
                        syncState: .synced,
                        createdAt: list.createdAt.addingTimeInterval(Double(itemIndex) * 3_600),
                        updatedAt: referenceDate
                    )
                )
            }
        }

        let contacts = FakeContactProvider(
            seededMatches: profiles.dropFirst().prefix(12).map { profile in
                ContactMatch(
                    id: "perf_contact_\(profile.id)",
                    displayName: profile.displayName,
                    handle: profile.handle,
                    userID: profile.id,
                    isAlreadyFollowing: true,
                    followsCurrentUser: follows.contains {
                        $0.followerUserID == profile.id && $0.followedUserID == currentUser.id
                    }
                )
            }
        )

        return WanderFixtures(
            currentUser: currentUser,
            profiles: profiles,
            places: places,
            userPlaces: userPlaces,
            placeAttributes: placeAttributes,
            placeVisits: placeVisits,
            follows: follows,
            blocks: [],
            placeLists: placeLists,
            placeListMembers: placeListMembers,
            placeListItems: placeListItems,
            contactProvider: contacts
        )
    }

    private static let performanceLocations: [PerformanceFixtureLocation] = [
        PerformanceFixtureLocation(locality: "Los Angeles", region: "CA", country: "United States", latitude: 34.0522, longitude: -118.2437, timeZoneIdentifier: "America/Los_Angeles"),
        PerformanceFixtureLocation(locality: "New York", region: "NY", country: "United States", latitude: 40.7128, longitude: -74.0060, timeZoneIdentifier: "America/New_York"),
        PerformanceFixtureLocation(locality: "San Francisco", region: "CA", country: "United States", latitude: 37.7749, longitude: -122.4194, timeZoneIdentifier: "America/Los_Angeles"),
        PerformanceFixtureLocation(locality: "Chicago", region: "IL", country: "United States", latitude: 41.8781, longitude: -87.6298, timeZoneIdentifier: "America/Chicago"),
        PerformanceFixtureLocation(locality: "London", region: "England", country: "United Kingdom", latitude: 51.5072, longitude: -0.1276, timeZoneIdentifier: "Europe/London"),
        PerformanceFixtureLocation(locality: "Tokyo", region: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo")
    ]
}

private struct PerformanceFixtureLocation {
    let locality: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
}

enum WanderModelContainer {
    static var preview: ModelContainer {
        let schema = Schema([
            LocalProfile.self,
            LocalFollow.self,
            LocalBlock.self,
            LocalMute.self,
            LocalPlace.self,
            LocalUserPlace.self,
            LocalPlaceAttribute.self,
            LocalPlaceVisit.self,
            LocalVisitPhoto.self,
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
