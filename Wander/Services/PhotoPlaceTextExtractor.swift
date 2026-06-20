import Foundation

enum PhotoPlaceTextExtractor {
    static func searchQueries(from recognizedText: String, limit: Int = 4) -> [String] {
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map(cleanedLine)
            .filter { !$0.isEmpty }

        let placeLines = lines
            .enumerated()
            .filter { isLikelyPlaceLine($0.element) }
            .map { IndexedLine(index: $0.offset, text: $0.element, score: score($0.element)) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.index < rhs.index }
                return lhs.score > rhs.score
            }

        var queries: [String] = []
        for line in placeLines {
            appendUnique(line.text, to: &queries)

            if let context = nearbyContextLine(after: line.index, in: lines) {
                appendUnique("\(line.text) \(context)", to: &queries)
            }

            if queries.count >= limit { break }
        }

        return Array(queries.prefix(limit))
    }

    static func searchQuery(from recognizedText: String) -> String? {
        searchQueries(from: recognizedText, limit: 1).first
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
        guard !containsBlockedFragment(lowered), !isMostlyRatingOrPrice(lowered) else { return false }

        let letters = line.filter(\.isLetter).count
        let digits = line.filter(\.isNumber).count
        guard letters >= max(3, digits) else { return false }

        if isLikelyAddressLine(line) || isLikelyLocalityLine(line) {
            return false
        }

        return true
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

        return (titleCaseWords * 4) + (usefulCategoryHints * 8) + min(line.count, 44)
    }

    private static func nearbyContextLine(after index: Int, in lines: [String]) -> String? {
        let nearby = lines.dropFirst(index + 1).prefix(3)
        return nearby.first { line in
            isUsefulContextLine(line)
        }
    }

    private static func isUsefulContextLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard !containsBlockedFragment(lowered), !isMostlyRatingOrPrice(lowered) else { return false }

        return isLikelyAddressLine(line) || isLikelyLocalityLine(line)
    }

    private static func isLikelyAddressLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let streetHints = [
            "street", "st", "avenue", "ave", "road", "rd", "boulevard", "blvd",
            "drive", "dr", "lane", "ln", "way", "plaza", "place", "pl"
        ]
        return line.range(of: #"^\d{1,6}\s+"#, options: .regularExpression) != nil
            && streetHints.contains { lowered.split(separator: " ").contains(Substring($0)) }
    }

    private static func isLikelyLocalityLine(_ line: String) -> Bool {
        line.range(of: #"[A-Za-z .'-]+,\s*[A-Z]{2}(\s+\d{5})?$"#, options: .regularExpression) != nil
    }

    private static func isMostlyRatingOrPrice(_ line: String) -> Bool {
        line.range(of: #"^\$+\d*(\.\d{2})?$"#, options: .regularExpression) != nil
            || line.range(of: #"^\d(\.\d)?\s*(stars?|★|\([0-9,]+\))"#, options: [.regularExpression, .caseInsensitive]) != nil
            || line.range(of: #"^[0-9,]+\s+(reviews?|ratings?)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsBlockedFragment(_ loweredLine: String) -> Bool {
        let blockedFragments = [
            "receipt", "subtotal", "total", "amount", "visa", "mastercard",
            "invoice", "table", "qty", "http", "www.", "@", "#",
            "directions", "route", "website", "call", "share", "save",
            "overview", "reviews", "photos", "menu", "hours", "closed",
            "open now", "opens ", "order online", "delivery", "pickup",
            "sponsored", "advertisement"
        ]
        return blockedFragments.contains(where: loweredLine.contains)
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        values.append(value)
    }

    private struct IndexedLine {
        let index: Int
        let text: String
        let score: Int
    }
}
