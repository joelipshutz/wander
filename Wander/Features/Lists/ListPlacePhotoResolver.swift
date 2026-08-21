import ImageIO
import UIKit

struct ListPlaceResolvedPhoto {
    let photo: PlacePhoto
    let image: UIImage
}

final class PlacePhotoDecodedImage: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    var estimatedByteCost: Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct PlacePhotoImageCacheMetrics: Equatable, Sendable {
    let hits: Int
    let misses: Int
    let coalescedRequests: Int
    let entryCount: Int
    let totalByteCost: Int
}

private struct PlacePhotoImageCacheKey: Hashable, Sendable {
    let canonicalPlaceKey: String
    let photoKey: String
    let targetPixelSize: Int
}

private final class PlacePhotoImageMemoryCache: @unchecked Sendable {
    private struct Entry {
        let image: PlacePhotoDecodedImage
        let byteCost: Int
    }

    private let countLimit: Int
    private let totalCostLimit: Int
    private let lock = NSLock()
    private var entries: [PlacePhotoImageCacheKey: Entry] = [:]
    private var recency: [PlacePhotoImageCacheKey] = []
    private var totalByteCost = 0
    private var hits = 0
    private var misses = 0
    private var coalescedRequests = 0

    init(countLimit: Int, totalCostLimit: Int) {
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
    }

    func image(for key: PlacePhotoImageCacheKey) -> PlacePhotoDecodedImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key] else {
            misses += 1
            return nil
        }
        hits += 1
        markRecentlyUsed(key)
        return entry.image
    }

    func insert(_ image: PlacePhotoDecodedImage, for key: PlacePhotoImageCacheKey) {
        lock.lock()
        defer { lock.unlock() }

        if let previous = entries.removeValue(forKey: key) {
            totalByteCost -= previous.byteCost
        }
        recency.removeAll { $0 == key }

        let entry = Entry(image: image, byteCost: max(1, image.estimatedByteCost))
        entries[key] = entry
        recency.append(key)
        totalByteCost += entry.byteCost

        while entries.count > countLimit || totalByteCost > totalCostLimit {
            guard let oldestKey = recency.first else { break }
            recency.removeFirst()
            if let removed = entries.removeValue(forKey: oldestKey) {
                totalByteCost -= removed.byteCost
            }
        }
    }

    func recordCoalescedRequest() {
        lock.lock()
        coalescedRequests += 1
        lock.unlock()
    }

    func metrics() -> PlacePhotoImageCacheMetrics {
        lock.lock()
        defer { lock.unlock() }
        return PlacePhotoImageCacheMetrics(
            hits: hits,
            misses: misses,
            coalescedRequests: coalescedRequests,
            entryCount: entries.count,
            totalByteCost: totalByteCost
        )
    }

    private func markRecentlyUsed(_ key: PlacePhotoImageCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

actor PlacePhotoImagePipeline {
    static let shared = PlacePhotoImagePipeline()

    typealias Decoder = @Sendable (Data, Int) -> PlacePhotoDecodedImage?

    private struct InFlightEntry {
        let id: UUID
        let task: Task<PlacePhotoDecodedImage?, Never>
    }

    nonisolated private let cache: PlacePhotoImageMemoryCache
    private let decoder: Decoder
    private var inFlight: [PlacePhotoImageCacheKey: InFlightEntry] = [:]

    init(
        countLimit: Int = 128,
        totalCostLimit: Int = 32 * 1_024 * 1_024,
        decoder: @escaping Decoder = { data, targetPixelSize in
            guard let image = PlacePhotoImagePipeline.downsampledImage(
                from: data,
                targetPixelSize: targetPixelSize
            ) else { return nil }
            return PlacePhotoDecodedImage(image: image)
        }
    ) {
        cache = PlacePhotoImageMemoryCache(
            countLimit: countLimit,
            totalCostLimit: totalCostLimit
        )
        self.decoder = decoder
    }

    nonisolated func cachedImage(
        canonicalPlaceKey: String,
        photoKey: String,
        targetPixelSize: Int
    ) -> PlacePhotoDecodedImage? {
        cache.image(
            for: Self.cacheKey(
                canonicalPlaceKey: canonicalPlaceKey,
                photoKey: photoKey,
                targetPixelSize: targetPixelSize
            )
        )
    }

    nonisolated func cacheMetrics() -> PlacePhotoImageCacheMetrics {
        cache.metrics()
    }

    func image(
        from data: Data,
        canonicalPlaceKey: String,
        photoKey: String,
        targetPixelSize: Int
    ) async -> PlacePhotoDecodedImage? {
        guard !Task.isCancelled else { return nil }

        let key = Self.cacheKey(
            canonicalPlaceKey: canonicalPlaceKey,
            photoKey: photoKey,
            targetPixelSize: targetPixelSize
        )
        if let cached = cache.image(for: key) {
            return cached
        }

        let entry: InFlightEntry
        if let existing = inFlight[key] {
            cache.recordCoalescedRequest()
            entry = existing
        } else {
            let id = UUID()
            let decoder = self.decoder
            let task = Task<PlacePhotoDecodedImage?, Never>.detached(priority: .utility) {
                guard !Task.isCancelled else { return nil }
                let decodedImage = decoder(data, key.targetPixelSize)
                guard !Task.isCancelled else { return nil }
                return decodedImage
            }
            let newEntry = InFlightEntry(id: id, task: task)
            inFlight[key] = newEntry
            entry = newEntry
        }

        let decodedImage = await entry.task.value
        if inFlight[key]?.id == entry.id {
            inFlight[key] = nil
            if let decodedImage {
                cache.insert(decodedImage, for: key)
            }
        }
        guard !Task.isCancelled else { return nil }
        return decodedImage
    }

    nonisolated private static func cacheKey(
        canonicalPlaceKey: String,
        photoKey: String,
        targetPixelSize: Int
    ) -> PlacePhotoImageCacheKey {
        PlacePhotoImageCacheKey(
            canonicalPlaceKey: canonicalPlaceKey,
            photoKey: photoKey,
            targetPixelSize: normalizedTargetPixelSize(targetPixelSize)
        )
    }

    nonisolated private static func normalizedTargetPixelSize(_ targetPixelSize: Int) -> Int {
        let clamped = max(1, targetPixelSize)
        let quantum = 64
        return ((clamped + quantum - 1) / quantum) * quantum
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
final class ListPlacePhotoSelectionCache {
    struct Key: Hashable {
        let backendScopeID: UUID
        let canonicalPlaceKey: String
        let preferredPhotoKey: String
        let eligibleUserIDs: [String]?
        let authorizationScopeKey: String
    }

    static let shared = ListPlacePhotoSelectionCache()

    private let countLimit: Int
    private var photos: [Key: PlacePhoto] = [:]
    private var recency: [Key] = []

    init(countLimit: Int = 256) {
        self.countLimit = max(1, countLimit)
    }

    func photo(for key: Key) -> PlacePhoto? {
        guard let photo = photos[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return photo
    }

    func insert(_ photo: PlacePhoto, for key: Key) {
        photos[key] = photo
        recency.removeAll { $0 == key }
        recency.append(key)

        while photos.count > countLimit, let oldestKey = recency.first {
            recency.removeFirst()
            photos.removeValue(forKey: oldestKey)
        }
    }

    func removePhoto(for key: Key) {
        photos.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }

    var entryCount: Int { photos.count }
}

@MainActor
enum ListPlacePhotoResolver {
    private struct VisibleUserPhotoTask {
        let id: UUID
        let task: Task<PlacePhoto, Error>
    }

    private static var visibleUserPhotoTasks: [String: VisibleUserPhotoTask] = [:]

    static func cachedResolvedPhoto(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        eligibleUserIDs: [String]? = nil,
        authorizationScopeKey: String,
        targetPixelSize: Int,
        backend: WanderBackend,
        selectionCache: ListPlacePhotoSelectionCache = .shared
    ) -> ListPlaceResolvedPhoto? {
        let key = selectionCacheKey(
            request: request,
            preferredUserPhoto: preferredUserPhoto,
            eligibleUserIDs: eligibleUserIDs,
            authorizationScopeKey: authorizationScopeKey,
            backend: backend
        )
        let selectedPhoto = selectionCache.photo(for: key) ?? preferredUserPhoto
        guard let selectedPhoto,
              let decodedImage = PlacePhotoImagePipeline.shared.cachedImage(
                  canonicalPlaceKey: request.canonicalPhotoCacheKey,
                  photoKey: selectedPhoto.cacheKey,
                  targetPixelSize: targetPixelSize
              )
        else { return nil }

        selectionCache.insert(selectedPhoto, for: key)
        return ListPlaceResolvedPhoto(photo: selectedPhoto, image: decodedImage.image)
    }

    static func resolve(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        eligibleUserIDs: [String]? = nil,
        authorizationScopeKey: String,
        targetPixelSize: Int,
        backend: WanderBackend,
        selectionCache: ListPlacePhotoSelectionCache = .shared
    ) async -> ListPlaceResolvedPhoto? {
        var attemptedPhotoKeys = Set<String>()
        let selectionKey = selectionCacheKey(
            request: request,
            preferredUserPhoto: preferredUserPhoto,
            eligibleUserIDs: eligibleUserIDs,
            authorizationScopeKey: authorizationScopeKey,
            backend: backend
        )

        if let cachedPhoto = selectionCache.photo(for: selectionKey) {
            if let resolved = await render(
                cachedPhoto,
                canonicalPlaceKey: request.canonicalPhotoCacheKey,
                backend: backend,
                targetPixelSize: targetPixelSize,
                attemptedPhotoKeys: &attemptedPhotoKeys
            ) {
                return resolved
            }
            selectionCache.removePhoto(for: selectionKey)
        }

        if let preferredUserPhoto,
           let resolved = await render(
               preferredUserPhoto,
               canonicalPlaceKey: request.canonicalPhotoCacheKey,
               backend: backend,
               targetPixelSize: targetPixelSize,
               attemptedPhotoKeys: &attemptedPhotoKeys
           ) {
            selectionCache.insert(resolved.photo, for: selectionKey)
            return resolved
        }

        if eligibleUserIDs?.isEmpty != true {
            do {
                let visibleUserPhoto = try await visibleUserPhoto(
                    for: request,
                    eligibleUserIDs: eligibleUserIDs,
                    authorizationScopeKey: authorizationScopeKey,
                    backend: backend
                )
                if let resolved = await render(
                    visibleUserPhoto,
                    canonicalPlaceKey: request.canonicalPhotoCacheKey,
                    backend: backend,
                    targetPixelSize: targetPixelSize,
                    attemptedPhotoKeys: &attemptedPhotoKeys
                ) {
                    selectionCache.insert(resolved.photo, for: selectionKey)
                    return resolved
                }
            } catch is CancellationError {
                return nil
            } catch {
                // A missing eligible user photo is the expected path to provider fallback.
            }
        }

        guard !Task.isCancelled else { return nil }

        do {
            let providerPhoto = try await backend.placePhoto(for: request)
            let resolved = await render(
                providerPhoto,
                canonicalPlaceKey: request.canonicalPhotoCacheKey,
                backend: backend,
                targetPixelSize: targetPixelSize,
                attemptedPhotoKeys: &attemptedPhotoKeys
            )
            if let resolved {
                selectionCache.insert(resolved.photo, for: selectionKey)
            }
            return resolved
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private static func render(
        _ photo: PlacePhoto,
        canonicalPlaceKey: String,
        backend: WanderBackend,
        targetPixelSize: Int,
        attemptedPhotoKeys: inout Set<String>
    ) async -> ListPlaceResolvedPhoto? {
        guard attemptedPhotoKeys.insert(photo.cacheKey).inserted else { return nil }

        if let decodedImage = PlacePhotoImagePipeline.shared.cachedImage(
            canonicalPlaceKey: canonicalPlaceKey,
            photoKey: photo.cacheKey,
            targetPixelSize: targetPixelSize
        ) {
            return ListPlaceResolvedPhoto(photo: photo, image: decodedImage.image)
        }

        do {
            let data: Data
            if let localAssetRef = photo.localAssetRef {
                if let localData = await Task.detached(priority: .utility, operation: {
                    VisitPhotoLocalFileStore.data(from: localAssetRef)
                }).value {
                    data = localData
                } else {
                    data = try await backend.placePhotoImageData(
                        for: photo,
                        canonicalPlaceKey: canonicalPlaceKey
                    )
                }
            } else {
                data = try await backend.placePhotoImageData(
                    for: photo,
                    canonicalPlaceKey: canonicalPlaceKey
                )
            }
            try Task.checkCancellation()
            guard let decodedImage = await PlacePhotoImagePipeline.shared.image(
                from: data,
                canonicalPlaceKey: canonicalPlaceKey,
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

    private static func selectionCacheKey(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        eligibleUserIDs: [String]?,
        authorizationScopeKey: String,
        backend: WanderBackend
    ) -> ListPlacePhotoSelectionCache.Key {
        ListPlacePhotoSelectionCache.Key(
            backendScopeID: backend.photoCacheScopeID,
            canonicalPlaceKey: request.canonicalPhotoCacheKey,
            preferredPhotoKey: preferredUserPhoto?.cacheKey ?? "none",
            eligibleUserIDs: eligibleUserIDs?.sorted(),
            authorizationScopeKey: authorizationScopeKey
        )
    }

    private static func visibleUserPhoto(
        for request: PlacePhotoRequest,
        eligibleUserIDs: [String]?,
        authorizationScopeKey: String,
        backend: WanderBackend
    ) async throws -> PlacePhoto {
        try Task.checkCancellation()
        let contributorKey = eligibleUserIDs?
            .sorted()
            .joined(separator: ",") ?? "all-visible-users"
        let key = "\(authorizationScopeKey)|\(request.lookupKey)|contributors:\(contributorKey)"
        let entry: VisibleUserPhotoTask
        if let existing = visibleUserPhotoTasks[key] {
            entry = existing
        } else {
            let id = UUID()
            let task = Task { @MainActor in
                if let eligibleUserIDs {
                    return try await backend.visibleUserPlacePhoto(
                        for: request.restrictingVisibleUserPhotos(to: eligibleUserIDs)
                    )
                }
                return try await backend.visibleUserPlacePhoto(for: request)
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
