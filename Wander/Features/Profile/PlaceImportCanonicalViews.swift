import SwiftUI
import UIKit

private struct FinishPlaceImportKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

private struct RestartPlaceImportKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var finishPlaceImport: (() -> Void)? {
        get { self[FinishPlaceImportKey.self] }
        set { self[FinishPlaceImportKey.self] = newValue }
    }

    var restartPlaceImport: @MainActor @Sendable () -> Void {
        get { self[RestartPlaceImportKey.self] }
        set { self[RestartPlaceImportKey.self] = newValue }
    }
}

private struct ImportListSelectionRequest: Identifiable {
    let id = UUID()
    let itemIDs: [String]
    let targets: [MapPlaceListTarget]
}

/// One import report keeps actionable matches above saved places. Status actions
/// stay staged until Save; list membership is independent of Wanna / Check In.
struct PlaceImportCanonicalReviewScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchIDs: [String]
    let onDone: () -> Void
    var initiallyExpandedDetailItemID: String? = nil

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.restartPlaceImport) private var restartPlaceImport
    @Environment(\.finishPlaceImport) private var finishPlaceImport
    @State private var expandedMatchItemIDs: Set<String> = []
    @State private var expandedDetailItemIDs: Set<String> = []
    @State private var detailDrafts: [String: PlaceSaveDraft] = [:]
    @State private var stagedDetailSubmissions: [String: MapPlaceSaveSubmission] = [:]
    @State private var isCommitting = false
    @State private var commitTask: Task<Void, Never>?
    @State private var showsCommitError = false
    @State private var commitErrorMessage = "A place’s details could not be saved. Review its details and try again. Any places already saved are safe."
    @State private var didExpandInitialDetails = false
    @State private var rescueItem: PlaceImportItem?
    @State private var listRequest: ImportListSelectionRequest?
    @State private var pendingStatuses: [String: PlaceStatus] = [:]
    @State private var pendingLists: [String: Set<String>] = [:]
    @State private var pendingRemovals: [String: PlaceImportSavedSelectionRemoval] = [:]
    @State private var didReconcileExisting = false
    @State private var privateDetailsWarningCount = 0
    @State private var showsSavedDetailsWarning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                ForEach(scopedBatches) { batch in
                    ImportSourceHeader(importStore: importStore, batch: batch, items: importStore.items(for: batch.id))
                }
                if processingCount > 0 {
                    processingContent
                } else if displayItems.isEmpty && recoveryItems.isEmpty && scopedBatches.allSatisfy({ $0.receipt == nil }) {
                    ContentUnavailableView(
                        "No places matched",
                        systemImage: "mappin.slash",
                        description: Text("Nothing from this import is ready to add.")
                    )
                } else {
                    if !displayItems.isEmpty { reviewHeader }
                    if !readyItems.isEmpty {
                        importSection("Ready to add", showsBulkControls: true) {
                            ForEach(readyItems) { item in
                                resolvedPlaceCard(item)
                            }
                        }
                    }

                    if !possibleMatchItems.isEmpty {
                        importSection("Possible matches", showsBulkControls: readyItems.isEmpty) {
                            ForEach(possibleMatchItems) { item in
                                possibleMatchesCard(item)
                            }
                        }
                    }
                }
                ForEach(scopedBatches) { batch in
                    PlaceImportReportScreen(importStore: importStore, batchID: batch.id, savedOnly: true,
                        pendingStatuses: pendingStatuses, pendingLists: pendingLists,
                        pendingRemovals: pendingRemovals,
                        onStageStatus: { entryID, status in
                            pendingStatuses[entryID] = status
                        },
                        onClearStagedStatus: { entryID in
                            pendingStatuses.removeValue(forKey: entryID)
                            stagedDetailSubmissions.removeValue(forKey: entryID)
                            for id in Array(pendingRemovals.keys) where id == entryID {
                                pendingRemovals[id]?.status = nil
                                pendingRemovals[id]?.visitID = nil
                                pendingRemovals[id]?.wannaID = nil
                                if pendingRemovals[id]?.listIDs.isEmpty == true { pendingRemovals.removeValue(forKey: id) }
                            }
                        },
                        onStageRemoval: { entryID, removal in
                            if removal.status == nil && removal.listIDs.isEmpty {
                                pendingRemovals.removeValue(forKey: entryID)
                            } else { pendingRemovals[entryID] = removal }
                            if removal.status != nil {
                                pendingStatuses.removeValue(forKey: entryID)
                                stagedDetailSubmissions.removeValue(forKey: entryID)
                            }
                            if !removal.listIDs.isEmpty { pendingLists.removeValue(forKey: entryID) }
                        },
                        onStageDetails: { entryID, submission in
                            stagedDetailSubmissions[entryID] = submission
                            pendingStatuses[entryID] = submission.status
                        },
                        onChooseLists: { entryID in
                            chooseSavedLists(entryID: entryID)
                        })
                }
                if processingCount == 0 {
                    ForEach(scopedBatches) { batch in
                        recoveryFooter(batch)
                    }
                }
            }
            .disabled(isCommitting)
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing6)
        }
        .scrollDismissesKeyboard(.interactively)
        .astirScreen()
        .navigationTitle("Import report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCommitting)
        .interactiveDismissDisabled(isCommitting)
        .safeAreaInset(edge: .top, spacing: 0) {
            if privateDetailsWarningCount > 0 {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Check-ins saved")
                            .font(AstirTypography.control)
                        Spacer(minLength: WanderTheme.spacing2)
                        Button("Dismiss") { privateDetailsWarningCount = 0 }
                            .font(AstirTypography.control)
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    Text(privateDetailsWarningCount == 1
                         ? "One check-in’s private answers couldn’t be stored on this device. The check-in was saved."
                         : "Private answers for \(privateDetailsWarningCount) check-ins couldn’t be stored on this device. The check-ins were saved.")
                        .font(AstirTypography.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(brandMode.primaryText)
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brandMode.recessedBackground)
                .accessibilityIdentifier("import.privateDetailsWarning")
            }
        }
        .sheet(item: $rescueItem) { item in
            PlaceImportRescueScreen(
                item: item,
                searchAction: { name, area in
                    await importStore.previewManualSearch(itemID: item.id, name: name, area: area)
                },
                confirmationAction: { name, area, candidates, selectedCandidateID in
                    importStore.confirmManualSearch(
                        itemID: item.id, name: name, area: area,
                        candidates: candidates, selectedCandidateID: selectedCandidateID
                    )
                }
            )
        }
        .sheet(item: $listRequest) { request in
            if let first = request.targets.first {
                MapPlaceListPickerSheet(target: first, additionalTargets: Array(request.targets.dropFirst()),
                    stagedListIDs: request.itemIDs.reduce(nil as Set<String>?) { result, id in
                        result.map { $0.intersection(pendingLists[id] ?? []) } ?? (pendingLists[id] ?? [])
                    } ?? [],
                    onStage: { listIDs in
                        for id in request.itemIDs { pendingLists[id] = listIDs }
                    }, analyticsSurface: "import") { _ in }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if processingCount == 0 && (!displayItems.isEmpty || !pendingItemIDs.isEmpty) {
                WanderPrimaryButton(title: isCommitting ? "Saving…" : "Save",
                    isDisabled: isCommitting || pendingItemIDs.isEmpty,
                    tone: .espressoConfirmation,
                    action: { commit(itemIDs: pendingItemIDs) })
                    .accessibilityIdentifier("import.save")
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.vertical, WanderTheme.spacing2)
                    .background(brandMode.background)
            }
        }
        .alert("Couldn’t add places", isPresented: $showsCommitError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(commitErrorMessage)
        }
        .alert("Check-ins saved", isPresented: $showsSavedDetailsWarning) {
            Button("Done") { (finishPlaceImport ?? onDone)() }
        } message: {
            Text("Your check-ins were saved, but some private answers couldn’t be stored on this device.")
        }
        .task {
            importStore.resumePendingImports()
            for entry in scopedBatches.flatMap({ $0.receipt?.entries ?? [] }) {
                if let removal = entry.unfinishedRemoval {
                    pendingRemovals[entry.id] = removal
                    if entry.status != removal.status { pendingStatuses[entry.id] = entry.status }
                }
            }
        }
        .task(id: selectionPreparationSignature) {
            if processingCount == 0 {
                importStore.markReviewOpened(batchIDs: batchIDs)
                for receipt in scopedBatches.compactMap(\.receipt) where receipt.presentedAt == nil {
                    importStore.markReceiptPresented(receiptID: receipt.id)
                }
            }
            importStore.prepareCandidateSelections(batchIDs: batchIDs)
            importStore.reconcileDuplicates(with: existingPlaces)
            if !didReconcileExisting {
                didReconcileExisting = true
                reconcileListSaves()
            }
            expandedMatchItemIDs.formUnion(possibleMatchItems.map(\.id))
            if !didExpandInitialDetails,
               let item = displayItems.first(where: { $0.id == initiallyExpandedDetailItemID }) {
                didExpandInitialDetails = true
                toggleDetails(item, candidate: item.selectedCandidate)
            }
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
            isCommitting = false
        }
    }

    private var reviewHeader: some View {
        Text("\(displayItems.count) \(displayItems.count == 1 ? "place" : "places") matched and ready")
            .font(AstirTypography.sheetTitle)
            .foregroundStyle(brandMode.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var processingContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Text("Matching your places")
                .font(AstirTypography.sheetTitle)
            ImportMatchingProgressBar(progress: matchingProgress, reduceMotion: reduceMotion)
                .frame(height: 20)
                .accessibilityHidden(true)
            Text(matchingProgress.label)
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.secondaryText)
                .monospacedDigit()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.matching-progress")
    }

    private var matchingProgress: PlaceImportMatchingProgress {
        importStore.matchingProgress(batchIDs: batchIDs)
    }

    private var applyToAllControls: some View {
        VStack(spacing: WanderTheme.spacing1) {
            Text("Apply to all")
                .font(AstirTypography.label)
                .foregroundStyle(brandMode.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: WanderTheme.spacing2) {
                masterStatusControl(.wannaGo, label: "Wanna")
                masterStatusControl(.been, label: "Check In")
                VStack(spacing: 3) {
                    listButton(items: scopedItems.filter { !$0.isSourceRetry })
                    Text("List").font(AstirTypography.metadata)
                }
            }
        }
        .frame(width: 148)
        .disabled(isCommitting)
        // Match the card's inner trailing inset so the master controls
        // align with the three actions on each place row.
        .padding(.trailing, WanderTheme.spacing3)
    }

    private var pendingItemIDs: Set<String> {
        let itemByEntry = Dictionary(uniqueKeysWithValues: scopedBatches.flatMap { $0.receipt?.entries ?? [] }
            .map { ($0.id, $0.itemID) })
        let actionIDs = Set(pendingStatuses.keys).union(pendingLists.filter { !$0.value.isEmpty }.keys)
        return Set(actionIDs.map { itemByEntry[$0] ?? $0 }).union(pendingRemovals.values.map(\.itemID))
    }

    private func masterStatusControl(_ status: PlaceStatus, label: String) -> some View {
        VStack(spacing: 3) {
            importStatusButton(status, isSelected: !displayItems.isEmpty && displayItems.allSatisfy { pendingStatuses[$0.id] == status }) {
                for item in displayItems {
                    stageStatus(status, item: item)
                }
            }
            .accessibilityIdentifier(status == .been ? "import.all.checkin" : "import.all.wanna")
            Text(label).font(AstirTypography.metadata).foregroundStyle(brandMode.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(width: 46)
    }

    private func importSection<Content: View>(
        _ title: String,
        showsBulkControls: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            if showsBulkControls {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
                        sectionTitle(title).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        applyToAllControls
                    }
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        sectionTitle(title)
                        applyToAllControls.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                sectionTitle(title)
            }
            VStack(spacing: WanderTheme.spacing3) {
                content()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AstirTypography.sectionTitle)
            .foregroundStyle(brandMode.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func recoveryFooter(_ batch: PlaceImportBatch) -> some View {
        let coverage = PlaceImportReportCoverage(batch: batch, items: scopedItems)
        switch coverage.footer {
        case .none:
            EmptyView()
        case .failed:
            ImportRetryContent {
                for item in recoveryItems where item.batchID == batch.id {
                    importStore.retry(itemID: item.id)
                }
            }
        case .partial:
            VStack(spacing: WanderTheme.spacing3) {
                Text("We weren't able to resolve all places")
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .multilineTextAlignment(.center)
                Text("\(coverage.matchedCount) of \(coverage.totalCount) places have matches. You can still save them.")
                    .font(AstirTypography.body)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
                if let sourceURL = scopedItems.first(where: {
                    $0.batchID == batch.id && $0.seed.sourceURLString != nil
                })?.seed.sourceURLString {
                    Button {
                        UIPasteboard.general.string = sourceURL
                        restartPlaceImport()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(AstirTypography.control)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(brandMode.accentForeground)
                            .background(brandMode.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Copies the source link and opens Import places. Saved places stay safe.")
                    .accessibilityIdentifier("import.try-again")
                }
            }
            .padding(.vertical, WanderTheme.spacing3)
        }
    }

    private func resolvedPlaceCard(_ item: PlaceImportItem) -> some View {
        ImportPlaceCard(name: item.displayName, area: item.displayArea) {
            CanonicalImportThumbnail(item: item, size: 58)
        } actions: {
            cardActions(item)
        } details: {
            if detailDrafts[item.id] != nil {
                inlineDetails(item)
                    .frame(height: expandedDetailItemIDs.contains(item.id) ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(expandedDetailItemIDs.contains(item.id) ? 1 : 0)
                    .accessibilityHidden(!expandedDetailItemIDs.contains(item.id))
            }
        }
        .accessibilityIdentifier("import.ready-card.\(item.id)")
    }

    private func possibleMatchesCard(_ item: PlaceImportItem) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.seed.nameHint ?? item.displayName)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text("Select every place you want")
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundStyle(brandMode.accentText)
                    Text("Possible matches")
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.primaryText)
                    Spacer(minLength: 0)
                    Text("\(min(item.candidates.count, 5))")
                        .font(AstirTypography.metadata.weight(.bold))
                        .foregroundStyle(brandMode.secondaryText)
                    Image(systemName: expandedMatchItemIDs.contains(item.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(brandMode.secondaryText.opacity(0.72))
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
                                .overlay(brandMode.border)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(brandMode.recessedBackground.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            cardActions(item)

            if detailDrafts[item.id] != nil {
                inlineDetails(item)
                    .frame(height: expandedDetailItemIDs.contains(item.id) ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(expandedDetailItemIDs.contains(item.id) ? 1 : 0)
                    .accessibilityHidden(!expandedDetailItemIDs.contains(item.id))
            }
        }
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(brandMode.border, lineWidth: 1)
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
                    .foregroundStyle(isSelected ? brandMode.accent : brandMode.border)
                    .frame(width: 36, height: WanderTheme.tapMinimum)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: WanderTheme.spacing1) {
                        Text(candidate.name)
                            .font(AstirTypography.cardTitle)
                            .foregroundStyle(brandMode.primaryText)
                            .lineLimit(1)
                        if isBestMatch {
                            Text("Best match")
                                .font(AstirTypography.metadata)
                                .foregroundStyle(brandMode.accentText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(WanderTheme.terracottaTint.color)
                                .clipShape(Capsule())
                        }
                    }
                    Text(candidateArea(candidate))
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
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

    private func cardActions(_ item: PlaceImportItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WanderTheme.spacing2) {
                detailsButton(item).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                rowStatusControls(item)
            }
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                detailsButton(item)
                rowStatusControls(item).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func detailsButton(_ item: PlaceImportItem) -> some View {
        Button {
            toggleDetails(item, candidate: item.selectedCandidate)
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                Text("Add details")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expandedDetailItemIDs.contains(item.id) ? 180 : 0))
            }
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.accentText)
            .frame(minHeight: WanderTheme.tapMinimum)
        }
        .buttonStyle(.plain)
        .disabled(item.selectedCandidate == nil)
        .accessibilityIdentifier("import.details.\(item.id)")
    }

    private func rowStatusControls(_ item: PlaceImportItem) -> some View {
        HStack(spacing: WanderTheme.spacing2) {
            importStatusButton(
                .wannaGo,
                isSelected: pendingStatuses[item.id] == .wannaGo
            ) { toggleStatus(.wannaGo, item: item) }
            .accessibilityIdentifier("import.wanna.\(item.id)")
            importStatusButton(
                .been,
                isSelected: pendingStatuses[item.id] == .been
            ) { toggleStatus(.been, item: item) }
            .accessibilityIdentifier("import.checkin.\(item.id)")
            listButton(items: [item])
                .accessibilityIdentifier("import.list.\(item.id)")
        }
        .frame(width: 148)
        .disabled(isCommitting)
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
                .wanderGlassCapsule(
                    tone: status == .been ? .neutral : (isSelected ? .selected : .neutral)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? "Check In" : "Wanna")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func chooseSavedLists(entryID: String) {
        guard let entry = scopedBatches.flatMap({ $0.receipt?.entries ?? [] }).first(where: { $0.id == entryID }),
              let item = scopedItems.first(where: { $0.id == entry.itemID }) else { return }
        let target: MapPlaceListTarget
        if let visible = store.importVisiblePlace(for: entry, item: item) { target = .visiblePlace(visible) }
        else if let candidate = store.importCandidate(for: entry, item: item) { target = .candidate(candidate) }
        else { return }
        listRequest = ImportListSelectionRequest(itemIDs: [entryID], targets: [target])
    }

    private func chooseLists(items: [PlaceImportItem]) {
        let targets = items.flatMap { item in
            (item.selectedCandidates.isEmpty ? Array(item.candidates.prefix(1)) : item.selectedCandidates)
                .map { MapPlaceListTarget.candidate($0) }
        }
        guard !targets.isEmpty else { return }
        listRequest = ImportListSelectionRequest(itemIDs: items.map(\.id), targets: targets)
    }

    private func listButton(items: [PlaceImportItem]) -> some View {
        let selected = !items.isEmpty && items.allSatisfy { !(pendingLists[$0.id] ?? []).isEmpty }
        return Button { chooseLists(items: items) } label: {
            Image(systemName: "list.bullet")
                .frame(width: 44, height: 44)
                .modifier(ImportListButtonOutline(isSelected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to list")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func reconcileListSaves() {
        for batch in scopedBatches {
            var entries = batch.receipt?.entries ?? []
            let originalEntries = entries
            for item in importStore.items(for: batch.id) where ![.saved, .dismissed].contains(item.state) {
                let candidates = item.selectedCandidates.isEmpty ? Array(item.candidates.prefix(1)) : item.selectedCandidates
                let saves = candidates.compactMap { candidate -> PlaceImportReceiptEntry? in
                    guard let existing = store.existingImportSave(matching: candidate) else { return nil }
                    return PlaceImportReceiptEntry(itemID: item.id, displayName: candidate.name,
                        displayArea: candidateArea(candidate), status: existing.status, outcome: .existing,
                        userPlaceID: existing.userPlaceID)
                }
                if !candidates.isEmpty && saves.count == candidates.count, let last = saves.last?.userPlaceID {
                    entries.removeAll { $0.itemID == item.id }
                    entries.append(contentsOf: saves)
                    importStore.markSaved(itemID: item.id, userPlaceID: last)
                }
            }
            if entries != originalEntries {
                importStore.recordReceipt(batchID: batch.id, entries: entries, destinationListID: batch.destinationListID)
            }
        }
    }

    private func stageStatus(_ status: PlaceStatus, item: PlaceImportItem) {
        pendingStatuses[item.id] = status
        importStore.setIncludedInImport(true, itemID: item.id)
        if item.selectedCandidates.isEmpty, let candidateID = item.candidates.first?.id {
            importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
        }
        importStore.setStagedStatus(status, itemID: item.id)
        updateDetailStatus(status, itemID: item.id)
    }

    private func toggleStatus(_ status: PlaceStatus, item: PlaceImportItem) {
        if pendingStatuses[item.id] == status {
            pendingStatuses.removeValue(forKey: item.id)
        } else {
            stageStatus(status, item: item)
        }
    }

    private func toggleDetails(_ item: PlaceImportItem, candidate: PlaceCandidate?) {
        guard let candidate else { return }
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            if expandedDetailItemIDs.contains(item.id) {
                expandedDetailItemIDs.remove(item.id)
                return
            }
            let context = detailContext(for: item, candidate: candidate)
            if detailDrafts[item.id] == nil,
               let draft = PlaceSaveDraft.restorableFlow(
                   ownerUserID: store.currentUser.id,
                   context: context
               ) {
                detailDrafts[item.id] = draft
            }
            expandedDetailItemIDs.insert(item.id)
        }
    }

    @ViewBuilder
    private func inlineDetails(_ item: PlaceImportItem) -> some View {
        if let candidate = item.selectedCandidate,
           let draft = detailDrafts[item.id] {
            MapPlaceSaveEditor(
                context: detailContext(for: item, candidate: candidate),
                draft: draft,
                onDraftChange: { draftID, form, submittedAt in
                    guard var updated = detailDrafts[item.id], updated.id == draftID else { return }
                    updated.form = form
                    updated.updatedAt = .now
                    updated.submittedAt = submittedAt
                    detailDrafts[item.id] = updated
                    if pendingStatuses[item.id] != nil { pendingStatuses[item.id] = form.selectedStatus }
                    importStore.setStagedStatus(form.selectedStatus, itemID: item.id)
                    importStore.setStagedNote(form.note, itemID: item.id)
                    importStore.setStagedRatingScore(form.selectedRatingScore, itemID: item.id)
                    importStore.setStagedVisitedAt(form.visitedAt, itemID: item.id)
                },
                onSave: { _ in nil },
                onRemove: { _ in false },
                onClose: {},
                onSaveCompleted: { _ in },
                presentation: .inlineStaging,
                onSubmissionChange: { submission in
                    stagedDetailSubmissions[item.id] = submission
                }
            )
            .id("\(item.id):\(candidate.id):\(draft.form.selectedStatus.rawValue)")
            .padding(.top, WanderTheme.spacing1)
        }
    }

    private func detailContext(
        for item: PlaceImportItem,
        candidate: PlaceCandidate
    ) -> MapPlaceSaveContext {
        .importCandidate(
            candidate,
            sourceType: item.source.canonicalAddSourceType,
            status: detailDrafts[item.id]?.form.selectedStatus ?? item.stagedStatus,
            defaultVisibility: detailDrafts[item.id]?.form.selectedVisibility
                ?? store.effectiveDefaultVisibility,
            ratingScore: detailDrafts[item.id]?.form.selectedRatingScore
                ?? item.stagedRatingScore,
            note: detailDrafts[item.id]?.form.note ?? item.stagedNote ?? ""
        )
    }

    private func updateDetailStatus(_ status: PlaceStatus, itemID: String) {
        guard var draft = detailDrafts[itemID] else { return }
        draft.form.selectedStatus = status
        draft.updatedAt = .now
        detailDrafts[itemID] = draft
    }

    private func commit(itemIDs: Set<String>) {
        guard !isCommitting else { return }
        guard !itemIDs.isEmpty else { return }
        guard let expectedUserID = auth.state.session?.userID,
              expectedUserID == store.currentUser.id
        else {
            auth.presentGate(for: .syncPlace)
            return
        }

        commitErrorMessage = "A place’s details could not be saved. Review its details and try again. Any places already saved are safe."
        isCommitting = true
        commitTask = Task { @MainActor in
            let didSave = await commitScopedImports(expectedUserID: expectedUserID, itemIDs: itemIDs)
            isCommitting = false
            commitTask = nil
            if didSave {
                if privateDetailsWarningCount > 0 {
                    showsSavedDetailsWarning = true
                } else { (finishPlaceImport ?? onDone)() }
            }
        }
    }

    @MainActor
    private func commitScopedImports(expectedUserID: String, itemIDs: Set<String>) async -> Bool {
        guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
        var receipts: [PlaceImportReceiptEntry] = []
        var completedItems: [String: String] = [:]
        var completedReceipts: [(String, [PlaceImportReceiptEntry], String?)] = []
        for batch in scopedBatches {
            guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
            let batchItems = importStore.items(for: batch.id).filter { !$0.isSourceRetry }
            let destination = destinationList(for: batch, itemCount: batchItems.count)
            var entries = batch.receipt?.entries ?? []

            for item in batchItems where itemIDs.contains(item.id) && item.state != .dismissed {
                if item.state == .saved {
                    for index in entries.indices where entries[index].itemID == item.id
                        && [.added, .existing].contains(entries[index].outcome) {
                        guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
                        let entry = entries[index]
                        var selection = store.importSelection(for: entry, item: item)
                        var saveID = store.importVisiblePlace(for: entry, item: item)?.userPlace.id
                        let status = pendingStatuses[entry.id]
                        if let status, status != selection.status {
                            guard let (result, replacement) = await store.createImportedSelection(
                                entry: entry, item: item, status: status,
                                submission: stagedDetailSubmissions[entry.id]) else {
                                showsCommitError = true
                                return false
                            }
                            guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
                            if result.localDetailsWarning != nil { privateDetailsWarningCount += 1 }
                            selection = replacement
                            saveID = result.userPlaceID
                            // Persist the new identity before a later list/removal
                            // can fail. Reopening resumes the captured removal.
                            entries[index] = PlaceImportReceiptEntry(id: entry.id, itemID: entry.itemID,
                                displayName: entry.displayName, displayArea: entry.displayArea,
                                status: status, outcome: entry.outcome, userPlaceID: result.userPlaceID,
                                savedSelection: replacement, unfinishedRemoval: pendingRemovals[entry.id])
                            store.flushPersistence()
                            importStore.recordReceipt(batchID: batch.id, entries: entries, destinationListID: destination?.id)
                            // The replacement already owns these details. A
                            // retry must not replay its original add submission.
                            stagedDetailSubmissions.removeValue(forKey: entry.id)
                        } else if let submission = stagedDetailSubmissions[entry.id] {
                            // Same-action edits retain the exact receipt identity.
                            guard submission.status == selection.status,
                                  let result = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil) else {
                                showsCommitError = true
                                return false
                            }
                            if result.localDetailsWarning != nil { privateDetailsWarningCount += 1 }
                        }
                        if let removal = pendingRemovals[entry.id] {
                            guard store.removeImportedSelection(removal, entry: entry, item: item) else {
                                showsCommitError = true
                                return false
                            }
                            if removal.status != nil && status == nil {
                                selection.status = nil; selection.visitID = nil; selection.wannaID = nil
                            }
                            selection.listIDs.subtract(removal.listIDs)
                            saveID = store.importVisiblePlace(for: entry, item: item)?.userPlace.id
                        }
                        if !(pendingLists[entry.id] ?? []).isEmpty {
                            if saveID == nil, let candidate = store.importCandidate(for: entry, item: item) {
                                saveID = store.saveImportedCandidate(candidate, status: .wannaGo, visibility: .selfOnly,
                                    note: nil, sourceType: item.source.canonicalAddSourceType).userPlaceID
                            }
                            guard let saveID, await addPendingLists(itemID: entry.id, userPlaceID: saveID, expectedUserID: expectedUserID) else {
                                showsCommitError = true
                                return false
                            }
                            selection.listIDs.formUnion(pendingLists[entry.id] ?? [])
                        }
                        entries[index] = PlaceImportReceiptEntry(
                            id: entry.id, itemID: entry.itemID, displayName: entry.displayName,
                            displayArea: entry.displayArea, status: selection.status,
                            outcome: entry.outcome, userPlaceID: saveID ?? entry.userPlaceID,
                            savedSelection: selection
                        )
                        // Checkpoint each completed card so retrying another card
                        // cannot create its replacement action a second time.
                        store.flushPersistence()
                        importStore.recordReceipt(batchID: batch.id, entries: entries, destinationListID: destination?.id)
                    }
                    continue
                }
                guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
                let selected = item.selectedCandidates.isEmpty ? Array(item.candidates.prefix(1)) : item.selectedCandidates
                guard !selected.isEmpty else {
                    continue
                }

                entries.removeAll { $0.itemID == item.id && $0.outcome == .needsReview }

                var lastUserPlaceID: String?
                for candidate in selected {
                    guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
                    let existing = store.existingImportSave(matching: candidate)
                    let status = pendingStatuses[item.id] ?? existing?.status ?? .wannaGo
                    let result: SaveResult
                    if let stagedSubmission = stagedDetailSubmissions[item.id] {
                        guard let stagedResult = await persistImportedPlaceSaveSubmission(
                            stagedSubmission.replacingImportCandidate(
                                candidate,
                                sourceType: item.source.canonicalAddSourceType,
                                status: status
                            ),
                            sourceType: item.source.canonicalAddSourceType,
                            store: store,
                            backend: nil
                        ) else {
                            showsCommitError = true
                            return false
                        }
                        guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
                        result = stagedResult
                        if result.localDetailsWarning != nil { privateDetailsWarningCount += 1 }
                    } else {
                        result = store.saveImportedCandidate(
                            candidate,
                            status: status,
                            visibility: .selfOnly,
                            note: item.stagedNote,
                            sourceType: item.source.canonicalAddSourceType,
                            ratingScore: status == .been ? item.stagedRatingScore : nil,
                            visitedAt: item.stagedVisitedAt ?? .now
                        )
                    }
                    if let destination {
                        _ = store.addCurrentUserPlace(userPlaceID: result.userPlaceID, to: destination)
                    }
                    guard await addPendingLists(itemID: item.id, userPlaceID: result.userPlaceID, expectedUserID: expectedUserID) else { showsCommitError = true; return false }
                    lastUserPlaceID = result.userPlaceID
                    entries.append(
                        PlaceImportReceiptEntry(
                            itemID: item.id,
                            displayName: candidate.name,
                            displayArea: candidateArea(candidate),
                            status: status,
                            outcome: existing == nil ? .added : .existing,
                            userPlaceID: result.userPlaceID,
                            savedSelection: PlaceImportSavedSelection(
                                status: status,
                                visitID: status == .been ? store.visits(for: result.userPlaceID).first?.id : nil,
                                wannaID: status == .wannaGo ? UUID().uuidString.lowercased() : nil,
                                wannaIsOriginal: status == .wannaGo ? true : nil,
                                listIDs: (pendingLists[item.id] ?? []).union(destination.map { [$0.id] } ?? []),
                                candidateID: candidate.id
                            )
                        )
                    )
                }
                if let lastUserPlaceID {
                    completedItems[item.id] = lastUserPlaceID
                }
            }

            guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
            completedReceipts.append((batch.id, entries, destination?.id))
            receipts.append(contentsOf: entries)
        }
        guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
        importStore.performBatchedMutations {
            for (id, saveID) in completedItems { importStore.markSaved(itemID: id, userPlaceID: saveID) }
            for (id, entries, destinationID) in completedReceipts {
                importStore.recordReceipt(batchID: id, entries: entries, destinationListID: destinationID)
            }
        }
        let completedActionIDs = itemIDs.union(receipts.filter { itemIDs.contains($0.itemID) }.map(\.id))
        pendingRemovals = pendingRemovals.filter { !itemIDs.contains($0.value.itemID) }
        pendingStatuses = pendingStatuses.filter { !completedActionIDs.contains($0.key) }
        pendingLists = pendingLists.filter { !completedActionIDs.contains($0.key) }
        stagedDetailSubmissions = stagedDetailSubmissions.filter { !completedActionIDs.contains($0.key) }
        detailDrafts = detailDrafts.filter { !completedActionIDs.contains($0.key) }
        store.flushPersistence()
        guard canContinueCommit(expectedUserID: expectedUserID) else { return false }

        guard case .signedIn = auth.state, !receipts.isEmpty else { return true }
        Task { @MainActor in
            guard canContinueCommit(expectedUserID: expectedUserID) else { return }
            _ = await store.syncUnsyncedOwnPlaces(backend: backend)
            guard canContinueCommit(expectedUserID: expectedUserID) else { return }
            _ = await store.syncPendingPlaceLists(backend: backend)
            guard canContinueCommit(expectedUserID: expectedUserID) else { return }
            _ = await store.retryPendingSharedVisitInvites(backend: backend)
        }
        return true
    }

    private func addPendingLists(itemID: String, userPlaceID: String, expectedUserID: String) async -> Bool {
        for id in pendingLists[itemID] ?? [] {
            guard canContinueCommit(expectedUserID: expectedUserID) else { return false }
            guard let list = store.visiblePlaceLists.first(where: { $0.id == id }),
                  let visible = store.currentUserVisiblePlaces.first(where: { $0.userPlace.id == userPlaceID || $0.userPlace.localID == userPlaceID }) else { return false }
            let result = await MapPlaceListTarget.visiblePlace(visible).add(to: list, store: store, backend: nil, analyticsSurface: "import")
            guard result.outcome != .permissionDenied else { return false }
        }
        return true
    }

    private func canContinueCommit(expectedUserID: String) -> Bool {
        PlaceImportCommitAuthorization.isValid(
            expectedUserID: expectedUserID,
            authUserID: auth.state.session?.userID,
            currentUserID: store.currentUser.id,
            isCancelled: Task.isCancelled
        )
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

    private var recoveryItems: [PlaceImportItem] {
        scopedItems.filter {
            [.needsHelp, .failed].contains($0.state)
                && ($0.isSourceRetry || $0.candidates.isEmpty)
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
        status == .been ? WanderTheme.stateSuccess.color : brandMode.accent
    }
}

struct ImportMatchingProgressBar: View {
    @Environment(\.astirBrandMode) private var brandMode
    let progress: PlaceImportMatchingProgress
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // A shallow stone plinth: neutral until actual work completes.
                // Mask the full-width surface so the texture never stretches
                // or travels backwards like the old indeterminate capsule.
                plinth(color: Color.gray)
                plinth(color: brandMode.accent)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * progress.fraction)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: progress.fraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func plinth(color: Color) -> some View {
        Rectangle()
            .fill(color.gradient)
            .overlay {
                Canvas { context, size in
                    // Fixed, low-contrast stone grain; no random re-layout or
                    // repeating animation, including with Reduce Motion on.
                    for index in 0..<220 {
                        let x = Double((index * 73) % 997) / 997 * size.width
                        let y = Double((index * 37) % 101) / 101 * size.height
                        let mark = CGRect(x: x, y: y, width: 1 + Double(index % 4), height: 1 + Double(index % 3))
                        context.fill(Path(ellipseIn: mark), with: .color(index.isMultiple(of: 2) ? .white.opacity(0.10) : .black.opacity(0.09)))
                    }
                }
            }
            .overlay(alignment: .top) { Color.white.opacity(0.18).frame(height: 1) }
            .overlay(alignment: .bottom) { Color.black.opacity(0.16).frame(height: 2) }
    }
}

/// The same geometry and surface for a returned place before and after Save.
/// Only saved entries add navigation; their controls remain in the same row.
private struct ImportPlaceCard<Thumbnail: View, Actions: View, Details: View>: View {
    let name: String
    let area: String?
    var isSaved = false
    var openIdentifier: String = ""
    var onOpen: (() -> Void)? = nil
    @ViewBuilder var thumbnail: () -> Thumbnail
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var details: () -> Details
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing3) {
                thumbnail()
                if let onOpen {
                    Button(action: onOpen) { title }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(openIdentifier)
                } else {
                    title
                }
            }
            actions()
            details()
        }
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .strokeBorder(
                    isSaved ? WanderTheme.stateSuccess.color.opacity(0.95) : brandMode.border,
                    lineWidth: isSaved ? 2.5 : 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(AstirTypography.cardTitle)
                .foregroundStyle(brandMode.primaryText)
                .lineLimit(2)
            if let area {
                Text(area)
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CanonicalImportThumbnail: View {
    let item: PlaceImportItem
    let size: CGFloat

    var body: some View {
        PlaceImportPhotoThumb(item: item, loadsRemotePhoto: true, size: size)
    }
}

extension PlaceImportSource {
    var canonicalAddSourceType: AddSourceType {
        switch self {
        case .googleMaps, .instagram, .tiktok, .snapchat: .link
        case .textNotes: .manual
        }
    }

    var canonicalTint: Color {
        switch self {
        case .googleMaps: WanderTheme.skyTint.color
        case .instagram: WanderTheme.terracottaTint.color
        case .tiktok: AstirTheme.inkRaised.color
        case .snapchat: Color.white
        case .textNotes: WanderTheme.categorySage.color.opacity(0.24)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct PlaceImportHistoryScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    @Environment(\.astirBrandMode) private var brandMode
    @State private var isSelecting = false
    @State private var selectedBatchIDs: Set<String> = []
    @State private var confirmsDeletion = false

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
                .astirScreen()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        LazyVGrid(columns: columns, spacing: WanderTheme.spacing4) {
                            ForEach(historyBatches) { batch in
                                if isSelecting {
                                    Button {
                                        if !selectedBatchIDs.insert(batch.id).inserted {
                                            selectedBatchIDs.remove(batch.id)
                                        }
                                    } label: {
                                        historyTile(batch)
                                            .overlay(alignment: .topLeading) {
                                                Image(systemName: selectedBatchIDs.contains(batch.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 26, weight: .semibold))
                                                    .foregroundStyle(.white, brandMode.accent)
                                                    .padding(10)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(selectedBatchIDs.contains(batch.id) ? .isSelected : [])
                                } else {
                                    NavigationLink {
                                        PlaceImportHistoryDestination(importStore: importStore, batchID: batch.id)
                                    } label: {
                                        historyTile(batch)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(WanderTheme.spacing4)
                }
                .astirScreen()
            }
        }
        .navigationTitle("Import history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if !historyBatches.isEmpty {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        selectedBatchIDs.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack {
                    Button("Select all") { selectedBatchIDs = Set(historyBatches.map(\.id)) }
                    Spacer()
                    Button("Delete (\(selectedBatchIDs.count))", role: .destructive) { confirmsDeletion = true }
                        .disabled(selectedBatchIDs.isEmpty)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, WanderTheme.spacing4)
                .background(brandMode.background)
            }
        }
        .confirmationDialog("Delete \(selectedBatchIDs.count) imports?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete imports", role: .destructive) {
                importStore.performBatchedMutations {
                    for id in selectedBatchIDs { importStore.deleteBatch(batchID: id) }
                }
                selectedBatchIDs.removeAll()
                isSelecting = false
            }
        } message: {
            Text("This removes their import history and remaining matches. Places you already saved stay in Wanna and Check In.")
        }
    }

    private func historyTile(_ batch: PlaceImportBatch) -> some View {
        PlaceImportHistoryTile(batch: batch, items: importStore.items(for: batch.id))
            .contentShape(Rectangle())
            .accessibilityIdentifier("import.history.\(batch.id)")
            .task { await importStore.loadSourcePreview(batchID: batch.id) }
    }

    private var historyBatches: [PlaceImportBatch] {
        importStore.batches.sorted { $0.createdAt > $1.createdAt }
    }
}

struct PlaceImportHistoryDestination: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlaceImportReportScreen(importStore: importStore, batchID: batchID, onDone: { dismiss() })
    }
}

private struct PlaceImportHistoryTile: View {
    @Environment(\.astirBrandMode) private var brandMode
    let batch: PlaceImportBatch
    let items: [PlaceImportItem]

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            PlaceImportHistoryArtwork(batch: batch, items: items)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(brandMode.border, lineWidth: 1)
                }

            Text(PlaceImportHistoryPresentation.postTitle(title: batch.sourcePostTitle ?? batch.sourceName, caption: batch.sourcePostTitle == nil ? items.compactMap(\.seed.socialCaptionHint).first : nil, author: batch.sourceAuthorName) ?? "\(batch.source.canonicalName) post")
                .font(AstirTypography.cardTitle)
                .lineLimit(3)
            HStack(spacing: WanderTheme.spacing2) {
                CanonicalImportSourceMark(source: batch.source, color: brandMode.primaryText, size: 13)
                Text(batch.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(placeCount)")
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.primaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(batch.source.canonicalName) import, \(placeCount) places, \(PlaceImportHistoryPresentation.statusLabel(batch: batch, items: items))")
    }

    private var placeCount: Int {
        PlaceImportHistoryPresentation.placeCount(batch: batch, items: items)
    }
}

private struct PlaceImportHistoryArtwork: View {
    @Environment(\.astirBrandMode) private var brandMode
    let batch: PlaceImportBatch
    let items: [PlaceImportItem]
    var showsStatus = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                batch.source.canonicalTint
                sourceArtwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if showsStatus {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.58)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack {
                        HStack {
                            Spacer()
                            CanonicalImportSourceMark(source: batch.source, color: .white, size: 18)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.48), in: Circle())
                        }
                        Spacer()
                        HStack(alignment: .bottom) {
                            Text(PlaceImportHistoryPresentation.statusLabel(batch: batch, items: items))
                                .font(AstirTypography.control)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    .padding(WanderTheme.spacing3)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var sourceArtwork: some View {
        if let sourceArtworkURL {
            AsyncImage(url: sourceArtworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
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
                .scaledToFit()
        } else {
            VStack(spacing: WanderTheme.spacing2) {
                CanonicalImportSourceMark(source: batch.source, color: batch.source == .tiktok ? .white.opacity(0.8) : brandMode.primaryText.opacity(0.8), size: 38)
                Text("Post preview unavailable")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(batch.source == .tiktok ? Color.white.opacity(0.8) : brandMode.primaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sourceArtworkURL: URL? {
        items.lazy
            .compactMap(\.seed.sourceThumbnailURLString)
            .compactMap(URL.init(string:))
            .first
    }

}

private struct ImportRemainingReviewScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlaceImportCanonicalReviewScreen(
            importStore: importStore, batchIDs: [batchID], onDone: { dismiss() }
        )
    }
}

/// Source artwork and the original link have the same position for successful
/// and failed imports. A missing cover never becomes a photo of a matched POI.
private struct ImportSourceHeader: View {
    @ObservedObject var importStore: PlaceImportStore
    let batch: PlaceImportBatch
    let items: [PlaceImportItem]
    @Environment(\.astirBrandMode) private var brandMode
    @State private var copiedLink = false

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            PlaceImportHistoryArtwork(batch: batch, items: artworkItems, showsStatus: false)
                .frame(width: batch.source == .googleMaps ? 288 : 180, height: batch.source == .googleMaps ? 180 : 320)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Original \(batch.source.canonicalName) post preview")

            if let author = batch.sourceAuthorName, !author.isEmpty {
                Text(author)
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("import.source.author")
            }

            HStack(spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.source.canonicalName)
                        .font(AstirTypography.cardTitle)
                    if let sourceURL, let url = URL(string: sourceURL) {
                        Link(sourceURL, destination: url)
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.accentText)
                            .lineLimit(2)
                    }
                    Text(batch.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let sourceURL {
                    Button {
                        UIPasteboard.general.string = sourceURL
                        copiedLink = true
                    } label: {
                        Image(systemName: copiedLink ? "checkmark" : "doc.on.doc")
                            .frame(width: 44, height: 44)
                            .foregroundStyle(brandMode.accentText)
                            .wanderGlassCapsule(tone: copiedLink ? .selected : .neutral)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copiedLink ? "Link copied" : "Copy source link")
                }
            }
            .padding(WanderTheme.spacing3)
            .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .task(id: sourceURL) {
            await importStore.loadSourcePreview(batchID: batch.id)
        }
    }

    private var sourceURL: String? { items.lazy.compactMap(\.seed.sourceURLString).first }

    private var artworkItems: [PlaceImportItem] { items }
}

private struct ImportRetryContent: View {
    let retry: () -> Void
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Text("Oops that link didn't work")
                .font(AstirTypography.sheetTitle)
                .foregroundStyle(brandMode.primaryText)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(AstirTypography.control)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(brandMode.accentForeground)
                    .background(brandMode.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("import.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WanderTheme.spacing3)
    }
}

private struct CanonicalImportSourceMark: View {
    let source: PlaceImportSource
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let assetName = source.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "note.text")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ImportSelectionRemovalConfirmation {
    let entryID: String
    let title: String
    let message: String
    let buttonTitle: String
    let removal: PlaceImportSavedSelectionRemoval
    var offersListPicker = false
    var replacementStatus: PlaceStatus? = nil
}

struct PlaceImportReportScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchID: String
    var savedOnly = false
    var onDone: () -> Void = {}
    var pendingStatuses: [String: PlaceStatus] = [:]
    var pendingLists: [String: Set<String>] = [:]
    var pendingRemovals: [String: PlaceImportSavedSelectionRemoval] = [:]
    var onStageStatus: ((String, PlaceStatus) -> Void)?
    var onClearStagedStatus: ((String) -> Void)?
    var onStageRemoval: ((String, PlaceImportSavedSelectionRemoval) -> Void)?
    var onStageDetails: ((String, MapPlaceSaveSubmission) -> Void)?
    var onChooseLists: ((String) -> Void)?

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brandMode
    @State private var expandedDetailEntryIDs: Set<String> = []
    @State private var initializedDetailContexts: Set<String> = []

    @State private var savedListTarget: MapPlaceListTarget?
    @State private var selectedSavedEntryID: String?
    @State private var removalConfirmation: ImportSelectionRemovalConfirmation?
    @State private var showsRemovalConfirmation = false

    var body: some View {
        Group {
            if savedOnly {
                if !savedEntries.isEmpty {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("Saved (\(savedEntries.count))")
                            .font(AstirTypography.sectionTitle)
                            .foregroundStyle(brandMode.primaryText)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("import.saved-section")
                        VStack(spacing: WanderTheme.spacing3) {
                            ForEach(savedEntries) { entry in reportRow(entry) }
                        }
                    }
                }
            } else {
                PlaceImportCanonicalReviewScreen(importStore: importStore, batchIDs: [batchID], onDone: onDone)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedSavedEntryID != nil },
            set: { if !$0 { selectedSavedEntryID = nil } }
        )) {
            if let entry = savedEntries.first(where: { $0.id == selectedSavedEntryID }),
               let visible = visiblePlace(for: entry) {
                PlaceProfileFullScreen(
                    place: PlaceSheetPlace(visiblePlace: visible),
                    saves: store.visiblePlaces().filter { VisiblePlaceGrouping.matches($0, visible) }.map(saveSummary),
                    tasteSaves: store.currentUserVisiblePlaces.map(saveSummary),
                    currentUserID: store.currentUser.id, action: .none,
                    onBack: { selectedSavedEntryID = nil }, onAction: {}
                )
            }
        }
        .sheet(item: $savedListTarget) { target in
            MapPlaceListPickerSheet(target: target, analyticsSurface: "import") { _ in }
        }
        .alert(removalConfirmation?.title ?? "Remove selection?",
               isPresented: $showsRemovalConfirmation, presenting: removalConfirmation) { confirmation in
            Button(confirmation.buttonTitle, role: .destructive) {
                expandedDetailEntryIDs.remove(confirmation.entryID)
                onStageRemoval?(confirmation.entryID, confirmation.removal)
                if let status = confirmation.replacementStatus {
                    onStageStatus?(confirmation.entryID, status)
                }
            }
            if confirmation.offersListPicker {
                Button("Choose more lists") { onChooseLists?(confirmation.entryID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var savedEntries: [PlaceImportReceiptEntry] {
        guard let batch else { return [] }
        return PlaceImportHistoryPresentation.savedEntries(batch: batch)
    }

    private var remainingItems: [PlaceImportItem] {
        PlaceImportHistoryPresentation.remainingPlaces(items: items)
            .filter { !$0.candidates.isEmpty }
    }

    private var failedItems: [PlaceImportItem] {
        items.filter { [.needsHelp, .failed].contains($0.state) }
    }

    private var isMatching: Bool {
        guard let batch else { return false }
        return PlaceImportHistoryPresentation.isMatching(batch: batch, items: items)
    }

    private func reportRow(_ entry: PlaceImportReceiptEntry) -> some View {
        let visible = visiblePlace(for: entry)
        return ImportPlaceCard(
            name: visible?.place.canonicalName ?? entry.displayName,
            area: entry.displayArea,
            isSaved: !hasPendingChanges(entry),
            openIdentifier: "import.saved.\(entry.itemID)",
            onOpen: visible == nil ? nil : { selectedSavedEntryID = entry.id }
        ) {
            reportThumbnail(entry)
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    reportDetailsButton(entry, isAvailable: visible != nil && effectiveStatus(entry) != nil && entry.unfinishedRemoval == nil)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    reportStatusControls(entry, visible: visible)
                }
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    reportDetailsButton(entry, isAvailable: visible != nil && effectiveStatus(entry) != nil && entry.unfinishedRemoval == nil)
                    reportStatusControls(entry, visible: visible)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } details: {
            if let visible, expandedDetailEntryIDs.contains(entry.id) {
                inlineHistoricalDetails(entry: entry, visible: visible)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier("import.saved-card.\(entry.itemID)")
        .accessibilityValue(hasPendingChanges(entry) ? "Unsaved changes" : "Saved")
    }

    private func hasPendingChanges(_ entry: PlaceImportReceiptEntry) -> Bool {
        entry.unfinishedRemoval != nil || pendingStatuses[entry.id] != nil || !(pendingLists[entry.id] ?? []).isEmpty
            || pendingRemovals[entry.id] != nil
    }

    private func reportDetailsButton(_ entry: PlaceImportReceiptEntry, isAvailable: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                if expandedDetailEntryIDs.contains(entry.id) {
                    expandedDetailEntryIDs.remove(entry.id)
                } else {
                    expandedDetailEntryIDs.insert(entry.id)
                }
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                Text("Add details")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expandedDetailEntryIDs.contains(entry.id) ? 180 : 0))
            }
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.accentText)
            .frame(minHeight: WanderTheme.tapMinimum)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityIdentifier("import.saved-details.\(entry.itemID)")
    }

    private func savedSelection(_ entry: PlaceImportReceiptEntry) -> PlaceImportSavedSelection {
        store.importSelection(for: entry, item: items.first { $0.id == entry.itemID })
    }

    private func reportStatusControls(_ entry: PlaceImportReceiptEntry, visible: VisiblePlace?) -> some View {
        let selection = savedSelection(entry)
        let lists = store.importLists(for: selection)
        let removed = pendingRemovals[entry.id]?.listIDs ?? []
        let isInList = !(pendingLists[entry.id] ?? []).isEmpty || (!lists.isEmpty && removed.isEmpty)
        return HStack(spacing: WanderTheme.spacing2) {
            reportStatusButton(.wannaGo, entry: entry, visible: visible)
            reportStatusButton(.been, entry: entry, visible: visible)
            Button {
                if !removed.isEmpty {
                    var removal = pendingRemovals[entry.id]!
                    removal.listIDs = []
                    onStageRemoval?(entry.id, removal)
                } else if !lists.isEmpty {
                    var removal = pendingRemovals[entry.id] ?? .init(itemID: entry.itemID)
                    removal.listIDs = selection.listIDs
                    removalConfirmation = ImportSelectionRemovalConfirmation(
                        entryID: entry.id, title: "Remove from lists?",
                        message: "Saving will remove this place from \(lists.map(\.name).joined(separator: ", ")) and discard its details in those lists. Your Wanna and Check In selections will stay as they are.",
                        buttonTitle: "Remove from lists", removal: removal, offersListPicker: true)
                    showsRemovalConfirmation = true
                } else { onChooseLists?(entry.id) }
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .modifier(ImportListButtonOutline(isSelected: isInList))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to list")
            .accessibilityAddTraits(isInList ? .isSelected : [])
            .accessibilityValue(isInList ? "Selected" : "Not selected")
            .accessibilityIdentifier("import.saved-list.\(entry.itemID)")
        }
        .frame(width: 148)
        .disabled(entry.unfinishedRemoval != nil || (visible == nil && store.importCandidate(for: entry, item: items.first { $0.id == entry.itemID }) == nil))
    }

    @ViewBuilder
    private func reportThumbnail(_ entry: PlaceImportReceiptEntry) -> some View {
        if let item = items.first(where: { $0.id == entry.itemID }) {
            PlaceImportPhotoThumb(item: photoItem(item, for: entry), loadsRemotePhoto: true, size: 58)
        } else {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .fill(batch?.source.canonicalTint ?? brandMode.recessedBackground)
                .overlay {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(brandMode.secondaryText.opacity(0.55))
                }
                .frame(width: 58, height: 58)
        }
    }

    private func photoItem(_ item: PlaceImportItem, for entry: PlaceImportReceiptEntry) -> PlaceImportItem {
        guard let candidate = item.candidates.first(where: {
            store.existingImportSave(matching: $0)?.userPlaceID == entry.userPlaceID
        }) else { return item }
        var result = item
        result.candidates = [candidate]
        result.selectedCandidateID = candidate.id
        result.selectedCandidateIDsRaw = [candidate.id]
        return result
    }

    private func reportStatusButton(_ status: PlaceStatus, entry: PlaceImportReceiptEntry, visible: VisiblePlace?) -> some View {
        let itemID = entry.itemID
        let selection = savedSelection(entry)
        let selected = (pendingStatuses[entry.id] ?? (pendingRemovals[entry.id]?.status == nil ? selection.status : nil)) == status
        return Button {
            if selected {
                if let pending = pendingStatuses[entry.id], pending != selection.status {
                    onClearStagedStatus?(entry.id)
                } else {
                    var removal = pendingRemovals[entry.id] ?? .init(itemID: itemID)
                    removal.status = status
                    removal.visitID = selection.visitID
                    removal.wannaID = selection.wannaID
                removal.wannaIsOriginal = selection.wannaIsOriginal
                    let visit = visible.flatMap { place in
                        store.visits(for: place.userPlace.id).first {
                            [$0.id, $0.localID, $0.serverID].contains(selection.visitID)
                        }
                    }
                    let visitDate = visit.map { " from " + $0.visitedAt.formatted(date: .abbreviated, time: .omitted) } ?? ""
                    removalConfirmation = ImportSelectionRemovalConfirmation(
                        entryID: entry.id, title: status == .been ? "Remove Check In?" : "Remove Wanna?",
                        message: status == .been
                            ? "Saving will delete this check-in\(visitDate) and its notes, ratings, photos and other details. Other check-ins at this place will remain."
                            : "Saving will remove this Wanna and its notes, planned date and other saved details. Your list selections will remain.",
                        buttonTitle: status == .been ? "Remove Check In" : "Remove Wanna", removal: removal)
                    showsRemovalConfirmation = true
                }
            } else if pendingRemovals[entry.id]?.status == status {
                var removal = pendingRemovals[entry.id]!
                removal.status = nil
                removal.visitID = nil
                removal.wannaID = nil
                onClearStagedStatus?(entry.id)
                onStageRemoval?(entry.id, removal)
            } else if let previous = selection.status, pendingRemovals[entry.id]?.status == nil {
                var removal = pendingRemovals[entry.id] ?? .init(itemID: itemID)
                removal.status = previous
                removal.visitID = selection.visitID
                removal.wannaID = selection.wannaID
                removal.wannaIsOriginal = selection.wannaIsOriginal
                let oldName = previous == .been ? "Check In" : "Wanna"
                let newName = status == .been ? "Check In" : "Wanna"
                removalConfirmation = ImportSelectionRemovalConfirmation(
                    entryID: entry.id, title: "Change to \(newName)?",
                    message: "Saving will remove this tile’s \(oldName) and its notes, dates, photos and other details, and create a new \(newName). Other visits and your list selections will remain.",
                    buttonTitle: "Change to \(newName)", removal: removal, replacementStatus: status)
                showsRemovalConfirmation = true
            } else { onStageStatus?(entry.id, status) }
        } label: {
            Image(systemName: status == .been ? "checkmark" : "bookmark.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.white : reportStatusColor(status))
                .background(selected ? reportStatusColor(status) : Color.clear)
                .clipShape(Circle())
                .wanderGlassCapsule(
                    tone: status == .been ? .neutral : (selected ? .selected : .neutral)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? "Check In" : "Wanna")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("import.saved-\(status == .been ? "checkin" : "wanna").\(itemID)")
    }

    private func effectiveStatus(_ entry: PlaceImportReceiptEntry) -> PlaceStatus? {
        pendingStatuses[entry.id] ?? (pendingRemovals[entry.id]?.status == nil ? savedSelection(entry).status : nil)
    }

    private func detailContext(for entry: PlaceImportReceiptEntry, visible: VisiblePlace) -> MapPlaceSaveContext {
        let selection = savedSelection(entry)
        let status = effectiveStatus(entry) ?? .wannaGo
        if status != selection.status || pendingRemovals[entry.id]?.status != nil,
           let item = items.first(where: { $0.id == entry.itemID }),
           let candidate = store.importCandidate(for: entry, item: item) {
            return .importCandidate(candidate, sourceType: item.source.canonicalAddSourceType,
                status: status, defaultVisibility: store.effectiveDefaultVisibility, ratingScore: nil, note: "")
        }
        if status == .been, let visit = store.visits(for: visible.userPlace.id).first(where: {
            [$0.id, $0.localID, $0.serverID].contains(selection.visitID)
        }) { return .editVisit(visit, visiblePlace: visible) }
        if let wanna = store.wannaSaves(for: visible.userPlace).first(where: {
            selection.wannaID == nil ? $0.isHistoricalOriginal == true : $0.id == selection.wannaID
        }) { return .editWanna(wanna, visiblePlace: visible) }
        if visible.userPlace.status == .been && (selection.wannaIsOriginal == true || selection.wannaID == nil) {
            let parent = visible.userPlace
            return .editWanna(PlaceWannaSave(id: UUID().uuidString.lowercased(), ownerID: store.currentUser.id,
                userPlaceID: parent.id, occurredAt: parent.historicalWantedAt ?? parent.savedAt,
                note: parent.historicalWantNote, visibility: parent.visibility, plannedDate: nil,
                attributeAnswersJSON: parent.historicalWantAttributeAnswersJSON ?? "[]", isHistoricalOriginal: true), visiblePlace: visible)
        }
        return .editWant(visible, attributes: store.attributes(for: visible.userPlace.id))
    }

    private func inlineHistoricalDetails(
        entry: PlaceImportReceiptEntry,
        visible: VisiblePlace
    ) -> some View {
        let context = detailContext(for: entry, visible: visible)
        let detailID = "history-details:\(entry.id):\(effectiveStatus(entry)?.rawValue ?? "none")"
        return MapPlaceSaveEditor(
            context: context,
            onSave: { submission in
                let result = await persistAddPlaceSaveSubmission(
                    submission,
                    store: store,
                    backend: nil
                )
                if result != nil {
                    beginBackgroundSyncIfPossible()
                }
                return result
            },
            onRemove: { _ in false },
            onClose: {
                _ = expandedDetailEntryIDs.remove(entry.id)
            },
            onSaveCompleted: { _ in
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    _ = expandedDetailEntryIDs.remove(entry.id)
                }
            },
            presentation: .inlineStaging,
            onSubmissionChange: { submission in
                guard !initializedDetailContexts.insert(detailID).inserted else { return }
                onStageDetails?(entry.id, submission)
            }
        )
        .id(detailID)
        .onDisappear { initializedDetailContexts.remove(detailID) }
        .padding(.top, WanderTheme.spacing1)
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
        store.importVisiblePlace(for: entry, item: items.first { $0.id == entry.itemID })
    }

    private func saveSummary(_ visible: VisiblePlace) -> PlaceSaveSummary {
        PlaceSaveSummary(visiblePlace: visible,
            attributes: store.attributes(for: visible.userPlace.id),
            viewerFollowsOwner: store.viewerFollows(visible.owner.id))
    }

    private func reportStatusColor(_ status: PlaceStatus) -> Color {
        status == .been ? WanderTheme.stateSuccess.color : brandMode.accent
    }
}

private extension PlaceImportSource {
    var canonicalName: String {
        switch self {
        case .googleMaps: "Google Maps"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .snapchat: "Snapchat"
        case .textNotes: "Notes"
        }
    }

    var canonicalSystemImage: String {
        switch self {
        case .googleMaps: "map.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .snapchat: "camera.viewfinder"
        case .textNotes: "note.text"
        }
    }

    var canonicalAccent: Color {
        switch self {
        case .googleMaps: WanderTheme.stateInfo.color
        case .instagram: WanderTheme.terracotta.color
        case .tiktok: WanderTheme.textInk.color
        case .snapchat: WanderTheme.textInk.color
        case .textNotes: WanderTheme.categoryMoss.color
        }
    }
}

struct PlaceImportSaveSyncBanner: View {
    @Environment(\.astirBrandMode) private var brandMode
    let notice: PlaceImportSaveSyncNotice
    let isOffline: Bool
    let retryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: notice.kind == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "iphone.and.arrow.forward")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(notice.kind == .failed ? WanderTheme.stateError.color : brandMode.accentText)
                .frame(width: 40, height: 40)
                .background(
                    (notice.kind == .failed ? WanderTheme.stateError.color : brandMode.accent)
                        .opacity(0.12)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(detail)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if notice.kind == .failed {
                Button("Retry", action: retryAction)
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }

            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(brandMode.secondaryText)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
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

/// The approved List treatment uses neutral glass with a sky-blue selection
/// outline, keeping the coral selection tint out of this action.
private struct ImportListButtonOutline: ViewModifier {
    let isSelected: Bool
    private let skyBlue = Color(red: 66.0 / 255, green: 217.0 / 255, blue: 1) // #42D9FF

    func body(content: Content) -> some View {
        content
            .wanderGlassCapsule(tone: .neutral, showsBorder: !isSelected)
            .overlay {
                if isSelected {
                    Capsule()
                        .stroke(skyBlue, lineWidth: WanderGlassTone.selected.borderWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}
