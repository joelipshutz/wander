import MapKit
import XCTest
@testable import Wander

final class WanderPlaceCategoryTests: XCTestCase {
    func testMapKitParksStayParks() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .park), "park")
        XCTAssertEqual(WanderPlaceCategory.primary(for: .nationalPark), "park")
    }

    func testCategorySymbolsIncludePark() {
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "park"), "tree.fill")
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "hike"), "figure.hiking")
    }

    func testMapKitHealthAndFitnessCategories() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .hospital), "hospital")
        XCTAssertEqual(WanderPlaceCategory.primary(for: .fitnessCenter), "gym")

        if #available(iOS 18.0, *) {
            XCTAssertEqual(WanderPlaceCategory.primary(for: .animalService), "veterinarian")
            XCTAssertEqual(WanderPlaceCategory.primary(for: .hiking), "hike")
        }
    }

    func testPlaceNameOverridesTuneBroadMapKitCategories() {
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Providence St. John's Health Center"),
            "hospital"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Green Dog Dental"),
            "veterinarian"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Iron Fitness"),
            "gym"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Plankhaus"),
            "pilates studio"
        )
    }

    func testCandidatePreviewSubtitleDoesNotRepeatLocality() {
        let candidate = PlaceCandidate(
            id: "jade-rabbit",
            name: "Jade Rabbit",
            category: "restaurant",
            address: "231 Santa Monica Boulevard Santa Monica",
            locality: "Santa Monica",
            latitude: 34.0,
            longitude: -118.0,
            confidence: 0.9
        )

        XCTAssertEqual(
            candidate.previewSubtitle(includeDistance: false),
            "231 Santa Monica Boulevard · Santa Monica · restaurant"
        )

        let commaCandidate = PlaceCandidate(
            id: "jade-rabbit-comma",
            name: "Jade Rabbit",
            category: "restaurant",
            address: "231 Santa Monica Boulevard, Santa Monica, CA",
            locality: "Santa Monica",
            latitude: 34.0,
            longitude: -118.0,
            confidence: 0.9
        )

        XCTAssertEqual(
            commaCandidate.previewSubtitle(includeDistance: false),
            "231 Santa Monica Boulevard · Santa Monica · restaurant"
        )
    }
}
