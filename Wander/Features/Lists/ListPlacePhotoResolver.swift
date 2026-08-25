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
        totalCostLimit: Int = 96 * 1_024 * 1_024,
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
                let startedAt = ContinuousClock.now
                let decodedImage = decoder(data, key.targetPixelSize)
                await PlacePhotoPerformanceMonitor.shared.record(.decode, startedAt: startedAt)
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
final class ListPlacePhotoBatcher {
    struct Resolution {
        let photo: PlacePhoto?
        let wasCancelled: Bool
    }

    private struct GroupKey: Hashable {
        let backendScopeID: UUID
        let eligibleUserIDs: [String]?
        let authorizationScopeKey: String
    }

    private final class PendingBatch {
        var requests: [String: PlacePhotoRequest] = [:]
        var task: Task<[String: Resolution], Never>?
    }

    static let shared = ListPlacePhotoBatcher()

    private let debounceNanoseconds: UInt64
    private var pendingBatches: [GroupKey: PendingBatch] = [:]

    init(debounceNanoseconds: UInt64 = 12_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    func photo(
        for request: PlacePhotoRequest,
        eligibleUserIDs: [String]?,
        authorizationScopeKey: String,
        backend: WanderBackend
    ) async -> Resolution {
        let normalizedEligibleUserIDs = eligibleUserIDs?.sorted()
        let groupKey = GroupKey(
            backendScopeID: backend.photoCacheScopeID,
            eligibleUserIDs: normalizedEligibleUserIDs,
            authorizationScopeKey: authorizationScopeKey
        )
        let pending = pendingBatches[groupKey] ?? PendingBatch()
        pending.requests[request.canonicalPhotoCacheKey] = request
        pendingBatches[groupKey] = pending

        if pending.task == nil {
            let debounceNanoseconds = self.debounceNanoseconds
            pending.task = Task { @MainActor [weak self, weak pending] in
                if debounceNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: debounceNanoseconds)
                } else {
                    await Task.yield()
                }
                guard let self, let pending else { return [:] }
                let requests = Array(pending.requests.values)
                if self.pendingBatches[groupKey] === pending {
                    self.pendingBatches[groupKey] = nil
                }
                return await self.resolve(
                    requests: requests,
                    eligibleUserIDs: normalizedEligibleUserIDs,
                    backend: backend
                )
            }
        }

        let resolutions = await pending.task?.value ?? [:]
        guard !Task.isCancelled else {
            return Resolution(photo: nil, wasCancelled: true)
        }
        return resolutions[request.canonicalPhotoCacheKey]
            ?? Resolution(photo: nil, wasCancelled: false)
    }

    private func resolve(
        requests: [PlacePhotoRequest],
        eligibleUserIDs: [String]?,
        backend: WanderBackend
    ) async -> [String: Resolution] {
        guard !requests.isEmpty else { return [:] }
        var photosByCanonicalKey: [String: PlacePhoto] = [:]

        if eligibleUserIDs?.isEmpty != true {
            let userRequests = requests.map { request in
                if let eligibleUserIDs {
                    return request.restrictingVisibleUserPhotos(to: eligibleUserIDs)
                }
                return request
            }
            do {
                let visiblePhotos = try await backend.visibleUserPlacePhotos(for: userRequests)
                for result in visiblePhotos where result.photo.isUserVisitPhoto {
                    photosByCanonicalKey[result.canonicalPlaceKey] = result.photo
                }
            } catch is CancellationError {
                return cancelledResolutions(for: requests)
            } catch {
                // Missing user photos fall through to category artwork.
            }
        }
        return Dictionary(
            uniqueKeysWithValues: requests.map {
                (
                    $0.canonicalPhotoCacheKey,
                    Resolution(
                        photo: photosByCanonicalKey[$0.canonicalPhotoCacheKey],
                        wasCancelled: false
                    )
                )
            }
        )
    }

    private func cancelledResolutions(
        for requests: [PlacePhotoRequest]
    ) -> [String: Resolution] {
        Dictionary(
            uniqueKeysWithValues: requests.map {
                (
                    $0.canonicalPhotoCacheKey,
                    Resolution(photo: nil, wasCancelled: true)
                )
            }
        )
    }
}

@MainActor
enum ListPlacePhotoResolver {
    static func cachedResolvedPhoto(
        request: PlacePhotoRequest,
        preferredUserPhoto: PlacePhoto?,
        eligibleUserIDs: [String]? = nil,
        authorizationScopeKey: String,
        targetPixelSize: Int,
        backend: WanderBackend,
        selectionCache: ListPlacePhotoSelectionCache = .shared
    ) -> ListPlaceResolvedPhoto? {
        let request = request.rendering(.listThumbnail)
        let key = selectionCacheKey(
            request: request,
            preferredUserPhoto: preferredUserPhoto,
            eligibleUserIDs: eligibleUserIDs,
            authorizationScopeKey: authorizationScopeKey,
            backend: backend
        )
        let selectedPhoto = selectionCache.photo(for: key) ?? preferredUserPhoto
        guard let selectedPhoto,
              selectedPhoto.isUserVisitPhoto,
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
        let request = request.rendering(.listThumbnail)
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

        let batchResolution = await ListPlacePhotoBatcher.shared.photo(
            for: request,
            eligibleUserIDs: eligibleUserIDs,
            authorizationScopeKey: authorizationScopeKey,
            backend: backend
        )
        guard !batchResolution.wasCancelled, !Task.isCancelled else { return nil }
        if let selectedPhoto = batchResolution.photo {
            let resolved = await render(
                selectedPhoto,
                canonicalPlaceKey: request.canonicalPhotoCacheKey,
                backend: backend,
                targetPixelSize: targetPixelSize,
                attemptedPhotoKeys: &attemptedPhotoKeys
            )
            if let resolved {
                selectionCache.insert(resolved.photo, for: selectionKey)
            }
            if let resolved { return resolved }
        }

        return nil
    }

    private static func render(
        _ photo: PlacePhoto,
        canonicalPlaceKey: String,
        backend: WanderBackend,
        targetPixelSize: Int,
        attemptedPhotoKeys: inout Set<String>
    ) async -> ListPlaceResolvedPhoto? {
        guard photo.isUserVisitPhoto else { return nil }
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
                        canonicalPlaceKey: canonicalPlaceKey,
                        variant: .listThumbnail
                    )
                }
            } else {
                data = try await backend.placePhotoImageData(
                    for: photo,
                    canonicalPlaceKey: canonicalPlaceKey,
                    variant: .listThumbnail
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

}
