import Foundation

struct EventsInterest: Decodable, Equatable {
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
    }
}

@MainActor protocol EventsInterestRepository {
    func currentInterest() async throws -> EventsInterest?
    func registerInterest() async throws -> EventsInterest
}

/// Identity comes from the authenticated JWT, never from a client-supplied ID.
@MainActor struct SupabaseEventsInterestRepository: EventsInterestRepository {
    let rpc: any RemoteProcedureCalling
    private struct Params: Encodable {}

    func currentInterest() async throws -> EventsInterest? {
        let rows: [EventsInterest] = try await rpc.call("own_events_launch_interest", params: Params())
        return rows.first
    }

    func registerInterest() async throws -> EventsInterest {
        let rows: [EventsInterest] = try await rpc.call("register_events_launch_interest", params: Params())
        guard let interest = rows.first else {
            throw WanderRemoteError.invalidResponse("Missing Events interest confirmation")
        }
        return interest
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Only injected by the existing explicit simulator-test session.
@MainActor final class SimulatorEventsInterestRepository: EventsInterestRepository {
    private var interest: EventsInterest?
    func currentInterest() async throws -> EventsInterest? { interest }
    func registerInterest() async throws -> EventsInterest {
        let saved = interest ?? EventsInterest(createdAt: Date())
        interest = saved
        return saved
    }
}
#endif
