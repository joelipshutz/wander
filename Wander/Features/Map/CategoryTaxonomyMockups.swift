#if DEBUG
import SwiftUI

enum CategoryTaxonomyMockupPage: String, CaseIterable {
    case edit
    case categories
    case subcategories
    case labels

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
            case .categories:
                CategoryTaxonomyPrimaryPickerMockup()
            case .subcategories:
                CategoryTaxonomySubcategoryPickerMockup()
            case .labels:
                CategoryTaxonomyLabelsMockup()
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct PrimaryCategoryMock: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let count: Int
}

private enum CategoryTaxonomyMockData {
    static let primaryCategories: [PrimaryCategoryMock] = [
        PrimaryCategoryMock(id: "food_drink", title: "Food & drink", detail: "Restaurants, coffee, bars", symbol: "fork.knife", color: WanderTheme.terracotta.color, count: 40),
        PrimaryCategoryMock(id: "outdoors", title: "Outdoors & nature", detail: "Parks, trails, water", symbol: "tree.fill", color: WanderTheme.categoryMoss.color, count: 32),
        PrimaryCategoryMock(id: "arts", title: "Arts, culture & faith", detail: "Museums, temples, galleries", symbol: "sparkles", color: WanderTheme.avatarSofia.color, count: 30),
        PrimaryCategoryMock(id: "entertainment", title: "Entertainment", detail: "Venues, movies, games", symbol: "ticket.fill", color: WanderTheme.categorySun.color, count: 24),
        PrimaryCategoryMock(id: "health", title: "Health & wellness", detail: "Care, spas, pharmacies", symbol: "cross.case.fill", color: WanderTheme.stateSuccess.color, count: 26),
        PrimaryCategoryMock(id: "fitness", title: "Sports & fitness", detail: "Gyms, courts, studios", symbol: "dumbbell.fill", color: WanderTheme.categorySage.color, count: 28),
        PrimaryCategoryMock(id: "shopping", title: "Shopping", detail: "Stores, markets, supplies", symbol: "bag.fill", color: WanderTheme.terracottaDark.color, count: 36),
        PrimaryCategoryMock(id: "services", title: "Services", detail: "Salons, repairs, pet care", symbol: "scissors", color: WanderTheme.stateInfo.color, count: 34),
        PrimaryCategoryMock(id: "lodging", title: "Lodging", detail: "Hotels, resorts, stays", symbol: "bed.double.fill", color: WanderTheme.textMuted.color, count: 14),
        PrimaryCategoryMock(id: "transportation", title: "Transportation & transit", detail: "Airports, stations, parking", symbol: "tram.fill", color: WanderTheme.pinSocial.color, count: 22),
        PrimaryCategoryMock(id: "education", title: "Education", detail: "Schools, libraries, classes", symbol: "graduationcap.fill", color: WanderTheme.avatarAndrew.color, count: 16),
        PrimaryCategoryMock(id: "work", title: "Work & venues", detail: "Offices, coworking, events", symbol: "building.2.fill", color: WanderTheme.textInk.color, count: 18),
        PrimaryCategoryMock(id: "home", title: "Home & neighborhood", detail: "Apartments, landmarks, blocks", symbol: "house.fill", color: WanderTheme.stateWarning.color, count: 20),
        PrimaryCategoryMock(id: "public", title: "Public services", detail: "Civic, safety, government", symbol: "building.columns.fill", color: WanderTheme.borderStrong.color, count: 18)
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
        CategoryTaxonomyMockupScreen(title: "edit this place", subtitle: "Jitlada - Los Angeles") {
            placeHeader

            MockupSection(title: "place type") {
                MockupDetailRow(title: "category", value: "Food & drink", systemImage: "square.grid.2x2.fill")
                Divider().background(WanderTheme.borderHairline.color)
                MockupDetailRow(title: "subcategory", value: "Thai restaurant", systemImage: "line.3.horizontal.decrease.circle.fill")
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
                Image(systemName: "fork.knife")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Jitlada")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("5233 Sunset Blvd")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Food & drink - Thai restaurant")
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
                    PrimaryCategoryPickerTile(category: category, isSelected: category == WanderPlaceCategory.foodDrink) {}
                }
            }
        }
    }
}

private struct CategoryTaxonomySubcategoryPickerMockup: View {
    var body: some View {
        CategoryTaxonomyMockupScreen(title: "choose subcategory", subtitle: "Food & drink - 40 types") {
            MockupSearchField(text: "Search food & drink types")

            HStack(spacing: WanderTheme.spacing2) {
                CategoryPickerModePill(title: "Food & drink", systemImage: "fork.knife", isSelected: true)
                CategoryPickerModePill(title: "change", systemImage: "square.grid.2x2", isSelected: false)
                Spacer(minLength: 0)
            }

            ForEach(WanderPlaceCategory.subcategoryGroups(for: WanderPlaceCategory.foodDrink), id: \.title) { group in
                SubcategoryGroupSection(group: group, selectedSubcategory: "Thai restaurant") { _ in }
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
                    MockupSummaryLine(label: "type", value: "Food & drink / Thai restaurant")
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
            Text("Food & drink - Thai restaurant - Los Angeles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
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
    let systemImage: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .frame(width: 28, height: 28)
                .foregroundStyle(WanderTheme.terracotta.color)
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
                    Image(systemName: category.symbol)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(category.color)
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

            Text("\(category.count) types")
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
