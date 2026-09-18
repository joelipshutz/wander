import SwiftUI

/// The save editor owns presentation so scrolling/rebuilding a question panel
/// cannot dismiss its customization page or native confirmation.
struct CheckInQuestionCustomizationRequest: Identifiable {
    let id = UUID()
    let scopeIdentity: String
    let content: CheckInQuestionCustomizationSheet
}

/// Keep native presentation in a stable observable owner. Publishing the request
/// makes it an explicit editor dependency while nested confirmations are open.
@MainActor
final class CheckInQuestionPresentation: ObservableObject {
    @Published var request: CheckInQuestionCustomizationRequest?
}

/// Shared by new and edited check-ins. Shared and Stealth answers use separate
/// bindings; this view never serializes a save.
struct CheckInQuestionPanel: View {
    let ownerUserID: String
    let subtypeKey: String
    let subtypeTitle: String
    let defaultQuestions: [PlaceCheckInQuestion]
    let savedCustomQuestions: [CheckInCustomQuestion]
    @Binding var answers: [String: Set<String>]
    @Binding var customAnswers: [String: String]

    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var configuration: CheckInQuestionConfiguration
    @State private var loadedScope = ""
    @State private var customDefinitions: [CheckInCustomQuestion] = []
    @Binding private var customization: CheckInQuestionCustomizationRequest?
    @State private var showsAdditionalQuestions = false
    @State private var renderedPreferredIDs: [String] = []
    @State private var dismissedIDs: Set<String> = []
    @State private var preferenceError: String?
    private let preferenceStore: CheckInQuestionPreferenceStore

    init(
        ownerUserID: String,
        subtypeKey: String,
        subtypeTitle: String,
        defaultQuestions: [PlaceCheckInQuestion],
        savedCustomQuestions: [CheckInCustomQuestion] = [],
        answers: Binding<[String: Set<String>]>,
        customAnswers: Binding<[String: String]>,
        customization: Binding<CheckInQuestionCustomizationRequest?>,
        preferenceStore: CheckInQuestionPreferenceStore = CheckInQuestionPreferenceStore()
    ) {
        self.ownerUserID = ownerUserID
        self.subtypeKey = subtypeKey
        self.subtypeTitle = subtypeTitle
        self.defaultQuestions = defaultQuestions
        self.savedCustomQuestions = savedCustomQuestions
        _answers = answers
        _customAnswers = customAnswers
        _customization = customization
        self.preferenceStore = preferenceStore
        _configuration = State(initialValue: CheckInQuestionConfiguration(
            orderedQuestionIDs: defaultQuestions.map(\.id)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            header
            if let preferenceError {
                Text(preferenceError).font(AstirTypography.bodySmall)
                    .foregroundStyle(WanderTheme.stateError.color)
            }

            if preferredQuestions.isEmpty {
                Text("No recurring questions for this place type. Add any you want in Customize.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
            }

            ForEach(preferredQuestions) { question in
                answerRow(question)
            }

            if !additionalQuestions.isEmpty {
                Button {
                    showsAdditionalQuestions.toggle()
                } label: {
                    HStack {
                        Text("Also noted (\(additionalQuestions.count))")
                            .font(AstirTypography.control)
                        Spacer()
                        Image(systemName: showsAdditionalQuestions ? "chevron.down" : "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(brandMode.accentText)
                .accessibilityIdentifier("save.questions.alsoNoted")
                .accessibilityValue(showsAdditionalQuestions ? "Expanded" : "Collapsed")

                if showsAdditionalQuestions {
                    ForEach(additionalQuestions) { question in
                        answerRow(question)
                    }
                }
            }
        }
        .foregroundStyle(brandMode.primaryText)
        .onChange(of: scopeIdentity, initial: true) { _, _ in loadConfiguration() }
    }

    private func presentCustomization() {
        customization = CheckInQuestionCustomizationRequest(
            scopeIdentity: scopeIdentity,
            content: CheckInQuestionCustomizationSheet(
                ownerUserID: ownerUserID,
                subtypeKey: subtypeKey,
                subtypeTitle: subtypeTitle,
                defaultQuestions: defaultQuestions,
                configuration: currentConfiguration,
                preferenceStore: preferenceStore,
                answerStealthOverrides: answerStealthOverrides,
                onStealthChange: transferDraftAnswer
            ) { updated in
                configuration = updated
                renderedPreferredIDs = updated.orderedQuestionIDs
                dismissedIDs = []
                customDefinitions = preferenceStore.allCustomQuestions(ownerUserID: ownerUserID)
            }
        )
    }

    private var scopeIdentity: String {
        // Length prefixes avoid account/subtype separator collisions.
        "\(ownerUserID.utf8.count):\(ownerUserID)\(subtypeKey)"
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                sectionTitle
                customizeButton
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing3) {
                sectionTitle
                Spacer(minLength: WanderTheme.spacing2)
                customizeButton
            }
        }
    }

    private var sectionTitle: some View {
        Text("useful details")
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var customizeButton: some View {
        Button(action: presentCustomization) {
            Text("Customize")
                .font(AstirTypography.control)
                .frame(minHeight: WanderTheme.tapMinimum)
                .contentShape(Rectangle())
        }
        .foregroundStyle(brandMode.accentText)
        .disabled(ownerUserID.isEmpty)
        .accessibilityLabel("Customize questions for \(subtypeTitle)")
        .accessibilityIdentifier("save.questions.customize")
    }

    private var currentConfiguration: CheckInQuestionConfiguration {
        loadedScope == scopeIdentity
            ? configuration
            : CheckInQuestionConfiguration(orderedQuestionIDs: defaultQuestions.map(\.id))
    }

    private var preferredQuestions: [CheckInPresentedQuestion] {
        (loadedScope == scopeIdentity ? renderedPreferredIDs : currentConfiguration.orderedQuestionIDs).compactMap(presentedQuestion)
    }

    private var additionalQuestions: [CheckInPresentedQuestion] {
        let preferred = Set(loadedScope == scopeIdentity ? renderedPreferredIDs : currentConfiguration.orderedQuestionIDs)
        let catalogIDs = answers.keys.filter { !(answers[$0] ?? []).isEmpty }
        let privateIDs = loadedScope == scopeIdentity ? Array(customAnswers.keys) : []
        return Set(catalogIDs + privateIDs)
            .filter { !preferred.contains($0) && (!currentConfiguration.hiddenQuestionIDs.contains($0) || dismissedIDs.contains($0)) }
            .sorted()
            .compactMap(presentedQuestion)
    }

    private func presentedQuestion(_ id: String) -> CheckInPresentedQuestion? {
        if let question = defaultQuestions.first(where: { $0.id == id })
            ?? PlaceCheckInQuestionCatalog.question(id: id) {
            return CheckInPresentedQuestion(
                id: question.id,
                prompt: question.prompt,
                options: question.answerOptions,
                isPrivate: isStealth(questionID: id)
            )
        }
        guard loadedScope == scopeIdentity,
              let question = customDefinitions.first(where: { $0.id == id })
                ?? configuration.customQuestions.first(where: { $0.id == id })
                ?? savedCustomQuestions.first(where: { $0.id == id })
        else { return nil }
        return CheckInPresentedQuestion(id: question.id, prompt: question.prompt, options: ["Yes", "No"], isPrivate: isStealth(questionID: id))
    }

    private func isStealth(questionID: String) -> Bool {
        // An existing answer keeps its own audience when a preference changes
        // elsewhere. Only the explicit editor action below transfers a draft.
        if let value = customAnswers[questionID], !value.isEmpty { return true }
        if let values = answers[questionID], !values.isEmpty { return false }
        return currentConfiguration.isStealth(questionID: questionID)
    }

    private var answerStealthOverrides: [String: Bool] {
        var overrides = answers.filter { !$0.value.isEmpty }.mapValues { _ in false }
        for (id, value) in customAnswers where !value.isEmpty { overrides[id] = true }
        return overrides
    }

    private func selectedValues(for question: CheckInPresentedQuestion) -> Set<String> {
        let values: Set<String>
        if question.isPrivate, let value = customAnswers[question.id] {
            values = PlaceCheckInQuestionCatalog.question(id: question.id)?.selectedValues(fromPrivateValue: value) ?? [value]
        } else {
            values = answers[question.id] ?? []
        }
        guard CheckInCustomQuestion.isCustomID(question.id) else { return values }
        return Set(values.compactMap { $0 == "yes" ? "Yes" : $0 == "no" ? "No" : nil })
    }

    private func answerRow(_ question: CheckInPresentedQuestion) -> some View {
        CheckInQuestionAnswerRow(
            question: question,
            selectedValues: selectedValues(for: question),
            isDismissed: dismissedIDs.contains(question.id),
            onToggleUseful: { toggleUseful(questionID: question.id) },
            onSelect: { option in
                let value = CheckInCustomQuestion.isCustomID(question.id) ? option.lowercased() : option
                if question.isPrivate {
                    if let catalog = PlaceCheckInQuestionCatalog.question(id: question.id) {
                        let selected = catalog.selectedValues(fromPrivateValue: customAnswers[question.id] ?? "")
                        let updated = CheckInQuestionAnswerPolicy.toggling(value, selected: selected, allowsMultipleSelection: catalog.allowsMultipleSelection)
                        customAnswers[question.id] = catalog.privateValue(for: updated)
                    } else {
                        customAnswers[question.id] = customAnswers[question.id] == value ? nil : value
                    }
                } else {
                    answers[question.id] = CheckInQuestionAnswerPolicy.toggling(
                        value,
                        selected: answers[question.id] ?? [],
                        allowsMultipleSelection: PlaceCheckInQuestionCatalog.question(id: question.id)?.allowsMultipleSelection ?? false
                    )
                }
            },
            onClear: {
                if question.isPrivate {
                    customAnswers.removeValue(forKey: question.id)
                } else {
                    answers[question.id] = []
                }
            }
        )
    }

    private func transferDraftAnswer(questionID: String, stealth: Bool) {
        if stealth {
            if let values = answers[questionID], !values.isEmpty {
                customAnswers[questionID] = PlaceCheckInQuestionCatalog.question(id: questionID)?.privateValue(for: values) ?? values.sorted().first
                // Explicit empty is needed to clear a previously shared value.
                answers[questionID] = []
            }
        } else if let value = customAnswers.removeValue(forKey: questionID) {
            answers[questionID] = PlaceCheckInQuestionCatalog.question(id: questionID)?.selectedValues(fromPrivateValue: value) ?? [value]
        }
    }

    private func toggleUseful(questionID: String) {
        var updated = currentConfiguration
        let undo = dismissedIDs.contains(questionID)
        if undo {
            // Count only currently visible predecessors so multiple removals
            // can be undone in any order without scrambling the original list.
            let index = renderedPreferredIDs.firstIndex(of: questionID).map { original in
                renderedPreferredIDs.prefix(original).filter { updated.orderedQuestionIDs.contains($0) }.count
            }
            updated.undoHiddenQuestion(id: questionID, originalIndex: index)
        } else {
            updated.hideQuestion(id: questionID)
        }
        do {
            try preferenceStore.saveConfiguration(updated, ownerUserID: ownerUserID, subtypeKey: subtypeKey)
            configuration = updated
            if undo { dismissedIDs.remove(questionID) } else { dismissedIDs.insert(questionID) }
            preferenceError = nil
        } catch { preferenceError = error.localizedDescription }
    }

    private func loadConfiguration() {
        // Repeated appearances must not reset the current sheet or Undo state.
        // A different owner/subtype receives a fresh configuration.
        guard loadedScope != scopeIdentity else { return }
        configuration = preferenceStore.configuration(
            ownerUserID: ownerUserID,
            subtypeKey: subtypeKey,
            defaultQuestionIDs: defaultQuestions.map(\.id)
        )
        customDefinitions = preferenceStore.allCustomQuestions(ownerUserID: ownerUserID)
        loadedScope = scopeIdentity
        renderedPreferredIDs = configuration.orderedQuestionIDs
        dismissedIDs = []
        preferenceError = nil
        if let customization, customization.scopeIdentity != scopeIdentity {
            self.customization = nil
        }
    }
}

private struct CheckInPresentedQuestion: Identifiable {
    let id: String
    let prompt: String
    let options: [String]
    let isPrivate: Bool
}

/// Render only in the signed-in owner's visit detail. This reads the private
/// local store; these values never enter shared profile or search projections.
struct CheckInPrivateAnswerSummary: View {
    let ownerUserID: String
    let userPlaceLocalID: String
    /// Stable server UUID assigned when the visit is created; a legacy visit
    /// without one may use its local ID. The parameter name is kept for callers.
    let visitLocalID: String
    @Environment(\.astirBrandMode) private var brandMode
    @State private var rows: [PrivateAnswerRow] = []
    @State private var loadFailed = false
    @State private var loadedIdentity: [String] = []

    var body: some View {
        Group {
            if loadedIdentity == identity, !rows.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    Label("Stealth", systemImage: "eye.slash")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                            Text(row.prompt)
                                .font(AstirTypography.bodySmall)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(row.answer)
                                .font(AstirTypography.control)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .foregroundStyle(brandMode.primaryText)
                .accessibilityIdentifier("checkIn.privateAnswers")
            } else if loadedIdentity == identity, loadFailed {
                Text("Your private answers couldn’t be loaded on this device.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }
        }
        .onChange(of: identity, initial: true) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: CheckInQuestionPreferenceStore.didChangeNotification)) { _ in load() }
    }

    private var identity: [String] { [ownerUserID, userPlaceLocalID, visitLocalID] }

    private func load() {
        rows = []
        loadFailed = false
        let store = CheckInQuestionPreferenceStore()
        do {
            let answers = try store.loadPrivateAnswers(
                ownerUserID: ownerUserID, userPlaceID: userPlaceLocalID, visitID: visitLocalID
            )
            let customQuestions = store.allCustomQuestions(ownerUserID: ownerUserID)
            rows = answers.compactMap { id, value in
                if let question = PlaceCheckInQuestionCatalog.question(id: id) {
                    let selected = question.selectedValues(fromPrivateValue: value)
                    guard !selected.isEmpty else { return nil }
                    return PrivateAnswerRow(id: id, prompt: question.prompt, answer: question.acceptedOptions.filter(selected.contains).joined(separator: ", "))
                }
                guard let question = customQuestions.first(where: { $0.id == id }), value == "yes" || value == "no" else { return nil }
                return PrivateAnswerRow(id: id, prompt: question.prompt, answer: value == "yes" ? "Yes" : "No")
            }.sorted { $0.prompt.localizedStandardCompare($1.prompt) == .orderedAscending }
        } catch {
            loadFailed = true
        }
        loadedIdentity = identity
    }

    private struct PrivateAnswerRow: Identifiable {
        let id: String
        let prompt: String
        let answer: String
    }
}

private struct CheckInQuestionAnswerRow: View {
    let question: CheckInPresentedQuestion
    let selectedValues: Set<String>
    let isDismissed: Bool
    let onToggleUseful: () -> Void
    let onSelect: (String) -> Void
    let onClear: () -> Void
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayOptions: [String] {
        question.options + selectedValues.filter { !question.options.contains($0) }.sorted()
    }

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : min(3, max(1, displayOptions.count))
    }

    private var optionRows: [[String]] {
        let options = displayOptions
        return stride(from: 0, to: options.count, by: columnCount).map { start in
            Array(options[start..<min(start + columnCount, options.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { prompt; usefulnessButton }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
                    prompt
                    Spacer(minLength: 0)
                    usefulnessButton
                }
            }

            // These small option sets must remain in the accessibility tree
            // while their enclosing save sheet scrolls or changes detents.
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                ForEach(Array(optionRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                        ForEach(row, id: \.self) { option in
                            optionButton(option)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(0..<(columnCount - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 0)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .disabled(isDismissed)
            .saturation(isDismissed ? 0 : 1)
            .opacity(isDismissed ? 0.4 : 1)

            if !selectedValues.isEmpty && !isDismissed {
                Button("Clear answer", action: onClear)
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .accessibilityLabel("Clear answer to \(question.prompt)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var prompt: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
            Text(question.prompt)
                .font(AstirTypography.cardTitle)
                .foregroundStyle(isDismissed ? brandMode.secondaryText : brandMode.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("save.question.row.\(question.id)")
            if question.isPrivate {
                Label("Stealth", systemImage: "eye.slash")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize()
                    .accessibilityIdentifier("save.question.stealth.\(question.id)")
            }
        }
        .opacity(isDismissed ? 0.5 : 1)
    }

    private var usefulnessButton: some View {
        Button(action: onToggleUseful) {
            Text(isDismissed ? "Undo" : "Not useful")
                .font(AstirTypography.label)
                .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
                .contentShape(Rectangle())
                .fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(.plain)
            .foregroundStyle(brandMode.accentText)
            .accessibilityLabel("\(isDismissed ? "Undo hiding" : "Not useful:") \(question.prompt)")
            .accessibilityValue(isDismissed ? "Hidden from future prompts" : "Shown")
            .accessibilityIdentifier("save.question.useful.\(question.id)")
    }

    private func optionButton(_ option: String) -> some View {
        let selected = selectedValues.contains(option)
        return Button {
            onSelect(option)
        } label: {
            HStack(spacing: WanderTheme.spacing1) {
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                Text(option)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AstirTypography.control)
            .foregroundStyle(selected ? brandMode.accentText : brandMode.primaryText)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            .padding(.horizontal, WanderTheme.spacing2)
            .padding(.vertical, WanderTheme.spacing1)
            .background(selected ? brandMode.accentWash : brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(selected ? brandMode.accentText : brandMode.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(question.prompt) \(option)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Tap again to clear this answer." : "Select this answer.")
        .accessibilityIdentifier("save.question.\(question.id).\(option)")
    }
}

struct CheckInQuestionCustomizationSheet: View {
    let ownerUserID: String
    let subtypeKey: String
    let subtypeTitle: String
    let defaultQuestions: [PlaceCheckInQuestion]
    let preferenceStore: CheckInQuestionPreferenceStore
    let onConfigurationChange: (CheckInQuestionConfiguration) -> Void
    let onStealthChange: ((String, Bool) -> Void)?
    let answerStealthOverrides: [String: Bool]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var configuration: CheckInQuestionConfiguration
    @State private var errorMessage: String?
    @State private var showsCatalog = false
    @State private var showsCustomEditor = false
    @State private var showsRestoreConfirmation = false
    @State private var changedStealth: [String: Bool] = [:]
    private var usesOwnNavigationStack = true

    init(
        ownerUserID: String,
        subtypeKey: String,
        subtypeTitle: String,
        defaultQuestions: [PlaceCheckInQuestion],
        configuration: CheckInQuestionConfiguration,
        preferenceStore: CheckInQuestionPreferenceStore,
        answerStealthOverrides: [String: Bool] = [:],
        onStealthChange: ((String, Bool) -> Void)? = nil,
        onConfigurationChange: @escaping (CheckInQuestionConfiguration) -> Void
    ) {
        self.ownerUserID = ownerUserID
        self.subtypeKey = subtypeKey
        self.subtypeTitle = subtypeTitle
        self.defaultQuestions = defaultQuestions
        self.preferenceStore = preferenceStore
        self.onStealthChange = onStealthChange
        self.answerStealthOverrides = answerStealthOverrides
        self.onConfigurationChange = onConfigurationChange
        _configuration = State(initialValue: configuration)
    }

    /// The save sheet already owns a NavigationStack; keep its customization
    /// flow in that stack so back navigation has a single presentation owner.
    func inExistingNavigationStack() -> Self {
        var screen = self
        screen.usesOwnNavigationStack = false
        return screen
    }

    var body: some View {
        Group {
            if usesOwnNavigationStack {
                NavigationStack { questionList }
            } else {
                questionList
            }
        }
        .alert("Are you sure?", isPresented: $showsRestoreConfirmation) {
            Button("Yes, restore") { update { $0.restoreSuggestedQuestions(defaultQuestions.map(\.id)) } }
            Button("No, cancel", role: .cancel) {}
        } message: {
            Text("Replace this list with suggested questions? Your previous answers will be kept.")
        }
        .tint(brandMode.accentText)
    }

    private var questionList: some View {
        List {
            Section {
                ForEach(configuration.orderedQuestionIDs, id: \.self) { id in
                    HStack(spacing: WanderTheme.spacing2) {
                        Text(prompt(for: id))
                            .font(AstirTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("save.questions.recurring.\(id)")
                        Spacer(minLength: WanderTheme.spacing1)
                        Button { toggleStealth(questionID: id) } label: {
                            Image(systemName: displayedStealth(questionID: id) ? "eye.slash" : "eye")
                                .foregroundStyle(displayedStealth(questionID: id) ? brandMode.secondaryText : brandMode.accent)
                                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stealth for \(prompt(for: id))")
                        .accessibilityValue(displayedStealth(questionID: id) ? "On, only you" : "Off, check-in audience")
                        .accessibilityHint("Toggle who can see this question and answer")
                        .accessibilityIdentifier("save.questions.stealth.\(id)")
                    }
                    .listRowBackground(brandMode.raisedBackground)
                }
                .onMove { offsets, destination in
                    update { $0.moveQuestions(from: offsets, to: destination) }
                }
                .onDelete { offsets in update { $0.removeQuestions(at: offsets) } }
            } header: {
                Text("For \(subtypeTitle)")
            } footer: {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Drag to reorder.")
                    Text("Removing a question changes future prompts and keeps previous answers.")
                    Label("This symbol means those questions only stay with you", systemImage: "eye.slash")
                        .accessibilityLabel("Slashed eye. This symbol means those questions only stay with you")
                }
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("save.questions.footer")
            }

            Section {
                // Native NavigationLinks are disabled by active List edit
                // mode. Buttons keep navigation available while reordering.
                Button { showsCatalog = true } label: {
                    Label("Add a question", systemImage: "plus")
                        .frame(minHeight: WanderTheme.tapMinimum)
                }
                .accessibilityIdentifier("save.questions.addCatalog")
                Button { showsCustomEditor = true } label: {
                    Label("Create your own", systemImage: "square.and.pencil")
                        .frame(minHeight: WanderTheme.tapMinimum)
                }
                .accessibilityIdentifier("save.questions.createCustom")
            }
            .listRowBackground(brandMode.raisedBackground)

            Section {
                Button("Restore suggested questions") { showsRestoreConfirmation = true }
                    .frame(minHeight: WanderTheme.tapMinimum)
                .accessibilityIdentifier("save.questions.restore")
            }
            .listRowBackground(brandMode.raisedBackground)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(WanderTheme.stateError.color)
                }
                .listRowBackground(brandMode.raisedBackground)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .navigationTitle("Customize questions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $showsCatalog) {
            CheckInAddCatalogQuestionScreen(selectedIDs: Set(configuration.orderedQuestionIDs)) { id in
                let stealth = false
                var updated = configuration
                updated.addCatalogQuestion(id: id, stealth: stealth)
                try persist(updated)
                changedStealth[id] = stealth
                onStealthChange?(id, stealth)
            }
        }
        .navigationDestination(isPresented: $showsCustomEditor) {
            CheckInCreateCustomQuestionScreen { prompt in
                let stealth = true
                var updated = configuration
                let question = try updated.addCustomQuestion(prompt: prompt, stealth: stealth)
                try persist(updated)
                changedStealth[question.id] = stealth
                onStealthChange?(question.id, stealth)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                .accessibilityIdentifier("save.questions.done")
            }
        }
    }

    private func prompt(for id: String) -> String {
        PlaceCheckInQuestionCatalog.question(id: id)?.prompt
            ?? configuration.customQuestions.first(where: { $0.id == id })?.prompt
            ?? "Saved question"
    }

    private func displayedStealth(questionID: String) -> Bool {
        changedStealth[questionID] ?? answerStealthOverrides[questionID] ?? configuration.isStealth(questionID: questionID)
    }

    private func toggleStealth(questionID: String) {
        let stealth = !displayedStealth(questionID: questionID)
        var updated = configuration
        updated.setStealth(stealth, questionID: questionID)
        do {
            try persist(updated)
            changedStealth[questionID] = stealth
            onStealthChange?(questionID, stealth)
        } catch { errorMessage = error.localizedDescription }
    }

    private func update(_ mutation: (inout CheckInQuestionConfiguration) -> Void) {
        var updated = configuration
        mutation(&updated)
        do { try persist(updated) }
        catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ updated: CheckInQuestionConfiguration) throws {
        try preferenceStore.saveConfiguration(updated, ownerUserID: ownerUserID, subtypeKey: subtypeKey)
        configuration = updated
        errorMessage = nil
        onConfigurationChange(updated)
    }
}

private struct CheckInAddCatalogQuestionScreen: View {
    let selectedIDs: Set<String>
    let onAdd: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @State private var errorMessage: String?

    private var matches: [PlaceCheckInQuestion] {
        PlaceCheckInQuestionCatalog.availableQuestions.filter {
            search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.prompt.localizedCaseInsensitiveContains(search)
        }.sorted { $0.prompt.localizedStandardCompare($1.prompt) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                CheckInQuestionSearchField(
                    placeholder: "Find a question",
                    text: $search,
                    isFocused: $isSearchFocused,
                    accessibilityIdentifier: "save.questions.catalogSearch"
                )
            }
            .listRowBackground(brandMode.raisedBackground)


            if let errorMessage {
                Text(errorMessage)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .listRowBackground(brandMode.raisedBackground)
            }
            if matches.isEmpty {
                Text("No matching questions. You can create your own from Customize.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .listRowBackground(brandMode.raisedBackground)
            }
            ForEach(matches, id: \.id) { question in
                Button {
                    isSearchFocused = false
                    do {
                        try onAdd(question.id)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        Text(question.prompt)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: selectedIDs.contains(question.id) ? "checkmark" : "plus")
                            .accessibilityHidden(true)
                    }
                    .font(AstirTypography.body)
                    .frame(minHeight: WanderTheme.tapMinimum)
                }
                .disabled(selectedIDs.contains(question.id))
                .accessibilityLabel("\(question.prompt)\(selectedIDs.contains(question.id) ? ", already added" : "")")
                .accessibilityIdentifier("save.questions.catalog.\(question.id)")
                .listRowBackground(brandMode.raisedBackground)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { isSearchFocused = false }
        .environment(\.editMode, .constant(.inactive))
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .navigationTitle("Add a question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Keep search in the screen's content so presenting or popping a question
/// editor cannot leave a navigation-bar search controller over its controls.
struct CheckInQuestionSearchField: View {
    let placeholder: String
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let accessibilityIdentifier: String
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(brandMode.secondaryText)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .font(AstirTypography.body)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit { isFocused.wrappedValue = false }
                .frame(minHeight: WanderTheme.tapMinimum)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(accessibilityIdentifier)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier(accessibilityIdentifier + ".clear")
            }
        }
    }
}

private struct CheckInCreateCustomQuestionScreen: View {
    let onAdd: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var prompt = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Lots of plants indoors?", text: $prompt, axis: .vertical)
                    .font(AstirTypography.body)
                    .lineLimit(2...5)
                    .focused($isFocused)
                    .accessibilityLabel("Your recurring question")
                    .accessibilityIdentifier("save.questions.customPrompt")
                    .onChange(of: prompt) { _, value in
                        if value.count > CheckInCustomQuestion.maximumPromptLength {
                            prompt = String(value.prefix(CheckInCustomQuestion.maximumPromptLength))
                        }
                    }
            } header: {
                Text("Your question")
            } footer: {
                Text("Ask something you can answer with Yes or No.")
            }
            .listRowBackground(brandMode.raisedBackground)
            if let errorMessage {
                Text(errorMessage)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .listRowBackground(brandMode.raisedBackground)
            }
        }
        .environment(\.editMode, .constant(.inactive))
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .navigationTitle("Create a question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    do {
                        try onAdd(prompt)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(CheckInCustomQuestion.normalizedPrompt(prompt).isEmpty)
                .accessibilityIdentifier("save.questions.customAdd")
            }
        }
        .onAppear { isFocused = true }
    }
}
