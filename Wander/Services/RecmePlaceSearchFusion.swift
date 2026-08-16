import Foundation

enum RecmePlaceSearchFusion {
    // Versioned, explicit policy. The semantic arm can recover semantic misses,
    // while lexical rank retains a small edge for exact/named-place behavior.
    private static let reciprocalRankOffset = 12.0
    private static let lexicalWeight = 1.0
    private static let semanticWeight = 0.9

    static func outcome(
        lexical: [PlaceCandidate],
        semantic: [PlaceCandidate],
        semanticStatus: RecmeSemanticSearchStatus,
        limit: Int
    ) -> RecmePlaceSearchOutcome {
        let lexicalRanks = uniqueRanks(lexical)
        let semanticRanks = uniqueRanks(semantic)
        let allIDs = Set(lexicalRanks.keys).union(semanticRanks.keys)
        let lexicalCandidates = uniqueCandidates(lexical)
        let semanticCandidates = uniqueCandidates(semantic)

        let matches = allIDs.map { id -> RankedMatch in
            let lexicalRank = lexicalRanks[id]
            let semanticRank = semanticRanks[id]
            var score = 0.0
            var providers: Set<RecmePlaceSearchProvider> = []

            if let lexicalRank {
                score += lexicalWeight / (reciprocalRankOffset + Double(lexicalRank))
                providers.insert(.lexical)
            }
            if let semanticRank {
                score += semanticWeight / (reciprocalRankOffset + Double(semanticRank))
                providers.insert(.semantic)
            }

            return RankedMatch(
                match: RecmePlaceSearchMatch(
                    candidate: lexicalCandidates[id] ?? semanticCandidates[id]!,
                    providers: providers
                ),
                score: score,
                lexicalRank: lexicalRank,
                semanticRank: semanticRank
            )
        }
        .sorted(by: ranksBefore)
        .prefix(max(0, limit))
        .map(\.match)

        return RecmePlaceSearchOutcome(
            matches: matches,
            lexicalCount: lexicalRanks.count,
            semanticCount: semanticRanks.count,
            overlapCount: Set(lexicalRanks.keys).intersection(semanticRanks.keys).count,
            semanticStatus: semanticStatus
        )
    }

    private struct RankedMatch {
        let match: RecmePlaceSearchMatch
        let score: Double
        let lexicalRank: Int?
        let semanticRank: Int?
    }

    private static func uniqueRanks(_ candidates: [PlaceCandidate]) -> [String: Int] {
        var ranks: [String: Int] = [:]
        for (offset, candidate) in candidates.enumerated() where ranks[candidate.id] == nil {
            ranks[candidate.id] = offset + 1
        }
        return ranks
    }

    private static func uniqueCandidates(_ candidates: [PlaceCandidate]) -> [String: PlaceCandidate] {
        candidates.reduce(into: [:]) { result, candidate in
            if result[candidate.id] == nil {
                result[candidate.id] = candidate
            }
        }
    }

    private static func ranksBefore(_ lhs: RankedMatch, _ rhs: RankedMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.lexicalRank != rhs.lexicalRank {
            return (lhs.lexicalRank ?? .max) < (rhs.lexicalRank ?? .max)
        }
        if lhs.semanticRank != rhs.semanticRank {
            return (lhs.semanticRank ?? .max) < (rhs.semanticRank ?? .max)
        }
        return lhs.match.candidate.id < rhs.match.candidate.id
    }
}
