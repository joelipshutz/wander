import Foundation
import Combine

@MainActor final class AccountContactDetailsModel: ObservableObject {
    @Published var metroID: String?
    @Published var homeCountryCode: String?
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

    var canSave: Bool { didLoad && !isLoading && !isSaving && phoneIsValid }

    func selectMetro(_ id: String) {
        didEditMetro = true
        metroID = id
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
                metroID = saved.metroID
                homeCountryCode = saved.homeCountryCode
                phoneCountryCode = OnboardingPhoneNumber.country(saved.phoneCountryCode).id
                phoneText = saved.phoneE164.map { OnboardingPhoneNumber.nationalDisplay($0, country: phoneCountryCode) } ?? ""
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
                metroID = suggestion.metroID
                homeCountryCode = suggestion.countryCode
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
            phoneE164: OnboardingPhoneNumber.normalized(phoneText, country: phoneCountryCode)
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
