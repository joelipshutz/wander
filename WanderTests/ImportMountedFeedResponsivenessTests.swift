#if targetEnvironment(simulator)
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Wander

/// One integrated diagnostic sample, not a paired performance acceptance test.
/// The real Feed observes the same store whose import checkpoints mutate and save.
/// Includes Root's two import-reconciliation observers; earlier Feed-only samples
/// did not include this additional workload and are not directly comparable.
@MainActor
final class ImportMountedFeedResponsivenessTests: XCTestCase {
    func testFileImportKeepsMounted600EventFeedRenderingAndScrolling() async throws {
        let rowCount = 200
        let batchID = "mounted-import-batch"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mounted-feed-import-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("library.json")
        let importURL = directory.appendingPathComponent("imports.json")
        let persistence = WanderStorePersistence.coalescingFile(url: storeURL)
        defer { persistence.flush(); try? FileManager.default.removeItem(at: directory) }
        let suite = "mounted-feed-import-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WanderStore(fixtures: .performanceScale(), persistence: persistence)
        let ownerID = store.currentUser.id
        let followed = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
        let fixtureDate = Date.now
        let page = fixtureFeedPage(from: followed, store: store, relativeTo: fixtureDate)
        #if DEBUG
        try assertFixtureParity(page,
            store.livePerformanceFixtureFeedPage(from: followed, relativeTo: fixtureDate))
        #endif
        let pageIDs = page.activity.map(\.id)
        XCTAssertEqual(pageIDs.count, 600)
        XCTAssertEqual(Set(pageIDs).count, 600)
        let backend = WanderBackend(feedRepository: ImportMountedFeedRepository(page: page),
            placePhotoRepository: ImportMountedFeedPhotos(),
            placePhotoDataDiskCache: .disabled)
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedIn(
            AuthSession(userID: ownerID, displayName: store.currentUser.displayName,
                handle: store.currentUser.handle))))
        await auth.refreshSession()
        XCTAssertTrue(auth.isSessionValidated)
        store.selectLiveFeedQuery(LiveFeedQuery())
        let loaded = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(loaded)
        store.revealFeedActivity(try XCTUnwrap(pageIDs.last))
        let groupIDs = store.visibleLiveFeedSections.flatMap(\.groups).map(\.id)
        let eventIDs = store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id)
        XCTAssertEqual(groupIDs.count, 600)
        XCTAssertEqual(Set(eventIDs), Set(pageIDs))

        let importPersistence = FilePlaceImportPersistence(fileURL: importURL)
        let importSnapshot = importFixture(rowCount: rowCount, batchID: batchID, ownerID: ownerID)
        try importPersistence.save(importSnapshot)
        let importStore = PlaceImportStore(persistence: importPersistence, resolver: ImportMountedFeedResolver())
        let expectedItemIDs = (0..<rowCount).map { "mounted-item-\($0)" }
        let initialSaveCount = store.userPlaces.count
        let initialListItemCount = store.placeListItems.count
        let initialVisitIDs = store.placeVisits.map(\.id)
        let probe = ImportMountedFeedProbe(initialSaveCount: initialSaveCount,
            finalSaveCount: initialSaveCount + rowCount)

        let scene = try await foregroundScene()
        let originalWindow = try XCTUnwrap(scene.keyWindow)
        let originalRoot = try XCTUnwrap(originalWindow.rootViewController)
        let wasHidden = originalWindow.isHidden
        let wasKey = originalWindow.isKeyWindow
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let root = ImportMountedFeedRoot(store: store, importStore: importStore,
            isSessionValidated: auth.isSessionValidated, activityIDs: Set(pageIDs), probe: probe)
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(PushNotificationManager(userDefaults: defaults))
            .environmentObject(FirstVisitWalkthroughCoordinator(isEnabled: false))
            .environmentObject(ActivityNavigationCoordinator())
            .environmentObject(PlacePlanInvitationInbox())
            .environmentObject(NotificationBadgeStore(defaults: defaults))
            .environmentObject(FollowNotificationInbox())
            .environmentObject(ActivityNotificationInbox())
            .environmentObject(PlaceSaveDraftStore(persistence: .ephemeral))
            .environmentObject(ProductUpsellCoordinator(userDefaults: defaults))
            .environment(\.scenePhase, .active)
            .dynamicTypeSize(.large)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        originalWindow.isHidden = true
        originalWindow.rootViewController = nil
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalWindow.rootViewController = originalRoot
            originalWindow.isHidden = wasHidden
            if wasKey { originalWindow.makeKey() }
        }
        host.view.frame = bounds
        _ = host.sizeThatFits(in: bounds.size)
        window.layoutIfNeeded()
        let mountDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var mountedScroll: UIScrollView?
        while ContinuousClock.now < mountDeadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            mountedScroll = verticalScroll(in: host.view)
            if probe.didAppear, let scroll = mountedScroll,
               scroll.contentSize.height > scroll.bounds.height * 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let scroll = try XCTUnwrap(mountedScroll)
        XCTAssertTrue(probe.didAppear)
        XCTAssertGreaterThan(scroll.bounds.height, 300)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height * 3)
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), pageIDs)
        persistence.flush()

        let display = ImportFeedDisplayDriver(scroll: scroll, window: window)
        display.start()
        defer { display.stop() }
        let heartbeat = ImportFeedHeartbeat()
        let heartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                heartbeat.tick()
                do { try await Task.sleep(for: .milliseconds(1)) }
                catch { return }
            }
        }
        defer { heartbeatTask.cancel() }
        try await waitForTicks { display.tickCount > 0 && heartbeat.tickCount > 0 }
        display.beginMeasurement()
        heartbeat.beginMeasurement()
        probe.isImporting = true
        var libraryCheckpointAcknowledgments = 0
        let started = ProcessInfo.processInfo.systemUptime
        let result = await PlaceImportAutoSaveCoordinator.process(batchIDs: [batchID],
            importStore: importStore, store: store, expectedUserID: ownerID,
            afterLibraryCheckpoint: { libraryCheckpointAcknowledgments += 1 },
            isAuthorized: { true })
        persistence.flush()
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        probe.isImporting = false
        let movingTicksDuringImport = display.movingTicks
        let ticksDuringImport = display.tickCount
        let heartbeatTicksDuringImport = heartbeat.tickCount
        // Include the first delivery after completion when observing gaps, so
        // an uninterrupted main-thread stall cannot disappear from the sample.
        display.isImporting = false
        try await waitForTicks {
            display.tickCount > ticksDuringImport && heartbeat.tickCount > heartbeatTicksDuringImport
        }
        display.stop()
        heartbeatTask.cancel()
        await heartbeatTask.value
        let displayGapMS = display.maximumGapMS
        let heartbeatGapMS = heartbeat.maximumGapMS
        let displayGaps = ImportFeedGapSummary(display.gapsMS)
        let heartbeatGaps = ImportFeedGapSummary(heartbeat.gapsMS)

        XCTAssertGreaterThan(ticksDuringImport, 0, "The native display link must run during the import.")
        XCTAssertGreaterThan(libraryCheckpointAcknowledgments, 0)
        XCTAssertEqual(displayGaps.count, display.tickCount)
        XCTAssertEqual(heartbeatGaps.count, heartbeat.tickCount)
        XCTAssertGreaterThan(movingTicksDuringImport, 0, "The actual Feed must scroll while saves are being checkpointed.")
        XCTAssertGreaterThan(probe.intermediateRenderedSaveCounts.count, 0,
            "Mounted SwiftUI must render partially completed saves before the import finishes.")
        XCTAssertGreaterThan(probe.revisionReconciliationsDuringImport, 0,
            "The production reconciliation path must run for library revisions during import.")
        XCTAssertGreaterThan(probe.itemReconciliationsDuringImport, 0,
            "The production reconciliation path must run for import item changes during import.")
        XCTAssertGreaterThan(display.maximumOffset - display.minimumOffset, 0)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        let renderDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while probe.lastRenderedSaveCount != initialSaveCount + rowCount, ContinuousClock.now < renderDeadline {
            try await Task.sleep(for: .milliseconds(10))
            window.layoutIfNeeded()
        }
        XCTAssertEqual(probe.lastRenderedSaveCount, initialSaveCount + rowCount)
        XCTAssertTrue(scene.keyWindow === window)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height * 3)
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), pageIDs)
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).map(\.id), groupIDs)
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id), eventIDs)
        XCTAssertEqual(result.batchIDs, [batchID])
        XCTAssertEqual(result.addedCount, rowCount)
        XCTAssertEqual(result.existingCount, 0)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertEqual(result.sourceRetryCount, 0)
        XCTAssertTrue(result.retryBatchIDs.isEmpty)
        XCTAssertEqual(store.userPlaces.count, initialSaveCount + rowCount)
        XCTAssertEqual(store.placeListItems.count, initialListItemCount + rowCount)
        XCTAssertEqual(store.placeVisits.map(\.id), initialVisitIDs)
        let batch = try XCTUnwrap(importStore.batches.first)
        let receipt = try XCTUnwrap(batch.receipt)
        XCTAssertNotNil(batch.automaticSaveCompletedAt)
        XCTAssertEqual(receipt.entries.map(\.itemID), expectedItemIDs)
        XCTAssertTrue(receipt.entries.allSatisfy { $0.outcome == .added && $0.status == .wannaGo })
        XCTAssertTrue(importStore.items.allSatisfy { $0.state == .saved && $0.savedUserPlaceID != nil })
        XCTAssertNil(importStore.persistenceError)
        let destinationID = try XCTUnwrap(batch.destinationListID)
        let members = store.placeListItems.filter { $0.listID == destinationID && $0.deletedAt == nil }
        let savedIDs = Set(receipt.entries.compactMap(\.userPlaceID))
        XCTAssertEqual(members.count, rowCount)
        XCTAssertEqual(savedIDs.count, rowCount)
        XCTAssertEqual(Set(members.compactMap(\.ownerUserPlaceID)), savedIDs)
        XCTAssertTrue(members.allSatisfy { $0.senderNotificationPolicy == .silent })
        XCTAssertTrue(store.userPlaces.filter { savedIDs.contains($0.id) }.allSatisfy {
            SenderNotificationPolicy.restored(from: $0.senderNotificationJSON) == .silent
        })
        let notification = try XCTUnwrap(store.importNotificationCommits.first { $0.selectedItemIDs == Set(expectedItemIDs) })
        XCTAssertTrue(notification.silent)
        XCTAssertTrue(notification.locallyComplete)
        XCTAssertTrue(store.automaticImportCheckpoints.isEmpty)

        // Read actual atomic files only after timed callbacks have stopped.
        let libraryBytes = try Data(contentsOf: storeURL)
        let persisted = try JSONDecoder().decode(WanderStoreSnapshot.self, from: libraryBytes)
        let current = WanderStoreSnapshot(store: store)
        XCTAssertEqual(persisted.currentUser, current.currentUser)
        XCTAssertEqual(persisted.places, current.places)
        XCTAssertEqual(persisted.userPlaces, current.userPlaces)
        XCTAssertEqual(persisted.placeVisits, current.placeVisits)
        XCTAssertEqual(persisted.placeLists, current.placeLists)
        XCTAssertEqual(persisted.placeListItems, current.placeListItems)
        XCTAssertEqual(persisted.importNotificationCommits, current.importNotificationCommits)
        XCTAssertEqual(persisted.automaticImportCheckpoints, current.automaticImportCheckpoints)
        var persistedFields = try XCTUnwrap(JSONSerialization.jsonObject(with: libraryBytes) as? [String: Any])
        var currentFields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        // Capture time is the only intentional difference from this later
        // oracle snapshot. Compare every other persisted field, not just saves.
        persistedFields.removeValue(forKey: "savedAt")
        currentFields.removeValue(forKey: "savedAt")
        XCTAssertEqual(NSDictionary(dictionary: persistedFields), NSDictionary(dictionary: currentFields))
        let restored = try FilePlaceImportPersistence(fileURL: importURL).load()
        let expected = PlaceImportSnapshot(ownerUserID: ownerID, batches: importStore.batches, items: importStore.items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(restored, try decoder.decode(PlaceImportSnapshot.self, from: encoder.encode(expected)))
        XCTAssertEqual(restored.batches.first?.receipt?.entries.map(\.itemID), expectedItemIDs)
        #if DEBUG
        try await assertPhotoFixtureParity(page.activity.compactMap(\.place))
        #endif
        let attachment = XCTAttachment(string:
            "REC675 mounted_feed_import sample_count=1 rows=200 feed_events=600 host=393x852 replay=false root_import_reconciliation=true heartbeat_sleep_ms=1 requested_display_hz=60 "
            + "scheduling_variant=default_yield requested_between_chunks_sleep_ms=0 "
            + "initial_library_saves=\(initialSaveCount) elapsed_ms=\(elapsedMS) "
            + "display_ticks_during_import=\(ticksDuringImport) moving_ticks_during_import=\(movingTicksDuringImport) "
            + "display_max_gap_ms=\(displayGapMS) heartbeat_max_gap_ms=\(heartbeatGapMS) "
            + "display_p50_gap_ms=\(displayGaps.p50) display_p95_gap_ms=\(displayGaps.p95) display_gap_samples=\(displayGaps.count) "
            + "heartbeat_p50_gap_ms=\(heartbeatGaps.p50) heartbeat_p95_gap_ms=\(heartbeatGaps.p95) heartbeat_gap_samples=\(heartbeatGaps.count) percentile_method=nearest_rank gaps_include_post_completion_delivery=true "
            + "heartbeat_ticks_during_import=\(heartbeatTicksDuringImport) native_layout_ms=\(display.layoutMS) "
            + "library_checkpoint_acknowledgments=\(libraryCheckpointAcknowledgments) "
            + "intermediate_rendered_save_counts=\(probe.intermediateRenderedSaveCounts.count) "
            + "revision_reconciliations=\(probe.revisionReconciliationsDuringImport) item_reconciliations=\(probe.itemReconciliationsDuringImport) "
            + "offset_range=\(display.maximumOffset - display.minimumOffset) durable_receipts=\(receipt.entries.count)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForTicks(_ delivered: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !delivered(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(delivered(), "The foreground main actor and display link must deliver the measurement boundary.")
    }

    private func foregroundScene() async throws -> UIWindowScene {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) { return scene }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.bounds.height > 300,
               scroll.contentSize.height > scroll.bounds.height { candidates.append(scroll) }
            view.subviews.forEach(visit)
        }
        visit(view)
        return candidates.max { $0.bounds.height < $1.bounds.height }
    }

    private func importFixture(rowCount: Int, batchID: String, ownerID: String) -> PlaceImportSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<rowCount).map { index in
            let candidate = PlaceCandidate(id: "mounted-candidate-\(index)", name: "Mounted import fixture \(index)",
                category: "park", latitude: 33 + Double(index / 20) * 0.01,
                longitude: -117 + Double(index % 20) * 0.01,
                sourceProvider: "mounted-fixture", sourceProviderPlaceID: "mounted-provider-\(index)", confidence: 1)
            return PlaceImportItem(id: "mounted-item-\(index)", batchID: batchID, source: .googleMaps,
                seed: PlaceImportSeed(id: "mounted-seed-\(index)", rawText: candidate.name,
                    nameHint: candidate.name, areaHint: nil, sourceURLString: nil, sourceLine: index),
                state: .ready, candidates: [candidate], selectedCandidateID: candidate.id,
                createdAt: timestamp, updatedAt: timestamp)
        }
        let batch = PlaceImportBatch(id: batchID, source: .googleMaps, sourceName: "Mounted import fixture",
            sourceListName: "Mounted import list", createdAt: timestamp, updatedAt: timestamp, state: .ready,
            totalCount: rowCount, processedCount: rowCount, automaticSaveRequested: true, requestedStatus: .wannaGo)
        return PlaceImportSnapshot(ownerUserID: ownerID, batches: [batch], items: Array(items.reversed()))
    }

    /// The identical fictional page used by the Debug Live fixture, kept in
    /// tests so ordinary Release can measure it without widening app policy.
    private func fixtureFeedPage(from followedPlaces: [VisiblePlace], store: WanderStore,
                                 relativeTo now: Date) -> FollowedFeedPage {
        var seen = Set<String>()
        var distinct: [VisiblePlace] = []
        for source in followedPlaces.sorted(by: { $0.place.id < $1.place.id }) {
            guard seen.insert(source.place.id).inserted else { continue }
            distinct.append(source)
            if distinct.count == 300 { break }
        }
        var events: [FeedActivity] = []
        events.reserveCapacity(distinct.count * 2)
        for (index, source) in distinct.enumerated() {
            let original = source.place
            let latitude: Double = 34.075 + Double(index / 20 - 7) * 0.002
            let longitude: Double = -118.285 + (Double(index % 20) - 9.5) * 0.002
            let place = LocalPlace(localID: original.localID, serverID: original.serverID,
                canonicalName: original.canonicalName, category: original.category,
                primaryCategory: original.primaryCategory, subcategory: original.subcategory,
                address: original.address, locality: "Los Angeles", region: "CA", country: "US",
                latitude: latitude, longitude: longitude,
                sourceProvider: original.sourceProvider, sourceProviderPlaceID: original.sourceProviderPlaceID,
                syncState: .synced)
            let visible = VisiblePlace(id: source.id, place: place, userPlace: source.userPlace,
                owner: source.owner, attributes: source.attributes)
            let actor = store.shell(for: source.owner)
            let note = "A fictional place memory for the Live scale review. "
                + String(repeating: "A useful stop worth remembering. ", count: 1 + index % 4)
            for occurrence in 0..<2 {
                let eventID = String(format: "live-perf-%03d-%d", index, occurrence)
                let kind: FeedActivityKind = occurrence == 0 ? .placeWannaGo : .placeBeen
                let secondsAgo: TimeInterval = 3_600 + Double(index * 30) + Double(occurrence * 7_200)
                let occurredAt = now.addingTimeInterval(-secondsAgo)
                events.append(FeedActivity(id: eventID, kind: kind, actor: actor,
                    place: visible, occurredAt: occurredAt, note: note))
            }
        }
        return FollowedFeedPage(activity: FeedPresentation.newestFirst(events, relativeTo: now),
            featuredPlaces: [], nextCursor: nil, fetchedAt: now)
    }

    #if DEBUG
    private func assertPhotoFixtureParity(_ places: [VisiblePlace]) async throws {
        let actual = ImportMountedFeedPhotos()
        let reference = MapCapturePlacePhotoRepository(launchArguments: [])
        var seenTiles = Set<Int>()
        for place in places {
            let request = FeedPlacePhotoPolicy.request(for: place)
            guard seenTiles.insert(MapCapturePlacePhotoRepository.tileIndex(for: request.lookupKey)).inserted else { continue }
            let actualPhoto = try await actual.photo(for: request)
            let referencePhoto = try await reference.photo(for: request)
            XCTAssertEqual(actualPhoto, referencePhoto)
            let actualBytes = try await actual.imageData(for: actualPhoto)
            let referenceBytes = try await reference.imageData(for: referencePhoto)
            XCTAssertEqual(actualBytes, referenceBytes)
            let actualUserPhoto = try await actual.visibleUserPhoto(for: request)
            let referenceUserPhoto = try await reference.visibleUserPhoto(for: request)
            XCTAssertEqual(actualUserPhoto, referenceUserPhoto)
            try await actual.validateAccess(to: actualUserPhoto)
            try await reference.validateAccess(to: referenceUserPhoto)
            if seenTiles.count == 4 { break }
        }
        XCTAssertEqual(seenTiles.count, 4)
    }

    private func assertFixtureParity(_ actual: FollowedFeedPage, _ reference: FollowedFeedPage) throws {
        XCTAssertEqual(actual.activity.count, reference.activity.count)
        XCTAssertEqual(actual.nextCursor, reference.nextCursor)
        XCTAssertEqual(actual.fetchedAt, reference.fetchedAt)
        XCTAssertTrue(actual.featuredPlaces.isEmpty)
        XCTAssertTrue(reference.featuredPlaces.isEmpty)
        for (actual, reference) in zip(actual.activity, reference.activity) {
            XCTAssertEqual(actual.id, reference.id)
            XCTAssertEqual(actual.kind, reference.kind)
            XCTAssertEqual(actual.actor, reference.actor)
            XCTAssertEqual(actual.occurredAt, reference.occurredAt)
            XCTAssertEqual(actual.note, reference.note)
            XCTAssertEqual(actual.rating, reference.rating)
            XCTAssertEqual(actual.media, reference.media)
            XCTAssertEqual(actual.sharedVisit, reference.sharedVisit)
            XCTAssertEqual(actual.list, reference.list)
            let place = try XCTUnwrap(actual.place)
            let expected = try XCTUnwrap(reference.place)
            XCTAssertEqual(place.id, expected.id)
            XCTAssertTrue(place.userPlace === expected.userPlace)
            XCTAssertTrue(place.owner === expected.owner)
            XCTAssertEqual(place.attributes.map(ObjectIdentifier.init), expected.attributes.map(ObjectIdentifier.init))
            XCTAssertEqual(place.communitySaveCount, expected.communitySaveCount)
            func fields(_ value: LocalPlace) throws -> NSDictionary {
                let data = try JSONEncoder().encode(WanderStoreSnapshot.PlaceRecord(value))
                var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                // Both builders use the same LocalPlace defaults. Only their
                // construction instants differ; event times are compared above.
                for key in ["createdAt", "updatedAt", "localUpdatedAt"] { fields.removeValue(forKey: key) }
                return NSDictionary(dictionary: fields)
            }
            XCTAssertEqual(try fields(place.place), try fields(expected.place))
        }
    }
    #endif
}

@MainActor
private final class ImportMountedFeedProbe {
    let initialSaveCount: Int
    let finalSaveCount: Int
    var didAppear = false
    var isImporting = false
    var lastRenderedSaveCount = 0
    var intermediateRenderedSaveCounts = Set<Int>()
    var revisionReconciliationsDuringImport = 0
    var itemReconciliationsDuringImport = 0
    init(initialSaveCount: Int, finalSaveCount: Int) {
        self.initialSaveCount = initialSaveCount
        self.finalSaveCount = finalSaveCount
    }
    func record(saveCount: Int) {
        lastRenderedSaveCount = saveCount
        if isImporting && saveCount > initialSaveCount && saveCount < finalSaveCount {
            intermediateRenderedSaveCounts.insert(saveCount)
        }
    }
}

private struct ImportMountedFeedRoot: View {
    @ObservedObject var store: WanderStore
    @ObservedObject var importStore: PlaceImportStore
    let isSessionValidated: Bool
    let activityIDs: Set<String>
    let probe: ImportMountedFeedProbe
    var body: some View {
        let _ = probe.record(saveCount: store.userPlaces.count)
        FeedScreen(isFeedTabActive: true, isEmbedded: true, showsInviteEntry: false,
            isEmbeddedFeedVisible: true, filteredActivityIDs: activityIDs)
            .onAppear { probe.didAppear = true }
            .onChange(of: store.presentationRevision) { _, _ in
                guard isSessionValidated else { return }
                if probe.isImporting { probe.revisionReconciliationsDuringImport += 1 }
                store.reconcilePlaceImportDuplicates(in: importStore)
            }
            .onChange(of: importStore.items) { _, _ in
                guard isSessionValidated else { return }
                if probe.isImporting { probe.itemReconciliationsDuringImport += 1 }
                store.reconcilePlaceImportDuplicates(in: importStore)
            }
    }
}

@MainActor
private final class ImportMountedFeedRepository: FeedRepository {
    let page: FollowedFeedPage
    init(page: FollowedFeedPage) { self.page = page }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage { page }
    func liveFeed(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        onContent(page)
        return page
    }
}

/// Exact bundled-photo behavior of MapCapturePlacePhotoRepository with empty
/// launch arguments. Kept test-local because that app fixture is Debug-only.
@MainActor
private struct ImportMountedFeedPhotos: PlacePhotoRepository {
    private static let assetName = "PlaceCarouselPhotos"
    private static let tileCount = 4
    private static var croppedImageCache: [Int: UIImage] = [:]
    private static var encodedImageCache: [Int: Data] = [:]

    func validateAccess(to photo: PlacePhoto) async throws {
        guard photo.requiresAccessCheck else { return }
        guard photo.provider == "visit_photo" else { throw WanderRemoteError.notConfigured }
        let isCaptureTile = (0..<Self.tileCount).contains { index in
            photo.providerPlaceID == "capture-visit-\(index)"
                && photo.photoURLString == "capture://place-carousel/\(index)"
        }
        guard isCaptureTile, photo.storageBucket == nil, photo.storagePath == nil,
              photo.localAssetRef == nil else { throw WanderRemoteError.notConfigured }
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        if request.skipsGooglePlacesLookup {
            return try await visibleUserPhoto(for: request)
        }
        return photo(
            provider: "google_places",
            providerPlaceID: "capture-google-\(Self.tileIndex(for: request.lookupKey))",
            request: request
        )
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        photo(
            provider: "visit_photo",
            providerPlaceID: "capture-visit-\(Self.tileIndex(for: request.lookupKey))",
            request: request
        )
    }

    func visiblePhotoGalleryPage(placeIDs: [String], after cursor: PlacePhotoGalleryCursor?,
                                 limit: Int) async throws -> PlacePhotoGalleryPage {
        PlacePhotoGalleryPage(items: [], nextCursor: nil, hasMore: false)
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        let tileIndex = Self.tileIndex(from: photo.providerPlaceID)
        if let data = Self.encodedImageCache[tileIndex] {
            return data
        }
        guard let image = Self.croppedAssetImage(tileIndex: tileIndex),
              let data = image.pngData()
        else {
            throw WanderRemoteError.invalidResponse("Map capture photo asset is unavailable")
        }
        Self.encodedImageCache[tileIndex] = data
        return data
    }

    static func tileIndex(for key: String) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(tileCount))
    }

    private func photo(
        provider: String,
        providerPlaceID: String,
        request: PlacePhotoRequest
    ) -> PlacePhoto {
        let tileIndex = Self.tileIndex(from: providerPlaceID)
        let tileSize = Self.croppedAssetImage(tileIndex: tileIndex)?.size
        let isCoffeeShop = request.name.localizedCaseInsensitiveContains("coffee")
        return PlacePhoto(
            provider: provider,
            providerPlaceID: providerPlaceID,
            providerPrimaryType: isCoffeeShop ? "coffee_shop" : "restaurant",
            providerTypes: isCoffeeShop
                ? ["coffee_shop", "cafe", "point_of_interest"]
                : ["restaurant", "food", "point_of_interest"],
            providerRating: provider == "google_places" ? 4.7 : nil,
            providerUserRatingCount: provider == "google_places" ? 138 : nil,
            providerOpenNow: provider == "google_places" ? false : nil,
            providerNextOpenTimeString: provider == "google_places"
                ? "2026-08-18T15:00:00Z"
                : nil,
            providerUTCOffsetMinutes: provider == "google_places" ? -420 : nil,
            photoURLString: "capture://place-carousel/\(tileIndex)",
            width: tileSize.map { Int($0.width) },
            height: tileSize.map { Int($0.height) },
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: provider == "google_places"
                ? Self.googleMapsSourceURLString(for: request.name)
                : nil,
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
    }

    private static func tileIndex(from providerPlaceID: String) -> Int {
        guard let suffix = providerPlaceID.split(separator: "-").last,
              let index = Int(suffix)
        else {
            return 0
        }
        return max(0, min(index, tileCount - 1))
    }

    private static func croppedAssetImage(tileIndex: Int) -> UIImage? {
        let normalizedIndex = max(0, min(tileIndex, tileCount - 1))
        if let cachedImage = croppedImageCache[normalizedIndex] {
            return cachedImage
        }
        guard let sourceImage = UIImage(named: assetName),
              let sourceCGImage = sourceImage.cgImage
        else {
            return nil
        }

        let tileWidth = sourceCGImage.width / 2
        let tileHeight = sourceCGImage.height / 2
        let cropRect = CGRect(
            x: (normalizedIndex % 2) * tileWidth,
            y: (normalizedIndex / 2) * tileHeight,
            width: tileWidth,
            height: tileHeight
        )
        guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else {
            return nil
        }
        let image = UIImage(
            cgImage: croppedCGImage,
            scale: sourceImage.scale,
            orientation: sourceImage.imageOrientation
        )
        croppedImageCache[normalizedIndex] = image
        return image
    }

    private static func googleMapsSourceURLString(for placeName: String) -> String? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: placeName)
        ]
        return components?.url?.absoluteString
    }
}

@MainActor
private struct ImportMountedFeedResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Pre-resolved mounted fixtures must not invoke a network resolver")
        return .needsHelp("Unexpected fixture resolution")
    }
}

/// Sorting is done only after timed callbacks stop. Keep every observed gap;
/// percentile calculation never samples away a long scheduling stall.
private struct ImportFeedGapSummary {
    let count: Int
    let p50: Double
    let p95: Double

    init(_ gaps: [Double]) {
        let sorted = gaps.sorted()
        count = sorted.count
        if sorted.isEmpty {
            p50 = .nan
            p95 = .nan
        } else {
            p50 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.50)) - 1)]
            p95 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        }
    }
}

@MainActor
private final class ImportFeedHeartbeat {
    private var previous: Double?
    private(set) var tickCount = 0
    private(set) var maximumGapMS = 0.0
    private(set) var gapsMS: [Double] = []
    func beginMeasurement() {
        tickCount = 0; maximumGapMS = 0; gapsMS.removeAll(keepingCapacity: true)
        previous = ProcessInfo.processInfo.systemUptime
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous {
            let gap = (now - previous) * 1_000
            maximumGapMS = max(maximumGapMS, gap)
            gapsMS.append(gap)
        }
        previous = now
        tickCount += 1
    }
}

@MainActor
private final class ImportFeedDisplayDriver: NSObject {
    let scroll: UIScrollView
    let window: UIWindow
    var isImporting = false
    private var link: CADisplayLink?
    private var previous = 0.0
    private(set) var tickCount = 0
    private(set) var movingTicks = 0
    private(set) var layoutMS = 0.0
    private(set) var maximumGapMS = 0.0
    private(set) var gapsMS: [Double] = []
    private(set) var minimumOffset = CGFloat.greatestFiniteMagnitude
    private(set) var maximumOffset = -CGFloat.greatestFiniteMagnitude
    init(scroll: UIScrollView, window: UIWindow) { self.scroll = scroll; self.window = window }
    func start() {
        previous = ProcessInfo.processInfo.systemUptime
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func beginMeasurement() {
        previous = ProcessInfo.processInfo.systemUptime
        tickCount = 0; movingTicks = 0; layoutMS = 0; maximumGapMS = 0
        gapsMS.removeAll(keepingCapacity: true)
        minimumOffset = scroll.contentOffset.y; maximumOffset = scroll.contentOffset.y
        isImporting = true
    }
    @objc private func tick(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        let gap = (now - previous) * 1_000
        maximumGapMS = max(maximumGapMS, gap)
        gapsMS.append(gap)
        previous = now
        tickCount += 1
        guard isImporting else { return }
        // Repeated down/up native motion avoids pagination-end effects. No AX,
        // store projections, or per-row assertions run in this timed callback.
        let phase = tickCount % 180
        let step = phase <= 90 ? phase : 180 - phase
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let target = min(bottom, top + CGFloat(step) * 64)
        let old = scroll.contentOffset.y
        scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        let actual = scroll.contentOffset.y
        if abs(actual - old) > 1 { movingTicks += 1 }
        minimumOffset = min(minimumOffset, actual)
        maximumOffset = max(maximumOffset, actual)
        layoutMS += (ProcessInfo.processInfo.systemUptime - now) * 1_000
    }
    func stop() { link?.invalidate(); link = nil; isImporting = false }
}
#endif
