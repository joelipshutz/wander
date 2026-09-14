#if DEBUG
import Foundation

enum CommonGroundMockPage: String, CaseIterable, Sendable {
    case profile
    case ownProfile
    case detail
    case mix
    case invitation
    case recipient
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
}

enum CommonGroundMockOccasion: String, CaseIterable, Sendable {
    case any = "Any time"
    case coffeeWalk = "Coffee & a walk"
    case dateNight = "Date night"
}

/// Fictional, deterministic design fixtures. Visit counts describe each person's
/// separate check-ins; no fixture claims that the people visited together.
enum CommonGroundMockData {
    static let places: [CommonGroundMockPlace] = [
        CommonGroundMockPlace(
            id: "narwhal", name: "Narwhal", category: "Coffee", area: "Silver Lake",
            systemImage: "cup.and.saucer",
            youRating: 5, joeRating: 5, youVisits: 18, joeVisits: 17,
            youWanna: false, joeWanna: false,
            reason: "You’ve checked in 18 times, Joe 17. You both rate it 5/5.",
            kind: .returnTogether
        ),
        CommonGroundMockPlace(
            id: "not-no-bar", name: "Not No Bar", category: "Bar", area: "Echo Park",
            systemImage: "wineglass",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "Already on both of your Wanna Go maps.",
            kind: .mutualWanna
        ),
        CommonGroundMockPlace(
            id: "mudwater", name: "Mudwater", category: "Coffee", area: "Los Feliz",
            systemImage: "cup.and.saucer",
            youRating: nil, joeRating: 4.5, youVisits: 0, joeVisits: 5,
            youWanna: true, joeWanna: false,
            reason: "Joe’s repeat coffee stop, already on your Wanna Go map.",
            kind: .introduce
        ),
        CommonGroundMockPlace(
            id: "the-little-room", name: "The Little Room", category: "Restaurant", area: "Atwater Village",
            systemImage: "fork.knife",
            youRating: 5, joeRating: nil, youVisits: 7, joeVisits: 0,
            youWanna: false, joeWanna: true,
            reason: "You rate it 5/5, and Joe wants to try it.",
            kind: .introduce
        ),
        CommonGroundMockPlace(
            id: "sundial-books", name: "Sundial Books", category: "Bookshop", area: "Highland Park",
            systemImage: "books.vertical",
            youRating: nil, joeRating: nil, youVisits: 0, joeVisits: 0,
            youWanna: true, joeWanna: true,
            reason: "A bookshop you’ve both been meaning to explore.",
            kind: .mutualWanna
        ),
        CommonGroundMockPlace(
            id: "grove-gardens", name: "Grove Gardens", category: "Garden", area: "Los Feliz",
            systemImage: "leaf",
            youRating: 5, joeRating: 4.5, youVisits: 5, joeVisits: 4,
            youWanna: false, joeWanna: false,
            reason: "You’ve returned five times, Joe four. You both rate it highly.",
            kind: .returnTogether
        ),
        CommonGroundMockPlace(
            id: "lantern-kitchen", name: "Lantern Kitchen", category: "Restaurant", area: "Echo Park",
            systemImage: "fork.knife",
            youRating: 4.5, joeRating: 3, youVisits: 2, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "You rated it 4.5/5; Joe rated it 3/5.",
            kind: .history
        ),
        CommonGroundMockPlace(
            id: "terrace", name: "Terrace", category: "Park", area: "Silver Lake",
            systemImage: "tree",
            youRating: nil, joeRating: nil, youVisits: 1, joeVisits: 1,
            youWanna: false, joeWanna: false,
            reason: "You’ve each checked in once; neither has a rating yet.",
            kind: .history
        )
    ]

    static func mix(
        area: String = "Los Angeles",
        occasion: CommonGroundMockOccasion = .any,
        sparse: Bool = false
    ) -> [CommonGroundMockPlace] {
        guard area.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Los Angeles") == .orderedSame else { return [] }

        let eligiblePlaces = places.filter { $0.kind != .history }
        // Sparse is a smaller underlying pool, not a limit applied after filters.
        let availablePlaces = sparse ? Array(eligiblePlaces.prefix(2)) : eligiblePlaces
        return availablePlaces.filter { place in
            switch occasion {
            case .any:
                true
            case .coffeeWalk:
                ["Coffee", "Bookshop", "Garden", "Park"].contains(place.category)
            case .dateNight:
                ["Bar", "Restaurant"].contains(place.category)
            }
        }
    }
}
#endif
