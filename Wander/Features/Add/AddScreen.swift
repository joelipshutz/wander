import AVFoundation
import CoreLocation
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum AddCameraAuthorization: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

enum AddCameraCaptureRoute: String, Identifiable, Equatable {
    case camera
    case permissionDenied
    case restricted
    case unavailable

    var id: String { rawValue }
}

struct AddCameraPresentationState: Equatable {
    var route: AddCameraCaptureRoute?
    private(set) var presentsPhotoLibraryAfterDismissal = false

    @discardableResult
    mutating func requestCamera(
        isAvailable: Bool,
        authorization: AddCameraAuthorization
    ) -> Bool {
        presentsPhotoLibraryAfterDismissal = false

        guard isAvailable else {
            route = .unavailable
            return false
        }

        switch authorization {
        case .authorized:
            route = .camera
            return false
        case .notDetermined:
            route = nil
            return true
        case .denied:
            route = .permissionDenied
            return false
        case .restricted:
            route = .restricted
            return false
        }
    }

    mutating func completePermissionRequest(granted: Bool, isAvailable: Bool) {
        guard granted else {
            route = .permissionDenied
            return
        }
        route = isAvailable ? .camera : .unavailable
    }

    mutating func dismissCapture() {
        route = nil
    }

    mutating func refreshAuthorization(
        isAvailable: Bool,
        authorization: AddCameraAuthorization
    ) {
        guard route == .permissionDenied else { return }

        switch authorization {
        case .authorized:
            route = isAvailable ? .camera : .unavailable
        case .restricted:
            route = .restricted
        case .notDetermined, .denied:
            break
        }
    }

    mutating func switchToPhotoLibrary() {
        presentsPhotoLibraryAfterDismissal = true
        route = nil
    }

    mutating func consumePhotoLibraryPresentation() -> Bool {
        defer { presentsPhotoLibraryAfterDismissal = false }
        return presentsPhotoLibraryAfterDismissal
    }

    mutating func reset() {
        route = nil
        presentsPhotoLibraryAfterDismissal = false
    }
}

enum AddCameraPreviewLayout {
    static let portraitCaptureHeightToWidthRatio: CGFloat = 4.0 / 3.0

    static func aspectFillScale(for containerSize: CGSize) -> CGFloat {
        guard containerSize.width > 0, containerSize.height > 0 else { return 1 }

        let unscaledPreviewHeight = containerSize.width * portraitCaptureHeightToWidthRatio
        return max(1, containerSize.height / unscaledPreviewHeight)
    }
}

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
    static let walkthroughPartialResultCapacity = 3
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

    static func walkthroughRequiresExpansion(candidateCount: Int) -> Bool {
        candidateCount > walkthroughPartialResultCapacity
    }
}

struct AddScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.astirBrandMode) private var brandMode
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
    let walkthroughParkSuggestion: @MainActor () async -> PlaceCandidate?
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
    @State private var cameraPresentation = AddCameraPresentationState()
    @State private var cameraSessionID = UUID()
    @State private var pendingCapturedPhoto: UIImage?
    @State private var pendingVisitPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    @State private var isImportingPhoto = false
    @State private var addSaveFlow: MapPlaceSaveContext?
    @State private var showsImportHub = ProcessInfo.processInfo.arguments.contains(
        "-WanderOpenImportHub"
    )
    @State private var showsImportInbox = false
    @State private var isAutoClosingWalkthrough = false
    @State private var isRunningWalkthroughSearch = false
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
        walkthroughParkSuggestion: @escaping @MainActor () async -> PlaceCandidate? = { nil },
        onClose: @escaping () -> Void
    ) {
        self.importStore = importStore
        self.placeSaveDraftStore = placeSaveDraftStore
        self.resetToken = resetToken
        _selectedDetent = selectedDetent
        self.launchRequest = launchRequest
        self.onLaunchRequestHandled = onLaunchRequestHandled
        self.walkthroughParkSuggestion = walkthroughParkSuggestion
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

    private var isAddWalkthroughActive: Bool {
        walkthroughs.activeSurface == .add
    }

    private var isWalkthroughAddFlowActive: Bool {
        isAddWalkthroughActive
            || walkthroughs.activeSurface == .saveFlow
            || walkthroughs.requestedSurface == .map
    }

    private var isWalkthroughAutomatingPlace: Bool {
        guard isAddWalkthroughActive else { return false }
        return walkthroughs.currentStep?.target == .addSearch
            || walkthroughs.currentStep?.target == .addPlace
    }

    private var activeSheetDetents: Set<PresentationDetent> {
        guard addSaveFlow != nil else {
            return AddSheetLayout.detents(
                hasPendingImports: importStore.summary.hasPendingImports
            )
        }
        return [MapPlaceSaveFlowSheet.compactDetent, .large]
    }

    private var activeSheetBackground: Color {
        brandMode.background
    }

    var body: some View {
        Group {
            if let context = addSaveFlow {
                inlineSaveFlow(context)
            } else {
                addPlaceFlow
            }
        }
        .presentationDetents(activeSheetDetents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(WanderTheme.radiusSheet)
        .presentationBackground(activeSheetBackground)
        .presentationBackgroundInteraction(
            .enabled(upThrough: MapPlaceSaveFlowSheet.compactDetent)
        )
        .presentationContentInteraction(.resizes)
        .walkthroughPresenterScrim(
            isPresented: addSaveFlow != nil && walkthroughs.activeSurface == .saveFlow
        )
        .firstVisitWalkthroughOverlay(walkthroughs, surface: .add)
        .onChange(of: walkthroughs.currentStep?.target) { _, _ in
            autoCloseAfterImportIfNeeded()
        }
        .onChange(of: walkthroughs.requestedSurface) { _, _ in
            autoCloseAfterImportIfNeeded()
        }
        .onChange(of: importStore.summary.hasPendingImports) { _, _ in
            guard addSaveFlow == nil, selectedDetent != .large else { return }
            selectedDetent = restingDetent
        }
    }

    private var addPlaceFlow: some View {
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
            .astirScreen()
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                cameraPresentation.refreshAuthorization(
                    isAvailable: isCameraAvailable,
                    authorization: cameraAuthorization
                )
            }
            .onChange(of: walkthroughs.activeSurface, initial: true) { _, activeSurface in
                if activeSurface == .saveFlow {
                    restoreActiveSaveFlowIfNeeded()
                } else if activeSurface == .add {
                    settleWalkthroughSheet()
                }
            }
            .task(id: walkthroughs.currentStep?.target) {
                await runWalkthroughAddAutomationIfNeeded()
            }
            .task(id: resetToken) {
                guard !isAddWalkthroughActive else { return }
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
            .fullScreenCover(
                item: $cameraPresentation.route,
                onDismiss: handleCameraPresentationDismissal
            ) { route in
                cameraCaptureDestination(route)
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
                    onDone: onClose
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
    }

    private func inlineSaveFlow(_ context: MapPlaceSaveContext) -> some View {
        MapPlaceSaveEditor(
            context: context,
            draft: placeSaveDraftStore.draft,
            onDraftChange: { draftID, form, submittedAt in
                placeSaveDraftStore.update(
                    draftID: draftID,
                    form: form,
                    submittedAt: submittedAt
                )
            },
            onSave: saveSharedSubmission,
            onRemove: { _ in false },
            onClose: dismissInlineSaveFlow,
            onContentExpansionRequested: expandSheet,
            onSaveCompleted: { result in
                completeInlineSaveFlow(result, sourceContextID: context.id)
            }
        )
        .id(context.id)
        .onDisappear {
            store.saveFlowDidDismiss(.saveSheet)
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
            .background(brandMode.background)
            .walkthroughTarget(.addImport)
        }
    }

    private var compactSourceContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            if isAddWalkthroughActive {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header
                    suggestedPlacesCore

                    if let resolutionMessage {
                        InlineMessage(text: resolutionMessage)
                    }
                }
                .walkthroughTarget(.addSearch)

                suggestedPlacesSeeMore
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header
                    suggestedPlaces

                    if let resolutionMessage {
                        InlineMessage(text: resolutionMessage)
                    }
                }
            }

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
        WanderTheme.spacing8
    }

    private var header: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            if step.canGoBack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(brandMode.accent)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isShowingHereNowResults ? "I'm here now" : "add a place")
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(isShowingHereNowResults ? "choose the place you're at" : step.subtitle)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
            }

            Spacer()

            if !isWalkthroughAddFlowActive {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(brandMode.primaryText)
                        .frame(width: 30, height: 30)
                        .astirGlassSurface(cornerRadius: 15)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close add place")
            }
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
                        .font(AstirTypography.label)
                        .foregroundStyle(brandMode.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to add options")

                confirmPlace

                if let resolutionMessage {
                    InlineMessage(text: resolutionMessage)
                }
            }
        }
        .walkthroughTarget(.addSearch)
    }

    private var searchField: some View {
        AddSearchField(
            query: $quickAddQuery,
            isLoading: isResolvingCandidates || isImportingPhoto,
            isFocused: $isQuickAddFocused,
            submit: {
                expandSheet()
                isQuickAddFocused = false
                Task {
                    await resolveQuickAddQuery()
                }
            },
            takePhoto: {
                requestCamera()
            },
            chooseFromLibrary: {
                showsPhotoLibrary = true
            }
        )
        .walkthroughEmphasis(.addSearch)
        .disabled(isWalkthroughAutomatingPlace)
        .allowsHitTesting(!isWalkthroughAutomatingPlace)
        .accessibilityHint(
            isWalkthroughAutomatingPlace
                ? "rec.me is choosing a nearby park for this demonstration"
                : ""
        )
    }

    private var suggestedPlaces: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            suggestedPlacesCore
            suggestedPlacesSeeMore
        }
    }

    private var suggestedPlacesCore: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("Suggested")
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(brandMode.primaryText)
                .accessibilityAddTraits(.isHeader)

            searchField

            if isLoadingSuggestions {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                        .tint(brandMode.accent)
                    Text("Finding places near you…")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                }
                .frame(minHeight: 82)
            } else if !suggestedCandidates.isEmpty {
                suggestedPlaceRows(
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
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accent)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Tries nearby suggestions again")
            }
        }
    }

    @ViewBuilder
    private var suggestedPlacesSeeMore: some View {
        let visibleCount = AddSuggestedPlaces.previewCount(
            screenHeight: UIScreen.main.bounds.height
        )
        if AddSuggestedPlaces.visible(suggestedCandidates, count: visibleCount).count
            < suggestedCandidates.count {
            Button {
                walkthroughs.perform(.addSearch)
                expandSheet()
                Task {
                    await resolveCurrentLocationCandidates()
                }
            } label: {
                Label("See more", systemImage: "arrow.up.right")
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accent)
                    .frame(maxWidth: .infinity, minHeight: AddSuggestedPlaces.showMoreHeight)
                    .background(brandMode.recessedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(brandMode.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens all nearby suggestions in the full-screen nearby view")
        }
    }

    private func suggestedPlaceRows(count: Int) -> some View {
        let visibleCandidates = AddSuggestedPlaces.visible(suggestedCandidates, count: count)

        return VStack(spacing: AddSuggestedPlaces.rowSpacing) {
            ForEach(visibleCandidates) { candidate in
                SuggestedPlaceCard(candidate: candidate) {
                    openSuggestedCandidate(candidate)
                }
            }
        }
    }

    private var confirmPlace: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(spacing: WanderTheme.spacing2) {
                ForEach(candidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isSelected: selectedCandidate?.id == candidate.id,
                        isInteractive: !isWalkthroughAutomatingPlace
                    ) {
                        selectedCandidateID = candidate.id
                    }
                }
            }

            if !showsFloatingCurrentLocationAction {
                candidateSaveAction
            }
        }
        .walkthroughTarget(showsFloatingCurrentLocationAction ? nil : .addPlace)
        .disabled(isWalkthroughAutomatingPlace)
        .allowsHitTesting(!isWalkthroughAutomatingPlace)
    }

    private var floatingCandidateAction: some View {
        candidateSaveAction
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing3)
            .background(
                LinearGradient(
                    colors: [
                        brandMode.background.opacity(0),
                        brandMode.background.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
            .walkthroughTarget(.addPlace)
    }

    private var candidateSaveAction: some View {
        AstirAddPrimaryButton(
            title: "Save",
            systemImage: "arrow.right"
        ) {
            openSharedSaveFlow()
        }
    }

    private func autoCloseAfterImportIfNeeded() {
        guard walkthroughs.activeSurface == nil,
              walkthroughs.requestedSurface == .map,
              addSaveFlow == nil,
              !isAutoClosingWalkthrough
        else { return }

        isAutoClosingWalkthrough = true
        Task { @MainActor in
            await Task.yield()
            guard walkthroughs.activeSurface == nil,
                  walkthroughs.requestedSurface == .map,
                  addSaveFlow == nil
            else {
                isAutoClosingWalkthrough = false
                return
            }
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

    @MainActor
    private func runWalkthroughAddAutomationIfNeeded() async {
        guard isAddWalkthroughActive, let target = walkthroughs.currentStep?.target else { return }

        switch target {
        case .addSearch:
            await runWalkthroughParkSearch()
        case .addImport:
            settleWalkthroughSheet()
        default:
            break
        }
    }

    @MainActor
    private func runWalkthroughParkSearch() async {
        guard !isRunningWalkthroughSearch else { return }
        isRunningWalkthroughSearch = true
        defer { isRunningWalkthroughSearch = false }

        settleWalkthroughSheet()
        isQuickAddFocused = false
        selectedSource = .manual
        candidates = []
        selectedCandidateID = nil
        isShowingInlineCandidateResults = false
        resolutionMessage = nil

        let candidate: PlaceCandidate
        if let existing = walkthroughs.tutorialCandidate {
            candidate = existing
        } else {
            let suggested = await walkthroughParkSuggestion()
            // Do not persist the fallback when the lookup was interrupted by
            // navigation or backgrounding. A later resume must be free to
            // finish choosing the intended nearby park.
            guard !Task.isCancelled else { return }
            candidate = suggested ?? FirstVisitParkSuggestionPolicy.hotchkissPark
            walkthroughs.recordTutorialCandidate(candidate)
        }
        guard !Task.isCancelled,
              walkthroughs.activeSurface == .add,
              walkthroughs.currentStep?.target == .addSearch
        else { return }

        // Let the coach settle before the automated typing begins. This keeps
        // the first instruction readable instead of racing through it during
        // the sheet's presentation animation.
        try? await Task.sleep(
            for: reduceMotion ? .milliseconds(900) : .milliseconds(1_500)
        )
        guard !Task.isCancelled,
              walkthroughs.currentStep?.target == .addSearch
        else { return }

        quickAddQuery = ""
        let shouldAnimateTyping = !reduceMotion && !UIAccessibility.isVoiceOverRunning
        if shouldAnimateTyping {
            for character in candidate.name {
                guard !Task.isCancelled,
                      walkthroughs.currentStep?.target == .addSearch
                else { return }
                withAnimation(.smooth(duration: 0.12)) {
                    quickAddQuery.append(character)
                }
                try? await Task.sleep(for: .milliseconds(74))
            }
        } else {
            quickAddQuery = candidate.name
        }
        guard !Task.isCancelled else { return }

        candidates = await walkthroughPreviewCandidates(selected: candidate)
        guard !Task.isCancelled,
              walkthroughs.currentStep?.target == .addSearch
        else { return }
        selectedCandidateID = candidate.id
        selectedSource = .manual
        isShowingInlineCandidateResults = true
        step = .source
        settleWalkthroughSheet(candidateCount: candidates.count)

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Selected \(candidate.name) for the saving-a-place demonstration."
            )
        }

        // Keep the selected result and its explanation visible for an average
        // reading beat before moving into the save sheet.
        try? await Task.sleep(for: .milliseconds(
            FirstVisitWalkthroughContent.automaticReadingDelayMilliseconds(for: .addSearch)
        ))
        guard !Task.isCancelled,
              walkthroughs.currentStep?.target == .addSearch
        else { return }
        openWalkthroughSaveFlowAfterSearch()
    }

    @MainActor
    private func walkthroughPreviewCandidates(selected candidate: PlaceCandidate) async -> [PlaceCandidate] {
        do {
            let resolved = try await store.manualCandidates(
                name: candidate.name,
                areaHint: candidate.locality,
                category: "park"
            )
            var seen = Set<String>()
            let ordered = ([candidate] + resolved).filter { item in
                seen.insert(Self.walkthroughCandidateIdentity(item)).inserted
            }
            return AddSuggestedPlaces.limited(ordered)
        } catch {
            return [candidate]
        }
    }

    private static func walkthroughCandidateIdentity(_ candidate: PlaceCandidate) -> String {
        [candidate.name, candidate.address, candidate.locality, candidate.region]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    @MainActor
    private func settleWalkthroughSheet(candidateCount: Int = 0) {
        let targetDetent: PresentationDetent = AddSuggestedPlaces
            .walkthroughRequiresExpansion(candidateCount: candidateCount)
            ? .large
            : restingDetent
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0)) {
            selectedDetent = targetDetent
        }
    }

    private var draftView: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(brandMode.accent)

            Text(draft?.title ?? "Draft saved.")
                .font(AstirTypography.sheetTitle)
                .foregroundStyle(brandMode.primaryText)
            Text(draft?.message ?? "You can finish this manually.")
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)

            AstirAddPrimaryButton(title: "try another search", systemImage: "magnifyingglass") {
                step = .source
                expandSheet()
                isQuickAddFocused = true
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
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
        cameraPresentation.reset()
        pendingCapturedPhoto = nil
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

        presentSaveFlow(addCandidateContext(
            selectedCandidate,
            sourceType: selectedSource,
            defaultVisibility: store.effectiveDefaultVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        ))
        // Persist the recoverable form before moving the NUX checkpoint to the
        // inline save editor. A kill between these statements can now always
        // reconstruct the exact presentation.
        walkthroughs.perform(.addPlace, transitioningTo: .saveFlow)
    }

    private func openWalkthroughSaveFlowAfterSearch() {
        guard walkthroughs.activeSurface == .add,
              walkthroughs.currentStep?.target == .addSearch,
              let selectedCandidate
        else { return }

        presentSaveFlow(addCandidateContext(
            selectedCandidate,
            sourceType: selectedSource,
            defaultVisibility: store.effectiveDefaultVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        ))
        walkthroughs.perform(.addSearch, transitioningTo: .saveFlow)
    }

    private func presentSaveFlow(_ context: MapPlaceSaveContext) {
        if let draft = PlaceSaveDraft.addFlow(
            ownerUserID: store.currentUser.id,
            context: context,
            walkthroughContentVersion: walkthroughs.activeSurface == .add
                ? FirstVisitWalkthroughContent.version
                : nil
        ) {
            placeSaveDraftStore.begin(draft)
        }
        var contentSwap = Transaction()
        contentSwap.disablesAnimations = true
        withTransaction(contentSwap) {
            addSaveFlow = context
        }
        Task { @MainActor in
            await Task.yield()
            guard addSaveFlow?.id == context.id else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.42, extraBounce: 0)) {
                selectedDetent = MapPlaceSaveFlowSheet.compactDetent
            }
        }
    }

    private func restoreActiveSaveFlowIfNeeded() {
        guard addSaveFlow == nil else { return }

        guard let draft = placeSaveDraftStore.draft,
              draft.ownerUserID == store.currentUser.id
        else {
            restoreLegacyWalkthroughSaveWithoutDraftIfNeeded()
            return
        }

        selectedSource = draft.sourceType
        candidates = [draft.candidate]
        selectedCandidateID = draft.candidate.id
        pendingVisitPhotoAttachments = draft.form.photoAttachments.compactMap(
            MapPlaceSavePhotoAttachment.restore
        )
        let context = addCandidateContext(
            draft.candidate,
            sourceType: draft.sourceType,
            defaultVisibility: draft.form.selectedVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        )
        addSaveFlow = context
        selectedDetent = MapPlaceSaveFlowSheet.compactDetent
    }

    private func restoreLegacyWalkthroughSaveWithoutDraftIfNeeded() {
        guard walkthroughs.activeSurface == .saveFlow,
              let candidate = walkthroughs.tutorialCandidate
        else { return }

        if walkthroughs.currentStep?.target == .saveSubmit,
           let currentSave = MapPlaceSaveContext.currentUserSave(
               matching: candidate,
               in: store.currentUserVisiblePlaces
           ) {
            let latestVisit = store.visits(for: currentSave.userPlace.id).first
            if walkthroughs.tutorialMemorySnapshot == nil {
                walkthroughs.recordTutorialMemorySnapshot(
                    FirstVisitTutorialMemorySnapshot(
                        candidate: candidate,
                        status: currentSave.userPlace.status,
                        date: latestVisit?.visitedAt ?? currentSave.userPlace.localUpdatedAt,
                        ratingScore: latestVisit?.ratingScore,
                        note: latestVisit?.note
                            ?? "A peaceful neighborhood park with room to slow down and breathe.",
                        tag: "good walk"
                    )
                )
            }
            walkthroughs.recordTutorialSave(userPlaceID: currentSave.userPlace.id)
            walkthroughs.perform(.saveSubmit)
        }

        selectedSource = .manual
        candidates = [candidate]
        selectedCandidateID = candidate.id
        let context = addCandidateContext(
            candidate,
            sourceType: .manual,
            defaultVisibility: store.effectiveDefaultVisibility
        )
        presentSaveFlow(context)
    }

    private func dismissInlineSaveFlow() {
        placeSaveDraftStore.clear()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.34, extraBounce: 0)) {
            addSaveFlow = nil
            selectedDetent = .large
        }
    }

    private func completeInlineSaveFlow(
        _: SaveResult,
        sourceContextID: UUID
    ) {
        guard addSaveFlow?.id == sourceContextID else { return }
        placeSaveDraftStore.clear()
        addSaveFlow = nil
        onClose()
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

    private var cameraAuthorization: AddCameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .denied
        }
    }

    @MainActor
    private func requestCamera() {
        cameraSessionID = UUID()
        pendingCapturedPhoto = nil
        let needsPermissionRequest = cameraPresentation.requestCamera(
            isAvailable: isCameraAvailable,
            authorization: cameraAuthorization
        )
        guard needsPermissionRequest else { return }

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            cameraPresentation.completePermissionRequest(
                granted: granted,
                isAvailable: isCameraAvailable
            )
        }
    }

    @ViewBuilder
    private func cameraCaptureDestination(_ route: AddCameraCaptureRoute) -> some View {
        switch route {
        case .camera:
            let sessionID = cameraSessionID
            AddCameraCaptureScreen(
                onImage: { image in
                    guard cameraPresentation.route == .camera,
                          cameraSessionID == sessionID else { return }
                    pendingCapturedPhoto = image
                    cameraPresentation.dismissCapture()
                },
                onGallery: switchCameraToPhotoLibrary,
                onCancel: cancelCameraCapture
            )
        case .permissionDenied:
            AddCameraRecoveryScreen(
                state: .permissionDenied,
                onGallery: switchCameraToPhotoLibrary,
                onCancel: cancelCameraCapture
            )
        case .restricted:
            AddCameraRecoveryScreen(
                state: .restricted,
                onGallery: switchCameraToPhotoLibrary,
                onCancel: cancelCameraCapture
            )
        case .unavailable:
            AddCameraRecoveryScreen(
                state: .unavailable,
                onGallery: switchCameraToPhotoLibrary,
                onCancel: cancelCameraCapture
            )
        }
    }

    @MainActor
    private func switchCameraToPhotoLibrary() {
        cameraSessionID = UUID()
        pendingCapturedPhoto = nil
        cameraPresentation.switchToPhotoLibrary()
    }

    @MainActor
    private func cancelCameraCapture() {
        cameraSessionID = UUID()
        pendingCapturedPhoto = nil
        cameraPresentation.dismissCapture()
    }

    @MainActor
    private func handleCameraPresentationDismissal() {
        if cameraPresentation.consumePhotoLibraryPresentation() {
            showsPhotoLibrary = true
            return
        }

        guard let image = pendingCapturedPhoto else { return }
        pendingCapturedPhoto = nil
        Task {
            await importCapturedPhoto(image)
        }
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

        // During the NUX, the inline editor records its memory snapshot and
        // advances the checkpoint after this returns. Keep the submitted draft
        // until that transition succeeds so a process kill remains recoverable.
        if walkthroughs.activeSurface != .saveFlow {
            placeSaveDraftStore.clear()
        }
        let needsSignIn = !auth.isSignedIn
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        resetAfterSave()
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
        let transferableImage = SendableCapturedImage(value: image)
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            transferableImage.value.jpegData(compressionQuality: 0.92)
        }).value else {
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

private struct AstirAddPrimaryButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(AstirTypography.control)
            .foregroundStyle(brandMode.accentForeground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(brandMode.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AddSearchField: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var query: String
    let isLoading: Bool
    let isFocused: FocusState<Bool>.Binding
    let submit: () -> Void
    let takePhoto: () -> Void
    let chooseFromLibrary: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: isLoading ? "hourglass" : "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(brandMode.secondaryText)

            TextField(
                "",
                text: $query,
                prompt: Text("Search for a place")
                    .foregroundStyle(brandMode.secondaryText.opacity(0.72))
            )
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.primaryText)
                .tint(brandMode.accent)
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
                        .foregroundStyle(brandMode.secondaryText.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear add search")
            }

            Menu {
                Button(action: takePhoto) {
                    Label("Take a Photo", systemImage: "camera")
                }

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
                .foregroundStyle(brandMode.accent)
                .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Add from a photo")
            .accessibilityHint("Choose Take a Photo or Photo Library")
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 48)
        .background(brandMode.recessedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
                isFocused.wrappedValue
                    ? brandMode.accent.opacity(0.78)
                    : brandMode.border,
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
    @Environment(\.astirBrandMode) private var brandMode
    let candidate: PlaceCandidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                CategoryIcon(category: candidate.category)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                        .lineLimit(1)
                    Text(candidate.subtitle)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: WanderTheme.spacing1)

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(brandMode.accentForeground)
                    .frame(width: 28, height: 28)
                    .background(brandMode.accent)
                    .clipShape(Circle())
            }
            .padding(WanderTheme.spacing2)
            .frame(
                maxWidth: .infinity,
                minHeight: AddSuggestedPlaces.rowHeight,
                alignment: .leading
            )
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(brandMode.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(candidate.name)")
        .accessibilityHint("Opens the save flow for this nearby place")
    }
}

private struct CandidateRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let candidate: PlaceCandidate
    let isSelected: Bool
    let isInteractive: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isInteractive {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
                    .accessibilityElement(children: .ignore)
            }
        }
        .accessibilityIdentifier("add.candidate.\(candidate.id)")
        .accessibilityLabel(candidate.name)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityRespondsToUserInteraction(isInteractive)
    }

    private var rowContent: some View {
        HStack(spacing: WanderTheme.spacing3) {
            CategoryIcon(category: candidate.category)
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(candidate.name)
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(candidate.subtitle)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? brandMode.accent : brandMode.border)
        }
        .padding(WanderTheme.spacing3)
        .background(isSelected ? brandMode.accentWash : brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? brandMode.accent : brandMode.border,
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }
}

private extension PlaceCandidate {
    var subtitle: String {
        previewSubtitle()
    }
}

private struct InlineMessage: View {
    @Environment(\.astirBrandMode) private var brandMode
    let text: String

    var body: some View {
        Text(text)
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(brandMode.accentWash)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(brandMode.accent.opacity(0.32), lineWidth: 1)
            }
    }
}

private struct LabeledField: View {
    @Environment(\.astirBrandMode) private var brandMode
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(label)
                .font(AstirTypography.label)
                .foregroundStyle(brandMode.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.primaryText)
                .tint(brandMode.accent)
                .padding(WanderTheme.spacing3)
                .background(brandMode.recessedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(brandMode.border, lineWidth: 1)
                }
        }
    }
}

private struct CategoryIcon: View {
    @Environment(\.astirBrandMode) private var brandMode
    let category: String

    var body: some View {
        WanderCategoryEmoji(category: category, size: 18)
            .frame(width: 40, height: 40)
            .background(brandMode.accentWash)
            .clipShape(Circle())
    }
}

private struct SendableCapturedImage: @unchecked Sendable {
    let value: UIImage
}

private struct AddCameraCaptureScreen: View {
    let onImage: @MainActor (UIImage) -> Void
    let onGallery: () -> Void
    let onCancel: () -> Void

    @State private var captureRequest = 0
    @State private var requestedCameraDevice: UIImagePickerController.CameraDevice = .rear

    private var canFlipCamera: Bool {
        UIImagePickerController.isCameraDeviceAvailable(.rear)
            && UIImagePickerController.isCameraDeviceAvailable(.front)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                AddCameraPicker(
                    previewSize: geometry.size,
                    captureRequest: captureRequest,
                    requestedCameraDevice: requestedCameraDevice,
                    onImage: onImage,
                    onCancel: onCancel
                )
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            .background(.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close camera")
                }

                Spacer()

                HStack {
                    Button(action: onGallery) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose from Photos")
                    .accessibilityHint("Closes the camera and opens your photo library")

                    Spacer()

                    Button {
                        captureRequest += 1
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.55), lineWidth: 3)
                                    .padding(-6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take photo")

                    Spacer()

                    Button {
                        requestedCameraDevice = requestedCameraDevice == .rear ? .front : .rear
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canFlipCamera)
                    .opacity(canFlipCamera ? 1 : 0)
                    .accessibilityLabel("Flip camera")
                }
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .safeAreaPadding(.vertical, WanderTheme.spacing2)
        }
        .statusBarHidden()
    }
}

private enum AddCameraRecoveryState: Equatable {
    case permissionDenied
    case restricted
    case unavailable

    var title: String {
        switch self {
        case .permissionDenied:
            "Camera access is off"
        case .restricted:
            "Camera access is restricted"
        case .unavailable:
            "Camera isn't available"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied:
            "Allow camera access in Settings, or choose an existing photo instead."
        case .restricted:
            "This device doesn't allow camera access. You can choose an existing photo instead."
        case .unavailable:
            "You can still choose a photo without losing anything you've entered."
        }
    }
}

private struct AddCameraRecoveryScreen: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.astirBrandMode) private var brandMode
    let state: AddCameraRecoveryState
    let onGallery: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            brandMode.background.ignoresSafeArea()

            VStack(spacing: WanderTheme.spacing4) {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(brandMode.primaryText)
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            .astirGlassSurface(cornerRadius: WanderTheme.tapMinimum / 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close camera")
                }

                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(brandMode.accent)
                    .frame(width: 88, height: 88)
                    .background(brandMode.accentWash)
                    .clipShape(Circle())

                VStack(spacing: WanderTheme.spacing2) {
                    Text(state.title)
                        .font(AstirTypography.sheetTitle)
                        .foregroundStyle(brandMode.primaryText)
                        .multilineTextAlignment(.center)

                    Text(state.message)
                        .font(AstirTypography.body)
                        .foregroundStyle(brandMode.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: WanderTheme.spacing2) {
                    AstirAddPrimaryButton(
                        title: "Choose from Photos",
                        systemImage: "photo.on.rectangle",
                        action: onGallery
                    )

                    if state == .permissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            openURL(url)
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(brandMode.raisedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(brandMode.border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .safeAreaPadding(.vertical, WanderTheme.spacing2)
        }
    }
}

private struct AddCameraPicker: UIViewControllerRepresentable {
    let previewSize: CGSize
    let captureRequest: Int
    let requestedCameraDevice: UIImagePickerController.CameraDevice
    let onImage: @MainActor (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.showsCameraControls = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        picker.view.backgroundColor = .black
        updatePreviewTransform(on: picker)
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        updatePreviewTransform(on: uiViewController)

        if UIImagePickerController.isCameraDeviceAvailable(requestedCameraDevice),
           uiViewController.cameraDevice != requestedCameraDevice {
            uiViewController.cameraDevice = requestedCameraDevice
        }

        guard context.coordinator.lastHandledCaptureRequest != captureRequest else { return }
        context.coordinator.lastHandledCaptureRequest = captureRequest
        uiViewController.takePicture()
    }

    private func updatePreviewTransform(on picker: UIImagePickerController) {
        let scale = AddCameraPreviewLayout.aspectFillScale(for: previewSize)
        picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var lastHandledCaptureRequest = 0
        private let onImage: @MainActor (UIImage) -> Void
        private let onCancel: () -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
