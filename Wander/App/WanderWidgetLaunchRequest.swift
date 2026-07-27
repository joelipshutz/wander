import Foundation

struct WanderPresentationResetRequest: Equatable, Identifiable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct WanderAddLaunchRequest: Equatable, Identifiable {
    enum Destination: Equatable {
        case hereNow
        case importInbox
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
