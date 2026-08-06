@preconcurrency import Contacts
import Foundation

enum ContactProviderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

struct ContactMatch: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let contactDetail: String?
    let handle: String?
    let userID: String?
    let isAlreadyFollowing: Bool
    let followsCurrentUser: Bool

    init(
        id: String,
        displayName: String,
        contactDetail: String? = nil,
        handle: String?,
        userID: String?,
        isAlreadyFollowing: Bool,
        followsCurrentUser: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.contactDetail = contactDetail
        self.handle = handle
        self.userID = userID
        self.isAlreadyFollowing = isAlreadyFollowing
        self.followsCurrentUser = followsCurrentUser
    }

    var isMatchedUser: Bool {
        userID != nil
    }
}

protocol ContactProvider: Sendable {
    func authorization() async -> ContactProviderAuthorization
    func requestAccess() async -> ContactProviderAuthorization
    func matches() async throws -> [ContactMatch]
}

extension ContactProvider {
    func authorization() async -> ContactProviderAuthorization { .authorized }
    func requestAccess() async -> ContactProviderAuthorization { .authorized }
}

struct FakeContactProvider: ContactProvider {
    let seededMatches: [ContactMatch]

    func matches() async throws -> [ContactMatch] {
        seededMatches
    }
}

actor SystemContactProvider: ContactProvider {
    private let store: CNContactStore

    init(store: CNContactStore = CNContactStore()) {
        self.store = store
    }

    func authorization() async -> ContactProviderAuthorization {
        Self.authorization(for: CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAccess() async -> ContactProviderAuthorization {
        let current = CNContactStore.authorizationStatus(for: .contacts)
        guard current == .notDetermined else {
            return Self.authorization(for: current)
        }

        do {
            _ = try await store.requestAccess(for: .contacts)
        } catch {
            return .denied
        }
        return Self.authorization(for: CNContactStore.authorizationStatus(for: .contacts))
    }

    func matches() async throws -> [ContactMatch] {
        guard await authorization() == .authorized else { return [] }

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault

        var results: [ContactMatch] = []
        try store.enumerateContacts(with: request) { contact, _ in
            guard let match = Self.match(for: contact) else { return }
            results.append(match)
        }
        return results
    }

    private static func authorization(for status: CNAuthorizationStatus) -> ContactProviderAuthorization {
        switch status {
        case .authorized, .limited:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private static func match(for contact: CNContact) -> ContactMatch? {
        let formattedName = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneNumber = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let phoneNumber, !phoneNumber.isEmpty else { return nil }
        let displayNameCandidates: [String?] = [formattedName, organization, phoneNumber]
        let displayName = displayNameCandidates
            .compactMap { $0 }
            .first { !$0.isEmpty }

        guard let displayName else { return nil }
        return ContactMatch(
            id: contact.identifier,
            displayName: displayName,
            contactDetail: phoneNumber,
            handle: nil,
            userID: nil,
            isAlreadyFollowing: false,
            followsCurrentUser: false
        )
    }
}
