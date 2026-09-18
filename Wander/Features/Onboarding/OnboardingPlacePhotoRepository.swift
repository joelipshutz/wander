import Foundation

/// The signed-out introduction reuses the production preview and image pipeline
/// with a cached, real place-photo response. This exact Hotchkiss Park photo was
/// retrieved through Astir's authenticated endpoint on September 17, 2026.
/// Bundling that response makes the opening work before an account exists;
/// it does not alter the authenticated photo service or substitute stock art.
@MainActor
struct OnboardingPlacePhotoRepository: PlacePhotoRepository {
    private let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        let park = FirstVisitParkSuggestionPolicy.hotchkissPark
        guard request.sourceProvider == park.sourceProvider,
              request.sourceProviderPlaceID == park.sourceProviderPlaceID,
              let url = bundle.url(forResource: "OnboardingHotchkissPark", withExtension: "json")
        else { throw WanderRemoteError.notConfigured }
        return try JSONDecoder().decode(PlacePhoto.self, from: Data(contentsOf: url))
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.notConfigured
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        guard photo.provider == "google_places",
              photo.providerPlaceID == "ChIJhfviD9W6woAR5UzoGcChwpY",
              let url = bundle.url(forResource: "OnboardingHotchkissPark", withExtension: "jpg")
        else { throw WanderRemoteError.notConfigured }
        return try Data(contentsOf: url)
    }
}
