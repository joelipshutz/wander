import Foundation

struct AccountContactDetails: Codable, Equatable {
    let metroID: String?
    let homeCountryCode: String?
    let phoneCountryCode: String
    let phoneE164: String?

    enum CodingKeys: String, CodingKey {
        case metroID = "metro_id"
        case homeCountryCode = "home_country_code"
        case phoneCountryCode = "phone_country_code"
        case phoneE164 = "phone_e164"
    }
}

@MainActor protocol AccountContactDetailsRepository {
    func currentDetails() async throws -> AccountContactDetails?
    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails
}

/// Private, owner-only RPCs. Identity is derived from the authenticated JWT.
@MainActor struct SupabaseAccountContactDetailsRepository: AccountContactDetailsRepository {
    let rpc: any RemoteProcedureCalling
    private struct Empty: Encodable {}
    private struct Parameters: Encodable {
        let input_details: AccountContactDetails
    }

    func currentDetails() async throws -> AccountContactDetails? {
        let rows: [AccountContactDetails] = try await rpc.call("own_account_contact_details", params: Empty())
        return rows.first
    }

    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails {
        let rows: [AccountContactDetails] = try await rpc.call("save_own_account_contact_details", params: Parameters(input_details: details))
        guard let saved = rows.first else {
            throw WanderRemoteError.invalidResponse("Missing account details confirmation")
        }
        return saved
    }
}

/// Only the coarse home selection is cached. Phone numbers stay out of defaults.
@MainActor struct HomeMetroSelectionStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func metroID(for userID: String) -> String? {
        defaults.string(forKey: key(userID))
    }

    func remember(_ metroID: String?, for userID: String) {
        defaults.set(metroID, forKey: key(userID))
    }

    private func key(_ userID: String) -> String { "astir.homeMetro.v1.\(userID)" }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor final class SimulatorAccountContactDetailsRepository: AccountContactDetailsRepository {
    private var details: AccountContactDetails?
    func currentDetails() async throws -> AccountContactDetails? { details }
    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails {
        self.details = details
        return details
    }
}
#endif
