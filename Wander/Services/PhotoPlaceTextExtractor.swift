import CoreLocation
import Foundation
import ImageIO

@MainActor
protocol PhotoPlaceCandidateSearching {
    func photoTextCandidates(for query: String) async throws -> [PlaceCandidate]
    func photoLocationCandidates(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate]
}

struct PhotoPlaceImportResolution: Equatable {
    enum Outcome: Equatable {
        case candidates
        case manualRescue
        case draft
    }

    enum Source: Equatable {
        case recognizedText
        case photoLocation
        case none
    }

    let outcome: Outcome
    let source: Source
    let candidates: [PlaceCandidate]
    let manualName: String?
    let message: String?
}

@MainActor
enum PhotoPlaceImportResolver {
    static func resolve(
        recognizedText: String?,
        photoCoordinate: CLLocationCoordinate2D?,
        searcher: PhotoPlaceCandidateSearching
    ) async -> PhotoPlaceImportResolution {
        let queries = recognizedText
            .map { PhotoPlaceTextExtractor.searchQueries(from: $0, limit: 8) } ?? []

        for query in queries {
            if let candidates = try? await searcher.photoTextCandidates(for: query),
               !candidates.isEmpty {
                return PhotoPlaceImportResolution(
                    outcome: .candidates,
                    source: .recognizedText,
                    candidates: candidates,
                    manualName: query,
                    message: nil
                )
            }
        }

        if let photoCoordinate,
           let candidates = try? await searcher.photoLocationCandidates(near: photoCoordinate),
           !candidates.isEmpty {
            return PhotoPlaceImportResolution(
                outcome: .candidates,
                source: .photoLocation,
                candidates: candidates,
                manualName: candidates.first?.name,
                message: "Found nearby places from this photo's location."
            )
        }

        if let manualName = queries.first {
            return PhotoPlaceImportResolution(
                outcome: .manualRescue,
                source: .recognizedText,
                candidates: [],
                manualName: manualName,
                message: "Read \"\(manualName)\" from the photo. Confirm or edit it, then tap find this place."
            )
        }

        return PhotoPlaceImportResolution(
            outcome: .draft,
            source: .none,
            candidates: [],
            manualName: nil,
            message: "We could not read a place from that photo yet. Add it manually if you want it on your map now."
        )
    }
}

enum PhotoPlaceMetadataExtractor {
    static func coordinate(from imageData: Data) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [AnyHashable: Any],
              let gps = dictionaryValue(for: kCGImagePropertyGPSDictionary, in: properties),
              let latitude = doubleValue(for: kCGImagePropertyGPSLatitude, in: gps),
              let longitude = doubleValue(for: kCGImagePropertyGPSLongitude, in: gps)
        else {
            return nil
        }

        let latitudeRef = stringValue(for: kCGImagePropertyGPSLatitudeRef, in: gps)?.uppercased()
        let longitudeRef = stringValue(for: kCGImagePropertyGPSLongitudeRef, in: gps)?.uppercased()
        let signedLatitude = latitudeRef == "S" ? -abs(latitude) : abs(latitude)
        let signedLongitude = longitudeRef == "W" ? -abs(longitude) : abs(longitude)
        let coordinate = CLLocationCoordinate2D(latitude: signedLatitude, longitude: signedLongitude)

        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    private static func dictionaryValue(for key: CFString, in dictionary: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        value(for: key, in: dictionary) as? [AnyHashable: Any]
    }

    private static func doubleValue(for key: CFString, in dictionary: [AnyHashable: Any]) -> Double? {
        let rawValue = value(for: key, in: dictionary)

        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }

        if let value = rawValue as? Double {
            return value
        }

        if let value = rawValue as? String {
            return Double(value)
        }

        return nil
    }

    private static func stringValue(for key: CFString, in dictionary: [AnyHashable: Any]) -> String? {
        value(for: key, in: dictionary) as? String
    }

    private static func value(for key: CFString, in dictionary: [AnyHashable: Any]) -> Any? {
        dictionary[key] ?? dictionary[key as String]
    }
}

enum PhotoPlaceTextExtractor {
    static func searchQueries(from recognizedText: String, limit: Int = 8) -> [String] {
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
        let blockedExactLines = [
            "apple maps", "search", "top result"
        ]
        guard !blockedExactLines.contains(loweredLine) else { return true }

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
