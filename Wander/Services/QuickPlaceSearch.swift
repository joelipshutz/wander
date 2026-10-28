import CoreLocation
import Foundation

/// Query routing shared by the + sheet and list place search. Provider order is
/// preserved so both entry points offer the same places for the same query.
enum QuickPlaceSearch {
    static func coordinate(from value: String) -> CLLocationCoordinate2D? {
        let pattern = #"[-+]?\d{1,3}(?:\.\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let values = expression.matches(in: value, range: range).compactMap { match -> Double? in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return Double(value[swiftRange])
        }
        guard values.count == 2 else { return nil }

        let uppercased = value.uppercased()
        let latitude = uppercased.contains("S") ? -abs(values[0]) : values[0]
        let longitude = uppercased.contains("W") ? -abs(values[1]) : values[1]
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

extension WanderStore {
    func quickSearchCandidates(for text: String) async throws -> [PlaceCandidate] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if let coordinate = QuickPlaceSearch.coordinate(from: query) {
            return try await photoLocationCandidates(near: coordinate)
        }
        return try await manualCandidates(name: query, areaHint: nil, category: nil)
    }
}
