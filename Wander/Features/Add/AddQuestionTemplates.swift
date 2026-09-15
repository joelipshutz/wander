import CoreGraphics
import Foundation

enum AddQuestionKind: Equatable {
    case singleChoice
    case multiTag
}

struct AddQuestionBlock: Identifiable, Equatable {
    let key: String
    let title: String
    let tag: String
    let kind: AddQuestionKind
    let valueType: String
    let options: [String]
    let defaultValues: [String]
    var minimumOptionWidth: CGFloat = 82

    var id: String { key }
}

enum AddQuestionTemplates {
    static func blocks(category: String, status: PlaceStatus) -> [AddQuestionBlock] {
        let assignment = WanderPlaceCategory.assignment(forRawCategory: category)
        return blocks(
            primaryCategory: assignment.primaryCategory,
            subcategory: assignment.subcategory,
            cuisine: WanderPlaceCategory.cuisineGuess(forRawValue: category),
            status: status
        )
    }

    static func blocks(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        localTagOptions: [String] = []
    ) -> [AddQuestionBlock] {
        let primary = WanderPlaceCategory.normalizedPrimaryCategory(primaryCategory)
        let assignment = PlaceCategoryAssignment(primaryCategory: primary, subcategory: subcategory)
        let normalizedCategory = WanderPlaceCategory.questionCategory(for: assignment)
        let suggestions = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: primary,
            subcategory: subcategory,
            cuisine: cuisine,
            status: status,
            localTagOptions: localTagOptions
        )
        let keyPrefix: String
        switch normalizedCategory {
        case "coffee", "hike", "restaurant", "bar", "park": keyPrefix = normalizedCategory
        default: keyPrefix = primary.replacingOccurrences(of: " ", with: "_")
        }
        let tags = AddQuestionBlock(
            key: "\(keyPrefix)_tags",
            title: "Tags",
            tag: "optional",
            kind: .multiTag,
            valueType: "multi_tag",
            options: suggestions.unifiedTagOptions,
            defaultValues: [],
            minimumOptionWidth: 104
        )
        guard status == .been else { return [tags] }
        return PlaceCheckInQuestionCatalog.questions(categoryID: primary, subcategory: subcategory).map {
            AddQuestionBlock(
                key: $0.id,
                title: $0.prompt,
                tag: "optional",
                kind: .singleChoice,
                valueType: $0.valueType,
                options: $0.options,
                defaultValues: []
            )
        } + [tags]
    }
}
