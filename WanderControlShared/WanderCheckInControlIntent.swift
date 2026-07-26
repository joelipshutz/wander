import AppIntents
import Combine
import Foundation

struct WanderControlNavigationRequest: Equatable, Identifiable {
    let id: UUID
    let route: WanderDeepLinkRoute

    init(id: UUID = UUID(), route: WanderDeepLinkRoute) {
        self.id = id
        self.route = route
    }
}

@MainActor
final class WanderControlNavigationCenter: ObservableObject {
    static let shared = WanderControlNavigationCenter()

    @Published private(set) var pendingRequest: WanderControlNavigationRequest?

    init(pendingRequest: WanderControlNavigationRequest? = nil) {
        self.pendingRequest = pendingRequest
    }

    func request(_ route: WanderDeepLinkRoute) {
        pendingRequest = WanderControlNavigationRequest(route: route)
    }

    func consume(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
    }
}

@available(iOS 18.0, *)
enum WanderControlDestination: String, AppEnum {
    case checkInHere

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "rec.me destination"
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .checkInHere: DisplayRepresentation(
            title: "Check-in here",
            subtitle: "Choose and save the place where you are"
        )
    ]

    var route: WanderDeepLinkRoute {
        switch self {
        case .checkInHere:
            .quickCapture
        }
    }
}

@available(iOS 18.0, *)
struct WanderOpenCheckInControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Check-in here"
    static let description = IntentDescription(
        "Opens rec.me to choose and save the place where you are."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Destination")
    var target: WanderControlDestination

    init() {
        target = .checkInHere
    }

    init(target: WanderControlDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WanderControlNavigationCenter.shared.request(target.route)
        return .result()
    }
}
