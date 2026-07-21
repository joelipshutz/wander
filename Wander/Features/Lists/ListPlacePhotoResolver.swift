import UIKit

struct ListPlaceResolvedPhoto {
    let photo: PlacePhoto
    let image: UIImage
}

enum ListPreviewPlaceSelector {
    static func distinctPrefix(_ places: [VisiblePlace], limit: Int) -> [VisiblePlace] {
        guard limit > 0 else { return [] }

        var seenPlaceIDs = Set<String>()
        var selected: [VisiblePlace] = []
        selected.reserveCapacity(min(limit, places.count))

        for place in places where seenPlaceIDs.insert(place.place.id).inserted {
            selected.append(place)
            if selected.count == limit {
                break
            }
        }

        return selected
    }
}

@MainActor
enum ListPlacePhotoResolver {
    static func resolve(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        backend: WanderBackend
    ) async -> ListPlaceResolvedPhoto? {
        var attemptedPhotoKeys = Set<String>()

        if let preferredUserPhoto,
           let resolved = await render(
               preferredUserPhoto,
               backend: backend,
               attemptedPhotoKeys: &attemptedPhotoKeys
           ) {
            return resolved
        }

        do {
            let visibleUserPhoto = try await backend.visibleUserPlacePhoto(for: request)
            if let resolved = await render(
                visibleUserPhoto,
                backend: backend,
                attemptedPhotoKeys: &attemptedPhotoKeys
            ) {
                return resolved
            }
        } catch is CancellationError {
            return nil
        } catch {
            // A missing visible user photo is the expected path to provider fallback.
        }

        guard !Task.isCancelled else { return nil }

        do {
            let providerPhoto = try await backend.placePhoto(for: request)
            return await render(
                providerPhoto,
                backend: backend,
                attemptedPhotoKeys: &attemptedPhotoKeys
            )
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private static func render(
        _ photo: PlacePhoto,
        backend: WanderBackend,
        attemptedPhotoKeys: inout Set<String>
    ) async -> ListPlaceResolvedPhoto? {
        guard attemptedPhotoKeys.insert(photo.cacheKey).inserted else { return nil }

        if let localAssetRef = photo.localAssetRef,
           let localImage = VisitPhotoLocalFileStore.image(from: localAssetRef) {
            return ListPlaceResolvedPhoto(photo: photo, image: localImage)
        }

        do {
            let data = try await backend.placePhotoImageData(for: photo)
            try Task.checkCancellation()
            guard let image = UIImage(data: data) else { return nil }
            return ListPlaceResolvedPhoto(photo: photo, image: image)
        } catch {
            return nil
        }
    }
}
