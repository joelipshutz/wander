import Foundation
import Observation

/// Pure model-to-record reuse owned by one automatic import run. Every capture
/// still walks the current arrays; only unchanged objects avoid repeated getters.
@MainActor
final class AutomaticImportSnapshotRecords {
    private let placeRecords = ObservedSnapshotRecords<LocalPlace, WanderStoreSnapshot.PlaceRecord>()
    private let userPlaceRecords = ObservedSnapshotRecords<LocalUserPlace, WanderStoreSnapshot.UserPlaceRecord>()
    private let attributeRecords = ObservedSnapshotRecords<LocalPlaceAttribute, WanderStoreSnapshot.PlaceAttributeRecord>()
    private let visitRecords = ObservedSnapshotRecords<LocalPlaceVisit, WanderStoreSnapshot.PlaceVisitRecord>()
    private(set) var isFinished = false

    var placeBuildCount: Int { placeRecords.buildCount }
    var userPlaceBuildCount: Int { userPlaceRecords.buildCount }
    var attributeBuildCount: Int { attributeRecords.buildCount }
    var visitBuildCount: Int { visitRecords.buildCount }
    var retainedRecordCount: Int { placeRecords.count + userPlaceRecords.count + attributeRecords.count + visitRecords.count }

    func places(_ models: [LocalPlace]) -> [WanderStoreSnapshot.PlaceRecord] {
        guard !isFinished else { return models.map(WanderStoreSnapshot.PlaceRecord.init) }
        return placeRecords.read(models, makeRecord: WanderStoreSnapshot.PlaceRecord.init)
    }

    func userPlaces(_ models: [LocalUserPlace]) -> [WanderStoreSnapshot.UserPlaceRecord] {
        guard !isFinished else { return models.map(WanderStoreSnapshot.UserPlaceRecord.init) }
        return userPlaceRecords.read(models, makeRecord: WanderStoreSnapshot.UserPlaceRecord.init)
    }

    func attributes(_ models: [LocalPlaceAttribute]) -> [WanderStoreSnapshot.PlaceAttributeRecord] {
        guard !isFinished else { return models.map(WanderStoreSnapshot.PlaceAttributeRecord.init) }
        return attributeRecords.read(models, makeRecord: WanderStoreSnapshot.PlaceAttributeRecord.init)
    }

    func visits(_ models: [LocalPlaceVisit]) -> [WanderStoreSnapshot.PlaceVisitRecord] {
        guard !isFinished else { return models.map(WanderStoreSnapshot.PlaceVisitRecord.init) }
        return visitRecords.read(models, makeRecord: WanderStoreSnapshot.PlaceVisitRecord.init)
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        placeRecords.finish()
        userPlaceRecords.finish()
        attributeRecords.finish()
        visitRecords.finish()
    }
}

@MainActor
private final class ObservedSnapshotRecords<Model: AnyObject, Record> {
    private var entries: [ObjectIdentifier: ObservedSnapshotRecord<Model, Record>] = [:]
    private(set) var buildCount = 0
    var count: Int { entries.count }

    func read(_ models: [Model], makeRecord: (Model) -> Record) -> [Record] {
        var next: [ObjectIdentifier: ObservedSnapshotRecord<Model, Record>] = [:]
        next.reserveCapacity(models.count)
        let records = models.map { model in
            let identity = ObjectIdentifier(model)
            let entry: ObservedSnapshotRecord<Model, Record>
            if let existing = next[identity] ?? entries[identity] {
                entry = existing
                if entry.refreshIfNeeded(makeRecord: makeRecord) { buildCount += 1 }
            } else {
                entry = ObservedSnapshotRecord(model, makeRecord: makeRecord)
                buildCount += 1
            }
            next[identity] = entry
            return entry.record
        }
        // Keep every old object alive until identity comparison is complete.
        // Different objects with duplicate local/server IDs remain distinct.
        for (identity, entry) in entries where next[identity] == nil { entry.finish() }
        entries = next
        return records
    }

    func finish() {
        for entry in entries.values { entry.finish() }
        entries.removeAll()
    }
}

@MainActor
private final class ObservedSnapshotRecord<Model: AnyObject, Record> {
    private let model: Model
    private let sentinel: SnapshotRecordObservationSentinel
    private var validity: SnapshotRecordObservationValidity
    private(set) var record: Record

    init(_ model: Model, makeRecord: (Model) -> Record) {
        self.model = model
        let sentinel = SnapshotRecordObservationSentinel()
        let validity = SnapshotRecordObservationValidity()
        self.sentinel = sentinel
        self.validity = validity
        record = withObservationTracking {
            _ = sentinel.generation
            return makeRecord(model)
        } onChange: { [weak validity] in validity?.invalidate() }
    }

    func refreshIfNeeded(makeRecord: (Model) -> Record) -> Bool {
        guard !validity.isValid else { return false }
        // Cancel the old one-shot registration before installing its successor.
        sentinel.generation &+= 1
        let validity = SnapshotRecordObservationValidity()
        self.validity = validity
        record = withObservationTracking {
            _ = sentinel.generation
            return makeRecord(model)
        } onChange: { [weak validity] in validity?.invalidate() }
        return true
    }

    func finish() { sentinel.generation &+= 1 }
}

@MainActor
@Observable
private final class SnapshotRecordObservationSentinel {
    var generation: UInt64 = 0
}

/// Callbacks only invalidate their own entry and never access models or actors.
private final class SnapshotRecordObservationValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true

    var isValid: Bool { lock.withLock { valid } }
    func invalidate() { lock.withLock { valid = false } }
}
