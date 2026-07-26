import CoreLocation
import Foundation

actor SocialImportAutomaticLookupPacer {
    static let shared = SocialImportAutomaticLookupPacer()

    private let minimumInterval: Duration
    private let clock = ContinuousClock()
    private var lastGrant: ContinuousClock.Instant?

    init(minimumInterval: Duration = .milliseconds(1_500)) {
        self.minimumInterval = minimumInterval
    }

    func waitForTurn() async throws {
        while true {
            try Task.checkCancellation()
            let now = clock.now
            if let lastGrant {
                let earliestGrant = lastGrant.advanced(by: minimumInterval)
                if now < earliestGrant {
                    try await clock.sleep(until: earliestGrant)
                    // Recheck after every suspension. Multiple callers—or an app
                    // resume after all deadlines elapsed—must not pass together.
                    continue
                }
            }
            // Record only an actual grant. A cancelled waiter never consumes a slot.
            lastGrant = now
            return
        }
    }
}

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
    case partialExpandedResolved([PlaceImportResolvedEntry], sourceName: String?)
}

enum PlaceImportManualSearchOutcome: Equatable {
    case matched
    case needsReview(candidateCount: Int)
    case failed(String)
}

enum PlaceImportCandidateSearchOutcome: Equatable {
    case results([PlaceCandidate])
    case failed(String)
}

@MainActor
protocol PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution
    func resolveManualSearch(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution
}

extension PlaceImportResolving {
    func resolveManualSearch(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await resolve(seed: seed, source: source)
    }
}

@MainActor
final class DevicePlaceImportResolver: PlaceImportResolving {
    private static let maximumExtractedSocialHints = 150
    private static let maximumImmediateSocialLookups = 24

    private struct SocialMediaRecognition {
        let recognizedTexts: [String]
        let attemptedCount: Int
        let emptyOrFailedCount: Int
    }

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
            if [.instagram, .tiktok].contains(source), seed.sourceURLString != nil {
                try await SocialImportAutomaticLookupPacer.shared.waitForTurn()
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
            return try await socialResolution(url: sourceURL, source: source, seed: seed)
        case .textNotes:
            do {
                let candidates = try await placeResolver.resolveLink(
                    LinkPlaceInput(rawValue: sourceURLString)
                )
                return candidateResolution(candidates, seed: seed)
            } catch {
                return .needsHelp(
                    "This link did not expose a place. Add a place name and nearby city to match it."
                )
            }
        }
    }

    func resolveManualSearch(
        seed: PlaceImportSeed,
        source _: PlaceImportSource
    ) async throws -> PlaceImportResolution {
        guard let name = normalized(seed.nameHint) else {
            return .needsHelp("Enter a place name before searching.")
        }
        return try await manualResolution(
            name: name,
            area: seed.areaHint,
            latitude: seed.latitude,
            longitude: seed.longitude,
            preserveUnselectedCandidates: true
        )
    }

    private func socialResolution(
        url: URL,
        source: PlaceImportSource,
        seed: PlaceImportSeed
    ) async throws -> PlaceImportResolution {
        let fetchedMetadata = await metadataProvider.metadata(for: url, source: source)
        try Task.checkCancellation()
        guard let metadata = fetchedMetadata else {
            return .needsHelp(
                "This public post did not expose a caption or cover image. Check the link and retry automatic matching."
            )
        }
        let recognition = try await recognizeSocialMedia(in: metadata)
        let hints = SocialPlaceHintExtractor.hints(
            from: metadata,
            recognizedTexts: recognition.recognizedTexts,
            limit: Self.maximumExtractedSocialHints
        )

        let durableHints = hints.filter(\.evidence.shouldRemainVisibleWithoutCandidates)
        if durableHints.count > Self.maximumImmediateSocialLookups {
            let expandedSeeds = durableHints.map { hint in
                socialSeed(
                    from: seed,
                    hint: hint,
                    candidate: nil,
                    // Keep the expanded rows at their source link's line. The
                    // store's stable array order keeps the guide contiguous and
                    // avoids collisions with subsequent pasted links.
                    sourceLine: seed.sourceLine
                )
            }
            let discoveredMediaCount = metadata.mediaItems.isEmpty
                ? (metadata.thumbnailURL == nil ? 0 : 1)
                : metadata.mediaItems.count
            WanderDebugLog.imports.notice(
                "social guide expansion source=\(source.rawValue, privacy: .public) discovered_media_count=\(discoveredMediaCount, privacy: .public) ocr_attempt_count=\(recognition.attemptedCount, privacy: .public) ocr_empty_or_failed_count=\(recognition.emptyOrFailedCount, privacy: .public) extracted_hint_count=\(hints.count, privacy: .public) durable_row_count=\(expandedSeeds.count, privacy: .public) deferred_lookup_count=\(expandedSeeds.count, privacy: .public)"
            )
            return .expanded(expandedSeeds, sourceName: nil)
        }

        var entries: [PlaceImportResolvedEntry] = []
        var seenResolvedCandidates = Set<String>()
        var seenPlausibleHints = Set<String>()
        var strongest: PlaceImportCandidateMatch?
        var resolvedCount = 0
        var unresolvedCount = 0
        var noCandidateCount = 0
        var lowConfidenceCount = 0
        var rejectedHintCount = 0
        var lookupFailureCount = 0
        for hint in hints {
            try Task.checkCancellation()
            let fetchedCandidates: [PlaceCandidate]
            do {
                fetchedCandidates = try await placeResolver.resolveManualEntry(
                    ManualPlaceInput(name: hint.name, areaHint: hint.area, category: nil)
                )
            } catch PlaceResolutionError.noCandidates {
                fetchedCandidates = []
            } catch {
                try Task.checkCancellation()
                lookupFailureCount += 1
                if !appendUnresolvedSocialHint(
                    hint,
                    originalSeed: seed,
                    to: &entries,
                    seenHints: &seenPlausibleHints,
                    helpMessage: "This place was named in the post, but Apple Maps was temporarily unavailable. Retry this item later."
                ) {
                    rejectedHintCount += 1
                } else {
                    unresolvedCount += 1
                }
                continue
            }
            try Task.checkCancellation()
            let candidates = SocialImportCountry.candidatesCompatibleWithExactCountry(
                fetchedCandidates,
                areaHint: hint.area
            )
            guard !candidates.isEmpty else {
                noCandidateCount += 1
                if !appendUnresolvedSocialHint(
                    hint,
                    originalSeed: seed,
                    to: &entries,
                    seenHints: &seenPlausibleHints
                ) {
                    rejectedHintCount += 1
                } else {
                    unresolvedCount += 1
                }
                continue
            }
            let match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: hint.name,
                areaHint: hint.area,
                allowNearSpellingMatch: hint.evidence == .imageText
            )
            if let selectedCandidateID = match.selectedCandidateID,
               let providerCandidate = match.candidates.first(where: { $0.id == selectedCandidateID }) {
                let selectedCandidate = socialCandidate(
                    from: providerCandidate,
                    preservingCreatorNameFrom: hint
                )
                let resolvedCandidates = match.candidates.map { candidate in
                    candidate.id == selectedCandidateID ? selectedCandidate : candidate
                }
                let identity = candidateIdentity(selectedCandidate)
                if seenResolvedCandidates.insert(identity).inserted {
                    entries.append(
                        PlaceImportResolvedEntry(
                            seed: socialSeed(from: seed, hint: hint, candidate: selectedCandidate),
                            candidates: resolvedCandidates,
                            selectedCandidateID: selectedCandidateID,
                            helpMessage: nil
                        )
                    )
                    resolvedCount += 1
                } else {
                    rejectedHintCount += 1
                }
                continue
            }
            if match.candidates.count > 1, match.bestScore >= 0.7 {
                let identity = hintIdentity(hint)
                if seenPlausibleHints.insert(identity).inserted {
                    entries.append(
                        PlaceImportResolvedEntry(
                            seed: socialSeed(from: seed, hint: hint, candidate: nil),
                            candidates: match.candidates,
                            selectedCandidateID: nil,
                            helpMessage: "Choose the matching venue from this post."
                        )
                    )
                    unresolvedCount += 1
                }
            } else {
                lowConfidenceCount += 1
                if !appendUnresolvedSocialHint(
                    hint,
                    originalSeed: seed,
                    to: &entries,
                    seenHints: &seenPlausibleHints
                ) {
                    rejectedHintCount += 1
                } else {
                    unresolvedCount += 1
                }
            }
            if match.bestScore > (strongest?.bestScore ?? 0) {
                strongest = match
            }
        }

        let discoveredMediaCount = metadata.mediaItems.isEmpty
            ? (metadata.thumbnailURL == nil ? 0 : 1)
            : metadata.mediaItems.count
        WanderDebugLog.imports.notice(
            "social import resolution source=\(source.rawValue, privacy: .public) discovered_media_count=\(discoveredMediaCount, privacy: .public) ocr_attempt_count=\(recognition.attemptedCount, privacy: .public) ocr_empty_or_failed_count=\(recognition.emptyOrFailedCount, privacy: .public) extracted_hint_count=\(hints.count, privacy: .public) resolved_count=\(resolvedCount, privacy: .public) unresolved_count=\(unresolvedCount, privacy: .public) no_candidate_count=\(noCandidateCount, privacy: .public) low_confidence_count=\(lowConfidenceCount, privacy: .public) lookup_failure_count=\(lookupFailureCount, privacy: .public) rejected_hint_count=\(rejectedHintCount, privacy: .public)"
        )
        if lookupFailureCount > 0 {
            if !entries.isEmpty {
                return .partialExpandedResolved(entries, sourceName: nil)
            }
            return .needsHelp(
                "Apple Maps matching was temporarily unavailable. Retry later."
            )
        }
        if entries.count == 1, let entry = entries.first {
            if entry.selectedCandidateID != nil {
                return .candidates(entry.candidates, selectedCandidateID: entry.selectedCandidateID)
            }
            return .expandedResolved(entries, sourceName: nil)
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

    private func recognizeSocialMedia(in metadata: SocialImportMetadata) async throws -> SocialMediaRecognition {
        var seenURLs = Set<String>()
        var urls = metadata.mediaItems.compactMap(\.imageURL).filter {
            seenURLs.insert($0.absoluteString).inserted
        }
        if urls.isEmpty, let thumbnailURL = metadata.thumbnailURL {
            urls = [thumbnailURL]
        }
        guard !urls.isEmpty else {
            return SocialMediaRecognition(recognizedTexts: [], attemptedCount: 0, emptyOrFailedCount: 0)
        }

        var recognized = Array<String?>(repeating: nil, count: urls.count)
        let maximumConcurrentRecognitions = 4
        for chunkStart in stride(from: 0, to: urls.count, by: maximumConcurrentRecognitions) {
            let chunkEnd = min(chunkStart + maximumConcurrentRecognitions, urls.count)
            try await withThrowingTaskGroup(of: (Int, String?).self) { group in
                for index in chunkStart..<chunkEnd {
                    let url = urls[index]
                    group.addTask { [thumbnailRecognizer] in
                        try Task.checkCancellation()
                        let text = await thumbnailRecognizer.recognizedText(at: url)
                        try Task.checkCancellation()
                        return (index, text)
                    }
                }
                for try await (index, text) in group {
                    recognized[index] = text
                }
            }
        }

        let recognizedTexts = recognized.compactMap { normalized($0) }
        return SocialMediaRecognition(
            recognizedTexts: recognizedTexts,
            attemptedCount: urls.count,
            emptyOrFailedCount: recognized.filter { normalized($0) == nil }.count
        )
    }

    @discardableResult
    private func appendUnresolvedSocialHint(
        _ hint: SocialPlaceSearchHint,
        originalSeed: PlaceImportSeed,
        to entries: inout [PlaceImportResolvedEntry],
        seenHints: inout Set<String>,
        helpMessage: String = "This place was named in the post, but Apple Maps needs your help matching it."
    ) -> Bool {
        guard hint.evidence.shouldRemainVisibleWithoutCandidates else { return false }
        let identity = hintIdentity(hint)
        guard seenHints.insert(identity).inserted else { return false }
        entries.append(
            PlaceImportResolvedEntry(
                seed: socialSeed(from: originalSeed, hint: hint, candidate: nil),
                candidates: [],
                selectedCandidateID: nil,
                helpMessage: helpMessage
            )
        )
        return true
    }

    private func manualResolution(
        name: String,
        area: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        preserveUnselectedCandidates: Bool = false
    ) async throws -> PlaceImportResolution {
        do {
            let candidates = SocialImportCountry.candidatesCompatibleWithExactCountry(
                try await placeResolver.resolveManualEntry(
                    ManualPlaceInput(name: name, areaHint: normalized(area), category: nil)
                ),
                areaHint: area
            )
            let match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: name,
                areaHint: area,
                latitude: latitude,
                longitude: longitude
            )
            if preserveUnselectedCandidates, !match.candidates.isEmpty {
                // A typed search is an explicit user request. Keep even one weak
                // MapKit result available for review instead of silently dropping it.
                return .candidates(
                    match.candidates,
                    selectedCandidateID: match.selectedCandidateID
                )
            }
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
        guard !match.candidates.isEmpty else {
            return .needsHelp("No matching Apple Maps place was found. Try a nearby city or neighborhood.")
        }
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
        candidate: PlaceCandidate?,
        sourceLine: Int? = nil
    ) -> PlaceImportSeed {
        PlaceImportSeed(
            rawText: original.rawText,
            nameHint: hint.name,
            areaHint: candidate?.address ?? hint.area,
            sourceURLString: original.sourceURLString,
            sourceLine: sourceLine ?? original.sourceLine,
            latitude: candidate?.latitude,
            longitude: candidate?.longitude,
            sourceProvider: candidate?.sourceProvider,
            sourceProviderPlaceID: candidate?.sourceProviderPlaceID
        )
    }

    private func socialCandidate(
        from candidate: PlaceCandidate,
        preservingCreatorNameFrom hint: SocialPlaceSearchHint
    ) -> PlaceCandidate {
        guard hint.evidence.preservesCreatorNameWhenMatched,
              PlaceImportCandidateMatcher.namesAreEquivalent(candidate.name, hint.name)
        else { return candidate }

        return PlaceCandidate(
            id: candidate.id,
            name: hint.name,
            category: candidate.category,
            primaryCategory: candidate.primaryCategory,
            subcategory: candidate.subcategory,
            categorySource: candidate.categorySource,
            categoryConfidence: candidate.categoryConfidence,
            rawProviderType: candidate.rawProviderType,
            address: candidate.address,
            locality: candidate.locality,
            region: candidate.region,
            country: candidate.country,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            sourceProvider: candidate.sourceProvider,
            sourceProviderPlaceID: candidate.sourceProviderPlaceID,
            distanceMeters: candidate.distanceMeters,
            websiteURLString: candidate.websiteURLString,
            phoneNumber: candidate.phoneNumber,
            timeZoneIdentifier: candidate.timeZoneIdentifier,
            actionLinksJSON: candidate.actionLinksJSON,
            confidence: candidate.confidence
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
    private struct LoadedItemUpgrade {
        let items: [PlaceImportItem]
        let replacedSocialItemsByPlaceholderID: [String: [PlaceImportItem]]
    }

    @Published private(set) var batches: [PlaceImportBatch]
    @Published private(set) var items: [PlaceImportItem]
    @Published private(set) var persistenceError: String?

    private let persistence: any PlaceImportPersisting
    private let resolver: any PlaceImportResolving
    private var processingTasks: [String: Task<Void, Never>] = [:]
    private var replacedSocialItemsByPlaceholderID: [String: [PlaceImportItem]]

    init(
        persistence: any PlaceImportPersisting = FilePlaceImportPersistence(),
        resolver: any PlaceImportResolving = DevicePlaceImportResolver()
    ) {
        self.persistence = persistence
        self.resolver = resolver
        do {
            let snapshot = try persistence.load()
            let upgrade = Self.upgradedLoadedItems(snapshot.items)
            batches = snapshot.batches
            items = upgrade.items
            replacedSocialItemsByPlaceholderID = upgrade.replacedSocialItemsByPlaceholderID
            persistenceError = nil
        } catch {
            batches = []
            items = []
            replacedSocialItemsByPlaceholderID = [:]
            persistenceError = "Import history could not be restored. New imports will still work in this session."
        }
        synchronizeAllBatches(persist: false)
    }

    private static func upgradedLoadedItems(_ loadedItems: [PlaceImportItem]) -> LoadedItemUpgrade {
        var seenSocialSources = Set<String>()
        let socialItemsBySource = Dictionary(grouping: loadedItems.filter { item in
            shouldUpgradeResolution(for: item)
                && [.instagram, .tiktok].contains(item.source)
                && item.seed.sourceURLString != nil
        }) { item in
            "\(item.batchID)|\(item.seed.sourceURLString ?? "")"
        }
        var replacedSocialItemsByPlaceholderID: [String: [PlaceImportItem]] = [:]

        let upgradedItems = loadedItems.compactMap { item -> PlaceImportItem? in
            guard shouldUpgradeResolution(for: item) else {
                var resumed = item
                if item.state == .resolving {
                    resumed.state = .queued
                }
                return resumed
            }

            var upgraded = item
            if [.instagram, .tiktok].contains(item.source),
               let sourceURLString = item.seed.sourceURLString {
                let sourceKey = "\(item.batchID)|\(sourceURLString)"
                guard seenSocialSources.insert(sourceKey).inserted else { return nil }
                replacedSocialItemsByPlaceholderID[item.id] = socialItemsBySource[sourceKey] ?? [item]
                upgraded.seed = PlaceImportSeed(
                    id: item.seed.id,
                    rawText: sourceURLString,
                    nameHint: nil,
                    areaHint: nil,
                    sourceURLString: sourceURLString,
                    sourceLine: item.seed.sourceLine
                )
            }

            upgraded.state = .queued
            upgraded.candidates = []
            upgraded.selectedCandidateID = nil
            upgraded.helpMessage = nil
            upgraded.duplicateUserPlaceID = nil
            upgraded.resolverVersion = PlaceImportItem.currentResolverVersion
            upgraded.pendingManualSearch = nil
            return upgraded
        }
        return LoadedItemUpgrade(
            items: upgradedItems,
            replacedSocialItemsByPlaceholderID: replacedSocialItemsByPlaceholderID
        )
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
    func enqueue(
        source: PlaceImportSource,
        text: String,
        sourceName: String? = nil,
        captureDeliveryID: String? = nil
    ) throws -> String {
        if let captureDeliveryID,
           let existingBatch = batches.first(where: { $0.captureDeliveryID == captureDeliveryID }) {
            return existingBatch.id
        }
        let seeds = try PlaceImportParser.parse(source: source, text: text, fileName: sourceName)
        let batch = PlaceImportBatch(
            source: source,
            sourceName: sourceName,
            captureDeliveryID: captureDeliveryID,
            totalCount: seeds.count
        )
        batches.append(batch)
        items.append(contentsOf: seeds.map { seed in
            PlaceImportItem(batchID: batch.id, source: source, seed: seed)
        })
        persist()
        startProcessing(batchID: batch.id)
        return batch.id
    }

    func batch(captureDeliveryID: String) -> PlaceImportBatch? {
        batches.first(where: { $0.captureDeliveryID == captureDeliveryID })
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
        items.enumerated()
            .filter { $0.element.batchID == batchID }
            .sorted {
                if $0.element.seed.sourceLine == $1.element.seed.sourceLine {
                    return $0.offset < $1.offset
                }
                return $0.element.seed.sourceLine < $1.element.seed.sourceLine
            }
            .map(\.element)
    }

    func item(id: String) -> PlaceImportItem? {
        items.first(where: { $0.id == id })
    }

    func selectCandidate(itemID: String, candidateID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].candidates.contains(where: { $0.id == candidateID })
        else { return }
        items[index].pendingManualSearch = nil
        items[index].selectedCandidateID = candidateID
        items[index].state = .ready
        items[index].helpMessage = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func retry(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].pendingManualSearch = nil
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
        _ = queueManualSearch(itemID: itemID, name: name, area: area)
    }

    func search(itemID: String, name: String, area: String?) async -> PlaceImportManualSearchOutcome {
        guard queueManualSearch(itemID: itemID, name: name, area: area) != nil else {
            return .failed("Enter a place name before searching.")
        }
        await waitForResolution(itemID: itemID)
        guard let item = item(id: itemID) else {
            return .failed("This import is no longer available.")
        }
        switch item.state {
        case .ready:
            return .matched
        case .ambiguous:
            return .needsReview(candidateCount: item.candidates.count)
        case .needsHelp, .failed:
            return .failed(
                item.helpMessage
                    ?? "No matching Apple Maps place was found. Try a nearby city or neighborhood."
            )
        case .queued, .resolving:
            return .failed("Apple Maps is still searching. Try again in a moment.")
        case .duplicate, .saved, .dismissed:
            return .failed("This import is no longer waiting for a place match.")
        }
    }

    func previewManualSearch(
        itemID: String,
        name: String,
        area: String?
    ) async -> PlaceImportCandidateSearchOutcome {
        guard let item = item(id: itemID) else {
            return .failed("This import is no longer available.")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failed("Enter a place name before searching.")
        }
        let normalizedArea = area?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArea = normalizedArea.flatMap { $0.isEmpty ? nil : $0 }
        let existingSeed = item.seed
        let searchSeed = PlaceImportSeed(
            id: existingSeed.id,
            rawText: existingSeed.rawText,
            nameHint: trimmedName,
            areaHint: trimmedArea,
            sourceURLString: existingSeed.sourceURLString,
            sourceLine: existingSeed.sourceLine,
            latitude: existingSeed.latitude,
            longitude: existingSeed.longitude,
            sourceProvider: existingSeed.sourceProvider,
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID
        )

        do {
            let resolution = try await resolver.resolveManualSearch(
                seed: searchSeed,
                source: item.source
            )
            guard self.item(id: itemID) != nil else {
                return .failed("This import is no longer available.")
            }
            switch resolution {
            case .candidates(let candidates, selectedCandidateID: _):
                guard !candidates.isEmpty else {
                    return .failed("No matching Apple Maps place was found. Try a more specific search.")
                }
                return .results(candidates)
            case .needsHelp(let message):
                return .failed(message)
            case .expanded, .expandedResolved, .partialExpandedResolved:
                return .failed("No matching Apple Maps place was found. Try a more specific search.")
            }
        } catch let error as LocalizedError {
            return .failed(error.errorDescription ?? "Apple Maps search is temporarily unavailable.")
        } catch {
            return .failed("Apple Maps search is temporarily unavailable.")
        }
    }

    func confirmManualSearch(
        itemID: String,
        name: String,
        area: String?,
        candidates: [PlaceCandidate],
        selectedCandidateID: String
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              ![.duplicate, .saved, .dismissed].contains(items[index].state),
              !candidates.isEmpty,
              candidates.contains(where: { $0.id == selectedCandidateID })
        else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let existingSeed = items[index].seed
        items[index].seed = PlaceImportSeed(
            id: existingSeed.id,
            rawText: existingSeed.rawText,
            nameHint: trimmedName,
            areaHint: {
                let value = area?.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.flatMap { $0.isEmpty ? nil : $0 }
            }(),
            sourceURLString: existingSeed.sourceURLString,
            sourceLine: existingSeed.sourceLine,
            latitude: existingSeed.latitude,
            longitude: existingSeed.longitude,
            sourceProvider: existingSeed.sourceProvider,
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID
        )
        items[index].pendingManualSearch = nil
        items[index].candidates = candidates
        items[index].selectedCandidateID = selectedCandidateID
        items[index].state = .ready
        items[index].helpMessage = nil
        items[index].duplicateUserPlaceID = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    @discardableResult
    private func queueManualSearch(itemID: String, name: String, area: String?) -> String? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
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
        items[index].pendingManualSearch = true
        let batchID = items[index].batchID
        synchronizeBatch(batchID)
        startProcessing(batchID: batchID)
        return batchID
    }

    func markSaved(itemID: String, userPlaceID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].pendingManualSearch = nil
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
        items[index].pendingManualSearch = nil
        items[index].state = .dismissed
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func cancel(batchID: String) {
        processingTasks[batchID]?.cancel()
        processingTasks[batchID] = nil
        let upgradePlaceholderIDs = replacedSocialItemsByPlaceholderID.compactMap { placeholderID, oldItems in
            oldItems.first?.batchID == batchID ? placeholderID : nil
        }
        for placeholderID in upgradePlaceholderIDs {
            guard let index = items.firstIndex(where: { $0.id == placeholderID }) else { continue }
            restoreReplacedSocialItems(placeholderID: placeholderID, at: index)
        }
        for index in items.indices where items[index].batchID == batchID && [.queued, .resolving].contains(items[index].state) {
            items[index].state = .dismissed
            items[index].pendingManualSearch = nil
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
        replacedSocialItemsByPlaceholderID = replacedSocialItemsByPlaceholderID.filter {
            $0.value.first?.batchID != batchID
        }
        items.removeAll(where: { $0.batchID == batchID })
        batches.removeAll(where: { $0.id == batchID })
        persist()
    }

    func clearAll() {
        for task in processingTasks.values {
            task.cancel()
        }
        processingTasks.removeAll()
        replacedSocialItemsByPlaceholderID.removeAll()
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

    private func waitForResolution(itemID: String) async {
        while !Task.isCancelled,
              let item = item(id: itemID),
              [.queued, .resolving].contains(item.state) {
            try? await Task.sleep(for: .milliseconds(20))
        }
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
              let index = nextQueuedItemIndex(batchID: batchID) {
            items[index].state = .resolving
            items[index].updatedAt = .now
            let itemID = items[index].id
            let seed = items[index].seed
            let source = items[index].source
            let isManualSearch = items[index].pendingManualSearch == true
            let isSocialUpgrade = replacedSocialItemsByPlaceholderID[itemID] != nil
            // Keep the pre-upgrade snapshot durable until its network-dependent refresh succeeds.
            synchronizeBatch(batchID, persist: !isSocialUpgrade)

            do {
                let resolution = if isManualSearch {
                    try await resolver.resolveManualSearch(seed: seed, source: source)
                } else {
                    try await resolver.resolve(seed: seed, source: source)
                }
                guard !Task.isCancelled,
                      let resolvedIndex = items.firstIndex(where: { $0.id == itemID })
                else { break }
                guard items[resolvedIndex].state == .resolving,
                      items[resolvedIndex].seed == seed
                else {
                    // A newer search, retry, or dismissal superseded this request.
                    await Task.yield()
                    continue
                }
                let shouldRestorePreviousRows: Bool
                switch resolution {
                case .needsHelp, .partialExpandedResolved:
                    shouldRestorePreviousRows = true
                case .candidates, .expanded, .expandedResolved:
                    shouldRestorePreviousRows = false
                }
                if shouldRestorePreviousRows,
                   restoreReplacedSocialItems(placeholderID: itemID, at: resolvedIndex) {
                    // A transient metadata failure must not erase previously useful rows.
                } else {
                    replacedSocialItemsByPlaceholderID[itemID] = nil
                    items[resolvedIndex].pendingManualSearch = nil
                    apply(resolution, at: resolvedIndex)
                }
            } catch {
                guard !Task.isCancelled,
                      let failedIndex = items.firstIndex(where: { $0.id == itemID })
                else { break }
                guard items[failedIndex].state == .resolving,
                      items[failedIndex].seed == seed
                else {
                    // Do not let an older failure overwrite newer user intent.
                    await Task.yield()
                    continue
                }
                if !restoreReplacedSocialItems(placeholderID: itemID, at: failedIndex) {
                    items[failedIndex].state = .failed
                    items[failedIndex].pendingManualSearch = nil
                    items[failedIndex].helpMessage = error.localizedDescription
                    items[failedIndex].updatedAt = .now
                }
            }
            synchronizeBatch(batchID)
            await Task.yield()
        }
        processingTasks[batchID] = nil
        synchronizeBatch(batchID)
    }

    private func nextQueuedItemIndex(batchID: String) -> Int? {
        items.firstIndex(where: {
            $0.batchID == batchID && $0.state == .queued && $0.pendingManualSearch == true
        }) ?? items.firstIndex(where: {
            $0.batchID == batchID && $0.state == .queued
        })
    }

    @discardableResult
    private func restoreReplacedSocialItems(placeholderID: String, at index: Int) -> Bool {
        guard let replacedItems = replacedSocialItemsByPlaceholderID.removeValue(forKey: placeholderID) else {
            return false
        }
        items.replaceSubrange(index...index, with: replacedItems)
        return true
    }

    private func apply(_ resolution: PlaceImportResolution, at index: Int) {
        switch resolution {
        case .candidates(let candidates, let selectedCandidateID):
            items[index].candidates = candidates
            items[index].selectedCandidateID = selectedCandidateID
            if selectedCandidateID != nil {
                items[index].state = .ready
                items[index].helpMessage = nil
            } else if !candidates.isEmpty {
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
        case .expandedResolved(let entries, let sourceName),
             .partialExpandedResolved(let entries, let sourceName):
            let original = items[index]
            let expandedItems = entries.map { entry in
                let state: PlaceImportItemState
                if entry.selectedCandidateID != nil {
                    state = .ready
                } else if !entry.candidates.isEmpty {
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
            // A resolver upgrade is intentionally staged in memory. Persist each group's
            // previous rows until its network-dependent refresh commits so an unrelated
            // save or app termination cannot make a temporary placeholder durable.
            let durableItems = items.flatMap { item in
                replacedSocialItemsByPlaceholderID[item.id] ?? [item]
            }
            try persistence.save(PlaceImportSnapshot(batches: batches, items: durableItems))
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
        let requiredVersion = item.source == .googleMaps ? 4 : PlaceImportItem.currentResolverVersion
        guard (item.resolverVersion ?? 0) < requiredVersion,
              [.googleMaps, .instagram, .tiktok].contains(item.source),
              [.ready, .ambiguous, .needsHelp, .failed].contains(item.state)
        else { return false }
        return true
    }
}
