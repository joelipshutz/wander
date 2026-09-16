import Foundation

public struct EventBookingEffect: Codable, Equatable, Sendable {
    public let bookingId: EventBookingID
    public let generationId: EventGenerationID
}
public struct EventAdmissionEffect: Codable, Equatable, Sendable {
    public let admissionId: EventAdmissionID
    public let bookingId: EventBookingID
    public let generationId: EventGenerationID
}
public struct EventCompletionEffect: Codable, Equatable, Sendable {
    public let completionId: EventCompletionID
    public let visitId: EventVisitID
}

/// Separate console projection: never infer Team admin from a guest's capabilities or URL.
public enum EventConsoleAccess: String, Codable, Sendable {
    case teamAdmin = "team_admin", denied, revoked
}
public enum EventOfflineAdmissionStatus: String, Codable, Sendable {
    case durablePending = "durable_pending", syncing, acknowledged, conflict, unknown
}
public struct EventOfflineAdmission: Codable, Equatable, Sendable {
    public let operationId: EventOperationID
    public let actingAdminId: EventAccountID
    public let eventId: EventID
    public let bookingId: EventBookingID
    public let generationId: EventGenerationID
    public let rosterSnapshotId: String
    public let rosterVersion: Int
    public let localRecordedAt: EventInstant
    public let localStatus: EventOfflineAdmissionStatus
    /// Local queue state is never canonical attendance or recap authorization.
    public func validate(in context: EventRequestContext) throws {
        guard context.eventId == eventId, context.accountId == actingAdminId,
              EventWire.isNonempty(rosterSnapshotId), rosterVersion > 0, rosterVersion <= 9_007_199_254_740_991 else {
            throw EventContractError.invalid("offline operation scope")
        }
    }
}
public enum EventDeliveryStatus: String, Codable, Sendable {
    case queued, claimed, providerAccepted = "provider_accepted", deliveryConfirmed = "delivery_confirmed"
    case retryableFailure = "retryable_failure", terminalFailure = "terminal_failure", suppressed, unknown
}

/// Typed allowlist for the future analytics adapter. No IDs, title, phone, code, location,
/// feedback, raw error text, account token or command payload can be attached here.
public struct EventAnalyticsDimensions: Codable, Sendable {
    public let surface: EventSurface
    public let action: EventAnalyticsAction
    public let outcome: EventAnalyticsOutcome
    public init(surface: EventSurface, action: EventAnalyticsAction, outcome: EventAnalyticsOutcome) {
        self.surface = surface; self.action = action; self.outcome = outcome
    }
}
public enum EventAnalyticsAction: String, Codable, Sendable { case view, rsvp, entry, checkin, recap }
public enum EventAnalyticsOutcome: String, Codable, Sendable { case started, succeeded, rejected, unknown }
