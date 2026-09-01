import SwiftUI
import UIKit

enum MapPlaceListActionSymbol {
    static let systemImage = "bookmark.fill"
}

enum MapPlaceListTarget: Identifiable {
    case candidate(PlaceCandidate)
    case visiblePlace(VisiblePlace)

    var id: String {
        switch self {
        case .candidate(let candidate):
            "candidate-\(candidate.id)"
        case .visiblePlace(let visiblePlace):
            "visible-place-\(visiblePlace.id)"
        }
    }

    var placeName: String {
        switch self {
        case .candidate(let candidate):
            candidate.name
        case .visiblePlace(let visiblePlace):
            visiblePlace.place.canonicalName
        }
    }

    @MainActor
    func isAlreadyInList(_ list: LocalPlaceList, store: WanderStore) -> Bool {
        switch self {
        case .candidate(let candidate):
            store.hasCandidate(candidate, in: list)
        case .visiblePlace(let visiblePlace):
            store.hasPlace(visiblePlace, in: list)
        }
    }

    @MainActor
    func needsCompanionWanna(in store: WanderStore) -> Bool {
        switch self {
        case .candidate(let candidate):
            !store.currentUserVisiblePlaces.contains {
                VisiblePlaceGrouping.matches($0, candidate: candidate)
            }
        case .visiblePlace(let visiblePlace):
            !store.currentUserVisiblePlaces.contains {
                VisiblePlaceGrouping.matches($0, visiblePlace)
            }
        }
    }

    @MainActor
    func add(
        to list: LocalPlaceList,
        store: WanderStore,
        backend: WanderBackend
    ) async -> ListPlaceAddResult {
        switch self {
        case .candidate(let candidate):
            await store.addCandidate(
                candidate,
                to: list,
                backend: backend,
                analyticsSurface: "map"
            )
        case .visiblePlace(let visiblePlace):
            await store.addVisiblePlace(
                visiblePlace,
                to: list,
                backend: backend,
                analyticsSurface: "map"
            )
        }
    }
}

struct MapPlaceListPickerSelection: Equatable {
    private(set) var existingListIDs: Set<String>
    private(set) var pendingListIDs: Set<String> = []

    mutating func togglePending(listID: String) {
        guard !existingListIDs.contains(listID) else { return }
        if !pendingListIDs.insert(listID).inserted {
            pendingListIDs.remove(listID)
        }
    }

    mutating func replaceExistingListIDs(_ listIDs: Set<String>) {
        existingListIDs = listIDs
        pendingListIDs.subtract(listIDs)
    }
}

private struct MapPlaceListPickerPresentation {
    let eligibleLists: [LocalPlaceList]
    let yourLists: [LocalPlaceList]
    let collaborationLists: [LocalPlaceList]
    let detailByListID: [String: String]
    let needsCompanionWanna: Bool

    static let empty = MapPlaceListPickerPresentation(
        eligibleLists: [],
        yourLists: [],
        collaborationLists: [],
        detailByListID: [:],
        needsCompanionWanna: false
    )
}

struct MapPlaceListPickerResult: Equatable {
    let addedCount: Int
    let alreadyInListCount: Int
    let deniedCount: Int
    let companionSave: ListPlaceAddResult.CompanionSave

    var message: String {
        guard addedCount > 0 else {
            return deniedCount > 0
                ? "Couldn’t add this place. Try again."
                : "This place is already in that list."
        }

        let destination = addedCount == 1 ? "1 list" : "\(addedCount) lists"
        let base = "Added to \(destination)."
        if case .createdWanna = companionSave {
            return "Added to \(destination) and Wanna Go."
        }
        if deniedCount > 0 {
            return "\(base) One list needs another try."
        }
        return base
    }

    static func summarize(_ results: [ListPlaceAddResult]) -> MapPlaceListPickerResult {
        var addedCount = 0
        var alreadyInListCount = 0
        var deniedCount = 0
        var companionSave: ListPlaceAddResult.CompanionSave = .none

        for result in results {
            switch result.outcome {
            case .added:
                addedCount += 1
            case .alreadyInList:
                alreadyInListCount += 1
            case .permissionDenied:
                deniedCount += 1
            }

            switch result.companionSave {
            case .createdWanna:
                companionSave = result.companionSave
            case .existingWanna where companionSave == .none:
                companionSave = result.companionSave
            case .none, .existingWanna:
                break
            }
        }

        return MapPlaceListPickerResult(
            addedCount: addedCount,
            alreadyInListCount: alreadyInListCount,
            deniedCount: deniedCount,
            companionSave: companionSave
        )
    }
}

struct MapPlaceListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    let target: MapPlaceListTarget
    let onComplete: (MapPlaceListPickerResult) -> Void
    @State private var selection = MapPlaceListPickerSelection(existingListIDs: [])
    @State private var didLoadMembership = false
    @State private var isApplying = false
    @State private var isCreatingList = false
    @State private var errorMessage: String?
    @State private var presentation = MapPlaceListPickerPresentation.empty

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("add to lists")
                            .font(WanderTypography.actionScreenTitle)
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text(target.placeName)
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }

                    newListButton

                    if yourLists.isEmpty && collaborationLists.isEmpty {
                        emptyState
                    } else {
                        if !yourLists.isEmpty {
                            listSection(title: "your lists", lists: yourLists)
                        }
                        if !collaborationLists.isEmpty {
                            listSection(title: "collabs", lists: collaborationLists)
                        }
                    }

                    if presentation.needsCompanionWanna {
                        companionSaveNotice
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WanderTypography.emphasizedBody)
                            .foregroundStyle(WanderTheme.stateError.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("map-list-picker.error")
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyButton
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .disabled(isApplying)
                    .accessibilityIdentifier("map-list-picker.cancel")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isApplying)
        .sheet(isPresented: $isCreatingList) {
            NewPlaceListEditorSheet { draft in
                createListAndAddPlace(draft)
            }
            .presentationDetents([.large])
            .presentationBackground(WanderTheme.canvasWarm.color)
        }
        .onAppear(perform: loadMembershipOnce)
        .onChange(of: store.presentationRevision) { _, _ in
            guard didLoadMembership, !isApplying else { return }
            refreshPresentation()
        }
        .accessibilityIdentifier("map-list-picker.sheet")
    }

    private var yourLists: [LocalPlaceList] {
        presentation.yourLists
    }

    private var collaborationLists: [LocalPlaceList] {
        presentation.collaborationLists
    }

    private var pendingLists: [LocalPlaceList] {
        presentation.eligibleLists.filter { selection.pendingListIDs.contains($0.id) }
    }

    private var newListButton: some View {
        Button {
            isCreatingList = true
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("new list")
                        .font(WanderTypography.control)
                    Text("Create it and add this place")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 60)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .accessibilityIdentifier("map-list-picker.new-list")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Image(systemName: WanderTab.lists.systemImage)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WanderTheme.terracottaDark.color)
            Text("No lists yet")
                .font(WanderTypography.editorialSectionTitle)
                .foregroundStyle(WanderTheme.textInk.color)
            Text("Make a list above and this place will be its first stop.")
                .font(WanderTypography.body)
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }

    private var companionSaveNotice: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 18, height: 18)

            Text("This place isn’t on your map yet, so adding it to a list will also save it to Wanna Go.")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("map-list-picker.wanna-notice")
    }

    private var applyButton: some View {
        Button {
            if pendingLists.isEmpty {
                dismiss()
            } else {
                Task { await applyPendingLists() }
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                if isApplying {
                    ProgressView()
                        .tint(WanderTheme.textOnAction.color)
                }
                Text(applyButtonTitle)
                    .font(WanderTypography.control)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(WanderTheme.textOnAction.color)
            .background(WanderTheme.terracotta.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
        .background(WanderTheme.canvasWarm.color.opacity(0.97))
        .accessibilityIdentifier("map-list-picker.apply")
    }

    private var applyButtonTitle: String {
        if isApplying { return "Adding…" }
        switch pendingLists.count {
        case 0:
            return "Done"
        case 1:
            return "Add to 1 list"
        default:
            return "Add to \(pendingLists.count) lists"
        }
    }

    private func listSection(title: String, lists: [LocalPlaceList]) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(WanderTheme.textMuted.color)

            LazyVStack(spacing: 0) {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    listRow(list)

                    if index < lists.count - 1 {
                        Divider()
                            .overlay(WanderTheme.borderHairline.color)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
    }

    private func listRow(_ list: LocalPlaceList) -> some View {
        let isExisting = selection.existingListIDs.contains(list.id)
        let isPending = selection.pendingListIDs.contains(list.id)

        return Button {
            guard !isExisting else { return }
            selection.togglePending(listID: list.id)
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: list.ownerUserID == store.currentUser.id ? "bookmark.fill" : "person.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(list.ownerUserID == store.currentUser.id
                        ? WanderTheme.terracottaDark.color
                        : WanderTheme.pinSocial.color)
                    .background((list.ownerUserID == store.currentUser.id
                        ? WanderTheme.terracottaTint.color
                        : WanderTheme.skyTint.color))
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(list.name)
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                    Text(listDetail(list))
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: isExisting || isPending ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        isExisting
                            ? Color(uiColor: .systemGray3)
                            : isPending
                                ? WanderTheme.terracotta.color
                                : WanderTheme.borderStrong.color
                    )
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isApplying || isExisting)
        .accessibilityIdentifier("map-list-picker.list.\(list.id)")
        .accessibilityLabel("\(list.name), \(isExisting ? "already in list" : isPending ? "selected" : "not selected")")
        .accessibilityHint(isExisting ? "This place is already in the list" : "Double tap to toggle this list")
    }

    private func listDetail(_ list: LocalPlaceList) -> String {
        presentation.detailByListID[list.id] ?? "List"
    }

    private func makeListDetail(_ list: LocalPlaceList) -> String {
        let count = list.cachedItemCount ?? store.visiblePlaces(in: list).count
        let places = count == 1 ? "1 place" : "\(count) places"
        let collaboratorCount = store.collaborators(for: list).count

        if list.ownerUserID != store.currentUser.id {
            return "Shared with you · \(places)"
        }
        if collaboratorCount > 0 {
            let collaborators = collaboratorCount == 1
                ? "1 collaborator"
                : "\(collaboratorCount) collaborators"
            return "\(collaborators) · \(places)"
        }
        return places
    }

    private func loadMembershipOnce() {
        guard !didLoadMembership else { return }
        didLoadMembership = true
        refreshPresentation()
    }

    private func refreshPresentation() {
        let eligibleLists = store.visiblePlaceLists.filter(store.canAddPlaces)
        var yourLists: [LocalPlaceList] = []
        var collaborationLists: [LocalPlaceList] = []
        var detailByListID: [String: String] = [:]
        var existingListIDs: Set<String> = []
        yourLists.reserveCapacity(eligibleLists.count)
        collaborationLists.reserveCapacity(eligibleLists.count)
        detailByListID.reserveCapacity(eligibleLists.count)

        for list in eligibleLists {
            if list.ownerUserID == store.currentUser.id {
                yourLists.append(list)
            } else {
                collaborationLists.append(list)
            }
            detailByListID[list.id] = makeListDetail(list)
            if target.isAlreadyInList(list, store: store) {
                existingListIDs.insert(list.id)
            }
        }

        presentation = MapPlaceListPickerPresentation(
            eligibleLists: eligibleLists,
            yourLists: yourLists,
            collaborationLists: collaborationLists,
            detailByListID: detailByListID,
            needsCompanionWanna: target.needsCompanionWanna(in: store)
        )
        selection.replaceExistingListIDs(existingListIDs)
    }

    @MainActor
    private func applyPendingLists() async {
        guard !isApplying else { return }
        let lists = pendingLists
        guard !lists.isEmpty else {
            dismiss()
            return
        }

        isApplying = true
        errorMessage = nil
        var results: [ListPlaceAddResult] = []
        for list in lists {
            results.append(
                await target.add(to: list, store: store, backend: backend)
            )
        }
        isApplying = false
        refreshPresentation()

        let summary = MapPlaceListPickerResult.summarize(results)
        guard summary.addedCount > 0 || summary.alreadyInListCount > 0 else {
            errorMessage = summary.message
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(summary)
        dismiss()
    }

    private func createListAndAddPlace(_ draft: NewPlaceListDraft) {
        let visibility: PlaceListVisibility = draft.isStealth ? .stealth : .followers
        guard let list = store.createPlaceList(
            name: draft.title,
            description: draft.description,
            visibility: visibility,
            collaboratorUserIDs: draft.collaboratorUserIDs
        ) else {
            errorMessage = "Couldn’t create that list. Try a different name."
            return
        }

        isApplying = true
        Task { @MainActor in
            let result = await target.add(to: list, store: store, backend: backend)
            _ = await store.syncPendingPlaceLists(backend: backend)
            isApplying = false
            refreshPresentation()
            let summary = MapPlaceListPickerResult.summarize([result])
            guard summary.addedCount > 0 || summary.alreadyInListCount > 0 else {
                errorMessage = summary.message
                return
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete(summary)
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }
    }
}
