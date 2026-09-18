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
        switch place.linkage {
        case .sharedRegulars: return "We’re both regulars at \(place.name)\nLet’s go together?"
        case .sharedLove: return "We both loved \(place.name)\nRound two?"
        case .mutualWanna: return "We both wanna go to \(place.name)\nLet’s make a plan?"
        case .partnerBeenViewerWanna: return "You’ve been to \(place.name) and I wanna go\nTake me next time?"
        case .viewerBeenPartnerWanna: return "I’ve been to \(place.name) and you wanna go\nLet’s make a plan?"
        case .partnerLoves: return "You love \(place.name)\nTake me next time?"
        case .viewerLoves: return "I love \(place.name)\nLet me show you why"
        case .bothBeen: return "We’ve both been to \(place.name)\nGo back together?"
        default: return "Want to go to \(place.name)?"
        }
    }

    var reasonTitle: String {
        switch place.linkage {
        case .sharedRegulars: "You’re both regulars at \(place.name)"
        case .sharedLove: "You both love this place"
        case .mutualWanna: "Both Wanna Go"
        case .viewerBeenPartnerWanna: "You’ve been and \(place.partner.shortName) wants to go"
        case .partnerBeenViewerWanna: "\(place.partner.shortName)’s been and you wanna go"
        case .partnerLoves: "\(place.partner.shortName) loves this place"
        case .viewerLoves: "You love this place, show \(place.partner.shortName)"
        case .bothBeen: "You’ve both been here"
        case .viewerBeen: "You’ve been here"
        case .partnerBeen: "\(place.partner.shortName)’s been here"
        case .viewerWanna: "You wanna go"
        case .partnerWanna: "\(place.partner.shortName) wants to go"
        case .sharedPlace: "A place for you two"
        }
    }

    var recipientReasonTitle: String {
        switch place.linkage {
        case .viewerBeenPartnerWanna: "\(place.viewer.shortName)’s been and you wanna go"
        case .partnerBeenViewerWanna: "You’ve been and \(place.viewer.shortName) wants to go"
        case .partnerLoves: "You love this place, show \(place.viewer.shortName)"
        case .viewerLoves: "\(place.viewer.shortName) loves this place"
        case .viewerBeen: "\(place.viewer.shortName)’s been here"
        case .partnerBeen: "You’ve been here"
        case .viewerWanna: "\(place.viewer.shortName) wants to go"
        case .partnerWanna: "You wanna go"
        default: reasonTitle
        }
    }

    var reasonDetail: String { place.narrativeDetail }
    var postcardReasonDetail: String? { nil }
    var reasonSymbol: String { place.narrativeSymbol }

    var whenText: String? {
        suggestedDate?.formatted(date: .abbreviated, time: .shortened)
    }

    /// The composer, shared artwork, and hosted invitation use this title/date.
    var linkTitle: String {
        "Let’s go to \(place.name) together"
    }

    var linkSubtitle: String {
        whenText ?? "Date TBD"
    }

    var linkLocation: String {
        locationText
    }

    var canCreateInvitation: Bool {
        place.photoReference?.placeID.flatMap(UUID.init(uuidString:)) != nil
    }

    func shareContent(invitationToken: String) -> WanderShareContent? {
        guard invitationToken.count == 48,
              invitationToken.allSatisfy({ "0123456789abcdef".contains($0) }),
              let url = URL(string: "https://getrec.me/plans/\(invitationToken)")
        else { return nil }
        return WanderShareContent.place(item: url, name: linkTitle, message: shareText)
    }

    /// Composer copy is separate from the link's title, artwork, and date.
    /// Never paste private visit/rating evidence into the outgoing message.
    var shareText: String { [message, whenText].compactMap { $0 }.joined(separator: "\n\n") }

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

}
#endif
