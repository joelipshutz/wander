import AppIntents
import Foundation

struct WanderControlNavigationRequest: Equatable, Identifiable {
    let id: UUID
    let route: WanderDeepLinkRoute
}

struct WanderControlLaunchRequestStore {
    private struct Payload: Codable {
        let id: UUID
        let destination: WanderControlDestination
    }

    private static let pendingRequestKey = "wander.control.pendingLaunchRequest"
    private let defaults: UserDefaults?

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: WanderWidgetConstants.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
    }

    @discardableResult
    func request(
        _ destination: WanderControlDestination,
        id: UUID = UUID()
    ) -> WanderControlNavigationRequest? {
        let payload = Payload(id: id, destination: destination)
        guard let defaults,
              let data = try? JSONEncoder().encode(payload)
        else { return nil }
        defaults.set(data, forKey: Self.pendingRequestKey)
        return WanderControlNavigationRequest(id: id, route: destination.route)
    }

    func takePendingRequest() -> WanderControlNavigationRequest? {
        guard let defaults,
              let data = defaults.data(forKey: Self.pendingRequestKey)
        else { return nil }

        defaults.removeObject(forKey: Self.pendingRequestKey)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return WanderControlNavigationRequest(
            id: payload.id,
            route: payload.destination.route
        )
    }
}

enum WanderControlDestination: String, AppEnum, Codable {
    case checkInHere

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "rec.me destination"
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .checkInHere: DisplayRepresentation(
            title: "Check-in",
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
    static let title: LocalizedStringResource = "Check-in"
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

    func perform() async throws -> some IntentResult {
        WanderControlLaunchRequestStore().request(target)
        return .result()
    }
}
