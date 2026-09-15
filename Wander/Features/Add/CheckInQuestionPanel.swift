import SwiftUI

/// Shared by new and edited check-ins. Public catalog answers and local private
/// answers intentionally use separate bindings; this view never serializes a save.
struct CheckInQuestionPanel: View {
    let ownerUserID: String
    let subtypeKey: String
    let subtypeTitle: String
    let defaultQuestions: [PlaceCheckInQuestion]
    @Binding var answers: [String: Set<String>]
    @Binding var customAnswers: [String: String]

    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var configuration: CheckInQuestionConfiguration
    @State private var loadedScope = ""
    @State private var customDefinitions: [CheckInCustomQuestion] = []
    @State private var showsCustomization = false
    private let preferenceStore: CheckInQuestionPreferenceStore

    init(
        ownerUserID: String,
        subtypeKey: String,
        subtypeTitle: String,
        defaultQuestions: [PlaceCheckInQuestion],
        answers: Binding<[String: Set<String>]>,
        customAnswers: Binding<[String: String]>,
        preferenceStore: CheckInQuestionPreferenceStore = CheckInQuestionPreferenceStore()
    ) {
        self.ownerUserID = ownerUserID
        self.subtypeKey = subtypeKey
        self.subtypeTitle = subtypeTitle
        self.defaultQuestions = defaultQuestions
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

            Text("Optional. Answer only what you know.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)

            if preferredQuestions.isEmpty {
                Text("No recurring questions for this place type. Add any you want in Customize.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
            }

            ForEach(preferredQuestions) { question in
                answerRow(question)
            }

            if !additionalQuestions.isEmpty {
                DisclosureGroup {
                    ForEach(additionalQuestions) { question in
                        answerRow(question)
                    }
                } label: {
                    Text("Also noted (\(additionalQuestions.count))")
                        .font(AstirTypography.control)
                        .frame(minHeight: WanderTheme.tapMinimum)
                }
                .tint(brandMode.accentText)
                .accessibilityIdentifier("save.questions.alsoNoted")
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
                preferenceStore: preferenceStore
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
        Text("A few useful details")
            .font(AstirTypography.sectionTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var customizeButton: some View {
        Button("Customize") { showsCustomization = true }
            .font(AstirTypography.control)
            .foregroundStyle(brandMode.accentText)
            .frame(minHeight: WanderTheme.tapMinimum)
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
        return (catalogIDs + privateIDs)
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
                isPrivate: false
            )
        }
        guard loadedScope == scopeIdentity,
              let question = customDefinitions.first(where: { $0.id == id })
                ?? configuration.customQuestions.first(where: { $0.id == id })
        else { return nil }
        return CheckInPresentedQuestion(id: question.id, prompt: question.prompt, options: ["Yes", "No"], isPrivate: true)
    }

    private func selectedValues(for question: CheckInPresentedQuestion) -> Set<String> {
        if question.isPrivate {
            switch customAnswers[question.id] {
            case "yes": return ["Yes"]
            case "no": return ["No"]
            default: return []
            }
        }
        return answers[question.id] ?? []
    }

    private func answerRow(_ question: CheckInPresentedQuestion) -> some View {
        CheckInQuestionAnswerRow(
            question: question,
            selectedValues: selectedValues(for: question),
            onSelect: { option in
                if question.isPrivate {
                    customAnswers[question.id] = CheckInQuestionAnswerPolicy.togglingPrivate(
                        option == "Yes" ? "yes" : "no",
                        current: customAnswers[question.id]
                    )
                } else {
                    answers[question.id] = CheckInQuestionAnswerPolicy.toggling(
                        option,
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
                    Label("Only you · On this device", systemImage: "lock")
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
            rows = store.allCustomQuestions(ownerUserID: ownerUserID).compactMap { question in
                guard let value = answers[question.id], value == "yes" || value == "no" else { return nil }
                return PrivateAnswerRow(id: question.id, prompt: question.prompt, answer: value == "yes" ? "Yes" : "No")
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

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : min(3, max(1, displayOptions.count))
        return Array(repeating: GridItem(.flexible(), spacing: WanderTheme.spacing2), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Divider().overlay(brandMode.border)
            Text(question.prompt)
                .font(AstirTypography.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WanderTheme.spacing2)

            if question.isPrivate {
                Label("Only you · On this device", systemImage: "lock")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: WanderTheme.spacing2) {
                ForEach(displayOptions, id: \.self) { option in
                    let selected = selectedValues.contains(option)
                    Button {
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

            if !selectedValues.isEmpty {
                Button("Clear answer", action: onClear)
                    .font(AstirTypography.label)
                    .foregroundStyle(brandMode.accentText)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .accessibilityLabel("Clear answer to \(question.prompt)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("save.question.row.\(question.id)")
    }
}

private struct CheckInQuestionCustomizationSheet: View {
    let ownerUserID: String
    let subtypeKey: String
    let subtypeTitle: String
    let defaultQuestions: [PlaceCheckInQuestion]
    let preferenceStore: CheckInQuestionPreferenceStore
    let onConfigurationChange: (CheckInQuestionConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @State private var configuration: CheckInQuestionConfiguration
    @State private var errorMessage: String?

    init(
        ownerUserID: String,
        subtypeKey: String,
        subtypeTitle: String,
        defaultQuestions: [PlaceCheckInQuestion],
        configuration: CheckInQuestionConfiguration,
        preferenceStore: CheckInQuestionPreferenceStore,
        onConfigurationChange: @escaping (CheckInQuestionConfiguration) -> Void
    ) {
        self.ownerUserID = ownerUserID
        self.subtypeKey = subtypeKey
        self.subtypeTitle = subtypeTitle
        self.defaultQuestions = defaultQuestions
        self.preferenceStore = preferenceStore
        self.onConfigurationChange = onConfigurationChange
        _configuration = State(initialValue: configuration)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(configuration.orderedQuestionIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                            Text(prompt(for: id))
                                .font(AstirTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                            if CheckInCustomQuestion.isCustomID(id) {
                                Text("Only you · On this device")
                                    .font(AstirTypography.caption)
                                    .foregroundStyle(brandMode.secondaryText)
                            }
                        }
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .listRowBackground(brandMode.raisedBackground)
                        .accessibilityElement(children: .combine)
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
                    NavigationLink {
                        CheckInAddCatalogQuestionScreen(
                            selectedIDs: Set(configuration.orderedQuestionIDs),
                            onAdd: { id in
                                var updated = configuration
                                updated.addCatalogQuestion(id: id)
                                try persist(updated)
                            }
                        )
                    } label: {
                        Label("Add a question", systemImage: "plus")
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .accessibilityIdentifier("save.questions.addCatalog")
                    NavigationLink {
                        CheckInCreateCustomQuestionScreen { prompt in
                            var updated = configuration
                            try updated.addCustomQuestion(prompt: prompt)
                            try persist(updated)
                        }
                    } label: {
                        Label("Create your own", systemImage: "square.and.pencil")
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .accessibilityIdentifier("save.questions.createCustom")
                } footer: {
                    Text("Your questions and order are saved for this account on this device. Custom questions have Yes/No answers and stay private.")
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
    @State private var errorMessage: String?

    private var matches: [PlaceCheckInQuestion] {
        PlaceCheckInQuestionCatalog.allQuestions.filter {
            search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.prompt.localizedCaseInsensitiveContains(search)
        }.sorted { $0.prompt.localizedStandardCompare($1.prompt) == .orderedAscending }
    }

    var body: some View {
        List {
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
        .searchable(text: $search, prompt: "Find a question")
        .environment(\.editMode, .constant(.inactive))
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .navigationTitle("Add a question")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Ask something you can answer with Yes or No. Only you can see your question and answers, on this device.")
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
