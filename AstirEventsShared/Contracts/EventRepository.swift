import Foundation

/// A host increments/replaces sessionEpoch on sign-out, sign-in or account replacement.
/// This is a client stale-response fence, never server authentication evidence.
public struct EventRequestContext: Equatable, Sendable {
    public let eventId: EventID
    public let accountId: EventAccountID?
    public let sessionEpoch: UUID
    public init(eventId: EventID, accountId: EventAccountID?, sessionEpoch: UUID) {
        self.eventId = eventId; self.accountId = accountId; self.sessionEpoch = sessionEpoch
    }
    public func accept(_ response: EventReadResponse, current: Self) throws -> EventReadResponse {
        guard self == current, eventId == response.eventId else { throw EventContractError.staleContext }
        try response.validate()
        if case .available(let view) = response.payload, case .resolved(let viewer) = view.viewer {
            guard accountId == viewer.accountId else { throw EventContractError.staleContext }
        }
        return response
    }
}

public enum EventOperationKindName: String, Codable, Sendable {
    case submitRSVP = "submit_rsvp", joinWaitlist = "join_event_waitlist", acceptOffer = "accept_offer"
    case declineOffer = "decline_offer", cancelRSVP = "cancel_rsvp", completeCheckin = "complete_event_checkin"
    case recordAdmission = "record_admission", deletePost = "delete_event_post"
}

/// Server scope: verified actor + kind + operationId, with a canonical payload fingerprint.
/// Retain this exact value after response loss; deliberate rebooking creates a new generation.
public struct EventCommand<Payload: Codable & Sendable>: Codable, Sendable {
    public let contractVersion: Int
    public let operationId: EventOperationID
    public let kind: EventOperationKindName
    public let eventId: EventID
    public let targetGenerationId: EventGenerationID?
    public let expectedRevision: Int?
    public let payload: Payload
    private enum CodingKeys: String, CodingKey { case contractVersion, operationId, kind, eventId, targetGenerationId, expectedRevision, payload }

    public init(operationId: EventOperationID, kind: EventOperationKindName, eventId: EventID,
                targetGenerationId: EventGenerationID?, expectedRevision: Int?, payload: Payload) throws {
        guard expectedRevision == nil || (1...9_007_199_254_740_991).contains(expectedRevision!) else { throw EventContractError.invalid("revision") }
        contractVersion = 1; self.operationId = operationId; self.kind = kind; self.eventId = eventId
        self.targetGenerationId = targetGenerationId; self.expectedRevision = expectedRevision; self.payload = payload
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .contractVersion) == 1 else { throw EventContractError.unsupportedVersion }
        try self.init(operationId: c.decode(EventOperationID.self, forKey: .operationId),
                      kind: c.decode(EventOperationKindName.self, forKey: .kind), eventId: c.decode(EventID.self, forKey: .eventId),
                      targetGenerationId: c.decode(EventGenerationID?.self, forKey: .targetGenerationId),
                      expectedRevision: c.decode(Int?.self, forKey: .expectedRevision), payload: c.decode(Payload.self, forKey: .payload))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contractVersion, forKey: .contractVersion); try c.encode(operationId, forKey: .operationId)
        try c.encode(kind, forKey: .kind); try c.encode(eventId, forKey: .eventId)
        try c.encode(targetGenerationId, forKey: .targetGenerationId); try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(payload, forKey: .payload)
    }
}

public enum EventCommandOutcome: String, Codable, Sendable { case applied, alreadyApplied = "already_applied", rejected }

/// The historic effect identifies what committed. Current state may already be canceled/deleted.
public struct EventCommandResult<Effect: Codable & Sendable>: Codable, Sendable {
    public let contractVersion: Int
    public let operationId: EventOperationID
    public let kind: EventOperationKindName
    public let outcome: EventCommandOutcome
    public let effect: Effect?
    public let currentState: EventReadResponse
    public let error: EventFailure?
    private enum CodingKeys: String, CodingKey { case contractVersion, operationId, kind, outcome, effect, currentState, error }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try c.decode(Int.self, forKey: .contractVersion)
        operationId = try c.decode(EventOperationID.self, forKey: .operationId)
        kind = try c.decode(EventOperationKindName.self, forKey: .kind)
        outcome = try c.decode(EventCommandOutcome.self, forKey: .outcome)
        effect = try c.decode(Effect?.self, forKey: .effect)
        currentState = try c.decode(EventReadResponse.self, forKey: .currentState)
        error = try c.decode(EventFailure?.self, forKey: .error)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contractVersion, forKey: .contractVersion); try c.encode(operationId, forKey: .operationId)
        try c.encode(kind, forKey: .kind); try c.encode(outcome, forKey: .outcome)
        try c.encode(effect, forKey: .effect); try c.encode(currentState, forKey: .currentState)
        try c.encode(error, forKey: .error)
    }

    public func validate<Payload>(for command: EventCommand<Payload>, captured: EventRequestContext,
                                  current: EventRequestContext) throws {
        guard contractVersion == 1 else { throw EventContractError.unsupportedVersion }
        guard operationId == command.operationId, kind == command.kind, currentState.eventId == command.eventId,
              command.eventId == captured.eventId else { throw EventContractError.invalid("uncorrelated result") }
        _ = try captured.accept(currentState, current: current)
        switch outcome {
        case .applied, .alreadyApplied:
            guard effect != nil, error == nil else { throw EventContractError.invalid("success envelope") }
            guard case .available(let view) = currentState.payload, case .resolved = view.viewer else {
                throw EventContractError.invalid("success without current authorized owner state")
            }
        case .rejected:
            guard effect == nil, error != nil else { throw EventContractError.invalid("rejection envelope") }
        }
    }
}

public enum EventRequestState<Value: Sendable>: Sendable {
    case idle
    case loading(EventRequestContext)
    case resolved(Value)
    case knownRejection(EventFailure)
    /// No state transition may be inferred until the original operation is resolved.
    case completionUnknown(EventOperationID, EventRequestContext)
}

/// Public read remains usable without full-app services. Hosts supply provider/token transport.
/// T02/T03 add real implementations; this package contains no Clerk, UI, map or local-store dependency.
public protocol EventReading: Sendable {
    func readEvent(in context: EventRequestContext) async throws -> EventReadResponse
}

public struct EventPage<Item: Codable & Sendable>: Codable, Sendable {
    public let items: [Item]
    public let nextCursor: String?
    public let hasMore: Bool
    public let permissionVersion: String

    private enum CodingKeys: String, CodingKey { case items, nextCursor, hasMore, permissionVersion }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Item].self, forKey: .items)
        nextCursor = try c.decode(String?.self, forKey: .nextCursor)
        hasMore = try c.decode(Bool.self, forKey: .hasMore)
        permissionVersion = try c.decode(String.self, forKey: .permissionVersion)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items); try c.encode(nextCursor, forKey: .nextCursor)
        try c.encode(hasMore, forKey: .hasMore); try c.encode(permissionVersion, forKey: .permissionVersion)
    }

    public func validate(limit: Int) throws {
        guard (1...100).contains(limit), items.count <= limit,
              hasMore == (nextCursor != nil), nextCursor.map(EventWire.isNonempty) ?? true,
              EventWire.isNonempty(permissionVersion) else {
            throw EventContractError.invalid("page boundary")
        }
    }
}

public enum EventSurface: String, Codable, Sendable { case app, clip, browser }
public enum EventNativeRoute: String, Codable, Sendable { case showNative = "show_native", openApp = "open_app", offerInstall = "offer_install", offerOpenOrInstall = "offer_open_or_install" }
public enum EventInstallKnowledge: Sendable { case installed, absent, unknown }
public enum EventRouting {
    public static func nativeAction(surface: EventSurface, installation: EventInstallKnowledge) -> EventNativeRoute {
        if surface == .app { return .showNative }
        switch installation {
        case .installed: return .openApp
        case .absent: return .offerInstall
        case .unknown: return .offerOpenOrInstall
        }
    }
    // An invocation failure leaves installation unknown; it never proves absence.
}
