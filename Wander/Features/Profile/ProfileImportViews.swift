import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct AddImportSection: View {
    let summary: PlaceImportSummary
    let sourceAction: (PlaceImportSource) -> Void
    let inboxAction: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: WanderTheme.spacing2), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("import places")
                .font(.system(size: 21, weight: .black))
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: WanderTheme.spacing2) {
                ForEach(PlaceImportSource.allCases) { source in
                    AddImportSourceTile(source: source) {
                        sourceAction(source)
                    }
                }
            }

            if summary.hasPendingImports {
                Button(action: inboxAction) {
                    HStack(spacing: WanderTheme.spacing3) {
                        ZStack {
                            Circle()
                                .fill(summary.processingCount > 0 ? WanderTheme.terracottaTint.color : WanderTheme.skyTint.color)
                            if summary.processingCount > 0 {
                                ProgressView()
                                    .tint(WanderTheme.terracotta.color)
                            } else {
                                Image(systemName: "tray.full.fill")
                                    .font(.system(size: 16, weight: .black))
                                    .foregroundStyle(WanderTheme.stateInfo.color)
                            }
                        }

                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(actionTitle)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                            Text(actionSubtitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(2)
                        }

                        Spacer(minLength: WanderTheme.spacing2)

                        if summary.processingCount > 0 {
                            Text(summary.progress.formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(WanderTheme.terracotta.color)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens import progress and review")
            }
        }
    }

    private var actionTitle: String {
        if summary.processingCount > 0, summary.remainingCount == 0 {
            return "Importing \(summary.processedCount) of \(summary.totalCount)"
        }
        if summary.remainingCount > 0 {
            return "Import Review"
        }
        return "Import Review"
    }

    private var actionSubtitle: String {
        if summary.processingCount > 0, summary.remainingCount > 0 {
            return "\(summary.remainingCount) ready  •  \(summary.processingCount) still importing"
        }
        if summary.processingCount > 0 {
            return "You can leave this page while matching continues"
        }
        if summary.remainingCount > 0 {
            return "\(summary.remainingCount) place\(summary.remainingCount == 1 ? "" : "s") waiting"
        }
        return "\(summary.remainingCount) place\(summary.remainingCount == 1 ? "" : "s") waiting"
    }
}

private struct AddImportSourceTile: View {
    let source: PlaceImportSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .fill(source.tint)
                    Image(systemName: source.systemImage)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(source.accent)
                }
                .frame(width: 42, height: 42)

                Text(source.tileTitle)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(WanderTheme.spacing2)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(source.accent.opacity(0.32), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import \(source.accessibilityTitle)")
    }
}

struct PlaceImportSourceScreen: View {
    let source: PlaceImportSource
    @ObservedObject var importStore: PlaceImportStore
    let onImportStarted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var selectedFile: PlaceImportFileContents?
    @State private var showsFileImporter = false
    @State private var errorMessage: String?
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    sourceHeader

                    if source.supportsFiles {
                        Button {
                            showsFileImporter = true
                        } label: {
                            Label(selectedFile?.fileName ?? source.fileButtonTitle, systemImage: "doc.badge.plus")
                                .font(.system(size: 15, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(WanderTheme.surfaceBone.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                                        .stroke(WanderTheme.borderStrong.color, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text(selectedFile == nil ? source.inputLabel : "or paste instead")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)

                        ZStack(alignment: .topLeading) {
                            if input.isEmpty {
                                Text(source.placeholder)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(WanderTheme.textFaint.color)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $input)
                                .font(.system(size: 15, weight: .medium))
                                .scrollContentBackground(.hidden)
                                .padding(WanderTheme.spacing2)
                                .frame(minHeight: 210)
                                .background(Color.clear)
                        }
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                        )
                    }

                    if let selectedFile {
                        HStack(spacing: WanderTheme.spacing2) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(WanderTheme.stateSuccess.color)
                            Text(selectedFile.fileName)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                self.selectedFile = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove selected file")
                        }
                        .padding(.horizontal, WanderTheme.spacing3)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    }

                    Button {
                        startImport()
                    } label: {
                        HStack(spacing: WanderTheme.spacing2) {
                            if isStarting {
                                ProgressView()
                                    .tint(WanderTheme.textOnAction.color)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                            }
                            Text("Start Import")
                        }
                        .font(.system(size: 16, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(canStart ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart || isStarting)
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .wanderScreen()
            .navigationTitle(source.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: source.allowedFileTypes,
                allowsMultipleSelection: false,
                onCompletion: handleFileSelection
            )
            .onChange(of: input) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedFile = nil
                }
            }
            .alert("Import could not start", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private var sourceHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            ZStack {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .fill(source.tint)
                Image(systemName: source.systemImage)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(source.accent)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(source.navigationTitle)
                    .font(.system(size: 24, weight: .black))
                Text(source.entrySubtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canStart: Bool {
        selectedFile != nil || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedFile = try PlaceImportFileReader.read(url)
            input = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startImport() {
        isStarting = true
        do {
            let contents = selectedFile?.text ?? input
            let batchID = try importStore.enqueue(
                source: source,
                text: contents,
                sourceName: selectedFile?.fileName
            )
            onImportStarted(batchID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isStarting = false
        }
    }
}

private enum PlaceImportReviewFilter: String, CaseIterable, Identifiable {
    case unresolved
    case duplicates
    case failed

    var id: String { rawValue }
}

private struct PlaceImportSaveRoute: Identifiable {
    let itemID: String
    let status: PlaceStatus
    let context: MapPlaceSaveContext

    var id: String { "\(itemID)|\(status.rawValue)" }
}

private struct PlaceImportQuickSaveIntent {
    let itemID: String
    let status: PlaceStatus
}

private struct PlaceImportMapLocation: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlaceImportInboxScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedFilter: PlaceImportReviewFilter = .unresolved
    @State private var visibleLimit = 50
    @State private var saveRoute: PlaceImportSaveRoute?
    @State private var candidatePickerItem: PlaceImportItem?
    @State private var pendingQuickSave: PlaceImportQuickSaveIntent?
    @State private var rescueItem: PlaceImportItem?
    @State private var showsClearConfirmation = false
    @State private var stagedStatuses: [String: PlaceStatus] = [:]
    @State private var bulkSaveQueue: [PlaceImportQuickSaveIntent] = []
    @State private var isBulkSaveRunning = false
    @State private var didSaveCurrentBulkItem = false

    var body: some View {
        Group {
            if !importStore.batches.isEmpty {
                List {
                    Section {
                        inboxSummary
                            .listRowBackground(WanderTheme.surfaceBone.color)
                    }

                    Section {
                        filterStrip
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    if selectedFilter == .unresolved, !readyItems.isEmpty {
                        Section {
                            markAllRow
                                .listRowInsets(
                                    EdgeInsets(
                                        top: WanderTheme.spacing1,
                                        leading: WanderTheme.spacing4,
                                        bottom: WanderTheme.spacing1,
                                        trailing: WanderTheme.spacing4
                                    )
                                )
                                .listRowBackground(WanderTheme.surfaceBone.color)
                        }
                    }

                    if filteredItems.isEmpty {
                        ContentUnavailableView(
                            selectedFilter == .unresolved ? "All caught up" : "No matching imports",
                            systemImage: selectedFilter == .unresolved ? "checkmark.circle" : "tray",
                            description: Text(
                                selectedFilter == .unresolved
                                    ? "There are no unresolved imports waiting for you."
                                    : "Choose another filter."
                            )
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(filteredItems.prefix(visibleLimit))) { item in
                            reviewRow(for: item)
                            .listRowInsets(
                                EdgeInsets(
                                    top: WanderTheme.spacing1,
                                    leading: WanderTheme.spacing4,
                                    bottom: WanderTheme.spacing1,
                                    trailing: WanderTheme.spacing4
                                )
                            )
                            .listRowSeparator(.visible)
                            .listRowSeparatorTint(WanderTheme.borderHairline.color)
                            .listRowBackground(WanderTheme.surfaceBone.color)
                            .onAppear {
                                loadNextPageIfNeeded(itemID: item.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(WanderTheme.canvasWarm.color)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsBulkSaveButton {
                        bulkSaveButton
                    }
                }
            } else {
                ContentUnavailableView(
                    "Import Review",
                    systemImage: "tray",
                    description: Text("Choose an import source from Profile to get started.")
                )
                .wanderScreen()
            }
        }
        .navigationTitle("Import Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !importStore.batches.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Text("Clear Imports")
                    }
                    .accessibilityLabel("Clear all imports")
                }
            }
        }
        .alert("Clear imports?", isPresented: $showsClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Import List", role: .destructive) {
                importStore.clearAll()
                selectedFilter = .unresolved
                visibleLimit = 50
                stagedStatuses = [:]
                bulkSaveQueue = []
                isBulkSaveRunning = false
            }
        } message: {
            Text("Are you sure you want to clear the import list?")
        }
        .sheet(item: $saveRoute, onDismiss: saveSheetDidDismiss) { route in
            MapPlaceSaveFlowSheet(context: route.context) { submission in
                await save(submission, itemID: route.itemID)
            } onRemove: { _ in
                false
            }
            .environmentObject(store)
        }
        .sheet(item: $candidatePickerItem, onDismiss: beginPendingQuickSave) { item in
            PlaceImportCandidatePicker(
                item: item,
                selectionAction: { candidateID in
                    importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                },
                quickSaveAction: { candidateID, status in
                    importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                    pendingQuickSave = PlaceImportQuickSaveIntent(itemID: item.id, status: status)
                }
            )
        }
        .sheet(item: $rescueItem) { item in
            PlaceImportRescueScreen(
                item: item,
                searchAction: { name, area in
                    await importStore.previewManualSearch(itemID: item.id, name: name, area: area)
                },
                confirmationAction: { name, area, candidates, selectedCandidateID in
                    importStore.confirmManualSearch(
                        itemID: item.id,
                        name: name,
                        area: area,
                        candidates: candidates,
                        selectedCandidateID: selectedCandidateID
                    )
                }
            )
        }
        .task(id: duplicateSignature) {
            importStore.reconcileDuplicates(with: existingPlaces)
        }
        .onAppear {
            importStore.resumePendingImports()
        }
    }

    private var inboxItems: [PlaceImportItem] {
        let batchDates = Dictionary(uniqueKeysWithValues: importStore.batches.map { ($0.id, $0.createdAt) })
        return importStore.items
            .filter { ![.dismissed, .saved].contains($0.state) }
            .sorted { lhs, rhs in
                let lhsDate = batchDates[lhs.batchID] ?? lhs.createdAt
                let rhsDate = batchDates[rhs.batchID] ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.seed.sourceLine != rhs.seed.sourceLine {
                    return lhs.seed.sourceLine < rhs.seed.sourceLine
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var filteredItems: [PlaceImportItem] {
        switch selectedFilter {
        case .unresolved:
            inboxItems.filter {
                [.queued, .resolving, .ready, .ambiguous, .needsHelp].contains($0.state)
            }
        case .duplicates:
            inboxItems.filter { $0.state == .duplicate }
        case .failed:
            inboxItems.filter { $0.state == .failed }
        }
    }

    private var readyItems: [PlaceImportItem] {
        inboxItems.filter { $0.state == .ready && $0.selectedCandidate != nil }
    }

    private var selectedReadyItems: [PlaceImportItem] {
        readyItems.filter { stagedStatuses[$0.id] != nil }
    }

    private var showsBulkSaveButton: Bool {
        selectedFilter == .unresolved && !selectedReadyItems.isEmpty
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(PlaceImportReviewFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                        visibleLimit = 50
                    } label: {
                        WanderChip(title: filter.rawValue, isSelected: selectedFilter == filter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
        }
    }

    private var inboxSummary: some View {
        let summary = importStore.summary
        let unresolvedCount = inboxItems.filter {
            [.queued, .resolving, .ready, .ambiguous, .needsHelp].contains($0.state)
        }.count
        let sources = Set(inboxItems.map(\.source))

        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .fill(WanderTheme.skyTint.color)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(WanderTheme.stateInfo.color)

                    if summary.processingCount == 0 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .frame(width: 16, height: 16)
                            .background(WanderTheme.stateSuccess.color)
                            .foregroundStyle(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
                            .offset(x: 17, y: -17)
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.processingCount > 0 ? "Importing places" : "Imports done")
                        .font(.system(size: 19, weight: .black))
                    Text(
                        "\(unresolvedCount) waiting across \(sources.count) source\(sources.count == 1 ? "" : "s")"
                    )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }

                Spacer()
            }

            if summary.processingCount > 0 {
                ProgressView(value: summary.progress)
                    .tint(WanderTheme.terracotta.color)
                Text("Importing \(summary.processedCount) of \(summary.totalCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            } else {
                HStack(spacing: WanderTheme.spacing4) {
                    importMetric(unresolvedCount, "to review", WanderTheme.terracotta.color)
                    importMetric(summary.duplicateCount, "duplicates", WanderTheme.stateInfo.color)
                }
            }

            if let persistenceError = importStore.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.stateError.color)
            }
        }
        .padding(.vertical, WanderTheme.spacing2)
    }

    @ViewBuilder
    private func reviewRow(for item: PlaceImportItem) -> some View {
        switch selectedFilter {
        case .unresolved:
            PlaceImportUnresolvedRow(
                item: item,
                selectedStatus: stagedStatuses[item.id],
                loadsRemotePhoto: auth.isSignedIn,
                statusAction: { toggleStatus($0, for: item) },
                candidateAction: { candidatePickerItem = item },
                rescueAction: { rescueItem = item },
                retryAction: { importStore.retry(itemID: item.id) },
                dismissAction: {
                    stagedStatuses[item.id] = nil
                    importStore.dismiss(itemID: item.id)
                }
            )
        case .duplicates:
            PlaceImportDuplicateRow(
                item: item,
                loadsRemotePhoto: auth.isSignedIn,
                dismissAction: { importStore.dismiss(itemID: item.id) }
            )
        case .failed:
            PlaceImportFailedRow(
                item: item,
                loadsRemotePhoto: auth.isSignedIn,
                retryAction: { importStore.retry(itemID: item.id) },
                rescueAction: { rescueItem = item },
                dismissAction: { importStore.dismiss(itemID: item.id) }
            )
        }
    }

    private var markAllRow: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Text("Mark all")
                .font(.system(size: 14, weight: .black))

            Spacer(minLength: WanderTheme.spacing2)

            VStack(spacing: 2) {
                Text("Wanna")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                importSelectionButton(
                    status: .wannaGo,
                    isSelected: readyItems.allSatisfy { stagedStatuses[$0.id] == .wannaGo },
                    action: { markAll(as: .wannaGo) }
                )
            }

            VStack(spacing: 2) {
                Text("Check in")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                importSelectionButton(
                    status: .been,
                    isSelected: readyItems.allSatisfy { stagedStatuses[$0.id] == .been },
                    action: { markAll(as: .been) }
                )
            }
        }
    }

    private var bulkSaveButton: some View {
        Button(action: startBulkSave) {
            HStack(spacing: WanderTheme.spacing2) {
                if isBulkSaveRunning {
                    ProgressView()
                        .tint(WanderTheme.surfaceRaised.color)
                }
                Text("Save")
                    .font(.system(size: 17, weight: .black))
                Text("\(selectedReadyItems.count)")
                    .font(.system(size: 12, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.18))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(WanderTheme.surfaceRaised.color)
            .background(WanderTheme.textInk.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        }
        .buttonStyle(.plain)
        .disabled(isBulkSaveRunning)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing2)
        .background(WanderTheme.canvasWarm.color.opacity(0.96))
        .shadow(color: WanderTheme.textInk.color.opacity(0.16), radius: 10, y: -2)
        .accessibilityLabel("Save \(selectedReadyItems.count) selected imports")
    }

    private func importSelectionButton(
        status: PlaceStatus,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: status == .been ? "checkmark" : "bookmark")
                .font(.system(size: 16, weight: .bold))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(isSelected ? status.importColor : WanderTheme.surfaceRaised.color)
                .foregroundStyle(isSelected ? Color.white : status.importColor)
                .clipShape(Circle())
                .overlay(Circle().stroke(status.importColor.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? "Mark all as check-ins" : "Mark all Wanna")
    }

    private func importMetric(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var existingPlaces: [PlaceImportExistingPlace] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceImportExistingPlace(
                userPlaceID: visiblePlace.userPlace.id,
                name: visiblePlace.place.canonicalName,
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude,
                sourceProvider: visiblePlace.place.sourceProvider,
                sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID
            )
        }
    }

    private var duplicateSignature: String {
        store.currentUserVisiblePlaces.map(\.userPlace.id).sorted().joined(separator: "|")
    }

    private func beginSave(_ item: PlaceImportItem, status: PlaceStatus) {
        guard let candidate = item.selectedCandidate else { return }
        let context = MapPlaceSaveContext.importCandidate(
            candidate,
            sourceType: item.source.addSourceType,
            status: status,
            defaultVisibility: store.effectiveDefaultVisibility
        )
        saveRoute = PlaceImportSaveRoute(itemID: item.id, status: status, context: context)
    }

    private func toggleStatus(_ status: PlaceStatus, for item: PlaceImportItem) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if stagedStatuses[item.id] == status {
                stagedStatuses[item.id] = nil
            } else {
                stagedStatuses[item.id] = status
            }
        }
    }

    private func markAll(as status: PlaceStatus) {
        let alreadySelected = readyItems.allSatisfy { stagedStatuses[$0.id] == status }
        withAnimation(.easeInOut(duration: 0.16)) {
            for item in readyItems {
                stagedStatuses[item.id] = alreadySelected ? nil : status
            }
        }
    }

    private func startBulkSave() {
        guard !isBulkSaveRunning else { return }
        bulkSaveQueue = selectedReadyItems.compactMap { item in
            stagedStatuses[item.id].map { PlaceImportQuickSaveIntent(itemID: item.id, status: $0) }
        }
        guard !bulkSaveQueue.isEmpty else { return }
        isBulkSaveRunning = true
        beginNextBulkSave()
    }

    private func beginNextBulkSave() {
        guard isBulkSaveRunning else { return }
        while !bulkSaveQueue.isEmpty {
            let intent = bulkSaveQueue.removeFirst()
            guard let item = importStore.item(id: intent.itemID), item.state == .ready else { continue }
            didSaveCurrentBulkItem = false
            beginSave(item, status: intent.status)
            return
        }
        isBulkSaveRunning = false
    }

    private func saveSheetDidDismiss() {
        store.saveFlowDidDismiss(.saveSheet)
        guard isBulkSaveRunning else { return }
        guard didSaveCurrentBulkItem else {
            bulkSaveQueue = []
            isBulkSaveRunning = false
            return
        }
        DispatchQueue.main.async {
            beginNextBulkSave()
        }
    }

    private func beginPendingQuickSave() {
        guard let intent = pendingQuickSave else { return }
        pendingQuickSave = nil
        guard let item = importStore.item(id: intent.itemID) else { return }
        beginSave(item, status: intent.status)
    }

    @MainActor
    private func save(_ submission: MapPlaceSaveSubmission, itemID: String) async -> SaveResult? {
        guard case .add(let sourceType) = submission.context.mode else { return nil }
        let remoteBackend = auth.isSignedIn ? backend : nil
        let result = await store.saveCandidate(
            submission.candidate,
            status: submission.status,
            visibility: submission.visibility,
            note: submission.note,
            sourceType: sourceType,
            ratingScore: submission.ratingScore,
            attributes: submission.attributes,
            backend: remoteBackend
        )
        let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
        await persistVisitPhotoAttachments(
            submission.photoAttachments,
            to: targetVisit,
            store: store,
            backend: remoteBackend
        )
        importStore.markSaved(itemID: itemID, userPlaceID: result.userPlaceID)
        stagedStatuses[itemID] = nil
        if isBulkSaveRunning {
            didSaveCurrentBulkItem = true
        }
        if !auth.isSignedIn {
            auth.presentGate(for: .syncPlace)
        }
        return result
    }

    private func loadNextPageIfNeeded(itemID: String) {
        guard let lastVisibleID = filteredItems.prefix(visibleLimit).last?.id,
              itemID == lastVisibleID,
              visibleLimit < filteredItems.count
        else { return }
        visibleLimit = min(filteredItems.count, visibleLimit + 50)
    }
}

private struct PlaceImportPhotoThumb: View {
    let item: PlaceImportItem
    let loadsRemotePhoto: Bool
    var size: CGFloat = 52
    @EnvironmentObject private var backend: WanderBackend
    @State private var photo: PlacePhoto?
    @State private var presentedMapLocation: PlaceImportMapLocation?

    var body: some View {
        Group {
            if let mapLocation = item.reviewMapLocation {
                Button {
                    presentedMapLocation = mapLocation
                } label: {
                    thumbnail
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(item.displayName) on a map")
                .accessibilityHint("Opens an interactive place map")
            } else {
                thumbnail
                    .accessibilityHidden(true)
            }
        }
        .task(id: photoTaskID) {
            await loadPhoto()
        }
        .sheet(item: $presentedMapLocation) { location in
            PlaceImportLocationMapSheet(location: location)
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .fill(item.source.tint)

            Image(systemName: item.source.systemImage)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(item.source.accent)

            if let photo {
                PlaceProfilePhotoImage(
                    photo: photo,
                    placeName: item.displayName,
                    onLoadFailure: { failedPhoto in
                        if failedPhoto.providerPlaceID == self.photo?.providerPlaceID {
                            self.photo = nil
                        }
                    }
                )

                if photo.isGooglePlacesPhoto {
                    VStack {
                        Spacer()
                        Text("Google")
                            .font(.system(size: 7, weight: .regular))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 12)
                            .background(Color.black.opacity(0.68))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }

    private var photoTaskID: String {
        "\(loadsRemotePhoto)|\(item.reviewPhotoRequest?.lookupKey ?? "none")"
    }

    private func loadPhoto() async {
        guard loadsRemotePhoto, let request = item.reviewPhotoRequest else {
            photo = nil
            return
        }
        do {
            let resolvedPhoto = try await backend.placePhoto(for: request)
            try Task.checkCancellation()
            photo = resolvedPhoto
        } catch {
            guard !Task.isCancelled else { return }
            photo = nil
        }
    }
}

private struct PlaceImportUnresolvedRow: View {
    let item: PlaceImportItem
    let selectedStatus: PlaceStatus?
    let loadsRemotePhoto: Bool
    let statusAction: (PlaceStatus) -> Void
    let candidateAction: () -> Void
    let rescueAction: () -> Void
    let retryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing2) {
            PlaceImportPhotoThumb(item: item, loadsRemotePhoto: loadsRemotePhoto)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text(item.reviewMetadata)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)

                unresolvedAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.state == .ready {
                HStack(spacing: 6) {
                    PlaceImportStatusSelector(
                        status: .wannaGo,
                        isSelected: selectedStatus == .wannaGo,
                        action: { statusAction(.wannaGo) }
                    )
                    PlaceImportStatusSelector(
                        status: .been,
                        isSelected: selectedStatus == .been,
                        action: { statusAction(.been) }
                    )
                }
            }

            importItemMenu(
                item: item,
                candidateAction: candidateAction,
                rescueAction: rescueAction,
                retryAction: retryAction,
                dismissAction: dismissAction
            )
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var unresolvedAction: some View {
        switch item.state {
        case .queued, .resolving:
            HStack(spacing: WanderTheme.spacing2) {
                ProgressView().controlSize(.small)
                Text(item.state == .queued ? "Waiting to match" : "Matching place")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        case .ready:
            EmptyView()
        case .ambiguous:
            PlaceImportInlineAction(
                title: "Review \(item.candidates.count) matches",
                systemImage: "map.fill",
                color: WanderTheme.stateInfo.color,
                action: candidateAction
            )
        case .needsHelp:
            VStack(alignment: .leading, spacing: 4) {
                if let helpMessage = item.helpMessage,
                   !helpMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(helpMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WanderTheme.stateError.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PlaceImportInlineAction(
                    title: item.seed.nameHint == nil ? "Retry automatic match" : "Search for the place",
                    systemImage: item.seed.nameHint == nil ? "arrow.clockwise" : "magnifyingglass",
                    color: WanderTheme.terracotta.color,
                    action: item.seed.nameHint == nil ? retryAction : rescueAction
                )
            }
        case .duplicate, .saved, .failed, .dismissed:
            EmptyView()
        }
    }
}

private struct PlaceImportDuplicateRow: View {
    let item: PlaceImportItem
    let loadsRemotePhoto: Bool
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            PlaceImportPhotoThumb(item: item, loadsRemotePhoto: loadsRemotePhoto)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.reviewMetadata)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Already in your places", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.stateInfo.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(
                    "Remove from import review",
                    systemImage: "xmark",
                    role: .destructive,
                    action: dismissAction
                )
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .accessibilityLabel("Duplicate import actions")
        }
        .padding(.vertical, 3)
    }
}

private struct PlaceImportFailedRow: View {
    let item: PlaceImportItem
    let loadsRemotePhoto: Bool
    let retryAction: () -> Void
    let rescueAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            PlaceImportPhotoThumb(item: item, loadsRemotePhoto: loadsRemotePhoto)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.helpMessage ?? "This import could not be processed.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WanderTheme.stateError.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: retryAction) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .background(WanderTheme.stateError.color.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry import")

            Menu {
                Button("Search for the place", systemImage: "magnifyingglass", action: rescueAction)
                Button(
                    "Remove from import review",
                    systemImage: "xmark",
                    role: .destructive,
                    action: dismissAction
                )
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .accessibilityLabel("Failed import actions")
        }
        .padding(.vertical, 3)
    }
}

private struct PlaceImportStatusSelector: View {
    let status: PlaceStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: status == .been ? "checkmark" : "bookmark")
                .font(.system(size: 16, weight: .bold))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(isSelected ? status.importColor : WanderTheme.surfaceRaised.color)
                .foregroundStyle(isSelected ? Color.white : status.importColor)
                .clipShape(Circle())
                .overlay(Circle().stroke(status.importColor.opacity(0.28), lineWidth: 1))
                .shadow(color: status.importColor.opacity(0.14), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .been ? CheckInCopy.noun : "Wanna")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PlaceImportInlineAction: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }
}

private func importItemMenu(
    item: PlaceImportItem,
    candidateAction: @escaping () -> Void,
    rescueAction: @escaping () -> Void,
    retryAction: @escaping () -> Void,
    dismissAction: @escaping () -> Void
) -> some View {
    Menu {
        if item.candidates.count > 1 {
            Button("Review matches", systemImage: "map", action: candidateAction)
        }
        Button("Search for a different place", systemImage: "magnifyingglass", action: rescueAction)
        if [.queued, .resolving, .needsHelp].contains(item.state) {
            Button("Retry automatic match", systemImage: "arrow.clockwise", action: retryAction)
        }
        Button(
            "Remove from import review",
            systemImage: "xmark",
            role: .destructive,
            action: dismissAction
        )
    } label: {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .bold))
            .frame(width: 32, height: WanderTheme.tapMinimum)
    }
    .accessibilityLabel("Import item actions")
}

private extension PlaceStatus {
    var importColor: Color {
        self == .been ? WanderTheme.stateSuccess.color : WanderTheme.stateWarning.color
    }
}

private extension PlaceImportItem {
    var reviewMetadata: String {
        let candidate = selectedCandidate ?? candidates.first
        let type = candidate.map {
            WanderPlaceCategory.display(for: $0.categoryAssignment).compactTitle
        }
        var seen = Set<String>()
        let parts = [displayArea, type].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        return parts.isEmpty ? "Place" : parts.joined(separator: " · ")
    }

    var reviewPhotoRequest: PlacePhotoRequest? {
        let candidate = selectedCandidate ?? candidates.first
        let name: String
        if source == .googleMaps {
            name = seed.nameHint ?? candidate?.name ?? ""
        } else {
            name = candidate?.name ?? seed.nameHint ?? ""
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return PlacePhotoRequest(
            name: name,
            address: source == .googleMaps ? (seed.areaHint ?? candidate?.address) : candidate?.address,
            latitude: source == .googleMaps ? (seed.latitude ?? candidate?.latitude) : candidate?.latitude,
            longitude: source == .googleMaps ? (seed.longitude ?? candidate?.longitude) : candidate?.longitude,
            sourceProvider: source == .googleMaps ? (seed.sourceProvider ?? candidate?.sourceProvider) : candidate?.sourceProvider,
            sourceProviderPlaceID: source == .googleMaps
                ? (seed.sourceProviderPlaceID ?? candidate?.sourceProviderPlaceID)
                : candidate?.sourceProviderPlaceID
        )
    }

    var reviewMapLocation: PlaceImportMapLocation? {
        if let coordinate = usableImportCoordinate(latitude: seed.latitude, longitude: seed.longitude) {
            return PlaceImportMapLocation(
                id: "\(id)-source",
                title: displayName,
                subtitle: seed.areaHint ?? displayArea,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        let candidate = selectedCandidate ?? (candidates.count == 1 ? candidates[0] : nil)
        guard let candidate,
              let coordinate = usableImportCoordinate(
                  latitude: candidate.latitude,
                  longitude: candidate.longitude
              )
        else { return nil }
        return PlaceImportMapLocation(
            id: "\(id)-\(candidate.id)",
            title: candidate.name,
            subtitle: candidate.address ?? candidate.previewSubtitle(),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}

private struct PlaceImportLocationMapSheet: View {
    let location: PlaceImportMapLocation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
                    )
                )
            ) {
                Marker(location.title, coordinate: location.coordinate)
                    .tint(WanderTheme.terracotta.color)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(location.title)
                        .font(.system(size: 18, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = location.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(WanderTheme.spacing4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
            }
            .navigationTitle("Place Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct PlaceImportCandidatePicker: View {
    let item: PlaceImportItem
    let selectionAction: (String) -> Void
    let quickSaveAction: (String, PlaceStatus) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @State private var profileCandidate: PlaceCandidate?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: WanderTheme.spacing3) {
                    if let candidateMapRegion {
                        candidateMap(region: candidateMapRegion)
                    }

                    ForEach(Array(item.candidates.enumerated()), id: \.element.id) { index, candidate in
                        PlaceImportCandidateCard(
                            index: index,
                            candidate: candidate,
                            profileAction: {
                                profileCandidate = candidate
                            },
                            quickSaveAction: { status in
                                quickSaveAction(candidate.id, status)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(WanderTheme.spacing4)
            }
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Choose the Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: profileDestinationBinding) {
                candidateProfileDestination
            }
        }
    }

    private var profileDestinationBinding: Binding<Bool> {
        Binding(
            get: { profileCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    profileCandidate = nil
                }
            }
        )
    }

    @ViewBuilder
    private var candidateProfileDestination: some View {
        if let profileCandidate {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(candidate: profileCandidate),
                saves: saveSummaries(for: profileCandidate),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: .choose,
                onBack: {
                    self.profileCandidate = nil
                },
                onAction: {
                    selectionAction(profileCandidate.id)
                    dismiss()
                }
            )
        }
    }

    private func saveSummaries(for candidate: PlaceCandidate) -> [PlaceSaveSummary] {
        store.visiblePlaces()
            .filter { visiblePlace in
                if let providerPlaceID = candidate.sourceProviderPlaceID {
                    return visiblePlace.place.sourceProvider == candidate.sourceProvider
                        && visiblePlace.place.sourceProviderPlaceID == providerPlaceID
                }
                return visiblePlace.place.canonicalName.caseInsensitiveCompare(candidate.name) == .orderedSame
            }
            .map { visiblePlace in
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: store.attributes(for: visiblePlace.userPlace.id)
                )
            }
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        }
    }

    private var candidateMapRegion: MKCoordinateRegion? {
        MapRegionFitter.region(
            fitting: item.candidates.compactMap { candidate in
                usableImportCoordinate(latitude: candidate.latitude, longitude: candidate.longitude)
            },
            minimumSpan: 0.02,
            paddingMultiplier: 1.5
        )
    }

    private func candidateMap(region: MKCoordinateRegion) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose on the map")
                    .font(.system(size: 17, weight: .black))
                Text("Tap a numbered pin to select that place.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
                ForEach(Array(item.candidates.enumerated()), id: \.element.id) { index, candidate in
                    if let coordinate = usableImportCoordinate(
                        latitude: candidate.latitude,
                        longitude: candidate.longitude
                    ) {
                        Annotation(candidate.name, coordinate: coordinate) {
                            Button {
                                selectionAction(candidate.id)
                                dismiss()
                            } label: {
                                ZStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 38, weight: .black))
                                        .foregroundStyle(WanderTheme.terracotta.color)
                                        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Color.white)
                                        .offset(y: -3)
                                }
                                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Choose match \(index + 1), \(candidate.name)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .accessibilityLabel("Map of \(item.candidates.count) possible place matches")
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct PlaceImportCandidateCard: View {
    let index: Int
    let candidate: PlaceCandidate
    let profileAction: () -> Void
    let quickSaveAction: (PlaceStatus) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Button(action: profileAction) {
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    candidateArtwork

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("MATCH \(index + 1)")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.7)
                            .foregroundStyle(WanderTheme.stateInfo.color)

                        Text(candidate.name)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Label {
                            Text(candidate.importCategoryTitle)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WanderTheme.terracottaDark.color)

                        Text(candidate.importLocationSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(width: 24, height: 44)
                }
                .padding(WanderTheme.spacing3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Open match \(index + 1), \(candidate.name), "
                    + "\(candidate.importCategoryTitle), \(candidate.importLocationSummary)"
            )
            .accessibilityHint("Shows the place profile and photo")

            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
                .padding(.horizontal, WanderTheme.spacing3)

            quickActions
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.vertical, WanderTheme.spacing2)
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .shadow(
            color: WanderTheme.textInk.color.opacity(0.08),
            radius: 8,
            x: 0,
            y: 3
        )
        .accessibilityElement(children: .contain)
    }

    private var candidateArtwork: some View {
        ZStack {
            LinearGradient(
                colors: artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: 54, height: 54)
                .offset(x: 25, y: -28)

            Circle()
                .fill(WanderTheme.surfaceRaised.color.opacity(0.88))
                .frame(width: 58, height: 58)
                .shadow(color: WanderTheme.textInk.color.opacity(0.08), radius: 5, y: 2)

            WanderCategoryEmoji(emoji: candidate.categoryEmoji, size: 34)
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 26, height: 26)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(Circle())
                .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 3, y: 1)
                .padding(6)
        }
        .accessibilityHidden(true)
    }

    private var artworkSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 72 : 82
    }

    private var artworkColors: [Color] {
        switch index % 4 {
        case 1:
            [WanderTheme.skyTint.color, WanderTheme.categorySage.color.opacity(0.42)]
        case 2:
            [WanderTheme.terracottaTint.color, WanderTheme.categorySun.color.opacity(0.48)]
        case 3:
            [WanderTheme.categoryMoss.color.opacity(0.26), WanderTheme.surfaceSand.color]
        default:
            [WanderTheme.surfaceSand.color, WanderTheme.terracottaTint.color]
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: WanderTheme.spacing1) {
                beenButton
                wannaButton
            }
        } else {
            HStack(spacing: WanderTheme.spacing2) {
                beenButton
                wannaButton
            }
        }
    }

    private var beenButton: some View {
        quickSaveButton(
            "Check in",
            systemImage: "checkmark.circle.fill",
            color: WanderTheme.stateSuccess.color
        ) {
            quickSaveAction(.been)
        }
    }

    private var wannaButton: some View {
        quickSaveButton(
            "Wanna",
            systemImage: "bookmark.fill",
            color: WanderTheme.stateWarning.color
        ) {
            quickSaveAction(.wannaGo)
        }
    }

    private func quickSaveButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.heavy))
                .padding(.horizontal, WanderTheme.spacing2)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(color.opacity(0.13))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.32), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save \(candidate.name) as \(title)")
    }
}

private extension PlaceCandidate {
    var importCategoryTitle: String {
        let display = WanderPlaceCategory.display(for: categoryAssignment)
        let title = display.subcategory ?? display.category
        return title.isEmpty ? "Place" : title
    }

    var importLocationSummary: String {
        previewSubtitle(includeCategory: false, fallback: "Nearby place")
    }
}

#if DEBUG
enum PlaceImportCandidateMockupPage {
    static var isPresented: Bool {
        ProcessInfo.processInfo.arguments.contains("-WanderPlaceImportCandidateMockup")
    }
}

struct PlaceImportCandidateMockupRoot: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())

    var body: some View {
        PlaceImportCandidatePicker(
            item: Self.item,
            selectionAction: { _ in },
            quickSaveAction: { _, _ in }
        )
        .environmentObject(store)
        .preferredColorScheme(.light)
    }

    private static let item = PlaceImportItem(
        id: "rec-114-candidate-mockup",
        batchID: "rec-114-mockup-batch",
        source: .googleMaps,
        seed: PlaceImportSeed(
            rawText: "Maru Coffee Los Feliz",
            nameHint: "Maru Coffee",
            areaHint: "Los Feliz",
            sourceURLString: nil,
            sourceLine: 1
        ),
        state: .ambiguous,
        candidates: [
            PlaceCandidate(
                id: "rec-114-maru",
                name: "Maru Coffee",
                category: "coffee shop",
                address: "1936 Hillhurst Ave, Los Angeles, CA 90027",
                locality: "Los Angeles",
                region: "CA",
                country: "United States",
                latitude: 34.10662,
                longitude: -118.28762,
                sourceProvider: "google_maps",
                confidence: 0.95
            ),
            PlaceCandidate(
                id: "rec-114-gget",
                name: "Go Get Em Tiger",
                category: "coffee shop",
                address: "230 N Larchmont Blvd, Los Angeles, CA 90004",
                locality: "Los Angeles",
                region: "CA",
                country: "United States",
                latitude: 34.07510,
                longitude: -118.32378,
                sourceProvider: "google_maps",
                confidence: 0.82
            ),
            PlaceCandidate(
                id: "rec-114-verve",
                name: "Verve Coffee Roasters",
                category: "coffee shop",
                address: "8925 Melrose Ave, West Hollywood, CA 90069",
                locality: "West Hollywood",
                region: "CA",
                country: "United States",
                latitude: 34.08088,
                longitude: -118.38694,
                sourceProvider: "google_maps",
                confidence: 0.76
            )
        ]
    )
}
#endif

private func usableImportCoordinate(
    latitude: Double?,
    longitude: Double?
) -> CLLocationCoordinate2D? {
    guard let latitude,
          let longitude,
          latitude.isFinite,
          longitude.isFinite,
          !(latitude == 0 && longitude == 0)
    else { return nil }
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
}

private struct PlaceImportRescueScreen: View {
    let item: PlaceImportItem
    let searchAction: (String, String?) async -> PlaceImportCandidateSearchOutcome
    let confirmationAction: (String, String?, [PlaceCandidate], String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var isSearching = false
    @State private var searchFailure: String?
    @State private var lastSubmittedQuery = ""
    @State private var searchRevision = 0
    @State private var candidateMapPosition: MapCameraPosition = .automatic
    @FocusState private var isSearchFocused: Bool

    init(
        item: PlaceImportItem,
        searchAction: @escaping (String, String?) async -> PlaceImportCandidateSearchOutcome,
        confirmationAction: @escaping (String, String?, [PlaceCandidate], String) -> Void
    ) {
        self.item = item
        self.searchAction = searchAction
        self.confirmationAction = confirmationAction
        _query = State(initialValue: item.seed.nameHint ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    searchField

                    if candidateMapRegion != nil {
                        candidateMap
                    }

                    if isSearching {
                        HStack(spacing: WanderTheme.spacing2) {
                            ProgressView()
                            Text("Searching Apple Maps…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                    } else if let searchFailure {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("No matches yet")
                                .font(.system(size: 17, weight: .black))
                            Label(searchFailure, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WanderTheme.stateError.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(WanderTheme.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    } else if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("Choose the right place")
                                .font(.system(size: 17, weight: .black))
                            Text("Select one match to connect it to this import.")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)

                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                candidateButton(candidate, number: index + 1)
                            }
                        }
                    }

                    Button(action: confirmSelection) {
                        Text("Match Place")
                            .font(.system(size: 17, weight: .black))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .background(
                                selectedCandidateID == nil
                                    ? WanderTheme.textFaint.color
                                    : WanderTheme.terracotta.color
                            )
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCandidateID == nil)
                    .accessibilityHint(
                        selectedCandidateID == nil
                            ? "Select a place result first."
                            : "Connects the selected place to this import."
                    )

                    if let sourceURLString = item.seed.sourceURLString {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("SOURCE")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(WanderTheme.textMuted.color)
                            Text(sourceURLString)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(WanderTheme.spacing4)
            }
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Match a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard !trimmedQuery.isEmpty else {
                    isSearchFocused = true
                    return
                }
                await performSearch()
            }
            .onChange(of: query) {
                guard normalizedQuery != lastSubmittedQuery else { return }
                searchRevision += 1
                isSearching = false
                selectedCandidateID = nil
                candidates = []
                searchFailure = nil
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField("Search for a place", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await performSearch() }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button {
                Task { await performSearch() }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedQuery.isEmpty || isSearching)
            .accessibilityLabel("Search Apple Maps")
        }
        .padding(.leading, WanderTheme.spacing3)
        .padding(.trailing, WanderTheme.spacing1)
        .frame(minHeight: 52)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var candidateMapRegion: MKCoordinateRegion? {
        candidateMapRegion(for: candidates)
    }

    private var candidateMap: some View {
        Map(position: $candidateMapPosition, interactionModes: [.pan, .zoom]) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if let coordinate = usableImportCoordinate(
                    latitude: candidate.latitude,
                    longitude: candidate.longitude
                ) {
                    Annotation(candidate.name, coordinate: coordinate) {
                        Button {
                            selectedCandidateID = candidate.id
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        selectedCandidateID == candidate.id
                                            ? WanderTheme.terracotta.color
                                            : WanderTheme.stateInfo.color
                                    )
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                                    )

                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(Color.white)
                            }
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            .shadow(color: Color.black.opacity(0.22), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select match \(index + 1), \(candidate.name)")
                        .accessibilityValue(
                            selectedCandidateID == candidate.id ? "Selected" : "Not selected"
                        )
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .accessibilityLabel("Map of \(candidates.count) Apple Maps search results")
    }

    private func candidateButton(_ candidate: PlaceCandidate, number: Int) -> some View {
        let isSelected = selectedCandidateID == candidate.id
        return Button {
            selectedCandidateID = candidate.id
        } label: {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(
                        isSelected ? WanderTheme.textOnAction.color : WanderTheme.stateInfo.color
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected
                            ? WanderTheme.terracotta.color
                            : WanderTheme.skyTint.color
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(candidate.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.previewSubtitle())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isSelected
                    ? WanderTheme.terracottaTint.color
                    : WanderTheme.surfaceRaised.color
            )
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(
                        isSelected
                            ? WanderTheme.terracotta.color
                            : WanderTheme.borderHairline.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.name), \(candidate.previewSubtitle())")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        trimmedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    @MainActor
    private func performSearch() async {
        guard !trimmedQuery.isEmpty, !isSearching else { return }
        let submittedQuery = trimmedQuery
        searchRevision += 1
        let revision = searchRevision
        searchFailure = nil
        selectedCandidateID = nil
        candidates = []
        isSearching = true
        isSearchFocused = false
        let outcome = await searchAction(submittedQuery, item.seed.areaHint)
        guard revision == searchRevision else { return }
        isSearching = false
        lastSubmittedQuery = normalizedQuery
        switch outcome {
        case .results(let results):
            if let region = candidateMapRegion(for: results) {
                candidateMapPosition = .region(region)
            } else {
                candidateMapPosition = .automatic
            }
            candidates = results
        case .failed(let message):
            searchFailure = message
        }
    }

    private func candidateMapRegion(for candidates: [PlaceCandidate]) -> MKCoordinateRegion? {
        MapRegionFitter.region(
            fitting: candidates.compactMap { candidate in
                usableImportCoordinate(
                    latitude: candidate.latitude,
                    longitude: candidate.longitude
                )
            },
            minimumSpan: 0.02,
            paddingMultiplier: 1.5
        )
    }

    private func confirmSelection() {
        guard let selectedCandidateID,
              candidates.contains(where: { $0.id == selectedCandidateID })
        else { return }
        confirmationAction(
            trimmedQuery,
            item.seed.areaHint,
            candidates,
            selectedCandidateID
        )
        dismiss()
    }
}

private extension PlaceImportSource {
    var tileTitle: String {
        switch self {
        case .googleMaps: "GOOGLE\nMAPS"
        case .instagram: "INSTAGRAM\nREELS"
        case .tiktok: "TIKTOKS"
        case .textNotes: "TEXTS /\nNOTES"
        }
    }

    var navigationTitle: String {
        switch self {
        case .googleMaps: "Google Maps"
        case .instagram: "Instagram Reels"
        case .tiktok: "TikToks"
        case .textNotes: "Texts & Notes"
        }
    }

    var accessibilityTitle: String { navigationTitle }

    var shortBadgeTitle: String {
        switch self {
        case .googleMaps: "MAPS"
        case .instagram: "REEL"
        case .tiktok: "TIKTOK"
        case .textNotes: "TEXT"
        }
    }

    var systemImage: String {
        switch self {
        case .googleMaps: "map.fill"
        case .instagram: "play.rectangle.fill"
        case .tiktok: "music.note"
        case .textNotes: "note.text"
        }
    }

    var accent: Color {
        switch self {
        case .googleMaps: WanderTheme.stateInfo.color
        case .instagram: WanderTheme.terracotta.color
        case .tiktok: WanderTheme.textInk.color
        case .textNotes: WanderTheme.categoryMoss.color
        }
    }

    var tint: Color {
        switch self {
        case .googleMaps: WanderTheme.skyTint.color
        case .instagram: WanderTheme.terracottaTint.color
        case .tiktok: WanderTheme.surfaceSand.color
        case .textNotes: WanderTheme.categorySage.color.opacity(0.24)
        }
    }

    var entrySubtitle: String {
        switch self {
        case .googleMaps:
            "Paste a public map link or choose an unzipped Google Takeout CSV or JSON file."
        case .instagram:
            "Paste public Reel or post links. Add place details during review when the post does not expose them."
        case .tiktok:
            "Paste public TikTok links. Captions are matched to Apple Maps when metadata is available."
        case .textNotes:
            "Paste one place per line or choose a text, Markdown, RTF, or CSV file."
        }
    }

    var inputLabel: String {
        switch self {
        case .googleMaps: "links or place names"
        case .instagram: "public links"
        case .tiktok: "public links"
        case .textNotes: "places"
        }
    }

    var placeholder: String {
        switch self {
        case .googleMaps:
            "https://maps.app.goo.gl/...\nMaru Coffee, Los Angeles"
        case .instagram:
            "https://www.instagram.com/reel/...\nGjusta, Venice | https://www.instagram.com/p/..."
        case .tiktok:
            "https://www.tiktok.com/@.../video/..."
        case .textNotes:
            "Maru Coffee, Los Angeles\nNight + Market - West Hollywood\nGjusta | Venice"
        }
    }

    var supportsFiles: Bool {
        self == .googleMaps || self == .textNotes
    }

    var fileButtonTitle: String {
        self == .googleMaps ? "Choose Google Maps file" : "Choose text or notes file"
    }

    var allowedFileTypes: [UTType] {
        switch self {
        case .googleMaps:
            [.commaSeparatedText, .json, .plainText, .zip]
        case .textNotes:
            [.plainText, .commaSeparatedText, .rtf, UTType(filenameExtension: "md") ?? .plainText]
        case .instagram, .tiktok:
            []
        }
    }

    var addSourceType: AddSourceType {
        switch self {
        case .googleMaps, .instagram, .tiktok: .link
        case .textNotes: .manual
        }
    }
}
