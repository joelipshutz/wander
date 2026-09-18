#if DEBUG
import SwiftUI
import UIKit

@MainActor
enum CommonGroundInvitationSharing {
    static func prepare(draft: CommonGroundInvitationDraft, backend: WanderBackend, brand: AstirBrandMode) async throws -> WanderShareContent {
        guard let repository = backend.placePlanInvitationRepository,
              let reference = draft.place.photoReference
        else { throw WanderRemoteError.notConfigured }
        // Publish provider artwork only. A visibility-scoped user photo is not
        // implicitly made public when the provider has no image available.
        var image: UIImage?
        if let photo = try? await backend.placePhoto(for: reference.request), photo.isGooglePlacesPhoto,
           let bytes = try? await backend.placePhotoImageData(for: photo, canonicalPlaceKey: reference.request.canonicalPhotoCacheKey, variant: .card) {
            image = UIImage(data: bytes)
        }
        let png = try renderArtwork(draft: draft, photo: image, brand: brand)
        return try await repository.create(draft: draft, previewPNG: png)
    }

    static func renderArtwork(draft: CommonGroundInvitationDraft, photo: UIImage?, brand: AstirBrandMode) throws -> Data {
        let renderer = ImageRenderer(content:
            CGInvitationLinkPreview(draft: draft, showsViewButton: true, sharePhoto: photo, rendersShareArtwork: draft.place.photoReference != nil)
                .environment(\.astirBrandMode, brand)
                .environment(\.dynamicTypeSize, .large)
                .frame(width: PlacePlanArtworkLayout.width)
        )
        renderer.scale = 2
        guard let png = renderer.uiImage?.pngData() else {
            throw WanderRemoteError.invalidResponse("invitation_artwork_unavailable")
        }
        return png
    }
}
#endif
