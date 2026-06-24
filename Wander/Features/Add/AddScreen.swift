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
    @State private var selectedStatus: PlaceStatus = .been
    @State private var selectedVisibility: PlaceVisibility = .followers
    @State private var selectedSource: AddSourceType = .manual
    @State private var note = ""
    @State private var manualName = ""
    @State private var manualArea = ""
    @State private var manualCategory = "coffee"
    @State private var linkInput = ""
    @State private var quickAddQuery = ""
    @State private var isShowingInlineCandidateResults = false
    @State private var selectedAnswers: [String: Set<String>] = [:]
    @State private var savedResult: SaveResult?
    @State private var draft: UnresolvedDraft?
    @State private var isResolvingCandidates = false
    @State private var resolutionMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    @State private var saveToast: AddSaveToast?

    init(resetToken: UUID = UUID()) {
        self.resetToken = resetToken
    }

    private var selectedCandidate: PlaceCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    private var currentQuestionBlocks: [AddQuestionBlock] {
        AddQuestionTemplates.blocks(
            category: selectedCandidate?.category ?? manualCategory,
            status: selectedStatus
        )
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
                    case .details:
                        detailsForm
                    case .saved:
                        savedView
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

            PickerBlock(title: "save as") {
                HStack(spacing: WanderTheme.spacing2) {
                    ChoicePill(title: "been", isSelected: selectedStatus == .been) { selectedStatus = .been }
                    ChoicePill(title: "wanna go", isSelected: selectedStatus == .wannaGo) { selectedStatus = .wannaGo }
                }
            }

            WanderPrimaryButton(title: "continue to details", systemImage: "arrow.right") {
                prepareDetails()
            }
        }
    }

    private var detailsForm: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            if let selectedCandidate {
                HStack {
                    CategoryIcon(category: selectedCandidate.category)
                    VStack(alignment: .leading) {
                        Text(selectedCandidate.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text(selectedStatus.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                }
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

            ForEach(currentQuestionBlocks) { block in
                QuestionBlock(title: block.title, tag: block.tag) {
                    SelectableQuestionOptions(
                        block: block,
                        selectedValues: selectedAnswers[block.key] ?? Set(block.defaultValues)
                    ) { option in
                        toggleAnswer(option, in: block)
                    }
                }
            }

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("a note for future you")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                TextField("best table, what to order, who told you...", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .tint(WanderTheme.terracotta.color)
                    .lineLimit(3, reservesSpace: true)
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }

            PlaceVisibilityStealthToggle(visibility: $selectedVisibility)

            WanderPrimaryButton(title: "save to my map", systemImage: "checkmark") {
                Task {
                    await saveSelectedCandidate()
                }
            }
        }
    }

    private var savedView: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: selectedStatus == .been ? "mappin.circle.fill" : "mappin.circle")
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
                .accessibilityHidden(true)

            VStack(spacing: WanderTheme.spacing2) {
                Text("it's on your map")
                    .font(.system(size: 26, weight: .black))
                Text(selectedVisibility.isStealthModeEnabled ? "saved as \(selectedStatus.displayTitle) in stealth mode." : "saved as \(selectedStatus.displayTitle).")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }

            if let savedResult {
                VStack(spacing: WanderTheme.spacing2) {
                    Text(syncStatusTitle(for: savedResult.syncState))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.vertical, WanderTheme.spacing2)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Capsule())

                    if savedResult.syncState == .pendingCreate && !auth.isSignedIn {
                        Button {
                            auth.presentGate(for: .syncPlace)
                        } label: {
                            Text("sign in to sync")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WanderTheme.terracotta.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            WanderPrimaryButton(title: "add another place", systemImage: "plus") {
                reset()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WanderTheme.spacing8)
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
        selectedStatus = .been
        selectedVisibility = store.defaultVisibility.normalizedForStealthMode
        selectedSource = .manual
        note = ""
        manualName = ""
        manualArea = ""
        manualCategory = "coffee"
        linkInput = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        selectedAnswers = [:]
        savedResult = nil
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        isImportingPhoto = false
        saveToast = nil
    }

    private func resetAfterSave() {
        step = .source
        candidates = []
        selectedCandidateID = nil
        selectedStatus = .been
        selectedVisibility = store.defaultVisibility.normalizedForStealthMode
        selectedSource = .manual
        note = ""
        manualName = ""
        manualArea = ""
        manualCategory = "coffee"
        linkInput = ""
        quickAddQuery = ""
        isShowingInlineCandidateResults = false
        selectedAnswers = [:]
        savedResult = nil
        draft = nil
        resolutionMessage = nil
        isResolvingCandidates = false
        selectedPhotoItem = nil
        isImportingPhoto = false
    }

    private func showSaveToast(for result: SaveResult?) {
        let toast = AddSaveToast(syncState: result?.syncState ?? .localOnly, canSignIn: !auth.isSignedIn)
        saveToast = toast

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result?.syncState == .serverDenied ? .warning : .success)

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
        case .details:
            step = isShowingInlineCandidateResults ? .source : .confirm
        case .draft:
            step = .source
        case .source, .saved:
            break
        }
    }

    private func prepareDetails() {
        let blocks = currentQuestionBlocks
        let allowedKeys = Set(blocks.map(\.key))
        var nextAnswers = selectedAnswers.filter { allowedKeys.contains($0.key) }

        for block in blocks where nextAnswers[block.key] == nil {
            nextAnswers[block.key] = Set(block.defaultValues)
        }

        selectedAnswers = nextAnswers
        step = .details
    }

    private func toggleAnswer(_ option: String, in block: AddQuestionBlock) {
        var values = selectedAnswers[block.key] ?? Set(block.defaultValues)

        switch block.kind {
        case .singleChoice:
            values = [option]
        case .multiTag:
            if values.contains(option) {
                values.remove(option)
            } else {
                values.insert(option)
            }
        }

        selectedAnswers[block.key] = values
    }

    private func attributeDrafts() -> [PlaceAttributeDraft] {
        currentQuestionBlocks.compactMap { block in
            let values = orderedSelections(for: block)
            guard !values.isEmpty else { return nil }

            switch block.kind {
            case .singleChoice:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValue: values[0])
            case .multiTag:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValues: values)
            }
        }
    }

    @MainActor
    private func saveSelectedCandidate() async {
        guard let selectedCandidate else { return }

        savedResult = await store.saveCandidate(
            selectedCandidate,
            status: selectedStatus,
            visibility: selectedVisibility,
            note: note.isEmpty ? nil : note,
            sourceType: selectedSource,
            attributes: attributeDrafts(),
            backend: auth.isSignedIn ? backend : nil
        )

        if !auth.isSignedIn {
            auth.presentGate(for: .syncPlace)
        }
        showSaveToast(for: savedResult)
        resetAfterSave()
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
            selectedVisibility = store.defaultVisibility.normalizedForStealthMode
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
            selectedVisibility = store.defaultVisibility.normalizedForStealthMode
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
            selectedVisibility = store.defaultVisibility.normalizedForStealthMode
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
        selectedAnswers = [:]
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
            selectedVisibility = store.defaultVisibility.normalizedForStealthMode
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
        selectedVisibility = store.defaultVisibility.normalizedForStealthMode
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

    private func syncStatusTitle(for syncState: SyncState) -> String {
        switch syncState {
        case .synced:
            "synced"
        case .failed:
            "sync failed"
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            "sync queued"
        case .localOnly:
            "saved here"
        case .serverDenied:
            "needs review"
        case .tombstoned:
            "removed"
        }
    }

    private func orderedSelections(for block: AddQuestionBlock) -> [String] {
        let values = selectedAnswers[block.key] ?? Set(block.defaultValues)
        let optionSelections = block.options.filter { values.contains($0) }
        let customSelections = values
            .filter { value in
                !block.options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            .sorted()
        return optionSelections + customSelections
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
    case details
    case saved
    case draft

    var subtitle: String {
        switch self {
        case .source: "Start with where you are, a name, a link, or a photo."
        case .link: "Paste the link; we'll look for the place."
        case .manual: "Name is enough; area helps."
        case .photo: "Choose a photo; we'll look for a place."
        case .confirm: "Pick the place and status."
        case .details: "optional taps for future you."
        case .saved: "it is ready on your map."
        case .draft: "we could not find enough place info yet."
        }
    }

    var canGoBack: Bool {
        switch self {
        case .link, .manual, .photo, .confirm, .details, .draft:
            true
        case .source, .saved:
            false
        }
    }
}

private struct AddSaveToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let canSignIn: Bool
    let dismissDelayNanoseconds: UInt64

    init(syncState: SyncState, canSignIn: Bool) {
        self.canSignIn = canSignIn

        switch syncState {
        case .synced:
            title = "saved to your map"
            message = "Synced and ready."
            systemImage = "checkmark"
            dismissDelayNanoseconds = 2_000_000_000
        case .failed:
            title = "saved here"
            message = canSignIn ? "Sign in to back it up." : "We'll keep trying to back it up."
            systemImage = "checkmark"
            dismissDelayNanoseconds = 3_000_000_000
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            title = "saved here"
            message = "Sync is queued."
            systemImage = "arrow.triangle.2.circlepath"
            dismissDelayNanoseconds = 3_500_000_000
        case .localOnly:
            title = "saved here"
            message = canSignIn ? "Sign in to back it up." : "Kept on this phone."
            systemImage = "checkmark"
            dismissDelayNanoseconds = canSignIn ? 5_000_000_000 : 2_500_000_000
        case .serverDenied:
            title = "needs review"
            message = "Saved locally until this can sync."
            systemImage = "exclamationmark.triangle"
            dismissDelayNanoseconds = 5_000_000_000
        case .tombstoned:
            title = "removed"
            message = "This saved place was removed."
            systemImage = "trash"
            dismissDelayNanoseconds = 3_500_000_000
        }
    }
}

private struct AddSaveToastView: View {
    let toast: AddSaveToast
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

private struct PickerBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            content
        }
    }
}

private struct ChoicePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
                .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
    }
}

private struct QuestionBlock<Content: View>: View {
    let title: String
    let tag: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                Spacer()
                Text(tag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            content
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct SelectableQuestionOptions: View {
    let block: AddQuestionBlock
    let selectedValues: Set<String>
    let onSelect: (String) -> Void
    @State private var isAddingCustomTag = false
    @State private var customTagText = ""
    @FocusState private var isCustomTagFocused: Bool

    var body: some View {
        WrappingChipLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
            ForEach(displayOptions, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    WanderChip(title: option, isSelected: selectedValues.contains(option))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }

            if block.kind == .multiTag {
                customTagControl
            }
        }
    }

    private var displayOptions: [String] {
        let customOptions = selectedValues
            .filter { value in
                !block.options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            .sorted()

        return block.options + customOptions
    }

    @ViewBuilder
    private var customTagControl: some View {
        if isAddingCustomTag {
            HStack(spacing: WanderTheme.spacing1) {
                TextField("tag", text: $customTagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .tint(WanderTheme.terracotta.color)
                    .frame(width: 86)
                    .submitLabel(.done)
                    .focused($isCustomTagFocused)
                    .onSubmit(addCustomTag)

                Button(action: addCustomTag) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save custom tag")
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .padding(.horizontal, WanderTheme.spacing2)
            .background(WanderTheme.surfaceRaised.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
            .fixedSize(horizontal: true, vertical: false)
            .onAppear {
                isCustomTagFocused = true
            }
        } else {
            Button {
                isAddingCustomTag = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .black))
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .background(WanderTheme.surfaceRaised.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add custom tag")
        }
    }

    private func addCustomTag() {
        let tag = customTagText
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !tag.isEmpty else {
            isAddingCustomTag = false
            customTagText = ""
            return
        }

        if let existing = displayOptions.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            if !selectedValues.contains(existing) {
                onSelect(existing)
            }
        } else {
            onSelect(tag)
        }

        customTagText = ""
        isAddingCustomTag = false
    }
}

private struct WrappingChipLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows.items {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> ChipRows {
        var rows: [ChipRow] = []
        var currentItems: [ChipItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        let effectiveMaxWidth = max(1, maxWidth)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if nextWidth > effectiveMaxWidth, !currentItems.isEmpty {
                rows.append(ChipRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [ChipItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(ChipItem(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(ChipRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return ChipRows(items: rows, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing)
    }

    private struct ChipItem {
        let index: Int
        let size: CGSize
    }

    private struct ChipRow {
        let items: [ChipItem]
        let width: CGFloat
        let height: CGFloat
    }

    private struct ChipRows {
        let items: [ChipRow]
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat

        var width: CGFloat {
            items.map(\.width).max() ?? 0
        }

        var height: CGFloat {
            guard !items.isEmpty else { return 0 }
            return items.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, items.count - 1))
        }
    }
}

private struct CategoryIcon: View {
    let category: String

    var body: some View {
        Image(systemName: imageName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(width: 40, height: 40)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())
    }

    private var imageName: String {
        WanderPlaceCategory.symbolName(for: category)
    }
}
