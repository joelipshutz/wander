import SwiftUI

/// Manage the same subtype preferences used by the composer without opening or
/// changing a place. Only an explicit composer action transfers a draft answer.
struct CheckInQuestionSettingsScreen: View {
    let ownerUserID: String
    @Environment(\.astirBrandMode) private var brandMode
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @State private var scopes: [CheckInQuestionSettingsScope] = []
    @State private var selectedScope: CheckInQuestionSettingsScope?
    private let preferenceStore = CheckInQuestionPreferenceStore()

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var categoryIDs: [String] {
        let ordinary = WanderPlaceCategory.editableCategories
        return ordinary + Set(scopes.map(\.categoryID)).subtracting(ordinary).sorted()
    }

    private var matchingScopes: [CheckInQuestionSettingsScope] {
        scopes.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.categoryTitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                CheckInQuestionSearchField(
                    placeholder: "Find a category or place type",
                    text: $search,
                    isFocused: $isSearchFocused,
                    accessibilityIdentifier: "questions.settings.search"
                )
            }
            .listRowBackground(brandMode.raisedBackground)

            if query.isEmpty {
                Section {
                    Text("Choose the questions you see for each place type.")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .listRowBackground(brandMode.background)
                }
                ForEach(categoryIDs, id: \.self) { category in
                    NavigationLink {
                        CheckInQuestionTypeSettingsScreen(
                            ownerUserID: ownerUserID,
                            categoryTitle: WanderPlaceCategory.broadCategory(for: category),
                            scopes: scopes.filter { $0.categoryID == category }
                        )
                    } label: {
                        Text(WanderPlaceCategory.broadCategory(for: category))
                            .font(AstirTypography.body)
                            .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .accessibilityIdentifier("questions.settings.category.\(category)")
                    .listRowBackground(brandMode.raisedBackground)
                }
            } else if matchingScopes.isEmpty {
                Text("No matching place types. Try a category or a more general name.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .listRowBackground(brandMode.raisedBackground)
            } else {
                ForEach(categoryIDs, id: \.self) { category in
                    let matches = matchingScopes.filter { $0.categoryID == category }
                    if !matches.isEmpty {
                        Section(WanderPlaceCategory.broadCategory(for: category)) {
                            ForEach(matches) { scope in
                                scopeButton(scope)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .tint(brandMode.accentText)
        .navigationTitle("Check-in questions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("questions.settings.screen")
        .onDisappear { isSearchFocused = false }
        .onChange(of: ownerUserID, initial: true) { _, _ in
            isSearchFocused = false
            selectedScope = nil
            reloadScopes()
        }
        .onReceive(NotificationCenter.default.publisher(for: CheckInQuestionPreferenceStore.didChangeNotification)) { _ in reloadScopes() }
        .sheet(item: $selectedScope) { scope in
            CheckInQuestionSettingsScopeEditor(ownerUserID: ownerUserID, scope: scope)
        }
    }

    private func scopeButton(_ scope: CheckInQuestionSettingsScope) -> some View {
        Button {
            isSearchFocused = false
            selectedScope = scope
        } label: {
            Text(scope.title)
                .font(AstirTypography.body)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        }
        .accessibilityIdentifier("questions.settings.scope.\(scope.id)")
        .listRowBackground(brandMode.raisedBackground)
    }

    private func reloadScopes() {
        let savedKeys = preferenceStore.configuredSubtypeKeys(ownerUserID: ownerUserID)
        var categories = WanderPlaceCategory.editableCategories
        if savedKeys.contains(where: { $0.hasPrefix(WanderPlaceCategory.fallbackPlace + ":") }) {
            categories.append(WanderPlaceCategory.fallbackPlace)
        }
        scopes = categories.flatMap { category in
            let defaultTitle = PlaceCheckInQuestionCatalog.subtypeDisplayTitle(categoryID: category, subcategory: nil)
            let curated = PlaceCheckInQuestionCatalog.profiles.filter { $0.categoryID == category }.flatMap(\.subcategories)
            let saved = savedKeys.filter { $0.hasPrefix(category + ":") }.map { String($0.dropFirst(category.count + 1)) }
            var seen = Set<String>()
            return ([defaultTitle] + curated + saved).compactMap { title -> CheckInQuestionSettingsScope? in
                let scope = CheckInQuestionSettingsScope(categoryID: category, title: title)
                return seen.insert(scope.id).inserted ? scope : nil
            }.sorted {
                if ($0.title == defaultTitle) != ($1.title == defaultTitle) { return $0.title == defaultTitle }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}

private struct CheckInQuestionSettingsScope: Identifiable {
    let categoryID: String
    let title: String
    var id: String { PlaceCheckInQuestionCatalog.preferenceKey(categoryID: categoryID, subcategory: title) }
    var categoryTitle: String { WanderPlaceCategory.broadCategory(for: categoryID) }
    var defaultQuestions: [PlaceCheckInQuestion] { PlaceCheckInQuestionCatalog.questions(categoryID: categoryID, subcategory: title) }
}

private struct CheckInQuestionTypeSettingsScreen: View {
    let ownerUserID: String
    let categoryTitle: String
    let scopes: [CheckInQuestionSettingsScope]
    @Environment(\.astirBrandMode) private var brandMode
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedScope: CheckInQuestionSettingsScope?

    private var matches: [CheckInQuestionSettingsScope] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? scopes : scopes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                CheckInQuestionSearchField(
                    placeholder: "Find a place type",
                    text: $search,
                    isFocused: $isSearchFocused,
                    accessibilityIdentifier: "questions.settings.typeSearch"
                )
            }
            .listRowBackground(brandMode.raisedBackground)

            if matches.isEmpty {
                Text("No matching place types.")
                    .foregroundStyle(brandMode.secondaryText)
                    .listRowBackground(brandMode.raisedBackground)
            }
            ForEach(matches) { scope in
                Button {
                    isSearchFocused = false
                    selectedScope = scope
                } label: {
                    Text(scope.title)
                        .font(AstirTypography.body)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                }
                .accessibilityIdentifier("questions.settings.scope.\(scope.id)")
                .listRowBackground(brandMode.raisedBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(brandMode.background)
        .foregroundStyle(brandMode.primaryText)
        .tint(brandMode.accentText)
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { isSearchFocused = false }
        .sheet(item: $selectedScope) { scope in
            CheckInQuestionSettingsScopeEditor(ownerUserID: ownerUserID, scope: scope)
        }
    }
}

private struct CheckInQuestionSettingsScopeEditor: View {
    let ownerUserID: String
    let scope: CheckInQuestionSettingsScope
    private let preferenceStore = CheckInQuestionPreferenceStore()

    var body: some View {
        CheckInQuestionCustomizationSheet(
            ownerUserID: ownerUserID,
            subtypeKey: scope.id,
            subtypeTitle: scope.title,
            defaultQuestions: scope.defaultQuestions,
            configuration: preferenceStore.configuration(
                ownerUserID: ownerUserID, subtypeKey: scope.id, defaultQuestionIDs: scope.defaultQuestions.map(\.id)
            ),
            preferenceStore: preferenceStore,
            onConfigurationChange: { _ in }
        )
    }
}
