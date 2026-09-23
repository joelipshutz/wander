import XCTest
@testable import Wander

@MainActor final class AccountContactDetailsTests: XCTestCase {
    func testLAUsesCountyIncludingDistantCitiesAndExcludesOrangeCounty() {
        XCTAssertEqual(suggest(34.70, -118.14, county: "Los Angeles County"), "los-angeles") // Lancaster
        XCTAssertEqual(suggest(33.77, -118.19, county: "Los Angeles"), "los-angeles") // Long Beach
        XCTAssertEqual(suggest(33.83, -117.91, county: "Orange County"), "orange-county") // Anaheim
        XCTAssertEqual(suggest(34.00, -117.38, county: "Riverside County"), "inland-empire")
        XCTAssertNil(suggest(34.05, -118.24, county: nil))
        XCTAssertNotEqual(suggest(34.27, -119.23, county: "Ventura County"), "los-angeles")
    }

    func testRuralAndInvalidLocationsDoNotInventAMetro() {
        XCTAssertEqual(HomeMetro.suggestedID(latitude: 46.88, longitude: -102.79, country: "US", state: "ND", county: nil), HomeMetro.otherID)
        XCTAssertNil(HomeMetro.suggestedID(latitude: .nan, longitude: 0, country: "US", state: nil, county: nil))
        XCTAssertEqual(HomeMetro.suggestedID(latitude: 51.5, longitude: -0.1, country: "GB", state: nil, county: nil), "london")
        XCTAssertEqual(Set(HomeMetro.all.map(\.id)).count, HomeMetro.all.count)
    }

    func testUSPhoneRequiresTenNationalDigitsAndAcceptsPaste() {
        XCTAssertEqual(OnboardingPhoneNumber.normalized("2025550123", country: "US"), "+12025550123")
        XCTAssertEqual(OnboardingPhoneNumber.normalized("+1 (202) 555-0123", country: "US"), "+12025550123")
        XCTAssertEqual(OnboardingPhoneNumber.normalized("1 202 555 0123", country: "US"), "+12025550123")
        XCTAssertNil(OnboardingPhoneNumber.normalized("202555012", country: "US"))
        XCTAssertNil(OnboardingPhoneNumber.normalized("20255501234", country: "US"))
        XCTAssertNil(OnboardingPhoneNumber.normalized("+1 2025550123 ext 5", country: "US"))
        XCTAssertNil(OnboardingPhoneNumber.normalized("+44 20 7946 0123", country: "US"))
    }

    func testInternationalNationalPrefixesAndLengths() {
        XCTAssertEqual(OnboardingPhoneNumber.normalized("020 7946 0123", country: "GB"), "+442079460123")
        XCTAssertEqual(OnboardingPhoneNumber.normalized("02 1234 5678", country: "IT"), "+390212345678")
        XCTAssertEqual(OnboardingPhoneNumber.normalized("0412 345 678", country: "AU"), "+61412345678")
        XCTAssertEqual(OnboardingPhoneNumber.country("GB").dialingCode, "+44")
        XCTAssertEqual(OnboardingPhoneNumber.country("unknown").id, "US")
    }

    func testSavedHomeWinsOverTravelAndRemainsAccountScoped() async {
        let repo = DetailsRepository()
        repo.details = .init(metroID: "los-angeles", homeCountryCode: "US", phoneCountryCode: "US", phoneE164: "+12025550123")
        let location = DetailsLocation(.init(metroID: "london", countryCode: "GB"))
        let suite = "AccountContactDetailsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = HomeMetroSelectionStore(defaults: defaults)
        let model = AccountContactDetailsModel(userID: "owner", repository: repo, location: location, cache: cache)
        await model.load()
        XCTAssertEqual(model.metroID, "los-angeles")
        XCTAssertEqual(location.calls, 0)
        XCTAssertEqual(cache.metroID(for: "owner"), "los-angeles")
        XCTAssertNil(cache.metroID(for: "other"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("2025550123") })
    }

    func testLocationPrefillsCountryAndMetroAndSaveNormalizesPhone() async {
        let repo = DetailsRepository()
        let model = AccountContactDetailsModel(userID: "new", repository: repo, location: DetailsLocation(.init(metroID: "london", countryCode: "GB")), defaultCountry: "US")
        await model.load()
        XCTAssertEqual(model.metroID, "london")
        XCTAssertEqual(model.phoneCountryCode, "GB")
        model.editPhone("020 7946 0123")
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(repo.details?.phoneE164, "+442079460123")
    }

    func testDeniedLocationAllowsManualEntryAndOptionalPhone() async {
        let repo = DetailsRepository()
        let location = DetailsLocation(nil)
        let model = AccountContactDetailsModel(userID: "denied", repository: repo, location: location, defaultCountry: "US")
        await model.load()
        XCTAssertTrue(model.canSave)
        model.selectMetro("los-angeles")
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertNil(repo.details?.phoneE164)
        XCTAssertEqual(repo.details?.homeCountryCode, "US")
    }

    func testFailedHydrationCannotOverwriteExistingDetails() async {
        let repo = DetailsRepository()
        repo.fails = true
        let model = AccountContactDetailsModel(userID: "failure", repository: repo, location: DetailsLocation(nil))
        await model.load()
        XCTAssertFalse(model.canSave)
        XCTAssertNotNil(model.errorMessage)
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(repo.saves, 0)
        repo.fails = false
        await model.load()
        XCTAssertTrue(model.canSave)
    }

    func testFailedSaveStaysInFormAndPreservesEdits() async {
        let repo = DetailsRepository()
        let model = AccountContactDetailsModel(userID: "failure", repository: repo, location: DetailsLocation(nil), defaultCountry: "US")
        await model.load()
        model.editPhone("2025550123")
        repo.fails = true
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.phoneText, "2025550123")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSaving)
    }

    func testLateLocationDoesNotOverwriteManualChoices() async {
        let location = DeferredDetailsLocation()
        let model = AccountContactDetailsModel(userID: "editing", repository: DetailsRepository(), location: location, defaultCountry: "US")
        let task = Task { await model.load() }
        while location.continuation == nil { await Task.yield() }
        model.selectMetro("new-york")
        model.selectPhoneCountry("CA")
        location.continuation?.resume(returning: .init(metroID: "london", countryCode: "GB"))
        await task.value
        XCTAssertEqual(model.metroID, "new-york")
        XCTAssertEqual(model.phoneCountryCode, "CA")
    }

    func testAccountChangeDiscardsLateLocationAndBlocksSave() async {
        var current = true
        let location = DeferredDetailsLocation()
        let model = AccountContactDetailsModel(userID: "leaving", repository: DetailsRepository(), location: location, isCurrentAccount: { current })
        let task = Task { await model.load() }
        while location.continuation == nil { await Task.yield() }
        current = false
        location.continuation?.resume(returning: .init(metroID: "los-angeles", countryCode: "US"))
        await task.value
        XCTAssertEqual(model.metroID, "los-angeles") // Immediate fallback remains; the late account result is ignored.
        let saved = await model.save()
        XCTAssertFalse(saved)
    }

    func testPrivateRPCErrorsAreRedacted() {
        XCTAssertTrue(WanderSupabaseClient.redactsAccountDetailsResponse(for: "save_own_account_contact_details"))
        XCTAssertTrue(WanderSupabaseClient.redactsAccountDetailsResponse(for: "own_account_contact_details"))
        XCTAssertFalse(WanderSupabaseClient.redactsAccountDetailsResponse(for: "current_profile"))
    }

    func testRepositoryUsesOwnerRPCsAndEncodesNormalizedPrivatePayload() async throws {
        let rpc = DetailsRPC()
        let repository = SupabaseAccountContactDetailsRepository(rpc: rpc)
        let empty = try await repository.currentDetails()
        XCTAssertNil(empty)
        rpc.response = "[{\"metro_id\":\"los-angeles\",\"home_country_code\":\"US\",\"phone_country_code\":\"US\",\"phone_e164\":\"+12025550123\"}]"
        let value = AccountContactDetails(metroID: "los-angeles", homeCountryCode: "US", phoneCountryCode: "US", phoneE164: "+12025550123")
        let saved = try await repository.save(value)
        XCTAssertEqual(saved, value)
        XCTAssertEqual(rpc.names, ["own_account_contact_details", "save_own_account_contact_details"])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: rpc.parameters[1]) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["input_details"])
        let details = try XCTUnwrap(payload["input_details"] as? [String: Any])
        XCTAssertEqual(details["phone_e164"] as? String, "+12025550123")
        XCTAssertNil(details["user_id"])
        XCTAssertNil(details["latitude"])
        XCTAssertNil(details["phone_verified"])
    }

    func testRepositoryRejectsMissingSaveConfirmation() async throws {
        let repository = SupabaseAccountContactDetailsRepository(rpc: DetailsRPC())
        do {
            _ = try await repository.save(.init(metroID: nil, homeCountryCode: nil, phoneCountryCode: "US", phoneE164: nil))
            XCTFail("An empty response cannot confirm persistence")
        } catch {
            XCTAssertTrue(error is WanderRemoteError)
        }
    }

    private func suggest(_ lat: Double, _ lon: Double, county: String?) -> String? {
        HomeMetro.suggestedID(latitude: lat, longitude: lon, country: "US", state: "CA", county: county)
    }
}

@MainActor private final class DetailsRPC: RemoteProcedureCalling {
    var response = "[]"
    var names: [String] = []
    var parameters: [Data] = []
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        names.append(name)
        parameters.append(try JSONEncoder().encode(params))
        return try decoder.decode(Value.self, from: Data(response.utf8))
    }
}

@MainActor private final class DetailsRepository: AccountContactDetailsRepository {
    var details: AccountContactDetails?
    var fails = false
    var saves = 0
    func currentDetails() async throws -> AccountContactDetails? {
        if fails { throw URLError(.notConnectedToInternet) }
        return details
    }
    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails {
        saves += 1
        if fails { throw URLError(.notConnectedToInternet) }
        self.details = details
        return details
    }
}

@MainActor private final class DetailsLocation: HomeMetroLocationProviding {
    let value: HomeMetroSuggestion?
    var calls = 0
    init(_ value: HomeMetroSuggestion?) { self.value = value }
    func suggestion() async throws -> HomeMetroSuggestion? { calls += 1; return value }
}

@MainActor private final class DeferredDetailsLocation: HomeMetroLocationProviding {
    var continuation: CheckedContinuation<HomeMetroSuggestion?, Never>?
    func suggestion() async throws -> HomeMetroSuggestion? {
        await withCheckedContinuation { continuation = $0 }
    }
}
