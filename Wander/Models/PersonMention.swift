import Foundation

/// Offsets use UTF-16, matching native text input and NSAttributedString.
/// A picker selection or an unambiguous exact name followed by Space creates a mention.
struct PersonMention: Codable, Equatable, Hashable {
    let userID: String
    let handle: String
    let name: String
    var location: Int
    let length: Int

    var range: NSRange { NSRange(location: location, length: length) }
    var nameRange: NSRange { NSRange(location: location + 1, length: max(0, length - 1)) }
    var text: String { "@\(name)" }

    func isValid(in text: String) -> Bool {
        guard location >= 0, length > 0, location <= text.utf16.count,
              length <= text.utf16.count - location,
              let range = Range(range, in: text) else { return false }
        return text[range] == self.text
    }
}

struct PersonMentionQuery: Equatable {
    let range: NSRange
    let text: String
}

struct PersonMentionCompletionRequest {
    private(set) var prefix: String
    private(set) var query: PersonMentionQuery

    init?(draft: PersonMentionDraft, selection: NSRange) {
        guard let active = draft.query(at: selection), active.text.last == " ",
              let previous = active.text.dropLast().last, !previous.isWhitespace,
              let cursor = Range(selection, in: draft.text)?.lowerBound else { return nil }
        prefix = String(draft.text[..<cursor])
        query = PersonMentionQuery(range: NSRange(location: active.range.location, length: active.range.length - 1),
                                   text: String(active.text.dropLast()))
    }

    mutating func rebase(replacing range: NSRange, with replacement: String) -> Bool {
        if NSMaxRange(range) <= query.range.location {
            guard let swiftRange = Range(range, in: prefix) else { return false }
            prefix.replaceSubrange(swiftRange, with: replacement)
            query = PersonMentionQuery(range: NSRange(location: query.range.location + replacement.utf16.count - range.length,
                                                      length: query.range.length), text: query.text)
            return true
        }
        return range.location >= NSMaxRange(query.range)
    }
}

struct PersonMentionDraft: Equatable {
    var text: String
    var mentions: [PersonMention] = []

    var searchText: String {
        var resolved = text
        for mention in mentions.filter({ $0.isValid(in: text) }).sorted(by: { $0.location > $1.location }) {
            guard let range = Range(mention.range, in: resolved) else { continue }
            resolved.replaceSubrange(range, with: "@\(mention.handle)")
        }
        return resolved
    }

    func query(at selection: NSRange) -> PersonMentionQuery? {
        guard selection.length == 0, selection.location >= 0, selection.location <= text.utf16.count,
              let cursor = Range(selection, in: text)?.lowerBound else { return nil }
        let prefix = text[..<cursor]
        guard let at = prefix.lastIndex(of: "@") else { return nil }
        if at != text.startIndex {
            let previous = text[text.index(before: at)]
            guard previous.isWhitespace || "([{\"'".contains(previous) else { return nil }
        }
        let range = NSRange(at..<cursor, in: text)
        guard !mentions.contains(where: {
            $0.isValid(in: text) && NSIntersectionRange($0.range, range).length > 0
        }) else { return nil }
        let query = String(text[text.index(after: at)..<cursor])
        guard query.count <= 80, !query.contains(where: { $0.isNewline }),
              query.allSatisfy({ $0.isLetter || $0.isNumber || " _-.'’".contains($0) })
        else { return nil }
        return PersonMentionQuery(range: range, text: query)
    }

    mutating func replace(_ range: NSRange, with replacement: String) {
        guard let swiftRange = Range(range, in: text) else { return }
        let delta = replacement.utf16.count - range.length
        mentions = mentions.compactMap { mention in
            guard mention.isValid(in: text) else { return nil }
            // An insertion inside a selected name invalidates its identity too.
            if NSIntersectionRange(mention.range, range).length > 0
                || (range.length == 0 && range.location > mention.location
                    && range.location < NSMaxRange(mention.range)) { return nil }
            var updated = mention
            if range.location <= mention.location { updated.location += delta }
            return updated
        }
        text.replaceSubrange(swiftRange, with: replacement)
    }

    mutating func reconcile(_ updatedText: String) {
        guard updatedText != text else { return }
        let prefix = text.commonPrefix(with: updatedText)
        let oldTail = text.dropFirst(prefix.count)
        let newTail = updatedText.dropFirst(prefix.count)
        let suffixCount = zip(oldTail.reversed(), newTail.reversed()).prefix { $0 == $1 }.count
        let oldEnd = text.index(text.endIndex, offsetBy: -suffixCount)
        let newEnd = updatedText.index(updatedText.endIndex, offsetBy: -suffixCount)
        let oldStart = text.index(text.startIndex, offsetBy: prefix.count)
        let newStart = updatedText.index(updatedText.startIndex, offsetBy: prefix.count)
        replace(NSRange(oldStart..<oldEnd, in: text), with: String(updatedText[newStart..<newEnd]))
    }

    /// Apply a space-boundary lookup only while its original text is intact.
    /// Later typing is preserved and its caret moves with the replacement.
    @discardableResult
    mutating func complete(_ request: PersonMentionCompletionRequest, person: ProfileShell, at selection: NSRange) -> NSRange? {
        guard text.hasPrefix(request.prefix),
              NSIntersectionRange(selection, request.query.range).length == 0,
              !(selection.location > request.query.range.location && selection.location < NSMaxRange(request.query.range)),
              !mentions.contains(where: { $0.isValid(in: text) && NSIntersectionRange($0.range, request.query.range).length > 0 })
        else { return nil }
        let previousLength = text.utf16.count
        guard select(person, for: request.query) != nil else { return nil }
        let offset = selection.location >= NSMaxRange(request.query.range) ? text.utf16.count - previousLength : 0
        return NSRange(location: selection.location + offset, length: selection.length)
    }

    @discardableResult
    mutating func select(_ person: ProfileShell, for query: PersonMentionQuery) -> NSRange? {
        guard let range = Range(query.range, in: text), text[range] == "@\(query.text)" else { return nil }
        let name = PersonMentionCandidates.name(for: person)
        let token = "@\(name)"
        let suffix = text[range.upperBound...]
        let separator = suffix.isEmpty ? " " : ""
        replace(query.range, with: token + separator)
        mentions.append(PersonMention(userID: person.id, handle: person.handle, name: name,
                                      location: query.range.location, length: token.utf16.count))
        mentions.sort { $0.location < $1.location }
        return NSRange(location: query.range.location + token.utf16.count + separator.utf16.count, length: 0)
    }
}

enum PersonMentionCandidates {
    static func exactMatch(_ profiles: [ProfileShell], query: String) -> ProfileShell? {
        let value = normalized(query)
        guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let matches = matching(profiles, query: query).filter {
            normalized(name(for: $0)) == value || normalized($0.handle).trimmingCharacters(in: CharacterSet(charactersIn: "@")) == value
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func name(for profile: ProfileShell) -> String {
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? profile.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")) : name
    }

    static func matching(_ profiles: [ProfileShell], query: String) -> [ProfileShell] {
        let query = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        var ordered: [ProfileShell] = []
        var indices: [String: Int] = [:]
        for profile in profiles {
            if let index = indices[profile.id] {
                let previous = ordered[index]
                // Keep ranking position while using the freshest available name.
                let hasName = !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ordered[index] = ProfileShell(
                    id: profile.id, handle: profile.handle,
                    displayName: hasName ? profile.displayName : previous.displayName,
                    avatarURL: profile.avatarURL ?? previous.avatarURL, bio: profile.bio ?? previous.bio,
                    homeArea: profile.homeArea ?? previous.homeArea,
                    isPrivateProfile: profile.isPrivateProfile ?? previous.isPrivateProfile,
                    createdAt: profile.createdAt ?? previous.createdAt, relationship: previous.relationship
                )
            } else {
                indices[profile.id] = ordered.count
                ordered.append(profile)
            }
        }
        return ordered.filter { profile in
            guard !query.isEmpty else { return true }
            let name = normalized(profile.displayName)
            let handle = normalized(profile.handle).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            return handle.hasPrefix(query) || name.hasPrefix(query)
                || name.split(whereSeparator: \.isWhitespace).contains { $0.hasPrefix(query) }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
