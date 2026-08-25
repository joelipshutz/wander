import CoreLocation
import Foundation
import SwiftUI

struct PlaceCardRatingPresentation: Equatable {
    enum Source: Equatable {
        case recme
        case provider(displayName: String)
    }

    let score: Double
    let count: Int?
    let source: Source

    var scoreText: String {
        String(format: "%.1f", score)
    }

    var providerDisplayName: String? {
        guard case .provider(let displayName) = source else { return nil }
        return displayName
    }
}

struct PlaceCardHoursPresentation: Equatable {
    let isOpen: Bool
    let statusText: String
    let detailText: String?
}

enum PlaceCardPresentation {
    static func rating(
        providerScore: Double?,
        providerCount: Int?,
        recmeRating: PlaceActualRating?,
        providerName: String? = nil
    ) -> PlaceCardRatingPresentation? {
        if let recmeRating, recmeRating.count > 0 {
            guard (1 ... 5).contains(recmeRating.score) else { return nil }
            return PlaceCardRatingPresentation(
                score: recmeRating.score,
                count: recmeRating.count,
                source: .recme
            )
        }

        // A malformed negative rec.me count is not the same as zero evidence.
        // Avoid silently replacing invalid first-party data with a provider score.
        guard recmeRating?.count ?? 0 == 0,
              let providerScore,
              (1 ... 5).contains(providerScore)
        else { return nil }

        guard let providerDisplayName = providerDisplayName(providerName) else {
            return nil
        }
        return PlaceCardRatingPresentation(
            score: providerScore,
            count: providerCount.flatMap { $0 >= 0 ? $0 : nil },
            source: .provider(displayName: providerDisplayName)
        )
    }

    private static func providerDisplayName(_ value: String?) -> String? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yelp":
            "Yelp"
        case "google", "google_maps", "google_places":
            nil
        case "apple", "apple_maps", "mapkit":
            "Apple Maps"
        default:
            "External"
        }
    }

    static func distanceText(
        viewerLocation: CLLocation?,
        latitude: Double?,
        longitude: Double?
    ) -> String? {
        guard let viewerLocation, let latitude, let longitude else { return nil }
        let destination = CLLocation(latitude: latitude, longitude: longitude)
        let miles = viewerLocation.distance(from: destination) / 1_609.344
        guard miles.isFinite else { return nil }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }

    static func hours(
        isOpen: Bool?,
        nextOpenTimeString: String?,
        nextCloseTimeString: String?,
        utcOffsetMinutes: Int?,
        now: Date = .now
    ) -> PlaceCardHoursPresentation? {
        guard let isOpen else { return nil }
        let nextTime = isOpen ? nextCloseTimeString : nextOpenTimeString
        let detailPrefix = isOpen ? "Closes" : "Opens"
        let detail = parsedGoogleDate(nextTime).map {
            "\(detailPrefix) \(relativeTimeText($0, utcOffsetMinutes: utcOffsetMinutes, now: now))"
        }
        return PlaceCardHoursPresentation(
            isOpen: isOpen,
            statusText: isOpen ? "Open" : "Closed",
            detailText: detail
        )
    }

    private static func parsedGoogleDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func relativeTimeText(
        _ date: Date,
        utcOffsetMinutes: Int?,
        now: Date
    ) -> String {
        let timeZone = utcOffsetMinutes
            .flatMap { TimeZone(secondsFromGMT: $0 * 60) }
            ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "h:mm a"
        let time = timeFormatter.string(from: date).replacingOccurrences(of: ":00", with: "")

        if calendar.isDate(date, inSameDayAs: now) {
            return "at \(time)"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "EEE"
        return "\(dayFormatter.string(from: date)) at \(time)"
    }
}

enum PlaceProfileVerticalMotionStyle {
    static let duration: TimeInterval = 0.52
    static let presentationAnimation = Animation.timingCurve(
        0.22,
        1,
        0.36,
        1,
        duration: duration
    )
    static let dismissalAnimation = Animation.timingCurve(
        0.4,
        0,
        0.6,
        1,
        duration: duration
    )
    static let reducedMotionAnimation = Animation.easeOut(duration: 0.12)
}

struct PlaceCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .saturation(configuration.isPressed ? 0.82 : 1)
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.34), .clear, .black.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(configuration.isPressed ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : configuration.isPressed
                        ? .easeOut(duration: 0.16)
                        : .spring(response: 0.46, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}
