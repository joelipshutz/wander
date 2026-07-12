@preconcurrency import MapKit
import SwiftUI

struct ListsScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    private let scenario: ListsScreenScenario
    private let editorStartsWithFriendSearch: Bool
    private let editorStartsWithDeleteConfirmation: Bool
    @State private var selectedScopeID: String
    @State private var editorPresentation: ListEditorPresentation?
    @State private var selectedList: PlaceListMock?
    @State private var collaboratorList: PlaceListMock?
    @State private var mapList: PlaceListMock?
    @State private var deletedListIDs = Set<String>()

    init(scenario: ListsScreenScenario = .resolved()) {
        self.scenario = scenario
        self.editorStartsWithFriendSearch = scenario == .createCollaboratorsSearch
        self.editorStartsWithDeleteConfirmation = scenario == .editDeleteConfirm || scenario == .collabEditDeleteConfirm
        let featuredList = PlaceListMock.featuredDetail
        let initialEditorPresentation: ListEditorPresentation? = switch scenario {
        case .create, .createCollaboratorsSearch:
            .create
        case .edit, .editDeleteConfirm:
            .edit(featuredList)
        case .collabEdit, .collabEditDeleteConfirm:
            .edit(PlaceListMock.collabs[0])
        default:
            nil
        }
        let initialCollaboratorList: PlaceListMock? = scenario == .collaboratorsSheet ? featuredList : nil
        let initialMapList: PlaceListMock? = scenario == .mapPreview || scenario == .mapSelectedPlace ? featuredList : nil

        _selectedScopeID = State(initialValue: scenario.initialScope.rawValue)
        _editorPresentation = State(initialValue: initialEditorPresentation)
        _collaboratorList = State(initialValue: initialCollaboratorList)
        _mapList = State(initialValue: initialMapList)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scenario.showsDetailRoot {
                    detailScreen(for: PlaceListMock.featuredDetail, initialSelectedPlace: scenario == .placeDetail ? PlaceListMock.featuredDetail.places.first : nil)
                } else {
                    homeScreen
                }
            }
            .navigationDestination(item: $selectedList) { list in
                detailScreen(for: list)
            }
            .sheet(item: $editorPresentation) { presentation in
                ListEditorSheet(
                    presentation: presentation,
                    startsWithFriendSearch: editorStartsWithFriendSearch,
                    startsWithDeleteConfirmation: editorStartsWithDeleteConfirmation,
                    onSave: { draft in
                        saveList(draft, presentation: presentation)
                    },
                    onDelete: deleteList
                )
                    .presentationDetents([.large])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
            .sheet(item: $collaboratorList) { list in
                CollaboratorInviteSheet(
                    list: list,
                    onSave: { collaborators in
                        saveCollaborators(collaborators, for: list)
                    }
                )
                    .presentationDetents([.medium, .large])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
            .fullScreenCover(item: $mapList) { list in
                ListMapFullScreen(
                    list: list,
                    initialSelectedPlaceID: scenario == .mapSelectedPlace ? list.places.first?.id : nil
                )
            }
        }
    }

    private func detailScreen(for list: PlaceListMock, initialSelectedPlace: ListPlaceMock? = nil) -> some View {
        ListDetailScreen(
            list: list,
            onEdit: { list in
                editorPresentation = .edit(list)
            },
            onCollaborators: { list in
                if canOpenCollaborators(for: list) {
                    collaboratorList = list
                }
            },
            onOpenMap: { list in
                mapList = list
            },
            onListChanged: { sourceListID in
                refreshOpenList(sourceListID: sourceListID)
            },
            initialSelectedPlace: initialSelectedPlace
        )
    }

    private func canOpenCollaborators(for list: PlaceListMock) -> Bool {
        guard list.isOwnedByCurrentUser else { return false }
        return !store.isPrivateProfile || list.isCollaborative
    }

    private func deleteList(_ list: PlaceListMock) {
        if let sourceListID = list.sourceListID {
            _ = store.deletePlaceList(id: sourceListID)
        }
        deletedListIDs.insert(list.id)

        if selectedList?.id == list.id {
            selectedList = nil
        }
        if collaboratorList?.id == list.id {
            collaboratorList = nil
        }
        if mapList?.id == list.id {
            mapList = nil
        }
        syncLists()
    }

    private func saveList(_ draft: ListEditorDraft, presentation: ListEditorPresentation) {
        let visibility: PlaceListVisibility = draft.isStealth ? .stealth : .followers
        let collaboratorUserIDs = draft.collaborators.map(\.id)

        switch presentation {
        case .create:
            _ = store.createPlaceList(
                name: draft.title,
                description: draft.description,
                visibility: visibility,
                collaboratorUserIDs: collaboratorUserIDs
            )
            selectedScopeID = ListsScope.mine.rawValue
            syncLists()
        case .edit(let list):
            guard let sourceListID = list.sourceListID else { return }
            _ = store.updatePlaceList(
                id: sourceListID,
                name: draft.title,
                description: draft.description,
                visibility: visibility,
                collaboratorUserIDs: collaboratorUserIDs
            )
            refreshOpenList(sourceListID: sourceListID)
            syncLists()
        }
    }

    private func saveCollaborators(_ collaborators: [ListCollaboratorMock], for list: PlaceListMock) {
        guard let sourceListID = list.sourceListID else { return }
        _ = store.setPlaceListCollaborators(
            listID: sourceListID,
            collaboratorUserIDs: collaborators.map(\.id)
        )
        refreshOpenList(sourceListID: sourceListID)
        syncLists()
    }

    private func syncLists() {
        Task {
            await syncAndRefreshLists()
        }
    }

    private func syncAndRefreshLists() async {
        _ = await store.syncPendingPlaceLists(backend: backend)
        await store.refreshRemotePlaceLists(backend: backend)
    }

    private func refreshOpenList(sourceListID: String) {
        guard let localList = store.visiblePlaceLists.first(where: {
            $0.id == sourceListID || $0.localID == sourceListID || $0.serverID == sourceListID
        }) else { return }
        let sourceIDs = Set([localList.id, localList.localID, localList.serverID, sourceListID].compactMap { $0 })
        let refreshed = PlaceListMock(list: localList, store: store)
        if selectedList?.sourceListID.map(sourceIDs.contains) == true {
            selectedList = refreshed
        }
        if collaboratorList?.sourceListID.map(sourceIDs.contains) == true {
            collaboratorList = refreshed
        }
        if mapList?.sourceListID.map(sourceIDs.contains) == true {
            mapList = refreshed
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
        .task {
            await syncAndRefreshLists()
        }
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
                        Text(emptyStateTitle)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(WanderTheme.textInk.color)

                        Text(emptyStateSubtitle)
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

    private var emptyStateTitle: String {
        switch selectedScope {
        case .mine:
            "Make your first list"
        case .friends:
            "No friend lists yet"
        case .collabs:
            "Make a new list"
        }
    }

    private var emptyStateSubtitle: String {
        switch selectedScope {
        case .mine:
            "Create a plan, then add places from map or search."
        case .friends:
            "Lists from people you follow will show up here when they share them."
        case .collabs:
            "Create a list and add a friend to make it collaborative."
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
                    ListTile(list: list, showsCollaborators: selectedScope != .mine)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(list.name)")
            }
        }
    }

    private var activeLists: [PlaceListMock] {
        guard scenario != .empty else { return [] }

        let storeLists = store.visiblePlaceLists(scope: selectedScope.placeListScope)
            .map { PlaceListMock(list: $0, store: store) }
            .filter { !deletedListIDs.contains($0.id) }

        guard !storeLists.isEmpty else {
            guard scenario.usesMockData else { return [] }

            switch selectedScope {
            case .mine:
                return PlaceListMock.mine.filter { !deletedListIDs.contains($0.id) }
            case .friends:
                return PlaceListMock.friends.filter { !deletedListIDs.contains($0.id) }
            case .collabs:
                return PlaceListMock.collabs.filter { !deletedListIDs.contains($0.id) }
            }
        }

        return storeLists
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

    var placeListScope: PlaceListScope {
        switch self {
        case .mine: .mine
        case .friends: .friends
        case .collabs: .collabs
        }
    }
}

enum ListsScreenScenario: String {
    case live
    case populated
    case empty
    case friends
    case collabs
    case detail
    case create
    case createCollaboratorsSearch
    case edit
    case collabEdit
    case editDeleteConfirm
    case collabEditDeleteConfirm
    case collaboratorsSheet
    case mapPreview
    case mapSelectedPlace
    case placeDetail

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
        switch self {
        case .detail, .edit, .collaboratorsSheet, .mapPreview, .mapSelectedPlace, .placeDetail:
            true
        default:
            false
        }
    }

    var usesMockData: Bool {
        switch self {
        case .live, .empty:
            false
        default:
            true
        }
    }

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> ListsScreenScenario {
        guard let flagIndex = arguments.firstIndex(of: "-WanderListsScenario") else {
            return .live
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .live
        }

        return ListsScreenScenario(rawValue: arguments[valueIndex]) ?? .populated
    }
}

private struct ListTile: View {
    let list: PlaceListMock
    let showsCollaborators: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            ListPreviewMosaic(list: list)
                .frame(maxWidth: .infinity)
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

                    if list.isCollaborative {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .accessibilityLabel("Collaborative list")
                    }
                }

                Text(list.subtitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }

            if showsCollaborators, !list.collaborators.isEmpty {
                HStack(spacing: WanderTheme.spacing2) {
                    FacePileView(collaborators: list.collaborators, size: 24)
                    Text(list.collaboratorSummary)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
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
            ForEach(0..<4, id: \.self) { index in
                mosaicTile(place: list.previewPlaces.indices.contains(index) ? list.previewPlaces[index] : nil)
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

    private func mosaicTile(place: ListPlaceMock?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .fill(place?.tint ?? WanderTheme.surfaceSand.color)

            Image(systemName: place.map { WanderPlaceCategory.symbolName(for: $0.category) } ?? "plus")
                .font(.system(size: place == nil ? 16 : 20, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color.opacity(place == nil ? 0.22 : 0.72))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ListDetailScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    let list: PlaceListMock
    var onEdit: (PlaceListMock) -> Void
    var onCollaborators: (PlaceListMock) -> Void
    var onOpenMap: (PlaceListMock) -> Void
    var onListChanged: (String) -> Void
    @State private var removedPlaceIDs = Set<String>()
    @State private var selectedPlace: ListPlaceMock?
    @State private var isAddingPlaces = false
    @State private var suggestions: [ListPlaceSuggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var shouldShowAutoSaveExplanation = false
    @State private var autoSaveToastTask: Task<Void, Never>?

    init(
        list: PlaceListMock,
        onEdit: @escaping (PlaceListMock) -> Void = { _ in },
        onCollaborators: @escaping (PlaceListMock) -> Void = { _ in },
        onOpenMap: @escaping (PlaceListMock) -> Void = { _ in },
        onListChanged: @escaping (String) -> Void = { _ in },
        initialSelectedPlace: ListPlaceMock? = nil
    ) {
        self.list = list
        self.onEdit = onEdit
        self.onCollaborators = onCollaborators
        self.onOpenMap = onOpenMap
        self.onListChanged = onListChanged
        _selectedPlace = State(initialValue: initialSelectedPlace)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                detailHeader
                mapPreview
                placeRows
                suggestionsSection
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .wanderScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canAddPlaces {
                    Button {
                        isAddingPlaces = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .black))
                            .frame(width: 34, height: 34)
                            .background(WanderTheme.textInk.color)
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add places to list")
                }

                if canManageList {
                    Button {
                        onEdit(displayList)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .black))
                            .frame(width: 34, height: 34)
                            .background(WanderTheme.surfaceSand.color)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit list")
                }
            }
        }
        .task(id: sourceList?.id ?? list.id) {
            _ = await store.syncPendingPlaceLists(backend: backend)
            await store.refreshRemotePlaceLists(backend: backend)
            await loadSuggestions()
        }
        .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
            selectedPlaceDestination
        }
        .navigationDestination(isPresented: $isAddingPlaces) {
            if let sourceList {
                ListAddPlacesScreen(list: sourceList) { result in
                    handleAddResult(result)
                    onListChanged(sourceList.id)
                    Task {
                        await loadSuggestions()
                    }
                }
            } else {
                ListAddPlacesUnavailableScreen()
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowAutoSaveExplanation {
                ListAutoSaveToast()
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: shouldShowAutoSaveExplanation)
        .onDisappear {
            autoSaveToastTask?.cancel()
        }
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedPlace != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceDestination: some View {
        if let selectedPlace {
            ListPlaceProfileDestination(place: selectedPlace) {
                self.selectedPlace = nil
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Text(displayList.name)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        if displayList.isStealth {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }

                    Text(displayList.description)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: WanderTheme.spacing2) {
                FacePileView(collaborators: displayList.collaborators, size: 30)
                Text(displayList.collaboratorSummary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                if canManageList {
                    Button {
                        onCollaborators(displayList)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(WanderTheme.terracottaTint.color)
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Manage collaborators")
                    .disabled(!canManageCollaborators)
                    .opacity(canManageCollaborators ? 1 : 0.48)
                    .accessibilityHint(collaboratorAccessibilityHint)
                }
                Spacer()
                Text("\(displayList.itemCount) places")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }
            .padding(.top, WanderTheme.spacing1)
        }
    }

    private var mapPreview: some View {
        Button {
            onOpenMap(displayList)
        } label: {
            ListMapPreview(list: displayList, height: 168, label: "open list map")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open map preview for \(displayList.name)")
    }

    private var placeRows: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("places")
                .font(.system(size: 18, weight: .black))

            if visiblePlaces.isEmpty {
                Text(displayList.itemCount > 0 ? "Loading places in this list." : "No places in this list yet.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WanderTheme.spacing4)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            } else {
                ForEach(visiblePlaces) { place in
                    ListPlaceRow(
                        place: place,
                        canRemove: canManageList,
                        onOpen: {
                            selectedPlace = place
                        },
                        onRemove: {
                            removePlace(place)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if canAddPlaces {
            ListSuggestionsSection(
                suggestions: suggestions,
                isLoading: isLoadingSuggestions,
                onAdd: { suggestion in
                    Task {
                        await addSuggestion(suggestion)
                    }
                },
                onOpen: { suggestion in
                    selectedPlace = ListPlaceMock(visiblePlace: suggestion.visiblePlace)
                }
            )
        }
    }

    private var visiblePlaces: [ListPlaceMock] {
        displayList.places.filter { !removedPlaceIDs.contains($0.id) }
    }

    private var sourceList: LocalPlaceList? {
        guard let sourceListID = list.sourceListID else { return nil }
        return store.placeLists.first {
            $0.id == sourceListID || $0.localID == sourceListID || $0.serverID == sourceListID
        }
    }

    private var displayList: PlaceListMock {
        sourceList.map { PlaceListMock(list: $0, store: store) } ?? list
    }

    private var canManageList: Bool {
        sourceList.map(store.canManage) ?? list.canManage
    }

    private var canAddPlaces: Bool {
        sourceList.map(store.canAddPlaces(to:)) ?? displayList.canAddPlaces
    }

    @MainActor
    private func loadSuggestions() async {
        guard let sourceList, canAddPlaces else {
            suggestions = []
            return
        }

        isLoadingSuggestions = true
        suggestions = await store.listSuggestions(for: sourceList, limit: 5, backend: backend)
        isLoadingSuggestions = false
    }

    @MainActor
    private func addSuggestion(_ suggestion: ListPlaceSuggestion) async {
        guard let sourceList else { return }
        let result = await store.addVisiblePlace(suggestion.visiblePlace, to: sourceList, backend: backend)
        handleAddResult(result)
        onListChanged(sourceList.id)
        await loadSuggestions()
    }

    @MainActor
    private func handleAddResult(_ result: ListPlaceAddResult) {
        if result.shouldExplainAutoSave {
            showAutoSaveToast()
        }
    }

    @MainActor
    private func showAutoSaveToast() {
        autoSaveToastTask?.cancel()
        shouldShowAutoSaveExplanation = true
        autoSaveToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                shouldShowAutoSaveExplanation = false
                autoSaveToastTask = nil
            }
        }
    }

    @MainActor
    private func removePlace(_ place: ListPlaceMock) {
        if let sourceList, let placeID = place.placeID {
            Task {
                _ = await store.removePlace(placeID: placeID, from: sourceList, backend: backend)
                await MainActor.run {
                    onListChanged(sourceList.id)
                }
            }
        } else {
            removedPlaceIDs.insert(place.id)
        }
    }

    private var canManageCollaborators: Bool {
        guard displayList.isOwnedByCurrentUser else { return false }
        return !store.isPrivateProfile || displayList.isCollaborative
    }

    private var collaboratorAccessibilityHint: String {
        if !displayList.isOwnedByCurrentUser {
            return "Only the list owner can manage collaborators"
        }

        guard store.isPrivateProfile else { return "" }

        if !displayList.isCollaborative {
            return "New collaborative lists are unavailable while Private Profile is on"
        }

        return "Add or remove friends on this existing collaborative list"
    }
}

private struct ListSuggestionsSection: View {
    let suggestions: [ListPlaceSuggestion]
    let isLoading: Bool
    let onAdd: (ListPlaceSuggestion) -> Void
    let onOpen: (ListPlaceSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("suggested places")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Spacer()
            }

            if isLoading {
                ListLoadingRow(title: "Finding places that fit this list")
            } else if suggestions.isEmpty {
                Text("Suggestions will appear as the list gets more specific.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WanderTheme.spacing4)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            } else {
                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(suggestions.prefix(4)) { suggestion in
                        ListVisiblePlaceAddRow(
                            visiblePlace: suggestion.visiblePlace,
                            supportingText: suggestion.reason,
                            onOpen: {
                                onOpen(suggestion)
                            },
                            onAdd: {
                                onAdd(suggestion)
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ListAddPlacesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    let list: LocalPlaceList
    let onAdded: (ListPlaceAddResult) -> Void
    @State private var query = ""
    @State private var suggestions: [ListPlaceSuggestion] = []
    @State private var searchCandidates: [PlaceCandidate] = []
    @State private var isLoadingSuggestions = false
    @State private var isSearching = false
    @State private var selectedPlace: ListPlaceMock?
    @State private var shouldShowAutoSaveExplanation = false
    @State private var autoSaveToastTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("add places")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(list.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                ListPlaceSearchField(query: $query)

                if normalizedQuery.isEmpty {
                    suggestionsContent
                } else {
                    searchContent
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .wanderScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            }
        }
        .task(id: list.id) {
            await loadSuggestions()
        }
        .onChange(of: query) { _, _ in
            Task {
                await runSearch()
            }
        }
        .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
            selectedPlaceDestination
        }
        .overlay(alignment: .bottom) {
            if shouldShowAutoSaveExplanation {
                ListAutoSaveToast()
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: shouldShowAutoSaveExplanation)
        .onDisappear {
            autoSaveToastTask?.cancel()
        }
    }

    @ViewBuilder
    private var suggestionsContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("suggested for this list")
                .font(.system(size: 18, weight: .black))

            if isLoadingSuggestions {
                ListLoadingRow(title: "Finding places that fit")
            } else if addableSuggestions.isEmpty {
                Text("Start with search, then suggestions will get sharper as the list fills in.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WanderTheme.spacing4)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            } else {
                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(addableSuggestions) { suggestion in
                        ListVisiblePlaceAddRow(
                            visiblePlace: suggestion.visiblePlace,
                            supportingText: suggestion.reason,
                            onOpen: {
                                selectedPlace = ListPlaceMock(visiblePlace: suggestion.visiblePlace)
                            },
                            onAdd: {
                                Task {
                                    await add(suggestion.visiblePlace)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("results")
                .font(.system(size: 18, weight: .black))

            if isSearching {
                ListLoadingRow(title: "Searching places")
            } else if addableSearchCandidates.isEmpty {
                Text("No places match that search.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WanderTheme.spacing4)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            } else {
                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(addableSearchCandidates) { candidate in
                        ListPlaceCandidateAddRow(
                            candidate: candidate,
                            supportingText: searchSupportingText(for: candidate),
                            onAdd: {
                                Task {
                                    await add(candidate)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var addableSuggestions: [ListPlaceSuggestion] {
        suggestions.filter { !store.hasPlace($0.visiblePlace, in: list) }
    }

    private var addableSearchCandidates: [PlaceCandidate] {
        searchCandidates.filter { !store.hasCandidate($0, in: list) }
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedPlace != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceDestination: some View {
        if let selectedPlace {
            ListPlaceProfileDestination(place: selectedPlace) {
                self.selectedPlace = nil
            }
        }
    }

    @MainActor
    private func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestions = await store.listSuggestions(for: list, limit: 8, backend: backend)
        isLoadingSuggestions = false
    }

    @MainActor
    private func runSearch() async {
        let query = normalizedQuery
        guard !query.isEmpty else {
            searchCandidates = []
            isSearching = false
            return
        }

        isSearching = true
        do {
            searchCandidates = try await store.manualCandidates(name: query, areaHint: nil, category: nil)
        } catch {
            searchCandidates = []
        }
        isSearching = false
    }

    @MainActor
    private func add(_ visiblePlace: VisiblePlace) async {
        let result = await store.addVisiblePlace(visiblePlace, to: list, backend: backend)
        onAdded(result)
        handleAddResult(result)
        await loadSuggestions()
        if !normalizedQuery.isEmpty {
            await runSearch()
        }
    }

    @MainActor
    private func handleAddResult(_ result: ListPlaceAddResult) {
        if result.shouldExplainAutoSave {
            showAutoSaveToast()
        }
    }

    @MainActor
    private func showAutoSaveToast() {
        autoSaveToastTask?.cancel()
        shouldShowAutoSaveExplanation = true
        autoSaveToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                shouldShowAutoSaveExplanation = false
                autoSaveToastTask = nil
            }
        }
    }

    @MainActor
    private func add(_ candidate: PlaceCandidate) async {
        let result = await store.addCandidate(candidate, to: list, backend: backend)
        onAdded(result)
        handleAddResult(result)
        await loadSuggestions()
        if !normalizedQuery.isEmpty {
            await runSearch()
        }
    }

    private func searchSupportingText(for candidate: PlaceCandidate) -> String {
        let parts: [String?] = [
            candidate.category,
            candidate.locality,
            candidate.region
        ]
        return parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}

private struct ListAddPlacesUnavailableScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("add places")
                .font(.system(size: 30, weight: .black, design: .rounded))
            Text("This list is not connected to local list data yet.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WanderTheme.spacing4)
        .wanderScreen()
    }
}

private struct ListAutoSaveToast: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .black))
                .frame(width: 34, height: 34)
                .background(WanderTheme.terracotta.color)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .clipShape(Circle())

            Text("We also saved this to your Want list.")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 18, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(WanderTheme.borderHairline.color.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct ListPlaceSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("Search places", text: $query)
                .font(.system(size: 16, weight: .bold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(WanderTheme.spacing3)
        .frame(minHeight: 54)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct ListVisiblePlaceAddRow: View {
    let visiblePlace: VisiblePlace
    let supportingText: String
    let onOpen: () -> Void
    let onAdd: () -> Void

    private var place: ListPlaceMock {
        ListPlaceMock(visiblePlace: visiblePlace)
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpen) {
                HStack(spacing: WanderTheme.spacing3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                            .fill(place.tint)
                        Image(systemName: WanderPlaceCategory.symbolName(for: place.category))
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)
                        Text(supportingText.isEmpty ? place.metadata : supportingText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }

                    Spacer(minLength: WanderTheme.spacing2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add \(place.name) to list")
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

private struct ListPlaceCandidateAddRow: View {
    let candidate: PlaceCandidate
    let supportingText: String
    let onAdd: () -> Void

    private var subtitle: String {
        if !supportingText.isEmpty {
            return supportingText
        }

        return [candidate.address, candidate.locality, candidate.region]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .fill(ListPlaceMock.tint(for: candidate.primaryCategory))
                    Image(systemName: WanderPlaceCategory.symbolName(for: candidate.primaryCategory))
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                    Text(subtitle.isEmpty ? "Map search" : subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }

                Spacer(minLength: WanderTheme.spacing2)
            }

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add \(candidate.name) to list")
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

private struct ListLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct ListMapPreview: View {
    let list: PlaceListMock
    let height: CGFloat
    let label: String

    var body: some View {
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

            GeometryReader { proxy in
                ForEach(Array(list.places.prefix(5).enumerated()), id: \.offset) { index, place in
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: index == 0 ? 34 : 26, weight: .black))
                        .foregroundStyle(index == 0 ? WanderTheme.terracotta.color : WanderTheme.pinSocial.color)
                        .position(scaledPosition(for: place, in: proxy.size))
                }
            }

            VStack {
                Spacer()
                HStack {
                    Label(label, systemImage: "map.fill")
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
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private func scaledPosition(for place: ListPlaceMock, in size: CGSize) -> CGPoint {
        let baseWidth: CGFloat = 340
        let baseHeight: CGFloat = 168
        let x = place.pinPosition.x / baseWidth * size.width
        let y = place.pinPosition.y / baseHeight * size.height

        return CGPoint(
            x: min(max(x, 24), max(size.width - 24, 24)),
            y: min(max(y, 24), max(size.height - 24, 24))
        )
    }
}

private struct ListPlaceRow: View {
    let place: ListPlaceMock
    var canRemove: Bool = true
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpen) {
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

                    Spacer(minLength: WanderTheme.spacing2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(place.name)")

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Remove \(place.name)")
            }
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

private struct CollaboratorInviteSheet: View {
    @EnvironmentObject private var store: WanderStore
    @Environment(\.dismiss) private var dismiss
    let list: PlaceListMock
    let onSave: ([ListCollaboratorMock]) -> Void
    @State private var selectedCollaborators: [ListCollaboratorMock]

    init(list: PlaceListMock, onSave: @escaping ([ListCollaboratorMock]) -> Void = { _ in }) {
        self.list = list
        self.onSave = onSave
        _selectedCollaborators = State(initialValue: list.collaborators)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("collaborators")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text(list.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    if store.isPrivateProfile && !canInviteWhilePrivate {
                        if !selectedCollaborators.isEmpty {
                            ExistingCollaboratorsSummary(collaborators: selectedCollaborators)
                        }
                        PrivateProfileCollaborationUnavailable(
                            message: selectedCollaborators.isEmpty
                                ? "Private Profile prevents new collaborative lists. Existing collaborative lists stay unchanged."
                                : "Existing collaborators stay on this list. New collaborator invites are unavailable while Private Profile is on."
                        )
                    } else {
                        FriendCollaboratorSearchContent(selectedCollaborators: $selectedCollaborators)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(selectedCollaborators)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
        }
    }

    private var canInviteWhilePrivate: Bool {
        list.isOwnedByCurrentUser && list.isCollaborative
    }
}

private struct FriendCollaboratorSearchSheet: View {
    @EnvironmentObject private var store: WanderStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCollaborators: [ListCollaboratorMock]
    let allowsInvitesWhilePrivate: Bool

    init(selectedCollaborators: Binding<[ListCollaboratorMock]>, allowsInvitesWhilePrivate: Bool = false) {
        _selectedCollaborators = selectedCollaborators
        self.allowsInvitesWhilePrivate = allowsInvitesWhilePrivate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("invite collaborator")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text("Search friends and add the people who can view this list with you.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if store.isPrivateProfile && !allowsInvitesWhilePrivate {
                        if !selectedCollaborators.isEmpty {
                            ExistingCollaboratorsSummary(collaborators: selectedCollaborators)
                        }
                        PrivateProfileCollaborationUnavailable(
                            message: selectedCollaborators.isEmpty
                                ? "Private Profile prevents new collaborative lists. Existing collaborative lists stay unchanged."
                                : "Existing collaborators stay on this list. New collaborator invites are unavailable while Private Profile is on."
                        )
                    } else {
                        FriendCollaboratorSearchContent(selectedCollaborators: $selectedCollaborators)
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
}

private struct FriendCollaboratorSearchContent: View {
    @EnvironmentObject private var store: WanderStore
    @Binding var selectedCollaborators: [ListCollaboratorMock]
    @State private var query = ""

    private var allFriendCandidates: [ListCollaboratorMock] {
        store.following(of: store.currentUser.id)
            .filter { store.relationship(to: $0.id) == .mutual }
            .map(ListCollaboratorMock.init(profile:))
    }

    private var friendCandidates: [ListCollaboratorMock] {
        allFriendCandidates.filter { friend in
            !selectedCollaborators.contains { isSameCollaborator($0, friend) }
        }
    }

    private var filteredFriends: [ListCollaboratorMock] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return friendCandidates }

        return friendCandidates.filter { friend in
            friend.name.lowercased().contains(normalized)
                || friend.handle.lowercased().contains(normalized)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                TextField("Search friends", text: $query)
                    .font(.system(size: 16, weight: .bold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(WanderTheme.spacing3)
            .frame(minHeight: 54)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )

            if !selectedCollaborators.isEmpty {
                selectedCollaboratorsSection
            }

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("friends")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                if allFriendCandidates.isEmpty {
                    Text("No friends available to invite.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WanderTheme.spacing3)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                } else if friendCandidates.isEmpty {
                    Text("All available friends are already collaborators.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WanderTheme.spacing3)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                } else if filteredFriends.isEmpty {
                    Text("No friends match that search.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WanderTheme.spacing3)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                } else {
                    ForEach(filteredFriends) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
    }

    private var selectedCollaboratorsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                FacePileView(collaborators: selectedCollaborators, size: 28)
                Text("\(selectedCollaborators.count) selected")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
            }

            ForEach(selectedCollaborators) { collaborator in
                HStack(spacing: WanderTheme.spacing2) {
                    WanderAvatar(
                        initials: collaborator.initials,
                        avatarURL: avatarURL(for: collaborator),
                        size: 32,
                        color: collaborator.color
                    )
                    Text("@\(collaborator.handle)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Spacer()
                    Button {
                        selectedCollaborators.removeAll { isSameCollaborator($0, collaborator) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WanderTheme.stateError.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove @\(collaborator.handle)")
                }
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }
        }
    }

    private func friendRow(_ friend: ListCollaboratorMock) -> some View {
        Button {
            selectedCollaborators.append(friend)
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: friend.initials,
                    avatarURL: friend.avatarURL,
                    size: 40,
                    color: friend.color
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(friend.handle)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(friend.name)")
    }

    private func isSameCollaborator(_ lhs: ListCollaboratorMock, _ rhs: ListCollaboratorMock) -> Bool {
        lhs.id == rhs.id || lhs.handle == rhs.handle
    }

    private func avatarURL(for collaborator: ListCollaboratorMock) -> String? {
        if let avatarURL = collaborator.avatarURL {
            return avatarURL
        }

        return store.profiles.first { profile in
            profile.id == collaborator.id || profile.handle == collaborator.handle
        }?.avatarURL
    }
}

private struct ExistingCollaboratorsSummary: View {
    let collaborators: [ListCollaboratorMock]
    var showsContainer = true

    var body: some View {
        if showsContainer {
            row
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: WanderTheme.spacing2) {
            FacePileView(collaborators: collaborators, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(collaborators.count) existing collaborator\(collaborators.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("This collaboration stays unchanged.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PrivateProfileCollaborationUnavailable: View {
    var showsContainer = true
    var title = "new collaboration is off"
    var message = "Private Profile prevents new collaborative lists. Existing collaborative lists stay unchanged."

    var body: some View {
        if showsContainer {
            content
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
        } else {
            content
                .padding(.vertical, WanderTheme.spacing1)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .black))
                .frame(width: 42, height: 42)
                .background(WanderTheme.terracottaTint.color)
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ListMapFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    let list: PlaceListMock
    @State private var position: MapCameraPosition
    @State private var selectedPlace: ListPlaceMock?
    @State private var profilePlace: ListPlaceMock?

    init(list: PlaceListMock, initialSelectedPlaceID: String? = nil) {
        self.list = list
        _position = State(initialValue: .region(list.mapRegion))
        _selectedPlace = State(initialValue: list.places.first { $0.id == initialSelectedPlaceID })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(list.places) { place in
                        Annotation(place.name, coordinate: place.coordinate) {
                            Button {
                                selectedPlace = place
                            } label: {
                                ListMapMarker(place: place, isSelected: selectedPlace?.id == place.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: WanderTheme.spacing3) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .black))
                                .frame(width: 44, height: 44)
                                .background(WanderTheme.surfaceRaised.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close list map")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .lineLimit(1)
                            Text("\(list.places.count) places")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }

                        Spacer()
                    }
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.92))
                    .clipShape(Capsule())
                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 16, x: 0, y: 8)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.top, WanderTheme.spacing2)

                    Spacer()
                }

                if let selectedPlace {
                    PlaceProfileMapSurface(
                        place: PlaceSheetPlace(listPlace: selectedPlace),
                        saves: [],
                        tasteSaves: [],
                        currentUserID: "you",
                        action: .none,
                        onOpen: {
                            profilePlace = selectedPlace
                        }
                    ) {}
                    .zIndex(20)
                } else {
                    ListMapPlaceRail(list: list) { place in
                        profilePlace = place
                    }
                    .zIndex(10)
                }
            }
            .background(WanderTheme.canvasWarm.color)
            .navigationDestination(isPresented: profilePlaceDestinationBinding) {
                profilePlaceDestination
            }
        }
    }

    private var profilePlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { profilePlace != nil },
            set: { isPresented in
                if !isPresented {
                    profilePlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var profilePlaceDestination: some View {
        if let profilePlace {
            ListPlaceProfileDestination(place: profilePlace) {
                self.profilePlace = nil
            }
        }
    }
}

private struct ListMapMarker: View {
    let place: ListPlaceMock
    let isSelected: Bool

    var body: some View {
        Image(systemName: WanderPlaceCategory.symbolName(for: place.category))
            .font(.system(size: isSelected ? 17 : 16, weight: .black))
            .frame(width: isSelected ? 44 : 40, height: isSelected ? 44 : 40)
            .background(WanderTheme.surfaceRaised.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(place.status == .wannaGo ? WanderTheme.pinSocial.color : WanderTheme.pinYou.color, style: StrokeStyle(lineWidth: isSelected ? 4 : 3, dash: place.status == .wannaGo ? [5, 4] : []))
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.20), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.08 : 1)
            .accessibilityLabel("\(place.name) on list map")
    }
}

private struct ListMapPlaceRail: View {
    let list: PlaceListMock
    let onSelect: (ListPlaceMock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text("places in this list")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
            }
            .padding(.horizontal, WanderTheme.spacing3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing3) {
                    ForEach(list.places) { place in
                        ListMapPlaceTile(place: place) {
                            onSelect(place)
                        }
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
            }
        }
        .padding(.vertical, WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: WanderTheme.textInk.color.opacity(0.16), radius: 24, x: 0, y: 12)
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
    }
}

private struct ListMapPlaceTile: View {
    let place: ListPlaceMock
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(place.tint)
                    Image(systemName: WanderPlaceCategory.symbolName(for: place.category))
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(place.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text(place.metadata)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
                .frame(width: 178, alignment: .leading)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(place.name)")
    }
}

private struct ListPlaceProfileDestination: View {
    let place: ListPlaceMock
    let onBack: () -> Void

    var body: some View {
        PlaceProfileFullScreen(
            place: PlaceSheetPlace(listPlace: place),
            saves: [],
            tasteSaves: [],
            currentUserID: "you",
            action: .none,
            onBack: onBack
        ) {}
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

private struct ListEditorDraft {
    let title: String
    let description: String
    let isStealth: Bool
    let collaborators: [ListCollaboratorMock]
}

private struct ListEditorSheet: View {
    @EnvironmentObject private var store: WanderStore
    @Environment(\.dismiss) private var dismiss
    private let presentation: ListEditorPresentation
    private let onSave: (ListEditorDraft) -> Void
    private let onDelete: (PlaceListMock) -> Void
    private let isOwnedByCurrentUser: Bool
    private let startedAsCollaborative: Bool
    @State private var title: String
    @State private var description: String
    @State private var isStealth: Bool
    @State private var stagedCollaborators: [ListCollaboratorMock]
    @State private var isShowingFriendSearch = false
    @State private var isShowingDeleteConfirmation = false

    init(
        presentation: ListEditorPresentation,
        startsWithFriendSearch: Bool = false,
        startsWithDeleteConfirmation: Bool = false,
        onSave: @escaping (ListEditorDraft) -> Void = { _ in },
        onDelete: @escaping (PlaceListMock) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.onSave = onSave
        self.onDelete = onDelete

        switch presentation {
        case .create:
            isOwnedByCurrentUser = true
            startedAsCollaborative = false
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _isStealth = State(initialValue: false)
            _stagedCollaborators = State(initialValue: [])
        case .edit(let list):
            isOwnedByCurrentUser = list.isOwnedByCurrentUser
            startedAsCollaborative = list.isCollaborative
            _title = State(initialValue: list.name)
            _description = State(initialValue: list.description)
            _isStealth = State(initialValue: list.isStealth)
            _stagedCollaborators = State(initialValue: list.collaborators)
        }
        _isShowingFriendSearch = State(initialValue: startsWithFriendSearch)
        _isShowingDeleteConfirmation = State(initialValue: startsWithDeleteConfirmation)
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
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing16 + WanderTheme.spacing16 + WanderTheme.spacing8)
            }
            .wanderScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                editorActionButtons
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingFriendSearch) {
                FriendCollaboratorSearchSheet(
                    selectedCollaborators: $stagedCollaborators,
                    allowsInvitesWhilePrivate: canEditCollaborators
                )
                    .presentationDetents([.large])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
            .onAppear {
                enforcePrivateProfileRules()
            }
            .onChange(of: store.isPrivateProfile) { _, _ in
                enforcePrivateProfileRules()
            }
            .alert("Delete List", isPresented: $isShowingDeleteConfirmation) {
                Button("Delete List", role: .destructive) {
                    if case .edit(let list) = presentation {
                        onDelete(list)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteConfirmationMessage)
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = presentation { return true }
        return false
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editorActionButtons: some View {
        VStack(spacing: WanderTheme.spacing3) {
            WanderPrimaryButton(
                title: isEditing ? "Save changes" : "Save list",
                systemImage: "checkmark",
                isDisabled: trimmedTitle.isEmpty
            ) {
                saveAndDismiss()
            }

            if isEditing {
                ListDestructiveButton(title: "Delete List", systemImage: "trash") {
                    isShowingDeleteConfirmation = true
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
        .background(WanderTheme.canvasWarm.color.opacity(0.96))
    }

    private func saveAndDismiss() {
        guard !trimmedTitle.isEmpty else { return }
        onSave(
            ListEditorDraft(
                title: title,
                description: description,
                isStealth: isStealth,
                collaborators: stagedCollaborators
            )
        )
        dismiss()
    }

    private var deleteConfirmationMessage: String {
        if stagedCollaborators.isEmpty {
            return "Are you sure you want to delete this list?"
        }

        return "Are you sure you want to delete this list? You will be deleting it for everybody."
    }

    private var listStealthBinding: Binding<Bool> {
        Binding(
            get: { store.isPrivateProfile ? true : isStealth },
            set: { newValue in
                guard !store.isPrivateProfile else {
                    isStealth = true
                    return
                }
                isStealth = newValue
            }
        )
    }

    private func enforcePrivateProfileRules() {
        guard store.isPrivateProfile else { return }
        isStealth = true
        if !canEditCollaborators {
            isShowingFriendSearch = false
        }
        if !startedAsCollaborative {
            stagedCollaborators = []
        }
    }

    private var stealthHelperCopy: String {
        if store.isPrivateProfile {
            if !stagedCollaborators.isEmpty {
                return "Locked on by Private Profile. Existing collaborators can still see this list."
            }

            return "Locked on by Private Profile. Only you can see this list."
        }

        return isStealth ? "Only you and invited collaborators can see it." : "People who follow you can see this list."
    }

    private var collaboratorsHelperCopy: String {
        guard isOwnedByCurrentUser else {
            return "Only the owner can manage collaborators."
        }

        guard store.isPrivateProfile else {
            return "Invite people before they can add places."
        }

        if !startedAsCollaborative {
            return "New collaborative lists are unavailable while Private Profile is on."
        }

        return "Existing collaborators stay on this list. You can add or remove friends."
    }

    private var canEditCollaborators: Bool {
        guard isOwnedByCurrentUser else { return false }
        return !store.isPrivateProfile || startedAsCollaborative
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
        Toggle(isOn: listStealthBinding) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("stealth mode")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(stealthHelperCopy)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(WanderTheme.textInk.color)
        .disabled(store.isPrivateProfile)
        .opacity(store.isPrivateProfile ? 0.56 : 1)
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
                    Text(collaboratorsHelperCopy)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                if canEditCollaborators {
                    Button {
                        isShowingFriendSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .black))
                            .frame(width: 44, height: 44)
                            .background(WanderTheme.terracottaTint.color)
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Invite collaborator")
                }
            }

            if store.isPrivateProfile && !canEditCollaborators && stagedCollaborators.isEmpty {
                PrivateProfileCollaborationUnavailable(
                    showsContainer: false,
                    title: "existing lists stay",
                    message: "Collaborators already on existing lists are not removed."
                )
            } else if stagedCollaborators.isEmpty {
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
            } else if store.isPrivateProfile && canEditCollaborators {
                ExistingCollaboratorsSummary(collaborators: stagedCollaborators, showsContainer: false)
            } else {
                ForEach(stagedCollaborators) { collaborator in
                    HStack(spacing: WanderTheme.spacing2) {
                        WanderAvatar(
                            initials: collaborator.initials,
                            avatarURL: avatarURL(for: collaborator),
                            size: 32,
                            color: collaborator.color
                        )
                        Text("@\(collaborator.handle)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text(isEditing ? "can view" : "draft invite")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                        Spacer()
                        if canEditCollaborators {
                            Button {
                                stagedCollaborators.removeAll { $0.id == collaborator.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundStyle(WanderTheme.stateError.color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove @\(collaborator.handle)")
                        }
                    }
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func avatarURL(for collaborator: ListCollaboratorMock) -> String? {
        if let avatarURL = collaborator.avatarURL {
            return avatarURL
        }

        return store.profiles.first { profile in
            profile.id == collaborator.id || profile.handle == collaborator.handle
        }?.avatarURL
    }
}

private struct ListDestructiveButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WanderTheme.stateError.color)
            .foregroundStyle(WanderTheme.textOnAction.color)
            .clipShape(Capsule())
        }
    }
}

private struct FacePileView: View {
    @EnvironmentObject private var store: WanderStore
    let collaborators: [ListCollaboratorMock]
    var size: CGFloat

    var body: some View {
        HStack(spacing: -8) {
            ForEach(collaborators.prefix(3)) { collaborator in
                WanderAvatar(
                    initials: collaborator.initials,
                    avatarURL: avatarURL(for: collaborator),
                    size: size,
                    color: collaborator.color
                )
            }
        }
        .frame(minWidth: collaborators.isEmpty ? 0 : size + CGFloat(max(0, min(collaborators.count, 3) - 1)) * (size - 8), alignment: .leading)
    }

    private func avatarURL(for collaborator: ListCollaboratorMock) -> String? {
        if let avatarURL = collaborator.avatarURL {
            return avatarURL
        }

        return store.profiles.first { profile in
            profile.id == collaborator.id || profile.handle == collaborator.handle
        }?.avatarURL
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
    var itemCountOverride: Int? = nil
    var sourceListID: String? = nil
    var ownerUserID: String = "you"
    var canManage: Bool = true
    var canAddPlaces: Bool = true

    var previewPlaces: [ListPlaceMock] { places }
    var itemCount: Int { itemCountOverride ?? places.count }
    var isOwnedByCurrentUser: Bool { ownerName == "You" }
    var isCollaborative: Bool { !collaborators.isEmpty }

    var mapRegion: MKCoordinateRegion {
        MapRegionFitter.region(fitting: places.map(\.coordinate)) ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    var subtitle: String {
        if ownerName == "You" {
            return "\(itemCount) places"
        }

        return "\(ownerName) - \(itemCount) places"
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

@MainActor
private extension PlaceListMock {
    init(list: LocalPlaceList, store: WanderStore) {
        let owner = store.profiles.first { $0.id == list.ownerUserID }
        self.id = list.id
        self.name = list.name
        self.description = list.description
        self.ownerName = list.ownerUserID == store.currentUser.id ? "You" : owner?.displayName ?? "Friend"
        self.isStealth = list.isStealth
        self.collaborators = store.collaborators(for: list).map(ListCollaboratorMock.init(profile:))
        self.places = store.visiblePlaces(in: list).map(ListPlaceMock.init(visiblePlace:))
        self.itemCountOverride = list.cachedItemCount
        self.sourceListID = list.id
        self.ownerUserID = list.ownerUserID
        self.canManage = store.canManage(list)
        self.canAddPlaces = store.canAddPlaces(to: list)
    }
}

private struct ListPlaceMock: Identifiable {
    let id: String
    let name: String
    let category: String
    let metadata: String
    let tint: Color
    let pinPosition: CGPoint
    let latitude: Double
    let longitude: Double
    let status: PlaceStatus
    let note: String?
    let placeID: String?
    let visiblePlaceID: String?

    init(
        id: String,
        name: String,
        category: String,
        metadata: String,
        tint: Color,
        pinPosition: CGPoint,
        latitude: Double? = nil,
        longitude: Double? = nil,
        status: PlaceStatus = .wannaGo,
        note: String? = nil,
        placeID: String? = nil,
        visiblePlaceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.metadata = metadata
        self.tint = tint
        self.pinPosition = pinPosition
        self.latitude = latitude ?? 34.075 + (84 - pinPosition.y) * 0.00042
        self.longitude = longitude ?? -118.285 + (pinPosition.x - 170) * 0.00055
        self.status = status
        self.note = note
        self.placeID = placeID
        self.visiblePlaceID = visiblePlaceID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var dedupeKey: String {
        "\(name.normalizedListLookupKey)|\(category.normalizedListLookupKey)"
    }

    init(visiblePlace: VisiblePlace) {
        let place = visiblePlace.place
        let metadataParts = [
            visiblePlace.userPlace.status.displayTitle,
            place.category,
            place.locality
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        self.init(
            id: "saved-\(visiblePlace.id)",
            name: place.canonicalName,
            category: place.category,
            metadata: metadataParts.joined(separator: " - "),
            tint: Self.tint(for: place.category),
            pinPosition: Self.previewPinPosition(for: place.id),
            latitude: place.latitude,
            longitude: place.longitude,
            status: visiblePlace.userPlace.status,
            note: visiblePlace.userPlace.note,
            placeID: place.id,
            visiblePlaceID: visiblePlace.id
        )
    }

    static func tint(for category: String) -> Color {
        switch WanderPlaceCategory.primary(for: nil, name: category) ?? category.lowercased() {
        case "coffee":
            return WanderTheme.terracottaTint.color
        case "restaurant":
            return WanderTheme.sunTint.color
        case "hike", "park":
            return WanderTheme.categorySage.color.opacity(0.36)
        case "bar":
            return WanderTheme.skyTint.color
        default:
            return WanderTheme.surfaceSand.color
        }
    }

    private static func previewPinPosition(for key: String) -> CGPoint {
        let seed = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return CGPoint(
            x: CGFloat(54 + seed % 232),
            y: CGFloat(46 + (seed / 5) % 88)
        )
    }
}

private struct ListCollaboratorMock: Identifiable {
    let id: String
    let name: String
    let initials: String
    let handle: String
    let avatarURL: String?
    let color: Color

    init(id: String, name: String, initials: String, handle: String? = nil, avatarURL: String? = nil, color: Color) {
        self.id = id
        self.name = name
        self.initials = initials
        self.handle = handle ?? name.lowercased()
        self.avatarURL = avatarURL
        self.color = color
    }

    init(profile: LocalProfile) {
        self.init(
            id: profile.id,
            name: profile.displayName,
            initials: profile.initials,
            handle: profile.handle,
            avatarURL: profile.avatarURL,
            color: Self.color(for: profile.handle)
        )
    }

    private static func color(for handle: String) -> Color {
        let palette = [
            WanderTheme.terracotta.color,
            WanderTheme.pinSocial.color,
            WanderTheme.avatarRyan.color,
            WanderTheme.avatarSofia.color,
            WanderTheme.categorySage.color,
            WanderTheme.categorySun.color
        ]
        let seed = handle.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[seed % palette.count]
    }
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

private extension PlaceSheetPlace {
    init(listPlace: ListPlaceMock) {
        let assignment = WanderPlaceCategory.assignment(forRawCategory: listPlace.category)
        self.id = listPlace.id
        self.name = listPlace.name
        self.category = assignment.legacyCategory
        self.primaryCategory = assignment.primaryCategory
        self.subcategory = assignment.subcategory
        self.categorySource = assignment.source
        self.categoryConfidence = assignment.confidence
        self.rawProviderType = assignment.rawProviderType
        self.address = nil
        self.locality = "Los Angeles"
        self.region = "CA"
        self.latitude = listPlace.latitude
        self.longitude = listPlace.longitude
        self.websiteURLString = nil
        self.phoneNumber = nil
        self.actionLinksJSON = nil
        self.compactSubtitleOverride = listPlace.metadata
        self.status = listPlace.status
        self.visibility = .followers
        self.note = listPlace.note
        self.noteOwnerID = "you"
        self.noteOwnerName = "You"
    }
}

private extension String {
    var normalizedListLookupKey: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
