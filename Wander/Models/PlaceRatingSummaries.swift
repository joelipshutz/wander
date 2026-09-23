import Foundation

/// A server-calculated average. Never build an Astir aggregate from the
/// client's visible activity rows: that would omit hidden/private ratings.
struct PlaceRatingAggregate: Codable, Equatable, Sendable {
    let score: Double?
    let count: Int

    init(score: Double?, count: Int) throws {
        guard count >= 0,
              (count == 0 && score == nil)
                || (count > 0 && score.map { $0.isFinite && (1 ... 5).contains($0) } == true)
        else { throw ValidationError.invalidAggregate }
        self.score = score
        self.count = count
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let score = try container.decodeIfPresent(Double.self, forKey: .score)
        let count = try container.decode(Int.self, forKey: .count)
        do {
            try self.init(score: score, count: count)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid rating score/count pair"
            ))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case score, count
    }

    enum ValidationError: Error {
        case invalidAggregate
    }
}

/// Three independent aggregates, with deliberately explicit denominators:
/// own/astir count rated check-ins; friends counts followed people with at
/// least one readable rated check-in. No author IDs or hidden activity payloads.
/// The RPC must return all three; an omitted aggregate is not an empty result.
struct PlaceRatingSummaries: Codable, Equatable, Sendable {
    let own: PlaceRatingAggregate
    let friends: PlaceRatingAggregate
    let astir: PlaceRatingAggregate
}
