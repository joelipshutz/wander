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

    func testPrivacyFilterKeepsEligibleUserPhotosAndExcludesPrivatePhotos() {
        let visible = PlacePhotoCarouselMockPrivacyFilter.visiblePhotos(
            from: PlacePhotoCarouselMockData.candidates
        )

        XCTAssertEqual(
            visible.map(\.id),
            ["maya-photo", "current-user-photo", "sofia-photo", "andrew-photo"]
        )
        XCTAssertFalse(visible.contains { $0.id == "stealth-photo" })
        XCTAssertFalse(visible.contains { $0.id == "private-profile-photo" })
        XCTAssertFalse(visible.contains { $0.id == "blocked-photo" })
    }

    func testPrivacyFilterReturnsOnlyUserPhotos() {
        XCTAssertEqual(
            PlacePhotoCarouselMockPrivacyFilter.visiblePhotos(
                from: PlacePhotoCarouselMockData.candidates
            ).map(\.source).count,
            4
        )
    }

    func testHundredPhotoFixtureContainsOnlyUniqueUserPhotos() {
        let photos = PlacePhotoCarouselMockData.hundredVisiblePhotos

        XCTAssertEqual(photos.count, 100)
        XCTAssertFalse(photos.contains { $0.id.localizedCaseInsensitiveContains("google") })
        XCTAssertEqual(Set(photos.map(\.id)).count, photos.count)
    }

    func testViewerFixtureExercisesLongCurrentUserAttribution() {
        let photos = PlacePhotoCarouselMockData.viewerPhotos

        XCTAssertEqual(photos[0].id, "maya-photo")
        guard case let .user(profile) = photos[0].source else {
            return XCTFail("The viewer should start on a representative user photo")
        }
        XCTAssertEqual(profile.name, "You")
        XCTAssertEqual(profile.handle, "ryan_lieblein")
    }
}
#endif
