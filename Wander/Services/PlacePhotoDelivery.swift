import CryptoKit
import Foundation

struct PlacePhotoDataCacheMetrics: Equatable, Sendable {
    let memoryHits: Int
    let diskHits: Int
    let misses: Int
    let networkLoads: Int
    let entryCount: Int
    let totalByteCost: Int
}

enum PlacePhotoLoadStage: String, CaseIterable, Sendable {
    case metadataBatch
    case diskRead
    case networkDownload
    case decode
}

struct PlacePhotoLoadStageMetrics: Equatable, Sendable {
    let sampleCount: Int
    let totalMilliseconds: Double
    let maximumMilliseconds: Double
}

actor PlacePhotoPerformanceMonitor {
    static let shared = PlacePhotoPerformanceMonitor()

    private struct Accumulator {
        var sampleCount = 0
        var totalMilliseconds = 0.0
        var maximumMilliseconds = 0.0
    }

    private var samples: [PlacePhotoLoadStage: Accumulator] = [:]

    func record(_ stage: PlacePhotoLoadStage, startedAt: ContinuousClock.Instant) {
        let duration = startedAt.duration(to: .now)
        let components = duration.components
        let rawMilliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        let milliseconds = max(0, rawMilliseconds)
        var accumulator = samples[stage, default: Accumulator()]
        accumulator.sampleCount += 1
        accumulator.totalMilliseconds += milliseconds
        accumulator.maximumMilliseconds = max(
            accumulator.maximumMilliseconds,
            milliseconds
        )
        samples[stage] = accumulator
    }

    func snapshot() -> [PlacePhotoLoadStage: PlacePhotoLoadStageMetrics] {
        samples.mapValues { accumulator in
            PlacePhotoLoadStageMetrics(
                sampleCount: accumulator.sampleCount,
                totalMilliseconds: accumulator.totalMilliseconds,
                maximumMilliseconds: accumulator.maximumMilliseconds
            )
        }
    }

    func reset() {
        samples = [:]
    }
}

actor PlacePhotoDataDiskCache {
    static let shared = PlacePhotoDataDiskCache()
    static let disabled = PlacePhotoDataDiskCache(isEnabled: false)

    private struct Entry {
        let url: URL
        let byteCost: Int
        let modifiedAt: Date
    }

    private let directoryURL: URL
    private let countLimit: Int
    private let totalCostLimit: Int
    private let fileManager: FileManager
    private let isEnabled: Bool
    private var memoryHits = 0
    private var diskHits = 0
    private var misses = 0
    private var networkLoads = 0

    init(
        directoryURL: URL? = nil,
        countLimit: Int = 512,
        totalCostLimit: Int = 160 * 1_024 * 1_024,
        fileManager: FileManager = .default,
        isEnabled: Bool = true
    ) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = cachesURL.appendingPathComponent(
                "recme-place-photo-variants-v1",
                isDirectory: true
            )
        }
    }

    func data(
        canonicalPlaceKey: String,
        photoKey: String,
        variant: PlacePhotoRenderVariant
    ) -> Data? {
        guard isEnabled else { return nil }
        let startedAt = ContinuousClock.now
        defer {
            Task {
                await PlacePhotoPerformanceMonitor.shared.record(.diskRead, startedAt: startedAt)
            }
        }

        let url = fileURL(
            canonicalPlaceKey: canonicalPlaceKey,
            photoKey: photoKey,
            variant: variant
        )
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            misses += 1
            return nil
        }
        diskHits += 1
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func insert(
        _ data: Data,
        canonicalPlaceKey: String,
        photoKey: String,
        variant: PlacePhotoRenderVariant
    ) {
        guard isEnabled else { return }
        guard !data.isEmpty, data.count <= totalCostLimit else { return }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let url = fileURL(
                canonicalPlaceKey: canonicalPlaceKey,
                photoKey: photoKey,
                variant: variant
            )
            try data.write(to: url, options: .atomic)
            try pruneIfNeeded()
        } catch {
            // Disk caching is an optimization; delivery continues from memory/network.
        }
    }

    func recordMemoryHit() {
        guard isEnabled else { return }
        memoryHits += 1
    }

    func recordNetworkLoad() {
        guard isEnabled else { return }
        networkLoads += 1
    }

    func metrics() -> PlacePhotoDataCacheMetrics {
        let entries = cacheEntries()
        return PlacePhotoDataCacheMetrics(
            memoryHits: memoryHits,
            diskHits: diskHits,
            misses: misses,
            networkLoads: networkLoads,
            entryCount: entries.count,
            totalByteCost: entries.reduce(0) { $0 + $1.byteCost }
        )
    }

    func removeAll() {
        guard isEnabled else { return }
        try? fileManager.removeItem(at: directoryURL)
        memoryHits = 0
        diskHits = 0
        misses = 0
        networkLoads = 0
    }

    private func fileURL(
        canonicalPlaceKey: String,
        photoKey: String,
        variant: PlacePhotoRenderVariant
    ) -> URL {
        let identity = "\(canonicalPlaceKey.utf8.count):\(canonicalPlaceKey)|\(photoKey)|\(variant.rawValue)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).image", isDirectory: false)
    }

    private func pruneIfNeeded() throws {
        var entries = cacheEntries().sorted { $0.modifiedAt > $1.modifiedAt }
        var totalCost = entries.reduce(0) { $0 + $1.byteCost }
        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let entry = entries.popLast() else { break }
            try? fileManager.removeItem(at: entry.url)
            totalCost -= entry.byteCost
        }
    }

    private func cacheEntries() -> [Entry] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true else { return nil }
            return Entry(
                url: url,
                byteCost: max(0, values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }
}

actor PlacePhotoDownloadLimiter {
    static let shared = PlacePhotoDownloadLimiter(limit: 4)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if activeCount < limit {
            activeCount += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        while let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
            return
        }
        activeCount = max(0, activeCount - 1)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
