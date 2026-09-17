#if DEBUG
import Foundation

/// One value travels from the composer to sharing or the recipient preview. Evidence
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
            return "We’re both \(place.name) people\n\(suggestion)"
        case .sharedLove:
            return "We both loved \(place.name)\nRound two?"
        case .mutualWanna:
            return place.totalVisits > 0
                ? "We both wanna go to \(place.name)\nLet’s make a plan?"
                : "We’ve both had \(place.name) saved\nLet’s finally go?"
        case .joesRegular:
            return place.youVisits > 0
                ? "We both know \(place.name)\nLet’s go back together?"
                : "You keep going back to \(place.name)\nTake me next time?"
        case .ryansRegular:
            return place.joeVisits > 0
                ? "We both know \(place.name)\nLet’s go back together?"
                : "I keep going back to \(place.name)\nLet me show you why"
        case .history:
            return "Want to go to \(place.name)?"
        }
    }

    var reasonTitle: String {
        switch reason {
        case .sharedRegulars: "Shared regulars"
        case .sharedLove: "Shared love"
        case .mutualWanna: "Both Wanna Go"
        case .joesRegular: "\(place.partner.shortName)’s regular spot"
        case .ryansRegular: "\(place.viewer.shortName)’s regular spot"
        case .history: "Shared place"
        }
    }

    var reasonDetail: String {
        switch reason {
        case .sharedRegulars, .history:
            "\(visitEvidence(name: place.viewer.shortName, count: place.youVisits)) · \(visitEvidence(name: place.partner.shortName, count: place.joeVisits))"
        case .sharedLove:
            "\(ratingEvidence(name: place.viewer.shortName, rating: place.youRating)) · \(ratingEvidence(name: place.partner.shortName, rating: place.joeRating))"
        case .mutualWanna:
            "In both of your Wannas"
        case .joesRegular:
            "\(visitEvidence(name: place.partner.shortName, count: place.joeVisits)) · In \(place.viewer.shortName)’s Wannas"
        case .ryansRegular:
            "\(visitEvidence(name: place.viewer.shortName, count: place.youVisits)) · In \(place.partner.shortName)’s Wannas"
        }
    }

    var postcardReasonDetail: String? {
        if case .mutualWanna = reason { return nil }
        return reasonDetail
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

    /// One title/subtitle contract drives the in-app rehearsal and the rich
    /// Messages card. The production invite route can publish these same values
    /// as its Open Graph title and description when that route is introduced.
    var linkTitle: String {
        "Let’s go to \(place.name) together"
    }

    var linkSubtitle: String {
        whenText ?? "Date TBD"
    }

    var linkLocation: String {
        locationText
    }

    var shareContent: WanderShareContent? {
        WanderShareContent.place(
            serverID: place.photoReference?.request.placeID,
            name: linkTitle,
            message: shareText
        )
    }

    /// The proposed message and date travel with the existing place link.
    var shareText: String {
        var paragraphs = [
            message,
            [place.name, locationText].filter { !$0.isEmpty }.joined(separator: " · "),
            "\(reasonTitle): \(reasonDetail)"
        ]
        if let whenText {
            paragraphs.append("When: \(whenText)")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private var locationText: String {
        let parts = place.area.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if place.city.isEmpty || parts.contains(where: { $0.caseInsensitiveCompare(place.city) == .orderedSame }) {
            return place.area
        }
        return [place.area, place.city].filter { !$0.isEmpty }.joined(separator: ", ")
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
