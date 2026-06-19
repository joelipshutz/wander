import Foundation

enum PhotoPlaceTextExtractor {
    static func searchQuery(from recognizedText: String) -> String? {
        recognizedText
            .components(separatedBy: .newlines)
            .map(cleanedLine)
            .filter(isLikelyPlaceLine)
            .max { lhs, rhs in score(lhs) < score(rhs) }
    }

    private static func cleanedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyPlaceLine(_ line: String) -> Bool {
        guard line.count >= 3,
              line.count <= 80,
              line.range(of: "[A-Za-z]", options: .regularExpression) != nil
        else { return false }

        let lowered = line.lowercased()
        let blockedFragments = [
            "receipt", "subtotal", "total", "amount", "visa", "mastercard",
            "order", "invoice", "table", "qty", "http", "www.", "@", "#"
        ]
        guard !blockedFragments.contains(where: lowered.contains) else { return false }

        let letters = line.filter(\.isLetter).count
        let digits = line.filter(\.isNumber).count
        return letters >= max(3, digits)
    }

    private static func score(_ line: String) -> Int {
        let titleCaseWords = line.split(separator: " ").filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }.count
        let usefulCategoryHints = [
            "cafe", "coffee", "restaurant", "market", "bar", "bakery",
            "shrine", "temple", "park", "hotel", "gallery", "museum"
        ].filter { line.lowercased().contains($0) }.count

        return (titleCaseWords * 3) + (usefulCategoryHints * 5) + min(line.count, 40)
    }
}
