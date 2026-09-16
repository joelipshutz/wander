import SwiftUI

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
    @State private var showsCustomization = false
    @State private var showsAdditionalQuestions = false
    private let preferenceStore: CheckInQuestionPreferenceStore

    init(
        ownerUserID: String,
        subtypeKey: String,
        subtypeTitle: String,
        defaultQuestions: [PlaceCheckInQuestion],
        savedCustomQuestions: [CheckInCustomQuestion] = [],
        answers: Binding<[String: Set<String>]>,
        customAnswers: Binding<[String: String]>,
        preferenceStore: CheckInQuestionPreferenceStore = CheckInQuestionPreferenceStore()
    ) {
        self.ownerUserID = ownerUserID
        self.subtypeKey = subtypeKey
        self.subtypeTitle = subtypeTitle
        self.defaultQuestions = defaultQuestions
        self.savedCustomQuestions = savedCustomQuestions
        _answers = answers
        _customAnswers = customAnswers
        self.preferenceStore = preferenceStore
        _configuration = State(initialValue: CheckInQuestionConfiguration(
            orderedQuestionIDs: defaultQuestions.map(\.id)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            header

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
        .sheet(isPresented: $showsCustomization) {
            CheckInQuestionCustomizationSheet(
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
                customDefinitions = preferenceStore.allCustomQuestions(ownerUserID: ownerUserID)
            }
        }
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
        Text("Useful details")
            .font(AstirTypography.control)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var customizeButton: some View {
        Button { showsCustomization = true } label: {
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
        currentConfiguration.orderedQuestionIDs.compactMap(presentedQuestion)
    }

    private var additionalQuestions: [CheckInPresentedQuestion] {
        let preferred = Set(currentConfiguration.orderedQuestionIDs)
        let catalogIDs = answers.keys.filter { !(answers[$0] ?? []).isEmpty }
        let privateIDs = loadedScope == scopeIdentity ? Array(customAnswers.keys) : []
        return Set(catalogIDs + privateIDs)
            .filter { !preferred.contains($0) }
            .sorted()
            .compactMap(presentedQuestion)
    }

    private func presentedQuestion(_ id: String) -> CheckInPresentedQuestion? {
        if let question = defaultQuestions.first(where: { $0.id == id })
            ?? PlaceCheckInQuestionCatalog.question(id: id) {
            return CheckInPresentedQuestion(
                id: question.id,
                prompt: question.prompt,
                options: question.options,
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
            values = [value]
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
            onSelect: { option in
                let value = CheckInCustomQuestion.isCustomID(question.id) ? option.lowercased() : option
                if question.isPrivate {
                    customAnswers[question.id] = customAnswers[question.id] == value ? nil : value
                } else {
                    answers[question.id] = CheckInQuestionAnswerPolicy.toggling(
                        value,
                        selected: answers[question.id] ?? []
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
            if let value = answers[questionID]?.sorted().first {
                customAnswers[questionID] = value
                // Explicit empty is needed to clear a previously shared value.
                answers[questionID] = []
            }
        } else if let value = customAnswers.removeValue(forKey: questionID) {
            answers[questionID] = [value]
        }
    }

    private func loadConfiguration() {
        configuration = preferenceStore.configuration(
            ownerUserID: ownerUserID,
            subtypeKey: subtypeKey,
            defaultQuestionIDs: defaultQuestions.map(\.id)
        )
        customDefinitions = preferenceStore.allCustomQuestions(ownerUserID: ownerUserID)
        loadedScope = scopeIdentity
        showsCustomization = false
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
                if let question = PlaceCheckInQuestionCatalog.question(id: id), question.options.contains(value) {
                    return PrivateAnswerRow(id: id, prompt: question.prompt, answer: value)
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
            Text(question.prompt)
                .font(AstirTypography.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("save.question.row.\(question.id)")

            if question.isPrivate {
                Label("Stealth", systemImage: "eye.slash")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
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

            if !selectedValues.isEmpty {
                Button("Clear answer", action: onClear)
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .accessibilityLabel("Clear answer to \(question.prompt)")
            }
        }
        .accessibilityElement(children: .contain)
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
    @State private var editingQuestionID: String?

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(configuration.orderedQuestionIDs, id: \.self) { id in
                        Button { editingQuestionID = id } label: {
                            HStack(spacing: WanderTheme.spacing2) {
                                Text(prompt(for: id))
                                    .font(AstirTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: WanderTheme.spacing1)
                                Image(systemName: displayedStealth(questionID: id) ? "eye.slash" : "ellipsis")
                                    .foregroundStyle(brandMode.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: WanderTheme.tapMinimum)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(brandMode.raisedBackground)
                        .accessibilityLabel(prompt(for: id))
                        .accessibilityValue(displayedStealth(questionID: id) ? "Stealth" : "Check-in audience")
                        .accessibilityHint("Change this question’s Stealth setting")
                        .accessibilityIdentifier("save.questions.recurring.\(id)")
                    }
                    .onMove { offsets, destination in
                        update { $0.moveQuestions(from: offsets, to: destination) }
                    }
                    .onDelete { offsets in update { $0.removeQuestions(at: offsets) } }
                } header: {
                    Text("For \(subtypeTitle)")
                } footer: {
                    Text("Drag to reorder. Removing a question changes future prompts and keeps previous answers.")
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
                    Button("Restore suggested questions") {
                        update { $0.restoreSuggestedQuestions(defaultQuestions.map(\.id)) }
                    }
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
                CheckInAddCatalogQuestionScreen(selectedIDs: Set(configuration.orderedQuestionIDs)) { id, stealth in
                    var updated = configuration
                    updated.addCatalogQuestion(id: id, stealth: stealth)
                    try persist(updated)
                    onStealthChange?(id, stealth)
                }
            }
            .navigationDestination(isPresented: $showsCustomEditor) {
                CheckInCreateCustomQuestionScreen { prompt, stealth in
                    var updated = configuration
                    let question = try updated.addCustomQuestion(prompt: prompt, stealth: stealth)
                    try persist(updated)
                    onStealthChange?(question.id, stealth)
                }
            }
            .navigationDestination(item: $editingQuestionID) { id in
                CheckInQuestionStealthScreen(prompt: prompt(for: id), stealth: displayedStealth(questionID: id)) { stealth in
                    var updated = configuration
                    updated.setStealth(stealth, questionID: id)
                    try persist(updated)
                    onStealthChange?(id, stealth)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("save.questions.done")
                }
            }
        }
        .tint(brandMode.accentText)
    }

    private func prompt(for id: String) -> String {
        PlaceCheckInQuestionCatalog.question(id: id)?.prompt
            ?? configuration.customQuestions.first(where: { $0.id == id })?.prompt
            ?? "Saved question"
    }

    private func displayedStealth(questionID: String) -> Bool {
        answerStealthOverrides[questionID] ?? configuration.isStealth(questionID: questionID)
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
    let onAdd: (String, Bool) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @State private var errorMessage: String?
    @State private var stealth = false

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

            Section {
                CheckInQuestionStealthToggle(isOn: $stealth, accessibilityIdentifier: "save.questions.catalogStealth")
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
                        try onAdd(question.id, stealth)
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
    let onAdd: (String, Bool) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var prompt = ""
    @State private var errorMessage: String?
    @State private var stealth = true
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
            Section {
                CheckInQuestionStealthToggle(isOn: $stealth, accessibilityIdentifier: "save.questions.customStealth")
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
                        try onAdd(prompt, stealth)
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

private struct CheckInQuestionStealthToggle: View {
    @Binding var isOn: Bool
    let accessibilityIdentifier: String
    @Environment(\.astirBrandMode) private var brandMode

    private var privacyDescription: String {
        isOn ? "Only you see this question and your answer." : "Shared with your check-in’s audience."
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                HStack(spacing: WanderTheme.spacing3) {
                    Text("Stealth")
                    Spacer(minLength: 0)
                    Label(isOn ? "On" : "Off", systemImage: isOn ? "eye.slash.fill" : "eye")
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.vertical, WanderTheme.spacing1)
                        .background(isOn ? brandMode.accentWash : brandMode.background)
                        .clipShape(Capsule())
                }
                .font(AstirTypography.control)
                Text(privacyDescription)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(brandMode.primaryText)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .tint(brandMode.accent)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("Stealth. \(privacyDescription)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(isOn ? "Turn Stealth off" : "Turn Stealth on")
    }
}

private struct CheckInQuestionStealthScreen: View {
    let prompt: String
    let onChange: (Bool) throws -> Void
    @State private var stealth: Bool
    @State private var errorMessage: String?
    @Environment(\.astirBrandMode) private var brandMode

    init(prompt: String, stealth: Bool, onChange: @escaping (Bool) throws -> Void) {
        self.prompt = prompt
        self.onChange = onChange
        _stealth = State(initialValue: stealth)
    }

    var body: some View {
        Form {
            Section {
                Text(prompt)
                    .font(AstirTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                CheckInQuestionStealthToggle(isOn: Binding(
                    get: { stealth },
                    set: { value in
                        do {
                            try onChange(value)
                            stealth = value
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                ), accessibilityIdentifier: "save.questions.selectedStealth")
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
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
    }
}
