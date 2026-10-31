import Foundation
import SwiftData
import XCTest
@testable import Wander

@MainActor
final class AutomaticImportHistorySnapshotRecordsTests: XCTestCase {
    func testEveryAttributeFieldInvalidatesOnlyItsOwnRecord() throws {
        let mutations: [(String, (LocalPlaceAttribute) -> Void)] = [
            ("localID", { $0.localID = "changed-local" }),
            ("serverID", { $0.serverID = "changed-server" }),
            ("userPlaceID", { $0.userPlaceID = "changed-parent" }),
            ("questionKey", { $0.questionKey = "changed-question" }),
            ("valueType", { $0.valueType = "raw-value-type" }),
            ("valueJSON", { $0.valueJSON = "raw JSON need not be valid" }),
            ("syncStateRaw", { $0.syncStateRaw = "raw-sync-state" }),
            ("localUpdatedAt", { $0.localUpdatedAt = .distantFuture }),
            ("serverUpdatedAt", { $0.serverUpdatedAt = .distantFuture }),
            ("lastSyncError", { $0.lastSyncError = "changed-error" }),
            ("createdAt", { $0.createdAt = .distantFuture }),
            ("updatedAt", { $0.updatedAt = .distantFuture })
        ]
        XCTAssertEqual(Set(mutations.map(\.0)), Set(Mirror(reflecting:
            WanderStoreSnapshot.PlaceAttributeRecord(attribute("schema"))).children.compactMap(\.label)))
        for (name, mutate) in mutations {
            let first = attribute("first")
            let second = attribute("second")
            let records = AutomaticImportSnapshotRecords()
            defer { records.finish() }
            let before = records.attributes([first, second])
            XCTAssertEqual(records.attributeBuildCount, 2)
            mutate(first)
            let actual = records.attributes([first, second])
            XCTAssertEqual(try bytes(actual), try bytes([first, second].map(WanderStoreSnapshot.PlaceAttributeRecord.init)), name)
            XCTAssertNotEqual(try bytes(actual[0]), try bytes(before[0]), name)
            XCTAssertEqual(records.attributeBuildCount, 3, name)
            _ = records.attributes([first, second])
            XCTAssertEqual(records.attributeBuildCount, 3, "Unchanged rows must not be recaptured: \(name)")
        }
    }

    func testEveryVisitFieldInvalidatesOnlyItsOwnRecord() throws {
        let mutations: [(String, (LocalPlaceVisit) -> Void)] = [
            ("senderNotificationJSON", { $0.senderNotificationJSON = "{\"changed\":true}" }),
            ("localID", { $0.localID = "changed-local" }),
            ("serverID", { $0.serverID = "changed-server" }),
            ("userPlaceID", { $0.userPlaceID = "changed-parent" }),
            ("visitedAt", { $0.visitedAt = .distantFuture }),
            ("note", { $0.note = "Changed note" }),
            ("ratingScore", { $0.ratingScore = 0.123 }),
            ("attributeAnswersJSON", { $0.attributeAnswersJSON = "raw answers need not be valid JSON" }),
            ("attributeAnswersAreComplete", { $0.attributeAnswersAreComplete = false }),
            ("tagsJSON", { $0.tagsJSON = "raw tags need not be valid JSON" }),
            ("backfilledFromUserPlace", { $0.backfilledFromUserPlace = true }),
            ("syncStateRaw", { $0.syncStateRaw = "raw-sync-state" }),
            ("localUpdatedAt", { $0.localUpdatedAt = .distantFuture }),
            ("serverUpdatedAt", { $0.serverUpdatedAt = .distantFuture }),
            ("lastSyncError", { $0.lastSyncError = "changed-error" }),
            ("createdAt", { $0.createdAt = .distantFuture }),
            ("updatedAt", { $0.updatedAt = .distantFuture }),
            ("deletedAt", { $0.deletedAt = .distantFuture })
        ]
        XCTAssertEqual(Set(mutations.map(\.0)), Set(Mirror(reflecting:
            WanderStoreSnapshot.PlaceVisitRecord(visit("schema"))).children.compactMap(\.label)))
        for (name, mutate) in mutations {
            let first = visit("first")
            let second = visit("second")
            let records = AutomaticImportSnapshotRecords()
            defer { records.finish() }
            let before = records.visits([first, second])
            XCTAssertEqual(records.visitBuildCount, 2)
            mutate(first)
            let actual = records.visits([first, second])
            XCTAssertEqual(try bytes(actual), try bytes([first, second].map(WanderStoreSnapshot.PlaceVisitRecord.init)), name)
            XCTAssertNotEqual(try bytes(actual[0]), try bytes(before[0]), name)
            XCTAssertEqual(records.visitBuildCount, 3, name)
            _ = records.visits([first, second])
            XCTAssertEqual(records.visitBuildCount, 3, name)
        }
    }

    func testNilTransitionsUnicodeRawJSONAndSignedZeroRemainByteExact() throws {
        let attribute = self.attribute("attribute")
        let visit = self.visit("visit")
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        let strings: [String?] = ["\u{00E9}", "e\u{0301}", nil, "restored"]
        let attributeStrings: [ReferenceWritableKeyPath<LocalPlaceAttribute, String?>] = [\.serverID, \.lastSyncError]
        let visitStrings: [ReferenceWritableKeyPath<LocalPlaceVisit, String?>] = [
            \.senderNotificationJSON, \.serverID, \.note, \.lastSyncError
        ]
        for path in attributeStrings {
            for value in strings {
                _ = records.attributes([attribute]); attribute[keyPath: path] = value
                XCTAssertEqual(try bytes(records.attributes([attribute])), try bytes([WanderStoreSnapshot.PlaceAttributeRecord(attribute)]))
            }
        }
        for path in visitStrings {
            for value in strings {
                _ = records.visits([visit]); visit[keyPath: path] = value
                XCTAssertEqual(try bytes(records.visits([visit])), try bytes([WanderStoreSnapshot.PlaceVisitRecord(visit)]))
            }
        }
        for value in ["\"\u{00E9}\"", "\"e\u{0301}\"", "invalid JSON"] {
            _ = records.attributes([attribute]); _ = records.visits([visit])
            attribute.valueJSON = value
            visit.attributeAnswersJSON = value
            visit.tagsJSON = value
            XCTAssertEqual(try bytes(records.attributes([attribute])), try bytes([WanderStoreSnapshot.PlaceAttributeRecord(attribute)]))
            XCTAssertEqual(try bytes(records.visits([visit])), try bytes([WanderStoreSnapshot.PlaceVisitRecord(visit)]))
        }
        let numbers: [Double?] = [0.0, -0.0, nil, 4.5]
        for value in numbers {
            _ = records.visits([visit]); visit.ratingScore = value
            let actual = records.visits([visit])[0]
            XCTAssertEqual(actual.ratingScore?.bitPattern, value?.bitPattern)
            XCTAssertEqual(try bytes(actual), try bytes(WanderStoreSnapshot.PlaceVisitRecord(visit)))
        }
        let flags: [Bool?] = [nil, false, true]
        for value in flags {
            _ = records.visits([visit]); visit.attributeAnswersAreComplete = value
            XCTAssertEqual(try bytes(records.visits([visit])), try bytes([WanderStoreSnapshot.PlaceVisitRecord(visit)]))
        }
        let dates: [Date?] = [nil, .distantPast]
        for value in dates {
            _ = records.attributes([attribute]); attribute.serverUpdatedAt = value
            XCTAssertEqual(try bytes(records.attributes([attribute])), try bytes([WanderStoreSnapshot.PlaceAttributeRecord(attribute)]))
        }
        let visitDates: [ReferenceWritableKeyPath<LocalPlaceVisit, Date?>] = [\.serverUpdatedAt, \.deletedAt]
        for path in visitDates {
            for value in dates {
                _ = records.visits([visit]); visit[keyPath: path] = value
                XCTAssertEqual(try bytes(records.visits([visit])), try bytes([WanderStoreSnapshot.PlaceVisitRecord(visit)]))
            }
        }
    }

    func testDuplicateIDsObjectMultiplicityOrderReplacementAndPruning() throws {
        let a = attribute("duplicate")
        let b = attribute("duplicate")
        b.valueJSON = "\"second object\""
        let v = visit("duplicate")
        let w = visit("duplicate")
        w.note = "Second object"
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        for values in [[a, b, a], [b, a], [attribute("duplicate"), b], []] {
            XCTAssertEqual(try bytes(records.attributes(values)),
                try bytes(values.map(WanderStoreSnapshot.PlaceAttributeRecord.init)))
        }
        XCTAssertEqual(records.attributeBuildCount, 3)
        for values in [[v, w, v], [w, v], [visit("duplicate"), w], []] {
            XCTAssertEqual(try bytes(records.visits(values)),
                try bytes(values.map(WanderStoreSnapshot.PlaceVisitRecord.init)))
        }
        XCTAssertEqual(records.visitBuildCount, 3)
        XCTAssertEqual(records.retainedRecordCount, 0)
    }

    func testRemovedHistoryObjectsAndFinishedCacheReleaseTheirObservationLifetime() throws {
        var attribute: LocalPlaceAttribute? = self.attribute("lifetime")
        var visit: LocalPlaceVisit? = self.visit("lifetime")
        weak var weakAttribute = attribute
        weak var weakVisit = visit
        let records = AutomaticImportSnapshotRecords()
        _ = records.attributes([try XCTUnwrap(attribute)])
        _ = records.visits([try XCTUnwrap(visit)])
        attribute = nil; visit = nil
        XCTAssertNotNil(weakAttribute)
        XCTAssertNotNil(weakVisit)
        _ = records.attributes([])
        XCTAssertNil(weakAttribute)
        XCTAssertNotNil(weakVisit)
        records.finish()
        records.finish()
        XCTAssertNil(weakVisit)
        XCTAssertEqual(records.retainedRecordCount, 0)
        let laterAttribute = self.attribute("later")
        let laterVisit = self.visit("later")
        _ = records.attributes([laterAttribute]); _ = records.visits([laterVisit])
        laterAttribute.valueJSON = "\"changed after finish\""
        laterVisit.note = "Changed after finish"
        XCTAssertEqual(records.attributes([laterAttribute]), [WanderStoreSnapshot.PlaceAttributeRecord(laterAttribute)])
        XCTAssertEqual(records.visits([laterVisit]), [WanderStoreSnapshot.PlaceVisitRecord(laterVisit)])
        XCTAssertEqual(records.retainedRecordCount, 0)
    }

    func testManagedHistoryModelsRecaptureRawChangesSynchronously() throws {
        let container = try ModelContainer(for: LocalPlaceAttribute.self, LocalPlaceVisit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let attribute = self.attribute("managed")
        let visit = self.visit("managed")
        container.mainContext.insert(attribute); container.mainContext.insert(visit)
        try container.mainContext.save()
        let records = AutomaticImportSnapshotRecords()
        defer { records.finish() }
        _ = records.attributes([attribute]); _ = records.visits([visit])
        attribute.valueJSON = "Changed managed value"
        visit.attributeAnswersAreComplete = nil
        visit.deletedAt = nil
        XCTAssertEqual(records.attributes([attribute]), [WanderStoreSnapshot.PlaceAttributeRecord(attribute)])
        XCTAssertEqual(records.visits([visit]), [WanderStoreSnapshot.PlaceVisitRecord(visit)])
        XCTAssertEqual(records.attributeBuildCount, 2)
        XCTAssertEqual(records.visitBuildCount, 2)
        try container.mainContext.save()
        XCTAssertEqual(records.attributes([attribute]), [WanderStoreSnapshot.PlaceAttributeRecord(attribute)])
        XCTAssertEqual(records.visits([visit]), [WanderStoreSnapshot.PlaceVisitRecord(visit)])
    }

    func testFullFileCheckpointKeepsHistoryAndFailedEncodingRetryMatchesFreshSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-memo-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WanderStorePersistence.file(url: url)
        let store = makeStore(persistence: persistence)
        let attribute = try XCTUnwrap(store.placeAttributes.first)
        let visit = try XCTUnwrap(store.placeVisits.first)
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        try await store.performCheckpointedImportMutationsAsync(using: context) {}
        try assertFile(url, equals: store)
        let original = try Data(contentsOf: url)
        attribute.valueJSON = "\"e\u{0301}\""
        visit.tagsJSON = "raw tags"
        visit.note = "Changed while cached"
        visit.ratingScore = .nan
        do {
            try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
            XCTFail("Non-finite history rating must retain the encoder failure")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        visit.ratingScore = -0.0
        visit.attributeAnswersAreComplete = nil
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertFile(url, equals: store)
        attribute.userPlaceID = "raw-changed-parent"
        visit.deletedAt = .distantPast
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        try assertFile(url, equals: store)
        context.finish()
        XCTAssertEqual(context.snapshotRetainedRecordCount, 0)
    }

    func testHistoryEditsDuringAcknowledgementAreFreshNextTimeAndDoNotAlterThePendingSnapshot() async throws {
        let gate = HistorySnapshotCheckpointGate()
        let store = makeStore(persistence: WanderStorePersistence(load: { nil }, save: { _ in },
            checkpointAsync: { await gate.write($0) }))
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        let task = Task { @MainActor in try await store.performCheckpointedImportMutationsAsync(using: context) {} }
        await gate.waitUntilEntered()
        XCTAssertFalse(context.isInstalled)
        let pending = try XCTUnwrap(gate.snapshots.last)
        let pendingBytes = try bytes(pending)
        let attribute = try XCTUnwrap(store.placeAttributes.first)
        let visit = try XCTUnwrap(store.placeVisits.first)
        attribute.valueJSON = "\"A manual edit while disk waits\""
        attribute.serverID = nil
        visit.note = "A manual history edit while disk waits"
        visit.deletedAt = .distantPast
        visit.attributeAnswersAreComplete = nil
        XCTAssertEqual(try bytes(try XCTUnwrap(gate.snapshots.last)), pendingBytes)
        gate.resume()
        try await task.value
        gate.blocks = false
        try await store.performCheckpointedImportMutationsAsync(using: context) {}
        let next = try XCTUnwrap(gate.snapshots.last)
        XCTAssertEqual(try bytes(next.placeAttributes), try bytes(store.placeAttributes.map(WanderStoreSnapshot.PlaceAttributeRecord.init)))
        XCTAssertEqual(try bytes(next.placeVisits), try bytes(store.placeVisits.map(WanderStoreSnapshot.PlaceVisitRecord.init)))
        XCTAssertNotEqual(try bytes(next.placeAttributes), try bytes(pending.placeAttributes))
        XCTAssertNotEqual(try bytes(next.placeVisits), try bytes(pending.placeVisits))
    }

    private func assertFile(_ url: URL, equals store: WanderStore) throws {
        let actual = try JSONDecoder().decode(WanderStoreSnapshot.self, from: Data(contentsOf: url))
        let expected = WanderStoreSnapshot(store: store)
        XCTAssertEqual(try bytes(actual.placeAttributes), try bytes(expected.placeAttributes))
        XCTAssertEqual(try bytes(actual.placeVisits), try bytes(expected.placeVisits))
        func fields(_ snapshot: WanderStoreSnapshot) throws -> Data {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes(snapshot)) as? [String: Any])
            object.removeValue(forKey: "savedAt")
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        XCTAssertEqual(try fields(actual), try fields(expected))
    }

    private func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func makeStore(persistence: WanderStorePersistence) -> WanderStore {
        let owner = LocalProfile(localID: "history-owner", handle: "history", displayName: "History")
        let place = LocalPlace(localID: "history-place", canonicalName: "History place", category: "park", latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "history-parent", userID: owner.id, placeID: place.id,
            status: .been, visibility: .selfOnly, sourceType: "manual")
        let attribute = self.attribute("history-attribute")
        let visit = self.visit("history-visit")
        visit.deletedAt = nil
        let fixtures = WanderFixtures(currentUser: owner, profiles: [owner], places: [place], userPlaces: [save],
            placeAttributes: [attribute], placeVisits: [visit], follows: [], blocks: [], placeLists: [],
            placeListMembers: [], placeListItems: [], contactProvider: FakeContactProvider(seededMatches: []))
        return WanderStore(fixtures: fixtures, persistence: persistence)
    }

    private func attribute(_ id: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(localID: id, serverID: "server-\(id)", userPlaceID: "history-parent", questionKey: "fixture",
            valueType: "text", valueJSON: "\"fixture\"", syncState: .synced, localUpdatedAt: .distantPast,
            serverUpdatedAt: .distantPast, lastSyncError: "fixture-error", createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func visit(_ id: String) -> LocalPlaceVisit {
        LocalPlaceVisit(localID: id, serverID: "server-\(id)", userPlaceID: "history-parent", visitedAt: .distantPast,
            note: "Fixture note", ratingScore: 4, attributeAnswersJSON: "[]", tags: ["fixture"], syncState: .synced,
            localUpdatedAt: .distantPast, serverUpdatedAt: .distantPast, lastSyncError: "fixture-error",
            createdAt: .distantPast, updatedAt: .distantPast, deletedAt: .distantPast,
            attributeAnswersAreComplete: true, senderNotificationJSON: "{}")
    }
}

@MainActor
private final class HistorySnapshotCheckpointGate {
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
