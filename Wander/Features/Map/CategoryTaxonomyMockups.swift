#if DEBUG
import SwiftUI

enum CategoryTaxonomyMockupPage: String, CaseIterable {
    case edit
    case removeSave
    case removeSaveConfirm
    case categories
    case subcategories
    case cuisine
    case cuisineSmart
    case cuisineDirectory
    case cuisineAtlas
    case labels
    case emojiGallery

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> CategoryTaxonomyMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderCategoryTaxonomyMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .edit
        }

        return CategoryTaxonomyMockupPage(rawValue: arguments[valueIndex]) ?? .edit
    }
}

struct CategoryTaxonomyMockupRoot: View {
    let page: CategoryTaxonomyMockupPage

    var body: some View {
        Group {
            switch page {
            case .edit:
                CategoryTaxonomyEditMockup()
            case .removeSave:
                RemoveSaveEditMockup()
            case .removeSaveConfirm:
                RemoveSaveEditMockup(startsWithConfirmation: true)
            case .categories:
                CategoryTaxonomyPrimaryPickerMockup()
            case .subcategories:
                CategoryTaxonomySubcategoryPickerMockup()
            case .cuisine:
                CategoryTaxonomyCuisinePickerMockup()
            case .cuisineSmart:
                CuisineSmartPickerMockup()
            case .cuisineDirectory:
                CuisineDirectoryPickerMockup()
            case .cuisineAtlas:
                CuisineAtlasPickerMockup()
            case .labels:
                CategoryTaxonomyLabelsMockup()
            case .emojiGallery:
                CategoryEmojiGalleryMockup()
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct RemoveSaveEditMockup: View {
    @State private var isShowingRemoveConfirmation: Bool

    init(startsWithConfirmation: Bool = false) {
        _isShowingRemoveConfirmation = State(initialValue: startsWithConfirmation)
    }

    var body: some View {
        CategoryTaxonomyMockupScreen(title: "edit visit", subtitle: "Jitlada - saved by you") {
            placeHeader

            MockupSection(title: "place type") {
                MockupDetailRow(title: "category", value: "Restaurants & Food", category: WanderPlaceCategory.restaurantsFood)
                Divider().background(WanderTheme.borderHairline.color)
                MockupDetailRow(title: "cuisine", value: "Thai", systemImage: "fork.knife.circle.fill")
            }

            MockupSection(title: "save as") {
                HStack(spacing: WanderTheme.spacing2) {
                    MockupChoicePill(title: "been", isSelected: true)
                    MockupChoicePill(title: "wanna go", isSelected: false)
                    Spacer(minLength: 0)
                }
            }

            MockupSection(title: "details saved here") {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    MockupSummaryLine(label: "rating", value: "4.5 - worth bringing friends")
                    Divider().background(WanderTheme.borderHairline.color)
                    MockupSummaryLine(label: "tags", value: "spicy, date-night room, share plates")
                    Divider().background(WanderTheme.borderHairline.color)
                    MockupSummaryLine(label: "my labels", value: "LA favorite, Joe rec")
                }
            }

            MockupSection(title: "note") {
                Text("Order the crispy rice salad. Good for an easy LA dinner when someone wants heat.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionButtons
        }
        .alert("Remove save?", isPresented: $isShowingRemoveConfirmation) {
            Button("Remove save", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Jitlada from your map and deletes your note, rating, tags, labels, and answers. It will not remove the place for anyone else.")
        }
    }

    private var placeHeader: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ZStack {
                Circle().fill(WanderTheme.terracottaTint.color)
                WanderCategoryEmoji(category: WanderPlaceCategory.restaurantsFood, size: 21)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Jitlada")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("5233 Sunset Blvd")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Saved Jun 12 - visible to followers")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }

            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            WanderPrimaryButton(title: "save changes", systemImage: "checkmark") {}
            MockupDestructiveButton(title: "Remove save", systemImage: "trash") {
                isShowingRemoveConfirmation = true
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
        .background {
            WanderTheme.canvasWarm.color
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    WanderTheme.borderHairline.color.frame(height: 1)
                }
        }
    }
}

private struct PrimaryCategoryMock: Identifiable {
    let id: String
    let title: String
    let detail: String
    let color: Color
    let count: Int
}

private enum CategoryTaxonomyMockData {
    static let primaryCategories: [PrimaryCategoryMock] = [
        PrimaryCategoryMock(id: "restaurants_food", title: "Restaurants & Food", detail: "Restaurants, cuisines, quick bites", color: WanderTheme.terracotta.color, count: 132),
        PrimaryCategoryMock(id: "coffee_tea_sweets", title: "Coffee, Tea, & Sweets", detail: "Coffee, tea, bakeries", color: WanderTheme.categorySun.color, count: 25),
        PrimaryCategoryMock(id: "bars_nightlife", title: "Bars & Nightlife", detail: "Bars, lounges, clubs", color: WanderTheme.terracottaDark.color, count: 26),
        PrimaryCategoryMock(id: "outdoors_nature", title: "Outdoors & Nature", detail: "Parks, trails, water", color: WanderTheme.categoryMoss.color, count: 41),
        PrimaryCategoryMock(id: "things_to_do", title: "Things To Do", detail: "Attractions, arts, venues", color: WanderTheme.avatarSofia.color, count: 52),
        PrimaryCategoryMock(id: "shopping", title: "Shopping", detail: "Stores, markets, supplies", color: WanderTheme.terracottaDark.color, count: 46),
        PrimaryCategoryMock(id: "wellness_fitness", title: "Wellness & Fitness", detail: "Health, beauty, fitness", color: WanderTheme.stateSuccess.color, count: 38),
        PrimaryCategoryMock(id: "stays", title: "Stays", detail: "Hotels, rentals, camping", color: WanderTheme.textMuted.color, count: 18),
        PrimaryCategoryMock(id: "services_errands", title: "Services & Errands", detail: "Errands, repairs, pet care", color: WanderTheme.stateInfo.color, count: 48),
        PrimaryCategoryMock(id: "travel_transit", title: "Travel & Transit", detail: "Airports, stations, parking", color: WanderTheme.pinSocial.color, count: 38),
        PrimaryCategoryMock(id: "work_education", title: "Work & Education", detail: "Offices, schools, libraries", color: WanderTheme.avatarAndrew.color, count: 17),
        PrimaryCategoryMock(id: "civic_faith", title: "Civic & Faith", detail: "Government, worship, safety", color: WanderTheme.borderStrong.color, count: 16),
        PrimaryCategoryMock(id: "areas_addresses", title: "Areas & Addresses", detail: "Cities, addresses, regions", color: WanderTheme.stateWarning.color, count: 15),
        PrimaryCategoryMock(id: "facilities_other", title: "Facilities & Other", detail: "Restrooms, facilities, unknown", color: WanderTheme.textFaint.color, count: 7)
    ]

    static let foodDrinkGroups: [(title: String, values: [String])] = [
        (
            "Coffee & tea",
            ["Coffee shop", "Cafe", "Espresso bar", "Coffee roaster", "Tea shop", "Bubble tea shop"]
        ),
        (
            "Restaurants",
            ["Restaurant", "Thai restaurant", "Sushi restaurant", "Ramen restaurant", "Pizza restaurant", "Fast food restaurant", "Taqueria", "Diner", "Food truck", "Fine dining", "Seafood restaurant", "Vegan restaurant", "Breakfast spot"]
        ),
        (
            "Bars & drinks",
            ["Bar", "Cocktail bar", "Wine bar", "Brewery", "Pub", "Sports bar", "Nightlife"]
        ),
        (
            "Bakeries & sweets",
            ["Bakery", "Dessert shop", "Ice cream shop", "Donut shop", "Chocolate shop", "Juice bar"]
        ),
        (
            "Markets & specialty food",
            ["Food market", "Farmers market", "Deli", "Butcher", "Specialty food shop", "Grocery store", "Food hall", "Wine shop"]
        )
    ]

    static let placeTags = [
        "spicy",
        "good for groups",
        "date-night room",
        "walk-in friendly",
        "great patio",
        "late-night",
        "share plates",
        "worth the wait"
    ]

    static let myLabels = [
        "LA favorite",
        "Joe rec",
        "parents in town",
        "birthday list",
        "Silver Lake",
        "show Maya",
        "weekend shortlist",
        "return with Sam"
    ]
}

private struct CategoryTaxonomyEditMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(title: "edit visit", subtitle: "Jitlada - Los Angeles") {
            placeHeader

            MockupSection(title: "place type") {
                MockupDetailRow(title: "category", value: "Restaurants & Food", category: WanderPlaceCategory.restaurantsFood)
                Divider().background(WanderTheme.borderHairline.color)
                MockupDetailRow(title: "cuisine", value: "Thai", systemImage: "fork.knife.circle.fill")
            }

            MockupSection(title: "save as") {
                HStack(spacing: WanderTheme.spacing2) {
                    MockupChoicePill(title: "been", isSelected: true)
                    MockupChoicePill(title: "wanna go", isSelected: false)
                    Spacer(minLength: 0)
                }
            }

            MockupSection(title: "place tags") {
                MockupChipGrid(values: Array(CategoryTaxonomyMockData.placeTags.prefix(6)), selected: ["spicy", "date-night room", "share plates"])
            }

            MockupSection(title: "my labels") {
                MockupChipGrid(values: Array(CategoryTaxonomyMockData.myLabels.prefix(6)), selected: ["LA favorite", "Joe rec"])
            }

            MockupSection(title: "note") {
                Text("Order the crispy rice salad. Good for an easy LA dinner when someone wants heat.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var placeHeader: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ZStack {
                Circle().fill(WanderTheme.terracottaTint.color)
                WanderCategoryEmoji(category: WanderPlaceCategory.restaurantsFood, size: 21)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Jitlada")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("5233 Sunset Blvd")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Thai - Restaurants & Food")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }

            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct CategoryTaxonomyPrimaryPickerMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(title: "choose category", subtitle: "14 primary categories") {
            MockupSearchField(text: "Search primary categories")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: WanderTheme.spacing2), GridItem(.flexible(), spacing: WanderTheme.spacing2)],
                spacing: WanderTheme.spacing2
            ) {
                ForEach(WanderPlaceCategory.editableCategories, id: \.self) { category in
                    PrimaryCategoryPickerTile(category: category, isSelected: category == WanderPlaceCategory.restaurantsFood) {}
                }
            }
        }
    }
}

private struct CategoryTaxonomySubcategoryPickerMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(
            title: "choose subcategory",
            subtitle: "Coffee, Tea, & Sweets - \(WanderPlaceCategory.subcategorySuggestions(for: WanderPlaceCategory.coffeeTeaSweets).count) types"
        ) {
            MockupSearchField(text: "Search coffee, tea, & sweets types")

            HStack(spacing: WanderTheme.spacing2) {
                CategoryPickerModePill(title: "Coffee, Tea, & Sweets", category: WanderPlaceCategory.coffeeTeaSweets, isSelected: true)
                CategoryPickerModePill(title: "change", systemImage: "square.grid.2x2", isSelected: false)
                Spacer(minLength: 0)
            }

            ForEach(WanderPlaceCategory.subcategoryGroups(for: WanderPlaceCategory.coffeeTeaSweets), id: \.title) { group in
                SubcategoryGroupSection(group: group, selectedSubcategory: "Coffee shop") { _ in }
            }
        }
    }
}

private struct CategoryTaxonomyCuisinePickerMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(
            title: "choose cuisine",
            subtitle: "Restaurants & Food - \(WanderPlaceCategory.restaurantCuisineOptions.count) cuisines"
        ) {
            MockupSearchField(text: "Search cuisines")

            HStack(spacing: WanderTheme.spacing2) {
                CategoryPickerModePill(title: "Restaurants & Food", category: WanderPlaceCategory.restaurantsFood, isSelected: true)
                CategoryPickerModePill(title: "change", systemImage: "square.grid.2x2", isSelected: false)
                Spacer(minLength: 0)
            }

            ForEach(WanderPlaceCategory.restaurantCuisineGroups(), id: \.title) { group in
                SubcategoryGroupSection(group: group, selectedSubcategory: "Thai") { _ in }
            }
        }
    }
}

private struct CuisineSmartPickerMockup: View {
    @State private var selectedCuisine = "Thai"

    var body: some View {
        CategoryTaxonomyMockupScreen(
            title: "what kind of food?",
            subtitle: "We’ll start with our best guess. Change it only if we missed."
        ) {
            CuisinePlaceContextCard(
                name: "Jitlada",
                detail: "Thai restaurant · Sunset Blvd",
                cuisine: selectedCuisine
            )

            CuisineSuggestionCard(
                cuisine: "Thai",
                reason: "Suggested from the place type and name",
                isSelected: selectedCuisine == "Thai"
            ) {
                selectedCuisine = "Thai"
            }

            MockupSearchField(text: "Search 126 cuisines")

            MockupSection(title: "quick picks") {
                MockupChipGrid(
                    values: ["Mexican", "Italian", "Japanese", "Chinese", "American", "Mediterranean"],
                    selected: [selectedCuisine]
                )
            }

            MockupSection(title: "more nearby favorites") {
                CuisineChoiceRow(cuisine: "Korean", detail: "Korean BBQ, bibimbap, noodles", selectedCuisine: $selectedCuisine)
                Divider().background(WanderTheme.borderHairline.color)
                CuisineChoiceRow(cuisine: "Vietnamese", detail: "Pho, bánh mì, rice plates", selectedCuisine: $selectedCuisine)
                Divider().background(WanderTheme.borderHairline.color)
                CuisineChoiceRow(cuisine: "Indian", detail: "Regional Indian cooking", selectedCuisine: $selectedCuisine)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CuisineSelectionFooter(cuisine: selectedCuisine)
        }
    }
}

private struct CuisineDirectoryPickerMockup: View {
    @State private var selectedCuisine = "Thai"

    var body: some View {
        CategoryTaxonomyMockupScreen(
            title: "choose cuisine",
            subtitle: "Fast, familiar, and easy to scan."
        ) {
            MockupSearchField(text: "Search cuisines")

            MockupSection(title: "suggested for Jitlada") {
                CuisineChoiceRow(
                    cuisine: "Thai",
                    detail: "Best match · place type + name",
                    selectedCuisine: $selectedCuisine,
                    accent: true
                )
            }

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("recent")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(["Mexican", "Japanese", "Italian", "Mediterranean"], id: \.self) { cuisine in
                            CuisineCompactChoice(
                                cuisine: cuisine,
                                isSelected: selectedCuisine == cuisine
                            ) {
                                selectedCuisine = cuisine
                            }
                        }
                    }
                }
            }

            MockupSection(title: "A") {
                ForEach(Array(["Afghan", "African", "American", "Argentinian", "Asian fusion"].enumerated()), id: \.element) { index, cuisine in
                    if index > 0 {
                        Divider().background(WanderTheme.borderHairline.color)
                    }
                    CuisineChoiceRow(cuisine: cuisine, detail: nil, selectedCuisine: $selectedCuisine)
                }
            }

            MockupSection(title: "B") {
                ForEach(Array(["Bagel", "Bangladeshi", "Barbecue", "Basque", "Belgian", "Bistro", "Brazilian", "British", "Burgers"].enumerated()), id: \.element) { index, cuisine in
                    if index > 0 {
                        Divider().background(WanderTheme.borderHairline.color)
                    }
                    CuisineChoiceRow(cuisine: cuisine, detail: nil, selectedCuisine: $selectedCuisine)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CuisineSelectionFooter(cuisine: selectedCuisine)
        }
    }
}

private struct CuisineAtlasPickerMockup: View {
    @State private var selectedAssignment = WanderPlaceCategory.assignment(
        primaryCategory: WanderPlaceCategory.restaurantsFood,
        subcategory: "Restaurant",
        source: PlaceCategorySource.provider.rawValue,
        confidence: 0.98,
        rawProviderType: "Thai restaurant"
    )
    @State private var selectedCuisine: String? = "Thai"

    var body: some View {
        PlaceTypePickerSheet(
            selectedAssignment: $selectedAssignment,
            selectedCuisine: $selectedCuisine,
            placeName: "Jitlada",
            suggestedCuisine: "Thai",
            suggestionReason: "Suggested from the place type and name",
            recentCuisines: ["Mexican", "Japanese", "Italian", "Mediterranean"],
            initialMode: .cuisine,
            onSelect: {}
        )
    }
}

private struct CuisinePlaceContextCard: View {
    let name: String
    let detail: String
    let cuisine: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ZStack {
                Circle().fill(WanderTheme.terracottaTint.color)
                WanderCategoryEmoji(
                    category: WanderPlaceCategory.restaurantsFood,
                    cuisine: cuisine,
                    name: name,
                    size: 22
                )
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct CuisineSuggestionCard: View {
    let cuisine: String
    let reason: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .fill(WanderTheme.terracotta.color)
                    WanderCategoryEmoji(
                        category: WanderPlaceCategory.restaurantsFood,
                        cuisine: cuisine,
                        size: 26
                    )
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: WanderTheme.spacing1) {
                        Image(systemName: "sparkles")
                        Text("SMART PICK")
                    }
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)

                    Text(cuisine)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Text(reason)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.textFaint.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.terracotta.color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CuisineChoiceRow: View {
    let cuisine: String
    let detail: String?
    @Binding var selectedCuisine: String
    var accent = false

    var body: some View {
        Button {
            selectedCuisine = cuisine
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle().fill(accent ? WanderTheme.terracottaTint.color : WanderTheme.surfaceSand.color)
                    WanderCategoryEmoji(
                        category: WanderPlaceCategory.restaurantsFood,
                        cuisine: cuisine,
                        size: 17
                    )
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cuisine)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: selectedCuisine == cuisine ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(
                        selectedCuisine == cuisine
                            ? WanderTheme.terracotta.color
                            : WanderTheme.borderStrong.color
                    )
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CuisineCompactChoice: View {
    let cuisine: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                WanderCategoryEmoji(
                    category: WanderPlaceCategory.restaurantsFood,
                    cuisine: cuisine,
                    size: 15
                )
                Text(cuisine)
            }
            .font(.system(size: 13, weight: .black))
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 44)
            .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceBone.color)
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
    }
}

private struct CuisineAtlasTile: View {
    let cuisine: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack {
                    ZStack {
                        Circle().fill(WanderTheme.terracottaTint.color)
                        WanderCategoryEmoji(
                            category: WanderPlaceCategory.restaurantsFood,
                            cuisine: cuisine,
                            size: 21
                        )
                    }
                    .frame(width: 44, height: 44)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }

                Text(cuisine)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(isSelected ? WanderTheme.terracottaTint.color : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CuisineSelectionFooter: View {
    let cuisine: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CUISINE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text(cuisine)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
            }

            Spacer(minLength: 0)

            Text("done")
                .font(.system(size: 16, weight: .black))
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: 48)
                .background(WanderTheme.terracotta.color)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .clipShape(Capsule())
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing3)
        .background {
            WanderTheme.canvasWarm.color
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    WanderTheme.borderHairline.color.frame(height: 1)
                }
        }
    }
}

private struct CategoryTaxonomyLabelsMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(title: "tags and labels", subtitle: "distinct defaults for Jitlada") {
            placeHeader

            MockupSection(title: "place tags") {
                MockupChipGrid(values: CategoryTaxonomyMockData.placeTags, selected: ["spicy", "good for groups", "date-night room"])
            }

            MockupSection(title: "my labels") {
                MockupChipGrid(values: CategoryTaxonomyMockData.myLabels, selected: ["LA favorite", "Joe rec", "birthday list"])
            }

            MockupSection(title: "saved summary") {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    MockupSummaryLine(label: "category", value: "Restaurants & Food")
                    MockupSummaryLine(label: "cuisine", value: "Thai")
                    MockupSummaryLine(label: "tags", value: "spicy, good for groups, date-night room")
                    MockupSummaryLine(label: "my labels", value: "LA favorite, Joe rec, birthday list")
                }
            }
        }
    }

    private var placeHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text("Jitlada")
                    .font(.system(size: 24, weight: .black))
                Spacer()
                Text("been")
                    .font(.system(size: 12, weight: .black))
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minHeight: 28)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
            Text("Thai - Los Angeles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct CategoryEmojiGalleryItem: Identifiable {
    let id: String
    let name: String
    let category: String
    let subcategory: String?
    let cuisine: String?

    init(
        _ name: String,
        category: String,
        subcategory: String? = nil,
        cuisine: String? = nil
    ) {
        id = "\(name)-\(subcategory ?? cuisine ?? category)"
        self.name = name
        self.category = category
        self.subcategory = subcategory
        self.cuisine = cuisine
    }
}

private struct CategoryEmojiGalleryMockup: View {
    private let healthAndBeauty = [
        CategoryEmojiGalleryItem("Saint John's Hospital", category: WanderPlaceCategory.wellnessFitness, subcategory: "Hospital"),
        CategoryEmojiGalleryItem("Santa Monica Eye Care", category: WanderPlaceCategory.wellnessFitness, subcategory: "Optometrist"),
        CategoryEmojiGalleryItem("Ocean Park Dental", category: WanderPlaceCategory.wellnessFitness, subcategory: "Dentist"),
        CategoryEmojiGalleryItem("Main Street Pharmacy", category: WanderPlaceCategory.wellnessFitness, subcategory: "Pharmacy"),
        CategoryEmojiGalleryItem("Gloss Nail Salon", category: WanderPlaceCategory.wellnessFitness, subcategory: "Nail salon"),
        CategoryEmojiGalleryItem("Proper Hair", category: WanderPlaceCategory.wellnessFitness, subcategory: "Hair salon"),
        CategoryEmojiGalleryItem("Iron Fitness", category: WanderPlaceCategory.wellnessFitness, subcategory: "Gym"),
        CategoryEmojiGalleryItem("Love Yoga", category: WanderPlaceCategory.wellnessFitness, subcategory: "Yoga studio")
    ]

    private let coffeeAndFood = [
        CategoryEmojiGalleryItem("Wild Leaven Bakery", category: WanderPlaceCategory.coffeeTeaSweets, subcategory: "Bakery"),
        CategoryEmojiGalleryItem("One Cedar Coffee", category: WanderPlaceCategory.coffeeTeaSweets, subcategory: "Coffee shop"),
        CategoryEmojiGalleryItem("Chado Tea Room", category: WanderPlaceCategory.coffeeTeaSweets, subcategory: "Tea house"),
        CategoryEmojiGalleryItem("Jitlada", category: WanderPlaceCategory.restaurantsFood, subcategory: "Restaurant", cuisine: "Thai"),
        CategoryEmojiGalleryItem("Marugame Udon", category: WanderPlaceCategory.restaurantsFood, subcategory: "Noodle restaurant", cuisine: "Japanese"),
        CategoryEmojiGalleryItem("Guelaguetza", category: WanderPlaceCategory.restaurantsFood, subcategory: "Restaurant", cuisine: "Mexican")
    ]

    var body: some View {
        CategoryTaxonomyMockupScreen(
            title: "place icons",
            subtitle: "Production category, subtype, and cuisine resolver"
        ) {
            gallerySection(title: "health, beauty, and fitness", items: healthAndBeauty)
            gallerySection(title: "coffee, sweets, and cuisines", items: coffeeAndFood)
        }
    }

    private func gallerySection(
        title: String,
        items: [CategoryEmojiGalleryItem]
    ) -> some View {
        MockupSection(title: title) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().background(WanderTheme.borderHairline.color)
                }

                HStack(spacing: WanderTheme.spacing3) {
                    ZStack {
                        Circle().fill(WanderTheme.terracottaTint.color)
                        WanderCategoryEmoji(
                            category: item.category,
                            subcategory: item.subcategory,
                            cuisine: item.cuisine,
                            name: item.name,
                            size: 20
                        )
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.cuisine ?? item.subcategory ?? item.category)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    Spacer(minLength: 0)
                }
                .frame(minHeight: 50)
            }
        }
    }
}

private struct CategoryTaxonomyMockupScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                header
                content
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(subtitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MockupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }
}

private struct MockupDetailRow: View {
    let title: String
    let value: String
    let systemImage: String?
    let category: String?

    init(title: String, value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        category = nil
    }

    init(title: String, value: String, category: String) {
        self.title = title
        self.value = value
        systemImage = nil
        self.category = category
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Group {
                if let category {
                    WanderCategoryEmoji(category: category, size: 16)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
            .frame(width: 28, height: 28)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer(minLength: WanderTheme.spacing2)
            Text(value)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
        .frame(minHeight: 46)
    }
}

private struct MockupChoicePill: View {
    let title: String
    let isSelected: Bool
    var systemImage: String?

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .black))
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 40)
        .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
        .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
    }
}

private struct MockupDestructiveButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WanderTheme.stateError.color)
            .foregroundStyle(WanderTheme.textOnAction.color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MockupChipGrid: View {
    let values: [String]
    let selected: Set<String>

    init(values: [String], selected: [String] = []) {
        self.values = values
        self.selected = Set(selected)
    }

    var body: some View {
        FlowLayout(spacing: WanderTheme.spacing2) {
            ForEach(values, id: \.self) { value in
                MockupChip(title: value, isSelected: selected.contains(value))
            }
        }
    }
}

private struct MockupChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 34)
            .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color.opacity(0.75)))
    }
}

private struct PrimaryCategoryTile: View {
    let category: PrimaryCategoryMock
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                ZStack {
                    Circle().fill(category.color.opacity(0.16))
                    WanderCategoryEmoji(category: category.id, size: 16)
                }
                .frame(width: 36, height: 36)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
            }

            Text(category.title)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 34, alignment: .topLeading)

            Text(category.detail)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(height: 30, alignment: .topLeading)

            Text(
                "\(category.count) \(category.id == WanderPlaceCategory.restaurantsFood ? "cuisines" : "types")"
            )
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
        }
        .padding(WanderTheme.spacing3)
        .frame(minHeight: 148, alignment: .topLeading)
        .background(isSelected ? WanderTheme.surfaceRaised.color : WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color, lineWidth: isSelected ? 2 : 1)
        )
    }
}

private struct MockupSearchField: View {
    let text: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
            Text(text)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 56)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
    }
}

private struct MockupSummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(CGFloat.zero, +) + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [CGFloat] {
        var rows: [CGFloat] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentWidth == 0 ? size.width : currentWidth + spacing + size.width
            if currentWidth > 0, proposedWidth > width {
                rows.append(currentHeight)
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if currentWidth > 0 {
            rows.append(currentHeight)
        }

        return rows
    }
}
#endif
