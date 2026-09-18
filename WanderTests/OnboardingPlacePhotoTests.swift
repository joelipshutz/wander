import UIKit
import XCTest
@testable import Wander

@MainActor
final class OnboardingPlacePhotoTests: XCTestCase {
    func testOpeningUsesRealHotchkissPhotoAndRetainsProviderAttribution() async throws {
        let repository = OnboardingPlacePhotoRepository()
        let request = PlaceSheetPlace(candidate: FirstVisitParkSuggestionPolicy.hotchkissPark).photoRequest
        let photo = try await repository.photo(for: request)
        XCTAssertEqual(photo.providerPlaceID, "ChIJhfviD9W6woAR5UzoGcChwpY")
        XCTAssertEqual(photo.providerPrimaryType, "park")
        XCTAssertFalse(try XCTUnwrap(photo.authorName).isEmpty)
        XCTAssertEqual(photo.sourcePhotoURL?.host, "www.google.com")
        XCTAssertNil(photo.providerOpenNow, "The opening must not claim that cached hours are live.")
        let data = try await repository.imageData(for: photo)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertGreaterThan(image.size.width, 500)
        XCTAssertGreaterThan(image.size.height, 500)
    }

    func testOpeningPhotoCannotBeUsedAsAStandInForOtherPlaces() async {
        let repository = OnboardingPlacePhotoRepository()
        do {
            _ = try await repository.photo(for: PlacePhotoRequest(name: "Another park", address: nil,
                latitude: nil, longitude: nil, sourceProvider: nil, sourceProviderPlaceID: nil))
            XCTFail("The cached park photo must never replace another place's photo.")
        } catch { XCTAssertEqual(error as? WanderRemoteError, .notConfigured) }
    }
}
