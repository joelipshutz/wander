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

struct PlaceImportResolvedEntry: Equatable, Sendable {
    let kind: PlaceImportItemKind
    let seed: PlaceImportSeed
    let candidates: [PlaceCandidate]
    let selectedCandidateID: String?
    let helpMessage: String?

    init(
        kind: PlaceImportItemKind = .place,
        seed: PlaceImportSeed,
        candidates: [PlaceCandidate],
        selectedCandidateID: String?,
        helpMessage: String?
    ) {
        self.kind = kind
        self.seed = seed
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
        self.helpMessage = helpMessage
    }
}

enum PlaceImportResolution: Equatable, Sendable {
    case candidates([PlaceCandidate], selectedCandidateID: String?)
    case needsHelp(String)
    case retrySocialUnderstanding(requestID: String)
    case expanded([PlaceImportSeed], sourceName: String?)
    case partialExpanded([PlaceImportSeed], retrySeed: PlaceImportSeed, sourceName: String?)
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
    func resolve(
        seed: PlaceImportSeed, source: PlaceImportSource,
        onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void
    ) async throws -> PlaceImportResolution
    func resolveManualSearch(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution
}

extension PlaceImportResolving {
    func resolve(
        seed: PlaceImportSeed, source: PlaceImportSource,
        onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void
    ) async throws -> PlaceImportResolution {
        try await resolve(seed: seed, source: source)
    }

    func resolveManualSearch(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await resolve(seed: seed, source: source)
    }
}

@MainActor
final class DevicePlaceImportResolver: PlaceImportResolving {
    private static let maximumExtractedSocialHints = 150
    private static let maximumImmediateSocialLookups = 24
    private static let maximumSocialLookupAttempts = 3

    private struct SocialMediaRecognition {
        let recognizedTexts: [String]
        let attemptedCount: Int
        let emptyOrFailedCount: Int
    }

    private struct SocialRecoveryHint {
        let hint: SocialPlaceSearchHint
        let helpMessage: String
    }

    private let placeResolver: any PlaceCandidateResolving
    private let metadataProvider: any SocialImportMetadataProviding
    private let googleListLoader: any GoogleMapsSharedListLoading
    private let thumbnailRecognizer: any SocialThumbnailTextRecognizing
    private let socialUnderstandingRepository: (any SocialImportUnderstandingRepository)?

    init(
        placeResolver: any PlaceCandidateResolving = MapKitPlaceResolver(),
        metadataProvider: any SocialImportMetadataProviding = PublicSocialImportMetadataProvider(),
        googleListLoader: any GoogleMapsSharedListLoading = GoogleMapsSharedListImporter(),
        thumbnailRecognizer: any SocialThumbnailTextRecognizing = VisionSocialThumbnailTextRecognizer(),
        socialUnderstandingRepository: (any SocialImportUnderstandingRepository)? = nil
    ) {
        self.placeResolver = placeResolver
        self.metadataProvider = metadataProvider
        self.googleListLoader = googleListLoader
        self.thumbnailRecognizer = thumbnailRecognizer
        self.socialUnderstandingRepository = socialUnderstandingRepository
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await resolve(seed: seed, source: source, onProgress: { _ in })
    }

    func resolve(
        seed: PlaceImportSeed, source: PlaceImportSource,
        onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void
    ) async throws -> PlaceImportResolution {
        if let name = normalized(seed.nameHint) {
            if source == .googleMaps, isAuthoritativeGoogleSeed(seed) {
                return await googleSeedResolution(seed, name: name)
            }
            return try await manualResolution(
                name: name,
                area: seed.areaHint,
                latitude: seed.latitude,
                longitude: seed.longitude,
                retriesTransientSocialFailures: [.instagram, .tiktok].contains(source)
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
            return try await socialResolution(
                url: sourceURL, source: source, seed: seed, onProgress: onProgress
            )
        case .snapchat, .textNotes:
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
        seed: PlaceImportSeed,
        onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void
    ) async throws -> PlaceImportResolution {
        var sourceSeed = seed
        var recognition = SocialMediaRecognition(
            recognizedTexts: [],
            attemptedCount: 0,
            emptyOrFailedCount: 0
        )
        var discoveredMediaCount = 0
        var understandingPath = "local_fallback"
        var understandingWasPartial = false
        var remoteHintsWereAccepted = false
        var shouldUseLocalEvidence = socialUnderstandingRepository == nil
        var hints: [SocialPlaceSearchHint] = []
        let sourceRetryOnly: PlaceImportResolution = .partialExpandedResolved(
            [
                PlaceImportResolvedEntry(
                    kind: .sourceRetry,
                    seed: seed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Automatic matching is temporarily unavailable. Retry the source scan."
                )
            ],
            sourceName: nil
        )

        if let socialUnderstandingRepository {
            do {
                let remote = try await socialUnderstandingRepository.understand(
                    url: url,
                    source: source,
                    clientRequestID: seed.effectiveSocialUnderstandingRequestID
                )
                try Task.checkCancellation()
                if remote.outcome == .fallback,
                   remote.diagnostics.failureCategory == "retry_required" {
                    // Persist the replacement ID in the store before any paid
                    // replay starts. If the app is interrupted again, relaunch
                    // resumes that exact attempt rather than paying repeatedly.
                    return .retrySocialUnderstanding(
                        requestID: UUID().uuidString.lowercased()
                    )
                }
                understandingPath = remote.diagnostics.providerPath
                discoveredMediaCount = remote.diagnostics.mediaCount
                let hasHostedFailure = remote.diagnostics.failureCategory != nil
                    && remote.diagnostics.failureCategory != "feature_disabled"
                switch remote.outcome {
                case .ok, .partial:
                    let eligibleHints = (remote.outcome == .partial || hasHostedFailure)
                        ? remote.hints.filter(\.isServerGrounded)
                        : remote.hints
                    hints = SocialImportEvidencePlanner.reviewHints(eligibleHints)
                    remoteHintsWereAccepted = !hints.isEmpty
                    understandingWasPartial = (remote.outcome == .partial || hasHostedFailure)
                        && !remote.diagnostics.declaredCountComplete
                    if hints.isEmpty {
                        // A hosted response that claims success or partial
                        // coverage without any grounded evidence cannot safely
                        // authorize local caption/cover guesses.
                        return sourceRetryOnly
                    }
                case .noPlaces:
                    if hasHostedFailure {
                        hints = SocialImportEvidencePlanner.reviewHints(
                            remote.hints.filter(\.isServerGrounded)
                        )
                        remoteHintsWereAccepted = !hints.isEmpty
                        understandingWasPartial = true
                        if hints.isEmpty {
                            return sourceRetryOnly
                        }
                        break
                    }
                    WanderDebugLog.imports.notice(
                        "social import understanding source=\(source.rawValue, privacy: .public) path=\(understandingPath, privacy: .public) outcome=no_places discovered_media_count=\(discoveredMediaCount, privacy: .public)"
                    )
                    return .needsHelp(
                        "No destination was explicitly identified in this post. Add a place name and nearby city to match it."
                    )
                case .fallback:
                    if remote.diagnostics.failureCategory == "feature_disabled" {
                        // A deliberate server kill-switch preserves the
                        // established local-only caption and Vision behavior.
                        shouldUseLocalEvidence = true
                        break
                    }
                    // Once the hosted path was admitted, only evidence returned
                    // by that scan may create place rows. Preserve grounded
                    // partial evidence, but never replace an empty/failed scan
                    // with ungrounded local guesses.
                    hints = SocialImportEvidencePlanner.reviewHints(
                        remote.hints.filter(\.isServerGrounded)
                    )
                    remoteHintsWereAccepted = !hints.isEmpty
                    understandingWasPartial = true
                    if hints.isEmpty {
                        return sourceRetryOnly
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Timeouts, transport errors, decode failures, and hosted 5xxs
                // are retryable source failures. Local caption/cover guesses
                // would look like real provider results and recreate the exact
                // misleading partial-import failure this path is meant to avoid.
                return sourceRetryOnly
            }
        }

        if shouldUseLocalEvidence {
            let fetchedMetadata = await metadataProvider.metadata(for: url, source: source)
            try Task.checkCancellation()
            let metadata = socialMetadata(
                fetched: fetchedMetadata,
                capturedCaption: seed.socialCaptionHint
            )
            guard let metadata else {
                if !hints.isEmpty {
                    // Keep grounded server results when public metadata is not
                    // available, while retaining the partial outcome below.
                    return try await resolveSocialHints(
                        hints,
                        source: source,
                        seed: seed,
                        recognition: recognition,
                        discoveredMediaCount: discoveredMediaCount,
                        understandingPath: understandingPath,
                        understandingWasPartial: understandingWasPartial,
                        remoteHintsWereAccepted: remoteHintsWereAccepted,
                        onProgress: onProgress
                    )
                }
                if understandingWasPartial {
                    return .needsHelp(
                        "This post is still being processed. Wait a moment, then retry automatic matching."
                    )
                }
                return .needsHelp(
                    "This public post did not expose readable place evidence. Check the link and retry automatic matching."
                )
            }
            recognition = try await recognizeSocialMedia(in: metadata)
            sourceSeed.sourceThumbnailURLString = (
                metadata.mediaItems.compactMap(\.imageURL).first
                    ?? metadata.thumbnailURL
            )?.absoluteString
            let localMediaCount = metadata.mediaItems.isEmpty
                ? (metadata.thumbnailURL == nil ? 0 : 1)
                : metadata.mediaItems.count
            discoveredMediaCount = max(discoveredMediaCount, localMediaCount)
            if !remoteHintsWereAccepted {
                understandingPath = "local_fallback"
            }
            let localHints = SocialPlaceHintExtractor.hints(
                from: metadata,
                recognizedTexts: recognition.recognizedTexts,
                limit: Self.maximumExtractedSocialHints
            )
            hints = SocialImportEvidencePlanner.reviewHints(hints + localHints)
        }

        return try await resolveSocialHints(
            hints,
            source: source,
            seed: sourceSeed,
            recognition: recognition,
            discoveredMediaCount: discoveredMediaCount,
            understandingPath: understandingPath,
            understandingWasPartial: understandingWasPartial,
            remoteHintsWereAccepted: remoteHintsWereAccepted,
            onProgress: onProgress
        )
    }

    private func resolveSocialHints(
        _ hints: [SocialPlaceSearchHint],
        source: PlaceImportSource,
        seed: PlaceImportSeed,
        recognition: SocialMediaRecognition,
        discoveredMediaCount: Int,
        understandingPath: String,
        understandingWasPartial: Bool,
        remoteHintsWereAccepted: Bool,
        onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void
    ) async throws -> PlaceImportResolution {

        let durableHints = hints.filter(\.evidence.shouldRemainVisibleWithoutCandidates)
        let hintsRequiringDeviceLookup = durableHints.filter {
            !$0.isServerGrounded || $0.resolvedCandidates.isEmpty
        }
        if hintsRequiringDeviceLookup.count > Self.maximumImmediateSocialLookups {
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
            WanderDebugLog.imports.notice(
                "social guide expansion source=\(source.rawValue, privacy: .public) understanding_path=\(understandingPath, privacy: .public) discovered_media_count=\(discoveredMediaCount, privacy: .public) ocr_attempt_count=\(recognition.attemptedCount, privacy: .public) ocr_empty_or_failed_count=\(recognition.emptyOrFailedCount, privacy: .public) extracted_hint_count=\(hints.count, privacy: .public) durable_row_count=\(expandedSeeds.count, privacy: .public) deferred_lookup_count=\(expandedSeeds.count, privacy: .public)"
            )
            if understandingWasPartial {
                return .partialExpanded(expandedSeeds, retrySeed: seed, sourceName: nil)
            }
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
        var recoveryHints: [SocialRecoveryHint] = []
        var completedHintCount = 0
        onProgress(.init(totalCount: hints.count, completedCount: 0, resolvedCount: 0))
        for hint in hints {
            try Task.checkCancellation()
            defer {
                completedHintCount += 1
                onProgress(.init(
                    totalCount: hints.count, completedCount: completedHintCount,
                    resolvedCount: entries.filter { !$0.candidates.isEmpty }.count
                ))
            }
            var fetchedCandidates: [PlaceCandidate]
            var usedOCRRecoveryLookup = false
            if hint.isServerGrounded, !hint.resolvedCandidates.isEmpty {
                fetchedCandidates = hint.resolvedCandidates
            } else {
                do {
                    fetchedCandidates = try await resolveSocialManualEntry(
                        ManualPlaceInput(name: hint.name, areaHint: hint.area, category: nil)
                    )
                } catch {
                    try Task.checkCancellation()
                    lookupFailureCount += 1
                    if hint.evidence.shouldRemainVisibleWithoutCandidates {
                        recoveryHints.append(
                            SocialRecoveryHint(
                                hint: hint,
                                helpMessage: "This place was named in the post, but place matching was temporarily unavailable. Retry this item later."
                            )
                        )
                    } else {
                        rejectedHintCount += 1
                    }
                    continue
                }
            }
            if fetchedCandidates.isEmpty,
               let recoveryInput = SocialOCRPlaceRecovery.manualInput(for: hint) {
                do {
                    fetchedCandidates = try await resolveSocialManualEntry(recoveryInput)
                    usedOCRRecoveryLookup = !fetchedCandidates.isEmpty
                } catch {
                    try Task.checkCancellation()
                    // The exact creator-provided lookup already completed with
                    // no candidates. OCR recovery is only an optional second
                    // chance, so its transient failure must not replace that
                    // clean result with a misleading service-outage row.
                    fetchedCandidates = []
                }
            }
            try Task.checkCancellation()
            let candidates = SocialImportCountry.candidatesCompatibleWithExactCountry(
                fetchedCandidates,
                areaHint: hint.area
            )
            guard !candidates.isEmpty else {
                noCandidateCount += 1
                if hint.evidence.shouldRemainVisibleWithoutCandidates {
                    recoveryHints.append(
                        SocialRecoveryHint(
                            hint: hint,
                            helpMessage: "This place was named in the post, but place matching needs your help."
                        )
                    )
                } else {
                    rejectedHintCount += 1
                }
                continue
            }
            let match = PlaceImportCandidateMatcher.match(
                candidates,
                nameHint: hint.name,
                areaHint: hint.area,
                allowNearSpellingMatch: hint.evidence == .imageText,
                maximumNearSpellingEdits: usedOCRRecoveryLookup ? 2 : 1,
                selectionPolicy: .socialGroundedArea
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
            if !match.candidates.isEmpty, match.bestScore >= 0.7 {
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
                if hint.evidence.shouldRemainVisibleWithoutCandidates {
                    recoveryHints.append(
                        SocialRecoveryHint(
                            hint: hint,
                            helpMessage: "This place was named in the post, but place matching needs your help."
                        )
                    )
                } else {
                    rejectedHintCount += 1
                }
            }
            if match.bestScore > (strongest?.bestScore ?? 0) {
                strongest = match
            }
        }

        if remoteHintsWereAccepted {
            for recovery in recoveryHints {
                if appendUnresolvedSocialHint(
                    recovery.hint,
                    originalSeed: seed,
                    to: &entries,
                    seenHints: &seenPlausibleHints,
                    helpMessage: recovery.helpMessage
                ) {
                    unresolvedCount += 1
                } else {
                    rejectedHintCount += 1
                }
            }
        } else if let recovery = bestRecoveryHint(recoveryHints),
                  appendUnresolvedSocialHint(
                      recovery.hint,
                      originalSeed: seed,
                      to: &entries,
                      seenHints: &seenPlausibleHints,
                      helpMessage: recovery.helpMessage
                  ) {
            unresolvedCount += 1
            rejectedHintCount += max(0, recoveryHints.count - 1)
        } else {
            rejectedHintCount += recoveryHints.count
        }

        if understandingWasPartial, !entries.isEmpty {
            entries.append(
                PlaceImportResolvedEntry(
                    kind: .sourceRetry,
                    seed: seed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Some media in this post could not be read. Retry automatic matching to look for more places."
                )
            )
        }

        WanderDebugLog.imports.notice(
            "social import resolution source=\(source.rawValue, privacy: .public) understanding_path=\(understandingPath, privacy: .public) discovered_media_count=\(discoveredMediaCount, privacy: .public) ocr_attempt_count=\(recognition.attemptedCount, privacy: .public) ocr_empty_or_failed_count=\(recognition.emptyOrFailedCount, privacy: .public) extracted_hint_count=\(hints.count, privacy: .public) resolved_count=\(resolvedCount, privacy: .public) unresolved_count=\(unresolvedCount, privacy: .public) no_candidate_count=\(noCandidateCount, privacy: .public) low_confidence_count=\(lowConfidenceCount, privacy: .public) lookup_failure_count=\(lookupFailureCount, privacy: .public) rejected_hint_count=\(rejectedHintCount, privacy: .public)"
        )
        if lookupFailureCount > 0 {
            if !entries.isEmpty {
                return .partialExpandedResolved(entries, sourceName: nil)
            }
            return .needsHelp(
                "Place matching was temporarily unavailable. Retry later."
            )
        }
        if understandingWasPartial, !entries.isEmpty {
            return .partialExpandedResolved(entries, sourceName: nil)
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
        if understandingWasPartial {
            return .needsHelp(
                "Some media in this post could not be read. Retry automatic matching to look for places."
            )
        }
        return .needsHelp(
            "No confident place match was found from this post's caption or cover image. Retry automatic matching."
        )
    }

    /// Runs every automatic social-place lookup through one bounded retry path.
    /// The shared pacer applies only to the real MapKit resolver, keeping unit
    /// tests deterministic and avoiding artificial sleeps for local fakes.
    private func resolveSocialManualEntry(
        _ input: ManualPlaceInput
    ) async throws -> [PlaceCandidate] {
        for attempt in 1...Self.maximumSocialLookupAttempts {
            try Task.checkCancellation()
            if placeResolver is MapKitPlaceResolver {
                try await SocialImportAutomaticLookupPacer.shared.waitForTurn()
            }
            do {
                return try await placeResolver.resolveManualEntry(input)
            } catch PlaceResolutionError.noCandidates {
                // A real empty search is terminal, not a transient failure.
                return []
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as PlaceResolutionError {
                throw error
            } catch {
                try Task.checkCancellation()
                if attempt == Self.maximumSocialLookupAttempts {
                    throw error
                }
            }
        }
        return []
    }

    private enum SocialOCRPlaceRecovery {
        static func manualInput(for hint: SocialPlaceSearchHint) -> ManualPlaceInput? {
            guard hint.evidence == .imageText,
                  let area = hint.area?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !area.isEmpty else { return nil }

            let tokens = hint.name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            guard let designator = recoveryDesignators.first(where: { tokens.contains($0.key) })?.value else {
                return nil
            }
            return ManualPlaceInput(name: designator, areaHint: area, category: nil)
        }

        private static let recoveryDesignators: [(key: String, value: String)] = [
            ("cafe", "Cafe"), ("coffee", "Coffee"), ("restaurant", "Restaurant"),
            ("bakery", "Bakery"), ("bookstore", "Bookstore"), ("books", "Books"),
            ("brewery", "Brewery"), ("hotel", "Hotel"), ("inn", "Inn"),
            ("lodge", "Lodge"), ("market", "Market"), ("museum", "Museum"),
            ("resort", "Resort"), ("winery", "Winery")
        ]
    }

    private func socialMetadata(
        fetched: SocialImportMetadata?,
        capturedCaption: String?
    ) -> SocialImportMetadata? {
        let capturedCaption = normalized(capturedCaption)
        guard fetched != nil || capturedCaption != nil else { return nil }
        guard let fetched else {
            return SocialImportMetadata(
                title: nil,
                caption: capturedCaption,
                authorName: nil,
                thumbnailURL: nil
            )
        }
        var seen = Set<String>()
        let caption = [capturedCaption, fetched.caption]
            .compactMap { normalized($0) }
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
        return SocialImportMetadata(
            title: fetched.title,
            caption: caption.isEmpty ? nil : caption,
            authorName: fetched.authorName,
            thumbnailURL: fetched.thumbnailURL,
            mediaItems: fetched.mediaItems
        )
    }

    private func bestRecoveryHint(_ hints: [SocialRecoveryHint]) -> SocialRecoveryHint? {
        hints.enumerated().max { lhs, rhs in
            if lhs.element.hint.evidence.trustRank != rhs.element.hint.evidence.trustRank {
                return lhs.element.hint.evidence.trustRank < rhs.element.hint.evidence.trustRank
            }
            if (lhs.element.hint.area == nil) != (rhs.element.hint.area == nil) {
                return lhs.element.hint.area == nil
            }
            if lhs.element.hint.name.count != rhs.element.hint.name.count {
                return lhs.element.hint.name.count < rhs.element.hint.name.count
            }
            return lhs.offset > rhs.offset
        }?.element
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
        helpMessage: String = "This place was named in the post, but place matching needs your help."
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
        preserveUnselectedCandidates: Bool = false,
        retriesTransientSocialFailures: Bool = false
    ) async throws -> PlaceImportResolution {
        do {
            let input = ManualPlaceInput(name: name, areaHint: normalized(area), category: nil)
            let resolvedCandidates: [PlaceCandidate]
            if retriesTransientSocialFailures {
                resolvedCandidates = try await resolveSocialManualEntry(input)
            } else {
                resolvedCandidates = try await placeResolver.resolveManualEntry(input)
            }
            let candidates = SocialImportCountry.candidatesCompatibleWithExactCountry(
                resolvedCandidates,
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
            sourceProviderPlaceID: candidate?.sourceProviderPlaceID,
            socialCaptionHint: original.socialCaptionHint,
            sourceThumbnailURLString: original.sourceThumbnailURLString
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

final class EphemeralPlaceImportPersistence: PlaceImportPersisting {
    private var snapshot = PlaceImportSnapshot()

    func load() throws -> PlaceImportSnapshot {
        snapshot
    }

    func save(_ snapshot: PlaceImportSnapshot) throws {
        self.snapshot = snapshot
    }
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
    private static let maximumConcurrentResolutions = 6

    private struct ProcessingClaim: Sendable {
        let itemID: String
        let seed: PlaceImportSeed
        let source: PlaceImportSource
        let isManualSearch: Bool
    }

    private enum ProcessingAttempt: Sendable {
        case resolved(PlaceImportResolution)
        case failed(String)
        case cancelled
    }
    private struct LoadedItemUpgrade {
        let items: [PlaceImportItem]
        let replacedSocialItemsByPlaceholderID: [String: [PlaceImportItem]]
    }

    @Published private(set) var batches: [PlaceImportBatch]
    @Published private(set) var items: [PlaceImportItem]
    @Published private(set) var persistenceError: String?
    @Published private(set) var matchingProgressByItemID: [String: PlaceImportMatchingProgress] = [:]

    private let persistence: any PlaceImportPersisting
    private let resolver: any PlaceImportResolving
    private var ownerUserID: String?
    private var processingTasks: [String: Task<Void, Never>] = [:]
    private var replacedSocialItemsByPlaceholderID: [String: [PlaceImportItem]]
    private var persistenceDeferralDepth = 0
    private var persistenceRequestedWhileDeferred = false

    init(
        persistence: any PlaceImportPersisting = FilePlaceImportPersistence(),
        resolver: any PlaceImportResolving = DevicePlaceImportResolver()
    ) {
        self.persistence = persistence
        self.resolver = resolver
        do {
            let snapshot = try persistence.load()
            let upgrade = Self.upgradedLoadedItems(snapshot.items)
            ownerUserID = snapshot.ownerUserID
            items = upgrade.items
            batches = Self.normalizedLoadedReceipts(
                snapshot.batches,
                items: snapshot.items
            )
            replacedSocialItemsByPlaceholderID = upgrade.replacedSocialItemsByPlaceholderID
            persistenceError = nil
        } catch {
            batches = []
            items = []
            ownerUserID = nil
            replacedSocialItemsByPlaceholderID = [:]
            persistenceError = "Import history could not be restored. New imports will still work in this session."
        }
        synchronizeAllBatches(persist: false)
    }

    /// Separates source-level retry status from place receipt rows written by
    /// builds that predated `PlaceImportItemKind`.
    ///
    /// Matching by item identity is authoritative here. Receipt text and shape
    /// are deliberately ignored because a real unresolved place can share the
    /// same display copy as an old source placeholder.
    private static func normalizedLoadedReceipts(
        _ loadedBatches: [PlaceImportBatch],
        items: [PlaceImportItem]
    ) -> [PlaceImportBatch] {
        let sourceRetryItemIDsByBatch = Dictionary(
            grouping: items.filter(\.isSourceRetry),
            by: \.batchID
        ).mapValues { Set($0.map(\.id)) }

        return loadedBatches.map { loadedBatch in
            guard let receipt = loadedBatch.receipt,
                  let sourceRetryItemIDs = sourceRetryItemIDsByBatch[loadedBatch.id]
            else { return loadedBatch }
            let receiptSourceRetryItemIDs = Set(
                receipt.entries.lazy
                    .map(\.itemID)
                    .filter(sourceRetryItemIDs.contains)
            )
            guard !receiptSourceRetryItemIDs.isEmpty else { return loadedBatch }

            var normalizedBatch = loadedBatch
            normalizedBatch.receipt = PlaceImportReceipt(
                id: receipt.id,
                batchID: receipt.batchID,
                sourceName: receipt.sourceName,
                createdAt: receipt.createdAt,
                entries: receipt.entries.filter {
                    !receiptSourceRetryItemIDs.contains($0.itemID)
                },
                destinationListID: receipt.destinationListID,
                sourceRetryCount: max(
                    receipt.sourceRetryCount,
                    receiptSourceRetryItemIDs.count
                ),
                presentedAt: receipt.presentedAt
            )
            return normalizedBatch
        }
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
                    sourceLine: item.seed.sourceLine,
                    socialCaptionHint: item.seed.socialCaptionHint,
                    sourceThumbnailURLString: item.seed.sourceThumbnailURLString,
                    socialUnderstandingRequestID: item.seed.socialUnderstandingRequestID
                )
            }

            upgraded.state = .queued
            upgraded.candidates = []
            upgraded.selectedCandidateID = nil
            upgraded.selectedCandidateIDsRaw = nil
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

    var unreviewedImportCount: Int {
        let itemsByBatch = Dictionary(grouping: items, by: \.batchID)
        return batches.filter { batch in
            PlaceImportHistoryPresentation.needsReview(batch: batch, items: itemsByBatch[batch.id] ?? [])
        }.count
    }

    /// Each import contributes once while matching or awaiting its first review.
    /// Keep this separate from review acknowledgement: opening an in-flight
    /// report must not mark results that have not arrived yet as reviewed.
    var recentImportBadgeCount: Int {
        let itemsByBatch = Dictionary(grouping: items, by: \.batchID)
        return batches.filter { batch in
            let batchItems = itemsByBatch[batch.id] ?? []
            return PlaceImportHistoryPresentation.isMatching(batch: batch, items: batchItems)
                || PlaceImportHistoryPresentation.needsReview(batch: batch, items: batchItems)
        }.count
    }

    func markReviewOpened(batchIDs: [String]) {
        let ids = Set(batchIDs)
        var changed = false
        for index in batches.indices where ids.contains(batches[index].id) {
            guard PlaceImportHistoryPresentation.needsReview(
                batch: batches[index], items: items(for: batches[index].id)
            ) else { continue }
            batches[index].reviewOpenedAt = .now
            changed = true
        }
        if changed { persist() }
    }

    func matchingProgress(batchIDs: [String]) -> PlaceImportMatchingProgress {
        let ids = Set(batchIDs)
        return .summarize(
            items: items.filter { ids.contains($0.batchID) },
            inFlight: matchingProgressByItemID
        )
    }

    var summary: PlaceImportSummary {
        let inboxItems = items.filter { $0.state != .dismissed }
        guard !inboxItems.isEmpty else { return .empty }
        let placeItems = inboxItems.filter { !$0.isSourceRetry }
        let unresolvedItems = placeItems.filter {
            [.queued, .resolving, .ready, .ambiguous, .needsHelp, .failed].contains($0.state)
        }
        let sourceRetryItems = inboxItems.filter(\.isSourceRetry)
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
            duplicateCount: placeItems.filter { $0.state == .duplicate }.count,
            savedCount: placeItems.filter { $0.state == .saved }.count,
            sourceRetryCount: sourceRetryItems.count,
            sourceRetryProcessingCount: sourceRetryItems.filter {
                [.queued, .resolving].contains($0.state)
            }.count
        )
    }

    var latestUnpresentedReceipt: PlaceImportReceipt? {
        batches
            .compactMap(\.receipt)
            .filter { $0.presentedAt == nil }
            .max { $0.createdAt < $1.createdAt }
    }

    func reviewPlan(batchID: String? = nil) -> PlaceImportReviewPlan {
        let reviewItems: [PlaceImportItem]
        if let batchID {
            reviewItems = items(for: batchID)
        } else {
            reviewItems = items
        }
        return PlaceImportReviewPlan(items: reviewItems)
    }

    @discardableResult
    func enqueue(
        source: PlaceImportSource,
        text: String,
        sourceName: String? = nil,
        captureDeliveryID: String? = nil,
        automaticSaveRequested: Bool = false,
        requestedStatus: PlaceStatus = .wannaGo,
        requestedRatingScore: Double? = nil
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
            totalCount: seeds.count,
            automaticSaveRequested: automaticSaveRequested,
            requestedStatus: requestedStatus,
            requestedRatingScore: requestedRatingScore
        )
        batches.append(batch)
        items.append(contentsOf: seeds.map { seed in
            PlaceImportItem(
                batchID: batch.id,
                source: source,
                seed: seed,
                stagedStatus: requestedStatus,
                stagedRatingScore: requestedStatus == .been ? requestedRatingScore : nil
            )
        })
        persist()
        startProcessing(batchID: batch.id)
        return batch.id
    }

    @discardableResult
    func enqueueSharedSocialLink(
        source: PlaceImportSource,
        urlString: String,
        caption: String?,
        sourceName: String?,
        captureDeliveryID: String,
        automaticSaveRequested: Bool = false,
        requestedStatus: PlaceStatus = .wannaGo,
        requestedRatingScore: Double? = nil
    ) throws -> String {
        if let existingBatch = batches.first(where: { $0.captureDeliveryID == captureDeliveryID }) {
            return existingBatch.id
        }
        guard [.instagram, .tiktok].contains(source),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host?.isEmpty == false
        else {
            throw PlaceImportParsingError.noPlacesFound
        }
        let trimmedCaption = caption?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaption = trimmedCaption?.isEmpty == false ? trimmedCaption : nil
        let batch = PlaceImportBatch(
            source: source,
            sourceName: sourceName,
            captureDeliveryID: captureDeliveryID,
            totalCount: 1,
            automaticSaveRequested: automaticSaveRequested,
            requestedStatus: requestedStatus,
            requestedRatingScore: requestedRatingScore
        )
        let seed = PlaceImportSeed(
            rawText: url.absoluteString,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: url.absoluteString,
            sourceLine: 1,
            socialCaptionHint: normalizedCaption
        )
        batches.append(batch)
        items.append(
            PlaceImportItem(
                batchID: batch.id,
                source: source,
                seed: seed,
                stagedStatus: requestedStatus,
                stagedRatingScore: requestedStatus == .been ? requestedRatingScore : nil
            )
        )
        persist()
        startProcessing(batchID: batch.id)
        return batch.id
    }

    @discardableResult
    func enqueueUnified(text: String) throws -> [String] {
        let seeds = try PlaceImportParser.parse(source: .textNotes, text: text)
        var sourceOrder: [PlaceImportSource] = []
        var seedsBySource: [PlaceImportSource: [PlaceImportSeed]] = [:]

        for seed in seeds {
            let source = PlaceImportSourceDetector.source(for: seed)
            if seedsBySource[source] == nil {
                sourceOrder.append(source)
                seedsBySource[source] = []
            }
            seedsBySource[source, default: []].append(seed)
        }

        let batches = sourceOrder.compactMap { source -> PlaceImportBatch? in
            guard let sourceSeeds = seedsBySource[source], !sourceSeeds.isEmpty else { return nil }
            let batch = PlaceImportBatch(
                source: source,
                sourceName: nil,
                totalCount: sourceSeeds.count
            )
            self.batches.append(batch)
            items.append(contentsOf: sourceSeeds.map { seed in
                PlaceImportItem(batchID: batch.id, source: source, seed: seed)
            })
            return batch
        }

        persist()
        for batch in batches {
            startProcessing(batchID: batch.id)
        }
        return batches.map(\.id)
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

    /// Stops in-flight resolution without discarding durable import progress.
    /// Resolved rows stay resolved; only active rows return to the queue so the
    /// next foreground/background window can resume them safely.
    func pauseProcessing(batchIDs: [String]) {
        let ids = Set(batchIDs)
        guard !ids.isEmpty else { return }
        for batchID in ids {
            processingTasks[batchID]?.cancel()
        }
        var didChange = false
        for index in items.indices
        where ids.contains(items[index].batchID) && items[index].state == .resolving {
            matchingProgressByItemID[items[index].id] = nil
            items[index].state = .queued
            items[index].updatedAt = .now
            didChange = true
        }
        for batchID in ids {
            synchronizeBatch(batchID, persist: false)
        }
        if didChange {
            persist()
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
        items[index].selectedCandidateIDsRaw = [candidateID]
        items[index].state = .ready
        items[index].helpMessage = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    /// Gives every candidate-bearing source row a useful default while keeping
    /// lower-confidence alternatives visible and independently selectable.
    func prepareCandidateSelections(batchIDs: [String]) {
        let ids = Set(batchIDs)
        guard !ids.isEmpty else { return }
        var changedBatchIDs = Set<String>()
        for index in items.indices where ids.contains(items[index].batchID) {
            guard !items[index].isSourceRetry,
                  !items[index].candidates.isEmpty,
                  ![.duplicate, .saved, .dismissed].contains(items[index].state),
                  items[index].selectedCandidateIDsRaw == nil,
                  items[index].selectedCandidates.isEmpty
            else { continue }
            let primaryID = items[index].candidates[0].id
            items[index].selectedCandidateID = primaryID
            items[index].selectedCandidateIDsRaw = [primaryID]
            items[index].state = .ready
            items[index].isSelectedForImport = true
            items[index].helpMessage = nil
            items[index].updatedAt = .now
            changedBatchIDs.insert(items[index].batchID)
        }
        for batchID in changedBatchIDs {
            synchronizeBatch(batchID, persist: false)
        }
        if !changedBatchIDs.isEmpty { persist() }
    }

    /// Toggles one of at most five possible Apple Maps matches. Status and
    /// optional details remain owned by the source row and therefore apply to
    /// every selected match.
    func toggleCandidateSelection(itemID: String, candidateID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].candidates.prefix(5).contains(where: { $0.id == candidateID }),
              ![.duplicate, .saved, .dismissed].contains(items[index].state)
        else { return }

        var selectedIDs = items[index].selectedCandidateIDs
        if let selectedIndex = selectedIDs.firstIndex(of: candidateID) {
            selectedIDs.remove(at: selectedIndex)
        } else {
            selectedIDs.append(candidateID)
        }
        let candidateOrder = items[index].candidates.map(\.id)
        selectedIDs = candidateOrder.filter(Set(selectedIDs).contains)
        items[index].selectedCandidateIDsRaw = selectedIDs
        items[index].selectedCandidateID = selectedIDs.first
        items[index].state = .ready
        items[index].isSelectedForImport = !selectedIDs.isEmpty
        items[index].helpMessage = nil
        items[index].updatedAt = .now
        synchronizeBatch(items[index].batchID)
    }

    func setStagedStatus(_ status: PlaceStatus, itemID: String) {
        setStagedStatus(status, itemIDs: [itemID])
    }

    func setStagedStatus(_ status: PlaceStatus, itemIDs: [String]) {
        let ids = Set(itemIDs)
        guard !ids.isEmpty else { return }
        var didChange = false
        for index in items.indices
        where ids.contains(items[index].id) && [.ready, .saved].contains(items[index].state) {
            items[index].stagedStatus = status
            items[index].updatedAt = .now
            didChange = true
        }
        if didChange { persist() }
    }

    func setIncludedInImport(_ isIncluded: Bool, itemID: String) {
        setIncludedInImport(isIncluded, itemIDs: [itemID])
    }

    func setIncludedInImport(_ isIncluded: Bool, itemIDs: [String]) {
        let ids = Set(itemIDs)
        guard !ids.isEmpty else { return }
        var didChange = false
        for index in items.indices
        where ids.contains(items[index].id)
            && items[index].state != .dismissed
            && !items[index].isSourceRetry {
            items[index].isSelectedForImport = isIncluded
            items[index].updatedAt = .now
            didChange = true
        }
        if didChange { persist() }
    }

    /// Claims the local import snapshot for the authenticated account. A snapshot
    /// owned by another account is cleared before any capture can be reviewed or saved.
    func bind(to userID: String) {
        guard ownerUserID != userID else { return }
        processingTasks.values.forEach { $0.cancel() }
        processingTasks.removeAll()
        batches = []
        items = []
        replacedSocialItemsByPlaceholderID = [:]
        ownerUserID = userID
        matchingProgressByItemID = [:]
        persist()
    }

    func setStagedNote(_ note: String?, itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              [.ready, .saved].contains(items[index].state)
        else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].stagedNote = trimmed?.isEmpty == false ? trimmed : nil
        items[index].updatedAt = .now
        persist()
    }

    func setStagedRatingScore(_ score: Double?, itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              [.ready, .saved].contains(items[index].state),
              items[index].stagedStatus == .been
        else { return }
        items[index].stagedRatingScore = score
        items[index].updatedAt = .now
        persist()
    }

    func setStagedVisitedAt(_ date: Date?, itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              [.ready, .saved].contains(items[index].state),
              items[index].stagedStatus == .been
        else { return }
        items[index].stagedVisitedAt = date
        items[index].updatedAt = .now
        persist()
    }

    func applyStagedStatus(_ status: PlaceStatus, batchID: String? = nil) {
        var changed = false
        for index in items.indices where items[index].state == .ready {
            guard batchID == nil || items[index].batchID == batchID else { continue }
            if items[index].stagedStatus != status {
                items[index].stagedStatus = status
                items[index].updatedAt = .now
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    func retry(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let existingName = items[index].seed.nameHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNameHint = existingName?.isEmpty == false
        if [.instagram, .tiktok].contains(items[index].source),
           items[index].seed.sourceURLString != nil,
           !hasNameHint {
            // Preserve one idempotency key across pause/crash resumption, but a
            // user-requested retry is a new paid attempt and must not be rejected
            // by the server's durable completed-request duplicate marker.
            items[index].seed.socialUnderstandingRequestID = UUID().uuidString.lowercased()
        }
        items[index].pendingManualSearch = nil
        items[index].state = .queued
        items[index].candidates = []
        items[index].selectedCandidateID = nil
        items[index].selectedCandidateIDsRaw = nil
        items[index].helpMessage = nil
        items[index].duplicateUserPlaceID = nil
        items[index].updatedAt = .now
        items[index].resolverVersion = PlaceImportItem.currentResolverVersion
        let batchID = items[index].batchID
        if let batchIndex = batches.firstIndex(where: { $0.id == batchID }) {
            batches[batchIndex].reviewOpenedAt = nil
        }
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
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID,
            socialCaptionHint: existingSeed.socialCaptionHint,
            sourceThumbnailURLString: existingSeed.sourceThumbnailURLString,
            socialUnderstandingRequestID: existingSeed.socialUnderstandingRequestID
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
            case .retrySocialUnderstanding, .expanded, .partialExpanded,
                 .expandedResolved, .partialExpandedResolved:
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
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID,
            socialCaptionHint: existingSeed.socialCaptionHint,
            sourceThumbnailURLString: existingSeed.sourceThumbnailURLString,
            socialUnderstandingRequestID: existingSeed.socialUnderstandingRequestID
        )
        items[index].pendingManualSearch = nil
        items[index].candidates = candidates
        items[index].selectedCandidateID = selectedCandidateID
        items[index].selectedCandidateIDsRaw = [selectedCandidateID]
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
            sourceProviderPlaceID: existingSeed.sourceProviderPlaceID,
            socialCaptionHint: existingSeed.socialCaptionHint,
            sourceThumbnailURLString: existingSeed.sourceThumbnailURLString,
            socialUnderstandingRequestID: existingSeed.socialUnderstandingRequestID
        )
        items[index].candidates = []
        items[index].selectedCandidateID = nil
        items[index].selectedCandidateIDsRaw = nil
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

    /// Coalesces a synchronous import mutation batch into one durable snapshot.
    func performBatchedMutations<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        persistenceDeferralDepth += 1
        defer {
            persistenceDeferralDepth -= 1
            if persistenceDeferralDepth == 0, persistenceRequestedWhileDeferred {
                persistenceRequestedWhileDeferred = false
                persist()
            }
        }
        return try operation()
    }

    func recordReceipt(
        batchID: String,
        entries: [PlaceImportReceiptEntry],
        destinationListID: String?
    ) {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        let sourceRetryItems = items.filter { $0.batchID == batchID && $0.isSourceRetry }
        let sourceRetryItemIDs = Set(sourceRetryItems.map(\.id))
        let activeSourceRetryCount = sourceRetryItems.filter {
            ![.saved, .dismissed].contains($0.state)
        }.count
        let receipt = PlaceImportReceipt(
            batchID: batchID,
            sourceName: batches[index].sourceName,
            entries: entries.filter { !sourceRetryItemIDs.contains($0.itemID) },
            destinationListID: destinationListID,
            sourceRetryCount: activeSourceRetryCount
        )
        batches[index].destinationListID = destinationListID
        batches[index].receipt = receipt
        batches[index].updatedAt = .now
        persist()
    }

    func markAutomaticSaveCompleted(batchID: String, at date: Date = .now) {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        batches[index].automaticSaveCompletedAt = date
        batches[index].updatedAt = date
        persist()
    }

    func setDestinationListID(_ destinationListID: String, batchID: String) {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        batches[index].destinationListID = destinationListID
        batches[index].updatedAt = .now
        persist()
    }

    func markReceiptPresented(receiptID: String) {
        guard let index = batches.firstIndex(where: { $0.receipt?.id == receiptID }) else { return }
        batches[index].receipt?.presentedAt = .now
        batches[index].updatedAt = .now
        persist()
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
        for item in items where item.batchID == batchID {
            matchingProgressByItemID[item.id] = nil
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
        matchingProgressByItemID.removeAll()
        items.removeAll()
        batches.removeAll()
        persist()
    }

    func reconcileDuplicates(with existingPlaces: [PlaceImportExistingPlace]) {
        var changedBatchIDs = Set<String>()
        for index in items.indices where [.ready, .ambiguous, .duplicate].contains(items[index].state) {
            // A multi-match row is independently selectable. One existing
            // candidate must not collapse or disable its unsaved siblings;
            // commit resolves duplicate status for each concrete candidate.
            if items[index].candidates.count > 1 {
                if items[index].state == .duplicate || items[index].duplicateUserPlaceID != nil {
                    items[index].duplicateUserPlaceID = nil
                    items[index].state = items[index].selectedCandidates.isEmpty ? .ambiguous : .ready
                    items[index].updatedAt = .now
                    changedBatchIDs.insert(items[index].batchID)
                }
                continue
            }
            let match = items[index].candidates.lazy.compactMap { candidate in
                existingPlaces.first(where: { self.existingPlaceMatches($0, candidate: candidate) })
                    .map { (candidate, $0) }
            }.first

            if let (candidate, existing) = match {
                if items[index].state != .duplicate || items[index].duplicateUserPlaceID != existing.userPlaceID {
                    items[index].state = .duplicate
                    items[index].selectedCandidateID = candidate.id
                    items[index].selectedCandidateIDsRaw = [candidate.id]
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
        while !Task.isCancelled {
            if processingTasks[batchID] == nil {
                startProcessing(batchID: batchID)
            }
            guard let task = processingTasks[batchID] else { return }
            await task.value
            guard !Task.isCancelled else { return }
            if !items.contains(where: { $0.batchID == batchID && $0.state == .queued }) {
                return
            }
        }
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
        while !Task.isCancelled {
            let claims = claimQueuedItems(
                batchID: batchID,
                limit: resolutionConcurrencyLimit(for: batchID)
            )
            guard !claims.isEmpty else { break }

            let tasks = claims.map { claim in
                Task { @MainActor [weak self, resolver] in
                    do {
                        let resolution = if claim.isManualSearch {
                            try await resolver.resolveManualSearch(seed: claim.seed, source: claim.source)
                        } else {
                            try await resolver.resolve(seed: claim.seed, source: claim.source) { [weak self] progress in
                                guard !Task.isCancelled,
                                      let item = self?.item(id: claim.itemID),
                                      item.state == .resolving, item.seed == claim.seed else { return }
                                self?.matchingProgressByItemID[claim.itemID] = progress
                            }
                        }
                        if claim.seed.nameHint != nil, !Task.isCancelled,
                           let item = self?.item(id: claim.itemID),
                           item.state == .resolving, item.seed == claim.seed {
                            let matched: Bool
                            if case .candidates(let candidates, _) = resolution {
                                matched = !candidates.isEmpty
                            } else {
                                matched = false
                            }
                            self?.matchingProgressByItemID[claim.itemID] = .init(
                                totalCount: 1, completedCount: 1, resolvedCount: matched ? 1 : 0
                            )
                        }
                        return ProcessingAttempt.resolved(resolution)
                    } catch is CancellationError {
                        return ProcessingAttempt.cancelled
                    } catch {
                        return ProcessingAttempt.failed(error.localizedDescription)
                    }
                }
            }
            let attempts = await withTaskCancellationHandler {
                var values: [ProcessingAttempt] = []
                for task in tasks {
                    values.append(await task.value)
                }
                return values
            } onCancel: {
                tasks.forEach { $0.cancel() }
            }
            guard !Task.isCancelled else { break }

            for (claim, attempt) in zip(claims, attempts) {
                apply(attempt, to: claim)
            }
            synchronizeBatch(batchID)
            await Task.yield()
        }
        processingTasks[batchID] = nil
        synchronizeBatch(batchID)
    }

    private func claimQueuedItems(batchID: String, limit: Int) -> [ProcessingClaim] {
        var claims: [ProcessingClaim] = []
        for _ in 0..<limit {
            guard let index = nextQueuedItemIndex(batchID: batchID) else { break }
            items[index].state = .resolving
            items[index].updatedAt = .now
            claims.append(
                ProcessingClaim(
                    itemID: items[index].id,
                    seed: items[index].seed,
                    source: items[index].source,
                    isManualSearch: items[index].pendingManualSearch == true
                )
            )
        }
        if !claims.isEmpty {
            // The persistence layer substitutes pre-upgrade social rows while
            // their network refresh is in flight, so a whole claimed chunk is safe.
            synchronizeBatch(batchID)
        }
        return claims
    }

    private func resolutionConcurrencyLimit(for batchID: String) -> Int {
        guard let batch = batches.first(where: { $0.id == batchID }),
              batch.source == .googleMaps,
              batch.totalCount >= 10
        else { return 1 }
        return Self.maximumConcurrentResolutions
    }

    private func apply(_ attempt: ProcessingAttempt, to claim: ProcessingClaim) {
        defer { matchingProgressByItemID[claim.itemID] = nil }
        guard let index = items.firstIndex(where: { $0.id == claim.itemID }),
              items[index].state == .resolving,
              items[index].seed == claim.seed
        else {
            // A newer search, retry, pause, or dismissal superseded this request.
            return
        }
        let batchID = items[index].batchID

        switch attempt {
        case .resolved(let resolution):
            if case .retrySocialUnderstanding(let requestID) = resolution {
                if var previousRows = replacedSocialItemsByPlaceholderID[claim.itemID] {
                    for previousIndex in previousRows.indices {
                        previousRows[previousIndex].seed.socialUnderstandingRequestID = requestID
                    }
                    replacedSocialItemsByPlaceholderID[claim.itemID] = previousRows
                }
                apply(resolution, at: index)
                break
            }
            let shouldRestorePreviousRows: Bool
            switch resolution {
            case .needsHelp, .partialExpanded, .partialExpandedResolved:
                shouldRestorePreviousRows = true
            case .retrySocialUnderstanding, .candidates, .expanded, .expandedResolved:
                shouldRestorePreviousRows = false
            }
            if partialResolutionContainsOnlySourceRetry(resolution) {
                // A hosted scan failure must replace stale pre-upgrade guesses,
                // not merge them back beside the retry row. Grounded partial
                // results still use the merge path below.
                replacedSocialItemsByPlaceholderID[claim.itemID] = nil
                items[index].pendingManualSearch = nil
                apply(resolution, at: index)
            } else if partialResolutionHasSourceRetry(resolution),
               mergeReplacedSocialItems(
                   resolution: resolution,
                   placeholderID: claim.itemID,
                   at: index
               ) {
                // Preserve pre-upgrade rows, add newly recovered places, and
                // retain the source-level retry marker for incomplete media.
            } else if shouldRestorePreviousRows,
               restoreReplacedSocialItems(placeholderID: claim.itemID, at: index) {
                // A transient metadata failure must not erase previously useful rows.
            } else {
                replacedSocialItemsByPlaceholderID[claim.itemID] = nil
                items[index].pendingManualSearch = nil
                apply(resolution, at: index)
            }
            if [.instagram, .tiktok].contains(claim.source),
               let sourceURLString = claim.seed.sourceURLString {
                deduplicateSocialSourceItems(
                    batchID: batchID,
                    sourceURLString: sourceURLString
                )
            }
        case .failed(let message):
            if !restoreReplacedSocialItems(placeholderID: claim.itemID, at: index) {
                items[index].state = .failed
                items[index].pendingManualSearch = nil
                items[index].helpMessage = message
                items[index].updatedAt = .now
            }
        case .cancelled:
            items[index].state = .queued
            items[index].updatedAt = .now
        }
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

    private func partialResolutionHasSourceRetry(_ resolution: PlaceImportResolution) -> Bool {
        switch resolution {
        case .partialExpanded:
            true
        case .partialExpandedResolved(let entries, _):
            entries.contains {
                $0.kind == .sourceRetry
                    || $0.seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
        case .candidates, .needsHelp, .retrySocialUnderstanding, .expanded, .expandedResolved:
            false
        }
    }

    private func partialResolutionContainsOnlySourceRetry(
        _ resolution: PlaceImportResolution
    ) -> Bool {
        guard case .partialExpandedResolved(let entries, _) = resolution,
              !entries.isEmpty else { return false }
        return entries.allSatisfy {
            $0.kind == .sourceRetry
                || $0.seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
    }

    @discardableResult
    private func mergeReplacedSocialItems(
        resolution: PlaceImportResolution,
        placeholderID: String,
        at index: Int
    ) -> Bool {
        guard let previousRows = replacedSocialItemsByPlaceholderID.removeValue(forKey: placeholderID) else {
            return false
        }
        let placeholder = items[index]
        items.replaceSubrange(index...index, with: previousRows + [placeholder])
        let placeholderIndex = index + previousRows.count
        items[placeholderIndex].pendingManualSearch = nil
        apply(resolution, at: placeholderIndex)
        return true
    }

    private func apply(_ resolution: PlaceImportResolution, at index: Int) {
        switch resolution {
        case .candidates(let candidates, let selectedCandidateID):
            if !candidates.isEmpty {
                // A source-level retry can collapse to one resolved place.
                // Convert that placeholder into a normal, selected place row.
                items[index].kind = nil
                items[index].isIncludedInImport = nil
            }
            items[index].candidates = candidates
            items[index].selectedCandidateID = selectedCandidateID
            items[index].selectedCandidateIDsRaw = selectedCandidateID.map { [$0] }
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
            items[index].selectedCandidateIDsRaw = nil
            items[index].state = .needsHelp
            items[index].helpMessage = message
        case .retrySocialUnderstanding(let requestID):
            items[index].seed.socialUnderstandingRequestID = requestID
            items[index].state = .queued
            items[index].candidates = []
            items[index].selectedCandidateID = nil
            items[index].selectedCandidateIDsRaw = nil
            items[index].helpMessage = nil
        case .expanded(let seeds, let sourceName):
            let original = items[index]
            let expandedItems = seeds.map { seed in
                PlaceImportItem(
                    batchID: original.batchID,
                    source: original.source,
                    seed: seed,
                    resolverVersion: PlaceImportItem.currentResolverVersion,
                    stagedStatus: original.stagedStatus,
                    stagedRatingScore: original.stagedRatingScore,
                    createdAt: original.createdAt
                )
            }
            items.replaceSubrange(index...index, with: expandedItems)
            if let sourceName,
               let batchIndex = batches.firstIndex(where: { $0.id == original.batchID }) {
                batches[batchIndex].sourceName = sourceName
            }
            return
        case .partialExpanded(let seeds, let retrySeed, let sourceName):
            let original = items[index]
            let expandedItems = seeds.map { seed in
                PlaceImportItem(
                    batchID: original.batchID,
                    source: original.source,
                    seed: seed,
                    resolverVersion: PlaceImportItem.currentResolverVersion,
                    stagedStatus: original.stagedStatus,
                    stagedRatingScore: original.stagedRatingScore,
                    createdAt: original.createdAt
                )
            }
            let retryItem = PlaceImportItem(
                batchID: original.batchID,
                source: original.source,
                kind: .sourceRetry,
                seed: retrySeed,
                state: .needsHelp,
                helpMessage: "Some media in this post could not be read. Retry automatic matching to look for more places.",
                resolverVersion: PlaceImportItem.currentResolverVersion,
                stagedStatus: original.stagedStatus,
                stagedRatingScore: original.stagedRatingScore,
                createdAt: original.createdAt
            )
            items.replaceSubrange(index...index, with: expandedItems + [retryItem])
            if let sourceName,
               let batchIndex = batches.firstIndex(where: { $0.id == original.batchID }) {
                batches[batchIndex].sourceName = sourceName
            }
            return
        case .expandedResolved(let entries, let sourceName),
             .partialExpandedResolved(let entries, let sourceName):
            let original = items[index]
            let infersLegacyRetryKind: Bool
            if case .partialExpandedResolved = resolution {
                infersLegacyRetryKind = true
            } else {
                infersLegacyRetryKind = false
            }
            let expandedItems = entries.map { entry in
                let isSourceRetry = entry.kind == .sourceRetry
                    || (infersLegacyRetryKind
                        && entry.seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
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
                    kind: isSourceRetry ? .sourceRetry : nil,
                    seed: entry.seed,
                    state: state,
                    candidates: entry.candidates,
                    selectedCandidateID: entry.selectedCandidateID,
                    helpMessage: entry.helpMessage,
                    resolverVersion: PlaceImportItem.currentResolverVersion,
                    stagedStatus: original.stagedStatus,
                    stagedRatingScore: original.stagedRatingScore,
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

    private func deduplicateSocialSourceItems(
        batchID: String,
        sourceURLString: String
    ) {
        let matchingIndices = items.indices.filter { index in
            let item = items[index]
            return item.batchID == batchID
                && item.seed.sourceURLString == sourceURLString
        }
        var retainedIndices: [Int] = []
        var duplicateIndices = Set<Int>()

        for index in matchingIndices {
            guard let existingIndex = retainedIndices.first(where: {
                socialSourceItemsReferToSamePlace(items[$0], items[index])
            }) else {
                retainedIndices.append(index)
                continue
            }
            if socialSourceItemQuality(items[index]) > socialSourceItemQuality(items[existingIndex]) {
                // Keep the original row identity and staged user edits while
                // accepting a better result from the source-level retry.
                items[existingIndex].seed = items[index].seed
                items[existingIndex].kind = items[index].kind
                items[existingIndex].state = items[index].state
                items[existingIndex].candidates = items[index].candidates
                items[existingIndex].selectedCandidateID = items[index].selectedCandidateID
                items[existingIndex].selectedCandidateIDsRaw = items[index].selectedCandidateIDsRaw
                items[existingIndex].helpMessage = items[index].helpMessage
                items[existingIndex].duplicateUserPlaceID = items[index].duplicateUserPlaceID
                items[existingIndex].resolverVersion = items[index].resolverVersion
                items[existingIndex].updatedAt = items[index].updatedAt
            }
            duplicateIndices.insert(index)
        }

        for index in duplicateIndices.sorted(by: >) {
            items.remove(at: index)
        }
    }

    private func socialSourceItemsReferToSamePlace(
        _ lhs: PlaceImportItem,
        _ rhs: PlaceImportItem
    ) -> Bool {
        if lhs.isSourceRetry || rhs.isSourceRetry {
            return lhs.isSourceRetry && rhs.isSourceRetry
        }
        let lhsName = lhs.seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsName = rhs.seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsName?.isEmpty != false || rhsName?.isEmpty != false {
            return lhsName?.isEmpty != false && rhsName?.isEmpty != false
        }

        let lhsSelectedCandidate = lhs.selectedCandidate
        let rhsSelectedCandidate = rhs.selectedCandidate
        if let lhsProviderID = lhsSelectedCandidate?.sourceProviderPlaceID,
           let rhsProviderID = rhsSelectedCandidate?.sourceProviderPlaceID,
           lhsSelectedCandidate?.sourceProvider == rhsSelectedCandidate?.sourceProvider {
            // Two confidently selected branches from the same provider are
            // distinct when their provider identities differ, even if their
            // creator-facing names and cities are identical.
            return lhsProviderID == rhsProviderID
        }
        guard socialSourceItemNamesAreEquivalent(
            lhsName ?? "",
            rhsName ?? "",
            lhs: lhs,
            rhs: rhs
        ) else { return false }

        let lhsCandidate = lhsSelectedCandidate ?? lhs.candidates.first
        let rhsCandidate = rhsSelectedCandidate ?? rhs.candidates.first
        if let lhsProviderID = lhsCandidate?.sourceProviderPlaceID,
           let rhsProviderID = rhsCandidate?.sourceProviderPlaceID,
           lhsCandidate?.sourceProvider == rhsCandidate?.sourceProvider,
           lhsProviderID == rhsProviderID {
            return true
        }

        let lhsCountryCodes = socialSourceItemCountryCodes(lhs)
        let rhsCountryCodes = socialSourceItemCountryCodes(rhs)
        if !lhsCountryCodes.isEmpty,
           !rhsCountryCodes.isEmpty,
           lhsCountryCodes.isDisjoint(with: rhsCountryCodes) {
            return false
        }

        let lhsAreas = socialSourceItemAreas(lhs)
        let rhsAreas = socialSourceItemAreas(rhs)
        guard !lhsAreas.isEmpty, !rhsAreas.isEmpty else { return true }
        return lhsAreas.contains { lhsArea in
            rhsAreas.contains { rhsArea in
                lhsArea == rhsArea
                    || lhsArea.contains(rhsArea)
                    || rhsArea.contains(lhsArea)
            }
        }
    }

    private func socialSourceItemNamesAreEquivalent(
        _ lhsName: String,
        _ rhsName: String,
        lhs: PlaceImportItem,
        rhs: PlaceImportItem
    ) -> Bool {
        if PlaceImportCandidateMatcher.namesAreEquivalent(lhsName, rhsName) {
            return true
        }

        let lhsWords = normalizedWords(lhsName)
        let rhsWords = normalizedWords(rhsName)
        let shorterWords: [String]
        let longerWords: [String]
        if lhsWords.count < rhsWords.count {
            shorterWords = lhsWords
            longerWords = rhsWords
        } else if rhsWords.count < lhsWords.count {
            shorterWords = rhsWords
            longerWords = lhsWords
        } else {
            return false
        }
        guard !shorterWords.isEmpty,
              Array(longerWords.prefix(shorterWords.count)) == shorterWords
        else { return false }

        let suffixWords = Set(longerWords.dropFirst(shorterWords.count))
        guard !suffixWords.isEmpty else { return false }
        return suffixWords.isSubset(of: socialSourceItemAreaWords(lhs))
            && suffixWords.isSubset(of: socialSourceItemAreaWords(rhs))
    }

    private func socialSourceItemAreaWords(_ item: PlaceImportItem) -> Set<String> {
        let candidate = item.selectedCandidate ?? item.candidates.first
        return Set([
            item.seed.areaHint,
            item.displayArea,
            candidate?.locality,
            candidate?.region
        ]
        .compactMap { $0 }
        .flatMap(normalizedWords))
    }

    private func socialSourceItemCountryCodes(_ item: PlaceImportItem) -> Set<String> {
        let candidate = item.selectedCandidate ?? item.candidates.first
        return Set([
            item.seed.areaHint,
            item.displayArea,
            candidate?.country
        ].compactMap { SocialImportCountry.isoCode(for: $0) })
    }

    private func socialSourceItemAreas(_ item: PlaceImportItem) -> Set<String> {
        let candidate = item.selectedCandidate ?? item.candidates.first
        let combinedLocalityAndRegion = [candidate?.locality, candidate?.region]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let localityAndRegion = combinedLocalityAndRegion.isEmpty
            ? nil
            : combinedLocalityAndRegion
        let rawAreas: [String?] = [
            item.seed.areaHint,
            item.displayArea,
            candidate?.address,
            candidate?.locality,
            candidate?.region,
            localityAndRegion
        ]
        let normalizedAreas = rawAreas.compactMap { value in
            SocialImportCountry.isoCode(for: value) == nil ? value : nil
        }
            .map(normalizedName)
            .filter { !$0.isEmpty }
        return Set(normalizedAreas)
    }

    private func socialSourceItemQuality(_ item: PlaceImportItem) -> Int {
        switch item.state {
        case .ready: 4
        case .ambiguous: 3
        case .needsHelp: 2
        case .queued, .resolving: 1
        case .failed: 0
        case .dismissed: 6
        case .saved, .duplicate: 5
        }
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
        let placeItems = batchItems.filter { !$0.isSourceRetry }
        let pendingPlaceCount = placeItems.filter { [.queued, .resolving].contains($0.state) }.count
        let terminalPlaceCount = placeItems.filter {
            [.saved, .duplicate, .dismissed].contains($0.state)
        }.count
        let hasActiveSourceRetry = batchItems.contains {
            $0.isSourceRetry && ![.saved, .dismissed].contains($0.state)
        }
        let hasPendingSourceRetry = batchItems.contains {
            $0.isSourceRetry && [.queued, .resolving].contains($0.state)
        }
        batches[index].totalCount = placeItems.count
        batches[index].processedCount = placeItems.count - pendingPlaceCount
        batches[index].updatedAt = .now

        if batches[index].state != .cancelled {
            if pendingPlaceCount > 0 || hasPendingSourceRetry {
                batches[index].state = .processing
            } else if terminalPlaceCount == placeItems.count && !hasActiveSourceRetry {
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
        if persistenceDeferralDepth > 0 {
            persistenceRequestedWhileDeferred = true
            return
        }
        do {
            // A resolver upgrade is intentionally staged in memory. Persist each group's
            // previous rows until its network-dependent refresh commits so an unrelated
            // save or app termination cannot make a temporary placeholder durable.
            let durableItems = items.flatMap { item in
                replacedSocialItemsByPlaceholderID[item.id] ?? [item]
            }
            try persistence.save(
                PlaceImportSnapshot(
                    ownerUserID: ownerUserID,
                    batches: batches,
                    items: durableItems
                )
            )
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

    private func normalizedWords(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func shouldUpgradeResolution(for item: PlaceImportItem) -> Bool {
        let requiredVersion = item.source == .googleMaps ? 4 : PlaceImportItem.currentResolverVersion
        let upgradeableStates: Set<PlaceImportItemState> = [.instagram, .tiktok].contains(item.source)
            ? [.queued, .resolving, .ready, .ambiguous, .needsHelp, .failed]
            : [.ready, .ambiguous, .needsHelp, .failed]
        guard (item.resolverVersion ?? 0) < requiredVersion,
              [.googleMaps, .instagram, .tiktok].contains(item.source),
              upgradeableStates.contains(item.state)
        else { return false }
        return true
    }
}
