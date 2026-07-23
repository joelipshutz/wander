import ImageIO
import UIKit

struct ListPlaceResolvedPhoto {
    let photo: PlacePhoto
    let image: UIImage
}

private final class ListPlaceDecodedImage: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    var estimatedByteCost: Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

private actor ListPlacePhotoImagePipeline {
    static let shared = ListPlacePhotoImagePipeline()

    private struct CacheKey: Hashable, Sendable {
        let photoKey: String
        let targetPixelSize: Int

        var cacheKey: NSString {
            "\(photoKey)|target-px:\(targetPixelSize)" as NSString
        }
    }

    private struct InFlightEntry {
        let id: UUID
        let task: Task<ListPlaceDecodedImage?, Never>
    }

    private let cache: NSCache<NSString, ListPlaceDecodedImage>
    private var inFlight: [CacheKey: InFlightEntry] = [:]

    init(countLimit: Int = 128, totalCostLimit: Int = 32 * 1_024 * 1_024) {
        cache = NSCache<NSString, ListPlaceDecodedImage>()
        cache.countLimit = max(1, countLimit)
        cache.totalCostLimit = max(1, totalCostLimit)
    }

    func image(
        from data: Data,
        photoKey: String,
        targetPixelSize: Int
    ) async -> ListPlaceDecodedImage? {
        guard !Task.isCancelled else { return nil }

        let key = CacheKey(
            photoKey: photoKey,
            targetPixelSize: max(1, targetPixelSize)
        )
        if let cached = cache.object(forKey: key.cacheKey) {
            return cached
        }

        let entry: InFlightEntry
        if let existing = inFlight[key] {
            entry = existing
        } else {
            let id = UUID()
            let task = Task<ListPlaceDecodedImage?, Never>.detached(priority: .utility) {
                guard !Task.isCancelled,
                      let image = Self.downsampledImage(
                          from: data,
                          targetPixelSize: key.targetPixelSize
                      ),
                      !Task.isCancelled
                else {
                    return nil
                }
                return ListPlaceDecodedImage(image: image)
            }
            let newEntry = InFlightEntry(id: id, task: task)
            inFlight[key] = newEntry
            entry = newEntry
        }

        let decodedImage = await entry.task.value
        if inFlight[key]?.id == entry.id {
            inFlight[key] = nil
            if let decodedImage {
                cache.setObject(
                    decodedImage,
                    forKey: key.cacheKey,
                    cost: max(1, decodedImage.estimatedByteCost)
                )
            }
        }
        guard !Task.isCancelled else { return nil }
        return decodedImage
    }

    nonisolated private static func downsampledImage(
        from data: Data,
        targetPixelSize: Int
    ) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
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
    private struct VisibleUserPhotoTask {
        let id: UUID
        let task: Task<PlacePhoto, Error>
    }

    private static var visibleUserPhotoTasks: [String: VisibleUserPhotoTask] = [:]

    static func authorizationScopeKey(for store: WanderStore) -> String {
        let followsKey = store.follows
            .map {
                "\($0.followerUserID)>\($0.followedUserID):\($0.localUpdatedAt.timeIntervalSinceReferenceDate.bitPattern)"
            }
            .sorted()
            .joined(separator: ",")
        let blocksKey = store.blocks
            .map {
                "\($0.blockerUserID)>\($0.blockedUserID):\($0.localUpdatedAt.timeIntervalSinceReferenceDate.bitPattern)"
            }
            .sorted()
            .joined(separator: ",")
        return "user:\(store.currentUser.id)|follows:\(followsKey)|blocks:\(blocksKey)"
    }

    static func resolve(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        authorizationScopeKey: String,
        targetPixelSize: Int,
        backend: WanderBackend
    ) async -> ListPlaceResolvedPhoto? {
        var attemptedPhotoKeys = Set<String>()

        if let preferredUserPhoto,
           let resolved = await render(
               preferredUserPhoto,
               backend: backend,
               targetPixelSize: targetPixelSize,
               attemptedPhotoKeys: &attemptedPhotoKeys
           ) {
            return resolved
        }

        do {
            let visibleUserPhoto = try await visibleUserPhoto(
                for: request,
                authorizationScopeKey: authorizationScopeKey,
                backend: backend
            )
            if let resolved = await render(
                visibleUserPhoto,
                backend: backend,
                targetPixelSize: targetPixelSize,
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
                targetPixelSize: targetPixelSize,
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
        targetPixelSize: Int,
        attemptedPhotoKeys: inout Set<String>
    ) async -> ListPlaceResolvedPhoto? {
        guard attemptedPhotoKeys.insert(photo.cacheKey).inserted else { return nil }

        do {
            let data: Data
            if let localAssetRef = photo.localAssetRef {
                if let localData = await Task.detached(priority: .utility, operation: {
                    VisitPhotoLocalFileStore.data(from: localAssetRef)
                }).value {
                    data = localData
                } else {
                    data = try await backend.placePhotoImageData(for: photo)
                }
            } else {
                data = try await backend.placePhotoImageData(for: photo)
            }
            try Task.checkCancellation()
            guard let decodedImage = await ListPlacePhotoImagePipeline.shared.image(
                from: data,
                photoKey: photo.cacheKey,
                targetPixelSize: targetPixelSize
            ) else {
                return nil
            }
            try Task.checkCancellation()
            return ListPlaceResolvedPhoto(photo: photo, image: decodedImage.image)
        } catch {
            return nil
        }
    }

    private static func visibleUserPhoto(
        for request: PlacePhotoRequest,
        authorizationScopeKey: String,
        backend: WanderBackend
    ) async throws -> PlacePhoto {
        try Task.checkCancellation()
        let key = "\(authorizationScopeKey)|\(request.lookupKey)"
        let entry: VisibleUserPhotoTask
        if let existing = visibleUserPhotoTasks[key] {
            entry = existing
        } else {
            let id = UUID()
            let task = Task { @MainActor in
                try await backend.visibleUserPlacePhoto(for: request)
            }
            let newEntry = VisibleUserPhotoTask(id: id, task: task)
            visibleUserPhotoTasks[key] = newEntry
            entry = newEntry
        }

        do {
            let photo = try await entry.task.value
            if visibleUserPhotoTasks[key]?.id == entry.id {
                visibleUserPhotoTasks[key] = nil
            }
            try Task.checkCancellation()
            return photo
        } catch {
            if visibleUserPhotoTasks[key]?.id == entry.id {
                visibleUserPhotoTasks[key] = nil
            }
            throw error
        }
    }
}
