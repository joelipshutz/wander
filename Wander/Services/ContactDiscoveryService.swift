import Foundation

struct ContactDiscoveryIdentifier: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case phone, email }
    let kind: Kind
    let value: String
}

enum ContactDiscoveryError: Error, LocalizedError {
    case permissionDenied, tooManyContacts, unavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Allow Contacts access in iOS Settings to find friends. You can still search by name."
        case .tooManyContacts: "Choose fewer contacts in iOS Settings to find friends. You can still search by name."
        case .unavailable: "Contact matching couldn’t load. You can try again or search by name."
        }
    }
}

@MainActor protocol ContactDiscoveryRepository {
    func isEnabled() async throws -> Bool
    func setEnabled(_ enabled: Bool) async throws
    func match(_ identifiers: [ContactDiscoveryIdentifier], region: String?) async throws -> [ProfileShell]
}

@MainActor struct SupabaseContactDiscoveryRepository: ContactDiscoveryRepository {
    let functions: any RemoteFunctionCalling
    private struct Request: Encodable {
        let action: String
        var identifiers: [ContactDiscoveryIdentifier]? = nil
        var region: String? = nil
    }
    private struct Status: Decodable { let enabled: Bool }
    private struct Matches: Decodable { let profiles: [RemoteProfileShellDTO] }
    func isEnabled() async throws -> Bool {
        let result: Status = try await functions.invoke("contact-discovery", body: Request(action: "status"))
        return result.enabled
    }
    func setEnabled(_ enabled: Bool) async throws {
        let result: Status = try await functions.invoke("contact-discovery", body: Request(action: enabled ? "enable" : "disable"))
        guard result.enabled == enabled else { throw ContactDiscoveryError.unavailable }
    }
    func match(_ identifiers: [ContactDiscoveryIdentifier], region: String?) async throws -> [ProfileShell] {
        let result: Matches = try await functions.invoke("contact-discovery",
            body: Request(action: "match", identifiers: identifiers, region: region))
        return result.profiles.map { $0.profileShell() }
    }
}

/// Permission alone, including an old invitation grant, never authorizes
/// matching. Consent is account- and device-specific; no contacts are persisted.
@MainActor final class ContactDiscoveryService {
    static let didChange = Notification.Name("AstirContactDiscoveryChanged")
    private let repository: (any ContactDiscoveryRepository)?
    private let provider: any ContactProvider
    private let defaults: UserDefaults
    private let activeUserID: () -> String?
    private var revision = 0
    private var disableOperations: [String: (id: UUID, task: Task<Void, Error>)] = [:]

    init(repository: (any ContactDiscoveryRepository)?, provider: any ContactProvider = SystemContactProvider(),
         defaults: UserDefaults = .standard, activeUserID: @escaping () -> String?) {
        self.repository = repository; self.provider = provider; self.defaults = defaults; self.activeUserID = activeUserID
    }
    func hasConsent(userID: String) -> Bool { defaults.bool(forKey: key(userID)) }
    private func key(_ userID: String) -> String { "Astir.contactDiscovery.consent.v1.\(userID)" }
    private func requireUser(_ userID: String) throws {
        try Task.checkCancellation()
        guard activeUserID() == userID else { throw AuthSessionError.notSignedIn }
    }
    func invalidateContactAccess() { revision += 1 }
    private func changed() {
        revision += 1
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    func enable(userID: String) async throws {
        try requireUser(userID)
        if let pending = disableOperations[userID] { try await pending.task.value }
        if defaults.bool(forKey: key(userID) + ".pendingDisable") { try await disable(userID: userID) }
        try requireUser(userID)
        guard let repository else { throw ContactDiscoveryError.unavailable }
        guard await provider.requestAccess() == .authorized else { throw ContactDiscoveryError.permissionDenied }
        try requireUser(userID)
        try await repository.setEnabled(true)
        try requireUser(userID)
        defaults.set(true, forKey: key(userID))
        defaults.removeObject(forKey: key(userID) + ".pendingDisable")
        changed()
    }
    func disable(userID: String) async throws {
        // Clear local consent and in-flight results immediately, even offline.
        let needsNotification = hasConsent(userID: userID) || !defaults.bool(forKey: key(userID) + ".pendingDisable")
        defaults.removeObject(forKey: key(userID))
        defaults.set(true, forKey: key(userID) + ".pendingDisable")
        if needsNotification { changed() }
        if let pending = disableOperations[userID] { try await pending.task.value; return }
        try requireUser(userID)
        guard let repository else { throw ContactDiscoveryError.unavailable }
        let operationID = UUID()
        let operation = Task { @MainActor in
            try self.requireUser(userID)
            try await repository.setEnabled(false)
            try self.requireUser(userID)
            self.defaults.removeObject(forKey: self.key(userID) + ".pendingDisable")
        }
        disableOperations[userID] = (operationID, operation)
        defer { if disableOperations[userID]?.id == operationID { disableOperations.removeValue(forKey: userID) } }
        try await operation.value
    }
    func reconcile(userID: String) async throws -> Bool {
        try requireUser(userID)
        guard let repository else { return false }
        if defaults.bool(forKey: key(userID) + ".pendingDisable") { try await disable(userID: userID) }
        if hasConsent(userID: userID), await provider.authorization() != .authorized { try await disable(userID: userID) }
        try requireUser(userID)
        let requestedRevision = revision
        let enabled = try await repository.isEnabled()
        try requireUser(userID)
        guard requestedRevision == revision else { return hasConsent(userID: userID) }
        if !enabled, hasConsent(userID: userID) {
            defaults.removeObject(forKey: key(userID)); changed()
        }
        return enabled
    }
    func canUseResults(userID: String) async -> Bool {
        let requestedRevision = revision
        let authorization = await provider.authorization()
        return activeUserID() == userID && hasConsent(userID: userID)
            && requestedRevision == revision && authorization == .authorized
    }
    func matches(userID: String) async throws -> [ProfileShell] {
        try requireUser(userID)
        if defaults.bool(forKey: key(userID) + ".pendingDisable") { try await disable(userID: userID) }
        guard hasConsent(userID: userID), let repository else { return [] }
        guard await provider.authorization() == .authorized else {
            try await disable(userID: userID)
            return []
        }
        let requestedRevision = revision
        let enabled = try await repository.isEnabled()
        try requireUser(userID)
        guard requestedRevision == revision else { return [] }
        guard enabled else {
            defaults.removeObject(forKey: key(userID)); changed()
            return []
        }
        guard hasConsent(userID: userID), requestedRevision == revision else { return [] }
        let identifiers = try await provider.discoveryIdentifiers()
        let uploadAuthorization = await provider.authorization()
        try requireUser(userID)
        guard hasConsent(userID: userID), requestedRevision == revision,
              uploadAuthorization == .authorized else { return [] }
        guard !identifiers.isEmpty else { return [] }
        let results = try await repository.match(identifiers, region: Locale.current.region?.identifier)
        let resultAuthorization = await provider.authorization()
        try requireUser(userID)
        guard hasConsent(userID: userID), requestedRevision == revision,
              resultAuthorization == .authorized else { return [] }
        return results.filter { $0.id != userID && $0.isPrivateProfile != true }
    }
}

enum PeopleRecommendationMerge {
    static func combine(contacts: [ProfileShell], general: [DiscoverPeopleRecommendation], limit: Int) -> [DiscoverPeopleRecommendation] {
        var seen = Set<String>()
        let ordered = contacts.map { DiscoverPeopleRecommendation(profile: $0, reason: .contacts, rank: 0) } + general
        let unique = Array(ordered.filter { seen.insert($0.id).inserted }.prefix(max(0, limit)))
        guard !contacts.isEmpty else { return unique }
        return unique.enumerated().map {
            DiscoverPeopleRecommendation(profile: $0.element.profile, reason: $0.element.reason, rank: $0.offset + 1)
        }
    }
}
