import Foundation

struct EventsMarketAccess: Decodable, Equatable {
    let metroID: String?
    enum CodingKeys: String, CodingKey { case metroID = "metro_id" }
}

@MainActor protocol EventsAccessRepository {
    func currentAccess() async throws -> EventsMarketAccess?
}

/// Only the home metro is fetched for the tab gate, never a phone number or GPS.
@MainActor struct SupabaseEventsAccessRepository: EventsAccessRepository {
    let rpc: any RemoteProcedureCalling
    private struct Empty: Encodable {}
    func currentAccess() async throws -> EventsMarketAccess? {
        let rows: [EventsMarketAccess] = try await rpc.call("own_events_market_access", params: Empty())
        return rows.first
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor struct SimulatorEventsAccessRepository: EventsAccessRepository {
    let details: SimulatorAccountContactDetailsRepository
    func currentAccess() async throws -> EventsMarketAccess? {
        EventsMarketAccess(metroID: try await details.currentDetails()?.metroID)
    }
}
#endif
