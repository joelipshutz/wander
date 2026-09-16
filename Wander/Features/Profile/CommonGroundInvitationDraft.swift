#if DEBUG
import Foundation

/// One value travels from Ryan's composer to Joe's recipient preview. Evidence
/// uses names so its meaning does not change when the reader changes.
struct CommonGroundInvitationDraft: Hashable, Sendable {
    let place: CommonGroundMockPlace
    var note: String = ""
    var suggestedDate: Date? = nil

    var message: String {
        let personalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard personalNote.isEmpty else { return personalNote }
        switch reason {
        case .sharedRegulars:
            let suggestion = place.category == "Coffee" ? "Coffee together?" : "Go together?"
            return "We’re both \(place.name) people. \(suggestion)"
        case .sharedLove:
            return "We both loved \(place.name). Round two?"
        case .mutualWanna:
            return place.totalVisits > 0
                ? "We both wanna go to \(place.name). Let’s make a plan?"
                : "We’ve both had \(place.name) saved. Let’s finally go?"
        case .joesRegular:
            return place.youVisits > 0
                ? "We both know \(place.name). Let’s go back together?"
                : "You keep going back to \(place.name). Take me next time?"
        case .ryansRegular:
            return place.joeVisits > 0
                ? "We both know \(place.name). Let’s go back together?"
                : "I keep going back to \(place.name). Let me show you why."
        case .history:
            return "Want to go to \(place.name)?"
        }
    }

    var reasonTitle: String {
        switch reason {
        case .sharedRegulars: "Shared regulars"
        case .sharedLove: "Shared love"
        case .mutualWanna: "Both wanna go"
        case .joesRegular: "Joe’s regular spot"
        case .ryansRegular: "Ryan’s regular spot"
        case .history: "Shared place"
        }
    }

    var reasonDetail: String {
        switch reason {
        case .sharedRegulars, .history:
            "\(visitEvidence(name: "Ryan", count: place.youVisits)) · \(visitEvidence(name: "Joe", count: place.joeVisits))"
        case .sharedLove:
            "\(ratingEvidence(name: "Ryan", rating: place.youRating)) · \(ratingEvidence(name: "Joe", rating: place.joeRating))"
        case .mutualWanna:
            "In both of your Wannas"
        case .joesRegular:
            "\(visitEvidence(name: "Joe", count: place.joeVisits)) · In Ryan’s Wannas."
        case .ryansRegular:
            "\(visitEvidence(name: "Ryan", count: place.youVisits)) · In Joe’s Wannas."
        }
    }

    var reasonSymbol: String {
        switch reason {
        case .sharedRegulars: "flame.fill"
        case .sharedLove: "heart.fill"
        case .mutualWanna: "sparkles"
        case .joesRegular: "arrow.up.right"
        case .ryansRegular: "arrow.up.left"
        case .history: "mappin.and.ellipse"
        }
    }

    var whenText: String? {
        suggestedDate?.formatted(date: .abbreviated, time: .shortened)
    }

    /// Text for a local sharing preview; no invented delivery state or URL.
    var shareText: String {
        var paragraphs = [
            message,
            "\(place.name) · \(place.area), \(place.city)",
            "\(reasonTitle): \(reasonDetail)"
        ]
        if let whenText {
            paragraphs.append("When: \(whenText)")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    static let preview = Self(
        place: CommonGroundMockData.places.first { $0.id == "narwhal" }!,
        // Saturday, September 19, 2026, 10:00 a.m. in Los Angeles.
        suggestedDate: Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 9, day: 19, hour: 17, minute: 0
        ))!
    )

    private enum Reason {
        case sharedRegulars, sharedLove, mutualWanna, joesRegular, ryansRegular, history
    }

    private var reason: Reason {
        guard place.kind != .history else { return .history }
        if place.bothLoved && place.bothRegulars { return .sharedRegulars }
        if place.bothLoved { return .sharedLove }
        if place.youWanna && place.joeWanna { return .mutualWanna }
        if place.youWanna && place.joeVisits >= 3 && (place.joeRating ?? 0) >= 4.5 {
            return .joesRegular
        }
        if place.joeWanna && place.youVisits >= 3 && (place.youRating ?? 0) >= 4.5 {
            return .ryansRegular
        }
        return .history
    }

    private func visitEvidence(name: String, count: Int) -> String {
        "\(name): \(count) \(count == 1 ? "check-in" : "check-ins")"
    }

    private func ratingEvidence(name: String, rating: Double?) -> String {
        guard let rating else { return "\(name): not rated" }
        return "\(name): \(PlaceRating.averageDisplay(rating))/5"
    }
}
#endif
