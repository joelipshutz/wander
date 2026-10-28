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
            "Invite Someone From Contacts"
        case .feedPeople:
            "Invite People To Astir"
        case .listCollaborator:
            "Invite A Collaborator"
        }
    }

    var entrySubtitle: String {
        switch self {
        case .sharedVisit:
            "Invite Them To Astir, Then Connect After They Join."
        case .feedPeople:
            "Bring The People Whose Taste You Trust."
        case .listCollaborator:
            "Invite Someone To Astir, Then Add Them To This List."
        }
    }

    var inviteMessage: String {
        switch self {
        case .sharedVisit(let placeName):
            if let placeName, !placeName.isEmpty {
                "Join Me On Astir So We Can Connect Around My Check-In At \(placeName)."
            } else {
                "Join Me On Astir So We Can Connect Around Our Check-Ins."
            }
        case .feedPeople:
            "Join Me On Astir So We Can Share Places Worth Remembering."
        case .listCollaborator(let listName):
            if let listName, !listName.isEmpty {
                "Join Me On Astir So I Can Add You As A Collaborator On \(listName)."
            } else {
                "Join Me On Astir So I Can Add You As A List Collaborator."
            }
        }
    }

    var sheetTitle: String {
        switch self {
        case .sharedVisit:
            "Add People"
        case .feedPeople:
            "Invite People"
        case .listCollaborator:
            "Add Collaborators"
        }
    }

    var sheetSubtitle: String {
        switch self {
        case .sharedVisit(let placeName):
            if let placeName, !placeName.isEmpty {
                "Who Joined You At \(placeName)?"
            } else {
                "Who Were You With?"
            }
        case .feedPeople:
            "Astir Is Better With People You Actually Know."
        case .listCollaborator(let listName):
            if let listName, !listName.isEmpty {
                "Invite People To Help Build \(listName)."
            } else {
                "Invite People To Build This List With You."
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
            "Find The People You Were With Without Typing Every Name."
        case .feedPeople:
            "Find People You Know And Choose Who Gets An Invite."
        case .listCollaborator:
            "Find The Right Collaborators Without Leaving Your List."
        }
    }

    var completionTitle: String {
        switch self {
        case .sharedVisit:
            "Invite Sent"
        case .feedPeople:
            "Invite Sent"
        case .listCollaborator:
            "Collaborator Invite Sent"
        }
    }
}

enum ContactInviteWalkthroughContent {
    static let selectionGoal = 5

    static let inviteProse =
        "Hey Sharing An Invite To Astir A Social App For Tracking Places. "
        + "This App Is Perfect For You And Selfishly I Need You On The App So I Can See The Places That You've Been To. "
        + "Excited To Have You On And Make Sure To Use My Link. "
        + "Heads Up This Invite Expires In 24 Hours."
}

enum ContactInviteWalkthroughComposerOutcome: Equatable {
    case sent
    case cancelled
    case failed
}

enum ContactInviteWalkthroughProgressReducer {
    enum Action: Equatable {
        case messageComposerFinished(
            contactID: String,
            outcome: ContactInviteWalkthroughComposerOutcome
        )
    }

    static func reduce(
        state: InviteSelection,
        action: Action,
        goal: Int = ContactInviteWalkthroughContent.selectionGoal
    ) -> InviteSelection {
        var nextState = state
        guard goal > 0 else { return nextState }

        switch action {
        case .messageComposerFinished(let contactID, let outcome):
            guard outcome == .sent,
                  canInvite(contactID: contactID, state: nextState, goal: goal)
            else { return nextState }
            _ = nextState.insert(contactID)
        }

        return nextState
    }

    static func canInvite(
        contactID: String,
        state: InviteSelection,
        goal: Int = ContactInviteWalkthroughContent.selectionGoal
    ) -> Bool {
        goal > 0 && state.count < goal && !state.contains(contactID)
    }

    static func isComplete(
        state: InviteSelection,
        goal: Int = ContactInviteWalkthroughContent.selectionGoal
    ) -> Bool {
        goal > 0 && state.count >= goal
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
                result.append(InviteContactSection(id: "frequent", title: "Frequently Contacted", contacts: frequent))
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
    mutating func insert(_ contactID: String) -> Bool {
        guard contactIDs.count < Self.maximumCount else { return false }
        return contactIDs.insert(contactID).inserted
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
