import Foundation
import XCTest
@testable import Wander

final class ImportCandidateMatchingPerformanceTests: XCTestCase {
    /// Pure local matching work; each round represents one four-place import
    /// with five provider alternatives per place. No resolver or network runs.
    func testPerformanceCandidateMatchingAcrossSelectionPolicies() {
        let cases = scenarios()
        let iterations = 150
        let expected = cases.map { $0.match() }
        for (scenario, result) in zip(cases, expected) {
            XCTAssertEqual(result.selectedCandidateID, scenario.selectedID)
            XCTAssertEqual(result.candidates.map(\.id), scenario.candidates.map(\.id))
            XCTAssertEqual(result.bestScore, scenario.bestScore, accuracy: 0.000_001)
        }

        var samples: [Double] = []
        for _ in 0..<3 {
            var selectedCount = 0
            var candidateCount = 0
            var scoreTotal = 0.0
            var finalResults: [PlaceImportCandidateMatch] = []
            let startedAt = ProcessInfo.processInfo.systemUptime
            for _ in 0..<iterations {
                finalResults = cases.map { $0.match() }
                for result in finalResults {
                    if result.selectedCandidateID != nil { selectedCount += 1 }
                    candidateCount += result.candidates.count
                    scoreTotal += result.bestScore
                }
            }
            samples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            XCTAssertEqual(finalResults, expected)
            XCTAssertEqual(selectedCount, 3 * iterations)
            XCTAssertEqual(candidateCount, 20 * iterations)
            XCTAssertEqual(scoreTotal, cases.reduce(0) { $0 + $1.bestScore } * Double(iterations), accuracy: 0.000_001)
        }
        let attachment = XCTAttachment(string:
            "REC675 import_candidate_matching calls_per_sample=\(iterations * cases.count) candidates_per_call=5 samples_ms=\(samples) median_ms=\(samples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Scenario {
        let candidates: [PlaceCandidate]
        let hint: String
        var area: String? = nil
        var nearSpelling = false
        var policy: PlaceImportCandidateSelectionPolicy = .conservative
        let selectedID: String?
        let bestScore: Double

        func match() -> PlaceImportCandidateMatch {
            PlaceImportCandidateMatcher.match(candidates, nameHint: hint, areaHint: area,
                allowNearSpellingMatch: nearSpelling, selectionPolicy: policy)
        }
    }

    private func scenarios() -> [Scenario] {
        let alternatives = ["Juniper Market", "Sunset Park", "Summit Museum", "Harbor Deli"]
        let exact = [candidate("exact", "Crisp Coffee")]
            + alternatives.enumerated().map { candidate("exact-other-\($0.offset)", $0.element) }
        let ambiguous = [candidate("branch-first", "Crisp Coffee"), candidate("branch-second", "Crisp Coffee")]
            + alternatives.prefix(3).enumerated().map { candidate("branch-other-\($0.offset)", $0.element) }
        let grounded = [
            candidate("landmark-first", "Griffith Observatory", latitude: 34.118105, longitude: -118.300376),
            candidate("landmark-second", "Griffith Observatory", latitude: 34.118099, longitude: -118.300400)
        ] + alternatives.prefix(3).enumerated().map { candidate("landmark-other-\($0.offset)", $0.element) }
        let spelling = [candidate("ocr", "Crisp Coffee")]
            + alternatives.enumerated().map { candidate("ocr-other-\($0.offset)", $0.element) }
        return [
            Scenario(candidates: exact, hint: "Crisp Coffee", selectedID: "exact", bestScore: 0.82),
            Scenario(candidates: ambiguous, hint: "Crisp Coffee", selectedID: nil, bestScore: 0.82),
            Scenario(candidates: grounded, hint: "Griffith Observatory", area: "Los Angeles, California",
                policy: .socialGroundedArea, selectedID: "landmark-first", bestScore: 0.92),
            Scenario(candidates: spelling, hint: "Crisp Coffea", nearSpelling: true, selectedID: "ocr", bestScore: 0.78)
        ]
    }

    private func candidate(_ id: String, _ name: String,
                           latitude: Double = 34.05, longitude: Double = -118.25) -> PlaceCandidate {
        PlaceCandidate(id: id, name: name, category: "place", locality: "Los Angeles", region: "CA",
            latitude: latitude, longitude: longitude, sourceProvider: "fixture",
            sourceProviderPlaceID: id, confidence: 1)
    }
}
