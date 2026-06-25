import XCTest
@testable import Wander

final class PlaceProfilePresentationTests: XCTestCase {
    func testCommonTagsRequireUserAndTrustedOrTwoTrustedSupports() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_coffee", category: "coffee")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 4, tags: ["quiet", "laptop time"]),
            summary(owner: maya, place: place, ratingScore: 5, tags: ["quiet", "patio"]),
            summary(owner: ryan, place: place, ratingScore: 4, tags: ["patio"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["quiet", "patio"])
        XCTAssertEqual(tags.first?.hasOwnSupport, true)
        XCTAssertFalse(tags.contains { $0.title == "laptop time" })
    }

    func testCommonTagsIgnoreInterestSignals() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_noodles", category: "restaurant")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"]),
            summary(owner: maya, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["cozy"])
        XCTAssertFalse(tags.contains { $0.title == "must go" })
    }

    func testActualRatingPrefersCurrentUsersRating() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_bar", category: "bar")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 3, tags: []),
            summary(owner: maya, place: place, ratingScore: 5, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.actualRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .own)
        XCTAssertEqual(rating.score, 3)
        XCTAssertEqual(rating.count, 1)
    }

    func testActualRatingAveragesTrustedRatingsWhenUnsaved() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_hike", category: "hike")
        let summaries = [
            summary(owner: maya, place: place, ratingScore: 4, tags: []),
            summary(owner: ryan, place: place, ratingScore: 5, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.actualRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .trusted)
        XCTAssertEqual(rating.score, 4.5)
        XCTAssertEqual(rating.count, 2)
    }

    func testFitRatingIsNilWhenEvidenceIsThin() {
        let currentUser = profile(id: "user_joe", handle: "joe")

        let presentation = PlaceProfilePresenter.presentation(
            placeID: "place_unknown",
            category: "coffee",
            saves: [],
            tasteSaves: [],
            currentUserID: currentUser.id
        )

        XCTAssertNil(presentation.fitRating)
        XCTAssertNil(presentation.actualRating)
        XCTAssertTrue(presentation.commonTags.isEmpty)
    }

    func testFitRatingUsesTrustedRatingsCategoryAndTagHistory() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let selectedPlace = place(id: "place_selected", category: "coffee")
        let likedPlace = place(id: "place_liked", category: "coffee")

        let selectedSaves = [
            summary(owner: maya, place: selectedPlace, ratingScore: 5, tags: ["quiet", "wifi solid"]),
            summary(owner: ryan, place: selectedPlace, ratingScore: 4, tags: ["quiet"])
        ]
        let tasteSaves = [
            summary(owner: currentUser, place: likedPlace, ratingScore: 5, tags: ["quiet", "outlets"])
        ]

        let presentation = PlaceProfilePresenter.presentation(
            placeID: selectedPlace.id,
            category: selectedPlace.category,
            saves: selectedSaves,
            tasteSaves: tasteSaves,
            currentUserID: currentUser.id
        )

        let fit = try XCTUnwrap(presentation.fitRating)
        XCTAssertGreaterThanOrEqual(fit.score, 8)
        XCTAssertEqual(presentation.commonTags.map(\.title), ["quiet"])
        XCTAssertTrue(fit.reasons.contains { $0.contains("coffee") })
        XCTAssertTrue(fit.reasons.contains { $0.contains("quiet") })
    }

    private func profile(id: String, handle: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: handle,
            displayName: handle.capitalized,
            syncState: .synced
        )
    }

    private func place(id: String, category: String) -> LocalPlace {
        LocalPlace(
            localID: "local_\(id)",
            serverID: id,
            canonicalName: id.replacingOccurrences(of: "_", with: " ").capitalized,
            category: category,
            locality: "Los Angeles",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "mapkit",
            syncState: .synced
        )
    }

    private func summary(
        owner: LocalProfile,
        place: LocalPlace,
        ratingScore: Int?,
        interestSignal: String? = nil,
        tags: [String]
    ) -> PlaceSaveSummary {
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(place.id)",
            serverID: "up_\(owner.id)_\(place.id)",
            userID: owner.id,
            placeID: place.id,
            status: ratingScore == nil ? .wannaGo : .been,
            visibility: .followers,
            note: nil,
            ratingScore: ratingScore,
            recommendedScore: ratingScore.map(Double.init),
            recommendedCount: ratingScore == nil ? 0 : 1,
            sourceType: "test",
            syncState: .synced
        )
        let visiblePlace = VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
        var attributes: [LocalPlaceAttribute] = []

        if let interestSignal {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "interest_signal", valueType: "emoji_scale", value: interestSignal))
        }

        if !tags.isEmpty {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "\(place.category)_tags", valueType: "multi_tag", values: tags))
        }

        return PlaceSaveSummary(visiblePlace: visiblePlace, attributes: attributes)
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, value: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(value),
            syncState: .synced
        )
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, values: [String]) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(values),
            syncState: .synced
        )
    }

    private func json<T: Encodable>(_ value: T) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}
