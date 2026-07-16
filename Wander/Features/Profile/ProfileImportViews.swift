import SwiftUI
import UniformTypeIdentifiers

struct ProfileImportSection: View {
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
                    ProfileImportSourceTile(source: source) {
                        sourceAction(source)
                    }
                }
            }

            Button(action: inboxAction) {
                HStack(spacing: WanderTheme.spacing3) {
                    ZStack {
                        Circle()
                            .fill(summary.processingCount > 0 ? WanderTheme.terracottaTint.color : WanderTheme.skyTint.color)
                        if summary.processingCount > 0 {
                            ProgressView()
                                .tint(WanderTheme.terracotta.color)
                        } else {
                            Image(systemName: summary.remainingCount > 0 ? "tray.full.fill" : "tray.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(WanderTheme.stateInfo.color)
                        }

                        if summary.processingCount == 0, summary.hasImports {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .frame(width: 14, height: 14)
                                .background(WanderTheme.stateSuccess.color)
                                .foregroundStyle(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
                                .offset(x: 13, y: -13)
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

    private var actionTitle: String {
        if summary.processingCount > 0, summary.remainingCount == 0 {
            return "Importing \(summary.processedCount) of \(summary.totalCount)"
        }
        if summary.remainingCount > 0 {
            return "Import Review"
        }
        return summary.hasImports ? "Imports done" : "Import Review"
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
        if summary.duplicateCount > 0 {
            return "\(summary.duplicateCount) already in your places"
        }
        return "No imports waiting"
    }
}

private struct ProfileImportSourceTile: View {
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
    @State private var showsCancelConfirmation = false

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
                            PlaceImportReviewRow(
                                item: item,
                                loadsRemotePhoto: auth.isSignedIn,
                                beenAction: { beginSave(item, status: .been) },
                                wannaAction: { beginSave(item, status: .wannaGo) },
                                candidateAction: { candidatePickerItem = item },
                                rescueAction: { rescueItem = item },
                                retryAction: { importStore.retry(itemID: item.id) },
                                dismissAction: { importStore.dismiss(itemID: item.id) }
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: WanderTheme.spacing1,
                                    leading: WanderTheme.spacing4,
                                    bottom: WanderTheme.spacing1,
                                    trailing: WanderTheme.spacing4
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear {
                                loadNextPageIfNeeded(itemID: item.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(WanderTheme.canvasWarm.color)
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
            if !processingBatchIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showsCancelConfirmation = true
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .accessibilityLabel("Cancel import")
                }
            }
        }
        .confirmationDialog("Cancel active imports?", isPresented: $showsCancelConfirmation) {
            if !processingBatchIDs.isEmpty {
                Button("Cancel active imports", role: .destructive) {
                    for batchID in processingBatchIDs {
                        importStore.cancel(batchID: batchID)
                    }
                }
            }
            Button("Keep importing", role: .cancel) {}
        } message: {
            Text("Places already saved will stay saved. Unfinished items will be dismissed.")
        }
        .sheet(item: $saveRoute) { route in
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
            PlaceImportRescueScreen(item: item) { name, area in
                importStore.retry(itemID: item.id, name: name, area: area)
            }
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
                [.queued, .resolving, .ready, .ambiguous, .needsHelp, .failed].contains($0.state)
            }
        case .duplicates:
            inboxItems.filter { $0.state == .duplicate }
        case .failed:
            inboxItems.filter { $0.state == .failed }
        }
    }

    private var processingBatchIDs: [String] {
        importStore.batches
            .filter { batch in
                importStore.items(for: batch.id).contains {
                    [.queued, .resolving].contains($0.state)
                }
            }
            .map(\.id)
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
            [.queued, .resolving, .ready, .ambiguous, .needsHelp, .failed].contains($0.state)
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
                    importMetric(summary.duplicateCount, "existing", WanderTheme.stateInfo.color)
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
    @EnvironmentObject private var backend: WanderBackend
    @State private var photo: PlacePhoto?

    var body: some View {
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
                        Text("Google Maps")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 15)
                            .background(Color.black.opacity(0.68))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .accessibilityHidden(true)
        .task(id: photoTaskID) {
            await loadPhoto()
        }
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

private struct PlaceImportReviewRow: View {
    let item: PlaceImportItem
    let loadsRemotePhoto: Bool
    let beenAction: () -> Void
    let wannaAction: () -> Void
    let candidateAction: () -> Void
    let rescueAction: () -> Void
    let retryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                PlaceImportPhotoThumb(item: item, loadsRemotePhoto: loadsRemotePhoto)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    if let area = item.displayArea {
                        Text(area)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: WanderTheme.spacing2)

                Label(item.source.shortBadgeTitle, systemImage: item.source.systemImage)
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minHeight: 28)
                    .background(item.source.tint)
                    .foregroundStyle(item.source.accent)
                    .clipShape(Capsule())

                if ![.queued, .resolving, .saved, .dismissed].contains(item.state) {
                    Menu {
                        if item.candidates.count > 1 {
                            Button(
                                "Review matches",
                                systemImage: "map",
                                action: candidateAction
                            )
                        }
                        Button(
                            "Search for a different place",
                            systemImage: "magnifyingglass",
                            action: rescueAction
                        )
                        if item.state == .failed {
                            Button("Retry", systemImage: "arrow.clockwise", action: retryAction)
                        }
                        Button("Dismiss", systemImage: "xmark", role: .destructive, action: dismissAction)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    }
                    .accessibilityLabel("Import item actions")
                }
            }

            rowActions
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .stroke(rowBorderColor.opacity(0.36), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var rowActions: some View {
        switch item.state {
        case .queued, .resolving:
            HStack(spacing: WanderTheme.spacing2) {
                ProgressView()
                Text(item.state == .queued ? "Waiting to match" : "Matching with Apple Maps")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .frame(minHeight: WanderTheme.tapMinimum)
        case .ready:
            HStack(spacing: WanderTheme.spacing2) {
                importStatusButton("Been", systemImage: "checkmark.circle.fill", color: WanderTheme.stateSuccess.color, action: beenAction)
                importStatusButton("Wanna", systemImage: "bookmark.fill", color: WanderTheme.stateWarning.color, action: wannaAction)
            }
        case .ambiguous:
            importCommandButton("Review \(item.candidates.count) matches", systemImage: "map.fill", color: WanderTheme.stateInfo.color, action: candidateAction)
        case .needsHelp:
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                if let helpMessage = item.helpMessage {
                    Text(helpMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                if item.seed.nameHint != nil {
                    importCommandButton(
                        "Search for the correct place",
                        systemImage: "magnifyingglass",
                        color: WanderTheme.terracotta.color,
                        action: rescueAction
                    )
                } else {
                    importCommandButton(
                        item.source == .googleMaps ? "Retry Google Maps import" : "Retry automatic match",
                        systemImage: "arrow.clockwise",
                        color: WanderTheme.terracotta.color,
                        action: retryAction
                    )
                }
            }
        case .duplicate:
            Label("Already saved", systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.stateInfo.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        case .saved:
            Label("Saved to your places", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        case .failed:
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(item.helpMessage ?? "This item could not be matched.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.stateError.color)
                importCommandButton("Retry", systemImage: "arrow.clockwise", color: WanderTheme.stateError.color, action: retryAction)
            }
        case .dismissed:
            EmptyView()
        }
    }

    private func importStatusButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .black))
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(color.opacity(0.13))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .stroke(color.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func importCommandButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .black))
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    private var rowBorderColor: Color {
        switch item.state {
        case .failed: WanderTheme.stateError.color
        case .needsHelp, .ambiguous: WanderTheme.stateWarning.color
        case .saved: WanderTheme.stateSuccess.color
        case .duplicate: WanderTheme.stateInfo.color
        default: WanderTheme.borderHairline.color
        }
    }
}

private extension PlaceImportItem {
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
}

private struct PlaceImportCandidatePicker: View {
    let item: PlaceImportItem
    let selectionAction: (String) -> Void
    let quickSaveAction: (String, PlaceStatus) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: WanderTheme.spacing3) {
                    ForEach(item.candidates) { candidate in
                        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                            Button {
                                selectionAction(candidate.id)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                                        Text(candidate.name)
                                            .font(.system(size: 17, weight: .black))
                                            .foregroundStyle(WanderTheme.textInk.color)
                                        Text(candidate.previewSubtitle())
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WanderTheme.textMuted.color)
                                            .lineLimit(3)
                                    }

                                    Spacer(minLength: WanderTheme.spacing2)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(WanderTheme.textFaint.color)
                                        .frame(width: 24, height: 24)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: WanderTheme.spacing2) {
                                quickSaveButton(
                                    "Been",
                                    systemImage: "checkmark.circle.fill",
                                    color: WanderTheme.stateSuccess.color
                                ) {
                                    quickSaveAction(candidate.id, .been)
                                    dismiss()
                                }
                                quickSaveButton(
                                    "Wanna",
                                    systemImage: "bookmark.fill",
                                    color: WanderTheme.stateWarning.color
                                ) {
                                    quickSaveAction(candidate.id, .wannaGo)
                                    dismiss()
                                }
                            }
                        }
                        .padding(WanderTheme.spacing3)
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
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
                .font(.system(size: 14, weight: .black))
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(color.opacity(0.13))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .stroke(color.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PlaceImportRescueScreen: View {
    let item: PlaceImportItem
    let retryAction: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var area: String

    init(item: PlaceImportItem, retryAction: @escaping (String, String?) -> Void) {
        self.item = item
        self.retryAction = retryAction
        _name = State(initialValue: item.seed.nameHint ?? "")
        _area = State(initialValue: item.seed.areaHint ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("place") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("City or neighborhood", text: $area)
                        .textInputAutocapitalization(.words)
                }

                if let sourceURLString = item.seed.sourceURLString {
                    Section("source") {
                        Text(sourceURLString)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .textSelection(.enabled)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Match a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") {
                        retryAction(name, area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : area)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
