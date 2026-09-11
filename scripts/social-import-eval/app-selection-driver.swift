import Foundation

// Wire-only value type. Every field read by the unchanged production matcher
// is supplied; category assignment does not participate in this matcher.
struct PlaceCandidate: Equatable, Codable {
    let id: String
    let name: String
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let areaComponents: [String]?
    let latitude: Double?
    let longitude: Double?
}

private struct Input: Decodable {
    let hints: [Hint]
}

private struct Hint: Decodable {
    let name: String
    let area: String?
    let modality: String
    let classification: String
    let resolved_places: [ResolvedPlace]?
}

private struct ResolvedPlace: Decodable {
    let provider: String
    let provider_place_id: String
    let name: String
    let formatted_address: String?
    let locality: String?
    let region: String?
    let country: String?
    let area_components: [String]?
    let latitude: Double
    let longitude: Double
}

private struct Row: Encodable {
    let name: String
    let area: String?
    let selectedCandidateID: String?
    let bestScore: Double
    let candidates: [PlaceCandidate]
    let status: String
}

private struct Output: Encodable {
    let rows: [Row]
    let selectedCount: Int
    let duplicateSelectedCount: Int
}

@main
private enum AppSelectionDriver {
    static func main() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 8_000_000 else { throw Failure.invalidInput }
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard input.hints.count <= 150 else { throw Failure.invalidInput }
        var seenHints = Set<String>()
        var selectedIDs = Set<String>()
        var duplicateSelectedCount = 0
        let rows = input.hints.compactMap { hint -> Row? in
            guard ["destination", "itinerary"].contains(hint.classification),
                  ["tagged_location", "image_text", "video_text", "caption", "speech"].contains(hint.modality),
                  let name = cleaned(hint.name, maximum: 160) else { return nil }
            let area = cleaned(hint.area, maximum: 160)
            let identity = [name, area ?? ""].joined(separator: "|")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenHints.insert(identity).inserted else { return nil }
            var seenPlaces = Set<String>()
            let decodedCandidates = (hint.resolved_places ?? []).prefix(3).compactMap { place -> PlaceCandidate? in
                guard place.provider == "google_places",
                      let id = cleaned(place.provider_place_id, maximum: 300),
                      seenPlaces.insert(id).inserted,
                      let name = cleaned(place.name, maximum: 200),
                      place.latitude.isFinite, (-90...90).contains(place.latitude),
                      place.longitude.isFinite, (-180...180).contains(place.longitude)
                else { return nil }
                return PlaceCandidate(
                    id: "google-places-\(id)", name: name,
                    address: cleaned(place.formatted_address, maximum: 500),
                    locality: cleaned(place.locality, maximum: 160),
                    region: cleaned(place.region, maximum: 160),
                    country: cleaned(place.country, maximum: 160),
                    areaComponents: place.area_components.map { Array($0.prefix(8)).compactMap { cleaned($0, maximum: 160) } },
                    latitude: place.latitude, longitude: place.longitude
                )
            }
            let candidates = SocialImportCountry.candidatesCompatibleWithExactCountry(decodedCandidates, areaHint: area)
            let match = PlaceImportCandidateMatcher.match(
                candidates, nameHint: name, areaHint: area,
                allowNearSpellingMatch: ["image_text", "video_text"].contains(hint.modality),
                selectionPolicy: .socialGroundedArea
            )
            let status: String
            if let selectedID = match.selectedCandidateID {
                if selectedIDs.insert(selectedID).inserted {
                    status = "selected"
                } else {
                    status = "duplicate_selected"
                    duplicateSelectedCount += 1
                }
            } else {
                status = candidates.isEmpty ? "needs_lookup" : "needs_review"
            }
            return Row(name: name, area: area, selectedCandidateID: match.selectedCandidateID,
                       bestScore: match.bestScore, candidates: match.candidates, status: status)
        }
        let output = Output(rows: rows, selectedCount: selectedIDs.count, duplicateSelectedCount: duplicateSelectedCount)
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }

    private enum Failure: Error { case invalidInput }

    private static func cleaned(_ value: String?, maximum: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return cleaned.isEmpty || cleaned.count > maximum ? nil : cleaned
    }
}
