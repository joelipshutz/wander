import CoreLocation
import XCTest
@testable import Wander

final class PlaceCardPresentationTests: XCTestCase {
    func testRecmeRatingTakesPriorityWhenProviderRatingIsAvailable() throws {
        let recme = PlaceActualRating(score: 5, count: 2, source: .friends)
        let rating = try XCTUnwrap(
            PlaceCardPresentation.rating(
                providerScore: 4.7,
                providerCount: 138,
                recmeRating: recme,
                providerName: "google_places"
            )
        )

        XCTAssertEqual(rating.scoreText, "5.0")
        XCTAssertEqual(rating.count, 2)
        XCTAssertEqual(rating.source, .recme)
        XCTAssertNil(rating.providerDisplayName)
    }

    func testZeroCountRecmeRatingFallsBackToYelpWithExplicitAttribution() throws {
        let emptyRecme = PlaceActualRating(score: 4.25, count: 0, source: .community)
        let rating = try XCTUnwrap(
            PlaceCardPresentation.rating(
                providerScore: 4.7,
                providerCount: 138,
                recmeRating: emptyRecme,
                providerName: "yelp"
            )
        )

        XCTAssertEqual(rating.score, 4.7)
        XCTAssertEqual(rating.count, 138)
        XCTAssertEqual(rating.source, .provider(displayName: "Yelp"))
        XCTAssertEqual(rating.providerDisplayName, "Yelp")
    }

    func testMissingRecmeRatingDoesNotExposeGoogleProviderRating() {
        XCTAssertNil(
            PlaceCardPresentation.rating(
                providerScore: 4.6,
                providerCount: 51,
                recmeRating: nil,
                providerName: "google_places"
            )
        )
    }

    func testMissingRecmeAndProviderRatingsOmitRating() {
        XCTAssertNil(
            PlaceCardPresentation.rating(
                providerScore: nil,
                providerCount: nil,
                recmeRating: nil,
                providerName: "yelp"
            )
        )
    }

    func testInvalidRecmeEvidenceNeverSilentlyFallsBackToProvider() {
        XCTAssertNil(
            PlaceCardPresentation.rating(
                providerScore: 4.7,
                providerCount: 138,
                recmeRating: PlaceActualRating(score: 5, count: -1, source: .community),
                providerName: "yelp"
            )
        )
    }

    func testDistanceOnlyRendersWhenViewerLocationIsAvailable() throws {
        XCTAssertNil(
            PlaceCardPresentation.distanceText(
                viewerLocation: nil,
                latitude: 34.0777,
                longitude: -118.2588
            )
        )

        let origin = CLLocation(latitude: 0, longitude: 0)
        let distance = try XCTUnwrap(
            PlaceCardPresentation.distanceText(
                viewerLocation: origin,
                latitude: 0.01447,
                longitude: 0
            )
        )
        XCTAssertEqual(distance, "1.0 mi")
    }

    func testClosedHoursShowTheNextOpeningInThePlaceTimezone() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-17T17:00:00Z"))
        let hours = try XCTUnwrap(
            PlaceCardPresentation.hours(
                isOpen: false,
                nextOpenTimeString: "2026-08-18T15:00:00Z",
                nextCloseTimeString: nil,
                utcOffsetMinutes: -420,
                now: now
            )
        )

        XCTAssertFalse(hours.isOpen)
        XCTAssertEqual(hours.statusText, "Closed")
        XCTAssertEqual(hours.detailText, "Opens Tue at 8 AM")
    }

    func testOpenHoursShowTodaysClosingTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-17T17:00:00Z"))
        let hours = try XCTUnwrap(
            PlaceCardPresentation.hours(
                isOpen: true,
                nextOpenTimeString: nil,
                nextCloseTimeString: "2026-08-17T18:00:00Z",
                utcOffsetMinutes: -420,
                now: now
            )
        )

        XCTAssertTrue(hours.isOpen)
        XCTAssertEqual(hours.statusText, "Open")
        XCTAssertEqual(hours.detailText, "Closes at 11 AM")
    }

    func testMissingHoursOmitsTheBadge() {
        XCTAssertNil(
            PlaceCardPresentation.hours(
                isOpen: nil,
                nextOpenTimeString: nil,
                nextCloseTimeString: nil,
                utcOffsetMinutes: nil
            )
        )
    }

    func testPlacePhotoDecodesGoogleCardMetadata() throws {
        let data = try XCTUnwrap(
            """
            {
              "provider": "google_places",
              "provider_place_id": "google-woodcat",
              "provider_primary_type": "coffee_shop",
              "provider_types": ["coffee_shop", "cafe"],
              "provider_rating": 4.7,
              "provider_user_rating_count": 138,
              "provider_open_now": false,
              "provider_next_open_time": "2026-08-18T15:00:00Z",
              "provider_next_close_time": null,
              "provider_utc_offset_minutes": -420,
              "photo_url": "https://example.com/photo.jpg"
            }
            """.data(using: .utf8)
        )
        let photo = try JSONDecoder().decode(PlacePhoto.self, from: data)

        XCTAssertEqual(photo.providerRating, 4.7)
        XCTAssertEqual(photo.providerUserRatingCount, 138)
        XCTAssertEqual(photo.providerOpenNow, false)
        XCTAssertEqual(photo.providerNextOpenTimeString, "2026-08-18T15:00:00Z")
        XCTAssertEqual(photo.providerUTCOffsetMinutes, -420)
    }
}
