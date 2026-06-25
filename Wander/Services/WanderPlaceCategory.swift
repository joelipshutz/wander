import MapKit

struct PlaceCategoryDisplay: Equatable {
    let rawCategory: String
    let category: String
    let subcategory: String?
    let sourceLabel: String

    var compactTitle: String {
        var parts: [String] = []
        if let subcategory, !subcategory.isEmpty {
            parts.append(subcategory)
        }
        if !category.isEmpty {
            parts.append(category)
        }
        return parts.joined(separator: " · ")
    }
}

enum PlaceMemoryAttributeKeys {
    static let personalLabels = "personal_labels"
}

enum PlacePersonalLabelSuggestions {
    static func options(category: String, status: PlaceStatus) -> [String] {
        let normalized = WanderPlaceCategory.questionCategory(for: category)

        if status == .wannaGo {
            switch normalized {
            case "coffee":
                return ["work maybe", "cute", "nearby", "recommended", "solo"]
            case "hike":
                return ["sunset", "views", "weekend", "dog friendly", "recommended"]
            case "restaurant":
                return ["date night", "group", "spicy", "recommended", "rainy night"]
            case "bar":
                return ["date", "group", "late", "patio", "recommended"]
            case "park":
                return ["walk", "picnic", "reset", "views", "dog friendly"]
            default:
                return ["worth checking", "recommended", "nearby", "bring friends"]
            }
        }

        switch normalized {
        case "coffee":
            return ["work-friendly", "quiet", "cute", "outlets", "solo"]
        case "hike":
            return ["sunset", "views", "shade", "dog friendly", "bring water"]
        case "restaurant":
            return ["date night", "group", "spicy", "cozy", "worth it"]
        case "bar":
            return ["patio", "good music", "not too loud", "late", "date"]
        case "park":
            return ["walk", "picnic", "quiet", "dog friendly", "reset"]
        default:
            return ["worth it", "easy", "cozy", "bring friends"]
        }
    }
}

enum WanderPlaceCategory {
    static let editableCategories = [
        "coffee",
        "restaurant",
        "bar",
        "hike",
        "park",
        "gym",
        "fitness studio",
        "pilates studio",
        "spiritual",
        "hospital",
        "pharmacy",
        "veterinarian",
        "hotel",
        "shop",
        "transportation",
        "place"
    ]

    static func primary(for pointCategory: MKPointOfInterestCategory?, name: String? = nil) -> String? {
        if let nameCategory = primaryFromName(name, pointCategory: pointCategory) {
            return nameCategory
        }

        if #available(iOS 18.0, *) {
            switch pointCategory {
            case .animalService:
                return "veterinarian"
            case .hiking:
                return "hike"
            case .rockClimbing, .skatePark, .skating, .skiing, .surfing, .swimming:
                return "fitness studio"
            default:
                break
            }
        }

        switch pointCategory {
        case .cafe, .bakery:
            return "coffee"
        case .restaurant, .foodMarket:
            return "restaurant"
        case .brewery, .winery, .nightlife:
            return "bar"
        case .park, .nationalPark:
            return "park"
        case .hospital:
            return "hospital"
        case .fitnessCenter:
            return "gym"
        default:
            return nil
        }
    }

    static func display(for category: String, sourceLabel: String = "suggested") -> PlaceCategoryDisplay {
        let normalizedCategory = normalizedCategory(category)
        let canonicalCategory = questionCategory(for: normalizedCategory)
        let subcategory: String?

        if normalizedCategory == "place" {
            subcategory = nil
        } else if normalizedCategory == canonicalCategory {
            subcategory = defaultSubcategory(for: canonicalCategory) ?? sentenceTitleized(normalizedCategory)
        } else {
            subcategory = sentenceTitleized(normalizedCategory)
        }

        return PlaceCategoryDisplay(
            rawCategory: normalizedCategory,
            category: broadCategory(for: canonicalCategory),
            subcategory: subcategory,
            sourceLabel: sourceLabel
        )
    }

    static func questionCategory(for category: String) -> String {
        let normalized = normalizedCategory(category)

        switch normalized {
        case "coffee", "coffee shop", "cafe", "bakery":
            return "coffee"
        case "restaurant", "thai restaurant", "fast food restaurant", "food", "food market":
            return "restaurant"
        case "bar", "brewery", "winery", "nightlife":
            return "bar"
        case "hike", "trail", "waterfall", "hot spring":
            return "hike"
        case "park", "national park":
            return "park"
        case "gym":
            return "gym"
        case "fitness studio", "yoga studio":
            return "fitness studio"
        case "pilates studio":
            return "pilates studio"
        case "spiritual", "church", "temple", "shrine":
            return "spiritual"
        case "hospital", "urgent care":
            return "hospital"
        case "pharmacy":
            return "pharmacy"
        case "veterinarian", "veterinary clinic", "animal hospital":
            return "veterinarian"
        case "hotel", "motel", "resort":
            return "hotel"
        case "shop", "store", "art supply store":
            return "shop"
        case "transportation", "transit", "transit station", "airport", "train station", "bus station":
            return "transportation"
        default:
            let padded = " \(normalized) "
            if containsAny(padded, [" restaurant ", " taqueria ", " ramen ", " sushi ", " pizza ", " diner "]) {
                return "restaurant"
            }
            if containsAny(padded, [" coffee ", " cafe ", " bakery "]) {
                return "coffee"
            }
            if containsAny(padded, [" bar ", " brewery ", " winery ", " cocktail "]) {
                return "bar"
            }
            if containsAny(padded, [" hike ", " trail ", " waterfall ", " hot spring "]) {
                return "hike"
            }
            if containsAny(padded, [" park "]) {
                return "park"
            }
            if containsAny(padded, [" gym "]) {
                return "gym"
            }
            if containsAny(padded, [" pilates ", " reformer "]) {
                return "pilates studio"
            }
            if containsAny(padded, [" fitness ", " yoga ", " barre ", " wellness studio "]) {
                return "fitness studio"
            }
            if containsAny(padded, [" church ", " temple ", " shrine ", " mosque ", " synagogue "]) {
                return "spiritual"
            }
            if containsAny(padded, [" hospital ", " urgent care ", " medical center "]) {
                return "hospital"
            }
            if containsAny(padded, [" pharmacy "]) {
                return "pharmacy"
            }
            if containsAny(padded, [" veterinarian ", " veterinary ", " animal hospital "]) {
                return "veterinarian"
            }
            if containsAny(padded, [" hotel ", " motel ", " resort "]) {
                return "hotel"
            }
            if containsAny(padded, [" airport ", " transit ", " station ", " train ", " bus ", " ferry ", " subway "]) {
                return "transportation"
            }
            if containsAny(padded, [" shop ", " store ", " mall ", " boutique "]) {
                return "shop"
            }
            return normalized
        }
    }

    static func symbolName(for category: String) -> String {
        switch questionCategory(for: category) {
        case "coffee":
            "cup.and.saucer.fill"
        case "hike":
            "figure.hiking"
        case "restaurant":
            "fork.knife"
        case "bar":
            "wineglass.fill"
        case "park":
            "tree.fill"
        case "hospital":
            "cross.case.fill"
        case "gym":
            "dumbbell.fill"
        case "fitness studio":
            "figure.strengthtraining.traditional"
        case "pilates studio":
            "figure.mind.and.body"
        case "spiritual":
            "sparkles"
        case "veterinarian":
            "pawprint.fill"
        case "pharmacy":
            "pills.fill"
        case "hotel":
            "bed.double.fill"
        case "shop":
            "bag.fill"
        case "transportation":
            "tram.fill"
        default:
            "mappin"
        }
    }

    private static func broadCategory(for category: String) -> String {
        switch category {
        case "coffee", "restaurant", "bar":
            "Food & drink"
        case "hike", "park":
            "Outdoors & nature"
        case "gym", "fitness studio", "pilates studio", "hospital", "pharmacy":
            "Health & wellness"
        case "spiritual":
            "Arts, culture & faith"
        case "veterinarian":
            "Services"
        case "hotel":
            "Lodging"
        case "shop":
            "Shopping"
        case "transportation":
            "Transportation & transit"
        default:
            "Place"
        }
    }

    private static func defaultSubcategory(for category: String) -> String? {
        switch category {
        case "coffee":
            "Coffee shop"
        case "restaurant":
            "Restaurant"
        case "bar":
            "Bar"
        case "hike":
            "Hike or trail"
        case "park":
            "Park"
        case "gym":
            "Gym"
        case "fitness studio":
            "Fitness studio"
        case "pilates studio":
            "Pilates studio"
        case "spiritual":
            "Spiritual place"
        case "hospital":
            "Hospital"
        case "pharmacy":
            "Pharmacy"
        case "veterinarian":
            "Veterinarian"
        case "hotel":
            "Hotel"
        case "shop":
            "Shop"
        case "transportation":
            "Transit stop"
        default:
            nil
        }
    }

    private static func primaryFromName(_ name: String?, pointCategory: MKPointOfInterestCategory?) -> String? {
        guard let normalizedName = normalized(name), !normalizedName.isEmpty else { return nil }

        if containsAny(normalizedName, ["veterinary", "veterinarian", " vet ", "animal hospital", "pet hospital", "pet clinic", "dog dental", "cat clinic"]) {
            return "veterinarian"
        }

        if containsAny(normalizedName, ["temple", "shrine", "meditation", "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue"]) {
            return "spiritual"
        }

        if containsAny(normalizedName, ["hospital", "medical center", "health center", "urgent care"]) {
            return "hospital"
        }

        if containsAny(normalizedName, ["pilates", "plankhaus", "lagree", "reformer"]) {
            return "pilates studio"
        }

        let isFitnessCategory = pointCategory == .fitnessCenter
        if isFitnessCategory, containsAny(normalizedName, ["studio", "barre", "yoga", "stretch"]) {
            return "fitness studio"
        }

        if containsAny(normalizedName, [" gym ", "fitness", "training", "strength", "workout"]) {
            return "gym"
        }

        return nil
    }

    private static func containsAny(_ normalizedName: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            normalizedName.contains(needle.lowercased())
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = " "
            + value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            + " "
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : normalized
    }

    private static func normalizedCategory(_ category: String) -> String {
        let normalized = category
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? "place" : normalized
    }

    private static func sentenceTitleized(_ value: String) -> String {
        let lowercased = value.lowercased()
        guard let first = lowercased.first else { return lowercased }
        return first.uppercased() + String(lowercased.dropFirst())
    }
}
