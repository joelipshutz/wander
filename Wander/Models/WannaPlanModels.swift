import Foundation

enum WannaEventState: String, Codable, CaseIterable, Equatable, Sendable {
    case active
    case fulfilled
    case removed
}
enum WannaEventSource: String, Codable, CaseIterable, Equatable, Sendable {
    case direct
    case planAcceptance = "plan_acceptance"
    case imported
    case restored
}

/// A projection of the user's current relationship with a place.
///
/// Visit history and active return intent are independent facts. Do not reduce
/// this model to one mutually exclusive `PlaceStatus`.
struct PlaceRelationshipSnapshot: Equatable, Sendable {
    let visitCount: Int
    let activeWannaCount: Int

    init(visitCount: Int, activeWannaCount: Int) {
        self.visitCount = max(0, visitCount)
        self.activeWannaCount = max(0, activeWannaCount)
    }

    var hasVisited: Bool {
        visitCount > 0
    }

    var hasActiveWanna: Bool {
        activeWannaCount > 0
    }

    func matches(_ status: PlaceStatus) -> Bool {
        switch status {
        case .been:
            hasVisited
        case .wannaGo:
            hasActiveWanna
        }
    }
}

enum WannaCheckInResolution: Equatable, Sendable {
    /// The first check-in fulfills active Wanna events without interrupting save.
    case fulfillAfterFirstVisit
    /// A repeat check-in saves first, then asks whether active Wanna should remain.
    case askAfterRepeatVisit(defaultChoice: WannaCheckInChoice)
    /// There is no active Wanna to resolve.
    case none

    static func afterSavingCheckIn(
        previousRelationship: PlaceRelationshipSnapshot
    ) -> WannaCheckInResolution {
        guard previousRelationship.hasActiveWanna else {
            return .none
        }

        if previousRelationship.hasVisited {
            return .askAfterRepeatVisit(defaultChoice: .keep)
        }

        return .fulfillAfterFirstVisit
    }
}

enum WannaCheckInChoice: String, CaseIterable, Equatable, Sendable {
    case keep
    case remove
}

enum WannaPlanSharing: String, Codable, CaseIterable, Equatable, Sendable {
    case feed
    case privateOnly = "private"

    var title: String {
        switch self {
        case .feed:
            "Share on Feed"
        case .privateOnly:
            "Private"
        }
    }
}

enum WannaPlanParticipantRole: String, Codable, CaseIterable, Equatable, Sendable {
    case creator
    case invitee
}

enum WannaPlanParticipantState: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case accepted
    case declined
    case left
    case cancelled
}

struct WannaPlanParticipantProjection: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let role: WannaPlanParticipantRole
    let state: WannaPlanParticipantState
    let isStealth: Bool

    init(
        id: String,
        displayName: String,
        role: WannaPlanParticipantRole,
        state: WannaPlanParticipantState,
        isStealth: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.state = state
        self.isStealth = isStealth
    }
}

enum WannaPlanVisibilityProjection {
    static func effectiveSharing(
        requested: WannaPlanSharing,
        creatorIsStealth: Bool,
        saveVisibility: PlaceVisibility
    ) -> WannaPlanSharing {
        guard !creatorIsStealth, saveVisibility != .selfOnly else {
            return .privateOnly
        }
        return requested
    }

    static func feedParticipants(
        from participants: [WannaPlanParticipantProjection]
    ) -> [WannaPlanParticipantProjection] {
        participants.filter {
            $0.role == .invitee &&
            $0.state == .accepted &&
            !$0.isStealth
        }
    }

    static func directParticipants(
        from participants: [WannaPlanParticipantProjection]
    ) -> [WannaPlanParticipantProjection] {
        participants.filter {
            $0.state == .pending || $0.state == .accepted
        }
    }

    static func feedCompanionCopy(
        from participants: [WannaPlanParticipantProjection],
        maximumNamedParticipants: Int = 2
    ) -> String? {
        let names = feedParticipants(from: participants)
            .map(\.displayName)
            .prefix(max(0, maximumNamedParticipants))

        guard !names.isEmpty else { return nil }
        return names.joined(separator: " and ")
    }
}
