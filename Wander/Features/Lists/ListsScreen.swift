@preconcurrency import MapKit
import SwiftUI
import UIKit

struct ListsScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    private let scenario: ListsScreenScenario
    private let scenarioList: PlaceListMock
    private let editorStartsWithFriendSearch: Bool
    private let editorStartsWithDeleteConfirmation: Bool
    @State private var selectedScopeID: String
    @State private var editorPresentation: ListEditorPresentation?
    @State private var selectedList: PlaceListMock?
    @State private var collaboratorList: PlaceListMock?
    @State private var mapList: PlaceListMock?
    @State private var selectedProfileID: String?
    @State private var pendingListInvite: PlaceListInvitePrompt?
    @State private var listInviteErrorMessage: String?
    @State private var deletedListIDs = Set<String>()

    init(scenario: ListsScreenScenario = .resolved()) {
        self.scenario = scenario
        let featuredList = PlaceListMock.fixture(for: scenario)
        self.scenarioList = featuredList
        self.editorStartsWithFriendSearch = scenario == .createCollaboratorsSearch
        self.editorStartsWithDeleteConfirmation = scenario == .editDeleteConfirm || scenario == .collabEditDeleteConfirm
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
        let initialMapList: PlaceListMock? = scenario.opensMapOnLaunch ? featuredList : nil

        _selectedScopeID = State(initialValue: scenario.initialScope.rawValue)
        _editorPresentation = State(initialValue: initialEditorPresentation)
        _collaboratorList = State(initialValue: initialCollaboratorList)
        _mapList = State(initialValue: initialMapList)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scenario.showsDetailRoot {
                    detailScreen(
                        for: scenarioList,
                        initialSelectedPlace: scenario == .placeDetail ? scenarioList.places.first : nil
                    )
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
            .sheet(item: $pendingListInvite) { prompt in
                PlaceListInviteSheet(prompt: prompt) {
                    await acceptListInvite(prompt)
                }
                    .presentationDetents([.medium])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
            .fullScreenCover(item: $mapList) { list in
                ListMapFullScreen(
                    list: list,
                    initialSelectedPlaceID: scenario.startsWithFocusedMapPlace ? list.mappedPlaces.first?.id : nil
                )
            }
            .fullScreenCover(isPresented: profileDestinationBinding) {
                if let selectedProfileID {
                    ProfileDetailView(profileID: selectedProfileID)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
            }
        }
        .task {
            await handleNotificationRoute(pushNotifications.navigationRequest)
        }
        .onChange(of: pushNotifications.navigationRequest) { _, request in
            Task {
                await handleNotificationRoute(request)
            }
        }
        .alert("Couldn’t open invitation", isPresented: listInviteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(listInviteErrorMessage ?? "This invitation is no longer available.")
        }
    }

    private func handleNotificationRoute(_ request: NotificationNavigationRequest?) async {
        guard let request else { return }

        switch request.destination {
        case .list(let listID):
            await openList(listID: listID, requestID: request.id)
        case .listInvite(let token):
            await resolveListInvite(token: token, requestID: request.id)
        default:
            return
        }
    }

    private func openList(listID: String, requestID: UUID? = nil) async {
        await store.refreshRemotePlaceLists(backend: backend)
        guard let list = store.visiblePlaceLists.first(where: {
            $0.id == listID || $0.localID == listID || $0.serverID == listID
        }) else { return }

        selectedList = PlaceListMock(list: list, store: store)
        selectedScopeID = list.ownerUserID == store.currentUser.id
            ? ListsScope.mine.rawValue
            : ListsScope.collabs.rawValue
        if let requestID {
            pushNotifications.consumeNavigationRequest(id: requestID)
        }
    }

    private func resolveListInvite(token: String, requestID: UUID) async {
        do {
            let resolution = try await backend.resolvePlaceListInvite(token: token)
            pushNotifications.consumeNavigationRequest(id: requestID)

            if resolution.viewerIsCollaborator == true,
               let listID = resolution.listID {
                await openList(listID: listID)
                return
            }

            guard resolution.status == .active, resolution.canAccept else {
                listInviteErrorMessage = resolution.unavailableMessage
                return
            }

            pendingListInvite = PlaceListInvitePrompt(
                token: token,
                resolution: resolution
            )
        } catch {
            pushNotifications.consumeNavigationRequest(id: requestID)
            listInviteErrorMessage = "This invitation could not be checked. Try opening the link again."
        }
    }

    private func acceptListInvite(_ prompt: PlaceListInvitePrompt) async -> Bool {
        do {
            let listID = try await backend.acceptPlaceListInvite(token: prompt.token)
            await store.refreshRemotePlaceLists(backend: backend)
            await openList(listID: listID)
            return true
        } catch {
            return false
        }
    }

    private var listInviteErrorBinding: Binding<Bool> {
        Binding(
            get: { listInviteErrorMessage != nil },
            set: { if !$0 { listInviteErrorMessage = nil } }
        )
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
            onOpenProfile: { profileID in
                guard profileID != store.currentUser.id else { return }
                selectedProfileID = profileID
            },
            initialSelectedPlace: initialSelectedPlace
        )
    }

    private var profileDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedProfileID != nil },
            set: { if !$0 { selectedProfileID = nil } }
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
        let renderedLists = activeLists

        return ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                header
                scopeSwitch

                if renderedLists.isEmpty {
                    emptyState
                } else {
                    listGrid(lists: renderedLists)
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
        WanderGlassHeader(
            title: "lists",
            subtitle: "save places into a plan you can actually use"
        ) {
            WanderGlassActionButton(
                systemImage: "plus",
                accessibilityLabel: "New list",
                accessibilityIdentifier: "lists.headerAdd"
            ) {
                editorPresentation = .create
            }
        }
    }

    private var scopeSwitch: some View {
        WanderGlassSegmentedSwitch(
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

    private func listGrid(lists: [PlaceListMock]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: WanderTheme.spacing3, alignment: .top),
                GridItem(.flexible(), spacing: WanderTheme.spacing3, alignment: .top)
            ],
            alignment: .leading,
            spacing: WanderTheme.spacing6
        ) {
            ForEach(lists) { list in
                Button {
                    selectedList = list
                } label: {
                    ListTile(list: list, showsCollaborators: selectedScope != .mine)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    list.isCollaborative
                        ? "Open \(list.name), collaborative list"
                        : "Open \(list.name)"
                )
            }
        }
    }

    private var activeLists: [PlaceListMock] {
        guard scenario != .empty else { return [] }

        let sourceLists = store.visiblePlaceLists(scope: selectedScope.placeListScope)
        let visiblePlacesByListID = store.visiblePlacesByListID(in: sourceLists)
        let preferredUserPhotosByPlaceID = store.firstVisitPhotosByPlaceID()
        let storeLists = sourceLists
            .map { list in
                let previewPlaces = ListPreviewPlaceSelector.distinctPrefix(
                    visiblePlacesByListID[list.id, default: []],
                    limit: 4
                )
                return PlaceListMock(
                    summary: list,
                    visiblePlaces: previewPlaces,
                    preferredUserPhotosByPlaceID: preferredUserPhotosByPlaceID,
                    store: store
                )
            }
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
    case mapEmpty
    case mapSingle
    case mapClustered
    case mapDispersed
    case mapPartial
    case mapUnresolved
    case mapUnmapped
    case mapError
    case mapOffline
    case mapLongNames
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
        case .detail, .edit, .collaboratorsSheet, .mapPreview, .mapSelectedPlace,
             .mapEmpty, .mapSingle, .mapClustered, .mapDispersed, .mapPartial,
             .mapUnresolved, .mapUnmapped, .mapError, .mapOffline, .mapLongNames,
             .placeDetail:
            true
        default:
            false
        }
    }

    var opensMapOnLaunch: Bool {
        switch self {
        case .mapPreview, .mapSelectedPlace, .mapEmpty, .mapSingle, .mapClustered,
             .mapDispersed, .mapPartial, .mapUnresolved, .mapError, .mapOffline,
             .mapUnmapped, .mapLongNames:
            true
        default:
            false
        }
    }

    var startsWithFocusedMapPlace: Bool {
        self == .mapSelectedPlace
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
                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing1) {
                    Text(list.name)
                        .font(WanderTypography.editorialNamedContent)
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

    var body: some View {
        mosaicContent
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.75), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mosaicContent: some View {
        switch min(list.previewPlaces.count, 4) {
        case 0:
            emptyCover
        case 1:
            mosaicTile(place: list.previewPlaces[0])
        case 2:
            HStack(spacing: 2) {
                mosaicTile(place: list.previewPlaces[0])
                mosaicTile(place: list.previewPlaces[1])
            }
        case 3:
            HStack(spacing: 2) {
                mosaicTile(place: list.previewPlaces[0])

                VStack(spacing: 2) {
                    mosaicTile(place: list.previewPlaces[1])
                    mosaicTile(place: list.previewPlaces[2])
                }
            }
        default:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    mosaicTile(place: list.previewPlaces[0])
                    mosaicTile(place: list.previewPlaces[1])
                }

                HStack(spacing: 2) {
                    mosaicTile(place: list.previewPlaces[2])
                    mosaicTile(place: list.previewPlaces[3])
                }
            }
        }
    }

    private var emptyCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .fill(WanderTheme.surfaceSand.color)

            Image(systemName: "bookmark.fill")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color.opacity(0.34))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func mosaicTile(place: ListPlaceMock) -> some View {
        ListPlacePhotoMedia(
            place: place,
            cornerRadius: WanderTheme.radiusSmall,
            fallbackEmojiSize: 22,
            googleAttributionFontSize: 8,
            eligibleUserIDs: list.photoContributorUserIDs
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct ListDetailScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.dismiss) private var dismiss
    let list: PlaceListMock
    var onEdit: (PlaceListMock) -> Void
    var onCollaborators: (PlaceListMock) -> Void
    var onOpenMap: (PlaceListMock) -> Void
    var onListChanged: (String) -> Void
    var onOpenProfile: (String) -> Void
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
        onOpenProfile: @escaping (String) -> Void = { _ in },
        initialSelectedPlace: ListPlaceMock? = nil
    ) {
        self.list = list
        self.onEdit = onEdit
        self.onCollaborators = onCollaborators
        self.onOpenMap = onOpenMap
        self.onListChanged = onListChanged
        self.onOpenProfile = onOpenProfile
        _selectedPlace = State(initialValue: initialSelectedPlace)
    }

    var body: some View {
        let renderedList = displayList

        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                detailHeader(for: renderedList)
                mapPreview(for: renderedList)
                placeRows(for: renderedList)
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
                if let listShareContent {
                    WanderShareButton(content: listShareContent) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .black))
                            .frame(width: 34, height: 34)
                            .background(WanderTheme.surfaceSand.color)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Share list")
                }

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
                        onEdit(renderedList)
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
        .task(id: list.sourceListID ?? list.id) {
            _ = await store.syncPendingPlaceLists(backend: backend)
            if let sourceList {
                await store.refreshRemotePlaceList(sourceList, backend: backend)
            }
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
        .onChange(of: sourceList?.id) { _, visibleListID in
            if list.sourceListID != nil && visibleListID == nil {
                dismiss()
            }
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

    private func detailHeader(for renderedList: PlaceListMock) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Text(renderedList.name)
                            .font(WanderTypography.editorialMasthead)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        if renderedList.isStealth {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }

                    Text(renderedList.description)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: WanderTheme.spacing2) {
                if let owner = listOwnerProfile(for: renderedList) {
                    Button {
                        onOpenProfile(owner.id)
                    } label: {
                        HStack(spacing: WanderTheme.spacing2) {
                            WanderAvatar(
                                initials: owner.initials,
                                avatarURL: owner.avatarURL,
                                size: 30,
                                color: WanderTheme.pinSocial.color
                            )
                            Text(owner.displayName)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(owner.displayName)'s profile")
                }
                FacePileView(
                    collaborators: renderedList.collaborators,
                    size: 30,
                    onSelect: onOpenProfile
                )
                Text(renderedList.collaboratorSummary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                if canManageList {
                    Button {
                        onCollaborators(renderedList)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(WanderTheme.terracottaTint.color)
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Manage collaborators")
                    .disabled(!canManageCollaborators(for: renderedList))
                    .opacity(canManageCollaborators(for: renderedList) ? 1 : 0.48)
                    .accessibilityHint(collaboratorAccessibilityHint(for: renderedList))
                }
                Spacer()
                Text("\(renderedList.itemCount) places")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }
            .padding(.top, WanderTheme.spacing1)
        }
    }

    private func mapPreview(for renderedList: PlaceListMock) -> some View {
        ListMapPreview(
            list: renderedList,
            height: 168,
            label: "View map"
        ) {
            onOpenMap(renderedList)
        }
    }

    @ViewBuilder
    private func placeRows(for renderedList: PlaceListMock) -> some View {
        let outlineCatalog = savedPlaceOutlineCatalog
        let visiblePlaces = visiblePlaces(in: renderedList)

        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("places")
                .font(.system(size: 18, weight: .black))

            if visiblePlaces.isEmpty {
                Text(renderedList.itemCount > 0 ? "Loading places in this list." : "No places in this list yet.")
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
                        outlines: savedPlaceOutlines(
                            for: place,
                            outlineCatalog: outlineCatalog
                        ),
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
                outlineCatalog: savedPlaceOutlineCatalog,
                currentUserID: store.currentUser.id,
                onAdd: { suggestion in
                    Task {
                        await addSuggestion(suggestion)
                    }
                },
                onOpen: { suggestion in
                    selectedPlace = ListPlaceMock(
                        visiblePlace: suggestion.visiblePlace,
                        currentUserID: store.currentUser.id
                    )
                }
            )
        }
    }

    private func visiblePlaces(in renderedList: PlaceListMock) -> [ListPlaceMock] {
        renderedList.places.filter { !removedPlaceIDs.contains($0.id) }
    }

    private var sourceList: LocalPlaceList? {
        guard let sourceListID = list.sourceListID else { return nil }
        return store.visiblePlaceLists.first {
            $0.id == sourceListID || $0.localID == sourceListID || $0.serverID == sourceListID
        }
    }

    private var displayList: PlaceListMock {
        sourceList.map { PlaceListMock(list: $0, store: store) } ?? list
    }

    private var savedPlaceOutlineCatalog: [String: [MapPinOutline]] {
        MapPinOutlineBuilder.outlineCatalog(
            for: store.visiblePlaces(),
            currentUserID: store.currentUser.id
        )
    }

    private func listOwnerProfile(for renderedList: PlaceListMock) -> LocalProfile? {
        guard !renderedList.isOwnedByCurrentUser else { return nil }
        return store.profiles.first { profile in
            profile.id == renderedList.ownerUserID
                || profile.handle.caseInsensitiveCompare(renderedList.ownerName) == .orderedSame
                || profile.displayName.caseInsensitiveCompare(renderedList.ownerName) == .orderedSame
        }
    }

    private var canManageList: Bool {
        sourceList.map(store.canManage) ?? list.canManage
    }

    private var canAddPlaces: Bool {
        sourceList.map(store.canAddPlaces(to:)) ?? list.canAddPlaces
    }

    private var listShareContent: WanderShareContent? {
        WanderShareContent.list(
            serverID: sourceList?.serverID ?? list.sourceListID,
            name: displayList.name
        )
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

    private func canManageCollaborators(for renderedList: PlaceListMock) -> Bool {
        guard renderedList.isOwnedByCurrentUser else { return false }
        return !store.isPrivateProfile || renderedList.isCollaborative
    }

    private func collaboratorAccessibilityHint(for renderedList: PlaceListMock) -> String {
        if !renderedList.isOwnedByCurrentUser {
            return "Only the list owner can manage collaborators"
        }

        guard store.isPrivateProfile else { return "" }

        if !renderedList.isCollaborative {
            return "New collaborative lists are unavailable while Private Profile is on"
        }

        return "Add or remove friends on this existing collaborative list"
    }
}

private struct ListSuggestionsSection: View {
    let suggestions: [ListPlaceSuggestion]
    let isLoading: Bool
    let outlineCatalog: [String: [MapPinOutline]]
    let currentUserID: String
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
                            outlines: savedPlaceOutlines(
                                for: suggestion.visiblePlace,
                                outlineCatalog: outlineCatalog,
                                currentUserID: currentUserID
                            ),
                            currentUserID: currentUserID,
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
        let outlineCatalog = savedPlaceOutlineCatalog

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
                            outlines: savedPlaceOutlines(
                                for: suggestion.visiblePlace,
                                outlineCatalog: outlineCatalog,
                                currentUserID: store.currentUser.id
                            ),
                            currentUserID: store.currentUser.id,
                            onOpen: {
                                selectedPlace = ListPlaceMock(
                                    visiblePlace: suggestion.visiblePlace,
                                    currentUserID: store.currentUser.id
                                )
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

    private var savedPlaceOutlineCatalog: [String: [MapPinOutline]] {
        MapPinOutlineBuilder.outlineCatalog(
            for: store.visiblePlaces(),
            currentUserID: store.currentUser.id
        )
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
    let outlines: [MapPinOutline]
    let currentUserID: String
    let onOpen: () -> Void
    let onAdd: () -> Void

    private var place: ListPlaceMock {
        ListPlaceMock(
            visiblePlace: visiblePlace,
            currentUserID: currentUserID
        )
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpen) {
                HStack(spacing: WanderTheme.spacing3) {
                    ListSavedPlaceIcon(
                        emoji: place.emoji,
                        outlines: outlines,
                        frameSize: 48,
                        diameter: 38,
                        emojiSize: 16
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(WanderTypography.editorialSmallNamedContent)
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
                    WanderCategoryEmoji(emoji: candidate.categoryEmoji, size: 18)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(WanderTypography.editorialSmallNamedContent)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let list: PlaceListMock
    let height: CGFloat
    let label: String
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Map(
                    position: .constant(.region(list.mapRegion)),
                    interactionModes: []
                ) {
                    ForEach(previewClusters) { cluster in
                        Annotation("", coordinate: cluster.coordinate) {
                            if cluster.isCluster {
                                ListMapClusterMarker(
                                    count: cluster.memberIDs.count,
                                    outlines: outlines(for: cluster),
                                    isSelected: false,
                                    compact: true
                                )
                                .accessibilityHidden(true)
                            } else if let place = place(for: cluster) {
                                ListMapMarker(
                                    place: place,
                                    outlines: MapPinOutlineBuilder.outlines(for: place.saveStates),
                                    isSelected: false,
                                    compact: true
                                )
                                .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))

                if list.mappedPlaces.isEmpty {
                    VStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: list.mapAvailability == .loading ? "arrow.triangle.2.circlepath" : "map")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                        Text(previewStateTitle)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text(previewStateMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .multilineTextAlignment(.center)
                    }
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .padding(.horizontal, WanderTheme.spacing4)
                }

                VStack(spacing: 0) {
                    Button(action: onOpen) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(list.totalItemCount == 0)
                    .accessibilityHidden(true)

                    // Keep MapKit's attribution visible and independently
                    // tappable while the rest of the map preview opens the map.
                    Color.clear
                        .frame(height: 32)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? max(height, 196) : height)

            Button(action: onOpen) {
                HStack(spacing: WanderTheme.spacing2) {
                    Label(label, systemImage: "map.fill")
                        .font(.subheadline.weight(.black))
                    Spacer(minLength: WanderTheme.spacing2)
                    Text(list.mapContentState.countLabel)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(
                    list.totalItemCount == 0
                        ? WanderTheme.textMuted.color
                        : WanderTheme.textInk.color
                )
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WanderTheme.surfaceRaised.color)
            }
            .buttonStyle(.plain)
            .disabled(list.totalItemCount == 0)
            .accessibilityLabel(
                list.totalItemCount == 0
                    ? "\(list.name), no places to map yet"
                    : "View map for \(list.name), \(list.mapContentState.countLabel)"
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var previewClusters: [ListMapCluster] {
        ListMapClusterer.clusters(
            for: list.mappedPlaces.map {
                ListMapCoordinate(id: $0.id, coordinate: $0.coordinate)
            },
            in: list.mapRegion,
            viewportSize: CGSize(width: 340, height: height),
            minimumScreenDistance: 40
        )
    }

    private func place(for cluster: ListMapCluster) -> ListPlaceMock? {
        guard let placeID = cluster.memberIDs.first else { return nil }
        return list.places.first { $0.id == placeID }
    }

    private func outlines(for cluster: ListMapCluster) -> [MapPinOutline] {
        let memberIDs = Set(cluster.memberIDs)
        return MapPinOutlineBuilder.outlines(
            for: list.places
                .filter { memberIDs.contains($0.id) }
                .flatMap(\.saveStates)
        )
    }

    private var previewStateTitle: String {
        switch list.mapAvailability {
        case .loading:
            "Loading places…"
        case .error:
            "Map places unavailable"
        case .offline:
            "You’re offline"
        case .ready:
            list.totalItemCount == 0 ? "No places to map yet" : "Places aren’t mapped yet"
        }
    }

    private var previewStateMessage: String {
        switch list.mapAvailability {
        case .loading:
            "This map will fill in as places arrive."
        case .error:
            "The list is still safe. Try again from list detail."
        case .offline:
            "Reconnect to load places that aren’t saved here."
        case .ready:
            list.totalItemCount == 0 ? "Add a place to start this map." : "The list still shows every resolved place below."
        }
    }
}

private struct ListSavedPlaceIcon: View {
    let emoji: String
    let outlines: [MapPinOutline]
    let frameSize: CGFloat
    let diameter: CGFloat
    let emojiSize: CGFloat

    var body: some View {
        WanderCategoryEmoji(emoji: emoji, size: emojiSize)
            .frame(width: diameter, height: diameter)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(outlineLayer)
            .frame(width: frameSize, height: frameSize)
    }

    private var outlineLayer: some View {
        ForEach(Array(outlines.indices), id: \.self) { index in
            MapPinOutlineStroke(
                outline: outlines[index],
                lineWidth: outlines.count > 1 ? 2.5 : 3
            )
            .padding(outlinePadding(for: index))
        }
    }

    private func outlinePadding(for index: Int) -> CGFloat {
        guard outlines.count > 1 else { return 0 }
        return index == 0 ? 0 : -5
    }
}

private struct ListPlaceRow: View {
    let place: ListPlaceMock
    let outlines: [MapPinOutline]
    var canRemove: Bool = true
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpen) {
                HStack(spacing: WanderTheme.spacing3) {
                    ListSavedPlaceIcon(
                        emoji: place.emoji,
                        outlines: outlines,
                        frameSize: 56,
                        diameter: 40,
                        emojiSize: 17
                    )

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(place.name)
                            .font(WanderTypography.editorialNamedContent)
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

private struct PlaceListInvitePrompt: Identifiable {
    let token: String
    let resolution: PlaceListInviteResolution

    var id: String { token }
}

private extension PlaceListInviteResolution {
    var unavailableMessage: String {
        switch status {
        case .expired:
            "This invitation has expired. Ask the list owner for a new link."
        case .revoked:
            "The list owner revoked this invitation."
        case .accepted:
            "This single-use invitation has already been accepted."
        case .unavailable:
            "This list is no longer available for collaboration."
        case .invalid:
            "This invitation link is invalid."
        case .active:
            viewerIsOwner == true
                ? "You already own this list."
                : "This invitation cannot be accepted by this account."
        }
    }
}

private struct PlaceListInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: PlaceListInvitePrompt
    let onAccept: @MainActor () async -> Bool
    @State private var isAccepting = false
    @State private var acceptanceErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 52, height: 52)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("build this list together")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(prompt.resolution.listName ?? "Shared list")
                        .font(WanderTypography.editorialTitle)
                    if let owner = prompt.resolution.ownerDisplayName {
                        Text("Invited by \(owner)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    if let description = prompt.resolution.listDescription,
                       !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }

                Button {
                    isAccepting = true
                    Task {
                        if await onAccept() {
                            dismiss()
                        } else {
                            acceptanceErrorMessage = "The invitation could not be accepted. It may have expired, been revoked, or already been used."
                        }
                        isAccepting = false
                    }
                } label: {
                    HStack {
                        if isAccepting {
                            ProgressView()
                                .tint(WanderTheme.textOnAction.color)
                        }
                        Text(isAccepting ? "joining..." : "accept invitation")
                            .font(.system(size: 15, weight: .black))
                    }
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
                .buttonStyle(.borderedProminent)
                .tint(WanderTheme.terracotta.color)
                .disabled(isAccepting)

                Text("You’ll become a collaborator only after accepting. The link is single-use and can expire or be revoked.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Spacer()
            }
            .padding(WanderTheme.spacing4)
            .wanderScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("not now") { dismiss() }
                        .font(.system(size: 14, weight: .black))
                }
            }
            .alert("Couldn’t join list", isPresented: acceptanceErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(acceptanceErrorMessage ?? "Try opening the invitation again.")
            }
        }
    }

    private var acceptanceErrorBinding: Binding<Bool> {
        Binding(
            get: { acceptanceErrorMessage != nil },
            set: { if !$0 { acceptanceErrorMessage = nil } }
        )
    }
}

private struct ListSharePresentation: Identifiable {
    let id = UUID()
    let content: WanderShareContent
}

private struct CollaboratorInviteSheet: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.dismiss) private var dismiss
    let list: PlaceListMock
    let onSave: ([ListCollaboratorMock]) -> Void
    @State private var selectedCollaborators: [ListCollaboratorMock]
    @State private var sharePresentation: ListSharePresentation?
    @State private var isCreatingInviteLink = false
    @State private var inviteLinkErrorMessage: String?

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
                        FriendCollaboratorSearchContent(
                            selectedCollaborators: $selectedCollaborators,
                            listName: list.name
                        )
                        inviteByLinkSection
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
            .sheet(item: $sharePresentation) { presentation in
                WanderShareSheet(content: presentation.content)
            }
            .alert("Couldn’t create invitation", isPresented: inviteLinkErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(inviteLinkErrorMessage ?? "Try again in a moment.")
            }
        }
    }

    private var canInviteWhilePrivate: Bool {
        list.isOwnedByCurrentUser && list.isCollaborative
    }

    private var canCreateInviteLink: Bool {
        guard list.isOwnedByCurrentUser,
              !store.isPrivateProfile,
              let listID = list.sourceListID
        else { return false }
        return UUID(uuidString: listID) != nil
    }

    private var inviteByLinkSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("invite by link")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            Button {
                createInviteLink()
            } label: {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "link")
                        .font(.system(size: 17, weight: .black))
                        .frame(width: 42, height: 42)
                        .background(WanderTheme.terracottaTint.color)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isCreatingInviteLink ? "creating link..." : "share collaborator invite")
                            .font(.system(size: 15, weight: .black))
                        Text("Single-use · expires in 7 days")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                    if isCreatingInviteLink {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }
            .buttonStyle(.plain)
            .disabled(!canCreateInviteLink || isCreatingInviteLink)
            .opacity(canCreateInviteLink ? 1 : 0.48)
        }
    }

    private func createInviteLink() {
        guard let listID = list.sourceListID, canCreateInviteLink else { return }
        isCreatingInviteLink = true
        inviteLinkErrorMessage = nil

        Task {
            defer { isCreatingInviteLink = false }
            do {
                let invite = try await backend.createPlaceListInvite(listID: listID)
                guard let content = WanderShareContent.listInvite(
                    token: invite.token,
                    name: list.name
                ) else {
                    inviteLinkErrorMessage = "The invitation was created, but its share link was invalid."
                    return
                }
                sharePresentation = ListSharePresentation(content: content)
            } catch {
                inviteLinkErrorMessage = "The invitation link could not be created. Check your connection and try again."
            }
        }
    }

    private var inviteLinkErrorBinding: Binding<Bool> {
        Binding(
            get: { inviteLinkErrorMessage != nil },
            set: { if !$0 { inviteLinkErrorMessage = nil } }
        )
    }
}

private struct FriendCollaboratorSearchSheet: View {
    @EnvironmentObject private var store: WanderStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCollaborators: [ListCollaboratorMock]
    let allowsInvitesWhilePrivate: Bool
    let listName: String?

    init(
        selectedCollaborators: Binding<[ListCollaboratorMock]>,
        allowsInvitesWhilePrivate: Bool = false,
        listName: String? = nil
    ) {
        _selectedCollaborators = selectedCollaborators
        self.allowsInvitesWhilePrivate = allowsInvitesWhilePrivate
        self.listName = listName
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
                        FriendCollaboratorSearchContent(
                            selectedCollaborators: $selectedCollaborators,
                            listName: listName
                        )
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
    let listName: String?
    @State private var query = ""
    @State private var isPresentingContactInvites = false

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

            InviteEntryPointButton(surface: .listCollaborator(listName: listName)) {
                isPresentingContactInvites = true
            }

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
        .sheet(isPresented: $isPresentingContactInvites) {
            ContactInviteSheet(
                surface: .listCollaborator(listName: listName),
                contactProvider: store.contactProvider
            )
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

private struct ListMapHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ListMapBottomHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ListMapBottomTopPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ListMapFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let list: PlaceListMock
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var interactionState: ListMapInteractionState
    @State private var profilePlace: ListPlaceMock?
    @State private var headerOverlayHeight: CGFloat = 0
    @State private var bottomOverlayHeight: CGFloat = 0
    @State private var mapViewportHeight: CGFloat = 0

    init(list: PlaceListMock, initialSelectedPlaceID: String? = nil) {
        self.list = list
        _position = State(initialValue: .region(list.mapRegion))
        _visibleRegion = State(initialValue: list.mapRegion)
        _interactionState = State(
            initialValue: ListMapInteractionState(
                focusedPlaceID: initialSelectedPlaceID.flatMap { selectedID in
                    list.places.first { $0.id == selectedID }?.id
                }
            )
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let mapViewportSize = CGSize(
                    width: proxy.size.width,
                    height: max(mapViewportHeight > 0 ? mapViewportHeight : proxy.size.height, 1)
                )
                let clusters = clusters(in: mapViewportSize)

                ZStack(alignment: .bottom) {
                    Map(position: $position) {
                        ForEach(clusters) { cluster in
                            Annotation("", coordinate: cluster.coordinate) {
                                if cluster.isCluster {
                                    Button {
                                        zoom(to: cluster)
                                    } label: {
                                        ListMapClusterMarker(
                                            count: cluster.memberIDs.count,
                                            outlines: outlines(for: cluster),
                                            isSelected: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "\(cluster.memberIDs.count) places close together"
                                    )
                                    .accessibilityHint("Zooms in")
                                } else if let place = place(for: cluster) {
                                    Button {
                                        focus(place)
                                    } label: {
                                        ListMapMarker(
                                            place: place,
                                            outlines: MapPinOutlineBuilder.outlines(for: place.saveStates),
                                            isSelected: interactionState.focusedPlaceID == place.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(place.accessibilitySummary)
                                    .accessibilityHint("Shows this place in the list rail")
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                    .onMapCameraChange(frequency: .onEnd) { context in
                        visibleRegion = context.region
                    }
                    .padding(.bottom, bottomOverlayHeight)
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        mapHeader
                            .padding(.horizontal, WanderTheme.spacing3)
                            .padding(.top, WanderTheme.spacing2)
                            .background {
                                GeometryReader { headerProxy in
                                    Color.clear.preference(
                                        key: ListMapHeaderHeightPreferenceKey.self,
                                        value: headerProxy.frame(in: .global).maxY
                                    )
                                }
                            }
                        Spacer(minLength: 0)
                        mapBottomOverlay(bottomInset: proxy.safeAreaInsets.bottom)
                            .background {
                                GeometryReader { bottomProxy in
                                    Color.clear.preference(
                                        key: ListMapBottomHeightPreferenceKey.self,
                                        value: bottomProxy.size.height
                                    )
                                    .preference(
                                        key: ListMapBottomTopPreferenceKey.self,
                                        value: bottomProxy.frame(in: .global).minY
                                    )
                                }
                            }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .onPreferenceChange(ListMapHeaderHeightPreferenceKey.self) { height in
                    headerOverlayHeight = height
                    applyInitialViewportFit(
                        visibleMapHeight: mapViewportHeight,
                        headerHeight: height
                    )
                }
                .onPreferenceChange(ListMapBottomHeightPreferenceKey.self) { height in
                    bottomOverlayHeight = height
                    applyInitialViewportFit(
                        visibleMapHeight: mapViewportHeight,
                        bottomHeight: height
                    )
                }
                .onPreferenceChange(ListMapBottomTopPreferenceKey.self) { minY in
                    mapViewportHeight = minY
                    applyInitialViewportFit(visibleMapHeight: minY)
                }
            }
            .background(WanderTheme.canvasWarm.color)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: profilePlaceDestinationBinding) {
                profilePlaceDestination
            }
        }
    }

    private var mapHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.97))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                    .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close list map")

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(WanderTypography.editorialNamedContent)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: WanderTheme.spacing1) {
                    if list.mapAvailability == .loading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(WanderTheme.terracotta.color)
                    }
                    Text(list.mapContentState.countLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, 9)
            .frame(
                maxWidth: dynamicTypeSize.isAccessibilitySize ? 300 : 276,
                minHeight: 44,
                alignment: .leading
            )
            .background(WanderTheme.surfaceRaised.color.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 12, x: 0, y: 5)

            Spacer(minLength: 0)
        }
    }

    private var profilePlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { profilePlace != nil },
            set: { isPresented in
                if !isPresented {
                    profilePlace = nil
                    interactionState.openPlaceID = nil
                }
            }
        )
    }

    private var focusedPlaceIDBinding: Binding<String?> {
        Binding(
            get: { interactionState.focusedPlaceID },
            set: { placeID in
                interactionState.handle(
                    .focus(placeID),
                    validPlaceIDs: Set(list.places.map(\.id))
                )
            }
        )
    }

    private func clusters(in viewportSize: CGSize) -> [ListMapCluster] {
        ListMapClusterer.clusters(
            for: list.mappedPlaces.map {
                ListMapCoordinate(id: $0.id, coordinate: $0.coordinate)
            },
            in: visibleRegion,
            viewportSize: viewportSize
        )
    }

    private func place(for cluster: ListMapCluster) -> ListPlaceMock? {
        guard let placeID = cluster.memberIDs.first else { return nil }
        return list.places.first { $0.id == placeID }
    }

    private func outlines(for cluster: ListMapCluster) -> [MapPinOutline] {
        let memberIDs = Set(cluster.memberIDs)
        return MapPinOutlineBuilder.outlines(
            for: list.places
                .filter { memberIDs.contains($0.id) }
                .flatMap(\.saveStates)
        )
    }

    private func focus(_ place: ListPlaceMock) {
        guard interactionState.focusedPlaceID != place.id else { return }
        if reduceMotion {
            interactionState.handle(.focus(place.id), validPlaceIDs: validPlaceIDs)
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                interactionState.handle(.focus(place.id), validPlaceIDs: validPlaceIDs)
            }
        }
    }

    private func open(_ place: ListPlaceMock) {
        interactionState.handle(.open(place.id), validPlaceIDs: validPlaceIDs)
        guard interactionState.openPlaceID == place.id else { return }
        profilePlace = place
    }

    private var validPlaceIDs: Set<String> {
        Set(list.places.map(\.id))
    }

    @ViewBuilder
    private func mapBottomOverlay(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            if list.mapAvailability == .offline && !list.places.isEmpty {
                ListMapAvailabilityNotice(
                    systemImage: "wifi.slash",
                    message: "Offline · showing saved places"
                )
                .padding(.bottom, WanderTheme.spacing2)
            } else if list.mapAvailability == .error && !list.places.isEmpty {
                ListMapAvailabilityNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    message: "Couldn’t refresh · showing saved places"
                )
                .padding(.bottom, WanderTheme.spacing2)
            } else if list.mappedPlaces.isEmpty && !list.places.isEmpty {
                ListMapAvailabilityNotice(
                    systemImage: "mappin.slash",
                    message: "No map location · browse below"
                )
                .padding(.bottom, WanderTheme.spacing2)
            }

            if list.places.isEmpty {
                ListMapStatePanel(list: list, bottomInset: bottomInset)
            } else {
                ListMapPlaceRail(
                    list: list,
                    focusedPlaceID: focusedPlaceIDBinding,
                    bottomInset: bottomInset
                ) { place in
                    open(place)
                }
            }
        }
    }

    private func applyInitialViewportFit(
        visibleMapHeight: CGFloat,
        headerHeight: CGFloat? = nil,
        bottomHeight: CGFloat? = nil
    ) {
        let resolvedHeaderHeight = headerHeight ?? headerOverlayHeight
        let resolvedBottomHeight = bottomHeight ?? bottomOverlayHeight
        guard visibleMapHeight > resolvedHeaderHeight,
              resolvedHeaderHeight > 0,
              resolvedBottomHeight > 0
        else { return }

        let region = viewportAdjustedRegion(
            list.mapRegion,
            viewportHeight: visibleMapHeight,
            headerHeight: resolvedHeaderHeight,
            bottomHeight: 0
        )
        mapViewportHeight = visibleMapHeight
        position = .region(region)
        visibleRegion = region
    }

    private func zoom(to cluster: ListMapCluster) {
        let memberIDs = Set(cluster.memberIDs)
        let coordinates = list.mappedPlaces
            .filter { memberIDs.contains($0.id) }
            .map(\.coordinate)
        let minimumSpan = max(
            min(visibleRegion.span.latitudeDelta, visibleRegion.span.longitudeDelta) * 0.32,
            0.0015
        )
        guard let region = MapRegionFitter.region(
            fitting: coordinates,
            minimumSpan: minimumSpan,
            paddingMultiplier: 1.75
        ) else { return }
        let adjustedRegion = viewportAdjustedRegion(
            region,
            viewportHeight: mapViewportHeight,
            headerHeight: headerOverlayHeight,
            bottomHeight: 0
        )

        if reduceMotion {
            position = .region(adjustedRegion)
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                position = .region(adjustedRegion)
            }
        }
    }

    private func viewportAdjustedRegion(
        _ region: MKCoordinateRegion,
        viewportHeight: CGFloat,
        headerHeight: CGFloat,
        bottomHeight: CGFloat
    ) -> MKCoordinateRegion {
        guard viewportHeight > 0,
              headerHeight >= 0,
              bottomHeight >= 0,
              headerHeight + bottomHeight > 0
        else {
            return region
        }
        return MapRegionFitter.region(
            region,
            accountingForViewportHeight: viewportHeight,
            obscuredTopHeight: headerHeight,
            obscuredBottomHeight: bottomHeight
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let place: ListPlaceMock
    let outlines: [MapPinOutline]
    let isSelected: Bool
    var compact = false

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(WanderTheme.surfaceRaised.color)
                    .overlay(
                        Circle()
                            .stroke(WanderTheme.textInk.color, lineWidth: 2)
                    )
                    .frame(width: compact ? 40 : 50, height: compact ? 40 : 50)
            }

            ListSavedPlaceIcon(
                emoji: place.emoji,
                outlines: outlines,
                frameSize: compact ? 34 : (isSelected ? 44 : 40),
                diameter: compact ? 34 : (isSelected ? 44 : 40),
                emojiSize: compact ? 14 : (isSelected ? 17 : 16)
            )
        }
            .frame(width: compact ? 40 : 52, height: compact ? 40 : 52)
            .contentShape(Circle())
            .shadow(color: WanderTheme.textInk.color.opacity(0.20), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82),
                value: isSelected
            )
            .accessibilityLabel("\(place.name) on list map")
    }
}

private struct ListMapClusterMarker: View {
    let count: Int
    let outlines: [MapPinOutline]
    let isSelected: Bool
    var compact = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: compact ? 12 : 14, weight: .black, design: .rounded))
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay {
                ForEach(Array(outlines.indices), id: \.self) { index in
                    MapPinOutlineStroke(
                        outline: outlines[index],
                        lineWidth: outlines.count > 1 ? 2.5 : 3
                    )
                    .padding(outlines.count > 1 && index > 0 ? -5 : 0)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(WanderTheme.textInk.color, lineWidth: 2)
                        .padding(-5)
                }
            }
            .frame(width: compact ? 40 : 52, height: compact ? 40 : 52)
            .shadow(color: WanderTheme.textInk.color.opacity(0.20), radius: 7, x: 0, y: 2)
    }
}

private struct ListMapPlaceRail: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var railViewportHeight: CGFloat = 102
    let list: PlaceListMock
    @Binding var focusedPlaceID: String?
    let bottomInset: CGFloat
    let onSelect: (ListPlaceMock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text(list.mapContentState.countLabel)
                    .font(.headline.weight(.black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Spacer()
                if list.places.count > 1 {
                    Text("Swipe to browse")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .padding(.horizontal, WanderTheme.spacing3)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: WanderTheme.spacing3) {
                    ForEach(list.places) { place in
                        ListMapPlaceTile(
                            place: place,
                            outlines: MapPinOutlineBuilder.outlines(for: place.saveStates),
                            isFocused: focusedPlaceID == place.id
                        ) {
                            onSelect(place)
                        }
                        .id(place.id)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedPlaceID, anchor: .center)
            .frame(height: max(102, railViewportHeight))
        }
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, max(bottomInset, WanderTheme.spacing2))
        .background(WanderTheme.surfaceRaised.color.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
        .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 18, x: 0, y: -5)
        .onAppear {
            if focusedPlaceID == nil {
                focusedPlaceID = list.places.first?.id
            }
        }
    }
}

private struct ListMapPlaceTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let place: ListPlaceMock
    let outlines: [MapPinOutline]
    let isFocused: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                ListMapCompactMedia(
                    place: place,
                    outlines: outlines
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(place.name)
                        .font(WanderTypography.editorialNamedContent)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    Text(place.detailsLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text(place.contextLine)
                        .font(.caption.weight(.black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(width: 20, height: 44)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        isFocused ? WanderTheme.textInk.color : WanderTheme.borderHairline.color,
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .shadow(
                color: WanderTheme.textInk.color.opacity(isFocused ? 0.16 : 0.08),
                radius: isFocused ? 10 : 5,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .containerRelativeFrame(.horizontal) { length, _ in
            if dynamicTypeSize.isAccessibilitySize {
                min(354, max(300, length - 28))
            } else {
                min(306, max(248, length - 52))
            }
        }
        .accessibilityLabel(place.accessibilitySummary)
        .accessibilityHint("Opens place")
    }
}

private struct ListMapCompactMedia: View {
    let place: ListPlaceMock
    let outlines: [MapPinOutline]

    var body: some View {
        ListPlacePhotoMedia(
            place: place,
            cornerRadius: WanderTheme.radiusMedium,
            fallbackEmojiSize: 22,
            googleAttributionFontSize: 7
        )
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            ListSavedPlaceIcon(
                emoji: place.emoji,
                outlines: outlines,
                frameSize: 25,
                diameter: 25,
                emojiSize: 10
            )
            .offset(x: 4, y: 4)
        }
        .accessibilityHidden(true)
    }
}

private struct ListPlacePhotoMedia: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.displayScale) private var displayScale
    let place: ListPlaceMock
    let cornerRadius: CGFloat
    let fallbackEmojiSize: CGFloat
    let googleAttributionFontSize: CGFloat
    var eligibleUserIDs: [String]? = nil
    @State private var resolvedPhoto: ListPlaceResolvedPhoto?
    @State private var resolvedPhotoKey: String?

    var body: some View {
        GeometryReader { proxy in
            let targetPixelSize = max(
                1,
                Int(ceil(max(proxy.size.width, proxy.size.height) * displayScale))
            )
            let resolutionKey = photoResolutionKey

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(place.tint)

                WanderCategoryEmoji(emoji: place.emoji, size: fallbackEmojiSize)

                if resolvedPhotoKey == resolutionKey, let resolvedPhoto {
                    Image(uiImage: resolvedPhoto.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .bottom) {
                if resolvedPhotoKey == resolutionKey,
                   resolvedPhoto?.photo.isGooglePlacesPhoto == true {
                    Text("Google Maps")
                        .font(.system(size: googleAttributionFontSize, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, minHeight: 13)
                        .background(Color.black.opacity(0.68))
                        .allowsHitTesting(false)
                }
            }
            .task(id: "\(resolutionKey)|target-px:\(targetPixelSize)") {
                resolvedPhoto = nil
                resolvedPhotoKey = resolutionKey
                let resolved = await ListPlacePhotoResolver.resolve(
                    request: place.canonicalProfilePlace.photoRequest,
                    preferredUserPhoto: place.preferredUserPhoto,
                    eligibleUserIDs: eligibleUserIDs,
                    authorizationScopeKey: photoAuthorizationScopeKey,
                    targetPixelSize: targetPixelSize,
                    backend: backend
                )
                guard !Task.isCancelled, photoResolutionKey == resolutionKey else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    resolvedPhoto = resolved
                    resolvedPhotoKey = resolutionKey
                }
            }
        }
        .clipped()
    }

    private var photoResolutionKey: String {
        [
            place.canonicalProfilePlace.photoLookupKey,
            place.preferredUserPhoto?.cacheKey ?? "no-preloaded-user-photo",
            eligibleUserIDs?.sorted().joined(separator: ",") ?? "all-visible-users",
            photoAuthorizationScopeKey
        ]
            .joined(separator: "|")
    }

    private var photoAuthorizationScopeKey: String {
        let followsKey = store.follows
            .map {
                "\($0.followerUserID)>\($0.followedUserID):\($0.localUpdatedAt.timeIntervalSinceReferenceDate.bitPattern)"
            }
            .sorted()
            .joined(separator: ",")
        let blocksKey = store.blocks
            .map {
                "\($0.blockerUserID)>\($0.blockedUserID):\($0.localUpdatedAt.timeIntervalSinceReferenceDate.bitPattern)"
            }
            .sorted()
            .joined(separator: ",")
        return "user:\(store.currentUser.id)|follows:\(followsKey)|blocks:\(blocksKey)"
    }
}

private struct ListMapAvailabilityNotice: View {
    let systemImage: String
    let message: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 36)
            .background(WanderTheme.surfaceRaised.color.opacity(0.96))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

private struct ListMapStatePanel: View {
    let list: PlaceListMock
    let bottomInset: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Group {
                if list.mapAvailability == .loading {
                    ProgressView()
                        .tint(WanderTheme.terracotta.color)
                } else {
                    Image(systemName: stateIcon)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                }
            }
            .frame(width: 36, height: 36)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(stateTitle)
                    .font(.headline.weight(.black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(stateMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing4)
        .padding(.bottom, max(bottomInset, WanderTheme.spacing2))
        .background(WanderTheme.surfaceRaised.color.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
    }

    private var stateIcon: String {
        switch list.mapAvailability {
        case .error:
            "exclamationmark.triangle.fill"
        case .offline:
            "wifi.slash"
        case .ready, .loading:
            "map"
        }
    }

    private var stateTitle: String {
        switch list.mapAvailability {
        case .loading:
            "Loading places…"
        case .error:
            "Couldn’t load these places"
        case .offline:
            "Places aren’t available offline"
        case .ready:
            list.totalItemCount == 0 ? "No places to map yet" : "Places aren’t mapped yet"
        }
    }

    private var stateMessage: String {
        switch list.mapAvailability {
        case .loading:
            "You can close the map while this list catches up."
        case .error:
            "Close the map and pull to refresh the list."
        case .offline:
            "Reconnect to load places that aren’t saved on this device."
        case .ready:
            list.totalItemCount == 0
                ? "Add a place from list detail to start this map."
                : "Resolved places still appear in the list below."
        }
    }
}

private struct ListPlaceProfileDestination: View {
    let place: ListPlaceMock
    let onBack: () -> Void

    var body: some View {
        PlaceProfileFullScreen(
            place: place.canonicalProfilePlace,
            saves: place.saves,
            tasteSaves: place.tasteSaves,
            currentUserID: place.currentUserID,
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
                if !isEditing {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .cancellationAction) {
                            newListBackButton
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            newListBackButton
                        }
                    }
                }

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
                    allowsInvitesWhilePrivate: canEditCollaborators,
                    listName: title
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

    private var newListBackButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WanderTheme.textInk.color)
        .accessibilityLabel("Back to lists")
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
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: -8) {
            ForEach(collaborators.prefix(3)) { collaborator in
                if let onSelect {
                    Button {
                        onSelect(profileID(for: collaborator))
                    } label: {
                        collaboratorAvatar(collaborator)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(collaborator.name)'s profile")
                } else {
                    collaboratorAvatar(collaborator)
                        .accessibilityLabel(collaborator.name)
                }
            }
        }
        .frame(minWidth: collaborators.isEmpty ? 0 : size + CGFloat(max(0, min(collaborators.count, 3) - 1)) * (size - 8), alignment: .leading)
    }

    private func collaboratorAvatar(_ collaborator: ListCollaboratorMock) -> some View {
        WanderAvatar(
            initials: collaborator.initials,
            avatarURL: avatarURL(for: collaborator),
            size: size,
            color: collaborator.color
        )
    }

    private func avatarURL(for collaborator: ListCollaboratorMock) -> String? {
        if let avatarURL = collaborator.avatarURL {
            return avatarURL
        }

        return store.profiles.first { profile in
            profile.id == collaborator.id || profile.handle == collaborator.handle
        }?.avatarURL
    }

    private func profileID(for collaborator: ListCollaboratorMock) -> String {
        store.profiles.first { profile in
            profile.id == collaborator.id
                || profile.handle.caseInsensitiveCompare(collaborator.handle) == .orderedSame
        }?.id ?? collaborator.id
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
    var mapAvailability: ListMapAvailability = .ready

    var previewPlaces: [ListPlaceMock] { places }
    var itemCount: Int { itemCountOverride ?? places.count }
    var totalItemCount: Int { max(itemCount, places.count) }
    var resolvedPlaceCount: Int { places.count }
    var mappedPlaces: [ListPlaceMock] { places.filter(\.isMappable) }
    var mappedPlaceCount: Int { mappedPlaces.count }
    var mapContentState: ListMapContentState {
        ListMapContentState(
            totalItemCount: totalItemCount,
            resolvedPlaceCount: resolvedPlaceCount,
            mappedPlaceCount: mappedPlaceCount
        )
    }
    var isOwnedByCurrentUser: Bool { ownerName == "You" }
    var isCollaborative: Bool { !collaborators.isEmpty }
    var photoContributorUserIDs: [String] {
        Array(Set([ownerUserID] + collaborators.map(\.id)))
            .filter { !$0.isEmpty }
            .sorted()
    }

    var mapRegion: MKCoordinateRegion {
        MapRegionFitter.region(
            fitting: mappedPlaces.map(\.coordinate),
            minimumSpan: 0.012,
            paddingMultiplier: 1.65
        ) ?? MKCoordinateRegion(
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
    init(
        summary list: LocalPlaceList,
        visiblePlaces: [VisiblePlace],
        preferredUserPhotosByPlaceID: [String: LocalVisitPhoto],
        store: WanderStore
    ) {
        let owner = store.profiles.first { $0.id == list.ownerUserID }
        self.id = list.id
        self.name = list.name
        self.description = list.description
        self.ownerName = list.ownerUserID == store.currentUser.id ? "You" : owner?.displayName ?? "Friend"
        self.isStealth = list.isStealth
        let listCollaborators = store.collaborators(for: list).map(ListCollaboratorMock.init(profile:))
        self.collaborators = listCollaborators
        let photoContributorUserIDs = Set([list.ownerUserID] + listCollaborators.map(\.id))
        self.places = visiblePlaces.map { visiblePlace in
            ListPlaceMock(
                cover: visiblePlace,
                currentUserID: store.currentUser.id,
                preferredUserPhoto: photoContributorUserIDs.contains(store.currentUser.id)
                    ? preferredUserPhotosByPlaceID[visiblePlace.place.id]
                        .map(PlacePhoto.init(localVisitPhoto:))
                    : nil
            )
        }
        self.itemCountOverride = list.cachedItemCount
        self.sourceListID = list.id
        self.ownerUserID = list.ownerUserID
        self.canManage = store.canManage(list)
        self.canAddPlaces = store.canAddPlaces(to: list)
        self.mapAvailability = .ready
    }

    init(list: LocalPlaceList, store: WanderStore) {
        self.init(list: list, visiblePlaces: store.visiblePlaces(in: list), store: store)
    }

    init(list: LocalPlaceList, visiblePlaces: [VisiblePlace], store: WanderStore) {
        let owner = store.profiles.first { $0.id == list.ownerUserID }
        let context = ListPlaceProjectionContext(store: store)
        self.id = list.id
        self.name = list.name
        self.description = list.description
        self.ownerName = list.ownerUserID == store.currentUser.id ? "You" : owner?.displayName ?? "Friend"
        self.isStealth = list.isStealth
        self.collaborators = store.collaborators(for: list).map(ListCollaboratorMock.init(profile:))
        self.places = visiblePlaces.map { visiblePlace in
            let saves = context.savesByVisiblePlaceID[visiblePlace.id] ?? [
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: visiblePlace.attributes,
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
            ]
            let preferredUserPhoto = context.firstVisitPhotoByPlaceID[visiblePlace.place.id]
                .map(PlacePhoto.init(localVisitPhoto:))

            return ListPlaceMock(
                visiblePlace: visiblePlace,
                saves: saves,
                tasteSaves: context.tasteSaves,
                currentUserID: context.currentUserID,
                preferredUserPhoto: preferredUserPhoto
            )
        }
        self.itemCountOverride = list.cachedItemCount
        self.sourceListID = list.id
        self.ownerUserID = list.ownerUserID
        self.canManage = store.canManage(list)
        self.canAddPlaces = store.canAddPlaces(to: list)
        // The store currently has no list-scoped request state. A cached count
        // without hydrated places is unresolved content, not proof that a
        // request is actively loading.
        self.mapAvailability = .ready
    }
}

@MainActor
private struct ListPlaceProjectionContext {
    let currentUserID: String
    let tasteSaves: [PlaceSaveSummary]
    let savesByVisiblePlaceID: [String: [PlaceSaveSummary]]
    let firstVisitPhotoByPlaceID: [String: LocalVisitPhoto]

    init(store: WanderStore) {
        currentUserID = store.currentUser.id
        tasteSaves = store.currentUserVisiblePlaces.map {
            PlaceSaveSummary(
                visiblePlace: $0,
                attributes: $0.attributes,
                viewerFollowsOwner: false
            )
        }
        firstVisitPhotoByPlaceID = store.firstVisitPhotosByPlaceID()

        let groups = VisiblePlaceGrouping.groups(
            from: store.visiblePlaces(),
            currentUserID: currentUserID
        )
        var summariesByVisiblePlaceID: [String: [PlaceSaveSummary]] = [:]
        summariesByVisiblePlaceID.reserveCapacity(groups.reduce(0) { $0 + $1.places.count })
        for group in groups {
            let summaries = group.places.map {
                PlaceSaveSummary(
                    visiblePlace: $0,
                    attributes: $0.attributes,
                    viewerFollowsOwner: store.viewerFollows($0.owner.id)
                )
            }
            for visiblePlace in group.places {
                summariesByVisiblePlaceID[visiblePlace.id] = summaries
            }
        }
        savesByVisiblePlaceID = summariesByVisiblePlaceID
    }
}

private struct ListPlaceMock: Identifiable {
    let id: String
    let name: String
    let category: String
    let emoji: String
    let metadata: String
    let tint: Color
    let pinPosition: CGPoint
    let latitude: Double
    let longitude: Double
    let status: PlaceStatus
    let saveOwnership: MapPinSaveOwnership
    let note: String?
    let placeID: String?
    let visiblePlaceID: String?
    let locality: String?
    let ownerName: String
    let profilePlace: PlaceSheetPlace?
    let saves: [PlaceSaveSummary]
    let tasteSaves: [PlaceSaveSummary]
    let currentUserID: String
    let preferredUserPhoto: PlacePhoto?
    let saveStates: [MapPinSaveState]

    init(
        id: String,
        name: String,
        category: String,
        emoji: String? = nil,
        metadata: String,
        tint: Color,
        pinPosition: CGPoint,
        latitude: Double? = nil,
        longitude: Double? = nil,
        status: PlaceStatus = .wannaGo,
        saveOwnership: MapPinSaveOwnership = .currentUser,
        note: String? = nil,
        placeID: String? = nil,
        visiblePlaceID: String? = nil,
        locality: String? = nil,
        ownerName: String = "You",
        profilePlace: PlaceSheetPlace? = nil,
        saves: [PlaceSaveSummary] = [],
        tasteSaves: [PlaceSaveSummary] = [],
        currentUserID: String = "you",
        preferredUserPhoto: PlacePhoto? = nil,
        saveStates: [MapPinSaveState]? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.emoji = emoji ?? WanderPlaceCategory.emoji(for: category, name: name)
        self.metadata = metadata
        self.tint = tint
        self.pinPosition = pinPosition
        self.latitude = latitude ?? 34.075 + (84 - pinPosition.y) * 0.00042
        self.longitude = longitude ?? -118.285 + (pinPosition.x - 170) * 0.00055
        self.status = status
        self.saveOwnership = saveOwnership
        self.note = note
        self.placeID = placeID
        self.visiblePlaceID = visiblePlaceID
        self.locality = locality
        self.ownerName = ownerName
        self.profilePlace = profilePlace
        self.saves = saves
        self.tasteSaves = tasteSaves
        self.currentUserID = currentUserID
        self.preferredUserPhoto = preferredUserPhoto
        self.saveStates = saveStates ?? [
            MapPinSaveState(ownership: saveOwnership, status: status)
        ]
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isMappable: Bool {
        ListMapCoordinate(id: id, coordinate: coordinate).isMappable
    }

    var canonicalProfilePlace: PlaceSheetPlace {
        profilePlace ?? PlaceSheetPlace(listPlace: self)
    }

    var detailsLine: String {
        let categoryDisplay = WanderPlaceCategory.display(
            for: WanderPlaceCategory.assignment(forRawCategory: category)
        )
        let categoryTitle = categoryDisplay.subcategory ?? categoryDisplay.category
        let parts = [categoryTitle, locality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? metadata : parts.joined(separator: " · ")
    }

    var contextLine: String {
        let visibleSaves = saves.map(\.visiblePlace)
        let hasOwnSave = visibleSaves.contains { $0.owner.id == currentUserID }
        let socialOwners = visibleSaves
            .filter { $0.owner.id != currentUserID }
            .map(\.owner.displayName)
        let uniqueSocialOwners = socialOwners.reduce(into: [String]()) { result, name in
            if !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                result.append(name)
            }
        }

        let ownershipSummary: String
        if visibleSaves.isEmpty {
            ownershipSummary = ownerName
        } else if hasOwnSave && uniqueSocialOwners.isEmpty {
            ownershipSummary = "You"
        } else if hasOwnSave {
            ownershipSummary = "You + \(uniqueSocialOwners.count)"
        } else if uniqueSocialOwners.count > 1, let firstOwner = uniqueSocialOwners.first {
            ownershipSummary = "\(firstOwner) + \(uniqueSocialOwners.count - 1)"
        } else {
            ownershipSummary = uniqueSocialOwners.first ?? ownerName
        }

        let statuses = visibleSaves.isEmpty ? [status] : visibleSaves.map(\.userPlace.status)
        let hasBeen = statuses.contains(.been)
        let hasWanna = statuses.contains(.wannaGo)
        let statusSummary = hasBeen && hasWanna
            ? "Checked in + Wanna go"
            : (hasBeen ? PlaceStatus.been.displayTitle : PlaceStatus.wannaGo.displayTitle)

        return "\(ownershipSummary) · \(statusSummary)"
    }

    var accessibilitySummary: String {
        [name, detailsLine, contextLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var dedupeKey: String {
        "\(name.normalizedListLookupKey)|\(category.normalizedListLookupKey)"
    }

    init(
        visiblePlace: VisiblePlace,
        saves: [PlaceSaveSummary] = [],
        tasteSaves: [PlaceSaveSummary] = [],
        currentUserID: String,
        preferredUserPhoto: PlacePhoto? = nil
    ) {
        let place = visiblePlace.place
        let categoryPresentation = visiblePlace.categoryPresentation
        let category = categoryPresentation.assignment.primaryCategory
        let metadataParts = [
            visiblePlace.userPlace.status.displayTitle,
            categoryPresentation.display.compactTitle,
            place.locality
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        self.init(
            id: "saved-\(visiblePlace.id)",
            name: place.canonicalName,
            category: category,
            emoji: categoryPresentation.emoji,
            metadata: metadataParts.joined(separator: " - "),
            tint: Self.tint(for: category),
            pinPosition: Self.previewPinPosition(for: place.id),
            latitude: place.latitude,
            longitude: place.longitude,
            status: visiblePlace.userPlace.status,
            saveOwnership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
            note: visiblePlace.userPlace.note,
            placeID: place.id,
            visiblePlaceID: visiblePlace.id,
            locality: place.locality,
            ownerName: visiblePlace.owner.id == currentUserID ? "You" : visiblePlace.owner.displayName,
            profilePlace: PlaceSheetPlace(visiblePlace: visiblePlace),
            saves: saves,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID,
            preferredUserPhoto: preferredUserPhoto,
            saveStates: saves.isEmpty
                ? nil
                : saves.map { save in
                    MapPinSaveState(
                        ownership: save.visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                        status: save.visiblePlace.userPlace.status
                    )
                }
        )
    }

    init(
        cover visiblePlace: VisiblePlace,
        currentUserID: String,
        preferredUserPhoto: PlacePhoto? = nil
    ) {
        let place = visiblePlace.place
        let categoryPresentation = visiblePlace.categoryPresentation
        let category = categoryPresentation.assignment.primaryCategory

        self.init(
            id: "saved-\(visiblePlace.id)",
            name: place.canonicalName,
            category: category,
            emoji: categoryPresentation.emoji,
            metadata: categoryPresentation.display.compactTitle,
            tint: Self.tint(for: category),
            pinPosition: Self.previewPinPosition(for: place.id),
            latitude: place.latitude,
            longitude: place.longitude,
            status: visiblePlace.userPlace.status,
            saveOwnership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
            placeID: place.id,
            visiblePlaceID: visiblePlace.id,
            locality: place.locality,
            ownerName: visiblePlace.owner.id == currentUserID ? "You" : visiblePlace.owner.displayName,
            profilePlace: PlaceSheetPlace(visiblePlace: visiblePlace),
            currentUserID: currentUserID,
            preferredUserPhoto: preferredUserPhoto
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

private func savedPlaceOutlines(
    for visiblePlace: VisiblePlace,
    outlineCatalog: [String: [MapPinOutline]],
    currentUserID: String
) -> [MapPinOutline] {
    if let outlines = outlineCatalog[visiblePlace.id] {
        return outlines
    }

    return MapPinOutlineBuilder.outlines(
        for: [
            MapPinSaveState(
                ownership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                status: visiblePlace.userPlace.status
            )
        ]
    )
}

private func savedPlaceOutlines(
    for place: ListPlaceMock,
    outlineCatalog: [String: [MapPinOutline]]
) -> [MapPinOutline] {
    if let visiblePlaceID = place.visiblePlaceID,
       let outlines = outlineCatalog[visiblePlaceID] {
        return outlines
    }

    return MapPinOutlineBuilder.outlines(for: place.saveStates)
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

@MainActor
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

    static let clusteredPlaces = [
        ListPlaceMock(
            id: "cluster-circuit",
            name: "Circuit Coffee",
            category: "coffee",
            metadata: "coffee - outlets - quiet",
            tint: WanderTheme.skyTint.color,
            pinPosition: CGPoint(x: 108, y: 86),
            latitude: 34.07720,
            longitude: -118.26045,
            status: .wannaGo,
            saveOwnership: .currentUser,
            ownerName: "You"
        ),
        ListPlaceMock(
            id: "cluster-woodcat",
            name: "Woodcat Coffee",
            category: "coffee",
            metadata: "coffee - window table",
            tint: WanderTheme.sunTint.color,
            pinPosition: CGPoint(x: 132, y: 92),
            latitude: 34.07728,
            longitude: -118.26037,
            status: .been,
            saveOwnership: .social,
            ownerName: "Maya"
        ),
        ListPlaceMock(
            id: "cluster-fern",
            name: "Fern Desk Coffee",
            category: "coffee",
            metadata: "coffee - wifi solid",
            tint: WanderTheme.terracottaTint.color,
            pinPosition: CGPoint(x: 150, y: 98),
            latitude: 34.07734,
            longitude: -118.26030,
            status: .wannaGo,
            saveOwnership: .social,
            ownerName: "Ryan"
        ),
        ListPlaceMock(
            id: "cluster-park",
            name: "Elysian Picnic Steps",
            category: "park",
            metadata: "park - sunset backup",
            tint: WanderTheme.categorySage.color.opacity(0.36),
            pinPosition: CGPoint(x: 250, y: 132),
            latitude: 34.08365,
            longitude: -118.24255,
            status: .been,
            saveOwnership: .currentUser,
            ownerName: "You"
        )
    ]

    static let dispersedPlaces = [
        ListPlaceMock(
            id: "dispersed-la",
            name: "Circuit Coffee",
            category: "coffee",
            metadata: "Los Angeles",
            tint: WanderTheme.skyTint.color,
            pinPosition: CGPoint(x: 80, y: 80),
            latitude: 34.0772,
            longitude: -118.2604
        ),
        ListPlaceMock(
            id: "dispersed-sf",
            name: "Sightglass Coffee",
            category: "coffee",
            metadata: "San Francisco",
            tint: WanderTheme.terracottaTint.color,
            pinPosition: CGPoint(x: 160, y: 100),
            latitude: 37.7764,
            longitude: -122.4086,
            status: .been
        ),
        ListPlaceMock(
            id: "dispersed-nyc",
            name: "Devoción",
            category: "coffee",
            metadata: "Brooklyn",
            tint: WanderTheme.sunTint.color,
            pinPosition: CGPoint(x: 260, y: 110),
            latitude: 40.7164,
            longitude: -73.9583,
            status: .been,
            saveOwnership: .social,
            ownerName: "Sofia"
        )
    ]

    static let longNamePlaces = [
        ListPlaceMock(
            id: "long-name",
            name: "The Extremely Thoughtful Neighborhood Coffee Shop With the Window Table Everyone Keeps Recommending",
            category: "coffee",
            metadata: "coffee - Highland Park - outlets and a very calm back patio",
            tint: WanderTheme.terracottaTint.color,
            pinPosition: CGPoint(x: 150, y: 94),
            latitude: 34.1110,
            longitude: -118.1926,
            status: .been,
            saveOwnership: .social,
            locality: "Highland Park",
            ownerName: "Maya"
        ),
        ListPlaceMock(
            id: "long-name-two",
            name: "A Small Park for Long Conversations After a Very Late Lunch",
            category: "park",
            metadata: "park - Mount Washington",
            tint: WanderTheme.categorySage.color.opacity(0.36),
            pinPosition: CGPoint(x: 238, y: 126),
            latitude: 34.1002,
            longitude: -118.2213,
            locality: "Mount Washington"
        )
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

    static func fixture(for scenario: ListsScreenScenario) -> PlaceListMock {
        switch scenario {
        case .mapEmpty:
            PlaceListMock(
                id: "map-empty",
                name: "New neighborhood ideas",
                description: "A quiet place to collect the next good find.",
                ownerName: "You",
                isStealth: false,
                collaborators: [],
                places: [],
                itemCountOverride: 0
            )
        case .mapSingle:
            PlaceListMock(
                id: "map-single",
                name: "One reliable coffee",
                description: "The place that always works.",
                ownerName: "You",
                isStealth: false,
                collaborators: [],
                places: [laptopPlaces[0]],
                itemCountOverride: 1
            )
        case .mapClustered:
            PlaceListMock(
                id: "map-clustered",
                name: "Echo Park coffee walk",
                description: "Several good options close enough to browse on foot.",
                ownerName: "You",
                isStealth: false,
                collaborators: [maya],
                places: clusteredPlaces
            )
        case .mapDispersed:
            PlaceListMock(
                id: "map-dispersed",
                name: "Coffee worth crossing a time zone for",
                description: "Saved from trusted people in a few different cities.",
                ownerName: "You",
                isStealth: false,
                collaborators: [sofia],
                places: dispersedPlaces
            )
        case .mapPartial:
            PlaceListMock(
                id: "map-partial",
                name: "Partially cached weekend",
                description: "Some places are ready here and the rest are still resolving.",
                ownerName: "You",
                isStealth: false,
                collaborators: [ryan],
                places: Array(clusteredPlaces.prefix(2)),
                itemCountOverride: 5
            )
        case .mapUnresolved:
            PlaceListMock(
                id: "map-unresolved",
                name: "Loading saved places",
                description: "The list is here while its place details arrive.",
                ownerName: "You",
                isStealth: false,
                collaborators: [],
                places: [],
                itemCountOverride: 4,
                mapAvailability: .loading
            )
        case .mapUnmapped:
            PlaceListMock(
                id: "map-unmapped",
                name: "Saved without a map location",
                description: "The place is still useful even before coordinates arrive.",
                ownerName: "You",
                isStealth: false,
                collaborators: [],
                places: [
                    ListPlaceMock(
                        id: "unmapped-place",
                        name: "A friend’s neighborhood recommendation",
                        category: "restaurant",
                        metadata: "restaurant · location unavailable",
                        tint: WanderTheme.sunTint.color,
                        pinPosition: CGPoint(x: 170, y: 90),
                        latitude: 0,
                        longitude: 0,
                        status: .been,
                        saveOwnership: .social,
                        ownerName: "Maya"
                    )
                ],
                itemCountOverride: 1
            )
        case .mapError:
            PlaceListMock(
                id: "map-error",
                name: "Weekend backups",
                description: "The list remains available even when map details fail.",
                ownerName: "You",
                isStealth: false,
                collaborators: [],
                places: [],
                itemCountOverride: 4,
                mapAvailability: .error
            )
        case .mapOffline:
            PlaceListMock(
                id: "map-offline",
                name: "Saved for the flight",
                description: "Cached places remain useful without a connection.",
                ownerName: "You",
                isStealth: false,
                collaborators: [maya],
                places: clusteredPlaces,
                mapAvailability: .offline
            )
        case .mapLongNames:
            PlaceListMock(
                id: "map-long-names",
                name: "Places for the Saturday when nobody wants to decide where the afternoon should go next",
                description: "Long names should stay readable on a small phone and at larger text sizes.",
                ownerName: "You",
                isStealth: false,
                collaborators: [maya, ryan],
                places: longNamePlaces
            )
        default:
            featuredDetail
        }
    }
}

private extension PlaceSheetPlace {
    init(listPlace: ListPlaceMock) {
        let assignment = WanderPlaceCategory.assignment(forRawCategory: listPlace.category)
        self.id = listPlace.placeID ?? listPlace.id
        self.name = listPlace.name
        self.category = assignment.legacyCategory
        self.primaryCategory = assignment.primaryCategory
        self.subcategory = assignment.subcategory
        self.categorySource = assignment.source
        self.categoryConfidence = assignment.confidence
        self.rawProviderType = assignment.rawProviderType
        self.cuisine = nil
        self.address = nil
        self.locality = listPlace.locality
        self.region = nil
        self.latitude = listPlace.latitude
        self.longitude = listPlace.longitude
        self.websiteURLString = nil
        self.phoneNumber = nil
        self.actionLinksJSON = nil
        self.sourceProvider = nil
        self.sourceProviderPlaceID = nil
        self.compactSubtitleOverride = listPlace.metadata
        self.status = listPlace.status
        self.visibility = nil
        self.note = listPlace.note
        self.noteOwnerID = listPlace.currentUserID
        self.noteOwnerName = listPlace.ownerName
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
