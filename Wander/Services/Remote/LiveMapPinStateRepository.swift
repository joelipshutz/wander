import Foundation

struct LiveMapPinSaveState: Decodable, Equatable, Sendable {
    let ownerID: String
    let hasBeen: Bool
    let hasWanna: Bool
    let isFriend: Bool

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id", hasBeen = "has_been", hasWanna = "has_wanna", isFriend = "is_friend"
    }
}

struct LiveMapPinState: Decodable, Equatable, Sendable {
    let placeID: String
    let saves: [LiveMapPinSaveState]
    let hasListMembership: Bool

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id", saves, hasListMembership = "has_list_membership"
    }
}

/// A complete response proves absence only for its explicitly covered place IDs.
/// It is independent of the Feed event window and must be discarded on account
/// or authorization changes by the owning Live session.
struct LiveMapPinStateSnapshot: Equatable, Sendable {
    let states: [LiveMapPinState]
    let complete: Bool
    let fetchedAt: Date?

    init(states: [LiveMapPinState], complete: Bool, fetchedAt: Date? = nil) {
        self.states = states
        self.complete = complete
        self.fetchedAt = fetchedAt
    }
}

@MainActor
protocol LiveMapPinStateRepository {
    func liveMapPinStates(placeIDs: [String]) async throws -> LiveMapPinStateSnapshot
}

@MainActor
enum LiveMapPinStateTransport {
    static let maximumBatchSize = 200

    static func fetch(placeIDs: [String], rpc: any RemoteProcedureCalling) async throws -> LiveMapPinStateSnapshot {
        guard placeIDs.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw WanderRemoteError.invalidResponse("Invalid Live pin state scope")
        }
        let ids = Set(placeIDs.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() }).sorted()
        guard !ids.isEmpty else { return LiveMapPinStateSnapshot(states: [], complete: true) }

        var states: [LiveMapPinState] = []
        var oldestFetch: Date?
        for start in stride(from: 0, to: ids.count, by: maximumBatchSize) {
            try Task.checkCancellation()
            let chunk = Array(ids[start..<min(start + maximumBatchSize, ids.count)])
            let response: RemoteLiveMapPinStateSnapshot = try await rpc.call(
                "live_map_pin_states", params: LiveMapPinStatesParameters(input_place_ids: chunk))
            try Task.checkCancellation()
            let validated = try validate(response, expectedIDs: chunk)
            states += validated
            oldestFetch = oldestFetch.map { min($0, response.fetchedAt) } ?? response.fetchedAt
        }
        // Nothing is published until every batch succeeds and covers its whole
        // requested scope. A partial response can never turn a pin Featured.
        return LiveMapPinStateSnapshot(states: states, complete: true, fetchedAt: oldestFetch)
    }

    private static func validate(_ response: RemoteLiveMapPinStateSnapshot,
                                 expectedIDs: [String]) throws -> [LiveMapPinState] {
        guard response.complete, response.states.count == expectedIDs.count else {
            throw WanderRemoteError.invalidResponse("Incomplete Live pin state response")
        }
        var seen = Set<String>()
        var normalized: [LiveMapPinState] = []
        for state in response.states {
            guard let id = UUID(uuidString: state.placeID)?.uuidString.lowercased(),
                  seen.insert(id).inserted else {
                throw WanderRemoteError.invalidResponse("Invalid Live pin state identity")
            }
            var owners = Set<String>()
            for save in state.saves {
                guard !save.ownerID.isEmpty, save.ownerID.count <= 256,
                      save.ownerID == save.ownerID.trimmingCharacters(in: .whitespacesAndNewlines),
                      owners.insert(save.ownerID).inserted, save.hasBeen || save.hasWanna else {
                    throw WanderRemoteError.invalidResponse("Invalid Live pin save state")
                }
            }
            normalized.append(LiveMapPinState(placeID: id, saves: state.saves,
                                               hasListMembership: state.hasListMembership))
        }
        guard seen == Set(expectedIDs) else {
            throw WanderRemoteError.invalidResponse("Mismatched Live pin state scope")
        }
        return normalized.sorted { $0.placeID < $1.placeID }
    }

    private struct LiveMapPinStatesParameters: Encodable {
        let input_place_ids: [String]
    }

    private struct RemoteLiveMapPinStateSnapshot: Decodable {
        let states: [LiveMapPinState]
        let complete: Bool
        let fetchedAt: Date

        enum CodingKeys: String, CodingKey {
            case states, complete, fetchedAt = "fetched_at"
        }
    }
}
