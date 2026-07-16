import CoreLocation
import Foundation

struct PlaceImportResolvedEntry: Equatable {
    let seed: PlaceImportSeed
    let candidates: [PlaceCandidate]
    let selectedCandidateID: String?
    let helpMessage: String?
}

enum PlaceImportResolution: Equatable {
    case candidates([PlaceCandidate], selectedCandidateID: String?)
    case needsHelp(String)
    case expanded([PlaceImportSeed], sourceName: String?)
    case expandedResolved([PlaceImportResolvedEntry], sourceName: String?)
}

@MainActor
protocol PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution
}

@MainActor
final class DevicePlaceImportResolver: PlaceImportResolving {
    private let placeResolver: any PlaceCandidateResolving
    private let metadataProvider: any SocialImportMetadataProviding
    private let googleListLoader: any GoogleMapsSharedListLoading
    private let thumbnailRecognizer: any SocialThumbnailTextRecognizing

    init(
        placeResolver: any PlaceCandidateResolving = MapKitPlaceResolver(),
        metadataProvider: any SocialImportMetadataProviding = PublicSocialImportMetadataProvider(),
        googleListLoader: any GoogleMapsSharedListLoading = GoogleMapsSharedListImporter(),
        thumbnailRecognizer: any SocialThumbnailTextRecognizing = VisionSocialThumbnailTextRecognizer()
    ) {
        self.placeResolver = placeResolver
        self.metadataProvider = metadataProvider
        self.googleListLoader = googleListLoader
        self.thumbnailRecognizer = thumbnailRecognizer
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        if let name = normalized(seed.nameHint) {
            if source == .googleMaps, isAuthoritativeGoogleSeed(seed) {
                return await googleSeedResolution(seed, name: name)
            }
            return try await manualResolution(
                name: name,
                area: seed.areaHint,
                latitude: seed.latitude,
                longitude: seed.longitude
            )
        }

        guard let sourceURLString = seed.sourceURLString,
              let sourceURL = URL(string: sourceURLString)
        else {
            return .needsHelp("Add a place name and nearby city to match this item.")
        }

        switch source {
        case .googleMaps:
            switch await googleListLoader.load(from: sourceURL) {
            case .list(let list):
                return .expanded(list.seeds, sourceName: list.name)
            case .singlePlace(let expandedURLString):
                do {
                    let candidates = try await placeResolver.resolveLink(
                        LinkPlaceInput(rawValue: expandedURLString)
                    )
                    return candidateResolution(candidates, seed: seed)
                } catch {
                    return .needsHelp("No matching Apple Maps place was found for this link.")
                }
            case .unavailable(let message):
                return .needsHelp(message)
            }
        case .tiktok, .instagram:
            return await socialResolution(url: sourceURL, source: source, seed: seed)
        case .textNotes:
            return .needsHelp("Add a place name and nearby city to match this line.")
        }
    }

    private func socialResolution(
        url: URL,
        source: PlaceImportSource,
        seed: PlaceImportSeed
    ) async -> PlaceImportResolution {
        guard let metadata = await metadataProvider.metadata(for: url, source: source) else {
            return .needsHelp(
                "This public post did not expose a caption or cover image. Check the link and retry automatic matching."
            )
        }
        let recognizedText: String? = if let thumbnailURL = metadata.thumbnailURL {
            await thumbnailRecognizer.recognizedText(at: thumbnailURL)
        } else {
            nil
        }
        let hints = SocialPlaceHintExtractor.hints(
            from: metadata,
            recognizedText: recognizedText,
            limit: 8
        )

        var resolvedEntries: [PlaceImportResolvedEntry] = []
        var plausibleEntries: [PlaceImportResolvedEntry] = []
        var seenResolvedCandidates = Set<String>()
        var seenPlausibleHints = Set<String>()
        var strongest: PlaceImportCandidateMatch?
        for hint in hints {
            guard let candidates = try? await placeResolver.resolveManualEntry(
                ManualPlaceInput(name: hint.name, areaHint: hint.area, category: nil)
            ), !candidates.isEmpty else { continue }
            let match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: hint.name,
                areaHint: hint.area
            )
            if let selectedCandidateID = match.selectedCandidateID,
               let selectedCandidate = match.candidates.first(where: { $0.id == selectedCandidateID }) {
                let identity = candidateIdentity(selectedCandidate)
                if seenResolvedCandidates.insert(identity).inserted {
                    resolvedEntries.append(
                        PlaceImportResolvedEntry(
                            seed: socialSeed(from: seed, hint: hint, candidate: selectedCandidate),
                            candidates: match.candidates,
                            selectedCandidateID: selectedCandidateID,
                            helpMessage: nil
                        )
                    )
                }
                continue
            }
            if match.candidates.count > 1, match.bestScore >= 0.7 {
                let identity = hintIdentity(hint)
                if seenPlausibleHints.insert(identity).inserted {
                    plausibleEntries.append(
                        PlaceImportResolvedEntry(
                            seed: socialSeed(from: seed, hint: hint, candidate: nil),
                            candidates: match.candidates,
                            selectedCandidateID: nil,
                            helpMessage: "Choose the matching venue from this post."
                        )
                    )
                }
            }
            if match.bestScore > (strongest?.bestScore ?? 0) {
                strongest = match
            }
        }

        let entries = resolvedEntries + plausibleEntries
        if entries.count == 1, let entry = entries.first {
            return .candidates(entry.candidates, selectedCandidateID: entry.selectedCandidateID)
        }
        if entries.count > 1 {
            return .expandedResolved(entries, sourceName: nil)
        }
        if let strongest, strongest.bestScore >= 0.38 {
            return candidateResolution(strongest)
        }
        return .needsHelp(
            "No confident place match was found from this post's caption or cover image. Retry automatic matching."
        )
    }

    private func manualResolution(
        name: String,
        area: String?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async throws -> PlaceImportResolution {
        do {
            let candidates = try await placeResolver.resolveManualEntry(
                ManualPlaceInput(name: name, areaHint: normalized(area), category: nil)
            )
            let match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: name,
                areaHint: area,
                latitude: latitude,
                longitude: longitude
            )
            return candidateResolution(match)
        } catch let error as LocalizedError {
            return .needsHelp(error.errorDescription ?? "No matching Apple Maps place was found.")
        } catch {
            return .needsHelp("No matching Apple Maps place was found. Try a nearby city or neighborhood.")
        }
    }

    private func candidateResolution(_ candidates: [PlaceCandidate], seed: PlaceImportSeed) -> PlaceImportResolution {
        guard !candidates.isEmpty else {
            return .needsHelp("No matching Apple Maps place was found. Try a nearby city or neighborhood.")
        }
        let match = PlaceImportCandidateMatcher.match(
            candidates,
            nameHint: seed.nameHint,
            areaHint: seed.areaHint,
            latitude: seed.latitude,
            longitude: seed.longitude
        )
        return candidateResolution(match)
    }

    private func candidateResolution(_ match: PlaceImportCandidateMatch) -> PlaceImportResolution {
        if let selectedCandidateID = match.selectedCandidateID {
            return .candidates(match.candidates, selectedCandidateID: selectedCandidateID)
        }
        if match.candidates.count > 1 {
            return .candidates(match.candidates, selectedCandidateID: nil)
        }
        return .needsHelp(
            "The only Apple Maps result was not a confident venue match. Search for the correct place."
        )
    }

    private func googleSeedResolution(_ seed: PlaceImportSeed, name: String) async -> PlaceImportResolution {
        var candidates: [PlaceCandidate] = []

        if let latitude = seed.latitude,
           let longitude = seed.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            if CLLocationCoordinate2DIsValid(coordinate),
               let nearby = try? await placeResolver.resolveNearbyPlaces(near: coordinate) {
                appendUnique(nearby, to: &candidates)
            }
        }

        var match = PlaceImportCandidateMatcher.match(
            candidates,
            nameHint: name,
            areaHint: seed.areaHint,
            latitude: seed.latitude,
            longitude: seed.longitude
        )
        if match.selectedCandidateID == nil,
           let manual = try? await placeResolver.resolveManualEntry(
               ManualPlaceInput(name: name, areaHint: normalized(seed.areaHint), category: nil)
           ) {
            appendUnique(manual, to: &candidates)
            match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: name,
                areaHint: seed.areaHint,
                latitude: seed.latitude,
                longitude: seed.longitude
            )
        }

        let enrichment = match.selectedCandidateID.flatMap { selectedCandidateID in
            match.candidates.first(where: { $0.id == selectedCandidateID })
        }
        let candidate = authoritativeGoogleCandidate(seed: seed, name: name, enrichment: enrichment)
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }

    private func authoritativeGoogleCandidate(
        seed: PlaceImportSeed,
        name: String,
        enrichment: PlaceCandidate?
    ) -> PlaceCandidate {
        let provider = seed.sourceProvider ?? "google_maps"
        let identity = seed.sourceProviderPlaceID ?? seed.id
        return PlaceCandidate(
            id: "import-\(provider)-\(identity)",
            name: name,
            category: enrichment?.category ?? WanderPlaceCategory.fallbackPlace,
            primaryCategory: enrichment?.primaryCategory,
            subcategory: enrichment?.subcategory,
            categorySource: enrichment?.categorySource ?? PlaceCategorySource.unknown.rawValue,
            categoryConfidence: enrichment?.categoryConfidence,
            rawProviderType: enrichment?.rawProviderType,
            address: seed.areaHint ?? enrichment?.address,
            locality: enrichment?.locality,
            region: enrichment?.region,
            country: enrichment?.country,
            latitude: seed.latitude ?? enrichment?.latitude,
            longitude: seed.longitude ?? enrichment?.longitude,
            sourceProvider: provider,
            sourceProviderPlaceID: seed.sourceProviderPlaceID,
            distanceMeters: enrichment?.distanceMeters,
            websiteURLString: enrichment?.websiteURLString,
            phoneNumber: enrichment?.phoneNumber,
            timeZoneIdentifier: enrichment?.timeZoneIdentifier,
            actionLinksJSON: enrichment?.actionLinksJSON,
            confidence: 1
        )
    }

    private func isAuthoritativeGoogleSeed(_ seed: PlaceImportSeed) -> Bool {
        seed.sourceProviderPlaceID != nil || (seed.latitude != nil && seed.longitude != nil)
    }

    private func appendUnique(_ newCandidates: [PlaceCandidate], to candidates: inout [PlaceCandidate]) {
        var identities = Set(candidates.map(candidateIdentity))
        for candidate in newCandidates where identities.insert(candidateIdentity(candidate)).inserted {
            candidates.append(candidate)
        }
    }

    private func socialSeed(
        from original: PlaceImportSeed,
        hint: SocialPlaceSearchHint,
        candidate: PlaceCandidate?
    ) -> PlaceImportSeed {
        PlaceImportSeed(
            rawText: original.rawText,
            nameHint: candidate?.name ?? hint.name,
            areaHint: candidate?.address ?? hint.area,
            sourceURLString: original.sourceURLString,
            sourceLine: original.sourceLine,
            latitude: candidate?.latitude,
            longitude: candidate?.longitude,
            sourceProvider: candidate?.sourceProvider,
            sourceProviderPlaceID: candidate?.sourceProviderPlaceID
        )
    }

    private func candidateIdentity(_ candidate: PlaceCandidate) -> String {
        if let providerPlaceID = candidate.sourceProviderPlaceID {
            return "\(candidate.sourceProvider)|\(providerPlaceID)"
        }
        return candidate.id
    }

    private func hintIdentity(_ hint: SocialPlaceSearchHint) -> String {
        [hint.name, hint.area ?? ""]
            .joined(separator: "|")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber || $0 == "|" }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

}

protocol PlaceImportPersisting {
    func load() throws -> PlaceImportSnapshot
    func save(_ snapshot: PlaceImportSnapshot) throws
}

final class FilePlaceImportPersistence: PlaceImportPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = root
                .appendingPathComponent("rec-me", isDirectory: true)
                .appendingPathComponent("place-imports-v1.json", isDirectory: false)
        }
    }

    func load() throws -> PlaceImportSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PlaceImportSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(PlaceImportSnapshot.self, from: data)
        guard snapshot.version == PlaceImportSnapshot.currentVersion else {
            return PlaceImportSnapshot()
        }
        return snapshot
    }

    func save(_ snapshot: PlaceImportSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}

@MainActor
final class PlaceImportStore: ObservableObject {
    @Published private(set) var batches: [PlaceImportBatch]
    @Published private(set) var items: [PlaceImportItem]
    @Published private(set) var persistenceError: String?

    private let persistence: any PlaceImportPersisting
    private let resolver: any PlaceImportResolving
    private var processingTasks: [String: Task<Void, Never>] = [:]

    init(
        persistence: any PlaceImportPersisting = FilePlaceImportPersistence(),
        resolver: any PlaceImportResolving = DevicePlaceImportResolver()
    ) {
        self.persistence = persistence
        self.resolver = resolver
        do {
            let snapshot = try persistence.load()
            batches = snapshot.batches
            items = snapshot.items.map { item in
                var resumed = item
                if item.state == .resolving {
                    resumed.state = .queued
                }
                if Self.shouldUpgradeResolution(for: item) {
                    resumed.state = .queued
                    resumed.candidates = []
                    resumed.selectedCandidateID = nil
                    resumed.helpMessage = nil
                    resumed.duplicateUserPlaceID = nil
                    resumed.resolverVersion = PlaceImportItem.currentResolverVersion
                }
                return resumed
            }
            persistenceError = nil
        } catch {
            batches = []
            items = []
            persistenceError = "Import history could not be restored. New imports will still work in this session."
        }
        synchronizeAllBatches(persist: false)
    }

    var primaryBatch: PlaceImportBatch? {
        let sorted = batches.sorted { $0.createdAt > $1.createdAt }
        return sorted.first(where: { ![.complete, .cancelled].contains($0.state) }) ?? sorted.first
    }

    var summary: PlaceImportSummary {
        let inboxItems = items.filter { $0.state != .dismissed }
        guard !inboxItems.isEmpty else { return .empty }
        let unresolvedItems = inboxItems.filter {
            [.queued, .resolving, .ready, .ambiguous, .needsHelp, .failed].contains($0.state)
        }
        let processingCount = unresolvedItems.filter { [.queued, .resolving].contains($0.state) }.count
        let readyCount = unresolvedItems.filter { $0.state == .ready }.count
        let needsHelpCount = unresolvedItems.filter { [.ambiguous, .needsHelp, .failed].contains($0.state) }.count
        return PlaceImportSummary(
            batchID: primaryBatch?.id ?? batches.first?.id,
            totalCount: unresolvedItems.count,
            processedCount: unresolvedItems.count - processingCount,
            processingCount: processingCount,
            readyCount: readyCount,
            needsHelpCount: needsHelpCount,
            duplicateCount: inboxItems.filter { $0.state == .duplicate }.count,
            savedCount: inboxItems.filter { $0.state == .saved }.count
        )
    }

    @discardableResult
    func enqueue(source: PlaceImportSource, text: String, sourceName: String? = nil) throws -> String {
        let seeds = try PlaceImportParser.parse(source: source, text: text, fileName: sourceName)
        let batch = PlaceImportBatch(source: source, sourceName: sourceName, totalCount: seeds.count)
        batches.append(batch)
        items.append(contentsOf: seeds.map { seed in
            PlaceImportItem(batchID: batch.id, source: source, seed: seed)
        })
        persist()
        startProcessing(batchID: batch.id)
        return batch.id
    }

    func resumePendingImports() {
        for index in items.indices where items[index].state == .resolving {
            items[index].state = .queued
        }
        for batch in batches where items(for: batch.id).contains(where: { $0.state == .queued }) {
            startProcessing(batchID: batch.id)
        }
    }

    func items(for batchID: String) -> [PlaceImportItem] {
        items.filter { $0.batchID == batchID }.sorted {
            if $0.seed.sourceLine == $1.seed.sourceLine {
                return $0.createdAt < $1.createdAt
            }
            return $0.seed.sourceLine < $1.seed.sourceLine
        }
    }

    func item(id: String) -> PlaceImportItem? {
        items.first(where: { $0.id == id })
    }

    func selectCandidate(itemID: String, candidateID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].candidates.contains(where: { $0.id == candidateID })
        else { return }
        items[index].selectedCandidateID = candidateID
        items[index].state = .ready
        items[index].helpMessage = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func retry(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].state = .queued
        items[index].candidates = []
        items[index].selectedCandidateID = nil
        items[index].helpMessage = nil
        items[index].duplicateUserPlaceID = nil
        items[index].updatedAt = .now
        items[index].resolverVersion = PlaceImportItem.currentResolverVersion
        let batchID = items[index].batchID
        synchronizeBatch(batchID)
        startProcessing(batchID: batchID)
    }

    func retry(itemID: String, name: String, area: String?) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let existingSeed = items[index].seed
        items[index].seed = PlaceImportSeed(
            id: existingSeed.id,
            rawText: existingSeed.rawText,
            nameHint: trimmedName,
            areaHint: area?.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURLString: existingSeed.sourceURLString,
            sourceLine: existingSeed.sourceLine,
            latitude: existingSeed.latitude,
            longitude: existingSeed.longitude,
            sourceProvider: existingSeed.sourceProvider,
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID
        )
        items[index].candidates = []
        items[index].selectedCandidateID = nil
        items[index].state = .queued
        items[index].helpMessage = nil
        items[index].duplicateUserPlaceID = nil
        items[index].updatedAt = .now
        items[index].resolverVersion = PlaceImportItem.currentResolverVersion
        let batchID = items[index].batchID
        synchronizeBatch(batchID)
        startProcessing(batchID: batchID)
    }

    func markSaved(itemID: String, userPlaceID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].state = .saved
        items[index].savedUserPlaceID = userPlaceID
        items[index].duplicateUserPlaceID = nil
        items[index].helpMessage = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func dismiss(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }), items[index].state != .saved else {
            return
        }
        items[index].state = .dismissed
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func cancel(batchID: String) {
        processingTasks[batchID]?.cancel()
        processingTasks[batchID] = nil
        for index in items.indices where items[index].batchID == batchID && [.queued, .resolving].contains(items[index].state) {
            items[index].state = .dismissed
            items[index].updatedAt = .now
        }
        if let index = batches.firstIndex(where: { $0.id == batchID }) {
            batches[index].state = .cancelled
            batches[index].updatedAt = .now
        }
        persist()
    }

    func deleteBatch(batchID: String) {
        processingTasks[batchID]?.cancel()
        processingTasks[batchID] = nil
        items.removeAll(where: { $0.batchID == batchID })
        batches.removeAll(where: { $0.id == batchID })
        persist()
    }

    func clearAll() {
        for task in processingTasks.values {
            task.cancel()
        }
        processingTasks.removeAll()
        items.removeAll()
        batches.removeAll()
        persist()
    }

    func reconcileDuplicates(with existingPlaces: [PlaceImportExistingPlace]) {
        var changedBatchIDs = Set<String>()
        for index in items.indices where [.ready, .ambiguous, .duplicate].contains(items[index].state) {
            let match = items[index].candidates.lazy.compactMap { candidate in
                existingPlaces.first(where: { self.existingPlaceMatches($0, candidate: candidate) })
                    .map { (candidate, $0) }
            }.first

            if let (candidate, existing) = match {
                if items[index].state != .duplicate || items[index].duplicateUserPlaceID != existing.userPlaceID {
                    items[index].state = .duplicate
                    items[index].selectedCandidateID = candidate.id
                    items[index].duplicateUserPlaceID = existing.userPlaceID
                    items[index].helpMessage = nil
                    items[index].updatedAt = .now
                    changedBatchIDs.insert(items[index].batchID)
                }
            } else if items[index].state == .duplicate {
                items[index].duplicateUserPlaceID = nil
                items[index].state = items[index].selectedCandidateID == nil && items[index].candidates.count > 1
                    ? .ambiguous
                    : .ready
                items[index].updatedAt = .now
                changedBatchIDs.insert(items[index].batchID)
            }
        }

        for batchID in changedBatchIDs {
            synchronizeBatch(batchID, persist: false)
        }
        if !changedBatchIDs.isEmpty {
            persist()
        }
    }

    func waitForProcessing(batchID: String) async {
        await processingTasks[batchID]?.value
    }

    private func startProcessing(batchID: String) {
        guard processingTasks[batchID] == nil,
              items.contains(where: { $0.batchID == batchID && $0.state == .queued })
        else { return }

        processingTasks[batchID] = Task { [weak self] in
            await self?.process(batchID: batchID)
        }
    }

    private func process(batchID: String) async {
        while !Task.isCancelled,
              let index = items.firstIndex(where: { $0.batchID == batchID && $0.state == .queued }) {
            items[index].state = .resolving
            items[index].updatedAt = .now
            let itemID = items[index].id
            let seed = items[index].seed
            let source = items[index].source
            synchronizeBatch(batchID)

            do {
                let resolution = try await resolver.resolve(seed: seed, source: source)
                guard !Task.isCancelled,
                      let resolvedIndex = items.firstIndex(where: { $0.id == itemID })
                else { break }
                apply(resolution, at: resolvedIndex)
            } catch {
                guard !Task.isCancelled,
                      let failedIndex = items.firstIndex(where: { $0.id == itemID })
                else { break }
                items[failedIndex].state = .failed
                items[failedIndex].helpMessage = error.localizedDescription
                items[failedIndex].updatedAt = .now
            }
            synchronizeBatch(batchID)
            await Task.yield()
        }
        processingTasks[batchID] = nil
        synchronizeBatch(batchID)
    }

    private func apply(_ resolution: PlaceImportResolution, at index: Int) {
        switch resolution {
        case .candidates(let candidates, let selectedCandidateID):
            items[index].candidates = candidates
            items[index].selectedCandidateID = selectedCandidateID
            if selectedCandidateID != nil {
                items[index].state = .ready
                items[index].helpMessage = nil
            } else if candidates.count > 1 {
                items[index].state = .ambiguous
                items[index].helpMessage = nil
            } else {
                items[index].state = .needsHelp
                items[index].helpMessage =
                    "The only Apple Maps result was not a confident venue match. Search for the correct place."
            }
        case .needsHelp(let message):
            items[index].candidates = []
            items[index].selectedCandidateID = nil
            items[index].state = .needsHelp
            items[index].helpMessage = message
        case .expanded(let seeds, let sourceName):
            let original = items[index]
            let expandedItems = seeds.map { seed in
                PlaceImportItem(
                    batchID: original.batchID,
                    source: original.source,
                    seed: seed,
                    resolverVersion: PlaceImportItem.currentResolverVersion,
                    createdAt: original.createdAt
                )
            }
            items.replaceSubrange(index...index, with: expandedItems)
            if let sourceName,
               let batchIndex = batches.firstIndex(where: { $0.id == original.batchID }) {
                batches[batchIndex].sourceName = sourceName
            }
            return
        case .expandedResolved(let entries, let sourceName):
            let original = items[index]
            let expandedItems = entries.map { entry in
                let state: PlaceImportItemState
                if entry.selectedCandidateID != nil {
                    state = .ready
                } else if entry.candidates.count > 1 {
                    state = .ambiguous
                } else {
                    state = .needsHelp
                }
                return PlaceImportItem(
                    batchID: original.batchID,
                    source: original.source,
                    seed: entry.seed,
                    state: state,
                    candidates: entry.candidates,
                    selectedCandidateID: entry.selectedCandidateID,
                    helpMessage: entry.helpMessage,
                    resolverVersion: PlaceImportItem.currentResolverVersion,
                    createdAt: original.createdAt
                )
            }
            items.replaceSubrange(index...index, with: expandedItems)
            if let sourceName,
               let batchIndex = batches.firstIndex(where: { $0.id == original.batchID }) {
                batches[batchIndex].sourceName = sourceName
            }
            return
        }
        items[index].resolverVersion = PlaceImportItem.currentResolverVersion
        items[index].updatedAt = .now
    }

    private func synchronizeAllBatches(persist: Bool) {
        for batchID in batches.map(\.id) {
            synchronizeBatch(batchID, persist: false)
        }
        if persist {
            self.persist()
        }
    }

    private func synchronizeBatch(_ batchID: String, persist: Bool = true) {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        let batchItems = items(for: batchID)
        let pendingCount = batchItems.filter { [.queued, .resolving].contains($0.state) }.count
        let terminalCount = batchItems.filter { [.saved, .duplicate, .dismissed].contains($0.state) }.count
        batches[index].totalCount = batchItems.count
        batches[index].processedCount = batchItems.count - pendingCount
        batches[index].updatedAt = .now

        if batches[index].state != .cancelled {
            if pendingCount > 0 {
                batches[index].state = .processing
            } else if terminalCount == batchItems.count {
                batches[index].state = .complete
            } else {
                batches[index].state = .ready
            }
        }
        if persist {
            self.persist()
        }
    }

    private func persist() {
        do {
            try persistence.save(PlaceImportSnapshot(batches: batches, items: items))
            persistenceError = nil
        } catch {
            persistenceError = "Import progress could not be saved. Keep rec.me open and try again."
        }
    }

    private func existingPlaceMatches(_ existing: PlaceImportExistingPlace, candidate: PlaceCandidate) -> Bool {
        if let existingProviderID = existing.sourceProviderPlaceID,
           let candidateProviderID = candidate.sourceProviderPlaceID,
           existingProviderID == candidateProviderID,
           existing.sourceProvider == candidate.sourceProvider {
            return true
        }

        let existingName = normalizedName(existing.name)
        let candidateName = normalizedName(candidate.name)
        guard existingName == candidateName else { return false }
        guard let existingLatitude = existing.latitude,
              let existingLongitude = existing.longitude,
              let candidateLatitude = candidate.latitude,
              let candidateLongitude = candidate.longitude
        else {
            return true
        }
        return abs(existingLatitude - candidateLatitude) < 0.001
            && abs(existingLongitude - candidateLongitude) < 0.001
    }

    private func normalizedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func shouldUpgradeResolution(for item: PlaceImportItem) -> Bool {
        guard (item.resolverVersion ?? 0) < PlaceImportItem.currentResolverVersion,
              [.googleMaps, .instagram, .tiktok].contains(item.source),
              [.ready, .ambiguous, .needsHelp, .failed].contains(item.state)
        else { return false }
        return true
    }
}
