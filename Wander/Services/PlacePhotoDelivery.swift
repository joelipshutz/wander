import CryptoKit
import Darwin
import Foundation

/// Image bytes can stay cached; signed delivery URLs and live business facts cannot.
enum PlacePhotoManifestCachePolicy {
    static let freshness: TimeInterval = 5 * 60

    static func isFresh(cachedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(cachedAt)
        return age >= 0 && age < freshness
    }
}

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
        let fileID: String
    }

    private var contentDirectoryURL: URL {
        directoryURL.appendingPathComponent("content", isDirectory: true)
    }

    private let revocationDirectoryURL: URL
    private let directoryURL: URL
    private let countLimit: Int
    private let totalCostLimit: Int
    private let fileManager: FileManager
    private let isEnabled: Bool
    private var memoryHits = 0
    private var diskHits = 0
    private var misses = 0
    private var networkLoads = 0
    private var revocationRevisions: [String: Int] = [:]
    private var revokedKeys: Set<String> = []

    init(
        directoryURL: URL? = nil,
        revocationDirectoryURL: URL? = nil,
        countLimit: Int = 512,
        totalCostLimit: Int = 160 * 1_024 * 1_024,
        fileManager: FileManager = .default,
        isEnabled: Bool = true
    ) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.revocationDirectoryURL = revocationDirectoryURL
            ?? directoryURL?.appendingPathComponent("access", isDirectory: true)
            ?? applicationSupport.appendingPathComponent("recme-photo-access-v1", isDirectory: true)
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
        if isEnabled {
            Task(priority: .utility) { await self.consolidateExistingEntries() }
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
            try storeSharedBytes(data, at: url)
            try pruneIfNeeded()
        } catch {
            // Disk caching is an optimization; delivery continues from memory/network.
            removeUnreferencedContent()
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
            totalByteCost: uniqueByteCost(entries)
        )
    }

    func removeAll() {
        guard isEnabled else { return }
        for entry in cacheEntries() { try? fileManager.removeItem(at: entry.url) }
        removeUnreferencedContent()
        memoryHits = 0
        diskHits = 0
        misses = 0
        networkLoads = 0
    }

    func remove(canonicalPlaceKey: String, photoKey: String) {
        guard isEnabled else { return }
        for variant in PlacePhotoRenderVariant.allCases {
            try? fileManager.removeItem(at: fileURL(
                canonicalPlaceKey: canonicalPlaceKey, photoKey: photoKey, variant: variant
            ))
        }
        removeUnreferencedContent()
    }

    /// Retain the v1 lookup paths and exact image bytes while reclaiming duplicate
    /// payloads. Yield between files so a first upgrade does not monopolize reads.
    func consolidateExistingEntries() async {
        guard isEnabled else { return }
        let files = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix(".photo-link-") {
            try? fileManager.removeItem(at: url)
        }
        for entry in cacheEntries() {
            if referenceCount(at: entry.url) == 1,
               let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe),
               !data.isEmpty {
                try? storeSharedBytes(data, at: entry.url, existingFile: true, modifiedAt: entry.modifiedAt)
            }
            await Task.yield()
        }
        try? pruneIfNeeded()
    }

    /// Scoped lookup -> hard link -> content-addressed bytes. The digest is only
    /// a storage identity; callers still require their existing authorized key.
    /// Atomic replacement keeps updating one variant from mutating other links.
    private func storeSharedBytes(
        _ data: Data,
        at url: URL,
        existingFile: Bool = false,
        modifiedAt: Date = .now
    ) throws {
        try fileManager.createDirectory(at: contentDirectoryURL, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let contentURL = contentDirectoryURL.appendingPathComponent(digest)
        if !fileManager.fileExists(atPath: contentURL.path) {
            if existingFile {
                try fileManager.linkItem(at: url, to: contentURL)
            } else {
                try data.write(to: contentURL, options: .atomic)
            }
        }
        let temporaryURL = directoryURL.appendingPathComponent(".photo-link-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.linkItem(at: contentURL, to: temporaryURL)
        guard rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let previousDate = (try? fileManager.attributesOfItem(atPath: contentURL.path)[.modificationDate]) as? Date
        try? fileManager.setAttributes(
            [.modificationDate: max(previousDate ?? modifiedAt, modifiedAt)],
            ofItemAtPath: url.path
        )
    }

    private func referenceCount(at url: URL) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.referenceCount] as? NSNumber)?.intValue
    }

    private func removeUnreferencedContent() {
        let files = (try? fileManager.contentsOfDirectory(at: contentDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in files where referenceCount(at: url) == 1 {
            try? fileManager.removeItem(at: url)
        }
    }

    private func uniqueByteCost(_ entries: [Entry]) -> Int {
        var seen: Set<String> = []
        return entries.reduce(0) { cost, entry in
            cost + (seen.insert(entry.fileID).inserted ? entry.byteCost : 0)
        }
    }

    func recordRevocation(_ key: String) {
        revocationRevisions[key, default: 0] += 1
        revokedKeys.insert(key)
        guard isEnabled else { return }
        try? fileManager.createDirectory(at: revocationDirectoryURL, withIntermediateDirectories: true)
        try? Data().write(to: revocationURL(key), options: .atomic)
    }

    func hasRevocation(_ key: String) -> Bool {
        revokedKeys.contains(key) || (isEnabled && fileManager.fileExists(atPath: revocationURL(key).path))
    }

    func revocationRevision(_ key: String) -> Int { revocationRevisions[key, default: 0] }

    func clearRevocation(_ key: String, ifRevision revision: Int) -> Bool {
        guard revision == revocationRevisions[key, default: 0] else { return false }
        revokedKeys.remove(key)
        if isEnabled { try? fileManager.removeItem(at: revocationURL(key)) }
        return true
    }

    private func revocationURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return revocationDirectoryURL.appendingPathComponent("\(digest).denied")
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
        var totalCost = uniqueByteCost(entries)
        var references = Dictionary(grouping: entries, by: \.fileID).mapValues(\.count)
        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let entry = entries.popLast() else { break }
            try fileManager.removeItem(at: entry.url)
            references[entry.fileID, default: 1] -= 1
            if references[entry.fileID] == 0 { totalCost -= entry.byteCost }
        }
        removeUnreferencedContent()
    }

    private func cacheEntries() -> [Entry] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "image" else { return nil }
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let fileID = attributes[.systemFileNumber] as? NSNumber,
                  let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true else { return nil }
            return Entry(
                url: url,
                byteCost: max(0, values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                fileID: fileID.stringValue
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
