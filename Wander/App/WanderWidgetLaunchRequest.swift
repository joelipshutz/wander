import Foundation

struct WanderDeepLinkLaunchRequest: Equatable, Identifiable {
    let id: UUID
    let route: WanderDeepLinkRoute

    init(id: UUID = UUID(), route: WanderDeepLinkRoute) {
        self.id = id
        self.route = route
    }

    init?(id: UUID = UUID(), url: URL) {
        guard let route = WanderDeepLinkRoute.parse(url) else {
            return nil
        }

        self.init(id: id, route: route)
    }
}

struct WanderDeepLinkInbox: Equatable {
    private(set) var pendingRequest: WanderDeepLinkLaunchRequest?

    mutating func receive(_ url: URL) {
        guard let request = WanderDeepLinkLaunchRequest(url: url) else {
            return
        }

        pendingRequest = request
    }

    func request(ifSessionValidated isSessionValidated: Bool)
        -> WanderDeepLinkLaunchRequest?
    {
        isSessionValidated ? pendingRequest : nil
    }

    mutating func consume(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else {
            return
        }

        pendingRequest = nil
    }
}

struct WanderPresentationResetRequest: Equatable, Identifiable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct WanderAddLaunchRequest: Equatable, Identifiable {
    enum Destination: Equatable {
        case hereNow
        case importHub
        case search(query: String)
        case importInbox
        case importReview(batchIDs: [String])
        case nearbyPlace(PlaceCandidate)
    }

    let id: UUID
    let destination: Destination

    init(id: UUID = UUID(), destination: Destination) {
        self.id = id
        self.destination = destination
    }
}

struct WanderMapSearchLaunchRequest: Equatable, Identifiable {
    let id: UUID
    let query: String?

    init(id: UUID = UUID(), query: String?) {
        self.id = id
        self.query = query?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct WanderProfileCalendarLaunchRequest: Equatable, Identifiable {
    enum Destination: Equatable {
        case calendar
        case day
    }

    let id: UUID
    let targetDate: Date
    let destination: Destination

    init(
        id: UUID = UUID(),
        targetDate: Date = .now,
        destination: Destination = .calendar
    ) {
        self.id = id
        self.targetDate = targetDate
        self.destination = destination
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
