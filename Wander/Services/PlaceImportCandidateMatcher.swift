import CoreLocation
import Foundation

struct PlaceImportCandidateMatch: Equatable {
    let candidates: [PlaceCandidate]
    let selectedCandidateID: String?
    let bestScore: Double
}

enum PlaceImportCandidateMatcher {
    static func match(
        _ candidates: [PlaceCandidate],
        nameHint: String?,
        areaHint: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        allowNearSpellingMatch: Bool = false
    ) -> PlaceImportCandidateMatch {
        guard !candidates.isEmpty else {
            return PlaceImportCandidateMatch(candidates: [], selectedCandidateID: nil, bestScore: 0)
        }
        guard let nameHint = nameHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nameHint.isEmpty
        else {
            return PlaceImportCandidateMatch(
                candidates: candidates,
                selectedCandidateID: candidates.count == 1 ? candidates[0].id : nil,
                bestScore: candidates.count == 1 ? 0.7 : 0
            )
        }

        let scored = candidates.enumerated().map { index, candidate in
            (
                candidate: candidate,
                score: score(
                    candidate,
                    nameHint: nameHint,
                    areaHint: areaHint,
                    latitude: latitude,
                    longitude: longitude
                ),
                index: index
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.index < rhs.index }
            return lhs.score > rhs.score
        }

        let best = scored[0]
        let runnerUpScore = scored.dropFirst().first?.score ?? 0
        let exactName = normalized(best.candidate.name) == normalized(nameHint)
        let exactCoreName = coreTokens(best.candidate.name) == coreTokens(nameHint)
            && !coreTokens(nameHint).isEmpty
        let nearSpellingName = allowNearSpellingMatch
            && isNearSpellingMatch(best.candidate.name, nameHint)
        let exactEquivalentCount = scored.filter { scoredCandidate in
            normalized(scoredCandidate.candidate.name) == normalized(nameHint)
                || (coreTokens(scoredCandidate.candidate.name) == coreTokens(nameHint)
                    && !coreTokens(nameHint).isEmpty)
                || (allowNearSpellingMatch
                    && isNearSpellingMatch(scoredCandidate.candidate.name, nameHint))
        }.count
        let hasClearLead = best.score - runnerUpScore >= 0.08
        let isUniqueExactMatch = (exactName || exactCoreName || nearSpellingName)
            && exactEquivalentCount == 1
        let selectedID = (isUniqueExactMatch || (best.score >= 0.82 && hasClearLead))
            ? best.candidate.id
            : nil

        return PlaceImportCandidateMatch(
            candidates: scored.map(\.candidate),
            selectedCandidateID: selectedID,
            bestScore: best.score
        )
    }

    private static func score(
        _ candidate: PlaceCandidate,
        nameHint: String,
        areaHint: String?,
        latitude: Double?,
        longitude: Double?
    ) -> Double {
        let hintKey = normalized(nameHint)
        let candidateKey = normalized(candidate.name)
        let hintTokens = tokens(nameHint)
        let candidateTokens = tokens(candidate.name)
        let hintCore = coreTokens(nameHint)
        let candidateCore = coreTokens(candidate.name)

        var score: Double
        if hintKey == candidateKey {
            score = 0.82
        } else if hintCore == candidateCore, !hintCore.isEmpty {
            score = 0.8
        } else if min(hintKey.count, candidateKey.count) >= 5,
                  hintKey.contains(candidateKey) || candidateKey.contains(hintKey) {
            score = 0.72
        } else {
            let intersection = hintTokens.intersection(candidateTokens).count
            let union = hintTokens.union(candidateTokens).count
            score = union == 0 ? 0 : Double(intersection) / Double(union) * 0.68
        }

        if let areaHint = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines), !areaHint.isEmpty {
            let areaTokens = tokens(areaHint)
            let candidateArea = [candidate.address, candidate.locality, candidate.region, candidate.country]
                .compactMap { $0 }
                .joined(separator: " ")
            let candidateAreaTokens = tokens(candidateArea)
            let overlapCount = areaTokens.intersection(candidateAreaTokens).count
            if overlapCount > 0 {
                let denominator = max(1, min(areaTokens.count, candidateAreaTokens.count))
                score += min(0.1, Double(overlapCount) / Double(denominator) * 0.1)
            }
        }

        if let latitude,
           let longitude,
           let candidateLatitude = candidate.latitude,
           let candidateLongitude = candidate.longitude {
            let source = CLLocation(latitude: latitude, longitude: longitude)
            let target = CLLocation(latitude: candidateLatitude, longitude: candidateLongitude)
            switch target.distance(from: source) {
            case ...500:
                score += 0.1
            case ...3_000:
                score += 0.06
            case ...10_000:
                score += 0.02
            case 25_000...:
                score -= 0.12
            default:
                break
            }
        }

        return max(0, min(1, score))
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func coreTokens(_ value: String) -> Set<String> {
        tokens(value).subtracting([
            "the", "restaurant", "restaurants", "eatery", "company", "co", "inc", "llc"
        ])
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isNearSpellingMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsCharacters = Array(normalized(lhs))
        let rhsCharacters = Array(normalized(rhs))
        guard min(lhsCharacters.count, rhsCharacters.count) >= 8,
              abs(lhsCharacters.count - rhsCharacters.count) <= 1
        else { return false }

        var lhsIndex = 0
        var rhsIndex = 0
        var edits = 0
        while lhsIndex < lhsCharacters.count, rhsIndex < rhsCharacters.count {
            if lhsCharacters[lhsIndex] == rhsCharacters[rhsIndex] {
                lhsIndex += 1
                rhsIndex += 1
                continue
            }
            edits += 1
            guard edits <= 1 else { return false }
            if lhsCharacters.count > rhsCharacters.count {
                lhsIndex += 1
            } else if rhsCharacters.count > lhsCharacters.count {
                rhsIndex += 1
            } else {
                lhsIndex += 1
                rhsIndex += 1
            }
        }
        if lhsIndex < lhsCharacters.count || rhsIndex < rhsCharacters.count {
            edits += 1
        }
        return edits == 1
    }
}
