import Foundation

public enum EventContractError: Error, Equatable, Sendable {
    case invalid(String)
    case unsupportedVersion
    case staleContext
}

/// Opaque canonical identifiers, never an authentication credential.
public struct EventIdentifier<Kind>: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) throws {
        guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw EventContractError.invalid("empty or padded identifier")
        }
        rawValue = value
    }
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EventIdentityKind {}
public enum EventPlaceKind {}
public enum EventAccountKind {}
public enum EventBookingKind {}
public enum EventGenerationKind {}
public enum EventAdmissionKind {}
public enum EventCompletionKind {}
public enum EventVisitKind {}
public enum EventSourceKind {}
public enum EventOperationKind {}
public enum EventOfferKind {}
public typealias EventID = EventIdentifier<EventIdentityKind>
public typealias EventPlaceID = EventIdentifier<EventPlaceKind>
public typealias EventAccountID = EventIdentifier<EventAccountKind>
public typealias EventBookingID = EventIdentifier<EventBookingKind>
public typealias EventGenerationID = EventIdentifier<EventGenerationKind>
public typealias EventAdmissionID = EventIdentifier<EventAdmissionKind>
public typealias EventCompletionID = EventIdentifier<EventCompletionKind>
public typealias EventVisitID = EventIdentifier<EventVisitKind>
public typealias EventSourceID = EventIdentifier<EventSourceKind>
public typealias EventOperationID = EventIdentifier<EventOperationKind>
public typealias EventOfferID = EventIdentifier<EventOfferKind>

/// Preserve wire precision. Local clocks/display conversions never decide eligibility.
public struct EventInstant: Codable, Equatable, Sendable {
    public let rawValue: String
    public let epochMicroseconds: Int64
    public var date: Date {
        Date(timeIntervalSince1970: Double(epochMicroseconds) / 1_000_000)
    }
    public init(_ value: String) throws {
        let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$"#
        let fraction = value.contains(".") ? String(value.dropFirst(20).dropLast()) : ""
        guard value.range(of: pattern, options: .regularExpression) == (value.startIndex..<value.endIndex),
              !value.hasPrefix("0000"),
              let fractionValue = Int64(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)),
              let parsed = Self.formatter(fractional: false).date(from: String(value.prefix(19)) + "Z"),
              Self.formatter(fractional: false).string(from: parsed).prefix(19) == value.prefix(19)
        else { throw EventContractError.invalid("invalid UTC instant") }
        rawValue = value
        epochMicroseconds = Int64(parsed.timeIntervalSince1970) * 1_000_000 + fractionValue
    }
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EventBookingStatus: String, Codable, Sendable {
    case pending, waitlisted, offered, confirmed, canceled, declined
}
public enum EventAdmissionStatus: String, Codable, Sendable { case none, valid, revoked }
public enum EventCompletionStatus: String, Codable, Sendable { case none, completed }
public enum EventPostStatus: String, Codable, Sendable { case absent, present, deleted }
public enum EventRecapStatus: String, Codable, Sendable { case unpublished, publishedLocked = "published_locked", publishedEligible = "published_eligible" }
public enum EventCapability: String, Codable, CaseIterable, Sendable {
    case submitRSVP = "submit_rsvp", joinWaitlist = "join_waitlist", acceptOffer = "accept_offer"
    case cancelRSVP = "cancel_rsvp", viewGuestList = "view_guest_list", manageRSVP = "manage_rsvp"
    case requestEntryCredential = "request_entry_credential", completeCheckin = "complete_checkin", viewRecap = "view_recap"
}
public enum EventRetryClass: String, Codable, Sendable {
    case none, authenticate, refresh, sameOperation = "same_operation", retryLater = "retry_later", userInput = "user_input"
}
public enum EventErrorCode: String, Codable, Sendable {
    case authenticationRequired = "authentication_required", sessionExpired = "session_expired"
    case accountMismatch = "account_mismatch", permissionDenied = "permission_denied", teamAccessRevoked = "team_access_revoked"
    case phoneVerificationRequired = "phone_verification_required", phoneChallengeInvalid = "phone_challenge_invalid", phoneChallengeExpired = "phone_challenge_expired"
    case nameRequired = "name_required", usernameRequired = "username_required", usernameUnavailable = "username_unavailable"
    case eventUnavailable = "event_unavailable", eventAccessDenied = "event_access_denied", registrationClosed = "registration_closed", nativeActionRequired = "native_action_required"
    case existingRequest = "existing_request", capacityUnavailable = "capacity_unavailable", codeRequired = "code_required", codeInvalid = "code_invalid", codeDisabled = "code_disabled", codeExhausted = "code_exhausted"
    case offerExpired = "offer_expired", offerUnavailable = "offer_unavailable", notOfferOwner = "not_offer_owner", cancellationClosed = "cancellation_closed"
    case staleRevision = "stale_revision", operationConflict = "operation_conflict", capacityCommitmentsConflict = "capacity_commitments_conflict", policyResolutionRequired = "policy_resolution_required"
    case bookingIneligible = "booking_ineligible", rosterMismatch = "roster_mismatch", alreadyAdmitted = "already_admitted", reconciliationConflict = "reconciliation_conflict"
    case recapUnpublished = "recap_unpublished", admissionRequired = "admission_required", completionRequired = "completion_required", sourceRemoved = "source_removed", assetNotReady = "asset_not_ready", assetAccessDenied = "asset_access_denied", completionExistsPostDeleted = "completion_exists_post_deleted"
    case temporarilyUnavailable = "temporarily_unavailable", rateLimited = "rate_limited"
}
public struct EventFailure: Codable, Equatable, Sendable {
    public let code: EventErrorCode
    public let retryClass: EventRetryClass
    public init(code: EventErrorCode, retryClass: EventRetryClass) { self.code = code; self.retryClass = retryClass }
}

public struct EventBooking: Codable, Equatable, Sendable {
    public let bookingId: EventBookingID
    public let generationId: EventGenerationID
    public let status: EventBookingStatus
    public let revision: Int
    public let offer: EventOffer?
    private enum CodingKeys: String, CodingKey { case bookingId, generationId, status, revision, offer }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookingId = try c.decode(EventBookingID.self, forKey: .bookingId)
        generationId = try c.decode(EventGenerationID.self, forKey: .generationId)
        status = try c.decode(EventBookingStatus.self, forKey: .status)
        revision = try c.decode(Int.self, forKey: .revision)
        offer = try c.decode(EventOffer?.self, forKey: .offer)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bookingId, forKey: .bookingId); try c.encode(generationId, forKey: .generationId)
        try c.encode(status, forKey: .status); try c.encode(revision, forKey: .revision)
        try c.encode(offer, forKey: .offer)
    }
}
public struct EventOffer: Codable, Equatable, Sendable {
    public let offerId: EventOfferID
    public let deadline: EventInstant
}
public struct EventResolvedViewer: Codable, Equatable, Sendable {
    public let accountId: EventAccountID
    /// Null means a successful authenticated lookup found no booking.
    public let booking: EventBooking?
    public let admission: EventAdmissionStatus
    public let completion: EventCompletionStatus
    public let personalPost: EventPostStatus
    public let profile: EventProfileReadiness
    private enum CodingKeys: String, CodingKey { case accountId, booking, admission, completion, personalPost, profile }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(EventAccountID.self, forKey: .accountId)
        booking = try c.decode(EventBooking?.self, forKey: .booking)
        admission = try c.decode(EventAdmissionStatus.self, forKey: .admission)
        completion = try c.decode(EventCompletionStatus.self, forKey: .completion)
        personalPost = try c.decode(EventPostStatus.self, forKey: .personalPost)
        profile = try c.decode(EventProfileReadiness.self, forKey: .profile)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountId, forKey: .accountId); try c.encode(booking, forKey: .booking)
        try c.encode(admission, forKey: .admission); try c.encode(completion, forKey: .completion)
        try c.encode(personalPost, forKey: .personalPost); try c.encode(profile, forKey: .profile)
    }
}
public struct EventProfileReadiness: Codable, Equatable, Sendable {
    public let hasName: Bool
    public let hasUsername: Bool
    /// Server-confirmed proof for the current number; not a local phone string.
    public let phoneVerified: Bool
    public var missingRSVPFields: [EventSetupField] {
        (hasName ? [] : [.name]) + (phoneVerified ? [] : [.phoneVerification])
    }
    public var missingEntryFields: [EventSetupField] {
        (hasName ? [] : [.name]) + (hasUsername ? [] : [.username])
    }
}
public enum EventSetupField: String, Codable, Sendable { case name, username, phoneVerification = "phone_verification" }

/// Unknown/failed can never be represented as a resolved empty RSVP.
public enum EventViewer: Codable, Equatable, Sendable {
    case unknown
    case failed(EventFailure)
    case resolved(EventResolvedViewer)
    private enum Keys: String, CodingKey { case status, failure, value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "unknown": self = .unknown
        case "failed": self = .failed(try c.decode(EventFailure.self, forKey: .failure))
        case "resolved": self = .resolved(try c.decode(EventResolvedViewer.self, forKey: .value))
        default: throw EventContractError.invalid("unsupported viewer state")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .unknown: try c.encode("unknown", forKey: .status)
        case .failed(let failure): try c.encode("failed", forKey: .status); try c.encode(failure, forKey: .failure)
        case .resolved(let value): try c.encode("resolved", forKey: .status); try c.encode(value, forKey: .value)
        }
    }
}

public struct EventMetadata: Codable, Equatable, Sendable {
    public let eventId: EventID
    public let placeId: EventPlaceID
    public let revision: Int
    public let title: String
    public let startsAt: EventInstant
    public let endsAt: EventInstant
    public let timeZone: String
}

public struct EventPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    func validate() throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw EventContractError.invalid("invalid coordinate")
        }
    }
}
public struct EventPublicVenue: Codable, Equatable, Sendable {
    public let label: String
    public let point: EventPoint
}
public struct EventApproximateLocation: Codable, Equatable, Sendable {
    public let label: String
    /// A deliberately displaced public area center, never the exact home coordinate.
    public let areaCenter: EventPoint
    public let radiusMeters: Double
}
public struct EventExactLocation: Codable, Equatable, Sendable {
    public let address: String
    public let point: EventPoint
    public let accessValidUntil: EventInstant
}
public enum EventLocation: Codable, Equatable, Sendable {
    case hidden
    case publicVenue(EventPublicVenue)
    case approximate(EventApproximateLocation)
    case authorizedExact(EventExactLocation)
    private enum Keys: String, CodingKey { case kind, value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "hidden": self = .hidden
        case "public_venue": self = .publicVenue(try c.decode(EventPublicVenue.self, forKey: .value))
        case "approximate": self = .approximate(try c.decode(EventApproximateLocation.self, forKey: .value))
        case "authorized_exact": self = .authorizedExact(try c.decode(EventExactLocation.self, forKey: .value))
        default: throw EventContractError.invalid("unsupported location projection")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .hidden: try c.encode("hidden", forKey: .kind)
        case .publicVenue(let v): try c.encode("public_venue", forKey: .kind); try c.encode(v, forKey: .value)
        case .approximate(let v): try c.encode("approximate", forKey: .kind); try c.encode(v, forKey: .value)
        case .authorizedExact(let v): try c.encode("authorized_exact", forKey: .kind); try c.encode(v, forKey: .value)
        }
    }
}

/// Guest projection only. Admin records, feedback, phones and gallery bytes have separate APIs.
public struct EventView: Codable, Equatable, Sendable {
    public let event: EventMetadata
    public let viewer: EventViewer
    public let capabilities: [EventCapability]
    public let location: EventLocation
    public let recap: EventRecapStatus
    public let permissionVersion: String

    func validate(at serverTime: EventInstant) throws {
        guard event.revision > 0, event.revision <= 9_007_199_254_740_991, event.endsAt.epochMicroseconds > event.startsAt.epochMicroseconds,
              EventWire.isTimeZone(event.timeZone), EventWire.isNonempty(permissionVersion),
              Set(capabilities).count == capabilities.count else { throw EventContractError.invalid("event metadata") }
        let rights = Set(capabilities)
        switch location {
        case .hidden: break
        case .publicVenue(let v): try v.point.validate()
        case .approximate(let v):
            try v.areaCenter.validate()
            guard v.radiusMeters.isFinite, v.radiusMeters > 0 else { throw EventContractError.invalid("approximation radius") }
        case .authorizedExact(let v):
            try v.point.validate()
            guard case .resolved = viewer, v.accessValidUntil.epochMicroseconds > serverTime.epochMicroseconds else {
                throw EventContractError.invalid("unauthorized or expired exact location")
            }
        }
        guard case .resolved(let v) = viewer else {
            guard rights.isEmpty, recap != .publishedEligible else { throw EventContractError.invalid("unresolved private rights") }
            return
        }
        if let booking = v.booking {
            guard booking.revision > 0, booking.revision <= 9_007_199_254_740_991, (booking.status == .offered) == (booking.offer != nil) else {
                throw EventContractError.invalid("booking offer state")
            }
        }
        if v.completion == .none && v.personalPost != .absent { throw EventContractError.invalid("post without completion") }
        if v.completion == .completed && v.personalPost == .absent { throw EventContractError.invalid("completion without historical post state") }
        let confirmed = v.booking?.status == .confirmed
        if !confirmed && !rights.isDisjoint(with: [.viewGuestList, .manageRSVP, .cancelRSVP, .requestEntryCredential]) {
            throw EventContractError.invalid("confirmed guest rights without confirmation")
        }
        if rights.contains(.acceptOffer) && (v.booking?.status != .offered || v.booking!.offer!.deadline.epochMicroseconds <= serverTime.epochMicroseconds) {
            throw EventContractError.invalid("acceptance without current offer")
        }
        if rights.contains(.submitRSVP), let status = v.booking?.status, status != .canceled && status != .declined {
            throw EventContractError.invalid("new attempt with active booking")
        }
        if rights.contains(.requestEntryCredential) && !v.profile.missingEntryFields.isEmpty {
            throw EventContractError.invalid("entry setup missing")
        }
        let recapEligible = v.admission == .valid && v.completion == .completed && recap != .unpublished
        guard (recap == .publishedEligible) == recapEligible,
              !rights.contains(.viewRecap) || recapEligible else { throw EventContractError.invalid("recap rights") }
        if rights.contains(.completeCheckin) && (v.admission != .valid || v.completion != .none || recap == .unpublished) {
            throw EventContractError.invalid("completion eligibility")
        }
    }
}

public enum EventReadPayload: Codable, Equatable, Sendable {
    case available(EventView)
    case unavailable(EventFailure)
    private enum Keys: String, CodingKey { case status, view, failure }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "available": self = .available(try c.decode(EventView.self, forKey: .view))
        case "unavailable": self = .unavailable(try c.decode(EventFailure.self, forKey: .failure))
        default: throw EventContractError.invalid("unsupported event read state")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .available(let view): try c.encode("available", forKey: .status); try c.encode(view, forKey: .view)
        case .unavailable(let failure): try c.encode("unavailable", forKey: .status); try c.encode(failure, forKey: .failure)
        }
    }
}

public struct EventReadResponse: Codable, Equatable, Sendable {
    public let contractVersion: Int
    public let eventId: EventID
    public let serverTime: EventInstant
    public let payload: EventReadPayload

    public func validate() throws {
        guard contractVersion == 1 else { throw EventContractError.unsupportedVersion }
        if case .available(let view) = payload {
            guard view.event.eventId == eventId else { throw EventContractError.invalid("event mismatch") }
            try view.validate(at: serverTime)
        } else if case .unavailable(let failure) = payload {
            guard [.eventUnavailable, .eventAccessDenied, .permissionDenied, .authenticationRequired, .sessionExpired, .temporarilyUnavailable, .rateLimited].contains(failure.code) else {
                throw EventContractError.invalid("invalid unavailable reason")
            }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        let result = try EventWire.decoder().decode(Self.self, from: data)
        try result.validate()
        return result
    }
}

public enum EventWire {
    static func isNonempty(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isTimeZone(_ value: String) -> Bool {
        let namedZone = value.range(of: #"^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$"#, options: .regularExpression) != nil
        return (value == "UTC" || namedZone) && TimeZone(identifier: value) != nil
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return encoder
    }
}
