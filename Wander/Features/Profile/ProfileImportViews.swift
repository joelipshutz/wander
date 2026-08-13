import MapKit
import SwiftUI

enum ImportHelpDestination {
    static let url = URL(string: "https://getrec.me/import-help")!
}

struct AddImportEntrySection: View {
    let summary: PlaceImportSummary
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("Import")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .accessibilityAddTraits(.isHeader)

            Button(action: action) {
                HStack(spacing: WanderTheme.spacing3) {
                    PlaceImportSourceIconStack(iconSize: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import from")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text("Instagram, Google Maps, TikTok, Notes & more")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }

                    Spacer(minLength: WanderTheme.spacing1)

                    if summary.hasPendingImports {
                        Text("\(summary.processingCount + summary.remainingCount)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(WanderTheme.terracotta.color)
                            .clipShape(Capsule())
                            .accessibilityLabel(
                                "\(summary.processingCount + summary.remainingCount) imports in progress or ready"
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import from Instagram, Google Maps, TikTok, Notes, and more")
            .accessibilityHint("Opens import sources")
        }
    }
}

struct PlaceImportHubScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let reviewAction: ([String]) -> Void
    let inboxAction: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var input = ""
    @State private var errorMessage: String?
    @State private var isStarting = false
    @FocusState private var isInputFocused: Bool

    private var summary: PlaceImportSummary {
        importStore.summary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    PlaceImportSourceIconStack(iconSize: 48)

                    Text("Import from anywhere")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("Paste links from Google Maps, Instagram, or TikTok, or type place names from your notes.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Use one line per place. You can mix sources in the same import. Everything stays private until you review and save it.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("places and links")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    ZStack(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("https://maps.app.goo.gl/…\nhttps://www.instagram.com/reel/…\nMaru Coffee, Los Angeles")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(WanderTheme.textFaint.color)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $input)
                            .focused($isInputFocused)
                            .accessibilityLabel("Places and links")
                            .accessibilityIdentifier("import.input")
                            .font(.system(size: 15, weight: .medium))
                            .scrollContentBackground(.hidden)
                            .padding(WanderTheme.spacing2)
                            .frame(minHeight: 220)
                            .background(Color.clear)
                    }
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                            .stroke(
                                isInputFocused
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderHairline.color,
                                lineWidth: isInputFocused ? 2 : 1
                            )
                    )
                }

                Button(action: startImport) {
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
                .accessibilityIdentifier("import.start")

                Button {
                    openURL(ImportHelpDestination.url)
                } label: {
                    Label("Where do I find a link?", systemImage: "questionmark.circle")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Import Help on getrec.me")
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, summary.hasPendingImports ? 92 : WanderTheme.spacing6)
        }
        .scrollDismissesKeyboard(.interactively)
        .wanderScreen()
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Import could not start", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openURL(ImportHelpDestination.url)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Import Help")
                .accessibilityHint("Shows where to find links in each supported app")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if summary.hasPendingImports {
                Button(action: inboxAction) {
                    HStack(spacing: WanderTheme.spacing3) {
                        if summary.processingCount > 0 {
                            ProgressView()
                                .font(.system(size: 12, weight: .black))
                                .tint(WanderTheme.textOnAction.color)
                        } else {
                            Image(systemName: "tray.full.fill")
                        }
                        Text(actionTitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(WanderTheme.terracotta.color.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing2)
                .background(WanderTheme.canvasWarm.color.opacity(0.97))
                .accessibilityHint("Opens unresolved imports from earlier captures")
            }
        }
    }

    private var actionTitle: String {
        if summary.remainingCount > 0 {
            return "Previous imports · \(summary.remainingCount) waiting"
        }
        if summary.processingCount > 0 {
            return "Previous imports · matching \(summary.processedCount) of \(summary.totalCount)"
        }
        return "Previous imports"
    }

    private var canStart: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func startImport() {
        isStarting = true
        do {
            let batchIDs = try importStore.enqueueUnified(text: input)
            input = ""
            isInputFocused = false
            isStarting = false
            reviewAction(batchIDs)
        } catch {
            errorMessage = error.localizedDescription
            isStarting = false
        }
    }
}

/// The primary import experience. It is intentionally scoped to the batch IDs
/// produced by one capture or paste so historical inbox rows cannot leak into
/// the active flow.
struct PlaceImportAdaptiveReviewScreen: View {
    @ObservedObject var importStore: PlaceImportStore
    let batchIDs: [String]
    let onViewMap: () -> Void

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.dismiss) private var dismiss
    @State private var candidatePickerItem: PlaceImportItem?
    @State private var rescueItem: PlaceImportItem?
    @State private var saveRoute: PlaceImportSaveRoute?
    @State private var completedReceipt: PlaceImportReceipt?
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                if let receipt = displayedReceipt {
                    completionContent(receipt)
                } else {
                    reviewContent
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, displayedReceipt == nil && bottomActionTitle != nil ? 88 : WanderTheme.spacing6)
        }
        .scrollDismissesKeyboard(.interactively)
        .wanderScreen()
        .navigationTitle(displayedReceipt == nil ? "Review Import" : "Verify Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if displayedReceipt != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .fontWeight(.bold)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if displayedReceipt == nil, let title = bottomActionTitle {
                WanderPrimaryButton(
                    title: isSaving ? "Saving…" : title,
                    systemImage: isSaving ? nil : bottomActionSystemImage,
                    isDisabled: isSaving,
                    action: startSave
                )
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing2)
                .background(WanderTheme.canvasWarm.color.opacity(0.97))
                .accessibilityHint(
                    reviewPlan.committableCount > 0
                        ? "Adds only the checked places that are ready"
                        : "Closes this import without adding unchecked places"
                )
            }
        }
        .sheet(item: $candidatePickerItem) { item in
            PlaceImportCandidatePicker(
                item: item,
                selectionAction: { candidateID in
                    importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                },
                quickSaveAction: { candidateID, status in
                    importStore.selectCandidate(itemID: item.id, candidateID: candidateID)
                    importStore.setStagedStatus(status, itemID: item.id)
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
        .sheet(item: $saveRoute, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { route in
            MapPlaceSaveFlowSheet(context: route.context) { submission in
                await saveOptionalDetails(submission, itemID: route.itemID)
            } onRemove: { context in
                await removeOptionalDetailsSave(context, itemID: route.itemID)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: duplicateSignature) {
            importStore.reconcileDuplicates(with: existingPlaces)
        }
        .onAppear {
            importStore.resumePendingImports()
            markDisplayedReceiptsPresented()
        }
        .onChange(of: displayedReceipt?.id) { _, _ in
            markDisplayedReceiptsPresented()
        }
        .onChange(of: auth.state) { _, _ in
            guard isSaving else { return }
            saveTask?.cancel()
            saveTask = nil
            isSaving = false
        }
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
            isSaving = false
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var reviewContent: some View {
        switch reviewPlan.surface {
        case .resolving:
            resolvingContent
        case .quickAdd:
            heading(
                title: "Ready to add",
                subtitle: "Keep it checked, then choose Check In or Wanna. Details are optional."
            )
            if let item = scopedItems.first {
                adaptiveCard(item, prominent: true)
            }
        case .duplicate:
            heading(
                title: "You already saved this",
                subtitle: "Keep it checked to include it in the imported list. Your existing details stay unchanged."
            )
            if let item = scopedItems.first {
                duplicateCard(item)
            }
        case .compact:
            heading(
                title: "Review \(scopedItems.count) places",
                subtitle: "Uncheck anything you don’t want. Choose Check In or Wanna on each place."
            )
            batchControls
            itemStack
        case .batch:
            heading(
                title: "Ready to import \(scopedItems.count) places",
                subtitle: "Check the places you want, then set each one to Check In or Wanna."
            )
            batchControls
            itemStack
        case .recovery:
            heading(
                title: "Help us match \(scopedItems.count == 1 ? "this place" : "these places")",
                subtitle: "Search for the right place. Nothing will be saved until you confirm."
            )
            itemStack
        case .complete:
            ContentUnavailableView(
                "Nothing waiting",
                systemImage: "checkmark.circle",
                description: Text("This capture has already been handled.")
            )
        }
    }

    private var resolvingContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            heading(
                title: "Finding the places",
                subtitle: "We’re reading this capture now. You’ll review every match before anything is saved."
            )
            HStack(spacing: WanderTheme.spacing3) {
                ProgressView()
                    .controlSize(.large)
                    .tint(WanderTheme.terracotta.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Matching \(reviewPlan.processingCount) item\(reviewPlan.processingCount == 1 ? "" : "s")")
                        .font(WanderTypography.editorialNamedContent)
                    Text(captureSourceCopy)
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .padding(WanderTheme.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }

    private var itemStack: some View {
        LazyVStack(spacing: WanderTheme.spacing3) {
            ForEach(scopedItems) { item in
                if item.state == .duplicate {
                    duplicateCard(item)
                } else {
                    adaptiveCard(item, prominent: false)
                }
            }
        }
    }

    private var batchControls: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing2) {
                Text("\(reviewPlan.selectedCount) of \(reviewPlan.totalCount) selected")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.textMuted.color)

                Spacer()

                Button(allItemsSelected ? "Clear all" : "Select all") {
                    setAllIncluded(!allItemsSelected)
                }
                .font(WanderTypography.label)
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(minHeight: WanderTheme.tapMinimum)
                .buttonStyle(.plain)
            }

            if !selectedReadyItems.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Apply to selected")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                    WanderGlassSegmentedSwitch(
                        options: importStatusOptions,
                        selection: bulkStatusSelection
                    )
                    .accessibilityLabel("Status for selected places")
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing1)
    }

    private func adaptiveCard(_ item: PlaceImportItem, prominent: Bool) -> some View {
        let isSelected = item.isSelectedForImport
        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                PlaceImportPhotoThumb(
                    item: item,
                    loadsRemotePhoto: auth.isSignedIn,
                    size: prominent ? 64 : 52
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(prominent ? WanderTypography.editorialCardTitle : WanderTypography.editorialNamedContent)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.reviewMetadata)
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                selectionButton(for: item)
            }
            .opacity(isSelected ? 1 : 0.62)

            if item.state == .ready {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Save as")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                    WanderGlassSegmentedSwitch(
                        options: importStatusOptions,
                        selection: statusSelection(for: item)
                    )
                    .accessibilityLabel("Status for \(item.displayName)")
                }
                .disabled(!isSelected)
                .opacity(isSelected ? 1 : 0.48)

                HStack(spacing: WanderTheme.spacing2) {
                    Button {
                        beginOptionalDetails(for: item)
                    } label: {
                        Label("Optional details", systemImage: "slider.horizontal.3")
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Edit place", systemImage: "magnifyingglass") {
                        rescueItem = item
                    }
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .buttonStyle(.plain)
                }
                .disabled(!isSelected)
                .opacity(isSelected ? 1 : 0.48)

            } else {
                recoveryActions(for: item)
                    .disabled(!isSelected)
                    .opacity(isSelected ? 1 : 0.48)
            }

            if !isSelected {
                Label("Won’t be added", systemImage: "minus.circle")
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(prominent ? WanderTheme.spacing4 : WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private func duplicateCard(_ item: PlaceImportItem) -> some View {
        let existing = existingVisiblePlace(item)
        let isSelected = item.isSelectedForImport
        return VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing3) {
                PlaceImportPhotoThumb(item: item, loadsRemotePhoto: auth.isSignedIn, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(WanderTypography.editorialNamedContent)
                    Text(item.reviewMetadata)
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Label(
                        existing?.userPlace.status == .been ? "Already checked in" : "Already in Wanna",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.stateInfo.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                selectionButton(for: item)
            }
            .opacity(isSelected ? 1 : 0.62)

            if isSelected, let existing {
                Button {
                    beginOptionalDetails(for: item, visiblePlace: existing)
                } label: {
                    Label("Optional details", systemImage: "slider.horizontal.3")
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(minHeight: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
            }

            if !isSelected {
                Label("Won’t be added to the imported list", systemImage: "minus.circle")
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private func selectionButton(for item: PlaceImportItem) -> some View {
        Button {
            importStore.setIncludedInImport(!item.isSelectedForImport, itemID: item.id)
        } label: {
            Image(systemName: item.isSelectedForImport ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    item.isSelectedForImport
                        ? WanderTheme.terracotta.color
                        : WanderTheme.borderStrong.color
                )
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isSelectedForImport ? "Exclude \(item.displayName)" : "Include \(item.displayName)")
        .accessibilityValue(item.isSelectedForImport ? "Included" : "Excluded")
    }

    @ViewBuilder
    private func recoveryActions(for item: PlaceImportItem) -> some View {
        if [.queued, .resolving].contains(item.state) {
            HStack(spacing: WanderTheme.spacing2) {
                ProgressView().controlSize(.small)
                Text("Matching place…")
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        } else {
            if let help = item.helpMessage, !help.isEmpty {
                Text(help)
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: WanderTheme.spacing2) {
                Button("Search for the place", systemImage: "magnifyingglass") {
                    rescueItem = item
                }
                .font(WanderTypography.label)
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(minHeight: WanderTheme.tapMinimum)
                .buttonStyle(.plain)

                if item.candidates.count > 1 {
                    Button("Review matches") { candidatePickerItem = item }
                        .font(WanderTypography.label)
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .buttonStyle(.plain)
                } else {
                    Button("Retry") { importStore.retry(itemID: item.id) }
                        .font(WanderTypography.label)
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func completionContent(_ receipt: PlaceImportReceipt) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                    Text(completionTitle(receipt))
                        .font(WanderTypography.editorialMajorSectionTitle)
                        .foregroundStyle(WanderTheme.textInk.color)
                }

                HStack(spacing: WanderTheme.spacing3) {
                    if receipt.addedCount > 0 {
                        completionMetric(receipt.addedCount, "added", WanderTheme.stateSuccess.color)
                    }
                    if receipt.existingCount > 0 {
                        completionMetric(receipt.existingCount, "already saved", WanderTheme.stateInfo.color)
                    }
                    if receipt.needsReviewCount > 0 {
                        completionMetric(receipt.needsReviewCount, "still needs help", WanderTheme.stateWarning.color)
                    }
                }

                if store.saveStreakSummary.isTodayCovered {
                    Label(
                        store.saveStreakSummary.currentCount == 1
                            ? "Today is covered"
                            : "Today is covered · \(store.saveStreakSummary.currentCount)-day streak",
                        systemImage: "flame.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Capsule())
                }
            }
            .padding(WanderTheme.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )

            VStack(spacing: 0) {
                ForEach(receipt.entries) { entry in
                    verificationRow(entry)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.vertical, WanderTheme.spacing2)

                    if entry.id != receipt.entries.last?.id {
                        Divider()
                            .overlay(WanderTheme.borderHairline.color)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )

            WanderPrimaryButton(
                title: "View on map",
                systemImage: "map.fill",
                action: onViewMap
            )
        }
    }

    private func heading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(WanderTypography.editorialMajorSectionTitle)
                .foregroundStyle(WanderTheme.textInk.color)
            Text(subtitle)
                .font(WanderTypography.body)
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            Label(captureSourceCopy, systemImage: "arrow.down.circle")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.terracottaDark.color)
        }
    }

    private var scopedBatches: [PlaceImportBatch] {
        let idSet = Set(batchIDs)
        return importStore.batches
            .filter { idSet.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var scopedItems: [PlaceImportItem] {
        let idSet = Set(batchIDs)
        let batchDates = Dictionary(uniqueKeysWithValues: scopedBatches.map { ($0.id, $0.createdAt) })
        return importStore.items
            .filter { idSet.contains($0.batchID) && ![.saved, .dismissed].contains($0.state) }
            .sorted { lhs, rhs in
                let lhsDate = batchDates[lhs.batchID] ?? lhs.createdAt
                let rhsDate = batchDates[rhs.batchID] ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.seed.sourceLine < rhs.seed.sourceLine
            }
    }

    private var reviewPlan: PlaceImportReviewPlan {
        PlaceImportReviewPlan(items: scopedItems)
    }

    private var bottomActionTitle: String? {
        guard reviewPlan.processingCount == 0 else { return nil }
        if reviewPlan.committableCount > 0 {
            return reviewPlan.primaryActionTitle
        }
        if !scopedItems.isEmpty, reviewPlan.selectedCount == 0 {
            return "Done"
        }
        return nil
    }

    private var bottomActionSystemImage: String? {
        reviewPlan.committableCount > 0 ? "plus" : "checkmark"
    }

    private var importStatusOptions: [WanderSegmentOption] {
        [
            WanderSegmentOption(id: PlaceStatus.wannaGo.rawValue, title: "Wanna"),
            WanderSegmentOption(id: PlaceStatus.been.rawValue, title: "Check In")
        ]
    }

    private var selectedReadyItems: [PlaceImportItem] {
        scopedItems.filter { $0.state == .ready && $0.isSelectedForImport }
    }

    private var allItemsSelected: Bool {
        !scopedItems.isEmpty && scopedItems.allSatisfy(\.isSelectedForImport)
    }

    private var bulkStatusSelection: Binding<String> {
        Binding(
            get: { PlaceImportBulkStatusAction.idleSelectionID },
            set: { rawValue in
                guard let status = PlaceImportBulkStatusAction.status(for: rawValue) else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    importStore.setStagedStatus(status, itemIDs: selectedReadyItems.map(\.id))
                }
            }
        )
    }

    private func statusSelection(for item: PlaceImportItem) -> Binding<String> {
        Binding(
            get: { item.stagedStatus.rawValue },
            set: { rawValue in
                guard let status = PlaceStatus(rawValue: rawValue) else { return }
                importStore.setStagedStatus(status, itemID: item.id)
            }
        )
    }

    private func setAllIncluded(_ isIncluded: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            importStore.setIncludedInImport(isIncluded, itemIDs: scopedItems.map(\.id))
        }
    }

    private var displayedReceipt: PlaceImportReceipt? {
        completedReceipt ?? combinedStoredReceipt
    }

    private var combinedStoredReceipt: PlaceImportReceipt? {
        let receipts = scopedBatches.compactMap(\.receipt)
        guard !receipts.isEmpty,
              receipts.count == scopedBatches.count
        else { return nil }
        let hasAutomaticSavedEntries = scopedBatches.contains { batch in
            batch.automaticSaveCompletedAt != nil
                && batch.receipt?.entries.contains {
                    [.added, .existing].contains($0.outcome)
                } == true
        }
        guard hasAutomaticSavedEntries
                || PlaceImportReceiptPresentationPolicy.canUseStoredReceipt(
                    activeItemCount: scopedItems.count
                )
        else { return nil }
        return PlaceImportReceipt(
            batchID: receipts.count == 1 ? receipts[0].batchID : "combined",
            sourceName: receipts.count == 1 ? receipts[0].sourceName : captureSourceCopy,
            createdAt: receipts.map(\.createdAt).max() ?? .now,
            entries: receipts.flatMap(\.entries),
            destinationListID: receipts.compactMap(\.destinationListID).last,
            presentedAt: receipts.allSatisfy { $0.presentedAt != nil } ? .now : nil
        )
    }

    private var captureSourceCopy: String {
        let sources = Set(scopedBatches.map(\.source))
        if sources.count == 1, let source = sources.first {
            return switch source {
            case .googleMaps: "From Google Maps"
            case .instagram: "From Instagram"
            case .tiktok: "From TikTok"
            case .textNotes: "From your notes"
            }
        }
        return "From this import"
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

    private func existingVisiblePlace(_ item: PlaceImportItem) -> VisiblePlace? {
        guard let duplicateID = item.duplicateUserPlaceID else { return nil }
        return store.currentUserVisiblePlaces.first { $0.userPlace.id == duplicateID }
    }

    @ViewBuilder
    private func verificationRow(_ entry: PlaceImportReceiptEntry) -> some View {
        if let item = importStore.item(id: entry.itemID) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing3) {
                    PlaceImportPhotoThumb(item: item, loadsRemotePhoto: auth.isSignedIn, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .font(WanderTypography.editorialNamedContent)
                        Text(verificationDetail(entry, item: item))
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        toggleVerifiedInclusion(entry, item: item)
                    } label: {
                        Image(systemName: item.isSelectedForImport ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                item.isSelectedForImport
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderStrong.color
                            )
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        item.isSelectedForImport
                            ? "Remove \(entry.displayName) from this import"
                            : "Keep \(entry.displayName)"
                    )
                }
                .opacity(item.isSelectedForImport ? 1 : 0.58)

                if item.isSelectedForImport, entry.outcome == .needsReview {
                    Button("Search for the place", systemImage: "magnifyingglass") {
                        completedReceipt = nil
                        rescueItem = item
                    }
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .buttonStyle(.plain)
                } else if item.isSelectedForImport,
                          let visiblePlace = verifiedVisiblePlace(entry, item: item) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        WanderGlassSegmentedSwitch(
                            options: importStatusOptions,
                            selection: Binding(
                                get: { visiblePlace.userPlace.status.rawValue },
                                set: { rawValue in
                                    guard let status = PlaceStatus(rawValue: rawValue) else { return }
                                    changeVerifiedStatus(status, entry: entry, item: item)
                                }
                            )
                        )
                        .disabled(entry.outcome == .existing)
                        .accessibilityLabel("Status for \(entry.displayName)")

                        if entry.outcome == .existing {
                            Text("Already saved — your existing status and details stay unchanged.")
                                .font(WanderTypography.metadata)
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }

                        Button {
                            beginOptionalDetails(for: item, visiblePlace: visiblePlace)
                        } label: {
                            Label("Optional details", systemImage: "slider.horizontal.3")
                                .font(WanderTypography.label)
                                .foregroundStyle(WanderTheme.terracotta.color)
                                .frame(minHeight: WanderTheme.tapMinimum)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !item.isSelectedForImport {
                    Label(
                        entry.outcome == .existing ? "Existing save kept" : "Removed from your map",
                        systemImage: "minus.circle"
                    )
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
        } else {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: entry.outcome.receiptSystemImage)
                    .foregroundStyle(entry.outcome.receiptColor)
                Text(entry.displayName)
                    .font(WanderTypography.editorialNamedContent)
            }
        }
    }

    private func verificationDetail(
        _ entry: PlaceImportReceiptEntry,
        item: PlaceImportItem
    ) -> String {
        if entry.outcome == .needsReview {
            return item.helpMessage ?? "Needs your help matching the place"
        }
        return [verifiedVisiblePlace(entry, item: item)?.userPlace.status == .been ? "Check In" : "Wanna", entry.displayArea]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func verifiedVisiblePlace(
        _ entry: PlaceImportReceiptEntry,
        item: PlaceImportItem
    ) -> VisiblePlace? {
        let userPlaceID = item.savedUserPlaceID ?? entry.userPlaceID
        return store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlaceID }
    }

    private func toggleVerifiedInclusion(
        _ entry: PlaceImportReceiptEntry,
        item: PlaceImportItem
    ) {
        let shouldInclude = !item.isSelectedForImport
        if entry.outcome == .added {
            if shouldInclude,
               let candidate = item.selectedCandidate {
                let result = store.saveImportedCandidate(
                    candidate,
                    status: item.stagedStatus,
                    visibility: .selfOnly,
                    note: item.stagedNote,
                    sourceType: item.source.addSourceType,
                    ratingScore: item.stagedRatingScore,
                    visitedAt: item.stagedVisitedAt ?? .now
                )
                importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
            } else if let userPlaceID = item.savedUserPlaceID ?? entry.userPlaceID {
                _ = store.removeSave(userPlaceID: userPlaceID)
            }
        }
        importStore.setIncludedInImport(shouldInclude, itemID: item.id)
        syncVerifiedChanges()
    }

    private func changeVerifiedStatus(
        _ status: PlaceStatus,
        entry: PlaceImportReceiptEntry,
        item: PlaceImportItem
    ) {
        guard entry.outcome == .added,
              status != verifiedVisiblePlace(entry, item: item)?.userPlace.status,
              let candidate = item.selectedCandidate
        else { return }
        if let userPlaceID = item.savedUserPlaceID ?? entry.userPlaceID {
            _ = store.removeSave(userPlaceID: userPlaceID)
        }
        importStore.setStagedStatus(status, itemID: item.id)
        let result = store.saveImportedCandidate(
            candidate,
            status: status,
            visibility: .selfOnly,
            note: item.stagedNote,
            sourceType: item.source.addSourceType,
            ratingScore: status == .been ? item.stagedRatingScore : nil,
            visitedAt: item.stagedVisitedAt ?? .now
        )
        importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
        syncVerifiedChanges()
    }

    private func beginOptionalDetails(
        for item: PlaceImportItem,
        visiblePlace: VisiblePlace? = nil
    ) {
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
            guard let candidate = item.selectedCandidate else { return }
            context = .importCandidate(
                candidate,
                sourceType: item.source.addSourceType,
                status: item.stagedStatus,
                defaultVisibility: .selfOnly,
                ratingScore: item.stagedRatingScore,
                note: item.stagedNote ?? ""
            )
        }
        store.saveFlowDidPresent(.saveSheet)
        saveRoute = PlaceImportSaveRoute(
            itemID: item.id,
            status: item.stagedStatus,
            context: context
        )
    }

    @MainActor
    private func saveOptionalDetails(
        _ submission: MapPlaceSaveSubmission,
        itemID: String
    ) async -> SaveResult? {
        guard let result = await persistAddPlaceSaveSubmission(
            submission,
            store: store,
            backend: auth.isSignedIn ? backend : nil
        ) else { return nil }
        importStore.setStagedStatus(submission.status, itemID: itemID)
        importStore.setIncludedInImport(true, itemID: itemID)
        importStore.markSaved(itemID: itemID, userPlaceID: result.userPlaceID)
        return result
    }

    @MainActor
    private func removeOptionalDetailsSave(
        _ context: MapPlaceSaveContext,
        itemID: String
    ) async -> Bool {
        let didRemove: Bool
        switch context.mode {
        case .editVisit(_, let visit):
            didRemove = await store.deleteVisit(
                visitID: visit.id,
                backend: auth.isSignedIn ? backend : nil
            )
        case .editWant(let visiblePlace):
            didRemove = await store.removeSave(
                userPlaceID: visiblePlace.userPlace.id,
                backend: auth.isSignedIn ? backend : nil
            ) != nil
        case .add, .addVisit, .sharedVisit:
            didRemove = false
        }
        if didRemove {
            importStore.setIncludedInImport(false, itemID: itemID)
        }
        return didRemove
    }

    private func syncVerifiedChanges() {
        guard auth.isSignedIn else { return }
        Task { @MainActor in
            _ = await store.syncUnsyncedOwnPlaces(backend: backend)
            _ = await store.syncPendingPlaceLists(backend: backend)
        }
    }

    private func startSave() {
        guard !isSaving else { return }
        if reviewPlan.selectedCount == 0 {
            for item in scopedItems {
                importStore.dismiss(itemID: item.id)
            }
            dismiss()
            return
        }
        guard let expectedUserID = auth.state.session?.userID,
              expectedUserID == store.currentUser.id
        else {
            auth.presentGate(for: .syncPlace)
            return
        }
        isSaving = true
        saveTask = Task { @MainActor in
            await commitScopedImports(expectedUserID: expectedUserID)
            isSaving = false
            saveTask = nil
        }
    }

    @MainActor
    private func commitScopedImports(expectedUserID: String) async {
        var allEntries: [PlaceImportReceiptEntry] = []
        var destinationListID: String?

        for batch in scopedBatches {
            guard canContinueCommit(expectedUserID: expectedUserID) else { return }
            let activeItems = importStore.items(for: batch.id)
                .filter { ![.saved, .dismissed].contains($0.state) }
            let excludedItems = activeItems.filter { !$0.isSelectedForImport }
            let items = activeItems.filter(\.isSelectedForImport)
            for item in excludedItems {
                importStore.dismiss(itemID: item.id)
            }
            let ready = items.filter { $0.state == .ready && $0.selectedCandidate != nil }
            let duplicates = items.filter {
                $0.state == .duplicate && $0.duplicateUserPlaceID != nil
            }
            let recovery = items.filter {
                [.ambiguous, .needsHelp, .failed].contains($0.state)
            }
            guard !ready.isEmpty || !duplicates.isEmpty || !recovery.isEmpty else { continue }

            let destination = ready.isEmpty && duplicates.isEmpty
                ? nil
                : destinationList(for: batch, itemCount: items.count)
            let remoteBackend = auth.isSignedIn ? backend : nil
            var entries: [PlaceImportReceiptEntry] = []

            for item in ready {
                guard canContinueCommit(expectedUserID: expectedUserID) else { return }
                guard let candidate = item.selectedCandidate else { continue }
                let existedBeforeCommit = MapPlaceSaveContext.currentUserSave(
                    matching: candidate,
                    in: store.currentUserVisiblePlaces
                ) != nil
                let status = item.stagedStatus
                let result = await store.saveCandidate(
                    candidate,
                    status: status,
                    visibility: .selfOnly,
                    note: item.stagedNote,
                    sourceType: item.source.addSourceType,
                    ratingScore: status == .been ? item.stagedRatingScore : nil,
                    visitedAt: status == .been ? (item.stagedVisitedAt ?? .now) : .now,
                    backend: remoteBackend
                )
                guard canContinueCommit(expectedUserID: expectedUserID) else { return }
                await add(userPlaceID: result.userPlaceID, to: destination, backend: remoteBackend)
                guard canContinueCommit(expectedUserID: expectedUserID) else { return }
                importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
                entries.append(
                    PlaceImportReceiptEntry(
                        itemID: item.id,
                        displayName: item.displayName,
                        displayArea: item.displayArea,
                        status: status,
                        outcome: existedBeforeCommit ? .existing : .added,
                        userPlaceID: result.userPlaceID
                    )
                )
            }

            for item in duplicates {
                guard canContinueCommit(expectedUserID: expectedUserID) else { return }
                guard let userPlaceID = item.duplicateUserPlaceID else { continue }
                let visiblePlace = store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlaceID }
                await add(visiblePlace: visiblePlace, to: destination, backend: remoteBackend)
                guard canContinueCommit(expectedUserID: expectedUserID) else { return }
                importStore.markSaved(itemID: item.id, userPlaceID: userPlaceID)
                entries.append(
                    PlaceImportReceiptEntry(
                        itemID: item.id,
                        displayName: item.displayName,
                        displayArea: item.displayArea,
                        status: visiblePlace?.userPlace.status,
                        outcome: .existing,
                        userPlaceID: userPlaceID
                    )
                )
            }

            entries.append(contentsOf: recovery.map { item in
                return PlaceImportReceiptEntry(
                    itemID: item.id,
                    displayName: item.displayName,
                    displayArea: item.displayArea,
                    status: nil,
                    outcome: .needsReview,
                    userPlaceID: nil
                )
            })

            guard canContinueCommit(expectedUserID: expectedUserID) else { return }
            importStore.recordReceipt(
                batchID: batch.id,
                entries: entries,
                destinationListID: destination?.id
            )
            allEntries.append(contentsOf: entries)
            destinationListID = destination?.id ?? destinationListID
        }

        guard canContinueCommit(expectedUserID: expectedUserID) else { return }
        guard !allEntries.isEmpty else { return }
        let receipt = PlaceImportReceipt(
            batchID: scopedBatches.count == 1 ? scopedBatches[0].id : "combined",
            sourceName: scopedBatches.count == 1 ? scopedBatches[0].sourceName : captureSourceCopy,
            entries: allEntries,
            destinationListID: destinationListID
        )
        completedReceipt = receipt
        markDisplayedReceiptsPresented()
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
        guard batch.source == .googleMaps,
              batch.sourceName != nil || itemCount > 1
        else { return nil }
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

    @MainActor
    private func add(userPlaceID: String, to list: LocalPlaceList?, backend: WanderBackend?) async {
        let visiblePlace = store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlaceID }
        await add(visiblePlace: visiblePlace, to: list, backend: backend)
    }

    @MainActor
    private func add(visiblePlace: VisiblePlace?, to list: LocalPlaceList?, backend: WanderBackend?) async {
        guard let visiblePlace, let list else { return }
        _ = await store.addVisiblePlace(visiblePlace, to: list, backend: backend)
    }

    private func markDisplayedReceiptsPresented() {
        for receipt in scopedBatches.compactMap(\.receipt) where receipt.presentedAt == nil {
            importStore.markReceiptPresented(receiptID: receipt.id)
        }
    }

    private func completionTitle(_ receipt: PlaceImportReceipt) -> String {
        let total = receipt.entries.count
        return total == 1 ? "Review this place" : "Review \(total) places"
    }

    private func completionMetric(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaceImportSourceIconStack: View {
    let iconSize: CGFloat
    private let sources: [PlaceImportSource] = [.googleMaps, .instagram, .tiktok]

    var body: some View {
        HStack(spacing: -9) {
            ForEach(sources) { source in
                PlaceImportSourceIcon(source: source, size: iconSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Google Maps, Instagram, and TikTok")
    }
}

private struct PlaceImportSourceIcon: View {
    let source: PlaceImportSource
    let size: CGFloat

    var body: some View {
        ZStack {
            background

            if let assetName = source.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(source.brandMarkColor)
                    .padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
    }

    @ViewBuilder
    private var background: some View {
        switch source {
        case .googleMaps:
            Circle().fill(Color.white)
        case .instagram:
            Circle().fill(
                LinearGradient(
                    colors: [Color(red: 0.51, green: 0.18, blue: 0.78), Color(red: 0.95, green: 0.19, blue: 0.42), Color(red: 1, green: 0.72, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .tiktok:
            Circle().fill(Color.black)
        case .textNotes:
            Circle().fill(WanderTheme.surfaceSand.color)
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
    @State private var isBulkSaveRunning = false
    @State private var bulkSavedCount = 0
    @State private var presentedReceipt: PlaceImportReceipt?
    @State private var receiptIDsAwaitingPresentation: [String] = []

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
                isBulkSaveRunning = false
                bulkSavedCount = 0
            }
        } message: {
            Text("Are you sure you want to clear the import list?")
        }
        .sheet(item: $saveRoute, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { route in
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
        .sheet(item: $presentedReceipt, onDismiss: receiptDidDismiss) { receipt in
            PlaceImportReceiptSheet(
                receipt: receipt,
                streakCount: store.saveStreakSummary.currentCount,
                isTodayCovered: store.saveStreakSummary.isTodayCovered
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

    private var reviewPlan: PlaceImportReviewPlan {
        PlaceImportReviewPlan(items: inboxItems)
    }

    private var showsBulkSaveButton: Bool {
        selectedFilter == .unresolved && reviewPlan.committableCount > 0
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
                selectedStatus: item.stagedStatus,
                loadsRemotePhoto: auth.isSignedIn,
                statusAction: { importStore.setStagedStatus($0, itemID: item.id) },
                detailsAction: { beginSave(item, status: item.stagedStatus) },
                candidateAction: { candidatePickerItem = item },
                rescueAction: { rescueItem = item },
                retryAction: { importStore.retry(itemID: item.id) },
                dismissAction: {
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
                    isSelected: readyItems.allSatisfy { $0.stagedStatus == .wannaGo },
                    action: { markAll(as: .wannaGo) }
                )
            }

            VStack(spacing: 2) {
                Text("Check in")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                importSelectionButton(
                    status: .been,
                    isSelected: readyItems.allSatisfy { $0.stagedStatus == .been },
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
                Text(reviewPlan.primaryActionTitle ?? "Add places")
                    .font(.system(size: 17, weight: .black))
                if isBulkSaveRunning {
                    Text("\(bulkSavedCount)/\(reviewPlan.committableCount)")
                        .font(.system(size: 12, weight: .black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.18))
                        .clipShape(Capsule())
                }
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
        .accessibilityLabel(reviewPlan.primaryActionTitle ?? "Add imported places")
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
        store.saveFlowDidPresent(.saveSheet)
        saveRoute = PlaceImportSaveRoute(itemID: item.id, status: status, context: context)
    }

    private func markAll(as status: PlaceStatus) {
        withAnimation(.easeInOut(duration: 0.16)) {
            importStore.applyStagedStatus(status)
        }
    }

    private func startBulkSave() {
        guard !isBulkSaveRunning else { return }
        guard auth.isSignedIn else {
            auth.presentGate(for: .syncPlace)
            return
        }
        isBulkSaveRunning = true
        bulkSavedCount = 0
        store.saveFlowDidPresent(.saveSheet)
        Task { @MainActor in
            await commitReadyImports()
        }
    }

    @MainActor
    private func commitReadyImports() async {
        let batchOrder = importStore.batches.sorted { $0.createdAt < $1.createdAt }
        var combinedEntries: [PlaceImportReceiptEntry] = []
        var recordedReceiptIDs: [String] = []
        var lastDestinationListID: String?

        for batch in batchOrder {
            let batchItems = importStore.items(for: batch.id)
            let ready = batchItems.filter { $0.state == .ready && $0.selectedCandidate != nil }
            let duplicates = batchItems.filter {
                $0.state == .duplicate && $0.duplicateUserPlaceID != nil
            }
            guard !ready.isEmpty || !duplicates.isEmpty else { continue }

            let destinationList = destinationList(for: batch, itemCount: batchItems.count)
            let remoteBackend = auth.isSignedIn ? backend : nil
            var entries: [PlaceImportReceiptEntry] = []

            for item in ready {
                guard let candidate = item.selectedCandidate else { continue }
                let existedBeforeCommit = MapPlaceSaveContext.currentUserSave(
                    matching: candidate,
                    in: store.currentUserVisiblePlaces
                ) != nil
                let status = item.stagedStatus
                let result = await store.saveCandidate(
                    candidate,
                    status: status,
                    visibility: .selfOnly,
                    note: nil,
                    sourceType: item.source.addSourceType,
                    backend: remoteBackend
                )
                await add(userPlaceID: result.userPlaceID, to: destinationList, backend: remoteBackend)
                importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
                entries.append(
                    PlaceImportReceiptEntry(
                        itemID: item.id,
                        displayName: item.displayName,
                        displayArea: item.displayArea,
                        status: status,
                        outcome: existedBeforeCommit ? .existing : .added,
                        userPlaceID: result.userPlaceID
                    )
                )
                bulkSavedCount += 1
            }

            for item in duplicates {
                guard let userPlaceID = item.duplicateUserPlaceID else { continue }
                let visiblePlace = store.currentUserVisiblePlaces.first {
                    $0.userPlace.id == userPlaceID
                }
                await add(visiblePlace: visiblePlace, to: destinationList, backend: remoteBackend)
                importStore.markSaved(itemID: item.id, userPlaceID: userPlaceID)
                entries.append(
                    PlaceImportReceiptEntry(
                        itemID: item.id,
                        displayName: item.displayName,
                        displayArea: item.displayArea,
                        status: visiblePlace?.userPlace.status,
                        outcome: .existing,
                        userPlaceID: userPlaceID
                    )
                )
                bulkSavedCount += 1
            }

            entries.append(contentsOf: batchItems.compactMap { item in
                guard [.ambiguous, .needsHelp, .failed].contains(item.state) else { return nil }
                return PlaceImportReceiptEntry(
                    itemID: item.id,
                    displayName: item.displayName,
                    displayArea: item.displayArea,
                    status: nil,
                    outcome: .needsReview,
                    userPlaceID: nil
                )
            })

            importStore.recordReceipt(
                batchID: batch.id,
                entries: entries,
                destinationListID: destinationList?.id
            )
            if let receipt = importStore.batches.first(where: { $0.id == batch.id })?.receipt {
                recordedReceiptIDs.append(receipt.id)
            }
            combinedEntries.append(contentsOf: entries)
            lastDestinationListID = destinationList?.id ?? lastDestinationListID
        }

        isBulkSaveRunning = false
        guard !combinedEntries.isEmpty else {
            store.saveFlowDidDismiss(.saveSheet)
            return
        }
        receiptIDsAwaitingPresentation = recordedReceiptIDs
        presentedReceipt = PlaceImportReceipt(
            batchID: batchOrder.count == 1 ? batchOrder[0].id : "combined",
            sourceName: batchOrder.count == 1 ? batchOrder[0].sourceName : "Imported places",
            entries: combinedEntries,
            destinationListID: lastDestinationListID
        )
    }

    private func destinationList(
        for batch: PlaceImportBatch,
        itemCount: Int
    ) -> LocalPlaceList? {
        guard batch.source == .googleMaps,
              batch.sourceName != nil || itemCount > 1
        else { return nil }
        if let destinationListID = batch.destinationListID,
           let existing = store.visiblePlaceLists.first(where: { $0.id == destinationListID }) {
            return existing
        }
        let existingNames = Set(
            store.visiblePlaceLists
                .filter { $0.ownerUserID == store.currentUser.id }
                .map(\.name)
        )
        let name = PlaceImportDestinationListName.unique(
            batch.sourceName,
            existingNames: existingNames
        )
        guard let list = store.createPlaceList(
            name: name,
            description: "Imported from Google Maps",
            visibility: .stealth
        ) else { return nil }
        importStore.setDestinationListID(list.id, batchID: batch.id)
        return list
    }

    @MainActor
    private func add(
        userPlaceID: String,
        to list: LocalPlaceList?,
        backend: WanderBackend?
    ) async {
        let visiblePlace = store.currentUserVisiblePlaces.first {
            $0.userPlace.id == userPlaceID
        }
        await add(visiblePlace: visiblePlace, to: list, backend: backend)
    }

    @MainActor
    private func add(
        visiblePlace: VisiblePlace?,
        to list: LocalPlaceList?,
        backend: WanderBackend?
    ) async {
        guard let visiblePlace, let list else { return }
        _ = await store.addVisiblePlace(visiblePlace, to: list, backend: backend)
    }

    private func receiptDidDismiss() {
        for receiptID in receiptIDsAwaitingPresentation {
            importStore.markReceiptPresented(receiptID: receiptID)
        }
        receiptIDsAwaitingPresentation = []
        store.saveFlowDidDismiss(.saveSheet)
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

private struct PlaceImportReceiptSheet: View {
    let receipt: PlaceImportReceipt
    let streakCount: Int
    let isTodayCovered: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    summaryCard

                    VStack(spacing: 0) {
                        ForEach(receipt.entries) { entry in
                            receiptRow(entry)

                            if entry.id != receipt.entries.last?.id {
                                Divider()
                                    .overlay(WanderTheme.borderHairline.color)
                                    .padding(.leading, 46)
                            }
                        }
                    }
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                }
                .padding(WanderTheme.spacing4)
            }
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Import saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(WanderTheme.stateSuccess.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    if let sourceName = receipt.sourceName,
                       !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(sourceName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }
                }
            }

            HStack(spacing: WanderTheme.spacing2) {
                if receipt.addedCount > 0 {
                    receiptMetric(receipt.addedCount, "added", WanderTheme.stateSuccess.color)
                }
                if receipt.existingCount > 0 {
                    receiptMetric(receipt.existingCount, "already saved", WanderTheme.stateInfo.color)
                }
                if receipt.needsReviewCount > 0 {
                    receiptMetric(receipt.needsReviewCount, "needs review", WanderTheme.stateWarning.color)
                }
            }

            if isTodayCovered {
                Label(
                    streakCount == 1 ? "Today is covered" : "Today is covered · \(streakCount)-day streak",
                    systemImage: "flame.fill"
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Capsule())
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var summaryTitle: String {
        let savedCount = receipt.addedCount + receipt.existingCount
        if savedCount == 0 {
            return "Nothing added yet"
        }
        return savedCount == 1 ? "1 place saved" : "\(savedCount) places saved"
    }

    private func receiptMetric(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func receiptRow(_ entry: PlaceImportReceiptEntry) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: entry.outcome.receiptSystemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(entry.outcome.receiptColor)
                .frame(width: 28, height: 28)
                .background(entry.outcome.receiptColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(2)
                Text(entry.receiptDetail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button("Edit") {
                openAddSearch(for: entry)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(entry.displayName) in Add search")
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
    }

    private func openAddSearch(for entry: PlaceImportReceiptEntry) {
        let query = [entry.displayName, entry.displayArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard let url = WanderDeepLinkRoute.addSearch(query: query).url else { return }
        dismiss()
        DispatchQueue.main.async {
            openURL(url)
        }
    }
}

private extension PlaceImportReceiptOutcome {
    var receiptSystemImage: String {
        switch self {
        case .added: "plus"
        case .existing: "checkmark"
        case .needsReview: "magnifyingglass"
        case .failed: "exclamationmark"
        }
    }

    var receiptColor: Color {
        switch self {
        case .added: WanderTheme.stateSuccess.color
        case .existing: WanderTheme.stateInfo.color
        case .needsReview: WanderTheme.stateWarning.color
        case .failed: WanderTheme.stateError.color
        }
    }
}

private extension PlaceImportReceiptEntry {
    var receiptDetail: String {
        let outcomeCopy = switch outcome {
        case .added: status == .been ? CheckInCopy.noun : "Wanna"
        case .existing: "Already in your places"
        case .needsReview: "Needs a place match"
        case .failed: "Could not save"
        }
        guard let displayArea,
              !displayArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return outcomeCopy }
        return "\(outcomeCopy) · \(displayArea)"
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
    let detailsAction: () -> Void
    let candidateAction: () -> Void
    let rescueAction: () -> Void
    let retryAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
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

                importItemMenu(
                    item: item,
                    detailsAction: detailsAction,
                    candidateAction: candidateAction,
                    rescueAction: rescueAction,
                    retryAction: retryAction,
                    dismissAction: dismissAction
                )
            }

            if item.state == .ready {
                HStack(spacing: WanderTheme.spacing2) {
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

                    Spacer(minLength: 0)

                    Button("Edit place", systemImage: "magnifyingglass", action: rescueAction)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, WanderTheme.spacing1)
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
            Label(
                status == .been ? CheckInCopy.noun : "Wanna",
                systemImage: status == .been ? "checkmark.circle.fill" : "bookmark.fill"
            )
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(isSelected ? status.importColor : WanderTheme.surfaceRaised.color)
                .foregroundStyle(isSelected ? Color.white : status.importColor)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(status.importColor.opacity(0.28), lineWidth: 1))
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
    detailsAction: @escaping () -> Void,
    candidateAction: @escaping () -> Void,
    rescueAction: @escaping () -> Void,
    retryAction: @escaping () -> Void,
    dismissAction: @escaping () -> Void
) -> some View {
    Menu {
        if item.state == .ready {
            Button("Add optional details", systemImage: "slider.horizontal.3", action: detailsAction)
        }
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
            $0.compactPlaceType
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
                    attributes: store.attributes(for: visiblePlace.userPlace.id),
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
            }
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id),
                viewerFollowsOwner: false
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
        let title = compactPlaceType
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

enum PlaceImportAdaptiveMockupPage {
    static var isPresented: Bool {
        ProcessInfo.processInfo.arguments.contains("-WanderPlaceImportAdaptiveMockup")
    }
}

@MainActor
struct PlaceImportAdaptiveMockupRoot: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @StateObject private var importStore: PlaceImportStore

    init() {
        _importStore = StateObject(
            wrappedValue: PlaceImportStore(
                persistence: PlaceImportAdaptiveMockupPersistence(snapshot: Self.snapshot),
                resolver: PlaceImportAdaptiveMockupResolver()
            )
        )
    }

    var body: some View {
        NavigationStack {
            PlaceImportAdaptiveReviewScreen(
                importStore: importStore,
                batchIDs: [Self.batchID],
                onViewMap: {}
            )
        }
        .environmentObject(store)
        .preferredColorScheme(.light)
    }

    private static let batchID = "rec-227-adaptive-mockup"
    private static let snapshot = PlaceImportSnapshot(
        batches: [
            PlaceImportBatch(
                id: batchID,
                source: .instagram,
                sourceName: "Instagram",
                state: .ready,
                totalCount: 3,
                processedCount: 3
            )
        ],
        items: [
            item(
                id: "mart-collective",
                name: "The Mart Collective",
                area: "Venice, CA",
                category: "antique store"
            ),
            item(
                id: "gjusta",
                name: "Gjusta",
                area: "Venice, CA",
                category: "bakery",
                status: .been,
                isIncluded: false
            ),
            PlaceImportItem(
                id: "manual-match",
                batchID: batchID,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: "Instagram post",
                    nameHint: "Little lunch spot",
                    areaHint: "Los Angeles",
                    sourceURLString: "https://www.instagram.com/p/recme-mockup/",
                    sourceLine: 3
                ),
                state: .needsHelp,
                helpMessage: "We found the name in the post, but need your help choosing the place."
            )
        ]
    )

    private static func item(
        id: String,
        name: String,
        area: String,
        category: String,
        status: PlaceStatus = .wannaGo,
        isIncluded: Bool = true
    ) -> PlaceImportItem {
        let candidate = PlaceCandidate(
            id: "candidate-\(id)",
            name: name,
            category: category,
            address: area,
            locality: area.components(separatedBy: ",").first,
            region: "CA",
            country: "United States",
            latitude: 33.99,
            longitude: -118.46,
            sourceProvider: "apple_maps",
            sourceProviderPlaceID: "mock-\(id)",
            confidence: 0.96
        )
        return PlaceImportItem(
            id: id,
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: name,
                nameHint: name,
                areaHint: area,
                sourceURLString: "https://www.instagram.com/p/recme-mockup/",
                sourceLine: status == .been ? 2 : 1
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            stagedStatus: status,
            isIncludedInImport: isIncluded
        )
    }
}

private final class PlaceImportAdaptiveMockupPersistence: PlaceImportPersisting {
    private var snapshot: PlaceImportSnapshot

    init(snapshot: PlaceImportSnapshot) {
        self.snapshot = snapshot
    }

    func load() throws -> PlaceImportSnapshot { snapshot }
    func save(_ snapshot: PlaceImportSnapshot) throws { self.snapshot = snapshot }
}

@MainActor
private final class PlaceImportAdaptiveMockupResolver: PlaceImportResolving {
    func resolve(seed _: PlaceImportSeed, source _: PlaceImportSource) async throws -> PlaceImportResolution {
        .needsHelp("Search for the place.")
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

extension PlaceImportSource {
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

    var brandAssetName: String? {
        switch self {
        case .googleMaps: "BrandGoogleMaps"
        case .instagram: "BrandInstagram"
        case .tiktok: "BrandTikTok"
        case .textNotes: nil
        }
    }

    var brandMarkColor: Color {
        switch self {
        case .googleMaps: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .instagram, .tiktok: Color.white
        case .textNotes: WanderTheme.textInk.color
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

    var addSourceType: AddSourceType {
        switch self {
        case .googleMaps, .instagram, .tiktok: .link
        case .textNotes: .manual
        }
    }
}
