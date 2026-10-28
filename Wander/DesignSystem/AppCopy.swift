import Foundation

/// Presentation only. Never apply this to user content, identifiers, or stored values.
enum AppCopy {
    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+(?:['’][\p{L}\p{M}\p{N}_]+)*"#)
    private static let preservedWords: Set<String> = [
        "iOS", "iPhone", "iPad", "iCloud", "iMessage", "macOS", "watchOS", "tvOS", "visionOS",
        "km", "mi", "ft", "m", "h", "d", "min", "mins", "ms", "am", "pm"
    ]

    /// Uppercase each word's initial without lowercasing acronyms or the rest of a brand name.
    static func capitalizingWords(_ copy: String) -> String {
        var result = copy
        let matches = words.matches(in: copy, range: NSRange(copy.startIndex..., in: copy))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let word = String(result[range])
            guard !preservedWords.contains(word), let first = word.first, first.isLetter else { continue }
            result.replaceSubrange(range, with: String(first).uppercased() + word.dropFirst())
        }
        return result
    }
}
