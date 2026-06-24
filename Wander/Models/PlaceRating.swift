import Foundation

struct PlaceRating: Equatable {
    static let minimumScore = 1
    static let maximumScore = 5
    static let defaultScore = 3

    let score: Int

    init?(_ score: Int?) {
        guard let normalized = Self.normalized(score) else { return nil }
        self.score = normalized
    }

    static func normalized(_ score: Int?) -> Int? {
        guard let score else { return nil }
        return min(max(score, minimumScore), maximumScore)
    }

    static func scoreForSave(status: PlaceStatus, score: Int?) -> Int? {
        guard status == .been else { return nil }
        return normalized(score) ?? defaultScore
    }

    static func averageDisplay(_ score: Double) -> String {
        let rounded = (score * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
