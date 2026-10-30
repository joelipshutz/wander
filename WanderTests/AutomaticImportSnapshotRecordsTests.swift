import Combine
import Foundation
import SwiftData
import XCTest
@testable import Wander

@MainActor
final class AutomaticImportSnapshotRecordsTests: XCTestCase {
    func testEveryPlaceRecordFieldIsObservedAndRecapturedWithoutReadingUnchangedRows() throws {
        let mutations: [(String, (LocalPlace) -> Void)] = [
            ("localID", { $0.localID = "changed-local" }),
            ("serverID", { $0.serverID = "changed-server" }),
            ("canonicalName", { $0.canonicalName = "Changed name" }),
            ("category", { $0.category = "raw-category" }),
            ("primaryCategory", { $0.primaryCategory = "raw-primary" }),
            ("subcategory", { $0.subcategory = "raw-subcategory" }),
            ("categorySource", { $0.categorySource = "raw-source" }),
            ("categoryConfidence", { $0.categoryConfidence = 0.123 }),
            ("rawProviderType", { $0.rawProviderType = "raw-provider-type" }),
            ("address", { $0.address = "Changed address" }),
            ("locality", { $0.locality = "Changed locality" }),
            ("region", { $0.region = "Changed region" }),
            ("country", { $0.country = "Changed country" }),
            ("latitude", { $0.latitude = 36.123 }),
            ("longitude", { $0.longitude = -120.456 }),
            ("sourceProvider", { $0.sourceProvider = "changed-provider" }),
            ("sourceProviderPlaceID", { $0.sourceProviderPlaceID = "changed-provider-id" }),
            ("confidence", { $0.confidence = 0.234 }),
            ("websiteURLString", { $0.websiteURLString = "https://example.invalid/changed" }),
            ("phoneNumber", { $0.phoneNumber = "changed-phone" }),
            ("timeZoneIdentifier", { $0.timeZoneIdentifier = "Europe/London" }),
            ("actionLinksJSON", { $0.actionLinksJSON = "{\"changed\":true}" }),
            ("syncStateRaw", { $0.syncStateRaw = "unknown-sync-state" }),
            ("localUpdatedAt", { $0.localUpdatedAt = .distantFuture }),
            ("serverUpdatedAt", { $0.serverUpdatedAt = .distantFuture }),
            ("lastSyncError", { $0.lastSyncError = "changed-error" }),
            ("createdAt", { $0.createdAt = .distantFuture }),
            ("updatedAt", { $0.updatedAt = .distantFuture })
        ]
        XCTAssertEqual(Set(mutations.map(\.0)), Set(Mirror(reflecting:
            WanderStoreSnapshot.PlaceRecord(makePlace("schema"))).children.compactMap(\.label)),
            "A new DTO field must gain an observation regression")
        for (name, mutate) in mutations {
            let changed = makePlace("changed")
            let unchanged = makePlace("unchanged")
            let records = AutomaticImportSnapshotRecords()
            defer { records.finish() }
            let before = records.places([changed, unchanged])
            XCTAssertEqual(records.placeBuildCount, 2)
            mutate(changed)
            let actual = records.places([changed, unchanged])
            XCTAssertEqual(try bytes(actual), try bytes([changed, unchanged].map(WanderStoreSnapshot.PlaceRecord.init)), name)
            XCTAssertNotEqual(try bytes(before[0]), try bytes(actual[0]), name)
            XCTAssertEqual(records.placeBuildCount, 3, name)
            _ = records.places([changed, unchanged])
            XCTAssertEqual(records.placeBuildCount, 3, name)
        }
    }

    func testEveryUserPlaceRecordFieldIsObservedAndRecapturedWithoutReadingUnchangedRows() throws {
        let mutations: [(String, (LocalUserPlace) -> Void)] = [
            ("senderNotificationJSON", { $0.senderNotificationJSON = "{\"changed\":true}" }),
            ("localID", { $0.localID = "changed-local" }),
            ("serverID", { $0.serverID = "changed-server" }),
            ("userID", { $0.userID = "changed-owner" }),
            ("placeID", { $0.placeID = "changed-place" }),
            ("statusRaw", { $0.statusRaw = "unknown-status" }),
            ("note", { $0.note = "Changed note" }),
            ("ratingSignal", { $0.ratingSignal = "changed-signal" }),
            ("ratingScore", { $0.ratingScore = 0.123 }),
            ("recommendedScore", { $0.recommendedScore = 0.234 }),
            ("recommendedCount", { $0.recommendedCount = 91 }),
            ("categoryOverride", { $0.categoryOverride = "raw-category" }),
            ("subcategoryOverride", { $0.subcategoryOverride = "raw-subcategory" }),
            ("categoryOverrideSource", { $0.categoryOverrideSource = "raw-source" }),
            ("categoryOverrideConfidence", { $0.categoryOverrideConfidence = 0.345 }),
            ("viewerPrimaryCategory", { $0.viewerPrimaryCategory = "raw-primary" }),
            ("viewerSubcategory", { $0.viewerSubcategory = "raw-subcategory" }),
            ("viewerFoodType", { $0.viewerFoodType = "raw-food" }),
            ("visibilityRaw", { $0.visibilityRaw = "unknown-visibility" }),
            ("nearbyConfirmed", { $0.nearbyConfirmed = true }),
            ("visitedAt", { $0.visitedAt = .distantFuture }),
            ("savedAt", { $0.savedAt = .distantFuture }),
            ("plannedDate", { $0.plannedDate = .distantFuture }),
            ("isPrivateListCompanion", { $0.isPrivateListCompanion = true }),
            ("sourceType", { $0.sourceType = "changed-source" }),
            ("sourceArtifactID", { $0.sourceArtifactID = "changed-artifact" }),
            ("sourceUserPlaceID", { $0.sourceUserPlaceID = "changed-source-save" }),
            ("attributionUserID", { $0.attributionUserID = "changed-attribution" }),
            ("historicalWantNote", { $0.historicalWantNote = "Changed historical note" }),
            ("historicalWantAttributeAnswersJSON", { $0.historicalWantAttributeAnswersJSON = "[\"changed\"]" }),
            ("historicalWantTagsJSON", { $0.historicalWantTagsJSON = "[\"changed\"]" }),
            ("historicalWantedAt", { $0.historicalWantedAt = .distantFuture }),
            ("syncStateRaw", { $0.syncStateRaw = "unknown-sync-state" }),
            ("localUpdatedAt", { $0.localUpdatedAt = .distantFuture }),
            ("serverUpdatedAt", { $0.serverUpdatedAt = .distantFuture }),
            ("lastSyncError", { $0.lastSyncError = "changed-error" }),
            ("createdAt", { $0.createdAt = .distantFuture }),
            ("updatedAt", { $0.updatedAt = .distantFuture }),
            ("deletedAt", { $0.deletedAt = .distantFuture })
        ]
        XCTAssertEqual(Set(mutations.map(\.0)), Set(Mirror(reflecting:
            WanderStoreSnapshot.UserPlaceRecord(makeSave("schema"))).children.compactMap(\.label)))
        for (name, mutate) in mutations {
            let changed = makeSave("changed")
            let unchanged = makeSave("unchanged")
            let records = AutomaticImportSnapshotRecords()
            defer { records.finish() }
            let before = records.userPlaces([changed, unchanged])
            mutate(changed)
            let actual = records.userPlaces([changed, unchanged])
            XCTAssertEqual(try bytes(actual), try bytes([changed, unchanged].map(WanderStoreSnapshot.UserPlaceRecord.init)), name)
            XCTAssertNotEqual(try bytes(before[0]), try bytes(actual[0]), name)
            XCTAssertEqual(records.userPlaceBuildCount, 3, name)
            _ = records.userPlaces([changed, unchanged])
            XCTAssertEqual(records.userPlaceBuildCount, 3, name)
        }
    }

    func testOptionalNilTransitionsUnicodeAndSignedZeroPreserveExactRecords() throws {
        let place = makePlace("place")
        let save = makeSave("save")
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        let optionalStrings: [String?] = ["\u{00E9}", "e\u{0301}", nil, "restored"]
        let optionalNumbers: [Double?] = [0.0, -0.0, nil, 1.5]
        let optionalDates: [Date?] = [nil, .distantPast]
        let placeStrings: [ReferenceWritableKeyPath<LocalPlace, String?>] = [
            \.serverID, \.subcategory, \.rawProviderType, \.address, \.locality, \.region, \.country,
            \.sourceProviderPlaceID, \.websiteURLString, \.phoneNumber, \.timeZoneIdentifier, \.actionLinksJSON, \.lastSyncError
        ]
        let saveStrings: [ReferenceWritableKeyPath<LocalUserPlace, String?>] = [
            \.senderNotificationJSON, \.serverID, \.note, \.ratingSignal, \.categoryOverride, \.subcategoryOverride,
            \.categoryOverrideSource, \.viewerPrimaryCategory, \.viewerSubcategory, \.viewerFoodType,
            \.sourceArtifactID, \.sourceUserPlaceID, \.attributionUserID, \.historicalWantNote,
            \.historicalWantAttributeAnswersJSON, \.historicalWantTagsJSON, \.lastSyncError
        ]
        for path in placeStrings {
            for value in optionalStrings {
                _ = records.places([place])
                place[keyPath: path] = value
                XCTAssertEqual(try bytes(records.places([place])), try bytes([WanderStoreSnapshot.PlaceRecord(place)]))
            }
        }
        for path in saveStrings {
            for value in optionalStrings {
                _ = records.userPlaces([save])
                save[keyPath: path] = value
                XCTAssertEqual(try bytes(records.userPlaces([save])), try bytes([WanderStoreSnapshot.UserPlaceRecord(save)]))
            }
        }
        for value in ["\u{00E9}", "e\u{0301}"] {
            _ = records.places([place]); _ = records.userPlaces([save])
            place.canonicalName = value
            save.sourceType = value
            XCTAssertEqual(try bytes(records.places([place])), try bytes([WanderStoreSnapshot.PlaceRecord(place)]))
            XCTAssertEqual(try bytes(records.userPlaces([save])), try bytes([WanderStoreSnapshot.UserPlaceRecord(save)]))
        }
        for path in [\LocalPlace.latitude, \LocalPlace.longitude] {
            for value in [0.0, -0.0, 1.5] {
                _ = records.places([place])
                place[keyPath: path] = value
                let actual = records.places([place])[0]
                XCTAssertEqual(try bytes(actual), try bytes(WanderStoreSnapshot.PlaceRecord(place)))
                XCTAssertEqual(path == \LocalPlace.latitude ? actual.latitude.bitPattern : actual.longitude.bitPattern, value.bitPattern)
            }
        }
        let placeNumbers: [ReferenceWritableKeyPath<LocalPlace, Double?>] = [\.confidence, \.categoryConfidence]
        for path in placeNumbers {
            for value in optionalNumbers {
                _ = records.places([place]); place[keyPath: path] = value
                XCTAssertEqual(try bytes(records.places([place])), try bytes([WanderStoreSnapshot.PlaceRecord(place)]))
            }
        }
        let saveNumbers: [ReferenceWritableKeyPath<LocalUserPlace, Double?>] = [\.ratingScore, \.recommendedScore, \.categoryOverrideConfidence]
        for path in saveNumbers {
            for value in optionalNumbers {
                _ = records.userPlaces([save]); save[keyPath: path] = value
                XCTAssertEqual(try bytes(records.userPlaces([save])), try bytes([WanderStoreSnapshot.UserPlaceRecord(save)]))
            }
        }
        for value in optionalDates {
            _ = records.places([place]); place.serverUpdatedAt = value
            XCTAssertEqual(try bytes(records.places([place])), try bytes([WanderStoreSnapshot.PlaceRecord(place)]))
        }
        let saveDates: [ReferenceWritableKeyPath<LocalUserPlace, Date?>] = [
            \.visitedAt, \.plannedDate, \.historicalWantedAt, \.serverUpdatedAt, \.deletedAt
        ]
        for path in saveDates {
            for value in optionalDates {
                _ = records.userPlaces([save]); save[keyPath: path] = value
                XCTAssertEqual(try bytes(records.userPlaces([save])), try bytes([WanderStoreSnapshot.UserPlaceRecord(save)]))
            }
        }
    }

    func testArrayOrderDuplicateIDsRepeatedObjectsReplacementAndRemovalStayExact() throws {
        let first = makePlace("duplicate")
        let second = makePlace("duplicate")
        second.canonicalName = "Second object"
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        let initial = [first, second, first]
        XCTAssertEqual(try bytes(records.places(initial)), try bytes(initial.map(WanderStoreSnapshot.PlaceRecord.init)))
        XCTAssertEqual(records.placeBuildCount, 2)
        let reordered = [second, first, first]
        XCTAssertEqual(try bytes(records.places(reordered)), try bytes(reordered.map(WanderStoreSnapshot.PlaceRecord.init)))
        XCTAssertEqual(records.placeBuildCount, 2)
        let replacement = makePlace("duplicate")
        replacement.canonicalName = "Replacement object"
        XCTAssertEqual(try bytes(records.places([replacement, first])),
            try bytes([replacement, first].map(WanderStoreSnapshot.PlaceRecord.init)))
        XCTAssertEqual(records.placeBuildCount, 3)
        XCTAssertEqual(records.retainedRecordCount, 2)
        // Repeated parent objects and distinct objects with identical IDs must
        // also retain array multiplicity rather than collapsing by save ID.
        let a = makeSave("duplicate")
        let b = makeSave("duplicate")
        b.note = "Second save"
        for saves in [[a, b, a], [b, a], [makeSave("duplicate"), b], []] {
            XCTAssertEqual(try bytes(records.userPlaces(saves)), try bytes(saves.map(WanderStoreSnapshot.UserPlaceRecord.init)))
        }
        _ = records.places([])
        XCTAssertEqual(records.retainedRecordCount, 0)
    }

    func testPruningAndFinishReleaseModelsAndDoNotRetainRegistrations() throws {
        var first: LocalPlace? = makePlace("first")
        var second: LocalPlace? = makePlace("second")
        weak var weakFirst = first
        weak var weakSecond = second
        let records = AutomaticImportSnapshotRecords()
        _ = records.places([try XCTUnwrap(first), try XCTUnwrap(second)])
        first = nil
        XCTAssertNotNil(weakFirst)
        _ = records.places([try XCTUnwrap(second)])
        XCTAssertNil(weakFirst, "Pruned entries must cancel observations and release models")
        second = nil
        XCTAssertNotNil(weakSecond)
        records.finish()
        records.finish()
        XCTAssertNil(weakSecond)
        XCTAssertEqual(records.retainedRecordCount, 0)
        let later = makePlace("later")
        let reads = records.placeBuildCount
        XCTAssertEqual(records.places([later]), [WanderStoreSnapshot.PlaceRecord(later)])
        later.canonicalName = "Changed after finish"
        XCTAssertEqual(records.places([later]), [WanderStoreSnapshot.PlaceRecord(later)])
        XCTAssertEqual(records.placeBuildCount, reads, "Finished helpers use fresh, unretained records")
    }

    func testManagedModelsInvalidateBeforeTheNextCapture() throws {
        let container = try ModelContainer(for: LocalPlace.self, LocalUserPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let place = makePlace("managed")
        let save = makeSave("managed")
        container.mainContext.insert(place)
        container.mainContext.insert(save)
        try container.mainContext.save()
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        _ = records.places([place]); _ = records.userPlaces([save])
        place.address = "Managed raw edit"
        save.note = "Managed raw edit"
        XCTAssertEqual(records.places([place]), [WanderStoreSnapshot.PlaceRecord(place)])
        XCTAssertEqual(records.userPlaces([save]), [WanderStoreSnapshot.UserPlaceRecord(save)])
        XCTAssertEqual(records.placeBuildCount, 2)
        XCTAssertEqual(records.userPlaceBuildCount, 2)
        try container.mainContext.save()
        XCTAssertEqual(records.places([place]), [WanderStoreSnapshot.PlaceRecord(place)])
        XCTAssertEqual(records.userPlaces([save]), [WanderStoreSnapshot.UserPlaceRecord(save)])
    }

    func testContextCapturesFullSchemaAndOnlyRebuildsChangedModelsAcrossCheckpoints() async throws {
        let probe = SnapshotRecordCheckpointProbe()
        let store = WanderStore(fixtures: .performanceScale(), persistence: probe.persistence)
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        try await store.performCheckpointedImportMutationsAsync(using: context) {}
        let placeCount = store.places.count
        let saveCount = store.userPlaces.count
        XCTAssertEqual(context.snapshotPlaceBuildCount, placeCount)
        XCTAssertEqual(context.snapshotUserPlaceBuildCount, saveCount)
        try assertSnapshot(try XCTUnwrap(probe.snapshots.last), equalsFresh: store)
        store.places[0].address = "Raw edit between chunks"
        store.userPlaces[0].note = "Raw edit between chunks"
        store.placeAttributes[0].valueJSON = "\"Always captured fresh\""
        try await store.performCheckpointedImportMutationsAsync(using: context) {}
        XCTAssertEqual(context.snapshotPlaceBuildCount, placeCount + 1)
        XCTAssertEqual(context.snapshotUserPlaceBuildCount, saveCount + 1)
        try assertSnapshot(try XCTUnwrap(probe.snapshots.last), equalsFresh: store)
        try await store.commitAutomaticImportCheckpointDurablyAsync()
        XCTAssertEqual(context.snapshotPlaceBuildCount, placeCount + 1, "An ordinary capture never installs or consumes the memo")
        context.finish()
        XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
    }

    func testContextIsAbsentDuringAwaitAndOrdinaryUISavesAreCapturedNextTime() async throws {
        let gate = SnapshotRecordCheckpointGate()
        var ordinary: [WanderStoreSnapshot] = []
        let store = makeStore(persistence: WanderStorePersistence(load: { nil }, save: { ordinary.append($0) },
            checkpointAsync: { await gate.write($0) }))
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        let task = Task { @MainActor in try await store.performCheckpointedImportMutationsAsync(using: context) {} }
        await gate.waitUntilEntered()
        XCTAssertFalse(context.isInstalled)
        let captured = try XCTUnwrap(gate.snapshots.last)
        store.userPlaces[0].note = "UI edit while disk waits"
        _ = store.saveCandidate(PlaceCandidate(id: "ui-place", name: "UI place", category: "park",
            latitude: 41, longitude: -111, confidence: 1), status: .wannaGo, visibility: .selfOnly,
            note: "UI save", sourceType: .manual)
        XCTAssertEqual(ordinary.count, 1)
        XCTAssertEqual(captured.userPlaces.count, 1)
        XCTAssertEqual(ordinary[0].userPlaces.count, 2)
        XCTAssertNotEqual(captured.userPlaces[0].note, store.userPlaces[0].note)
        gate.resume()
        try await task.value
        gate.blocks = false
        try await store.performCheckpointedImportMutationsAsync(using: context) {}
        try assertSnapshot(try XCTUnwrap(gate.snapshots.last), equalsFresh: store)
        XCTAssertEqual(context.snapshotPlaceBuildCount, 2)
        XCTAssertEqual(context.snapshotUserPlaceBuildCount, 3)
    }

    func testAccountRoundTripOtherStoreAndFinishedContextFallBackToFreshCheckpointRecords() async throws {
        let probe = SnapshotRecordCheckpointProbe()
        let store = makeStore(persistence: probe.persistence)
        let owner = store.currentUser.id
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: owner))
        defer { context.finish() }
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        XCTAssertEqual(context.snapshotRetainedRecordCount, 2)
        let other = makeStore(persistence: probe.persistence)
        other.places[0].canonicalName = "Different store, same IDs"
        try await other.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertSnapshot(try XCTUnwrap(probe.snapshots.last), equalsFresh: other)
        XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        store.apply(authState: .signedIn(AuthSession(userID: "other-owner", displayName: "Other", handle: "other")))
        store.apply(authState: .signedIn(AuthSession(userID: owner, displayName: "Original", handle: "original")))
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertSnapshot(try XCTUnwrap(probe.snapshots.last), equalsFresh: store)
        XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
        context.finish()
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertSnapshot(try XCTUnwrap(probe.snapshots.last), equalsFresh: store)
    }

    func testIndependentContextsAndCancellationReleaseOnlyTheirOwnRecords() async throws {
        let gate = SnapshotRecordCheckpointGate()
        gate.blocks = false
        let store = makeStore(persistence: WanderStorePersistence(load: { nil }, save: { _ in },
            checkpointAsync: { await gate.write($0) }))
        let first = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        let second = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { first.finish(); second.finish() }
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: first)
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: second)
        first.finish()
        store.userPlaces[0].note = "Changed after the other context finished"
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: second)
        XCTAssertEqual(second.snapshotUserPlaceBuildCount, 2)
        try assertSnapshot(try XCTUnwrap(gate.snapshots.last), equalsFresh: store)
        gate.blocks = true
        let task = Task { @MainActor in
            defer { second.finish() }
            try await store.performCheckpointedImportMutationsAsync(using: second) {}
        }
        await gate.waitUntilEntered()
        task.cancel()
        XCTAssertFalse(second.isInstalled)
        XCTAssertGreaterThan(second.snapshotRetainedRecordCount, 0,
            "The caller owns the context until the exact acknowledgement returns")
        gate.resume()
        try await task.value
        XCTAssertTrue(second.isFinished)
        XCTAssertEqual(second.snapshotRetainedRecordCount, 0)
    }

    func testAuthorityLossRecapturesObserverRawEditsAndAccountChanges() async throws {
        for switchesAccount in [false, true] {
            let probe = SnapshotRecordCheckpointProbe()
            let store = makeStore(persistence: probe.persistence)
            let visible = VisiblePlace(id: store.userPlaces[0].id, place: store.places[0],
                userPlace: store.userPlaces[0], owner: store.currentUser, attributes: [])
            let hydrated = await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(userPlaceRepository: SnapshotRecordCalendarRepository(visible: visible)))
            XCTAssertTrue(hydrated)
            XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
            let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
            defer { context.finish() }
            try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
            let observer = SnapshotRecordAuthorityObserver()
            observer.action = {
                store.userPlaces[0].note = "Observer raw edit"
                store.places[0].address = "Observer address"
                if switchesAccount {
                    store.apply(authState: .signedIn(AuthSession(userID: "observer-owner", displayName: "Observer", handle: "observer")))
                }
            }
            let subscription = store.objectWillChange.sink { _ in MainActor.assumeIsolated { observer.receive() } }
            defer { subscription.cancel() }
            store.userPlaces[0].note = "Triggers authority loss"
            try await store.performCheckpointedImportMutationsAsync(using: context) {
                let batch = PlaceImportBatch(id: "memo-authority", source: .googleMaps, sourceName: "Fixture",
                    totalCount: 0, automaticSaveRequested: true)
                store.recordAutomaticImportCheckpoint(PlaceImportAutoSaveCheckpoint(
                    ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: []))
                observer.armed = true
            }
            XCTAssertEqual(observer.calls, 1)
            let written = try XCTUnwrap(probe.snapshots.last)
            try assertSnapshot(written, equalsFresh: store)
            if switchesAccount {
                XCTAssertEqual(written.currentUser.serverID, "observer-owner")
                XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
            } else {
                XCTAssertEqual(written.userPlaces[0].note, "Observer raw edit")
                XCTAssertEqual(written.places[0].address, "Observer address")
            }
        }
    }

    func testFailedAtomicWriteAndEncodingFailureRetryCurrentCompleteRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-memo-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WanderStorePersistence.file(url: url)
        let store = makeStore(persistence: persistence)
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        do {
            try await store.performCheckpointedImportMutationsAsync(using: context) {}
            XCTFail("Writing a file over a directory must fail")
        } catch {}
        XCTAssertFalse(context.isInstalled)
        XCTAssertEqual(context.snapshotRetainedRecordCount, 2)
        try FileManager.default.removeItem(at: url)
        store.userPlaces[0].note = "Retry includes new raw note"
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        let firstBytes = try Data(contentsOf: url)
        try assertSnapshot(try JSONDecoder().decode(WanderStoreSnapshot.self, from: firstBytes), equalsFresh: store)
        store.places[0].latitude = .nan
        do {
            try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
            XCTFail("Non-finite coordinates must retain the original encoding failure")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), firstBytes, "Failed encoding must not replace the durable file")
        store.places[0].latitude = 37
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertSnapshot(try JSONDecoder().decode(WanderStoreSnapshot.self, from: Data(contentsOf: url)), equalsFresh: store)
        context.finish()
        XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
    }

    private func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func assertSnapshot(_ snapshot: WanderStoreSnapshot, equalsFresh store: WanderStore,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        func fields(_ snapshot: WanderStoreSnapshot) throws -> Data {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes(snapshot)) as? [String: Any])
            object.removeValue(forKey: "savedAt") // Separate captures intentionally have fresh timestamps.
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        XCTAssertEqual(try fields(snapshot), try fields(WanderStoreSnapshot(store: store)), file: file, line: line)
        XCTAssertEqual(try bytes(snapshot.places), try bytes(store.places.map(WanderStoreSnapshot.PlaceRecord.init)), file: file, line: line)
        XCTAssertEqual(try bytes(snapshot.userPlaces), try bytes(store.userPlaces.map(WanderStoreSnapshot.UserPlaceRecord.init)), file: file, line: line)
    }

    private func makePlace(_ id: String) -> LocalPlace {
        LocalPlace(localID: id, serverID: "server-\(id)", canonicalName: "Fixture", category: "park",
            primaryCategory: "park", subcategory: "fixture", categorySource: "fixture", categoryConfidence: 0.8,
            rawProviderType: "fixture", address: "Fixture address", locality: "Fixture city", region: "CA", country: "US",
            latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: "provider-\(id)",
            confidence: 0.9, websiteURLString: "https://example.invalid", phoneNumber: "fixture-phone",
            timeZoneIdentifier: "America/Los_Angeles", actionLinksJSON: "{}", syncState: .synced,
            localUpdatedAt: .distantPast, serverUpdatedAt: .distantPast, lastSyncError: "fixture-error",
            createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func makeSave(_ id: String) -> LocalUserPlace {
        LocalUserPlace(localID: id, serverID: "server-\(id)", userID: "memo-owner", placeID: "server-place",
            status: .wannaGo, visibility: .selfOnly, note: "Fixture note", ratingSignal: "fixture", ratingScore: 4,
            recommendedScore: 0.8, recommendedCount: 3, categoryOverride: "park", subcategoryOverride: "fixture",
            categoryOverrideSource: "fixture", categoryOverrideConfidence: 0.7, viewerPrimaryCategory: "park",
            viewerSubcategory: "fixture", viewerFoodType: "fixture", visitedAt: .distantPast, savedAt: .distantPast,
            plannedDate: .distantPast, sourceType: "manual", sourceArtifactID: "fixture-artifact",
            sourceUserPlaceID: "fixture-source-save", attributionUserID: "fixture-attribution",
            historicalWantNote: "Fixture history", historicalWantAttributeAnswersJSON: "[]",
            historicalWantTagsJSON: "[]", historicalWantedAt: .distantPast, syncState: .synced,
            localUpdatedAt: .distantPast, serverUpdatedAt: .distantPast, lastSyncError: "fixture-error",
            createdAt: .distantPast, updatedAt: .distantPast, deletedAt: .distantPast,
            senderNotificationJSON: "{}")
    }

    private func makeStore(persistence: WanderStorePersistence) -> WanderStore {
        let owner = LocalProfile(localID: "memo-owner-local", serverID: "memo-owner", handle: "memo", displayName: "Memo")
        let place = makePlace("place")
        let save = makeSave("save")
        save.deletedAt = nil
        let fixtures = WanderFixtures(currentUser: owner, profiles: [owner], places: [place], userPlaces: [save],
            placeAttributes: [], follows: [], blocks: [], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: []))
        return WanderStore(fixtures: fixtures, persistence: persistence)
    }
}

@MainActor
private final class SnapshotRecordCheckpointProbe {
    var snapshots: [WanderStoreSnapshot] = []
    var persistence: WanderStorePersistence {
        WanderStorePersistence(load: { nil }, save: { _ in }, checkpointAsync: { [self] in snapshots.append($0) })
    }
}

@MainActor
private final class SnapshotRecordCheckpointGate {
    var snapshots: [WanderStoreSnapshot] = []
    var blocks = true
    private var continuation: CheckedContinuation<Void, Never>?
    func write(_ snapshot: WanderStoreSnapshot) async {
        snapshots.append(snapshot)
        if blocks { await withCheckedContinuation { continuation = $0 } }
    }
    func waitUntilEntered() async {
        for _ in 0..<1_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        XCTFail("Checkpoint did not reach the controlled gate")
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class SnapshotRecordAuthorityObserver {
    var armed = false
    var calls = 0
    var action: (() -> Void)?
    func receive() {
        guard armed else { return }
        armed = false
        calls += 1
        action?()
    }
}

@MainActor
private final class SnapshotRecordCalendarRepository: UserPlaceRepository {
    let visible: VisiblePlace
    init(visible: VisiblePlace) { self.visible = visible }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { [visible] }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws { throw URLError(.unsupportedURL) }
    func delete(userPlaceID: String) async throws { throw URLError(.unsupportedURL) }
}
