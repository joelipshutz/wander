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
            "They’ll be added only after accepting."
        case .feedPeople:
            "Bring the people whose taste you trust."
        case .listCollaborator:
            "Share this list with someone not here yet."
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
            "invites ready"
        case .feedPeople:
            "invites ready"
        case .listCollaborator:
            "collaborator invites ready"
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
    private(set) var contactIDs: Set<String> = []

    init(contactIDs: Set<String> = []) {
        self.contactIDs = contactIDs
    }

    var count: Int { contactIDs.count }

    func contains(_ contactID: String) -> Bool {
        contactIDs.contains(contactID)
    }

    mutating func toggle(_ contactID: String) {
        if contactIDs.contains(contactID) {
            contactIDs.remove(contactID)
        } else {
            contactIDs.insert(contactID)
        }
    }
}

struct InviteIntent: Equatable {
    let surface: InviteSurface
    let resourceID: String?

    var analyticsProperties: [String: String] {
        ["surface": surface.analyticsValue]
    }
}
