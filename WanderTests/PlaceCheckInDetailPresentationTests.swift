import XCTest
@testable import Wander

@MainActor
final class PlaceCheckInDetailPresentationTests: XCTestCase {
    func testDietaryArrayDisplaysAndIndexesOnlyExplicitSelections() {
        let value = LocalPlaceAttribute(localID: "diet", userPlaceID: "save", questionKey: "place_detail_dietary_options", valueType: "multi_tag", valueJSON: #"["Vegan","Gluten free"]"#)
        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: value), ["Dietary options: Vegan", "Dietary options: Gluten free"])
        XCTAssertEqual(PlaceProfileAttributePresentation.searchTerms(from: value), ["vegan options", "gluten free options"])
        XCTAssertTrue(PlaceProfileTagParser.tags(from: value).isEmpty)
        value.valueJSON = #""Vegan""#
        XCTAssertTrue(PlaceProfileAttributePresentation.searchTerms(from: value).isEmpty)
    }

    func testAnswersKeepTheirQuestionOnReadSurfaces() {
        let outlets = attribute(key: "place_detail_outlets", answer: "None found")
        let binary = attribute(key: "place_detail_everyday_quiet_work", answer: "No")

        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: outlets), ["Outlets: None found"])
        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: binary), ["Quiet work: No"])
    }

    func testUnknownDetailRemainsReadableWithoutBecomingAStandaloneTag() {
        let unknown = attribute(key: "place_detail_future_facility", answer: "Yes")

        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: unknown), ["Saved detail: Yes"])
        XCTAssertTrue(PlaceProfileAttributePresentation.searchTerms(from: unknown).isEmpty)
        XCTAssertTrue(PlaceProfileTagParser.tags(from: unknown).isEmpty)
    }

    func testCheckInAnswersDoNotBecomeCommonTagsOrTasteDescriptors() {
        let first = visiblePlace(id: "first", key: "place_detail_outlets", answer: "Plenty")
        let second = visiblePlace(id: "second", key: "place_detail_outlets", answer: "Plenty")
        let summaries = [first, second].map {
            PlaceSaveSummary(visiblePlace: $0, attributes: $0.attributes, viewerFollowsOwner: true)
        }

        XCTAssertTrue(PlaceProfileTagParser.tags(from: first.attributes[0]).isEmpty)
        XCTAssertTrue(PlaceProfilePresenter.commonTags(from: summaries, currentUserID: "viewer").isEmpty)

        let legacy = attribute(key: "coffee_tags", answer: "Quiet", valueType: "multi_tag")
        XCTAssertEqual(PlaceProfileTagParser.tags(from: legacy).map(\.displayTitle), ["Quiet"])
    }

    func testOutletSearchUsesExplicitMeaningAndShowsContextualEvidence() throws {
        let positive = visiblePlace(id: "positive", key: "place_detail_outlets", answer: "A few")
        let negative = visiblePlace(id: "negative", key: "place_detail_outlets", answer: "None found")
        let results = TrustedPlaceSearch.matches(query: "outlets", in: [negative, positive])

        XCTAssertEqual(results.map(\.place.id), [positive.id])
        let evidence = try XCTUnwrap(results.first?.evidence.first { $0.field == .attribute })
        XCTAssertEqual(evidence.displayValue, "Outlets: A few")
        XCTAssertTrue(TrustedPlaceSearch.matches(query: "none", in: [negative]).isEmpty)
        XCTAssertTrue(TrustedPlaceSearch.matches(query: "few", in: [positive]).isEmpty)
    }

    func testOutsideDogAnswerCannotSupplyIndoorOrUnqualifiedFriendlyMatch() {
        let outside = visiblePlace(id: "outside", key: "place_detail_dog_access", answer: "Outside only")
        let inside = visiblePlace(id: "inside", key: "place_detail_dog_access", answer: "Inside and outside")
        let prohibited = visiblePlace(id: "prohibited", key: "place_detail_dog_access", answer: "Not allowed")
        let places = [outside, inside, prohibited]

        XCTAssertEqual(Set(TrustedPlaceSearch.matches(query: "dogs outside", in: places).map(\.place.id)), Set([outside.id, inside.id]))
        XCTAssertEqual(TrustedPlaceSearch.matches(query: "dogs indoors", in: places).map(\.place.id), [inside.id])
        XCTAssertEqual(TrustedPlaceSearch.matches(query: "dog friendly", in: places).map(\.place.id), [inside.id])
    }

    func testWannaAndMalformedValuesCannotSupplyCheckInEvidence() {
        let wanna = visiblePlace(id: "wanna", key: "place_detail_outlets", answer: "Plenty", status: .wannaGo)
        let array = visiblePlace(id: "array", key: "place_detail_outlets", answer: "Plenty")
        array.attributes[0].valueJSON = #"["Plenty"]"#
        let wrongType = visiblePlace(id: "wrong-type", key: "place_detail_outlets", answer: "Plenty")
        wrongType.attributes[0].valueType = "multi_tag"
        let unknownOption = visiblePlace(id: "unknown-option", key: "place_detail_outlets", answer: "outlets everywhere")

        XCTAssertTrue(TrustedPlaceSearch.matches(query: "outlets", in: [wanna, array, wrongType, unknownOption]).isEmpty)
    }

    func testBinaryAnswersAreIndexedByMeaningWithoutIndexingYesOrNo() {
        let positive = visiblePlace(id: "quiet", key: "place_detail_everyday_quiet_work", answer: "Yes")
        let negative = visiblePlace(id: "no-quiet", key: "place_detail_everyday_quiet_work", answer: "No")

        XCTAssertEqual(TrustedPlaceSearch.matches(query: "quiet workspace", in: [negative, positive]).map(\.place.id), [positive.id])
        XCTAssertTrue(TrustedPlaceSearch.matches(query: "yes", in: [positive]).isEmpty)
        XCTAssertTrue(TrustedPlaceSearch.matches(query: "no", in: [negative]).isEmpty)
    }

    private func attribute(
        key: String,
        answer: String,
        valueType: String = "single_choice",
        userPlaceID: String = "save"
    ) -> LocalPlaceAttribute {
        let data = try! JSONEncoder().encode(answer)
        return LocalPlaceAttribute(
            localID: UUID().uuidString,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: String(decoding: data, as: UTF8.self)
        )
    }

    private func visiblePlace(
        id: String,
        key: String,
        answer: String,
        status: PlaceStatus = .been
    ) -> VisiblePlace {
        let owner = LocalProfile(localID: "owner-\(id)", handle: "traveler", displayName: "Traveler")
        let place = LocalPlace(
            localID: "place-\(id)",
            canonicalName: "A place",
            category: "coffee_tea_sweets",
            latitude: 0,
            longitude: 0
        )
        let saved = LocalUserPlace(
            localID: id,
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            savedAt: Date(timeIntervalSince1970: 100),
            sourceType: "manual"
        )
        return VisiblePlace(
            id: id,
            place: place,
            userPlace: saved,
            owner: owner,
            attributes: [attribute(key: key, answer: answer, userPlaceID: saved.id)]
        )
    }
}
