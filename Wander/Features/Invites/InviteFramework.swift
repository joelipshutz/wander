import Foundation

enum InviteSurface: Equatable {
    case sharedVisit(placeName: String?)
    case feedPeople
    case listCollaborator(listName: String?)

    var analyticsValue: String {
        switch self {
        case .sharedVisit:
            "shared_visit"
        case .feedPeople:
            "feed_people"
        case .listCollaborator:
            "list_collaborator"
        }
    }

    var entryTitle: String {
        switch self {
        case .sharedVisit:
            "invite someone from contacts"
        case .feedPeople:
            "invite people to rec.me"
        case .listCollaborator:
            "invite a collaborator"
        }
    }

    var entrySubtitle: String {
        switch self {
        case .sharedVisit:
            "Invite them to rec.me, then connect after they join."
        case .feedPeople:
            "Bring the people whose taste you trust."
        case .listCollaborator:
            "Invite someone to rec.me, then add them to this list."
        }
    }

    var inviteMessage: String {
        switch self {
        case .sharedVisit(let placeName):
            if let placeName, !placeName.isEmpty {
                "Join me on rec.me so we can connect around my check-in at \(placeName)."
            } else {
                "Join me on rec.me so we can connect around our check-ins."
            }
        case .feedPeople:
            "Join me on rec.me so we can share places worth remembering."
        case .listCollaborator(let listName):
            if let listName, !listName.isEmpty {
                "Join me on rec.me so I can add you as a collaborator on \(listName)."
            } else {
                "Join me on rec.me so I can add you as a list collaborator."
            }
        }
    }

    var sheetTitle: String {
        switch self {
        case .sharedVisit:
            "add people"
        case .feedPeople:
            "invite people"
        case .listCollaborator:
            "add collaborators"
        }
    }

    var sheetSubtitle: String {
        switch self {
        case .sharedVisit(let placeName):
            if let placeName, !placeName.isEmpty {
                "Who joined you at \(placeName)?"
            } else {
                "Who were you with?"
            }
        case .feedPeople:
            "rec.me is better with people you actually know."
        case .listCollaborator(let listName):
            if let listName, !listName.isEmpty {
                "Invite people to help build \(listName)."
            } else {
                "Invite people to build this list with you."
            }
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .sharedVisit:
            "Add"
        case .feedPeople:
            "Invite"
        case .listCollaborator:
            "Invite"
        }
    }

    var permissionMessage: String {
        switch self {
        case .sharedVisit:
            "Find the people you were with without typing every name."
        case .feedPeople:
            "Find people you know and choose who gets an invite."
        case .listCollaborator:
            "Find the right collaborators without leaving your list."
        }
    }

    var completionTitle: String {
        switch self {
        case .sharedVisit:
            "invite sent"
        case .feedPeople:
            "invite sent"
        case .listCollaborator:
            "collaborator invite sent"
        }
    }
}

enum InviteContactRelationship: Equatable {
    case contactOnly
    case recmeUser(handle: String, userID: String)

    var isOnRecme: Bool {
        if case .recmeUser = self { return true }
        return false
    }
}

struct InviteContact: Identifiable, Equatable {
    let id: String
    let displayName: String
    let contactDetail: String?
    let relationship: InviteContactRelationship
    let isFrequentlyContacted: Bool

    var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    var sectionTitle: String {
        guard let first = displayName.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "#"
        }
        let value = String(first).uppercased()
        return value.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "#" : value
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let searchable = [displayName, contactDetail, handle.map { "@\($0)" }]
            .compactMap { $0 }
            .joined(separator: " ")
        return searchable.localizedCaseInsensitiveContains(normalized)
    }

    private var handle: String? {
        guard case .recmeUser(let handle, _) = relationship else { return nil }
        return handle
    }

    init(
        id: String,
        displayName: String,
        contactDetail: String?,
        relationship: InviteContactRelationship,
        isFrequentlyContacted: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.contactDetail = contactDetail
        self.relationship = relationship
        self.isFrequentlyContacted = isFrequentlyContacted
    }

    init(contactMatch: ContactMatch) {
        id = contactMatch.id
        displayName = contactMatch.displayName
        contactDetail = contactMatch.contactDetail
        if let handle = contactMatch.handle, let userID = contactMatch.userID {
            relationship = .recmeUser(handle: handle, userID: userID)
        } else {
            relationship = .contactOnly
        }
        isFrequentlyContacted = contactMatch.isAlreadyFollowing || contactMatch.followsCurrentUser
    }
}

struct InviteContactSection: Identifiable, Equatable {
    let id: String
    let title: String
    let contacts: [InviteContact]

    static func sections(for contacts: [InviteContact], query: String = "") -> [InviteContactSection] {
        let filtered = contacts.filter { $0.matches(query) }
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var result: [InviteContactSection] = []

        if !isSearching {
            let frequent = filtered
                .filter(\.isFrequentlyContacted)
                .sorted(by: sortContacts)
            if !frequent.isEmpty {
                result.append(InviteContactSection(id: "frequent", title: "frequently contacted", contacts: frequent))
            }
        }

        let grouped = Dictionary(grouping: filtered.filter { isSearching || !$0.isFrequentlyContacted }) {
            $0.sectionTitle
        }
        for title in grouped.keys.sorted() {
            result.append(
                InviteContactSection(
                    id: "letter-\(title)",
                    title: title,
                    contacts: grouped[title, default: []].sorted(by: sortContacts)
                )
            )
        }
        return result
    }

    private static func sortContacts(_ lhs: InviteContact, _ rhs: InviteContact) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

struct InviteSelection: Equatable {
    static let maximumCount = 20

    private(set) var contactIDs: Set<String> = []

    init(contactIDs: Set<String> = []) {
        self.contactIDs = contactIDs
    }

    var count: Int { contactIDs.count }

    func contains(_ contactID: String) -> Bool {
        contactIDs.contains(contactID)
    }

    @discardableResult
    mutating func toggle(_ contactID: String) -> Bool {
        if contactIDs.contains(contactID) {
            contactIDs.remove(contactID)
            return true
        } else {
            guard contactIDs.count < Self.maximumCount else { return false }
            contactIDs.insert(contactID)
            return true
        }
    }

    mutating func remove(_ contactID: String) {
        contactIDs.remove(contactID)
    }
}

struct InviteMessageDeliveryPlan: Equatable {
    private(set) var pendingContacts: [InviteContact]
    private(set) var sentContactIDs: [String] = []

    init(contacts: [InviteContact]) {
        pendingContacts = contacts
    }

    var currentContact: InviteContact? { pendingContacts.first }
    var sentCount: Int { sentContactIDs.count }

    @discardableResult
    mutating func markCurrentSent() -> InviteContact? {
        guard !pendingContacts.isEmpty else { return nil }
        let contact = pendingContacts.removeFirst()
        sentContactIDs.append(contact.id)
        return contact
    }

    mutating func cancelRemaining() {
        pendingContacts.removeAll()
    }
}

enum InviteAlphabetIndex {
    static func index(yPosition: CGFloat, height: CGFloat, itemCount: Int) -> Int? {
        guard itemCount > 0, height > 0 else { return nil }
        let progress = min(max(yPosition / height, 0), 0.999_999)
        return min(Int(progress * CGFloat(itemCount)), itemCount - 1)
    }
}

struct InviteIntent: Equatable {
    let surface: InviteSurface
    let resourceID: String?

    var analyticsProperties: [String: String] {
        ["surface": surface.analyticsValue]
    }
}
