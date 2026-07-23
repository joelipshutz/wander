#if DEBUG
import XCTest
@testable import Wander

final class PlacePhotoCarouselMockupTests: XCTestCase {
    func testLaunchArgumentRoutesToRequestedMockupPage() {
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander", "-WanderPlacePhotoCarouselMockup", "viewer"],
                environment: [:]
            ),
            .viewer
        )
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander", "-WanderPlacePhotoCarouselMockup", "hundredPhotos"],
                environment: [:]
            ),
            .hundredPhotos
        )
        XCTAssertNil(PlacePhotoCarouselMockupPage.resolved(from: ["Wander"], environment: [:]))
    }

    func testLaunchArgumentDefaultsToCardForMissingOrUnknownPage() {
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander", "-WanderPlacePhotoCarouselMockup"],
                environment: [:]
            ),
            .card
        )
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander", "-WanderPlacePhotoCarouselMockup", "unknown"],
                environment: [:]
            ),
            .card
        )
    }

    func testEnvironmentRoutesToRequestedMockupPage() {
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander"],
                environment: ["WANDER_PLACE_PHOTO_CAROUSEL_MOCKUP": "card"]
            ),
            .card
        )
        XCTAssertEqual(
            PlacePhotoCarouselMockupPage.resolved(
                from: ["Wander", "-WanderPlacePhotoCarouselMockup", "card"],
                environment: ["WANDER_PLACE_PHOTO_CAROUSEL_MOCKUP": "viewer"]
            ),
            .viewer
        )
    }

    func testPrivacyFilterPlacesGoogleFirstAndExcludesIneligibleUserPhotos() {
        let visible = PlacePhotoCarouselMockPrivacyFilter.visiblePhotos(
            from: PlacePhotoCarouselMockData.candidates
        )

        XCTAssertEqual(
            visible.map(\.id),
            ["google-photo", "maya-photo", "sofia-photo", "andrew-photo"]
        )
        guard case .google = visible.first?.source else {
            return XCTFail("The Google Maps place photo must lead every gallery")
        }
        XCTAssertFalse(visible.contains { $0.id == "stealth-photo" })
        XCTAssertFalse(visible.contains { $0.id == "private-profile-photo" })
        XCTAssertFalse(visible.contains { $0.id == "blocked-photo" })
    }

    func testPrivacyFilterStillReturnsEligibleUserPhotosWithoutGoogle() {
        let candidates = PlacePhotoCarouselMockData.candidates.filter { candidate in
            if case .google = candidate.source {
                return false
            }
            return true
        }

        XCTAssertEqual(
            PlacePhotoCarouselMockPrivacyFilter.visiblePhotos(from: candidates).map(\.id),
            ["maya-photo", "sofia-photo", "andrew-photo"]
        )
    }

    func testHundredPhotoFixtureKeepsOneGooglePhotoAtFront() {
        let photos = PlacePhotoCarouselMockData.hundredVisiblePhotos

        XCTAssertEqual(photos.count, 100)
        guard case .google = photos[0].source else {
            return XCTFail("The Google Maps place photo must remain first")
        }
        XCTAssertEqual(
            photos.dropFirst().filter {
                if case .google = $0.source {
                    return true
                }
                return false
            }.count,
            0
        )
        XCTAssertEqual(Set(photos.map(\.id)).count, photos.count)
    }
}
#endif
