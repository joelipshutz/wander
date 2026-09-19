import Foundation

struct PlaceMemoryTagOption: Identifiable, Equatable {
    let id: String
    let title: String
    /// Keep original spellings and values until the person explicitly clears
    /// this chip. Presentation grouping never rewrites persisted labels.
    let selectedValues: Set<String>
    var isSelected: Bool { !selectedValues.isEmpty }
}

enum PlaceMemoryTagPresentation {
    static let maximumSuggestions = 8

    /// Deliberately small, reviewed synonym groups. No fuzzy matching, stemming,
    /// substring matching, or provider-category normalization of personal text.
    private static let aliasGroups: [[String]] = [
        ["morning stop", "morning spot", "morning routine", "morning loop", "morning list"],
        ["date night", "date-night", "date idea", "date shortlist"],
        ["weekend plan", "weekend list", "weekend maybe"],
        ["work session", "work rotation", "work spot", "work maybe", "work shortlist"],
        ["gift idea", "gift list", "giftable"],
        ["bring visitors", "visitor idea", "visitor list", "visitor context"],
        ["try soon", "try next", "try next time"],
        ["regular spot", "go-to", "go to", "neighborhood standby", "neighborhood staple", "weekly routine", "regular care", "regular service", "regular routine", "daily routine"],
        ["meet here", "meeting spot", "meetup spot", "meetup idea"],
        ["stay again", "book again"],
        ["errand stop", "errand loop", "quick errand", "errand idea"],
        ["backup option", "backup plan"],
        ["drinks with friends", "group drinks", "group shortlist"],
        ["dinner with friends", "group dinner", "group dinner idea"],
        ["night out", "night-out list", "night-out shortlist"],
        ["sweet treat", "treat stop", "treat list", "dessert list", "dessert shortlist", "weekend treat"],
        ["commute", "daily commute"]
    ]

    private static let aliases: [String: String] = {
        var result: [String: String] = [:]
        for group in aliasGroups {
            guard let first = group.first else { continue }
            for value in group { result[normalizedKey(value)] = normalizedKey(first) }
        }
        return result
    }()

    static func displayTitle(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizedKey(_ value: String) -> String {
        displayTitle(value).lowercased()
    }

    static func equivalenceKey(_ value: String) -> String {
        let key = normalizedKey(value)
        return aliases[key] ?? key
    }

    static func suggestions(_ values: [String], limit: Int = maximumSuggestions) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let title = displayTitle(value)
            guard !title.isEmpty, seen.insert(equivalenceKey(title)).inserted else { return nil }
            return title
        }.prefix(max(0, limit)).map { $0 }
    }

    static func options(suggestions: [String], selected: Set<String>) -> [PlaceMemoryTagOption] {
        let selectedGroups = Dictionary(grouping: selected.filter { !displayTitle($0).isEmpty }, by: equivalenceKey)
        var seen = Set<String>()
        var options: [PlaceMemoryTagOption] = []

        for title in self.suggestions(suggestions) {
            let key = equivalenceKey(title)
            let originals = Set(selectedGroups[key] ?? [])
            let selectedTitle = originals.sorted().first.map(displayTitle)
            options.append(PlaceMemoryTagOption(id: key, title: selectedTitle ?? title, selectedValues: originals))
            seen.insert(key)
        }

        // A smaller suggestion set must never hide selected custom/legacy tags.
        for key in selectedGroups.keys.sorted() where !seen.contains(key) {
            let originals = Set(selectedGroups[key] ?? [])
            guard let first = originals.sorted().first else { continue }
            options.append(PlaceMemoryTagOption(id: key, title: displayTitle(first), selectedValues: originals))
        }
        return options
    }

    static func toggling(_ value: String, selected: Set<String>) -> Set<String> {
        let key = equivalenceKey(value)
        guard !key.isEmpty else { return selected }
        let matching = selected.filter { equivalenceKey($0) == key }
        if !matching.isEmpty { return selected.subtracting(matching) }
        return selected.union([displayTitle(value)])
    }
}
