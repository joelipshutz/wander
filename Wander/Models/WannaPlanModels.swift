import Foundation

enum WannaEventState: String, Codable, CaseIterable, Equatable, Sendable {
    case active
    case fulfilled
    case removed
}

enum WannaEventSource: String, Codable, CaseIterable, Equatable, Sendable {
    case direct
    case planAcceptance = "plan_acceptance"
    case imported = "import"
    case legacy
}

enum WannaPlanSharing: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case feed
    case privateOnly = "private"

    var title: String {
        switch self {
        case .feed: "Share on Feed"
        case .privateOnly: "Private"
        }
    }

    var helperCopy: String {
        switch self {
        case .feed: "People who can see your saves can see this plan."
        case .privateOnly: "Only you and the people invited can see this."
        }
    }
}

enum WannaPlanStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case active
    case cancelled
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
    case removed
}

struct WannaEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let userPlaceID: String
    let placeID: String
    let state: WannaEventState
    let source: WannaEventSource
    let wasVisitedBefore: Bool
    let plannedDate: Date?
    let occurredAt: Date
    let planID: String?
    let planSharing: WannaPlanSharing?
    let planStatus: WannaPlanStatus?

    var isActive: Bool {
        state == .active
    }
}

struct WannaPlanParticipant: Identifiable, Codable, Equatable, Sendable {
    let participantID: String
    let userID: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let role: WannaPlanParticipantRole
    let state: WannaPlanParticipantState

    var id: String { participantID }
}

struct WannaPlanContext: Codable, Equatable, Sendable {
    let wannaEventID: String
    let note: String?
    let wasVisitedBefore: Bool
    let plannedDate: Date?
    let planID: String?
    let sharing: WannaPlanSharing?
    let status: WannaPlanStatus?
    let participants: [WannaPlanParticipant]

    var acceptedInvitees: [WannaPlanParticipant] {
        participants.filter { $0.role == .invitee && $0.state == .accepted }
    }

    var feedTicketEyebrow: String {
        wasVisitedBefore ? "WANTS TO GO BACK" : "WANTS TO GO"
    }

    var feedAttributionAction: String {
        wasVisitedBefore ? "wants to go back" : "wants to go"
    }
}

enum WannaPlanVisibilityPolicy {
    static func effectiveSharing(
        requested: WannaPlanSharing,
        creatorIsPrivate: Bool,
        saveVisibility: PlaceVisibility
    ) -> WannaPlanSharing {
        guard !creatorIsPrivate, saveVisibility != .selfOnly else {
            return .privateOnly
        }
        return requested
    }

    static func feedParticipants(
        from participants: [WannaPlanParticipant]
    ) -> [WannaPlanParticipant] {
        participants.filter { participant in
            participant.role == .invitee && participant.state == .accepted
        }
    }
}

struct WannaPlanInvitation: Identifiable, Codable, Equatable, Sendable {
    let participantID: String
    let planID: String
    let invitationGeneration: Int
    let state: WannaPlanParticipantState
    let invitedAt: Date
    let creatorUserID: String
    let creatorHandle: String
    let creatorDisplayName: String
    let creatorAvatarURL: String?
    let placeID: String
    let placeName: String
    let category: String
    let primaryCategory: String
    let subcategory: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String?
    let plannedDate: Date?
    let sharing: WannaPlanSharing
    let planStatus: WannaPlanStatus
    let participants: [WannaPlanParticipant]

    var id: String { participantID }

    var candidate: PlaceCandidate {
        PlaceCandidate(
            id: placeID,
            name: placeName,
            category: primaryCategory,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: PlaceCategorySource.legacy.rawValue,
            categoryConfidence: nil,
            rawProviderType: category,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            confidence: 1
        )
    }
}

struct WannaPlanDraft: Equatable, Sendable {
    let id: String
    let inviteeUserIDs: [String]
    let sharing: WannaPlanSharing
}

struct WannaSaveDraft: Equatable, Sendable {
    let eventID: String
    let plan: WannaPlanDraft?
}

struct WannaSaveResult: Equatable, Sendable {
    let userPlaceID: String
    let placeID: String
    let wannaEventID: String
    let planID: String?
    let sharing: WannaPlanSharing?
    let invitationCount: Int
}

struct WannaPlanAcceptanceResult: Equatable, Sendable {
    let participantID: String
    let planID: String
    let participantState: WannaPlanParticipantState
    let wannaEventID: String
    let userPlaceID: String
    let placeID: String
}

struct WannaPlanAcceptanceIdentifiers: Equatable, Sendable {
    let operationID: String
    let wannaEventID: String

    static func deterministic(
        participantID: String,
        invitationGeneration: Int
    ) -> WannaPlanAcceptanceIdentifiers {
        let prefix = "wanna-plan:\(participantID):\(invitationGeneration)"
        return WannaPlanAcceptanceIdentifiers(
            operationID: stableUUID(for: "\(prefix):operation"),
            wannaEventID: stableUUID(for: "\(prefix):event")
        )
    }

    private static func stableUUID(for value: String) -> String {
        let bytes = Array(value.utf8)
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 1_099_511_628_211
        for byte in bytes { first = (first ^ UInt64(byte)) &* 1_099_511_628_211 }
        for byte in bytes.reversed() { second = (second ^ UInt64(byte)) &* 1_099_511_628_211 }
        var uuidBytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        uuidBytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian, Array.init))
        uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80
        let hex = uuidBytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }
}

struct PlaceRelationshipSnapshot: Equatable, Sendable {
    let visitCount: Int
    let activeWannaCount: Int

    init(visitCount: Int, activeWannaCount: Int) {
        self.visitCount = max(0, visitCount)
        self.activeWannaCount = max(0, activeWannaCount)
    }

    var hasVisited: Bool { visitCount > 0 }
    var hasActiveWanna: Bool { activeWannaCount > 0 }

    func matches(_ status: PlaceStatus) -> Bool {
        switch status {
        case .been: hasVisited
        case .wannaGo: hasActiveWanna
        }
    }
}

enum WannaCheckInChoice: String, Equatable, Sendable {
    case keep
    case remove
}

enum WannaCheckInResolution: Equatable, Sendable {
    case fulfillAfterFirstVisit
    case askAfterRepeatVisit(defaultChoice: WannaCheckInChoice)
    case none

    static func afterSavingCheckIn(
        previousRelationship: PlaceRelationshipSnapshot
    ) -> WannaCheckInResolution {
        guard previousRelationship.hasActiveWanna else { return .none }
        return previousRelationship.hasVisited
            ? .askAfterRepeatVisit(defaultChoice: .keep)
            : .fulfillAfterFirstVisit
    }
}
