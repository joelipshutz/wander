#if DEBUG
import SwiftUI

enum InviteMockupPage: String, CaseIterable {
    case checkInEntry
    case feedPeopleEntry
    case listCollaboratorEntry
    case permission
    case contacts
    case selected
    case empty
    case denied
    case success

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> InviteMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderInviteMockup") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .contacts }
        return InviteMockupPage(rawValue: arguments[valueIndex]) ?? .contacts
    }
}

struct InviteMockupRoot: View {
    let page: InviteMockupPage

    var body: some View {
        Group {
            switch page {
            case .checkInEntry:
                SharedVisitFriendPickerMockup()
            case .feedPeopleEntry:
                InviteEntryPointMockup(surface: .feedPeople)
            case .listCollaboratorEntry:
                InviteEntryPointMockup(surface: .listCollaborator(listName: "LA date nights"))
            case .permission:
                ContactInviteSheet(
                    surface: .sharedVisit(placeName: "Gjelina"),
                    contacts: InviteMockupData.contacts,
                    accessState: .primer,
                    canDismiss: false
                )
            case .contacts:
                ContactInviteSheet(
                    surface: .sharedVisit(placeName: "Gjelina"),
                    contacts: InviteMockupData.contacts,
                    canDismiss: false
                )
            case .selected:
                ContactInviteSheet(
                    surface: .sharedVisit(placeName: "Gjelina"),
                    contacts: InviteMockupData.contacts,
                    selectedContactIDs: ["maya", "joe", "adam"],
                    canDismiss: false
                )
            case .empty:
                ContactInviteSheet(
                    surface: .feedPeople,
                    contacts: InviteMockupData.contacts,
                    query: "someone impossible",
                    canDismiss: false
                )
            case .denied:
                ContactInviteSheet(
                    surface: .listCollaborator(listName: "LA date nights"),
                    contacts: InviteMockupData.contacts,
                    accessState: .denied,
                    canDismiss: false
                )
            case .success:
                ContactInviteSheet(
                    surface: .listCollaborator(listName: "LA date nights"),
                    contacts: InviteMockupData.contacts,
                    presentationState: .completed,
                    selectedContactIDs: ["maya", "joe"],
                    canDismiss: false
                )
            }
        }
        .preferredColorScheme(.light)
    }
}

@MainActor
private struct SharedVisitFriendPickerMockup: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @State private var selectedUserIDs: [String] = []

    var body: some View {
        SharedVisitFriendPicker(selectedUserIDs: $selectedUserIDs)
            .environmentObject(store)
    }
}

private struct InviteEntryPointMockup: View {
    let surface: InviteSurface
    @State private var isPresentingInviteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    mockHeader
                    mockSearch
                    InviteEntryPointButton(surface: surface) {
                        isPresentingInviteSheet = true
                    }
                    mockList
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .sharedVisit = surface {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {}
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingInviteSheet) {
            ContactInviteSheet(surface: surface, contacts: InviteMockupData.contacts)
        }
    }

    @ViewBuilder
    private var mockHeader: some View {
        switch surface {
        case .sharedVisit:
            EmptyView()
        case .feedPeople:
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("feed")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                HStack(spacing: WanderTheme.spacing2) {
                    mockSegment("places", selected: false)
                    mockSegment("people", selected: true)
                }
            }
        case .listCollaborator(let listName):
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("collaborators")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text(listName ?? "your list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }

    private var navigationTitle: String {
        if case .sharedVisit = surface { return "add friends" }
        return ""
    }

    private func mockSegment(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(selected ? WanderTheme.textOnAction.color : WanderTheme.textMuted.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 38)
            .background(selected ? WanderTheme.textInk.color : WanderTheme.surfaceSand.color)
            .clipShape(Capsule())
    }

    private var mockSearch: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(searchPlaceholder)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WanderTheme.textFaint.color)
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 50)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1) }
    }

    private var searchPlaceholder: String {
        switch surface {
        case .sharedVisit: "Search friends"
        case .feedPeople: "Search name or @handle"
        case .listCollaborator: "Search friends"
        }
    }

    private var mockList: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(listTitle)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ForEach(InviteMockupData.recmePeople) { contact in
                HStack(spacing: WanderTheme.spacing3) {
                    Text(contact.initials)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.stateInfo.color)
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.skyTint.color)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .font(.system(size: 15, weight: .black))
                        if case .recmeUser(let handle, _) = contact.relationship {
                            Text("@\(handle)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }
                    Spacer()
                    Text(trailingAction)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                }
            }
        }
    }

    private var listTitle: String {
        switch surface {
        case .sharedVisit: "friends"
        case .feedPeople: "people you follow"
        case .listCollaborator: "current collaborators"
        }
    }

    private var trailingAction: String {
        switch surface {
        case .sharedVisit: "add"
        case .feedPeople: "view"
        case .listCollaborator: "added"
        }
    }
}

private enum InviteMockupData {
    static let contacts: [InviteContact] = [
        InviteContact(id: "maya", displayName: "Maya Chen", contactDetail: nil, relationship: .recmeUser(handle: "mayac", userID: "user-maya"), isFrequentlyContacted: true),
        InviteContact(id: "joe", displayName: "Joe Lipshutz", contactDetail: nil, relationship: .recmeUser(handle: "jolipshutz", userID: "user-joe"), isFrequentlyContacted: true),
        InviteContact(id: "patrick", displayName: "Patrick Chen", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: true),
        InviteContact(id: "adam", displayName: "Adam Rivera", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "alejandro", displayName: "Alejandro Aguilar", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "alyx", displayName: "Alyx Barringer", contactDetail: "home", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "andrew", displayName: "Andrew Kim", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "bea", displayName: "Bea Moreno", contactDetail: nil, relationship: .recmeUser(handle: "beaeats", userID: "user-bea"), isFrequentlyContacted: false),
        InviteContact(id: "cam", displayName: "Cam Williams", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "daniela", displayName: "Daniela Ruiz", contactDetail: "work", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "eli", displayName: "Eli Rosen", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "frances", displayName: "Frances Lee", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "grace", displayName: "Grace Park", contactDetail: "home", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "harper", displayName: "Harper Stone", contactDetail: "mobile", relationship: .contactOnly, isFrequentlyContacted: false)
    ]

    static let recmePeople = contacts.filter { $0.relationship.isOnRecme }
}
#endif
