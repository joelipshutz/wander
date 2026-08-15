import CoreLocation
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum AddSheetLayout {
    static let emptyRestingHeight: CGFloat = 520
    static let pendingReviewRestingHeight: CGFloat = 570

    static func restingDetent(hasPendingImports: Bool) -> PresentationDetent {
        .height(hasPendingImports ? pendingReviewRestingHeight : emptyRestingHeight)
    }

    static func detents(hasPendingImports: Bool) -> Set<PresentationDetent> {
        [restingDetent(hasPendingImports: hasPendingImports), .large]
    }
}

enum AddSuggestedPlaces {
    static let maximumCount = 7
    static let rowHeight: CGFloat = 58
    static let rowSpacing: CGFloat = 8
    static let showMoreHeight: CGFloat = 44

    static func previewCount(screenHeight: CGFloat) -> Int {
        if screenHeight >= 900 { return 3 }
        if screenHeight >= 800 { return 2 }
        return 1
    }

    static func limited(_ candidates: [PlaceCandidate]) -> [PlaceCandidate] {
        Array(candidates.prefix(maximumCount))
    }

    static func visible(_ candidates: [PlaceCandidate], count: Int) -> [PlaceCandidate] {
        Array(candidates.prefix(max(0, count)))
    }
}

struct AddScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @ObservedObject var importStore: PlaceImportStore
    @ObservedObject var placeSaveDraftStore: PlaceSaveDraftStore
    let resetToken: UUID
    @Binding private var selectedDetent: PresentationDetent
    let launchRequest: WanderAddLaunchRequest?
    let onLaunchRequestHandled: (UUID) -> Void
    let onClose: () -> Void
    @State private var step: AddStep = .source
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var selectedSource: AddSourceType = .manual
    @State private var manualName = ""
    @State private var quickAddQuery = ""
    @State private var isShowingInlineCandidateResults = false
    @State private var suggestedCandidates: [PlaceCandidate] = []
    @State private var isLoadingSuggestions = false
    @State private var suggestionMessage: String?
    @State private var hasRequestedSuggestions = false
    @State private var draft: UnresolvedDraft?
    @State private var isResolvingCandidates = false
    @State private var resolutionMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
    @State private var pendingVisitPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    @State private var closesAfterSaveFlowDismiss = false
    @State private var isImportingPhoto = false
    @State private var addSaveFlow: MapPlaceSaveContext?
    @State private var showsImportHub = ProcessInfo.processInfo.arguments.contains(
        "-WanderOpenImportHub"
    )
    @State private var showsImportInbox = false
    @State private var isAutoClosingWalkthrough = false
    @State private var showsImportReview = false
    @State private var importReviewBatchIDs: [String] = []
    @FocusState private var isQuickAddFocused: Bool

    init(
        importStore: PlaceImportStore,
        placeSaveDraftStore: PlaceSaveDraftStore,
        resetToken: UUID = UUID(),
        selectedDetent: Binding<PresentationDetent>,
        launchRequest: WanderAddLaunchRequest? = nil,
        onLaunchRequestHandled: @escaping (UUID) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        self.importStore = importStore
        self.placeSaveDraftStore = placeSaveDraftStore
        self.resetToken = resetToken
        _selectedDetent = selectedDetent
        self.launchRequest = launchRequest
        self.onLaunchRequestHandled = onLaunchRequestHandled
        self.onClose = onClose
    }

    private var selectedCandidate: PlaceCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    private var restingDetent: PresentationDetent {
        AddSheetLayout.restingDetent(hasPendingImports: importStore.summary.hasPendingImports)
    }

    private var showsFloatingCurrentLocationAction: Bool {
        isShowingInlineCandidateResults
            && selectedSource == .currentLocation
            && selectedCandidate != nil
    }

    private var showsPinnedImportEntry: Bool {
        step == .source && !isShowingInlineCandidateResults
    }

    private var isShowingHereNowResults: Bool {
        isShowingInlineCandidateResults && selectedSource == .currentLocation
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsPinnedImportEntry {
                    compactSheetContent
                } else {
                    scrollableFlowContent
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFloatingCurrentLocationAction {
                    floatingCandidateAction
                }
            }
            .wanderScreen()
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains(
                    "-WanderShowWalkthroughCandidateResults"
                ) {
                    prepareWalkthroughCandidateResults()
                }
                if showsImportHub {
                    expandSheet()
                }
            }
            .onChange(of: resetToken) { _, _ in
                reset()
            }
            .onChange(of: walkthroughs.activeSurface, initial: true) { _, activeSurface in
                if activeSurface == .add {
                    expandSheet()
                }
            }
            .task(id: resetToken) {
                await loadNearbySuggestionsIfNeeded()
            }
            .onChange(of: isQuickAddFocused) { _, isFocused in
                if isFocused {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard isQuickAddFocused else { return }
                        expandSheet()
                    }
                } else if !shouldStayExpanded {
                    withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
                        selectedDetent = restingDetent
                    }
                }
            }
            .onChange(of: selectedDetent) { _, detent in
                guard detent == restingDetent, isQuickAddFocused else { return }
                isQuickAddFocused = false
            }
            .task(id: launchRequest?.id) {
                guard let launchRequest else { return }
                switch launchRequest.destination {
                case .hereNow:
                    expandSheet()
                    await resolveCurrentLocationCandidates()
                case .importHub:
                    expandSheet()
                    showsImportHub = true
                case .search(let query):
                    expandSheet()
                    quickAddQuery = query
                    manualName = query
                    await resolveQuickAddQuery()
                case .importInbox:
                    expandSheet()
                    showsImportInbox = true
                case .importReview(let batchIDs):
                    openImportReview(batchIDs: batchIDs)
                case .nearbyPlace(let candidate):
                    expandSheet()
                    selectedSource = .currentLocation
                    candidates = [candidate]
                    selectedCandidateID = candidate.id
                    pendingVisitPhotoAttachments = []
                    presentSaveFlow(addCandidateContext(
                        candidate,
                        sourceType: .currentLocation,
                        defaultVisibility: store.effectiveDefaultVisibility
                    ))
                }
                guard !Task.isCancelled else { return }
                onLaunchRequestHandled(launchRequest.id)
            }
            .task(id: placeSaveDraftStore.draft?.id) {
                restoreActiveSaveFlowIfNeeded()
            }
            .sheet(item: $addSaveFlow, onDismiss: {
                placeSaveDraftStore.clear()
                store.saveFlowDidDismiss(.saveSheet)
                if closesAfterSaveFlowDismiss {
                    closesAfterSaveFlowDismiss = false
                    onClose()
                }
            }) { context in
                MapPlaceSaveFlowSheet(
                    context: context,
                    draft: placeSaveDraftStore.draft,
                    onDraftChange: { draftID, form, submittedAt in
                        placeSaveDraftStore.update(
                            draftID: draftID,
                            form: form,
                            submittedAt: submittedAt
                        )
                    }
                ) { submission in
                    await saveSharedSubmission(submission)
                } onRemove: { _ in
                    false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsCamera) {
                AddCameraPicker { image in
                    Task {
                        await importCapturedPhoto(image)
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    await importPhotoDraft(from: item)
                }
            }
            .navigationDestination(isPresented: $showsImportHub) {
                PlaceImportHubScreen(
                    importStore: importStore,
                    reviewAction: openImportReview,
                    inboxAction: openImportInbox
                )
            }
            .navigationDestination(isPresented: $showsImportReview) {
                PlaceImportAdaptiveReviewScreen(
                    importStore: importStore,
                    batchIDs: importReviewBatchIDs,
                    onViewMap: onClose
                )
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
            }
            .navigationDestination(isPresented: $showsImportInbox) {
                PlaceImportInboxScreen(importStore: importStore)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
        }
        .walkthroughPresenterScrim(
            isPresented: addSaveFlow != nil && walkthroughs.activeSurface == .saveFlow
        )
        .firstVisitWalkthroughOverlay(walkthroughs, surface: .add)
        .onChange(of: walkthroughs.currentStep?.target) { _, target in
            autoCloseAfterImportIfNeeded(target)
        }
    }

    private var compactSheetContent: some View {
        VStack(spacing: 0) {
            compactSourceContent

            AddImportEntrySection(
                summary: importStore.summary,
                action: {
                    walkthroughs.perform(.addImport)
                    openImportHub()
                }
            )
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing3)
            .background(WanderTheme.canvasWarm.color)
            .walkthroughTarget(.addImport)
        }
    }

    private var compactSourceContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                header
                suggestedPlaces

                if let resolutionMessage {
                    InlineMessage(text: resolutionMessage)
                }
            }
            .walkthroughTarget(.addSearch)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing4)
    }

    private var scrollableFlowContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                header

                switch step {
                case .source:
                    sourcePicker
                case .confirm:
                    confirmPlace
                case .draft:
                    draftView
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, walkthroughCandidateCoachClearance)
        }
    }

    private var walkthroughCandidateCoachClearance: CGFloat {
        walkthroughs.activeSurface == .add
            && walkthroughs.currentStep?.target == .addPlace
            ? 260
            : WanderTheme.spacing8
    }

    private var header: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            if step.canGoBack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isShowingHereNowResults ? "I'm here now" : "add a place")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(isShowingHereNowResults ? "choose the place you're at" : step.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Button {
                walkthroughs.perform(.addClose)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(width: 30, height: 30)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(Circle())
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close add place")
            .walkthroughTarget(.addClose)
            .disabled(
                walkthroughs.activeSurface == .add
                    && walkthroughs.currentStep?.target != .addClose
            )
            .accessibilityHidden(
                walkthroughs.activeSurface == .add
                    && walkthroughs.currentStep?.target != .addClose
            )
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            if isShowingInlineCandidateResults {
                searchField

                Button {
                    clearInlineCandidateResults()
                } label: {
                    Label("back to add options", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to add options")

                confirmPlace

                if let resolutionMessage {
                    InlineMessage(text: resolutionMessage)
                }
            }
        }
    }

    private var searchField: some View {
        AddSearchField(
            query: $quickAddQuery,
            isLoading: isResolvingCandidates || isImportingPhoto,
            isFocused: $isQuickAddFocused,
            isCameraAvailable: isCameraAvailable,
            submit: {
                expandSheet()
                isQuickAddFocused = false
                Task {
                    await resolveQuickAddQuery()
                }
            },
            takePhoto: {
                showsCamera = true
            },
            chooseFromLibrary: {
                showsPhotoLibrary = true
            }
        )
        .walkthroughEmphasis(.addSearch)
    }

    private var suggestedPlaces: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("Suggested")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .accessibilityAddTraits(.isHeader)

            searchField

            if isLoadingSuggestions {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                        .tint(WanderTheme.terracotta.color)
                    Text("Finding places near you…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(minHeight: 82)
            } else if !suggestedCandidates.isEmpty {
                suggestedPlacePreview(
                    count: AddSuggestedPlaces.previewCount(
                        screenHeight: UIScreen.main.bounds.height
                    )
                )
            } else {
                Button {
                    hasRequestedSuggestions = false
                    Task {
                        await loadNearbySuggestionsIfNeeded()
                    }
                } label: {
                    Label(
                        suggestionMessage ?? "Use your location to suggest nearby places",
                        systemImage: "location.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Tries nearby suggestions again")
            }
        }
    }

    private func suggestedPlacePreview(count: Int) -> some View {
        let visibleCandidates = AddSuggestedPlaces.visible(suggestedCandidates, count: count)
        let hasMore = visibleCandidates.count < suggestedCandidates.count

        return VStack(spacing: AddSuggestedPlaces.rowSpacing) {
            ForEach(visibleCandidates) { candidate in
                SuggestedPlaceCard(candidate: candidate) {
                    openSuggestedCandidate(candidate)
                }
            }

            if hasMore {
                Button {
                    walkthroughs.perform(.addSearch)
                    expandSheet()
                    Task {
                        await resolveCurrentLocationCandidates()
                    }
                } label: {
                    Label("See more", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(maxWidth: .infinity, minHeight: AddSuggestedPlaces.showMoreHeight)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens all nearby suggestions in the full-screen nearby view")
            }
        }
    }

    private var confirmPlace: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(spacing: WanderTheme.spacing2) {
                ForEach(candidates) { candidate in
                    CandidateRow(candidate: candidate, isSelected: selectedCandidate?.id == candidate.id) {
                        selectedCandidateID = candidate.id
                    }
                }
            }

            if !showsFloatingCurrentLocationAction {
                candidateSaveAction
            }
        }
        .walkthroughTarget(showsFloatingCurrentLocationAction ? nil : .addPlace)
    }

    private var floatingCandidateAction: some View {
        candidateSaveAction
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing3)
            .background(
                LinearGradient(
                    colors: [
                        WanderTheme.canvasWarm.color.opacity(0),
                        WanderTheme.canvasWarm.color.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.16), radius: 8, y: 4)
            .walkthroughTarget(.addPlace)
    }

    private var candidateSaveAction: some View {
        WanderPrimaryButton(title: "Save", systemImage: "arrow.right") {
            openSharedSaveFlow()
        }
    }

    private func autoCloseAfterImportIfNeeded(_ target: WalkthroughTargetID?) {
        guard target == .addClose,
              walkthroughs.activeSurface == .add,
              !isAutoClosingWalkthrough
        else { return }

        isAutoClosingWalkthrough = true
        Task { @MainActor in
            await Task.yield()
            guard walkthroughs.currentStep?.target == .addClose else {
                isAutoClosingWalkthrough = false
                return
            }
            walkthroughs.perform(.addClose)
            onClose()
        }
    }

    private func prepareWalkthroughCandidateResults() {
        let previewCandidates = [
            PlaceCandidate(
                id: "walkthrough-maru",
                name: "Maru Coffee",
                category: "coffee",
                address: "1936 Hillhurst Ave",
                locality: "Los Angeles",
                latitude: 34.1062,
                longitude: -118.2870,
                confidence: 0.96
            ),
            PlaceCandidate(
                id: "walkthrough-dayglow",
                name: "Dayglow Coffee",
                category: "coffee",
                address: "3206 Sunset Blvd",
                locality: "Los Angeles",
                latitude: 34.0854,
                longitude: -118.2755,
                confidence: 0.94
            )
        ]

        selectedSource = .manual
        candidates = previewCandidates
        selectedCandidateID = previewCandidates[0].id
        quickAddQuery = "Coffee"
        resolutionMessage = nil
        isShowingInlineCandidateResults = true
        step = .source
        expandSheet()
    }

    private var draftView: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)

            Text(draft?.title ?? "Draft saved.")
                .font(.system(size: 22, weight: .bold))
            Text(draft?.message ?? "You can finish this manually.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)

            WanderPrimaryButton(title: "try another search", systemImage: "magnifyingglass") {
                step = .source
                expandSheet()
                isQuickAddFocused = true
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func reset() {
        step = .source
        candidates = []
        selectedCandidateID = nil
        selectedSource = .manual
        manualName = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        suggestedCandidates = []
        isLoadingSuggestions = false
        suggestionMessage = nil
        hasRequestedSuggestions = false
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        showsPhotoLibrary = false
        showsCamera = false
        pendingVisitPhotoAttachments = []
        isImportingPhoto = false
        addSaveFlow = nil
        placeSaveDraftStore.clear()
        showsImportHub = false
        showsImportInbox = false
        selectedDetent = restingDetent
    }

    private func resetAfterSave() {
        step = .source
        candidates = []
        selectedCandidateID = nil
        selectedSource = .manual
        manualName = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        pendingVisitPhotoAttachments = []
        isImportingPhoto = false
    }

    private func goBack() {
        resolutionMessage = nil

        switch step {
        case .confirm:
            step = .source
        case .draft:
            step = .source
        case .source:
            break
        }

        if step == .source {
            selectedDetent = restingDetent
        }
    }

    private var shouldStayExpanded: Bool {
        step != .source
            || isShowingInlineCandidateResults
            || isResolvingCandidates
            || !quickAddQuery.isEmpty
    }

    private func expandSheet() {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            selectedDetent = .large
        }
    }

    private func openImportHub() {
        expandSheet()
        showsImportHub = true
    }

    private func openImportInbox() {
        expandSheet()
        showsImportInbox = true
    }

    private func openImportReview(batchIDs: [String]) {
        guard !batchIDs.isEmpty else { return }
        expandSheet()
        importReviewBatchIDs = batchIDs
        showsImportReview = true
    }

    private func openSharedSaveFlow() {
        guard let selectedCandidate else { return }

        walkthroughs.perform(.addPlace)
        walkthroughs.activate(.saveFlow)
        presentSaveFlow(addCandidateContext(
            selectedCandidate,
            sourceType: selectedSource,
            defaultVisibility: store.effectiveDefaultVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        ))
    }

    private func presentSaveFlow(_ context: MapPlaceSaveContext) {
        if let draft = PlaceSaveDraft.addFlow(
            ownerUserID: store.currentUser.id,
            context: context
        ) {
            placeSaveDraftStore.begin(draft)
        }
        addSaveFlow = context
    }

    private func restoreActiveSaveFlowIfNeeded() {
        guard addSaveFlow == nil,
              let draft = placeSaveDraftStore.draft,
              draft.ownerUserID == store.currentUser.id
        else { return }

        selectedSource = draft.sourceType
        candidates = [draft.candidate]
        selectedCandidateID = draft.candidate.id
        pendingVisitPhotoAttachments = draft.form.photoAttachments.compactMap(
            MapPlaceSavePhotoAttachment.restore
        )
        var context = addCandidateContext(
            draft.candidate,
            sourceType: draft.sourceType,
            defaultVisibility: draft.form.selectedVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        )
        if draft.form.step == .details {
            context = context.resolvingExistingSave(selection: draft.form.selectedStatus)
        }
        selectedDetent = .large
        addSaveFlow = context
    }

    private func addCandidateContext(
        _ candidate: PlaceCandidate,
        sourceType: AddSourceType,
        defaultVisibility: PlaceVisibility,
        initialPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    ) -> MapPlaceSaveContext {
        let currentUserSave = MapPlaceSaveContext.currentUserSave(
            matching: candidate,
            in: store.currentUserVisiblePlaces
        )
        return MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: sourceType,
            defaultVisibility: defaultVisibility,
            initialPhotoAttachments: initialPhotoAttachments,
            currentUserSave: currentUserSave,
            latestVisit: currentUserSave.flatMap {
                store.visits(for: $0.userPlace.id).first
            }
        )
    }

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private func openSuggestedCandidate(_ candidate: PlaceCandidate) {
        walkthroughs.perform(.addSearch)
        expandSheet()
        selectedSource = .currentLocation
        candidates = [candidate]
        selectedCandidateID = candidate.id
        pendingVisitPhotoAttachments = []
        openSharedSaveFlow()
    }

    @MainActor
    private func loadNearbySuggestionsIfNeeded() async {
        guard !hasRequestedSuggestions else { return }
        hasRequestedSuggestions = true
        isLoadingSuggestions = true
        suggestionMessage = nil
        defer { isLoadingSuggestions = false }

        do {
            let nearby = try await store.currentLocationCandidates()
            suggestedCandidates = AddSuggestedPlaces.limited(nearby)
            if suggestedCandidates.isEmpty {
                suggestionMessage = "No nearby places found. Tap to try again."
            }
        } catch {
            suggestedCandidates = []
            suggestionMessage = resolutionCopy(for: error)
        }
    }

    @MainActor
    private func saveSharedSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        guard let result = await persistAddPlaceSaveSubmission(
            submission,
            store: store,
            backend: auth.isSignedIn ? backend : nil
        ) else { return nil }

        placeSaveDraftStore.clear()
        let needsSignIn = !auth.isSignedIn
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        resetAfterSave()
        closesAfterSaveFlowDismiss = true
        if needsSignIn {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                auth.presentGate(for: .syncPlace)
            }
        }
        return result
    }

    @MainActor
    private func resolveCurrentLocationCandidates() async {
        selectedSource = .currentLocation
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
        isResolvingCandidates = true
        defer { isResolvingCandidates = false }

        do {
            candidates = try await store.currentLocationCandidates()
            selectedCandidateID = candidates.first?.id
            guard !candidates.isEmpty else {
                resolutionMessage = PlaceResolutionError.noCandidates.localizedDescription
                return
            }
            isShowingInlineCandidateResults = true
            step = .source
        } catch {
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolutionCopy(for: error)
        }
    }

    @MainActor
    private func resolveManualCandidates(inline: Bool = false) async {
        selectedSource = .manual
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
        isResolvingCandidates = true
        defer { isResolvingCandidates = false }

        do {
            candidates = try await store.manualCandidates(
                name: manualName,
                areaHint: nil,
                category: nil
            )
            selectedCandidateID = candidates.first?.id
            guard !candidates.isEmpty else {
                resolutionMessage = PlaceResolutionError.noCandidates.localizedDescription
                return
            }
            isShowingInlineCandidateResults = inline
            step = inline ? .source : .confirm
            if inline {
                walkthroughs.perform(.addSearch)
            }
        } catch {
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolutionCopy(for: error)
        }
    }

    @MainActor
    private func resolveQuickAddQuery() async {
        let query = quickAddQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let coordinate = Self.coordinate(from: query) {
            await resolveCoordinateCandidates(coordinate)
        } else {
            manualName = query
            await resolveManualCandidates(inline: true)
        }
    }

    @MainActor
    private func resolveCoordinateCandidates(_ coordinate: CLLocationCoordinate2D) async {
        selectedSource = .manual
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
        isResolvingCandidates = true
        defer { isResolvingCandidates = false }

        do {
            candidates = try await store.photoLocationCandidates(near: coordinate)
            selectedCandidateID = candidates.first?.id
            guard !candidates.isEmpty else {
                resolutionMessage = PlaceResolutionError.noCandidates.localizedDescription
                return
            }
            isShowingInlineCandidateResults = true
            step = .source
        } catch {
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolutionCopy(for: error)
        }
    }

    private func clearInlineCandidateResults() {
        candidates = []
        selectedCandidateID = nil
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
        quickAddQuery = ""
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
            selectedDetent = restingDetent
        }
    }

    static func coordinate(from value: String) -> CLLocationCoordinate2D? {
        let pattern = #"[-+]?\d{1,3}(?:\.\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let values = expression.matches(in: value, range: range).compactMap { match -> Double? in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return Double(value[swiftRange])
        }
        guard values.count == 2 else { return nil }

        let uppercased = value.uppercased()
        let latitude = uppercased.contains("S") ? -abs(values[0]) : values[0]
        let longitude = uppercased.contains("W") ? -abs(values[1]) : values[1]
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    @MainActor
    private func importPhotoDraft(from item: PhotosPickerItem) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw WanderImageProcessingError.invalidImageData
            }
            let assetRef = item.itemIdentifier.map { "photos_picker:\($0)" }
            await importPhotoDraft(data: data, assetRef: assetRef)
        } catch {
            resolutionMessage = "Could not import that photo. Try another one or search by name."
        }
    }

    @MainActor
    private func importCapturedPhoto(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            resolutionMessage = "Could not use that photo. Try another one or search by name."
            return
        }
        await importPhotoDraft(
            data: data,
            assetRef: "camera:capture_\(UUID().uuidString.lowercased())"
        )
    }

    @MainActor
    private func importPhotoDraft(data: Data, assetRef: String?) async {
        selectedSource = .photo
        resolutionMessage = nil
        isImportingPhoto = true
        expandSheet()
        defer { isImportingPhoto = false }

        let recognizedText = await recognizeText(in: data)
        let photoCoordinate = PhotoPlaceMetadataExtractor.coordinate(from: data)
        let resolution = await PhotoPlaceImportResolver.resolve(
            recognizedText: recognizedText,
            photoCoordinate: photoCoordinate,
            searcher: store
        )

        if applyPhotoImportResolution(resolution) {
            if let image = UIImage(data: data),
               let attachment = MapPlaceSavePhotoAttachment.make(
                   image: image,
                   data: data,
                   fallbackAssetRef: assetRef
               ) {
                pendingVisitPhotoAttachments = [attachment]
            } else {
                pendingVisitPhotoAttachments = []
            }
            return
        }

        let resolvedAssetRef = assetRef ?? "photo:imported_\(data.count)"
        draft = await store.createUnresolvedDraft(
            sourceType: .photo,
            originalInput: "photo import · \(data.count) bytes",
            localAssetRef: resolvedAssetRef,
            backend: auth.isSignedIn ? backend : nil
        )

        if auth.isSignedIn,
           let draft,
           let result = await store.processExtractionJob(for: draft, backend: backend),
           applyExtractionResult(result, source: .photo) {
            return
        }

        step = .draft
    }

    @MainActor
    private func applyPhotoImportResolution(_ resolution: PhotoPlaceImportResolution) -> Bool {
        switch resolution.outcome {
        case .candidates:
            guard !resolution.candidates.isEmpty else { return false }

            selectedSource = .photo
            manualName = resolution.manualName ?? resolution.candidates.first?.name ?? ""
            candidates = resolution.candidates
            selectedCandidateID = resolution.candidates.first?.id
            resolutionMessage = resolution.message
            step = .confirm
            return true
        case .manualRescue:
            selectedSource = .manual
            manualName = resolution.manualName ?? ""
            quickAddQuery = manualName
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolution.message
            step = .source
            expandSheet()
            return true
        case .draft:
            resolutionMessage = resolution.message
            return false
        }
    }

    private func recognizeText(in data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data),
                  let cgImage = image.cgImage
            else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            try? handler.perform([request])
            let lines = request.results?.compactMap { observation in
                observation.topCandidates(1).first?.string
            } ?? []
            let text = lines.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }

    @MainActor
    private func applyExtractionResult(_ result: ExtractionJobResult, source: AddSourceType) -> Bool {
        let resolvedCandidates = ExtractionCandidateFilter.confirmableCandidates(from: result)
        guard !resolvedCandidates.isEmpty
        else {
            return false
        }

        selectedSource = source
        candidates = resolvedCandidates
        selectedCandidateID = resolvedCandidates.first?.id
        resolutionMessage = nil
        step = .confirm
        return true
    }

    private func resolutionCopy(for error: Error) -> String {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            return description
        }

        return "Could not find matching places. Try a more specific name or add a nearby area."
    }

}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

enum ExtractionCandidateFilter {
    static let minimumConfidence = 0.70

    static func confirmableCandidates(from result: ExtractionJobResult) -> [PlaceCandidate] {
        guard result.status == .needsConfirmation || result.status == .complete,
              result.confidence >= minimumConfidence
        else {
            return []
        }

        return result.candidates.filter { candidate in
            candidate.latitude != nil
                && candidate.longitude != nil
                && candidate.confidence >= minimumConfidence
        }
    }
}

private enum AddStep {
    case source
    case confirm
    case draft

    var subtitle: String {
        switch self {
        case .source: "find it nearby, search, or import"
        case .confirm: "Pick the right place, then save it."
        case .draft: "we could not find enough place info yet."
        }
    }

    var canGoBack: Bool {
        switch self {
        case .confirm, .draft:
            true
        case .source:
            false
        }
    }
}

private struct AddSearchField: View {
    @Binding var query: String
    let isLoading: Bool
    let isFocused: FocusState<Bool>.Binding
    let isCameraAvailable: Bool
    let submit: () -> Void
    let takePhoto: () -> Void
    let chooseFromLibrary: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: isLoading ? "hourglass" : "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField(
                "",
                text: $query,
                prompt: Text("Search for a place")
                    .foregroundStyle(WanderTheme.textFaint.color)
            )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .focused(isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(submit)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear add search")
            }

            Menu {
                Button(action: takePhoto) {
                    Label("Take a Photo", systemImage: "camera")
                }
                .disabled(!isCameraAvailable)

                Button(action: chooseFromLibrary) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .black))
                }
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Add from a photo")
            .accessibilityHint("Choose Take a Photo or Photo Library")
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 48)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                isFocused.wrappedValue
                    ? WanderTheme.terracotta.color.opacity(0.7)
                    : WanderTheme.borderHairline.color,
                lineWidth: isFocused.wrappedValue ? 1.5 : 1
            )
        )
        .animation(.easeOut(duration: 0.16), value: isFocused.wrappedValue)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search for a place")
        .disabled(isLoading)
        .opacity(isLoading ? 0.78 : 1)
    }
}

private struct SuggestedPlaceCard: View {
    let candidate: PlaceCandidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                CategoryIcon(category: candidate.category)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                    Text(candidate.subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }

                Spacer(minLength: WanderTheme.spacing1)

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: 28, height: 28)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())
            }
            .padding(WanderTheme.spacing2)
            .frame(
                maxWidth: .infinity,
                minHeight: AddSuggestedPlaces.rowHeight,
                alignment: .leading
            )
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(candidate.name)")
        .accessibilityHint("Opens the save flow for this nearby place")
    }
}

private struct CandidateRow: View {
    let candidate: PlaceCandidate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                CategoryIcon(category: candidate.category)
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(candidate.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(candidate.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add.candidate.\(candidate.id)")
        .accessibilityLabel(candidate.name)
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }
}

private extension PlaceCandidate {
    var subtitle: String {
        previewSubtitle()
    }
}

private struct InlineMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WanderTheme.terracottaDark.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        }
    }
}

private struct CategoryIcon: View {
    let category: String

    var body: some View {
        WanderCategoryEmoji(category: category, size: 18)
            .frame(width: 40, height: 40)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())
    }
}

private struct AddCameraPicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage) {
            dismiss()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: @MainActor (UIImage) -> Void
        private let dismiss: () -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
