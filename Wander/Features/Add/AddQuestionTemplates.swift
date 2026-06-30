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
        let normalizedCategory = WanderPlaceCategory.questionCategory(for: category)
        var blocks: [AddQuestionBlock] = []

        if status == .wannaGo {
            blocks.append(interestBlock())
            blocks.append(contentsOf: wannaGoBlocks(category: normalizedCategory))
            return blocks
        }

        switch normalizedCategory {
        case "coffee":
            blocks.append(contentsOf: coffeeBlocks)
        case "hike":
            blocks.append(contentsOf: hikeBlocks)
        case "restaurant":
            blocks.append(contentsOf: restaurantBlocks)
        case "bar":
            blocks.append(contentsOf: barBlocks)
        case "park":
            blocks.append(contentsOf: parkBlocks)
        default:
            blocks.append(contentsOf: defaultBlocks(category: normalizedCategory))
        }

        return blocks
    }

    private static func wannaGoBlocks(category: String) -> [AddQuestionBlock] {
        switch category {
        case "coffee":
            return [
                AddQuestionBlock(
                    key: "coffee_tags",
                    title: "why save it?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["work maybe", "cute", "food maybe", "nearby", "recommended"],
                    defaultValues: [],
                    minimumOptionWidth: 108
                )
            ]
        case "hike":
            return [
                AddQuestionBlock(
                    key: "hike_tags",
                    title: "why save it?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["sunset", "views", "easy maybe", "dog friendly", "recommended"],
                    defaultValues: [],
                    minimumOptionWidth: 112
                )
            ]
        case "restaurant":
            return [
                AddQuestionBlock(
                    key: "occasion",
                    title: "planning for?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["quick bite", "date night", "group", "rainy night"],
                    defaultValues: [],
                    minimumOptionWidth: 104
                ),
                AddQuestionBlock(
                    key: "restaurant_tags",
                    title: "why save it?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["looks cozy", "good table", "share plates", "recommended"],
                    defaultValues: [],
                    minimumOptionWidth: 112
                )
            ]
        case "bar":
            return [
                AddQuestionBlock(
                    key: "occasion",
                    title: "planning for?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["first drink", "date", "group", "late"],
                    defaultValues: [],
                    minimumOptionWidth: 98
                ),
                AddQuestionBlock(
                    key: "bar_tags",
                    title: "why save it?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["patio", "good music", "not too loud", "walk-in"],
                    defaultValues: [],
                    minimumOptionWidth: 104
                )
            ]
        case "park":
            return [
                AddQuestionBlock(
                    key: "best_for",
                    title: "planning for?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["walk", "picnic", "views", "reset"],
                    defaultValues: [],
                    minimumOptionWidth: 84
                )
            ]
        default:
            let keyPrefix = normalizedKeyPrefix(for: category)

            return [
                AddQuestionBlock(
                    key: "\(keyPrefix)_tags",
                    title: "why save it?",
                    tag: "multi",
                    kind: .multiTag,
                    valueType: "multi_tag",
                    options: ["looks useful", "easy maybe", "cozy", "bring friends"],
                    defaultValues: [],
                    minimumOptionWidth: 112
                )
            ]
        }
    }

    private static func interestBlock() -> AddQuestionBlock {
        AddQuestionBlock(
            key: "interest_signal",
            title: "how excited are you?",
            tag: "scale",
            kind: .singleChoice,
            valueType: "emoji_scale",
            options: ["curious", "excited", "must go"],
            defaultValues: ["excited"],
            minimumOptionWidth: 88
        )
    }

    private static let coffeeBlocks = [
        AddQuestionBlock(
            key: "work_setup",
            title: "good for working?",
            tag: "yes/no",
            kind: .singleChoice,
            valueType: "single_choice",
            options: ["yes", "sometimes", "nope"],
            defaultValues: ["yes"],
            minimumOptionWidth: 96
        ),
        AddQuestionBlock(
            key: "coffee_tags",
            title: "tags",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["wifi solid", "outlets", "quiet", "cute", "food on point"],
            defaultValues: ["wifi solid", "quiet"],
            minimumOptionWidth: 102
        )
    ]

    private static let hikeBlocks = [
        AddQuestionBlock(
            key: "strenuousness",
            title: "how strenuous?",
            tag: "scale",
            kind: .singleChoice,
            valueType: "single_choice",
            options: ["easy", "moderate", "hard"],
            defaultValues: ["easy"],
            minimumOptionWidth: 94
        ),
        AddQuestionBlock(
            key: "hike_tags",
            title: "tags",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["sunset", "views", "shade", "dog friendly", "crowded"],
            defaultValues: ["sunset", "views"],
            minimumOptionWidth: 98
        )
    ]

    private static let restaurantBlocks = [
        AddQuestionBlock(
            key: "price",
            title: "price feel?",
            tag: "price",
            kind: .singleChoice,
            valueType: "price_scale",
            options: ["$", "$$", "$$$"],
            defaultValues: ["$$"],
            minimumOptionWidth: 64
        ),
        AddQuestionBlock(
            key: "occasion",
            title: "best for?",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["quick bite", "date night", "group", "rainy night"],
            defaultValues: ["date night", "rainy night"],
            minimumOptionWidth: 104
        ),
        AddQuestionBlock(
            key: "restaurant_tags",
            title: "tags",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["cozy", "good table", "share plates", "worth it"],
            defaultValues: ["cozy", "worth it"],
            minimumOptionWidth: 104
        )
    ]

    private static let barBlocks = [
        AddQuestionBlock(
            key: "occasion",
            title: "best for?",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["first drink", "date", "group", "late"],
            defaultValues: ["first drink", "date"],
            minimumOptionWidth: 98
        ),
        AddQuestionBlock(
            key: "bar_tags",
            title: "tags",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["patio", "good music", "not too loud", "walk-in"],
            defaultValues: ["patio"],
            minimumOptionWidth: 104
        )
    ]

    private static let parkBlocks = [
        AddQuestionBlock(
            key: "best_for",
            title: "best for?",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["walk", "picnic", "views", "reset"],
            defaultValues: ["walk", "reset"],
            minimumOptionWidth: 84
        ),
        AddQuestionBlock(
            key: "park_tags",
            title: "tags",
            tag: "multi",
            kind: .multiTag,
            valueType: "multi_tag",
            options: ["shade", "sunny", "quiet", "dog friendly"],
            defaultValues: ["quiet"],
            minimumOptionWidth: 96
        )
    ]

    private static func defaultBlocks(category: String) -> [AddQuestionBlock] {
        let keyPrefix = normalizedKeyPrefix(for: category)

        return [
            AddQuestionBlock(
                key: "\(keyPrefix)_tags",
                title: "tags",
                tag: "multi",
                kind: .multiTag,
                valueType: "multi_tag",
                options: ["worth it", "easy", "cozy", "bring friends"],
                defaultValues: ["worth it"],
                minimumOptionWidth: 104
            )
        ]
    }

    private static func normalizedKeyPrefix(for category: String) -> String {
        let normalized = category
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")

        return normalized.isEmpty ? "place" : normalized
    }
}
