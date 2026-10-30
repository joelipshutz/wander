import Foundation
import Observation

/// Retains grouping inputs only for one synchronous list insertion operation.
/// Every read still validates the full model identity order and current locale.
/// Call finish() in the operation's defer to cancel its one-shot observations.
@MainActor
final class ListInsertionPlaceObservation {
    let sentinel = ListInsertionObservationSentinel()
    private(set) var validity = ListInsertionObservationValidity()
    private var fingerprints: [ListInsertionPlaceFingerprint] = []
    private var identities: [ObjectIdentifier] = []
    // ObjectIdentifier is unique only during an object's lifetime. Retain even
    // duplicate-reference nonwinners until their replacement has been checked.
    private var retainedPlaces: [LocalPlace] = []
    private var localeID = Locale.current.identifier
    private(set) var resetRevision: UInt64 = 0
    private(set) var fingerprintReadCount = 0
    private(set) var identityValidationCount = 0

    var count: Int { fingerprints.count }

    func read(_ places: [LocalPlace], localeID: String = Locale.current.identifier) -> [ListInsertionPlaceFingerprint] {
        let nextIdentities = places.map(ObjectIdentifier.init)
        identityValidationCount += nextIdentities.count
        let canAppend = validity.isValid && self.localeID == localeID
            && nextIdentities.count >= identities.count
            && zip(identities, nextIdentities).allSatisfy { $0.0 == $0.1 }
        if !canAppend {
            // Cancel the old generation before registering its successor. A
            // callback captures only its own token, never the mutable projection.
            finish()
            validity = ListInsertionObservationValidity()
            resetRevision &+= 1
        }
        self.localeID = localeID
        for place in places.dropFirst(fingerprints.count) {
            let token = validity
            let fingerprint = withObservationTracking {
                _ = sentinel.generation
                return ListInsertionPlaceFingerprint(place)
            } onChange: { [weak token] in
                token?.invalidate()
            }
            fingerprintReadCount += 1
            fingerprints.append(fingerprint)
        }
        identities = nextIdentities
        retainedPlaces = places
        return fingerprints
    }

    func finish() {
        // Each tracking registration reads this property. Its mutation delivers
        // every remaining callback and cancels all of their tracked model reads.
        sentinel.generation &+= 1
        fingerprints.removeAll(keepingCapacity: true)
        identities.removeAll(keepingCapacity: true)
        retainedPlaces.removeAll(keepingCapacity: true)
    }
}

@MainActor
@Observable
final class ListInsertionObservationSentinel {
    var generation: UInt64 = 0
}

/// Observation callbacks only mark validity; they never read or mutate models.
final class ListInsertionObservationValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    private var callbacks = 0

    func invalidate() {
        lock.lock()
        valid = false
        callbacks += 1
        lock.unlock()
    }

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }

    var callbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callbacks
    }
}

struct ListInsertionPlaceFingerprint: Equatable {
    let identity: ObjectIdentifier
    let localID: String
    let serverID: String?
    let name: String
    let provider: String
    let providerID: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: UInt64
    let longitude: UInt64

    init(_ place: LocalPlace) {
        identity = ObjectIdentifier(place)
        localID = place.localID
        serverID = place.serverID
        name = place.canonicalName
        provider = place.sourceProvider
        providerID = place.sourceProviderPlaceID
        address = place.address
        locality = place.locality
        region = place.region
        country = place.country
        latitude = place.latitude.bitPattern
        longitude = place.longitude.bitPattern
    }
}
