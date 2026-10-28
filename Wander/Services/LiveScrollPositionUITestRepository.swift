#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Fictional RPC responses exercise the production repository's progressive loading.
/// No account session or remote data is used by this opt-in simulator fixture.
@MainActor
enum LiveScrollPositionUITestRepository {
    static func make(arguments: [String], authenticatedUserID: String?) -> (any FeedRepository)? {
        let required: Set<String> = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderUnifiedLiveUITest", "-WanderFeedHydrationScrollUITest"]
        guard authenticatedUserID == "user_joe", required.isSubset(of: Set(arguments)) else { return nil }
        return SupabaseFeedRepository(rpc: FixtureRPC())
    }

    private final class FixtureRPC: RemoteProcedureCalling {
        private let now = Date.now.addingTimeInterval(-300)

        func call<Value: Decodable, Params: Encodable>(
            _ name: String, params: Params, decoder: JSONDecoder
        ) async throws -> Value {
            let payload: Any
            switch name {
            case "live_activity_feed":
                payload = ["activity": (0..<20).map(event), "featured_places": [],
                           "next_cursor": NSNull(), "fetched_at": timestamp(now)]
            case "feed_shared_visit_context":
                try await Task.sleep(for: .seconds(35))
                payload = (0..<6).map { index -> [String: Any] in
                    ["activity_id": identifier(index), "group_id": identifier(index / 2, family: 6591),
                     "visit_id": identifier(index, family: 6592), "companions": [
                        ["status": "accepted", "profile": profile(index + 1)]
                     ]]
                }
            case "activity_media":
                try await Task.sleep(for: .seconds(5))
                payload = [] as [String]
            default:
                throw URLError(.unsupportedURL)
            }
            return try decoder.decode(Value.self, from: JSONSerialization.data(withJSONObject: payload))
        }

        private func event(_ index: Int) -> [String: Any] {
            let occurredAt = timestamp(now.addingTimeInterval(Double(-index * 60)))
            let place: [String: Any] = [
                "user_place_id": identifier(index, family: 6593), "place_id": identifier(0, family: 6594),
                "owner_user_id": profile(index)["id"]!, "owner_handle": "fixture", "owner_display_name": "Fixture",
                "canonical_name": "Scroll Fixture Cafe", "category": "coffee", "latitude": 34.077, "longitude": -118.260,
                "status": "been", "visibility": "followers", "source_type": "manual", "attributes": [],
                "saved_at": occurredAt, "created_at": occurredAt, "updated_at": occurredAt
            ]
            return ["id": identifier(index), "event_type": "place_been", "occurred_at": occurredAt,
                    "actor": profile(index), "place": place, "media": [],
                    "note": "Scroll visit \(index + 1). " + String(repeating: "A place worth returning to. ", count: index % 5)]
        }

        private func profile(_ index: Int) -> [String: String] {
            let owner = index.isMultiple(of: 2)
            return ["id": owner ? "user_joe" : "scroll-companion", "handle": owner ? "fixture" : "companion",
                    "display_name": owner ? "Fixture owner" : "Companion", "relationship": owner ? "owner" : "mutual"]
        }

        private func identifier(_ index: Int, family: Int = 6590) -> String {
            String(format: "%04d0000-0000-0000-0000-%012d", family, index)
        }

        private func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    }
}
#endif
