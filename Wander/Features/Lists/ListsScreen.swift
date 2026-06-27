import SwiftUI

struct ListsScreen: View {
    private let scenario: ListsScreenScenario
    @State private var selectedScopeID: String
    @State private var editorPresentation: ListEditorPresentation?
    @State private var selectedList: PlaceListMock?

    init(scenario: ListsScreenScenario = .resolved()) {
        self.scenario = scenario
        let initialEditorPresentation: ListEditorPresentation? = switch scenario {
        case .create:
            .create
        case .edit:
            .edit(PlaceListMock.featuredDetail)
        default:
            nil
        }

        _selectedScopeID = State(initialValue: scenario.initialScope.rawValue)
        _editorPresentation = State(initialValue: initialEditorPresentation)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scenario.showsDetailRoot {
                    ListDetailScreen(list: PlaceListMock.featuredDetail) {
                        editorPresentation = .edit(PlaceListMock.featuredDetail)
                    }
                } else {
                    homeScreen
                }
            }
            .navigationDestination(item: $selectedList) { list in
                ListDetailScreen(list: list) {
                    editorPresentation = .edit(list)
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                ListEditorSheet(presentation: presentation)
                    .presentationDetents([.large])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
        }
    }

    private var homeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                header
                scopeSwitch

                if activeLists.isEmpty {
                    emptyState
                } else {
                    listGrid
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .wanderScreen()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("lists")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text("save places into a plan you can actually use")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Button {
                editorPresentation = .create
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 56, height: 56)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
                    .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 10, x: 0, y: 6)
            }
            .accessibilityLabel("New list")
        }
    }

    private var scopeSwitch: some View {
        WanderSegmentedSwitch(
            options: ListsScope.allCases.map { WanderSegmentOption(id: $0.rawValue, title: $0.title) },
            selection: $selectedScopeID
        )
        .accessibilityLabel("List type")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Spacer(minLength: WanderTheme.spacing6)

            Button {
                editorPresentation = .create
            } label: {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Image(systemName: "plus")
                        .font(.system(size: 42, weight: .black))
                        .frame(width: 92, height: 92)
                        .background(WanderTheme.terracotta.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Circle())
                        .shadow(color: WanderTheme.textInk.color.opacity(0.16), radius: 16, x: 0, y: 8)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("Add places to your list")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(WanderTheme.textInk.color)

                        Text("Tap the save icon, then choose a list name to start adding places.")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("new list")
                        .font(.system(size: 16, weight: .black))
                        .padding(.horizontal, WanderTheme.spacing4)
                        .frame(minHeight: 48)
                        .background(WanderTheme.textInk.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WanderTheme.spacing6)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create your first list")

            emptyHintRow
        }
    }

    private var emptyHintRow: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 18, weight: .black))
                .frame(width: 44, height: 44)
                .background(WanderTheme.terracottaTint.color)
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("coming next")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Saved places will get an add-to-list action from map surfaces.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var listGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: WanderTheme.spacing3),
                GridItem(.flexible(), spacing: WanderTheme.spacing3)
            ],
            alignment: .leading,
            spacing: WanderTheme.spacing6
        ) {
            ForEach(activeLists) { list in
                Button {
                    selectedList = list
                } label: {
                    ListTile(list: list)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(list.name)")
            }
        }
    }

    private var activeLists: [PlaceListMock] {
        guard scenario != .empty else { return [] }

        switch selectedScope {
        case .mine:
            return PlaceListMock.mine
        case .friends:
            return PlaceListMock.friends
        case .collabs:
            return PlaceListMock.collabs
        }
    }

    private var selectedScope: ListsScope {
        ListsScope(rawValue: selectedScopeID) ?? .mine
    }
}

enum ListsScope: String, CaseIterable {
    case mine
    case friends
    case collabs

    var title: String {
        switch self {
        case .mine: "My lists"
        case .friends: "Friends"
        case .collabs: "Collabs"
        }
    }
}

enum ListsScreenScenario: String {
    case populated
    case empty
    case friends
    case collabs
    case detail
    case create
    case edit

    var initialScope: ListsScope {
        switch self {
        case .friends:
            .friends
        case .collabs:
            .collabs
        default:
            .mine
        }
    }

    var showsDetailRoot: Bool {
        self == .detail || self == .edit
    }

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> ListsScreenScenario {
        guard let flagIndex = arguments.firstIndex(of: "-WanderListsScenario") else {
            return .populated
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .populated
        }

        return ListsScreenScenario(rawValue: arguments[valueIndex]) ?? .populated
    }
}

private struct ListTile: View {
    let list: PlaceListMock

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            ListPreviewMosaic(list: list)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                HStack(spacing: WanderTheme.spacing1) {
                    Text(list.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if list.isStealth {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }

                Text(list.subtitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }

            if !list.collaborators.isEmpty {
                HStack(spacing: WanderTheme.spacing2) {
                    FacePileView(collaborators: list.collaborators, size: 24)
                    Text(list.collaboratorSummary)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct ListPreviewMosaic: View {
    let list: PlaceListMock

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(list.previewPlaces.prefix(4).enumerated()), id: \.offset) { _, place in
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .fill(place.tint)

                    Image(systemName: WanderPlaceCategory.symbolName(for: place.category))
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.75), lineWidth: 1)
        )
    }
}

private struct ListDetailScreen: View {
    let list: PlaceListMock
    var onEdit: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                detailHeader
                mapPreview
                placeRows
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .wanderScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .black))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Edit list")

                Button {} label: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .black))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Manage collaborators")
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Text(list.name)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        if list.isStealth {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }

                    Text(list.description)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: WanderTheme.spacing2) {
                FacePileView(collaborators: list.collaborators, size: 30)
                Text(list.collaboratorSummary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
                Text("\(list.places.count) places")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }
            .padding(.top, WanderTheme.spacing1)
        }
    }

    private var mapPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                .fill(
                    LinearGradient(
                        colors: [
                            WanderTheme.skyTint.color,
                            WanderTheme.surfaceBone.color,
                            WanderTheme.sunTint.color
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ForEach(Array(list.places.prefix(5).enumerated()), id: \.offset) { index, place in
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: index == 0 ? 34 : 26, weight: .black))
                    .foregroundStyle(index == 0 ? WanderTheme.terracotta.color : WanderTheme.pinSocial.color)
                    .position(place.pinPosition)
            }

            VStack {
                Spacer()
                HStack {
                    Label("list map preview", systemImage: "map.fill")
                        .font(.system(size: 12, weight: .black))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minHeight: 34)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.90))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(WanderTheme.spacing3)
            }
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var placeRows: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("places")
                .font(.system(size: 18, weight: .black))

            ForEach(list.places) { place in
                ListPlaceRow(place: place)
            }
        }
    }
}

private struct ListPlaceRow: View {
    let place: ListPlaceMock

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ZStack {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .fill(place.tint)

                Image(systemName: WanderPlaceCategory.symbolName(for: place.category))
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(place.name)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)

                Text(place.metadata)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }

            Spacer()

            Button {} label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(WanderTheme.surfaceSand.color)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Remove \(place.name)")
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.70), lineWidth: 1)
        )
    }
}

private enum ListEditorPresentation: Identifiable, Hashable {
    case create
    case edit(PlaceListMock)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let list):
            "edit-\(list.id)"
        }
    }
}

private struct ListEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let presentation: ListEditorPresentation
    @State private var title: String
    @State private var description: String
    @State private var isStealth: Bool

    init(presentation: ListEditorPresentation) {
        self.presentation = presentation

        switch presentation {
        case .create:
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _isStealth = State(initialValue: false)
        case .edit(let list):
            _title = State(initialValue: list.name)
            _description = State(initialValue: list.description)
            _isStealth = State(initialValue: list.isStealth)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text(isEditing ? "edit list" : "new list")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text(isEditing ? "Keep the name, privacy, and collaborators current." : "Name the plan, decide who can see it, then add places.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    fieldBlock(title: "title") {
                        TextField("LA laptop mornings", text: $title)
                            .font(.system(size: 17, weight: .bold))
                            .textInputAutocapitalization(.words)
                    }

                    fieldBlock(title: "description") {
                        TextField("quiet tables, outlets, places worth returning to", text: $description, axis: .vertical)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(3...5)
                    }

                    stealthToggle
                    collaboratorsBlock

                    WanderPrimaryButton(title: isEditing ? "Save changes" : "Save list", systemImage: "checkmark", isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        dismiss()
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = presentation { return true }
        return false
    }

    private var visibleCollaborators: [ListCollaboratorMock] {
        switch presentation {
        case .create:
            [PlaceListMock.maya]
        case .edit(let list):
            list.collaborators
        }
    }

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            content()
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
        }
    }

    private var stealthToggle: some View {
        Toggle(isOn: $isStealth) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("stealth mode")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(isStealth ? "Only you and invited collaborators can see it." : "People who follow you can see this list.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(WanderTheme.textInk.color)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var collaboratorsBlock: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("collaborators")
                        .font(.system(size: 14, weight: .black))
                    Text("Invite people before they can add places.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .black))
                        .frame(width: 44, height: 44)
                        .background(WanderTheme.terracottaTint.color)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Invite collaborator")
            }

            if visibleCollaborators.isEmpty {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .black))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text("No collaborators yet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Spacer()
                }
            } else {
                ForEach(visibleCollaborators) { collaborator in
                    HStack(spacing: WanderTheme.spacing2) {
                        WanderAvatar(initials: collaborator.initials, size: 32, color: collaborator.color)
                        Text("@\(collaborator.name.lowercased())")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text(isEditing ? "can add places" : "draft invite")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                        Spacer()
                    }
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct FacePileView: View {
    let collaborators: [ListCollaboratorMock]
    var size: CGFloat

    var body: some View {
        HStack(spacing: -8) {
            ForEach(collaborators.prefix(3)) { collaborator in
                WanderAvatar(initials: collaborator.initials, size: size, color: collaborator.color)
            }
        }
        .frame(minWidth: collaborators.isEmpty ? 0 : size + CGFloat(max(0, min(collaborators.count, 3) - 1)) * (size - 8), alignment: .leading)
    }
}

private struct PlaceListMock: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let ownerName: String
    let isStealth: Bool
    let collaborators: [ListCollaboratorMock]
    let places: [ListPlaceMock]

    var previewPlaces: [ListPlaceMock] { places }

    var subtitle: String {
        if ownerName == "You" {
            return "\(places.count) places"
        }

        return "\(ownerName) - \(places.count) places"
    }

    var collaboratorSummary: String {
        guard !collaborators.isEmpty else { return "solo list" }

        if collaborators.count == 1 {
            return "\(collaborators[0].name)"
        }

        return collaborators.map(\.name).prefix(2).joined(separator: " + ")
    }

    static func == (lhs: PlaceListMock, rhs: PlaceListMock) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct ListPlaceMock: Identifiable {
    let id: String
    let name: String
    let category: String
    let metadata: String
    let tint: Color
    let pinPosition: CGPoint
}

private struct ListCollaboratorMock: Identifiable {
    let id: String
    let name: String
    let initials: String
    let color: Color
}

private extension PlaceListMock {
    static let joe = ListCollaboratorMock(id: "joe", name: "Joe", initials: "J", color: WanderTheme.terracotta.color)
    static let maya = ListCollaboratorMock(id: "maya", name: "Maya", initials: "M", color: WanderTheme.avatarSofia.color)
    static let ryan = ListCollaboratorMock(id: "ryan", name: "Ryan", initials: "R", color: WanderTheme.avatarRyan.color)
    static let sofia = ListCollaboratorMock(id: "sofia", name: "Sofia", initials: "S", color: WanderTheme.avatarAndrew.color)

    static let laptopPlaces = [
        ListPlaceMock(id: "circuit", name: "Circuit Coffee", category: "coffee", metadata: "coffee - outlets - quiet", tint: WanderTheme.skyTint.color, pinPosition: CGPoint(x: 78, y: 70)),
        ListPlaceMock(id: "fern", name: "Fern Desk Coffee", category: "coffee", metadata: "coffee - wifi solid", tint: WanderTheme.terracottaTint.color, pinPosition: CGPoint(x: 232, y: 88)),
        ListPlaceMock(id: "woodcat", name: "Woodcat Coffee", category: "coffee", metadata: "coffee - window table", tint: WanderTheme.sunTint.color, pinPosition: CGPoint(x: 168, y: 132)),
        ListPlaceMock(id: "elysian", name: "Elysian Picnic Steps", category: "park", metadata: "park - sunset backup", tint: WanderTheme.categorySage.color.opacity(0.36), pinPosition: CGPoint(x: 278, y: 134))
    ]

    static let dinnerPlaces = [
        ListPlaceMock(id: "bar-nido", name: "Bar Nido", category: "restaurant", metadata: "restaurant - date night", tint: WanderTheme.terracottaTint.color, pinPosition: CGPoint(x: 94, y: 104)),
        ListPlaceMock(id: "juniper", name: "Juniper Table", category: "restaurant", metadata: "restaurant - cozy", tint: WanderTheme.sunTint.color, pinPosition: CGPoint(x: 210, y: 62)),
        ListPlaceMock(id: "larchmont", name: "Larchmont Noodles", category: "restaurant", metadata: "restaurant - rainy night", tint: WanderTheme.surfaceSand.color, pinPosition: CGPoint(x: 268, y: 132)),
        ListPlaceMock(id: "patio", name: "Patio Bar", category: "bar", metadata: "bar - after dinner", tint: WanderTheme.skyTint.color, pinPosition: CGPoint(x: 148, y: 142))
    ]

    static let outdoorsPlaces = [
        ListPlaceMock(id: "griffith", name: "Griffith Observatory Trail", category: "hike", metadata: "hike - sunset - easy", tint: WanderTheme.categorySage.color.opacity(0.42), pinPosition: CGPoint(x: 112, y: 74)),
        ListPlaceMock(id: "elysian-2", name: "Elysian Picnic Steps", category: "park", metadata: "park - low effort", tint: WanderTheme.sunTint.color, pinPosition: CGPoint(x: 232, y: 110)),
        ListPlaceMock(id: "lake", name: "Echo Park Lake", category: "park", metadata: "park - walk", tint: WanderTheme.skyTint.color, pinPosition: CGPoint(x: 172, y: 144)),
        ListPlaceMock(id: "fern-dell", name: "Fern Dell", category: "hike", metadata: "hike - coffee nearby", tint: WanderTheme.terracottaTint.color, pinPosition: CGPoint(x: 278, y: 70))
    ]

    static let mine = [
        PlaceListMock(id: "laptop", name: "LA laptop mornings", description: "Quiet tables, outlets, and coffee that does not turn into a scene.", ownerName: "You", isStealth: false, collaborators: [], places: laptopPlaces),
        PlaceListMock(id: "date", name: "Date night short list", description: "Warm rooms where conversation is easy.", ownerName: "You", isStealth: false, collaborators: [maya], places: dinnerPlaces),
        PlaceListMock(id: "sunset", name: "Low-effort sunsets", description: "Places that feel planned without becoming a project.", ownerName: "You", isStealth: true, collaborators: [], places: outdoorsPlaces),
        PlaceListMock(id: "rain", name: "Rainy night noodles", description: "Cozy bowls for when leaving the house needs to be worth it.", ownerName: "You", isStealth: false, collaborators: [ryan], places: Array(dinnerPlaces.prefix(3))),
        PlaceListMock(id: "nyc", name: "NYC next time", description: "Borrowed saves for a future weekend.", ownerName: "You", isStealth: false, collaborators: [sofia], places: Array(laptopPlaces.prefix(2)) + Array(dinnerPlaces.prefix(2)))
    ]

    static let friends = [
        PlaceListMock(id: "maya-sunset", name: "Maya's sunset walks", description: "Soft landings around LA.", ownerName: "Maya", isStealth: false, collaborators: [maya], places: outdoorsPlaces),
        PlaceListMock(id: "ryan-brooklyn", name: "Ryan's Brooklyn tables", description: "Dinner ideas for later.", ownerName: "Ryan", isStealth: false, collaborators: [ryan], places: dinnerPlaces),
        PlaceListMock(id: "sofia-coffee", name: "Sofia's coffee to work from", description: "Laptop-friendly without office energy.", ownerName: "Sofia", isStealth: false, collaborators: [sofia], places: laptopPlaces)
    ]

    static let collabs = [
        PlaceListMock(id: "saturday", name: "Saturday plan", description: "A shared shortlist for where the day can go next.", ownerName: "You", isStealth: false, collaborators: [joe, maya, ryan], places: Array(laptopPlaces.prefix(2)) + Array(outdoorsPlaces.prefix(2))),
        PlaceListMock(id: "parents", name: "Parents in town", description: "Easy wins, low stairs, good table spacing.", ownerName: "Maya", isStealth: false, collaborators: [maya, joe], places: Array(dinnerPlaces.prefix(2)) + Array(outdoorsPlaces.prefix(2))),
        PlaceListMock(id: "launch", name: "Launch week meals", description: "Places near the office where nobody has to decide too hard.", ownerName: "Ryan", isStealth: true, collaborators: [ryan, joe, sofia], places: Array(laptopPlaces.prefix(3)) + Array(dinnerPlaces.prefix(1)))
    ]

    static let featuredDetail = mine[0]
}
