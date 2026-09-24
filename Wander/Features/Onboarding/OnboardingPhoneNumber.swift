import Foundation
import PhoneNumberKit

struct PhoneCountry: Identifiable, Equatable {
    let id: String
    let name: String
    let dialingCode: String
}

/// Country-specific parsing stays outside the view. This validates formatting,
/// not ownership; only a separate verification flow could establish ownership.
@MainActor
enum OnboardingPhoneNumber {
    private static let utility = PhoneNumberUtility()

    static let countries: [PhoneCountry] = utility.allCountries().compactMap { region in
        guard region != "001", let code = utility.countryCode(for: region) else { return nil }
        return PhoneCountry(id: region, name: Locale.current.localizedString(forRegionCode: region) ?? region, dialingCode: "+\(code)")
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static func country(_ region: String?) -> PhoneCountry {
        countries.first { $0.id == region?.uppercased() }
            ?? countries.first { $0.id == "US" }
            ?? PhoneCountry(id: "US", name: "United States", dialingCode: "+1")
    }

    static func normalized(_ raw: String, country: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 64,
              text.allSatisfy({ $0.wholeNumberValue != nil || "+()-. \u{00a0}".contains($0) }),
              let number = try? utility.parse(text, withRegion: country),
              number.numberExtension == nil,
              number.countryCode == utility.countryCode(for: country)
        else { return nil }
        let national = utility.format(number, toType: .e164, withPrefix: false)
        if number.countryCode == 1, national.count != 10 { return nil }
        return utility.format(number, toType: .e164)
    }

    static func nationalDisplay(_ e164: String, country: String) -> String {
        guard let number = try? utility.parse(e164, withRegion: country) else { return "" }
        return utility.format(number, toType: .national)
    }

    static func region(for e164: String) -> String? {
        guard let number = try? utility.parse(e164, withRegion: "US") else { return nil }
        return utility.getRegionCode(of: number)
    }
}
