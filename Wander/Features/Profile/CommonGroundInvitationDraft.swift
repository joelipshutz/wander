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
        case .sharedRegulars: return "We’re Both Regulars At \(place.name)\nLet’s Go Together?"
        case .sharedLove: return "We Both Loved \(place.name)\nRound Two?"
        case .mutualWanna: return "We Both Wanna Go To \(place.name)\nLet’s Make A Plan?"
        case .partnerBeenViewerWanna: return "You’ve Been To \(place.name) And I Wanna Go\nTake Me Next Time?"
        case .viewerBeenPartnerWanna: return "I’ve Been To \(place.name) And You Wanna Go\nLet’s Make A Plan?"
        case .partnerLoves: return "You Love \(place.name)\nTake Me Next Time?"
        case .viewerLoves: return "I Love \(place.name)\nLet Me Show You Why"
        case .bothBeen: return "We’ve Both Been To \(place.name)\nGo Back Together?"
        default: return "Want To Go To \(place.name)?"
        }
    }

    var reasonTitle: String {
        switch place.linkage {
        case .sharedRegulars: "You’re Both Regulars At \(place.name)"
        case .sharedLove: "You Both Love This Place"
        case .mutualWanna: "Both Wanna Go"
        case .viewerBeenPartnerWanna: "You’ve Been And \(place.partner.shortName) Wants To Go"
        case .partnerBeenViewerWanna: "\(place.partner.shortName)’s Been And You Wanna Go"
        case .partnerLoves: "\(place.partner.shortName) Loves This Place"
        case .viewerLoves: "You Love This Place, Show \(place.partner.shortName)"
        case .bothBeen: "You’ve Both Been Here"
        case .viewerBeen: "You’ve Been Here"
        case .partnerBeen: "\(place.partner.shortName)’s Been Here"
        case .viewerWanna: "You Wanna Go"
        case .partnerWanna: "\(place.partner.shortName) Wants To Go"
        case .sharedPlace: "A Place For You Two"
        }
    }

    var recipientReasonTitle: String {
        switch place.linkage {
        case .viewerBeenPartnerWanna: "\(place.viewer.shortName)’s Been And You Wanna Go"
        case .partnerBeenViewerWanna: "You’ve Been And \(place.viewer.shortName) Wants To Go"
        case .partnerLoves: "You Love This Place, Show \(place.viewer.shortName)"
        case .viewerLoves: "\(place.viewer.shortName) Loves This Place"
        case .viewerBeen: "\(place.viewer.shortName)’s Been Here"
        case .partnerBeen: "You’ve Been Here"
        case .viewerWanna: "\(place.viewer.shortName) Wants To Go"
        case .partnerWanna: "You Wanna Go"
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
        "Let’s Go To \(place.name) Together"
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
              let url = WanderDeepLinkRoute.placePlanInvitation(token: invitationToken).url
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
