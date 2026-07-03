import Foundation

struct PlaceRating: Equatable {
    static let minimumScore = 1.0
    static let maximumScore = 5.0
    static let defaultScore = 3.0
    static let step = 0.5
    static let allowedScores = stride(from: minimumScore, through: maximumScore, by: step).map { $0 }

    let score: Double

    init?(_ score: Double?) {
        guard let normalized = Self.normalized(score) else { return nil }
        self.score = normalized
    }

    static func normalized(_ score: Double?) -> Double? {
        guard let score else { return nil }
        let clamped = min(max(score, minimumScore), maximumScore)
        return (clamped / step).rounded() * step
    }

    static func scoreForSave(status: PlaceStatus, score: Double?) -> Double? {
        guard status == .been else { return nil }
        return normalized(score) ?? defaultScore
    }

    static func display(_ score: Double) -> String {
        averageDisplay(score)
    }

    static func averageDisplay(_ score: Double) -> String {
        let rounded = (score * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
