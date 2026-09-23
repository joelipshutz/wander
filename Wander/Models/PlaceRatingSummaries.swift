import Foundation

/// Public place identity only. Provider lookup must work even when every save
/// at the place is hidden, so it cannot depend on a viewer-visible save row.
struct PlaceRatingLookup: Encodable, Hashable, Sendable {
    let placeID: String?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?

    init(placeID: String?, sourceProvider: String? = nil, sourceProviderPlaceID: String? = nil) {
        self.placeID = placeID
        self.sourceProvider = sourceProvider
        self.sourceProviderPlaceID = sourceProviderPlaceID
    }

    @MainActor
    init(candidate: PlaceCandidate, knownPlaces: [LocalPlace]) {
        let matches = knownPlaces.filter { VisiblePlaceGrouping.matches($0, candidate: candidate) }
        let serverID = matches.compactMap(\.serverID).first { UUID(uuidString: $0) != nil }
        // A UUID on an unsynced local row is not a server identity.
        placeID = serverID ?? (matches.isEmpty && UUID(uuidString: candidate.id) != nil ? candidate.id : nil)
        sourceProvider = candidate.sourceProvider.isEmpty ? nil : candidate.sourceProvider
        sourceProviderPlaceID = candidate.sourceProviderPlaceID.flatMap { $0.isEmpty ? nil : $0 }
    }

    var canQuery: Bool {
        placeID != nil || (sourceProvider != nil && sourceProviderPlaceID != nil)
    }

    enum CodingKeys: String, CodingKey {
        case placeID = "input_place_id"
        case sourceProvider = "input_source_provider"
        case sourceProviderPlaceID = "input_source_provider_place_id"
    }
}

/// A server-calculated average. Never build an Astir aggregate from the
/// client's visible activity rows: that would omit hidden/private ratings.
struct PlaceRatingAggregate: Codable, Equatable, Sendable {
    static let empty = PlaceRatingAggregate()
    let score: Double?
    let count: Int

    private init() {
        score = nil
        count = 0
    }

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

struct PlaceRatingMetric: Equatable {
    let title: String
    let value: String
    let subtitle: String
    let suffix = "/5"
}

enum PlaceRatingsState: Equatable {
    case loading
    case loaded(PlaceRatingSummaries)
    case unavailable

    var metrics: [PlaceRatingMetric] {
        let titles = ["Your rating", "Friends rating", "Astir rating"]
        guard case .loaded(let summaries) = self else {
            return titles.map {
                PlaceRatingMetric(title: $0, value: "—", subtitle: self == .loading ? "Loading…" : "Unavailable")
            }
        }
        return zip(titles, [summaries.own, summaries.friends, summaries.astir]).enumerated().map { index, pair in
            let (title, aggregate) = pair
            let subtitle: String
            switch index {
            case 0: subtitle = aggregate.count == 0 ? "No rating yet" : CheckInCopy.count(aggregate.count)
            case 1: subtitle = aggregate.count == 0 ? "No visible ratings yet"
                : aggregate.count == 1 ? "1 person you follow" : "\(aggregate.count) people you follow"
            default: subtitle = aggregate.count == 0 ? "No ratings yet"
                : aggregate.count == 1 ? "1 rating" : "\(aggregate.count) ratings"
            }
            return PlaceRatingMetric(title: title, value: aggregate.score.map(PlaceRating.averageDisplay) ?? "—", subtitle: subtitle)
        }
    }
}
