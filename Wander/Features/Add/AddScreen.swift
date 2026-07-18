import PhotosUI
import SwiftUI
import UIKit
import Vision

struct AddScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let resetToken: UUID
    @State private var step: AddStep = .source
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var selectedSource: AddSourceType = .manual
    @State private var manualName = ""
    @State private var manualArea = ""
    @State private var manualCategory = "coffee"
    @State private var linkInput = ""
    @State private var quickAddQuery = ""
    @State private var isShowingInlineCandidateResults = false
    @State private var draft: UnresolvedDraft?
    @State private var isResolvingCandidates = false
    @State private var resolutionMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingVisitPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    @State private var isImportingPhoto = false
    @State private var saveToast: SaveSyncFeedback?
    @State private var addSaveFlow: MapPlaceSaveContext?

    init(resetToken: UUID = UUID()) {
        self.resetToken = resetToken
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
                    case .link:
                        linkForm
                    case .manual:
                        manualForm
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
            .overlay(alignment: .bottom) {
                if let saveToast {
                    AddSaveToastView(
                        toast: saveToast,
                        signInAction: {
                            auth.presentGate(for: .syncPlace)
                        },
                        dismissAction: {
                            self.saveToast = nil
                        }
                    )
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing8 + WanderTheme.spacing3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: saveToast)
            .onChange(of: resetToken) { _, _ in
                reset()
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            if step.canGoBack {
                Button {
                    goBack()
                } label: {
                    Label("back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .buttonStyle(.plain)
                .padding(.bottom, WanderTheme.spacing1)
            }

            Text("add a place")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Text(step.subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            AddSearchField(
                query: $quickAddQuery,
                isLoading: isResolvingCandidates,
                submit: {
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
                SourceRow(
                    title: isResolvingCandidates ? "finding nearby places..." : AddSourceType.currentLocation.title,
                    subtitle: "asks once, suggests places nearby",
                    systemImage: "location.fill",
                    isPrimary: true,
                    isDisabled: isResolvingCandidates
                ) {
                    Task {
                        await resolveCurrentLocationCandidates()
                    }
                }
                SourceRow(title: AddSourceType.link.title, subtitle: "paste a map or location link", systemImage: "link", isDisabled: isResolvingCandidates) {
                    resolutionMessage = nil
                    selectedSource = .link
                    step = .link
                }
                SourceRow(title: AddSourceType.manual.title, subtitle: "search by name or neighborhood", systemImage: "square.and.pencil", isDisabled: isResolvingCandidates) {
                    resolutionMessage = nil
                    selectedSource = .manual
                    step = .manual
                }
                SourceRow(title: AddSourceType.photo.title, subtitle: "scan text in a photo for a place", systemImage: "photo", isDisabled: isResolvingCandidates) {
                    resolutionMessage = nil
                    selectedSource = .photo
                    step = .photo
                }

                if let resolutionMessage {
                    InlineMessage(text: resolutionMessage)
                        .padding(.top, WanderTheme.spacing2)
                }

                Text("location finds nearby places only · it never broadcasts you")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, WanderTheme.spacing2)
            }
        }
    }

    private var linkForm: some View {
        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                TextField("paste a Google Maps, Apple Maps, or location link", text: $linkInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .tint(WanderTheme.terracotta.color)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        guard !linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !isResolvingCandidates
                        else { return }
                        Task {
                            await resolveLinkCandidates()
                        }
                    }
                    .lineLimit(2, reservesSpace: true)
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

            Text("Some map links can turn into place candidates now. Short links that do not expand become drafts.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)

            if let resolutionMessage {
                InlineMessage(text: resolutionMessage)
            }

            WanderPrimaryButton(
                title: isResolvingCandidates ? "checking link..." : "find place from link",
                systemImage: "magnifyingglass",
                isDisabled: linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolvingCandidates
            ) {
                Task {
                    await resolveLinkCandidates()
                }
            }

            Button {
                saveLinkDraft()
            } label: {
                Label("save link as draft", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
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

            WanderPrimaryButton(title: "add manually instead", systemImage: "square.and.pencil") {
                selectedSource = .manual
                step = .manual
            }
        }
    }

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            LabeledField(label: "place name", placeholder: "Larchmont Noodles", text: $manualName)
            LabeledField(label: "area", placeholder: "arts district", text: $manualArea)

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("category")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["coffee", "restaurant", "hike", "bar", "park"], id: \.self) { category in
                            Button {
                                manualCategory = category
                            } label: {
                                WanderChip(title: category, isSelected: manualCategory == category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let resolutionMessage {
                InlineMessage(text: resolutionMessage)
            }

            WanderPrimaryButton(
                title: isResolvingCandidates ? "finding..." : "find this place",
                systemImage: "magnifyingglass",
                isDisabled: manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolvingCandidates
            ) {
                Task {
                    await resolveManualCandidates()
                }
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

            WanderPrimaryButton(title: "add manually instead", systemImage: "square.and.pencil") {
                step = .manual
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
        manualArea = ""
        manualCategory = "coffee"
        linkInput = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        pendingVisitPhotoAttachments = []
        isImportingPhoto = false
        saveToast = nil
        addSaveFlow = nil
    }

    private func resetAfterSave() {
        step = .source
        candidates = []
        selectedCandidateID = nil
        selectedSource = .manual
        manualName = ""
        manualArea = ""
        manualCategory = "coffee"
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

    private func showSaveToast(for result: SaveResult?) {
        let toast = SaveSyncFeedback(syncState: result?.syncState ?? .localOnly, canSignIn: !auth.isSignedIn)
        saveToast = toast

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(toast.usesWarningHaptic ? .warning : .success)

        Task {
            try? await Task.sleep(nanoseconds: toast.dismissDelayNanoseconds)
            await MainActor.run {
                if saveToast?.id == toast.id {
                    saveToast = nil
                }
            }
        }
    }

    private func goBack() {
        resolutionMessage = nil

        switch step {
        case .link:
            step = .source
        case .photo:
            step = .source
        case .manual:
            step = .source
        case .confirm:
            if selectedSource == .manual {
                step = .manual
            } else if selectedSource == .link {
                step = .link
            } else {
                step = .source
            }
        case .draft:
            step = .source
        case .source:
            break
        }
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

        if !auth.isSignedIn {
            auth.presentGate(for: .syncPlace)
        }
        showSaveToast(for: result)
        resetAfterSave()
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
                areaHint: manualArea,
                category: manualCategory
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

    private func saveLinkDraft() {
        Task {
            await saveLinkDraftAsync()
        }
    }

    @MainActor
    private func resolveQuickAddQuery() async {
        let query = quickAddQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if Self.looksLikeLink(query) {
            linkInput = query
            await resolveLinkCandidates(inline: true)
        } else {
            manualName = query
            manualArea = ""
            await resolveManualCandidates(inline: true)
        }
    }

    private func clearInlineCandidateResults() {
        candidates = []
        selectedCandidateID = nil
        resolutionMessage = nil
        isShowingInlineCandidateResults = false
    }

    private static func looksLikeLink(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("http://")
            || normalized.hasPrefix("https://")
            || normalized.contains("maps.apple.com")
            || normalized.contains("google.com/maps")
            || normalized.contains("maps.app.goo.gl")
    }

    @MainActor
    private func saveLinkDraftAsync() async {
        selectedSource = .link
        resolutionMessage = nil
        draft = await store.createUnresolvedDraft(
            sourceType: .link,
            originalInput: linkInput,
            backend: auth.isSignedIn ? backend : nil
        )

        if auth.isSignedIn,
           let draft,
           let result = await store.processExtractionJob(for: draft, backend: backend),
           applyExtractionResult(result, source: .link) {
            return
        }

        step = .draft
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
            resolutionMessage = "Could not import that photo. Try another one or add manually."
        }
    }

    @MainActor
    private func applyPhotoImportResolution(_ resolution: PhotoPlaceImportResolution) -> Bool {
        switch resolution.outcome {
        case .candidates:
            guard !resolution.candidates.isEmpty else { return false }

            selectedSource = .photo
            manualName = resolution.manualName ?? resolution.candidates.first?.name ?? ""
            manualArea = ""
            candidates = resolution.candidates
            selectedCandidateID = resolution.candidates.first?.id
            resolutionMessage = resolution.message
            step = .confirm
            return true
        case .manualRescue:
            selectedSource = .manual
            manualName = resolution.manualName ?? ""
            manualArea = ""
            candidates = []
            selectedCandidateID = nil
            resolutionMessage = resolution.message
            step = .manual
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
    case link
    case manual
    case photo
    case confirm
    case draft

    var subtitle: String {
        switch self {
        case .source: "Start with where you are, a name, a link, or a photo."
        case .link: "Paste the link; we'll look for the place."
        case .manual: "Name is enough; area helps."
        case .photo: "Choose a photo; we'll look for a place."
        case .confirm: "Pick the right place, then save it."
        case .draft: "we could not find enough place info yet."
        }
    }

    var canGoBack: Bool {
        switch self {
        case .link, .manual, .photo, .confirm, .draft:
            true
        case .source:
            false
        }
    }
}

private struct AddSaveToastView: View {
    let toast: SaveSyncFeedback
    let signInAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: toast.systemImage)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: 34, height: 34)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(toast.title)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(toast.message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(width: 30, height: 30)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if toast.canSignIn {
                Button(action: signInAction) {
                    Text("sign in to sync")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

private struct AddSearchField: View {
    @Binding var query: String
    let isLoading: Bool
    let submit: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: isLoading ? "hourglass" : "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField("search by name or add a link", text: $query)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .textInputAutocapitalization(.never)
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
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search by name or add a link")
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
                    .frame(width: 40, height: 40)
                    .background(isPrimary ? WanderTheme.terracottaDark.color.opacity(0.18) : WanderTheme.surfaceSand.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color.opacity(0.82) : WanderTheme.textMuted.color)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textFaint.color)
            }
            .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .frame(minHeight: 62)
            .padding(WanderTheme.spacing3)
            .background(isPrimary ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
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
