import XCTest
import CoreLocation
@testable import Wander

@MainActor final class HomeCitySearchTests: XCTestCase {
    private let kyoto = HomeCity(name: "Kyoto", countryCode: "JP", region: "Kyoto")

    func testFallbackIsImmediateAndSearchIsNotLimitedToMetroCatalog() async {
        let repo = CityDetailsRepository()
        let model = AccountContactDetailsModel(userID: "fallback", repository: repo, location: CityLocation(nil))
        XCTAssertEqual(model.cityText, "Los Angeles") // Before any await/network work.
        await model.load()
        XCTAssertTrue(model.canSave)
        XCTAssertNil(HomeMetro.all.first { $0.name == kyoto.name })
        model.selectCity(kyoto)
        XCTAssertEqual(model.cityText, "Kyoto")
        XCTAssertEqual(model.phoneCountryCode, "JP")
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(repo.details?.homeCity, kyoto)
        XCTAssertEqual(repo.details?.metroID, "other")
    }

    func testLocationPrefillReusesRecentFixAndBoundsUnavailableLookup() async throws {
        let live = CountingCityLocation()
        let fix = CLLocation(latitude: 35.01, longitude: 135.77)
        let provider = HomeMetroLocationProvider(locationProvider: live, recentLocation: { fix }, reverseGeocode: { _ in self.kyoto })
        let result = try await provider.suggestion()
        XCTAssertEqual(result?.city, kyoto)
        XCTAssertEqual(live.calls, 0)
        let unavailable = HomeMetroLocationProvider(locationProvider: live, recentLocation: { nil }, reverseGeocode: { _ in nil }, budget: .milliseconds(20))
        do {
            _ = try await unavailable.suggestion()
            XCTFail("Expected the background location budget to cancel acquisition")
        } catch is CancellationError { }
        XCTAssertEqual(live.calls, 1)
    }

    func testNearestLocalityPrefillsAndSavedCityWinsOnNextLoad() async {
        let repo = CityDetailsRepository()
        let model = AccountContactDetailsModel(userID: "nearest", repository: repo,
            location: CityLocation(.init(metroID: "other", countryCode: "JP", city: kyoto)))
        await model.load()
        XCTAssertEqual(model.homeCity, kyoto)
        _ = await model.save()
        let traveling = AccountContactDetailsModel(userID: "nearest", repository: repo,
            location: CityLocation(.init(metroID: "los-angeles", countryCode: "US", city: .losAngeles)))
        await traveling.load()
        XCTAssertEqual(traveling.homeCity, kyoto)
    }

    func testLegacyUnknownHomeCanPrefillWithoutChangingSavedPhoneCountry() async {
        let repo = CityDetailsRepository()
        repo.details = .init(metroID: "other", homeCountryCode: nil, phoneCountryCode: "GB", phoneE164: "+442079460123")
        let model = AccountContactDetailsModel(userID: "legacyUnknown", repository: repo,
            location: CityLocation(.init(metroID: "other", countryCode: "JP", city: kyoto)))
        await model.load()
        XCTAssertEqual(model.homeCity, kyoto)
        XCTAssertEqual(model.phoneCountryCode, "GB")
        XCTAssertEqual(OnboardingPhoneNumber.normalized(model.phoneText, country: model.phoneCountryCode), "+442079460123")
    }

    func testUnresolvedOrClearedTextCannotBeSavedAndPhoneChoiceIsPreserved() async {
        let model = AccountContactDetailsModel(userID: "editing", repository: CityDetailsRepository(), location: CityLocation(nil))
        await model.load()
        model.editCity("Kyo")
        XCTAssertFalse(model.canSave)
        model.selectPhoneCountry("GB")
        model.selectCity(kyoto)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.phoneCountryCode, "GB")
        model.editCity("")
        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.homeCity)
    }

    func testSlowLocationAndHydrationNeverReplaceEditedText() async {
        let location = PendingCityLocation()
        let model = AccountContactDetailsModel(userID: "slow", repository: CityDetailsRepository(), location: location)
        let load = Task { await model.load() }
        await eventually { location.pending != nil }
        model.editCity("Nairo")
        location.pending?.resume(returning: .init(metroID: "other", countryCode: "JP", city: kyoto))
        await load.value
        XCTAssertEqual(model.cityText, "Nairo")
        XCTAssertNil(model.homeCity)
        let repository = PendingCityRepository()
        let restoring = AccountContactDetailsModel(userID: "slowSaved", repository: repository, location: CityLocation(nil))
        let restore = Task { await restoring.load() }
        await eventually { repository.pending != nil }
        restoring.selectCity(kyoto)
        restoring.editPhone("2025550123")
        repository.pending?.resume(returning: .init(metroID: "los-angeles", homeCountryCode: "US", phoneCountryCode: "US", phoneE164: nil, homeCity: .losAngeles))
        await restore.value
        XCTAssertEqual(restoring.homeCity, kyoto)
        XCTAssertEqual(restoring.phoneText, "2025550123")
    }

    func testKeyboardCommitOfSelectedCityDoesNotClearConfirmation() async {
        let model = AccountContactDetailsModel(userID: "commit", repository: CityDetailsRepository(), location: CityLocation(nil))
        await model.load()
        model.editCity("Kyo")
        model.selectCity(kyoto)
        model.editCity("Kyoto") // Native TextField's focus-loss commit.
        XCTAssertEqual(model.homeCity, kyoto)
        XCTAssertTrue(model.canSave)
        model.editCity("Kyot")
        XCTAssertNil(model.homeCity)
        XCTAssertFalse(model.canSave)
    }

    func testLateLocationKeepsTheCountryOfManuallySelectedCity() async {
        let location = PendingCityLocation()
        let model = AccountContactDetailsModel(userID: "countryRace", repository: CityDetailsRepository(), location: location)
        let load = Task { await model.load() }
        await eventually { location.pending != nil }
        model.selectCity(kyoto)
        location.pending?.resume(returning: .init(metroID: "los-angeles", countryCode: "US", city: .losAngeles))
        await load.value
        XCTAssertEqual(model.homeCity, kyoto)
        XCTAssertEqual(model.phoneCountryCode, "JP")
        model.selectCity(HomeCity(name: "Paris", countryCode: "FR"))
        XCTAssertEqual(model.phoneCountryCode, "FR")
    }

    func testCountyGateDoesNotConfuseSameNamedCitiesOrNeighboringCounties() {
        XCTAssertEqual(HomeCity(name: "Long Beach", countryCode: "US", region: "CA", county: "Los Angeles County").metroID, "los-angeles")
        XCTAssertEqual(HomeCity(name: "Pasadena", countryCode: "US", region: "CA", county: "Los Angeles").metroID, "los-angeles")
        XCTAssertEqual(HomeCity(name: "Pasadena", countryCode: "US", region: "TX", county: "Harris").metroID, "other")
        XCTAssertEqual(HomeCity(name: "Irvine", countryCode: "US", region: "CA", county: "Orange").metroID, "other")
        XCTAssertEqual(HomeCity(name: "Los Angeles", countryCode: "CL", region: "Biobío").metroID, "other")
        XCTAssertEqual(HomeCity(name: "Unknown", countryCode: "US", region: "CA").metroID, "other")
    }

    func testDebounceOnlyRequestsLatestTextAndCacheReturnsWithoutWaiting() async {
        let provider = CitySearchStub()
        let model = HomeCitySearchModel(provider: provider, debounce: .milliseconds(30))
        model.update("P")
        model.update("Pa")
        model.update("Par")
        await eventually { provider.queries == ["Par"] }
        provider.finish("Par", with: [.init(city: kyoto)])
        await eventually { !model.isSearching }
        model.update("")
        model.update("Par")
        XCTAssertEqual(model.suggestions.first?.city, kyoto)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(provider.queries, ["Par"])
    }

    func testOutOfOrderResponsesAndLateSelectionAreIgnored() async {
        let provider = CitySearchStub()
        let model = HomeCitySearchModel(provider: provider, debounce: .zero)
        model.update("old")
        await eventually { provider.queries.count == 1 }
        model.update("new")
        await eventually { provider.queries.count == 2 }
        provider.finish("new", with: [.init(city: kyoto)])
        await eventually { !model.isSearching }
        provider.finish("old", with: [.init(city: .losAngeles)])
        await Task.yield()
        XCTAssertEqual(model.suggestions.first?.city, kyoto)
        var selected: HomeCity?
        model.select(.init(city: kyoto)) { selected = $0 }
        await eventually { provider.selection != nil }
        model.update("")
        provider.selection?.resume(returning: kyoto)
        await Task.yield()
        XCTAssertNil(selected)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testEmptyFailureAndRetryAreDistinctAndClearCancelsResults() async {
        let provider = CitySearchStub()
        let model = HomeCitySearchModel(provider: provider, debounce: .zero)
        model.update("zzzz")
        await eventually { provider.queries.count == 1 }
        provider.finish("zzzz", with: [])
        await eventually { !model.isSearching }
        XCTAssertTrue(model.message?.hasPrefix("No matching") == true)
        model.update("offline")
        await eventually { provider.queries.count == 2 }
        provider.pending.removeValue(forKey: "offline")?.resume(throwing: URLError(.notConnectedToInternet))
        await eventually { !model.isSearching }
        XCTAssertTrue(model.message?.hasPrefix("Couldn’t") == true)
        model.retry()
        await eventually { provider.queries.count == 3 }
        model.update("")
        provider.finish("offline", with: [.init(city: kyoto)])
        await Task.yield()
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertNil(model.message)
    }

    func testCityPayloadStoresNoCoordinatesAndSupportsNonLatinNames() throws {
        let city = HomeCity(name: "京都市", countryCode: "JP", region: "京都府")
        let value = AccountContactDetails(metroID: "other", homeCountryCode: "JP", phoneCountryCode: "JP", phoneE164: nil, homeCity: city)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AccountContactDetails.self, from: data), value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(object["home_city"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["name", "country_code", "region"])
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for async state", file: file, line: line)
    }
}

@MainActor private final class CitySearchStub: HomeCitySearchProviding {
    var queries: [String] = []
    var pending: [String: CheckedContinuation<[HomeCitySuggestion], Error>] = [:]
    var selection: CheckedContinuation<HomeCity, Error>?
    func suggestions(for query: String) async throws -> [HomeCitySuggestion] {
        queries.append(query)
        return try await withCheckedThrowingContinuation { pending[query] = $0 }
    }
    func resolve(_ suggestion: HomeCitySuggestion) async throws -> HomeCity {
        try await withCheckedThrowingContinuation { selection = $0 }
    }
    func finish(_ query: String, with cities: [HomeCitySuggestion]) { pending.removeValue(forKey: query)?.resume(returning: cities) }
}

@MainActor private struct CityLocation: HomeMetroLocationProviding {
    let value: HomeMetroSuggestion?
    init(_ value: HomeMetroSuggestion?) { self.value = value }
    func suggestion() async throws -> HomeMetroSuggestion? { value }
}
@MainActor private final class PendingCityLocation: HomeMetroLocationProviding {
    var pending: CheckedContinuation<HomeMetroSuggestion?, Never>?
    func suggestion() async throws -> HomeMetroSuggestion? { await withCheckedContinuation { pending = $0 } }
}
@MainActor private final class CityDetailsRepository: AccountContactDetailsRepository {
    var details: AccountContactDetails?
    func currentDetails() async throws -> AccountContactDetails? { details }
    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails { self.details = details; return details }
}
@MainActor private final class PendingCityRepository: AccountContactDetailsRepository {
    var pending: CheckedContinuation<AccountContactDetails?, Never>?
    func currentDetails() async throws -> AccountContactDetails? { await withCheckedContinuation { pending = $0 } }
    func save(_ details: AccountContactDetails) async throws -> AccountContactDetails { details }
}

@MainActor private final class CountingCityLocation: CurrentLocationProviding {
    var calls = 0
    func currentLocation() async throws -> CLLocation {
        calls += 1
        try await Task.sleep(for: .seconds(30))
        return CLLocation(latitude: 0, longitude: 0)
    }
}
