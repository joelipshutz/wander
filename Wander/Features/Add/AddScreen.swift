import CoreLocation
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum AddSheetLayout {
    static let restingDetent = PresentationDetent.height(560)
    static let detents: Set<PresentationDetent> = [restingDetent, .large]
}

struct AddScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @ObservedObject var importStore: PlaceImportStore
    let resetToken: UUID
    @Binding private var selectedDetent: PresentationDetent
    let onClose: () -> Void
    @State private var step: AddStep = .source
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var selectedSource: AddSourceType = .manual
    @State private var manualName = ""
    @State private var linkInput = ""
    @State private var quickAddQuery = ""
    @State private var isShowingInlineCandidateResults = false
    @State private var draft: UnresolvedDraft?
    @State private var isResolvingCandidates = false
    @State private var resolutionMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingVisitPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    @State private var isImportingPhoto = false
    @State private var addSaveFlow: MapPlaceSaveContext?
    @State private var selectedImportSource: PlaceImportSource?
    @State private var showsImportInbox = false
    @State private var opensImportInboxAfterSource = false
    @FocusState private var isQuickAddFocused: Bool

    init(
        importStore: PlaceImportStore,
        resetToken: UUID = UUID(),
        selectedDetent: Binding<PresentationDetent>,
        onClose: @escaping () -> Void
    ) {
        self.importStore = importStore
        self.resetToken = resetToken
        _selectedDetent = selectedDetent
        self.onClose = onClose
    }

    private var selectedCandidate: PlaceCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header

                    switch step {
                    case .source:
                        sourcePicker
                    case .photo:
                        photoForm
                    case .confirm:
                        confirmPlace
                    case .draft:
                        draftView
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .scrollDismissesKeyboard(.interactively)
            .wanderScreen()
            .onChange(of: resetToken) { _, _ in
                reset()
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
                        selectedDetent = AddSheetLayout.restingDetent
                    }
                }
            }
            .onChange(of: selectedDetent) { _, detent in
                guard detent == AddSheetLayout.restingDetent, isQuickAddFocused else { return }
                isQuickAddFocused = false
            }
            .sheet(item: $addSaveFlow) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveSharedSubmission(submission)
                } onRemove: { _ in
                    false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedImportSource, onDismiss: openImportInboxAfterSourceIfNeeded) { source in
                PlaceImportSourceScreen(
                    source: source,
                    importStore: importStore
                ) { _ in
                    opensImportInboxAfterSource = true
                }
            }
            .navigationDestination(isPresented: $showsImportInbox) {
                PlaceImportInboxScreen(importStore: importStore)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
        }
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
                Text("add a place")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(step.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Button(action: onClose) {
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
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            AddSearchField(
                query: $quickAddQuery,
                isLoading: isResolvingCandidates,
                isFocused: $isQuickAddFocused,
                submit: {
                    expandSheet()
                    isQuickAddFocused = false
                    Task {
                        await resolveQuickAddQuery()
                    }
                }
            )

            if isShowingInlineCandidateResults {
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
            } else {
                VStack(spacing: 0) {
                    SourceRow(
                        title: isResolvingCandidates ? "finding nearby places..." : "I'm here now",
                        subtitle: "find nearby places",
                        systemImage: "location.fill",
                        isPrimary: true,
                        isDisabled: isResolvingCandidates
                    ) {
                        expandSheet()
                        Task {
                            await resolveCurrentLocationCandidates()
                        }
                    }
                    Divider().background(WanderTheme.borderHairline.color)
                    SourceRow(
                        title: "From a photo",
                        subtitle: "scan a place from a photo",
                        systemImage: "photo.fill",
                        isDisabled: isResolvingCandidates
                    ) {
                        resolutionMessage = nil
                        selectedSource = .photo
                        step = .photo
                        expandSheet()
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))

                AddImportSection(
                    summary: importStore.summary,
                    sourceAction: openImportSource,
                    inboxAction: openImportInbox
                )

                if let resolutionMessage {
                    InlineMessage(text: resolutionMessage)
                        .padding(.top, WanderTheme.spacing2)
                }

            }
        }
    }

    private var photoForm: some View {
        let title = isImportingPhoto ? "importing photo..." : "choose a photo"
        let subtitle = "we'll scan visible text and photo location"

        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20, weight: .bold))
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                }
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(minHeight: 64)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }
            .disabled(isImportingPhoto)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    await importPhotoDraft(from: item)
                }
            }

            if let resolutionMessage {
                InlineMessage(text: resolutionMessage)
            }

            Text("We'll search likely place names and nearby photo locations. If we read a name but cannot match it, you can edit the search before saving.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)

            WanderPrimaryButton(title: "search by name instead", systemImage: "magnifyingglass") {
                step = .source
                expandSheet()
                isQuickAddFocused = true
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

            WanderPrimaryButton(title: "continue", systemImage: "arrow.right") {
                openSharedSaveFlow()
            }
        }
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
        linkInput = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        pendingVisitPhotoAttachments = []
        isImportingPhoto = false
        addSaveFlow = nil
        selectedImportSource = nil
        showsImportInbox = false
        opensImportInboxAfterSource = false
        selectedDetent = AddSheetLayout.restingDetent
    }

    private func resetAfterSave() {
        step = .source
        candidates = []
        selectedCandidateID = nil
        selectedSource = .manual
        manualName = ""
        linkInput = ""
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
        case .photo:
            step = .source
        case .confirm:
            step = .source
        case .draft:
            step = .source
        case .source:
            break
        }

        if step == .source {
            selectedDetent = AddSheetLayout.restingDetent
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

    private func openImportSource(_ source: PlaceImportSource) {
        expandSheet()
        selectedImportSource = source
    }

    private func openImportInbox() {
        expandSheet()
        showsImportInbox = true
    }

    private func openImportInboxAfterSourceIfNeeded() {
        guard opensImportInboxAfterSource else { return }
        opensImportInboxAfterSource = false
        openImportInbox()
    }

    private func openSharedSaveFlow() {
        guard let selectedCandidate else { return }

        addSaveFlow = MapPlaceSaveContext.addCandidate(
            selectedCandidate,
            sourceType: selectedSource,
            defaultVisibility: store.effectiveDefaultVisibility,
            initialPhotoAttachments: pendingVisitPhotoAttachments
        )
    }

    @MainActor
    private func saveSharedSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        guard let result = await persistNewPlaceSaveSubmission(
            submission,
            store: store,
            backend: auth.isSignedIn ? backend : nil
        ) else { return nil }

        let needsSignIn = !auth.isSignedIn
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        resetAfterSave()
        onClose()
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
        } catch {
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolutionCopy(for: error)
        }
    }

    @MainActor
    private func resolveLinkCandidates(inline: Bool = false) async {
        selectedSource = .link
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
        isResolvingCandidates = true
        defer { isResolvingCandidates = false }

        do {
            candidates = try await store.linkCandidates(linkInput)
            selectedCandidateID = candidates.first?.id
            guard !candidates.isEmpty else {
                resolutionMessage = PlaceResolutionError.noCandidates.localizedDescription
                return
            }
            isShowingInlineCandidateResults = inline
            step = inline ? .source : .confirm
        } catch {
            if auth.isSignedIn {
                let draft = await store.createUnresolvedDraft(
                    sourceType: .link,
                    originalInput: linkInput,
                    backend: backend
                )

                if let result = await store.processExtractionJob(for: draft, backend: backend),
                   applyExtractionResult(result, source: .link) {
                    return
                }
            }

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
        } else if Self.looksLikeLink(query) {
            linkInput = query
            await resolveLinkCandidates(inline: true)
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
            selectedDetent = AddSheetLayout.restingDetent
        }
    }

    private static func looksLikeLink(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("http://")
            || normalized.hasPrefix("https://")
            || normalized.contains("maps.apple.com")
            || normalized.contains("google.com/maps")
            || normalized.contains("maps.app.goo.gl")
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
        selectedSource = .photo
        resolutionMessage = nil
        isImportingPhoto = true
        defer {
            isImportingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            let byteCount = data?.count ?? 0
            if let data {
                let recognizedText = await recognizeText(in: data)
                let photoCoordinate = PhotoPlaceMetadataExtractor.coordinate(from: data)
                let resolution = await PhotoPlaceImportResolver.resolve(
                    recognizedText: recognizedText,
                    photoCoordinate: photoCoordinate,
                    searcher: store
                )

                if applyPhotoImportResolution(resolution) {
                    let assetRef = item.itemIdentifier.map { "photos_picker:\($0)" }
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
            }

            let assetRef = item.itemIdentifier.map { "photos_picker:\($0)" } ?? "photos_picker:imported_photo_\(byteCount)"
            draft = await store.createUnresolvedDraft(
                sourceType: .photo,
                originalInput: "photo import · \(byteCount) bytes",
                localAssetRef: assetRef,
                backend: auth.isSignedIn ? backend : nil
            )

            if auth.isSignedIn,
               let draft,
               let result = await store.processExtractionJob(for: draft, backend: backend),
               applyExtractionResult(result, source: .photo) {
                return
            }

            step = .draft
        } catch {
            resolutionMessage = "Could not import that photo. Try another one or search by name."
        }
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
    case photo
    case confirm
    case draft

    var subtitle: String {
        switch self {
        case .source: "pick the fastest way"
        case .photo: "Choose a photo; we'll look for a place."
        case .confirm: "Pick the right place, then save it."
        case .draft: "we could not find enough place info yet."
        }
    }

    var canGoBack: Bool {
        switch self {
        case .photo, .confirm, .draft:
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
    let submit: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: isLoading ? "hourglass" : "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField(
                "",
                text: $query,
                prompt: Text("Search, paste a link, or add coordinates")
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
        .accessibilityLabel("Search, paste a link, or add coordinates")
        .disabled(isLoading)
        .opacity(isLoading ? 0.78 : 1)
    }
}

private struct SourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isPrimary = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.terracottaDark.color)
                    .frame(width: 34, height: 34)
                    .background(isPrimary ? WanderTheme.terracotta.color : WanderTheme.terracottaTint.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
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
