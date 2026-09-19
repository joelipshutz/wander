import Foundation

enum CommonGroundMockPage: String, CaseIterable, Sendable {
    case profile
    case ownProfile
    case detail
    case mix
    case invitation
    case recipient
    case messages
    case recipientOpened
    case sparse
    case loading
    case unavailable

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CommonGroundMockPage? {
        if let value = environment["WANDER_COMMON_GROUND_MOCKUP"] {
            return CommonGroundMockPage(rawValue: value) ?? .detail
        }
        guard let flagIndex = arguments.firstIndex(of: "-WanderCommonGroundMockup") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .detail }
        return CommonGroundMockPage(rawValue: arguments[valueIndex]) ?? .detail
    }
}

enum CommonGroundMockKind: Hashable, Sendable {
    case returnTogether
    case mutualWanna
    case introduce
    case history
}

struct CommonGroundMockPlace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: String
    let area: String
    let city: String
    let systemImage: String
    let youRating: Double?
    let joeRating: Double?
    let youEvidence: CommonGroundPersonEvidence
    let joeEvidence: CommonGroundPersonEvidence
    let reason: String
    let viewer: CommonGroundPerson
    let partner: CommonGroundPerson
    let photoReference: CommonGroundPlacePhotoReference?
    let sourcePlaceID: String?

    enum Linkage: String, Hashable, Sendable {
        case sharedRegulars, sharedLove, mutualWanna
        case viewerBeenPartnerWanna, partnerBeenViewerWanna
        case partnerLoves, viewerLoves, bothBeen
        case viewerBeen, partnerBeen, viewerWanna, partnerWanna, sharedPlace
    }

    /// One evidence decision drives every surface. A Wanna never counts as a
    /// visit, and a check-in never erases a separate repeat Wanna.
    var linkage: Linkage {
        if bothLoved && bothRegulars { return .sharedRegulars }
        if bothLoved { return .sharedLove }
        if youWanna && joeWanna { return .mutualWanna }
        if youVisits > 0 && joeWanna { return .viewerBeenPartnerWanna }
        if joeVisits > 0 && youWanna { return .partnerBeenViewerWanna }
        if partnerLoves { return .partnerLoves }
        if viewerLoves { return .viewerLoves }
        if youVisits > 0 && joeVisits > 0 { return .bothBeen }
        if youVisits > 0 { return .viewerBeen }
        if joeVisits > 0 { return .partnerBeen }
        if youWanna { return .viewerWanna }
        if joeWanna { return .partnerWanna }
        return .sharedPlace
    }

    var kind: CommonGroundMockKind {
        switch linkage {
        case .sharedRegulars, .sharedLove: .returnTogether
        case .mutualWanna: .mutualWanna
        case .viewerBeenPartnerWanna, .partnerBeenViewerWanna, .partnerLoves, .viewerLoves: .introduce
        default: .history
        }
    }

    var youVisits: Int { youEvidence.visitCount }
    var joeVisits: Int { joeEvidence.visitCount }
    var youWanna: Bool { youEvidence.hasWanna }
    var joeWanna: Bool { joeEvidence.hasWanna }
    var totalVisits: Int { youVisits + joeVisits }

    init(
        id: String, name: String, category: String, area: String, city: String,
        systemImage: String, youRating: Double?, joeRating: Double?,
        youVisits: Int, joeVisits: Int, youWanna: Bool, joeWanna: Bool,
        youWannaEventIDs: [String] = [], joeWannaEventIDs: [String] = [],
        reason: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.area = area
        self.city = city
        self.systemImage = systemImage
        self.youRating = youRating
        self.joeRating = joeRating
        self.reason = reason
        viewer = .previewViewer
        partner = .previewPartner
        photoReference = nil
        sourcePlaceID = nil
        // Fixtures mirror separate check-in and Wanna events. In the live
        // adapter, pass all visible events after canonical place resolution,
        // including Wanna events attached to a Been summary (REC-497).
        func evidence(owner: String, visits: Int, legacyWanna: Bool, wannaIDs: [String]) -> CommonGroundPersonEvidence {
            var records = (0..<max(0, visits)).map {
                CommonGroundEvidenceRecord(id: "\(id)-\(owner)-visit-\($0)", ownerID: owner,
                                           canonicalPlaceID: id, kind: .checkIn)
            }
            records += wannaIDs.map {
                CommonGroundEvidenceRecord(id: $0, ownerID: owner, canonicalPlaceID: id, kind: .wanna)
            }
            if legacyWanna {
                records.append(CommonGroundEvidenceRecord(id: "\(id)-\(owner)-legacy-wanna", ownerID: owner,
                                                          canonicalPlaceID: id, kind: .legacyWanna))
            }
            return .aggregate(personID: owner, canonicalPlaceID: id, records: records)
        }
        youEvidence = evidence(owner: "ryan", visits: youVisits, legacyWanna: youWanna, wannaIDs: youWannaEventIDs)
        joeEvidence = evidence(owner: "joe", visits: joeVisits, legacyWanna: joeWanna, wannaIDs: joeWannaEventIDs)
    }

    init(
        id: String, name: String, category: String, area: String, city: String,
        systemImage: String, youRating: Double?, joeRating: Double?,
        youEvidence: CommonGroundPersonEvidence, joeEvidence: CommonGroundPersonEvidence,
        reason: String, viewer: CommonGroundPerson, partner: CommonGroundPerson,
        photoReference: CommonGroundPlacePhotoReference?, sourcePlaceID: String?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.area = area
        self.city = city
        self.systemImage = systemImage
        self.youRating = youRating
        self.joeRating = joeRating
        self.youEvidence = youEvidence
        self.joeEvidence = joeEvidence
        self.reason = reason
        self.viewer = viewer
        self.partner = partner
        self.photoReference = photoReference
        self.sourcePlaceID = sourcePlaceID
    }

    var previewPhotoTile: Int? {
        guard sourcePlaceID == nil else { return nil }
        return switch category {
        case "Bar": 3
        case "Restaurant": 2
        case "Coffee": id == "mudwater" || id == "canal-coffee" ? 1 : 0
        default: nil
        }
    }

    var viewerLoves: Bool { youVisits > 0 && (youRating ?? 0) >= 4.5 }
    var partnerLoves: Bool { joeVisits > 0 && (joeRating ?? 0) >= 4.5 }
    var bothLoved: Bool { viewerLoves && partnerLoves }
    var bothRegulars: Bool { youVisits >= 3 && joeVisits >= 3 }

    var narrativeTitle: String {
        switch linkage {
        case .sharedRegulars: "You’re both regulars at \(name)"
        case .sharedLove: "\(name) won you both over"
        case .mutualWanna: "You both want to go to \(name)"
        case .viewerBeenPartnerWanna: "You’ve been to \(name)\n\(partner.shortName) wants to go"
        case .partnerBeenViewerWanna: "\(partner.shortName)’s been to \(name)\nYou wanna go"
        case .partnerLoves: "\(partner.shortName) loves \(name)"
        case .viewerLoves: "You love \(name)\nShow \(partner.shortName)"
        case .bothBeen: "You’ve both been to \(name)"
        case .viewerBeen: "You’ve been to \(name)\nBring \(partner.shortName) along"
        case .partnerBeen: "\(partner.shortName)’s been to \(name)\nGo together?"
        case .viewerWanna: "You want to go to \(name)\nBring \(partner.shortName) along"
        case .partnerWanna: "\(partner.shortName) wants to go to \(name)"
        case .sharedPlace: "Make a plan at \(name)"
        }
    }

    var narrativeDetail: String {
        switch linkage {
        case .sharedRegulars, .bothBeen:
            "You: \(visitsText(youVisits)) · \(partner.shortName): \(visitsText(joeVisits))"
        case .sharedLove:
            "You: \(PlaceRating.averageDisplay(youRating!))/5 · \(partner.shortName): \(PlaceRating.averageDisplay(joeRating!))/5"
        case .mutualWanna: "In both of your Wannas"
        case .viewerBeenPartnerWanna:
            "You: \(visitsText(youVisits)) · In \(partner.shortName)’s Wannas"
        case .partnerBeenViewerWanna:
            "\(partner.shortName): \(visitsText(joeVisits)) · In your Wannas"
        case .partnerLoves: "\(partner.shortName) rated it \(PlaceRating.averageDisplay(joeRating!))/5"
        case .viewerLoves: "You rated it \(PlaceRating.averageDisplay(youRating!))/5"
        case .viewerBeen: "You: \(visitsText(youVisits))"
        case .partnerBeen: "\(partner.shortName): \(visitsText(joeVisits))"
        case .viewerWanna: "In your Wannas"
        case .partnerWanna: "In \(partner.shortName)’s Wannas"
        case .sharedPlace: "A place on both your maps"
        }
    }

    var narrativeSymbol: String {
        switch linkage {
        case .sharedRegulars: "arrow.counterclockwise"
        case .sharedLove, .partnerLoves, .viewerLoves: "heart.fill"
        case .mutualWanna, .viewerWanna, .partnerWanna: "bookmark"
        case .partnerBeenViewerWanna: "arrow.up.right"
        case .viewerBeenPartnerWanna: "arrow.up.left"
        default: "mappin.and.ellipse"
        }
    }

    private func visitsText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "check-in" : "check-ins")"
    }

}

/// Fictional, deterministic design fixtures. Visit counts describe each person's
/// separate check-ins; no fixture claims that the people visited together.
enum CommonGroundMockData {
    static let places: [CommonGroundMockPlace] = [
        CommonGroundMockPlace(
            id: "narwhal", name: "Narwhal", category: "Coffee", area: "Silver Lake", city: "Los Angeles",
            systemImage: "cup.and.saucer",
            youRating: 5, joeRating: 5, youVisits: 18, joeVisits: 17,
            youWanna: false, joeWanna: false,
            reason: "18 check-ins for you. 17 for Joe."
        ),
        CommonGroundMockPlace(
            id: "grove-gardens", name: "Grove Gardens", category: "Garden", area: "Los Feliz", city: "Los Angeles",
            systemImage: "leaf",
            youRating: 5, joeRating: 4.5, youVisits: 1, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "You: 5/5. Joe: 4.5/5. One check-in each."
        ),
        CommonGroundMockPlace(
            id: "not-no-bar", name: "Not No Bar", category: "Bar", area: "Echo Park", city: "Los Angeles",
            systemImage: "wineglass",
            youRating: 4, joeRating: nil, youVisits: 1, joeVisits: 0,
            youWanna: false, joeWanna: true,
            youWannaEventIDs: ["not-no-bar-ryan-wanna-1", "not-no-bar-ryan-wanna-2"],
            reason: "In both of your Wannas"
        ),
        CommonGroundMockPlace(
            id: "mudwater", name: "Mudwater", category: "Coffee", area: "Los Feliz", city: "Los Angeles",
            systemImage: "cup.and.saucer",
            youRating: nil, joeRating: 4.5, youVisits: 0, joeVisits: 5,
            youWanna: true, joeWanna: false,
            reason: "Joe: 5 check-ins. In your Wannas."
        ),
        CommonGroundMockPlace(
            id: "the-little-room", name: "The Little Room", category: "Restaurant", area: "Atwater Village", city: "Los Angeles",
            systemImage: "fork.knife",
            youRating: 5, joeRating: nil, youVisits: 7, joeVisits: 0,
            youWanna: false, joeWanna: true,
            reason: "You: 7 check-ins. In Joe’s Wannas."
        ),
        CommonGroundMockPlace(
            id: "canal-coffee", name: "Canal Coffee", category: "Coffee", area: "Hackney", city: "London",
            systemImage: "cup.and.saucer",
            youRating: nil, joeRating: 4.5, youVisits: 0, joeVisits: 4,
            youWanna: true, joeWanna: false,
            reason: "Joe: 4 check-ins. In your Wannas."
        ),
        CommonGroundMockPlace(
            id: "sundial-books", name: "Sundial Books", category: "Bookshop", area: "Islington", city: "London",
            systemImage: "books.vertical",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "In both of your Wannas"
        ),
        CommonGroundMockPlace(
            id: "paper-lantern", name: "Paper Lantern", category: "Bookshop", area: "Nakagyo", city: "Kyoto",
            systemImage: "books.vertical",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "In both of your Wannas"
        ),
        CommonGroundMockPlace(
            id: "lantern-kitchen", name: "Lantern Kitchen", category: "Restaurant", area: "Echo Park", city: "Los Angeles",
            systemImage: "fork.knife",
            youRating: 4.5, joeRating: 3, youVisits: 2, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "Your saved ratings differ."
        ),
        CommonGroundMockPlace(
            id: "terrace", name: "Terrace", category: "Park", area: "Silver Lake", city: "Los Angeles",
            systemImage: "tree",
            youRating: nil, joeRating: nil, youVisits: 1, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "One check-in each, no ratings yet."
        )
    ]

    /// A city is available when either person has a check-in there. A shared
    /// Wanna alone does not add a city, and the two people need not have visited it together.
    static let availableCities: [String] = {
        var seen = Set<String>()
        return places.compactMap { place in
            guard place.youVisits > 0 || place.joeVisits > 0 else { return nil }
            let city = place.city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !city.isEmpty, seen.insert(city.lowercased()).inserted else { return nil }
            return city
        }
    }()

    static func mix(
        area: String = "Los Angeles",
        sparse: Bool = false
    ) -> [CommonGroundMockPlace] {
        let normalizedArea = area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard availableCities.contains(where: {
            $0.caseInsensitiveCompare(normalizedArea) == .orderedSame
        }) else { return [] }

        let eligiblePlaces = places.filter {
            $0.kind != .history && $0.city.caseInsensitiveCompare(normalizedArea) == .orderedSame
        }
        return sparse ? Array(eligiblePlaces.prefix(2)) : eligiblePlaces
    }
}
