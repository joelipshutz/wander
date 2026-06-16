import MapKit

enum WanderPlaceCategory {
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

    static func symbolName(for category: String) -> String {
        switch category {
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
        case "veterinarian":
            "pawprint.fill"
        case "pharmacy":
            "pills.fill"
        default:
            "mappin"
        }
    }

    private static func primaryFromName(_ name: String?, pointCategory: MKPointOfInterestCategory?) -> String? {
        guard let normalizedName = normalized(name), !normalizedName.isEmpty else { return nil }

        if containsAny(normalizedName, ["veterinary", "veterinarian", " vet ", "animal hospital", "pet hospital", "pet clinic", "dog dental", "cat clinic"]) {
            return "veterinarian"
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
}
