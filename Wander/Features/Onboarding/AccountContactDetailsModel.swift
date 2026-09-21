import Foundation
import Combine

@MainActor final class AccountContactDetailsModel: ObservableObject {
    @Published private(set) var cityText = "Los Angeles"
    @Published private(set) var homeCity: HomeCity? = .losAngeles
    @Published var metroID: String? = "los-angeles"
    @Published var homeCountryCode: String? = "US"
    @Published var phoneCountryCode: String
    @Published var phoneText = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isLocating = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didLoad = false
    private var didEditMetro = false
    private var didEditPhone = false
    private let repository: (any AccountContactDetailsRepository)?
    private let location: any HomeMetroLocationProviding
    private let userID: String
    private let cache: HomeMetroSelectionStore
    private let isCurrentAccount: () -> Bool

    init(userID: String, repository: (any AccountContactDetailsRepository)?,
         location: any HomeMetroLocationProviding = HomeMetroLocationProvider(),
         cache: HomeMetroSelectionStore = HomeMetroSelectionStore(),
         defaultCountry: String = Locale.current.region?.identifier ?? "US",
         isCurrentAccount: @escaping () -> Bool = { true }) {
        self.userID = userID
        self.repository = repository
        self.location = location
        self.cache = cache
        self.isCurrentAccount = isCurrentAccount
        phoneCountryCode = OnboardingPhoneNumber.country(defaultCountry).id
    }

    var phoneIsValid: Bool {
        phoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || OnboardingPhoneNumber.normalized(phoneText, country: phoneCountryCode) != nil
    }

    var canSave: Bool { didLoad && !isLoading && !isSaving && phoneIsValid && homeCity != nil }

    func editCity(_ text: String) {
        didEditMetro = true
        cityText = String(text.prefix(120))
        homeCity = nil
        metroID = nil
        homeCountryCode = nil
    }

    func selectCity(_ city: HomeCity) {
        didEditMetro = true
        applyCity(city)
        if !didEditPhone { phoneCountryCode = OnboardingPhoneNumber.country(city.countryCode).id }
    }

    private func applyCity(_ city: HomeCity) {
        homeCity = city
        cityText = city.name
        metroID = city.metroID
        homeCountryCode = city.countryCode
    }

    func selectMetro(_ id: String) {
        didEditMetro = true
        metroID = id
        homeCity = HomeCity.legacy(id)
        cityText = homeCity?.name ?? ""
        if let metro = HomeMetro.find(id) { homeCountryCode = metro.country }
    }

    func selectPhoneCountry(_ code: String) {
        didEditPhone = true
        phoneCountryCode = code
    }

    func editPhone(_ text: String) {
        didEditPhone = true
        phoneText = String(text.prefix(64))
    }

    func load() async {
        guard !didLoad, isCurrentAccount() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let repository else {
            errorMessage = "Your details aren’t available right now. Try again later."
            return
        }
        do {
            let saved = try await repository.currentDetails()
            guard !Task.isCancelled, isCurrentAccount() else { return }
            didLoad = true
            if let saved {
                if !didEditMetro {
                    homeCity = saved.homeCity ?? HomeCity.legacy(saved.metroID)
                    cityText = homeCity?.name ?? ""
                    metroID = saved.metroID
                    homeCountryCode = saved.homeCountryCode
                }
                if !didEditPhone {
                    phoneCountryCode = OnboardingPhoneNumber.country(saved.phoneCountryCode).id
                    phoneText = saved.phoneE164.map { OnboardingPhoneNumber.nationalDisplay($0, country: phoneCountryCode) } ?? ""
                }
                cache.remember(saved.metroID, for: userID)
                return // Saved home takes precedence over the current travel location.
            }
        } catch {
            guard !Task.isCancelled, isCurrentAccount() else { return }
            errorMessage = "Couldn’t load your saved details. Try again."
            return // Never overwrite an unread saved phone/home with empty defaults.
        }
        isLoading = false
        isLocating = true
        defer { isLocating = false }
        do {
            let suggestion = try await location.suggestion()
            guard !Task.isCancelled, isCurrentAccount(), let suggestion else { return }
            if !didEditMetro {
                if let city = suggestion.city ?? HomeCity.legacy(suggestion.metroID) {
                    applyCity(city)
                    // Preserve the legacy identifier when reading an older provider.
                    if suggestion.city == nil { metroID = suggestion.metroID }
                }
            }
            if !didEditPhone { phoneCountryCode = OnboardingPhoneNumber.country(suggestion.countryCode).id }
        } catch {
            // Denied, unavailable or timed-out location keeps manual entry available.
        }
    }

    func save() async -> Bool {
        guard canSave, isCurrentAccount(), let repository else { return false }
        // Once submitted, a late geocoder callback must not change the snapshot.
        didEditMetro = true
        didEditPhone = true
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let details = AccountContactDetails(
            metroID: metroID, homeCountryCode: homeCountryCode,
            phoneCountryCode: phoneCountryCode,
            phoneE164: OnboardingPhoneNumber.normalized(phoneText, country: phoneCountryCode),
            homeCity: homeCity
        )
        do {
            let saved = try await repository.save(details)
            guard !Task.isCancelled, isCurrentAccount() else { return false }
            cache.remember(saved.metroID, for: userID)
            return true
        } catch {
            guard !Task.isCancelled, isCurrentAccount() else { return false }
            errorMessage = "Couldn’t save your details. Try again."
            return false
        }
    }
}
