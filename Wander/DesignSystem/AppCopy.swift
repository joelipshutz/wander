import Foundation

/// Presentation only. Never apply this to user content, identifiers, or stored values.
enum AppCopy {
    /// Capitalize a standalone label's initial, preserving every subsequent character.
    /// Complete sentences are authored with their intended punctuation and casing.
    static func capitalizingInitial(_ copy: String) -> String {
        guard let index = copy.firstIndex(where: { $0.isLetter || $0.isNumber }),
              copy[index].isLetter else { return copy }
        // Brand casing is intentional even at the beginning of a label.
        let suffix = copy[index...]
        let brands = ["iOS", "iPhone", "iPad", "iCloud", "iMessage", "macOS", "watchOS", "tvOS", "visionOS"]
        if brands.contains(where: { suffix == $0 || suffix.hasPrefix($0 + " ") }) { return copy }
        var result = copy
        result.replaceSubrange(index...index, with: String(copy[index]).uppercased())
        return result
    }
}
