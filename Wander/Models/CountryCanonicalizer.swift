import Foundation

enum CountryCanonicalizer {
    private static let englishLocale = Locale(identifier: "en_US_POSIX")

    private static let localizedNames: [String: String] = {
        var names: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier.uppercased()
            guard code.count == 2,
                  code.unicodeScalars.allSatisfy(CharacterSet.letters.contains),
                  let name = englishLocale.localizedString(forRegionCode: code)
            else { continue }
            names[comparisonKey(name)] = name
        }
        return names
    }()

    static func canonicalName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let compactCode = trimmed
            .unicodeScalars
            .filter(CharacterSet.letters.contains)
            .map(String.init)
            .joined()
            .uppercased()
        if (2...3).contains(compactCode.count),
           let localized = englishLocale.localizedString(forRegionCode: compactCode) {
            return localized
        }

        return localizedNames[comparisonKey(trimmed)] ?? trimmed
    }

    private static func comparisonKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: englishLocale)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}
