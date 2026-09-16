#if DEBUG
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

    var kind: CommonGroundMockKind {
        if bothLoved { return .returnTogether }
        if youWanna && joeWanna { return .mutualWanna }
        if youWanna && joeVisits >= 3 && (joeRating ?? 0) >= 4.5 { return .introduce }
        if joeWanna && youVisits >= 3 && (youRating ?? 0) >= 4.5 { return .introduce }
        return .history
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

    var bothLoved: Bool {
        guard let youRating, let joeRating else { return false }
        return youRating >= 4.5 && joeRating >= 4.5
    }

    var bothRegulars: Bool { youVisits >= 3 && joeVisits >= 3 }

    var narrativeTitle: String {
        switch narrative {
        case .sharedRegulars: "You both love \(name)."
        case .sharedRatings: "\(name) won you both over."
        case .mutualWanna:
            totalVisits > 0 ? "You both want to go to \(name)." : "You both want to try \(name)."
        case .joeIntroduces:
            youVisits > 0 ? "\(partner.shortName) loves \(name). Go back together?" : "\(partner.shortName) loves \(name). You’re next?"
        case .youIntroduce:
            joeVisits > 0 ? "You and \(partner.shortName) could go back to \(name)." : "You could show \(partner.shortName) \(name)."
        case .history: "You’ve both saved \(name)."
        }
    }

    var narrativeSymbol: String {
        switch narrative {
        case .sharedRegulars: "flame.fill"
        case .sharedRatings: "heart.fill"
        case .mutualWanna: "bookmark"
        case .joeIntroduces: "arrow.up.right"
        case .youIntroduce: "arrow.up.left"
        case .history: "mappin.and.ellipse"
        }
    }

    private enum Narrative {
        case sharedRegulars, sharedRatings, mutualWanna, joeIntroduces, youIntroduce, history
    }

    private var narrative: Narrative {
        guard kind != .history else { return .history }
        if bothLoved && bothRegulars { return .sharedRegulars }
        if bothLoved { return .sharedRatings }
        if youWanna && joeWanna { return .mutualWanna }
        if youWanna && joeVisits >= 3 && (joeRating ?? 0) >= 4.5 { return .joeIntroduces }
        if joeWanna && youVisits >= 3 && (youRating ?? 0) >= 4.5 { return .youIntroduce }
        return .history
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
#endif
