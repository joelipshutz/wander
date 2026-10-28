import Foundation
import XCTest
@testable import Wander

@MainActor
final class LiveMapPinStateRepositoryTests: XCTestCase {
    func testChunksAndDeduplicatesCanonicalScopeWithoutTimeOrAudienceFilters() async throws {
        let rpc = PinStateRPC()
        let ids = (1...405).map(Self.placeID)
        let repository = SupabaseFeedRepository(rpc: rpc)

        let snapshot = try await repository.liveMapPinStates(
            placeIDs: Array(ids.reversed()) + [ids[0].uppercased(), ids[0]])

        XCTAssertEqual(rpc.calls.map(\.ids.count), [200, 200, 5])
        XCTAssertTrue(rpc.calls.allSatisfy { $0.name == "live_map_pin_states" })
        XCTAssertTrue(rpc.calls.allSatisfy { $0.parameterKeys == ["input_place_ids"] })
        XCTAssertEqual(rpc.calls.flatMap(\.ids), ids.sorted())
        XCTAssertEqual(snapshot.states.map(\.placeID), ids.sorted())
        XCTAssertTrue(snapshot.complete)
        XCTAssertTrue(snapshot.states.allSatisfy { $0.saves.isEmpty && !$0.hasListMembership })
    }

    func testDecodesIndependentStatusFacetsAndListMembershipInScalarResponse() async throws {
        let rpc = PinStateRPC()
        rpc.transform = { _, body in
            var body = body
            var states = body["states"] as! [[String: Any]]
            states[0]["place_id"] = (states[0]["place_id"] as! String).uppercased()
            states[0]["saves"] = [
                ["owner_id": "viewer", "has_been": true, "has_wanna": true, "is_friend": false],
                ["owner_id": "friend", "has_been": false, "has_wanna": true, "is_friend": true]
            ]
            states[0]["has_list_membership"] = true
            body["states"] = states
            return body
        }

        let snapshot = try await LiveMapPinStateTransport.fetch(placeIDs: [Self.placeID(1)], rpc: rpc)

        XCTAssertEqual(snapshot.states, [LiveMapPinState(
            placeID: Self.placeID(1),
            saves: [
                LiveMapPinSaveState(ownerID: "viewer", hasBeen: true, hasWanna: true, isFriend: false),
                LiveMapPinSaveState(ownerID: "friend", hasBeen: false, hasWanna: true, isFriend: true)
            ], hasListMembership: true)])
        XCTAssertEqual(snapshot.fetchedAt, ISO8601DateFormatter().date(from: "2026-10-27T10:00:00Z"))
    }

    func testLeaseUsesOldestBatchTimestamp() async throws {
        let rpc = PinStateRPC()
        rpc.transform = { index, body in
            var body = body
            body["fetched_at"] = index == 0 ? "2026-10-27T10:00:00Z" : "2026-10-27T10:01:00Z"
            return body
        }
        let snapshot = try await LiveMapPinStateTransport.fetch(
            placeIDs: (1...201).map(Self.placeID), rpc: rpc)
        XCTAssertEqual(snapshot.fetchedAt, ISO8601DateFormatter().date(from: "2026-10-27T10:00:00Z"))
    }

    func testMissingDuplicateAndForeignPlaceIDsCannotProveAbsence() async throws {
        for corruption in ["missing", "duplicate", "foreign", "malformed"] {
            let rpc = PinStateRPC()
            rpc.transform = { _, body in
                var body = body
                var states = body["states"] as! [[String: Any]]
                switch corruption {
                case "missing": states.removeLast()
                case "duplicate": states[1] = states[0]
                case "foreign": states[1]["place_id"] = Self.placeID(99)
                default: states[1]["place_id"] = "not-a-place-id"
                }
                body["states"] = states
                return body
            }
            await assertRejected(rpc: rpc, ids: [Self.placeID(1), Self.placeID(2)], context: corruption)
        }
    }

    func testIncompleteAndMissingFreshnessResponsesFailClosed() async throws {
        for corruption in ["incomplete", "missing_freshness", "invalid_freshness"] {
            let rpc = PinStateRPC()
            rpc.transform = { _, body in
                var body = body
                switch corruption {
                case "incomplete": body["complete"] = false
                case "missing_freshness": body.removeValue(forKey: "fetched_at")
                default: body["fetched_at"] = "invalid"
                }
                return body
            }
            await assertRejected(rpc: rpc, context: corruption)
        }
    }

    func testMalformedOrDuplicateOwnersAndEmptyFacetsFailClosed() async throws {
        for corruption in ["duplicate", "empty", "whitespace", "no_status"] {
            let rpc = PinStateRPC()
            rpc.transform = { _, body in
                var body = body
                var states = body["states"] as! [[String: Any]]
                var save: [String: Any] = [
                    "owner_id": "viewer", "has_been": true, "has_wanna": false, "is_friend": false
                ]
                switch corruption {
                case "empty": save["owner_id"] = ""
                case "whitespace": save["owner_id"] = " viewer "
                case "no_status": save["has_been"] = false
                default: break
                }
                states[0]["saves"] = corruption == "duplicate" ? [save, save] : [save]
                body["states"] = states
                return body
            }
            await assertRejected(rpc: rpc, context: corruption)
        }
    }

    func testLaterBatchFailureDoesNotPublishPartialSnapshotOrRequestRemainingBatches() async throws {
        let rpc = PinStateRPC()
        rpc.failureAtCall = 1
        do {
            _ = try await LiveMapPinStateTransport.fetch(placeIDs: (1...405).map(Self.placeID), rpc: rpc)
            XCTFail("Partial pin evidence must not be published")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }
        XCTAssertEqual(rpc.calls.map(\.ids.count), [200, 200])
    }

    func testInvalidScopeIsRejectedBeforeAnyNetworkRequestAndEmptyScopeIsLocal() async throws {
        let rpc = PinStateRPC()
        await assertRejected(rpc: rpc, ids: [Self.placeID(1), "not-a-uuid"])
        XCTAssertTrue(rpc.calls.isEmpty)

        let empty = try await LiveMapPinStateTransport.fetch(placeIDs: [], rpc: rpc)
        XCTAssertTrue(empty.complete)
        XCTAssertTrue(empty.states.isEmpty)
        XCTAssertNil(empty.fetchedAt)
        XCTAssertTrue(rpc.calls.isEmpty)
    }

    func testCancelledRequestDoesNotStartRemoteBatch() async {
        let rpc = PinStateRPC()
        let request = Task { @MainActor in
            try await LiveMapPinStateTransport.fetch(placeIDs: [Self.placeID(1)], rpc: rpc)
        }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Cancelled pin request must not publish evidence")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(rpc.calls.isEmpty)
    }

    private func assertRejected(rpc: PinStateRPC, ids: [String]? = nil, context: String = "",
                                file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await LiveMapPinStateTransport.fetch(placeIDs: ids ?? [Self.placeID(1)], rpc: rpc)
            XCTFail("Invalid pin state accepted: \(context)", file: file, line: line)
        } catch {
            XCTAssertTrue(error is WanderRemoteError || error is DecodingError,
                          "Unexpected error: \(context)", file: file, line: line)
        }
    }

    private static func placeID(_ index: Int) -> String {
        String(format: "65700000-0000-0000-0000-%012x", index)
    }
}

@MainActor
private final class PinStateRPC: RemoteProcedureCalling {
    struct Call {
        let name: String
        let ids: [String]
        let parameterKeys: Set<String>
    }

    var transform: ((Int, [String: Any]) -> [String: Any])?
    var failureAtCall: Int?
    private(set) var calls: [Call] = []

    func call<Value: Decodable, Params: Encodable>(
        _ name: String, params: Params, decoder: JSONDecoder
    ) async throws -> Value {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        let ids = encoded["input_place_ids"] as! [String]
        let index = calls.count
        calls.append(Call(name: name, ids: ids, parameterKeys: Set(encoded.keys)))
        if failureAtCall == index { throw WanderRemoteError.notAuthenticated }
        let states: [[String: Any]] = ids.map {
            ["place_id": $0, "saves": [], "has_list_membership": false]
        }
        let body: [String: Any] = [
            "states": states, "complete": true, "fetched_at": "2026-10-27T10:00:00Z"
        ]
        let response = transform?(index, body) ?? body
        return try decoder.decode(Value.self, from: JSONSerialization.data(withJSONObject: response))
    }
}
