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
    let youVisits: Int
    let joeVisits: Int
    let youWanna: Bool
    let joeWanna: Bool
    let reason: String
    let kind: CommonGroundMockKind

    var totalVisits: Int { youVisits + joeVisits }

    var bothLoved: Bool {
        guard let youRating, let joeRating else { return false }
        return youRating >= 4.5 && joeRating >= 4.5
    }

    var bothRegulars: Bool { youVisits >= 3 && joeVisits >= 3 }

    var narrativeTitle: String {
        switch narrative {
        case .sharedRegulars: "You both love \(name)."
        case .sharedRatings: "\(name) won you both over."
        case .mutualWanna: "You both want to try \(name)."
        case .joeIntroduces: "Joe loves \(name). You’re next?"
        case .youIntroduce: "You could show Joe \(name)."
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
            reason: "18 check-ins for you. 17 for Joe.",
            kind: .returnTogether
        ),
        CommonGroundMockPlace(
            id: "grove-gardens", name: "Grove Gardens", category: "Garden", area: "Los Feliz", city: "Los Angeles",
            systemImage: "leaf",
            youRating: 5, joeRating: 4.5, youVisits: 1, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "You: 5/5. Joe: 4.5/5. One check-in each.",
            kind: .returnTogether
        ),
        CommonGroundMockPlace(
            id: "not-no-bar", name: "Not No Bar", category: "Bar", area: "Echo Park", city: "Los Angeles",
            systemImage: "wineglass",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "On both Wanna Go maps.",
            kind: .mutualWanna
        ),
        CommonGroundMockPlace(
            id: "mudwater", name: "Mudwater", category: "Coffee", area: "Los Feliz", city: "Los Angeles",
            systemImage: "cup.and.saucer",
            youRating: nil, joeRating: 4.5, youVisits: 0, joeVisits: 5,
            youWanna: true, joeWanna: false,
            reason: "Joe: 5 check-ins. On your Wanna Go map.",
            kind: .introduce
        ),
        CommonGroundMockPlace(
            id: "the-little-room", name: "The Little Room", category: "Restaurant", area: "Atwater Village", city: "Los Angeles",
            systemImage: "fork.knife",
            youRating: 5, joeRating: nil, youVisits: 7, joeVisits: 0,
            youWanna: false, joeWanna: true,
            reason: "You: 7 check-ins. On Joe’s Wanna Go map.",
            kind: .introduce
        ),
        CommonGroundMockPlace(
            id: "canal-coffee", name: "Canal Coffee", category: "Coffee", area: "Hackney", city: "London",
            systemImage: "cup.and.saucer",
            youRating: nil, joeRating: 4.5, youVisits: 0, joeVisits: 4,
            youWanna: true, joeWanna: false,
            reason: "Joe: 4 check-ins. On your Wanna Go map.",
            kind: .introduce
        ),
        CommonGroundMockPlace(
            id: "sundial-books", name: "Sundial Books", category: "Bookshop", area: "Islington", city: "London",
            systemImage: "books.vertical",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "On both Wanna Go maps.",
            kind: .mutualWanna
        ),
        CommonGroundMockPlace(
            id: "paper-lantern", name: "Paper Lantern", category: "Bookshop", area: "Nakagyo", city: "Kyoto",
            systemImage: "books.vertical",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "On both Wanna Go maps.",
            kind: .mutualWanna
        ),
        CommonGroundMockPlace(
            id: "lantern-kitchen", name: "Lantern Kitchen", category: "Restaurant", area: "Echo Park", city: "Los Angeles",
            systemImage: "fork.knife",
            youRating: 4.5, joeRating: 3, youVisits: 2, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "Your saved ratings differ.",
            kind: .history
        ),
        CommonGroundMockPlace(
            id: "terrace", name: "Terrace", category: "Park", area: "Silver Lake", city: "Los Angeles",
            systemImage: "tree",
            youRating: nil, joeRating: nil, youVisits: 1, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "One check-in each, no ratings yet.",
            kind: .history
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
