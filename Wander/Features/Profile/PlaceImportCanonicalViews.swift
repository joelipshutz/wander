import SwiftUI
import UIKit

private struct CanonicalImportSaveRoute: Identifiable {
    let id = UUID()
    let itemID: String
    let candidateID: String
    let context: MapPlaceSaveContext
}

/// The launch import review: every resolved place stays visible, uncertain
/// source mentions expose up to five independently selectable candidates, and
/// the source row owns one shared Wanna / Check In state.
struct PlaceImportCanonicalReviewScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchIDs: [String]
    let onDone: () -> Void

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var saveRoute: CanonicalImportSaveRoute?
    @State private var expandedMatchItemIDs: Set<String> = []
    @State private var isCommitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                if processingCount > 0 {
                    processingContent
                } else if displayItems.isEmpty {
                    ContentUnavailableView(
                        "No places matched",
                        systemImage: "mappin.slash",
                        description: Text("Nothing from this import is ready to add.")
                    )
                } else {
                    reviewHeader
                    applyToAllControls

                    if !readyItems.isEmpty {
                        importSection("Ready to add") {
                            ForEach(readyItems) { item in
                                resolvedPlaceCard(item)
                            }
                        }
                    }

                    if !possibleMatchItems.isEmpty {
                        importSection("Possible matches") {
                            ForEach(possibleMatchItems) { item in
                                possibleMatchesCard(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 94)
        }
        .scrollDismissesKeyboard(.interactively)
        .wanderScreen()
        .navigationTitle("Review places")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingCommitButton
        }
        .sheet(item: $saveRoute, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { route in
            MapPlaceSaveFlowSheet(context: route.context) { submission in
                await saveOptionalDetails(submission, route: route)
            } onRemove: { _ in
                false
            }
            .environmentObject(store)
        }
        .task(id: selectionPreparationSignature) {
            importStore.prepareCandidateSelections(batchIDs: batchIDs)
            importStore.reconcileDuplicates(with: existingPlaces)
            expandedMatchItemIDs.formUnion(possibleMatchItems.map(\.id))
        }
    }

    private var reviewHeader: some View {
        Text("\(displayItems.count) places matched and ready")
            .font(WanderTypography.editorialMajorSectionTitle)
            .foregroundStyle(WanderTheme.textInk.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var processingContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            ProgressView()
                .controlSize(.large)
                .tint(WanderTheme.terracotta.color)
            Text("Matching your places")
                .font(WanderTypography.editorialMajorSectionTitle)
            Text("\(processingCount) still processing")
                .font(WanderTypography.body)
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var applyToAllControls: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: WanderTheme.spacing1) {
                Text("Apply to all")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: WanderTheme.spacing2) {
                    masterStatusControl(.wannaGo, label: "Wanna")
                    masterStatusControl(.been, label: "Check In")
                }
            }
            .frame(width: 100)
            // Match the card's inner trailing inset so the master controls
            // form two clean vertical columns with every place row.
            .padding(.trailing, WanderTheme.spacing3)
        }
    }

    private func masterStatusControl(_ status: PlaceStatus, label: String) -> some View {
        VStack(spacing: 3) {
            importStatusButton(
                status,
                isSelected: selectedItems.count == displayItems.count
                    && selectedItems.allSatisfy { $0.stagedStatus == status }
            ) {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    importStore.setIncludedInImport(true, itemIDs: displayItems.map(\.id))
                    importStore.setStagedStatus(status, itemIDs: displayItems.map(\.id))
                    for item in displayItems where item.selectedCandidates.isEmpty {
                        if let candidateID = item.candidates.first?.id {
                            importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                        }
                    }
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 46)
    }

    private func importSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(WanderTypography.editorialSectionTitle)
                .foregroundStyle(WanderTheme.textInk.color)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: WanderTheme.spacing3) {
                content()
            }
        }
    }

    private func resolvedPlaceCard(_ item: PlaceImportItem) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing3) {
                CanonicalImportThumbnail(item: item, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(WanderTypography.editorialNamedContent)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    if let area = item.displayArea {
                        Text(area)
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rowStatusControls(item)
            }

            Button {
                beginDetails(item, candidate: item.selectedCandidate)
            } label: {
                Label("Add details", systemImage: "chevron.down")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .disabled(item.selectedCandidate == nil)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }

    private func possibleMatchesCard(_ item: PlaceImportItem) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.seed.nameHint ?? item.displayName)
                        .font(WanderTypography.editorialNamedContent)
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("Select every place you want")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rowStatusControls(item)
            }

            Button {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    if expandedMatchItemIDs.contains(item.id) {
                        expandedMatchItemIDs.remove(item.id)
                    } else {
                        expandedMatchItemIDs.insert(item.id)
                    }
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                    Text("Possible matches")
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.textInk.color)
                    Spacer(minLength: 0)
                    Text("\(min(item.candidates.count, 5))")
                        .font(WanderTypography.metadata.weight(.bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Image(systemName: expandedMatchItemIDs.contains(item.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .frame(minHeight: WanderTheme.tapMinimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expandedMatchItemIDs.contains(item.id) ? "Expanded" : "Collapsed")

            if expandedMatchItemIDs.contains(item.id) {
                VStack(spacing: 0) {
                    ForEach(Array(item.candidates.prefix(5).enumerated()), id: \.element.id) { index, candidate in
                        candidateRow(candidate, item: item, isBestMatch: index == 0)
                        if candidate.id != item.candidates.prefix(5).last?.id {
                            Divider()
                                .overlay(WanderTheme.borderHairline.color)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(WanderTheme.surfaceSand.color.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                beginDetails(item, candidate: item.selectedCandidate)
            } label: {
                Label("Add details", systemImage: "chevron.down")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .disabled(item.selectedCandidate == nil)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }

    private func candidateRow(
        _ candidate: PlaceCandidate,
        item: PlaceImportItem,
        isBestMatch: Bool
    ) -> some View {
        let isSelected = item.selectedCandidateIDs.contains(candidate.id)
        return Button {
            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                importStore.toggleCandidateSelection(itemID: item.id, candidateID: candidate.id)
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color)
                    .frame(width: 36, height: WanderTheme.tapMinimum)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: WanderTheme.spacing1) {
                        Text(candidate.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)
                        if isBestMatch {
                            Text("Best match")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(WanderTheme.terracottaDark.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(WanderTheme.terracottaTint.color)
                                .clipShape(Capsule())
                        }
                    }
                    Text(candidateArea(candidate))
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, WanderTheme.spacing2)
            .frame(minHeight: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.name), \(isSelected ? "selected" : "not selected")")
    }

    private func rowStatusControls(_ item: PlaceImportItem) -> some View {
        HStack(spacing: WanderTheme.spacing2) {
            importStatusButton(
                .wannaGo,
                isSelected: item.isSelectedForImport && item.stagedStatus == .wannaGo
            ) { toggleStatus(.wannaGo, item: item) }
            importStatusButton(
                .been,
                isSelected: item.isSelectedForImport && item.stagedStatus == .been
            ) { toggleStatus(.been, item: item) }
        }
        .frame(width: 100)
    }

    private func importStatusButton(
        _ status: PlaceStatus,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: status == .been ? "checkmark" : "bookmark.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? Color.white : statusColor(status))
                .background(isSelected ? statusColor(status) : Color.clear)
                .clipShape(Circle())
                .wanderGlassCapsule(tone: isSelected ? .selected : .neutral)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? "Check In" : "Wanna")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var floatingCommitButton: some View {
        WanderPrimaryButton(
            title: isCommitting ? "Adding…" : commitButtonTitle,
            systemImage: isCommitting ? nil : (selectedCandidateCount == 0 ? "xmark" : "arrow.down.circle.fill"),
            isDisabled: isCommitting,
            tone: .espressoConfirmation,
            action: commit
        )
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing2)
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 7)
    }

    private var commitButtonTitle: String {
        guard selectedCandidateCount > 0 else { return "Done" }
        return "Add \(selectedCandidateCount) place\(selectedCandidateCount == 1 ? "" : "s")"
    }

    private func toggleStatus(_ status: PlaceStatus, item: PlaceImportItem) {
        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
            if item.isSelectedForImport && item.stagedStatus == status {
                importStore.setIncludedInImport(false, itemID: item.id)
            } else {
                importStore.setIncludedInImport(true, itemID: item.id)
                importStore.setStagedStatus(status, itemID: item.id)
                if item.selectedCandidates.isEmpty, let candidateID = item.candidates.first?.id {
                    importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                }
            }
        }
    }

    private func beginDetails(_ item: PlaceImportItem, candidate: PlaceCandidate?) {
        guard let candidate else { return }
        let visiblePlace = MapPlaceSaveContext.currentUserSave(
            matching: candidate,
            in: store.currentUserVisiblePlaces
        )
        let context: MapPlaceSaveContext
        if let visiblePlace {
            if visiblePlace.userPlace.status == .been,
               let visit = store.visits(for: visiblePlace.userPlace.id).first {
                context = .editVisit(visit, visiblePlace: visiblePlace)
            } else {
                context = .editWant(
                    visiblePlace,
                    attributes: store.attributes(for: visiblePlace.userPlace.id)
                )
            }
        } else {
            context = .importCandidate(
                candidate,
                sourceType: item.source.canonicalAddSourceType,
                status: item.stagedStatus,
                defaultVisibility: store.effectiveDefaultVisibility,
                ratingScore: item.stagedRatingScore,
                note: item.stagedNote ?? ""
            )
        }
        store.saveFlowDidPresent(.saveSheet)
        saveRoute = CanonicalImportSaveRoute(
            itemID: item.id,
            candidateID: candidate.id,
            context: context
        )
    }

    @MainActor
    private func saveOptionalDetails(
        _ submission: MapPlaceSaveSubmission,
        route: CanonicalImportSaveRoute
    ) async -> SaveResult? {
        guard let result = await persistAddPlaceSaveSubmission(
            submission,
            store: store,
            backend: nil
        ) else { return nil }
        importStore.setStagedStatus(submission.status, itemID: route.itemID)
        importStore.setStagedNote(submission.note, itemID: route.itemID)
        importStore.setStagedRatingScore(submission.ratingScore, itemID: route.itemID)
        importStore.setStagedVisitedAt(submission.visitedAt, itemID: route.itemID)
        importStore.setIncludedInImport(true, itemID: route.itemID)
        store.flushPersistence()
        return result
    }

    private func commit() {
        guard !isCommitting else { return }
        guard selectedCandidateCount > 0 else {
            dismissUnselectedRows()
            onDone()
            return
        }
        guard let expectedUserID = auth.state.session?.userID,
              expectedUserID == store.currentUser.id
        else {
            auth.presentGate(for: .syncPlace)
            return
        }

        isCommitting = true
        var receipts: [PlaceImportReceiptEntry] = []
        importStore.performBatchedMutations {
            for batch in scopedBatches {
                let batchItems = importStore.items(for: batch.id).filter { !$0.isSourceRetry }
                let destination = destinationList(for: batch, itemCount: batchItems.count)
                var entries: [PlaceImportReceiptEntry] = []

                for item in batchItems {
                    let selected = item.isSelectedForImport ? item.selectedCandidates : []
                    guard !selected.isEmpty else {
                        if ![.saved, .dismissed].contains(item.state) {
                            importStore.dismiss(itemID: item.id)
                        }
                        continue
                    }

                    var lastUserPlaceID: String?
                    for candidate in selected {
                        let existing = store.existingImportSave(matching: candidate)
                        let status = item.stagedStatus
                        let result = store.saveImportedCandidate(
                            candidate,
                            status: status,
                            visibility: .selfOnly,
                            note: item.stagedNote,
                            sourceType: item.source.canonicalAddSourceType,
                            ratingScore: status == .been ? item.stagedRatingScore : nil,
                            visitedAt: item.stagedVisitedAt ?? .now
                        )
                        if let destination {
                            _ = store.addCurrentUserPlace(userPlaceID: result.userPlaceID, to: destination)
                        }
                        lastUserPlaceID = result.userPlaceID
                        entries.append(
                            PlaceImportReceiptEntry(
                                itemID: item.id,
                                displayName: candidate.name,
                                displayArea: candidateArea(candidate),
                                status: status,
                                outcome: existing == nil ? .added : .existing,
                                userPlaceID: result.userPlaceID
                            )
                        )
                    }
                    if let lastUserPlaceID {
                        importStore.markSaved(itemID: item.id, userPlaceID: lastUserPlaceID)
                    }
                }

                importStore.recordReceipt(
                    batchID: batch.id,
                    entries: entries,
                    destinationListID: destination?.id
                )
                receipts.append(contentsOf: entries)
            }
        }
        store.flushPersistence()
        isCommitting = false
        onDone()

        guard auth.isSignedIn, !receipts.isEmpty else { return }
        Task { @MainActor in
            _ = await store.syncUnsyncedOwnPlaces(backend: backend)
            _ = await store.syncPendingPlaceLists(backend: backend)
        }
    }

    private func dismissUnselectedRows() {
        for item in scopedItems where ![.saved, .dismissed].contains(item.state) {
            importStore.dismiss(itemID: item.id)
        }
    }

    private func destinationList(for batch: PlaceImportBatch, itemCount: Int) -> LocalPlaceList? {
        guard batch.source == .googleMaps, batch.sourceName != nil || itemCount > 1 else { return nil }
        if let listID = batch.destinationListID,
           let existing = store.visiblePlaceLists.first(where: { $0.id == listID }) {
            return existing
        }
        let existingNames = Set(
            store.visiblePlaceLists
                .filter { $0.ownerUserID == store.currentUser.id }
                .map(\.name)
        )
        let name = PlaceImportDestinationListName.unique(batch.sourceName, existingNames: existingNames)
        guard let list = store.createPlaceList(
            name: name,
            description: "Imported from Google Maps",
            visibility: .stealth
        ) else { return nil }
        importStore.setDestinationListID(list.id, batchID: batch.id)
        return list
    }

    private var scopedBatches: [PlaceImportBatch] {
        let ids = Set(batchIDs)
        return importStore.batches.filter { ids.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
    }

    private var scopedItems: [PlaceImportItem] {
        let ids = Set(batchIDs)
        return importStore.items.filter { ids.contains($0.batchID) }
    }

    private var displayItems: [PlaceImportItem] {
        scopedItems.filter {
            !$0.isSourceRetry
                && !$0.candidates.isEmpty
                && ![.saved, .dismissed].contains($0.state)
        }
    }

    private var readyItems: [PlaceImportItem] {
        displayItems.filter { $0.candidates.count == 1 }
    }

    private var possibleMatchItems: [PlaceImportItem] {
        displayItems.filter { $0.candidates.count > 1 }
    }

    private var selectedItems: [PlaceImportItem] {
        displayItems.filter { $0.isSelectedForImport && !$0.selectedCandidates.isEmpty }
    }

    private var selectedCandidateCount: Int {
        selectedItems.reduce(0) { $0 + $1.selectedCandidates.count }
    }

    private var processingCount: Int {
        scopedItems.filter { [.queued, .resolving].contains($0.state) }.count
    }

    private var selectionPreparationSignature: String {
        scopedItems.map { "\($0.id):\($0.state.rawValue):\($0.candidates.count)" }.joined(separator: "|")
    }

    private var existingPlaces: [PlaceImportExistingPlace] {
        store.currentUserVisiblePlaces.map { visible in
            PlaceImportExistingPlace(
                userPlaceID: visible.userPlace.id,
                name: visible.place.canonicalName,
                latitude: visible.place.latitude,
                longitude: visible.place.longitude,
                sourceProvider: visible.place.sourceProvider,
                sourceProviderPlaceID: visible.place.sourceProviderPlaceID
            )
        }
    }

    private func candidateArea(_ candidate: PlaceCandidate) -> String {
        [candidate.locality, candidate.region]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
            .nonEmpty ?? candidate.address ?? "Apple Maps place"
    }

    private func statusColor(_ status: PlaceStatus) -> Color {
        status == .been ? WanderTheme.stateSuccess.color : WanderTheme.terracotta.color
    }
}

private struct CanonicalImportThumbnail: View {
    let item: PlaceImportItem
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .fill(item.source.canonicalTint)
            WanderCategoryEmoji(
                emoji: item.selectedCandidate?.categoryEmoji ?? item.candidates.first?.categoryEmoji ?? "📍",
                size: max(22, size * 0.44)
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .accessibilityHidden(true)
    }
}

extension PlaceImportSource {
    var canonicalAddSourceType: AddSourceType {
        switch self {
        case .googleMaps, .instagram, .tiktok: .link
        case .textNotes: .manual
        }
    }

    var canonicalTint: Color {
        switch self {
        case .googleMaps: WanderTheme.skyTint.color
        case .instagram: WanderTheme.terracottaTint.color
        case .tiktok: WanderTheme.surfaceSand.color
        case .textNotes: WanderTheme.categorySage.color.opacity(0.24)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct PlaceImportHistoryScreen: View {
    @ObservedObject var importStore: PlaceImportStore

    private let columns = [
        GridItem(.flexible(), spacing: WanderTheme.spacing3),
        GridItem(.flexible(), spacing: WanderTheme.spacing3)
    ]

    var body: some View {
        Group {
            if historyBatches.isEmpty {
                ContentUnavailableView(
                    "No import history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Links you import will appear here with their full report.")
                )
                .wanderScreen()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: WanderTheme.spacing4) {
                        ForEach(historyBatches) { batch in
                            NavigationLink {
                                PlaceImportHistoryDestination(
                                    importStore: importStore,
                                    batchID: batch.id
                                )
                            } label: {
                                PlaceImportHistoryTile(
                                    batch: batch,
                                    items: importStore.items(for: batch.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(WanderTheme.spacing4)
                }
                .wanderScreen()
            }
        }
        .navigationTitle("Import history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyBatches: [PlaceImportBatch] {
        importStore.batches.sorted { $0.createdAt > $1.createdAt }
    }
}

private struct PlaceImportHistoryDestination: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if importStore.batches.first(where: { $0.id == batchID })?.receipt != nil {
            PlaceImportReportScreen(importStore: importStore, batchID: batchID)
        } else {
            PlaceImportCanonicalReviewScreen(
                importStore: importStore,
                batchIDs: [batchID],
                onDone: { dismiss() }
            )
        }
    }
}

private struct PlaceImportHistoryTile: View {
    let batch: PlaceImportBatch
    let items: [PlaceImportItem]

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            PlaceImportHistoryArtwork(batch: batch, items: items)
                .frame(maxWidth: .infinity)
                .frame(height: 184)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                }

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: batch.source.canonicalSystemImage)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(batch.source.canonicalAccent)
                Text(batch.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(placeCount)")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.textInk.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(batch.source.canonicalName) import, \(placeCount) places")
    }

    private var placeCount: Int {
        batch.receipt?.entries.count ?? items.filter { !$0.isSourceRetry }.count
    }
}

private struct PlaceImportHistoryArtwork: View {
    let batch: PlaceImportBatch
    let items: [PlaceImportItem]

    var body: some View {
        ZStack {
            batch.source.canonicalTint
            sourceArtwork

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Spacer()
                    Image(systemName: batch.source.canonicalSystemImage)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.48), in: Circle())
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Text(batch.receipt == nil ? "Ready to review" : "\(placeCount) places")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .padding(WanderTheme.spacing3)
        }
        .clipped()
    }

    private var artItems: [PlaceImportItem] {
        let result = items.filter { !$0.isSourceRetry }
        return result.isEmpty ? items : result
    }

    @ViewBuilder
    private var sourceArtwork: some View {
        if let sourceArtworkURL {
            AsyncImage(url: sourceArtworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    @ViewBuilder
    private var fallbackArtwork: some View {
        if batch.source == .googleMaps {
            Image("OnboardingMapDiary")
                .resizable()
                .scaledToFill()
        } else {
            GeometryReader { proxy in
                let columns = [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(artItems.prefix(4))) { item in
                        ZStack {
                            item.source.canonicalTint
                            WanderCategoryEmoji(
                                emoji: item.selectedCandidate?.categoryEmoji
                                    ?? item.candidates.first?.categoryEmoji
                                    ?? "📍",
                                size: 30
                            )
                        }
                        .frame(height: (proxy.size.height - 2) / 2)
                    }
                }
            }
        }
    }

    private var sourceArtworkURL: URL? {
        artItems.lazy
            .compactMap(\.seed.sourceThumbnailURLString)
            .compactMap(URL.init(string:))
            .first
    }

    private var placeCount: Int {
        batch.receipt?.entries.count ?? artItems.count
    }
}

private struct ImportReportSaveRoute: Identifiable {
    let id = UUID()
    let context: MapPlaceSaveContext
}

struct PlaceImportReportScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchID: String

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var saveRoute: ImportReportSaveRoute?
    @State private var copiedLink = false

    var body: some View {
        Group {
            if let batch, let receipt = batch.receipt {
                ScrollView {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        PlaceImportHistoryArtwork(batch: batch, items: items)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

                        sourceLinkCard(batch: batch)

                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("Places")
                                .font(WanderTypography.editorialSectionTitle)
                            ForEach(receipt.entries) { entry in
                                reportRow(entry)
                            }
                        }
                    }
                    .padding(WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing6)
                }
                .wanderScreen()
            } else {
                ContentUnavailableView(
                    "Report unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This import has not been completed yet.")
                )
                .wanderScreen()
            }
        }
        .navigationTitle("Import report")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $saveRoute, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { route in
            MapPlaceSaveFlowSheet(context: route.context) { submission in
                let result = await persistAddPlaceSaveSubmission(
                    submission,
                    store: store,
                    backend: nil
                )
                beginBackgroundSyncIfPossible()
                return result
            } onRemove: { context in
                let removed = await removeHistoricalSave(context)
                if removed { beginBackgroundSyncIfPossible() }
                return removed
            }
            .environmentObject(store)
        }
    }

    private func sourceLinkCard(batch: PlaceImportBatch) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: batch.source.canonicalSystemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(batch.source.canonicalAccent)
                .frame(width: 40, height: 40)
                .background(batch.source.canonicalTint, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(batch.source.canonicalName)
                    .font(WanderTypography.editorialNamedContent)
                Text(batch.createdAt.formatted(date: .long, time: .shortened))
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let sourceURL {
                Button {
                    UIPasteboard.general.string = sourceURL
                    copiedLink = true
                } label: {
                    Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15, weight: .black))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .wanderGlassCapsule(tone: copiedLink ? .selected : .neutral)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copiedLink ? "Link copied" : "Copy source link")
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func reportRow(_ entry: PlaceImportReceiptEntry) -> some View {
        let visible = visiblePlace(for: entry)
        return VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .fill(batch?.source.canonicalTint ?? WanderTheme.surfaceSand.color)
                    WanderCategoryEmoji(
                        emoji: visible?.categoryEmoji ?? "📍",
                        size: 25
                    )
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visible?.place.canonicalName ?? entry.displayName)
                        .font(WanderTypography.editorialNamedContent)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text(entry.displayArea ?? "Saved place")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let visible {
                    HStack(spacing: WanderTheme.spacing2) {
                        reportStatusButton(.wannaGo, visible: visible)
                        reportStatusButton(.been, visible: visible)
                    }
                    .frame(width: 100)
                }
            }

            if let visible {
                HStack(spacing: WanderTheme.spacing3) {
                    if let listName = destinationListName {
                        Label(listName, systemImage: "list.bullet")
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        beginDetails(visible)
                    } label: {
                        Label("Add details", systemImage: "slider.horizontal.3")
                            .font(WanderTypography.label)
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }

    private func reportStatusButton(_ status: PlaceStatus, visible: VisiblePlace) -> some View {
        let selected = visible.userPlace.status == status
        return Button {
            guard !selected else { return }
            _ = store.changeImportedSaveStatus(
                userPlaceID: visible.userPlace.id,
                to: status,
                visitedAt: .now
            )
            beginBackgroundSyncIfPossible()
        } label: {
            Image(systemName: status == .been ? "checkmark" : "bookmark.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.white : reportStatusColor(status))
                .background(selected ? reportStatusColor(status) : Color.clear)
                .clipShape(Circle())
                .wanderGlassCapsule(tone: selected ? .selected : .neutral)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? "Check In" : "Wanna")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func beginDetails(_ visible: VisiblePlace) {
        let context: MapPlaceSaveContext
        if visible.userPlace.status == .been,
           let visit = store.visits(for: visible.userPlace.id).first {
            context = .editVisit(visit, visiblePlace: visible)
        } else {
            context = .editWant(
                visible,
                attributes: store.attributes(for: visible.userPlace.id)
            )
        }
        store.saveFlowDidPresent(.saveSheet)
        saveRoute = ImportReportSaveRoute(context: context)
    }

    @MainActor
    private func removeHistoricalSave(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            return await store.deleteVisit(visitID: visit.id, backend: nil)
        case .editWant(let visible):
            return store.removeSave(userPlaceID: visible.userPlace.id) != nil
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }

    private func beginBackgroundSyncIfPossible() {
        guard case .signedIn = auth.state else { return }
        Task { @MainActor in
            _ = await store.syncUnsyncedOwnPlaces(backend: backend)
            _ = await store.syncPendingPlaceLists(backend: backend)
        }
    }

    private var batch: PlaceImportBatch? {
        importStore.batches.first(where: { $0.id == batchID })
    }

    private var items: [PlaceImportItem] {
        importStore.items(for: batchID)
    }

    private var sourceURL: String? {
        items.lazy.compactMap(\.seed.sourceURLString).first
    }

    private func visiblePlace(for entry: PlaceImportReceiptEntry) -> VisiblePlace? {
        guard let userPlaceID = entry.userPlaceID else { return nil }
        return store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlaceID }
    }

    private var destinationListName: String? {
        guard let listID = batch?.receipt?.destinationListID else { return nil }
        return store.visiblePlaceLists.first(where: { $0.id == listID })?.name
    }

    private func reportStatusColor(_ status: PlaceStatus) -> Color {
        status == .been ? WanderTheme.stateSuccess.color : WanderTheme.terracotta.color
    }
}

private extension PlaceImportSource {
    var canonicalName: String {
        switch self {
        case .googleMaps: "Google Maps"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .textNotes: "Notes"
        }
    }

    var canonicalSystemImage: String {
        switch self {
        case .googleMaps: "map.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .textNotes: "note.text"
        }
    }

    var canonicalAccent: Color {
        switch self {
        case .googleMaps: WanderTheme.stateInfo.color
        case .instagram: WanderTheme.terracotta.color
        case .tiktok: WanderTheme.textInk.color
        case .textNotes: WanderTheme.categoryMoss.color
        }
    }
}

struct PlaceImportSaveSyncBanner: View {
    let notice: PlaceImportSaveSyncNotice
    let isOffline: Bool
    let retryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: notice.kind == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "iphone.and.arrow.forward")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(notice.kind == .failed ? WanderTheme.stateError.color : WanderTheme.terracottaDark.color)
                .frame(width: 40, height: 40)
                .background(
                    (notice.kind == .failed ? WanderTheme.stateError.color : WanderTheme.terracotta.color)
                        .opacity(0.12)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if notice.kind == .failed {
                Button("Retry", action: retryAction)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }

            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(width: 32, height: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, WanderTheme.spacing3)
        .padding(.trailing, WanderTheme.spacing1)
        .padding(.vertical, WanderTheme.spacing2)
        .wanderGlassPanel(cornerRadius: WanderTheme.radiusMedium, tone: .neutral)
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
    }

    private var title: String {
        if notice.kind == .failed {
            return "\(notice.count) place\(notice.count == 1 ? "" : "s") still need saving"
        }
        return "Saved on this phone"
    }

    private var detail: String {
        if notice.kind == .failed {
            return "Your places and choices are safe. Retry when you’re ready."
        }
        if isOffline {
            return "\(notice.count) place\(notice.count == 1 ? "" : "s") will sync when you’re back online."
        }
        return "Syncing \(notice.count) place\(notice.count == 1 ? "" : "s") in the background."
    }
}
