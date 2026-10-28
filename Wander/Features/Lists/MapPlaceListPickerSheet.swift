import SwiftUI
import UIKit

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
        backend: WanderBackend?,
        analyticsSurface: String = "map",
        keepNewCompanionPrivate: Bool = false,
        senderNotificationPolicy: SenderNotificationPolicy = .standard
    ) async -> ListPlaceAddResult {
        switch self {
        case .candidate(let candidate):
            await store.addCandidate(
                candidate,
                to: list,
                backend: backend,
                analyticsSurface: analyticsSurface,
                keepNewCompanionPrivate: keepNewCompanionPrivate,
                senderNotificationPolicy: senderNotificationPolicy
            )
        case .visiblePlace(let visiblePlace):
            await store.addVisiblePlace(
                visiblePlace,
                to: list,
                backend: backend,
                analyticsSurface: analyticsSurface,
                keepNewCompanionPrivate: keepNewCompanionPrivate,
                senderNotificationPolicy: senderNotificationPolicy
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
    var destinationListIDs: [String] = []
    var newlyAddedListIDs: Set<String> = []

    var message: String {
        guard addedCount > 0 else {
            return deniedCount > 0
                ? "Couldn’t Add This Place. Try Again."
                : "This Place Is Already In That List."
        }

        let destination = addedCount == 1 ? "1 List" : "\(addedCount) Lists"
        let base = "Added To \(destination)."
        if case .createdWanna = companionSave {
            return "Added To \(destination) And Wanna Go."
        }
        if deniedCount > 0 {
            return "\(base) One List Needs Another Try."
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
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    let target: MapPlaceListTarget
    var additionalTargets: [MapPlaceListTarget] = []
    var stagedListIDs: Set<String> = []
    var onStage: ((Set<String>) -> Void)?
    var stagedSaveStatus: PlaceStatus?
    private var targets: [MapPlaceListTarget] { [target] + additionalTargets }
    var analyticsSurface: String = "map"
    let onComplete: (MapPlaceListPickerResult) -> Void
    @State private var silentNotifications = false
    @State private var lastSelectedListID: String?
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
                        Text("Add To Lists")
                            .font(AstirTypography.sheetTitle)
                            .foregroundStyle(brandMode.primaryText)
                        Text(additionalTargets.isEmpty ? target.placeName : "\(targets.count) Places")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                            .lineLimit(1)
                    }

                    newListButton

                    if yourLists.isEmpty && collaborationLists.isEmpty {
                        emptyState
                    } else {
                        if !yourLists.isEmpty {
                            listSection(title: "Your Lists", lists: yourLists)
                        }
                        if !collaborationLists.isEmpty {
                            listSection(title: "Collabs", lists: collaborationLists)
                        }
                    }

                    if let stagedSaveStatus {
                        Text("Lists Are Updated Only When You Save This \(stagedSaveStatus == .been ? "Check-In" : "Wanna"). The Place Follows Each List’s Visibility; Your Save’s Audience Stays The Same.")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if presentation.needsCompanionWanna {
                        companionSaveNotice
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(WanderTheme.stateError.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("map-list-picker.error")
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .astirScreen()
            .tint(brandMode.accent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: WanderTheme.spacing2) {
                    if onStage == nil {
                        SilentSaveToggle(isSilent: $silentNotifications)
                            .disabled(isApplying)
                            .padding(.horizontal, WanderTheme.spacing4)
                    }
                    applyButton
                }
                .padding(.top, onStage == nil ? WanderTheme.spacing2 : 0)
                .background(brandMode.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
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
            .presentationBackground(brandMode.background)
        }
        .onAppear {
            guard !didLoadMembership else { return }
            loadMembershipOnce()
            for id in stagedListIDs {
                // A staged selection may outlive a new list receiving its server ID.
                let currentID = presentation.eligibleLists.first { $0.id == id || $0.localID == id }?.id ?? id
                selection.togglePending(listID: currentID)
            }
        }
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
                    .foregroundStyle(brandMode.accentForeground)
                    .background(brandMode.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("New List")
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text(onStage == nil ? "Create It And Add This Place" : stagedSaveStatus != nil ? "Create It And Select It For This Save" : "Create It And Select It For This Import")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(brandMode.secondaryText)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 60)
            .background(brandMode.accentWash)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(brandMode.accent.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .accessibilityIdentifier("map-list-picker.new-list")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Image(systemName: WanderTab.lists.systemImage)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(brandMode.accentText)
            Text("No Lists Yet")
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(brandMode.primaryText)
            Text("Make A List Above And This Place Will Be Its First Stop.")
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
    }

    private var companionSaveNotice: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing2) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(brandMode.accentText)
                .frame(width: 18, height: 18)

            Text(onStage == nil ? "This Place Isn’t On Your Map Yet, So Adding It To A List Will Also Save It To Wanna Go. If You Choose A Stealth List, The New Wanna Will Be Visible Only To You." : "List Choices Are Applied When You Tap Save In The Import Report. You Can Also Choose Wanna Or Check In.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("map-list-picker.wanna-notice")
    }

    private var applyButton: some View {
        Button {
            if pendingLists.isEmpty && onStage == nil {
                dismiss()
            } else {
                Task { await applyPendingLists() }
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                if isApplying {
                    ProgressView()
                        .tint(brandMode.accentForeground)
                }
                Text(applyButtonTitle)
                    .font(AstirTypography.control)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(brandMode.accentForeground)
            .background(brandMode.accent)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
        .background(brandMode.background.opacity(0.97))
        .accessibilityIdentifier("map-list-picker.apply")
    }

    private var applyButtonTitle: String {
        if onStage != nil { return "Done" }
        if isApplying { return "Adding…" }
        switch pendingLists.count {
        case 0:
            return "Done"
        case 1:
            return "Add To 1 List"
        default:
            return "Add To \(pendingLists.count) Lists"
        }
    }

    private func listSection(title: String, lists: [LocalPlaceList]) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(AstirTypography.metadata)
                .textCase(.uppercase)
                .foregroundStyle(brandMode.secondaryText)

            LazyVStack(spacing: 0) {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    listRow(list)

                    if index < lists.count - 1 {
                        Divider()
                            .overlay(brandMode.border)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(brandMode.border, lineWidth: 1)
            }
        }
    }

    private func listRow(_ list: LocalPlaceList) -> some View {
        let isExisting = selection.existingListIDs.contains(list.id)
        let isPending = selection.pendingListIDs.contains(list.id)

        return Button {
            guard !isExisting else { return }
            selection.togglePending(listID: list.id)
            if selection.pendingListIDs.contains(list.id) { lastSelectedListID = list.id }
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: PlaceListSymbol.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(!isExisting && list.ownerUserID == store.currentUser.id
                        ? brandMode.accent
                        : brandMode.secondaryText)
                    .background(!isExisting && list.ownerUserID == store.currentUser.id
                        ? brandMode.accentWash
                        : brandMode.recessedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(list.name)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(isExisting ? brandMode.secondaryText : brandMode.primaryText)
                        .lineLimit(1)
                    Text(isExisting ? "Already In List" : listDetail(list))
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: isExisting || isPending ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        isExisting
                            ? brandMode.secondaryText.opacity(0.58)
                            : isPending
                                ? brandMode.accent
                                : brandMode.border
                    )
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isApplying || isExisting)
        .accessibilityIdentifier("map-list-picker.list.\(list.id)")
        .accessibilityLabel("\(list.name), \(isExisting ? "Already In List" : isPending ? "Selected" : "Not Selected")")
        .accessibilityHint(isExisting ? "This Place Is Already In The List" : "Double Tap To Toggle This List")
    }

    private func listDetail(_ list: LocalPlaceList) -> String {
        presentation.detailByListID[list.id] ?? "List"
    }

    private func makeListDetail(_ list: LocalPlaceList) -> String {
        let count = list.cachedItemCount ?? store.visiblePlaces(in: list).count
        let places = count == 1 ? "1 Place" : "\(count) Places"
        let collaboratorCount = store.collaborators(for: list).count

        if list.ownerUserID != store.currentUser.id {
            return "Shared With You · \(places)"
        }
        if collaboratorCount > 0 {
            let collaborators = collaboratorCount == 1
                ? "1 Collaborator"
                : "\(collaboratorCount) Collaborators"
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
            if targets.allSatisfy({ $0.isAlreadyInList(list, store: store) }) {
                existingListIDs.insert(list.id)
            }
        }

        presentation = MapPlaceListPickerPresentation(
            eligibleLists: eligibleLists,
            yourLists: yourLists,
            collaborationLists: collaborationLists,
            detailByListID: detailByListID,
            needsCompanionWanna: targets.contains { $0.needsCompanionWanna(in: store) }
        )
        selection.replaceExistingListIDs(existingListIDs)
    }

    @MainActor
    private func applyPendingLists() async {
        guard !isApplying else { return }
        if let onStage {
            onStage(selection.pendingListIDs)
            dismiss()
            return
        }
        // If one selection creates a companion Wanna, the strictest selected
        // audience must be chosen before any save can reach Feed or push.
        let lists = pendingLists
        let keepNewCompanionPrivate = lists.contains { $0.visibility == .stealth }
        guard !lists.isEmpty else {
            dismiss()
            return
        }

        let notificationPolicy = SenderNotificationPolicy(silent: silentNotifications)
        isApplying = true
        errorMessage = nil
        let viewerID = store.currentUser.id
        var successfulLists: [LocalPlaceList] = []
        var newlyAddedLists: [LocalPlaceList] = []
        var results: [ListPlaceAddResult] = []
        for list in lists {
            for target in targets {
                guard store.currentUser.id == viewerID else { return }
                let result = await target.add(to: list, store: store, backend: backend,
                    analyticsSurface: analyticsSurface, keepNewCompanionPrivate: keepNewCompanionPrivate,
                    senderNotificationPolicy: notificationPolicy)
                results.append(result)
                if result.outcome == .added || result.outcome == .alreadyInList { successfulLists.append(list) }
                if result.outcome == .added { newlyAddedLists.append(list) }
            }
        }
        isApplying = false
        refreshPresentation()

        guard store.currentUser.id == viewerID else { return }
        var summary = MapPlaceListPickerResult.summarize(results)
        summary.destinationListIDs = Array(Set(successfulLists.map { selected in
            store.visiblePlaceLists.first(where: { $0.localID == selected.localID })?.id ?? selected.id
        })).sorted()
        summary.newlyAddedListIDs = Set(newlyAddedLists.map { selected in
            store.visiblePlaceLists.first(where: { $0.localID == selected.localID })?.id ?? selected.id
        })
        if let chosen = successfulLists.first(where: { $0.id == lastSelectedListID }) ?? successfulLists.last {
            RecentPlaceListChoice.shared.remember(chosen, accountID: viewerID, notificationPolicy: notificationPolicy)
        }
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
            errorMessage = "Couldn’t Create That List. Try A Different Name."
            return
        }

        if let onStage {
            onStage(selection.pendingListIDs.union([list.id]))
            dismiss()
            return
        }
        let notificationPolicy = SenderNotificationPolicy(silent: silentNotifications)
        let viewerID = store.currentUser.id
        isApplying = true
        Task { @MainActor in
            var results: [ListPlaceAddResult] = []
            for target in targets {
                guard store.currentUser.id == viewerID else { return }
                results.append(await target.add(to: list, store: store, backend: backend, analyticsSurface: analyticsSurface,
                    senderNotificationPolicy: notificationPolicy))
            }
            _ = await store.syncPendingPlaceLists(backend: backend)
            isApplying = false
            refreshPresentation()
            guard store.currentUser.id == viewerID else { return }
            var summary = MapPlaceListPickerResult.summarize(results)
            summary.destinationListIDs = [store.visiblePlaceLists.first(where: { $0.localID == list.localID })?.id ?? list.id]
            if results.contains(where: { $0.outcome == .added }) {
                summary.newlyAddedListIDs = Set(summary.destinationListIDs)
            }
            guard summary.addedCount > 0 || summary.alreadyInListCount > 0 else {
                errorMessage = summary.message
                return
            }

            RecentPlaceListChoice.shared.remember(list, accountID: viewerID, notificationPolicy: notificationPolicy)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete(summary)
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }
    }
}
