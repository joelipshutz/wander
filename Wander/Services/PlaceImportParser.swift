import Foundation
import UniformTypeIdentifiers
import UIKit

enum PlaceImportParsingError: Error, Equatable, LocalizedError {
    case emptyInput
    case noPlacesFound
    case unreadableFile
    case compressedTakeoutNeedsUnzip
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Add at least one link or place before importing."
        case .noPlacesFound:
            "No place entries were found. Try one place or link per line."
        case .unreadableFile:
            "This file could not be read. Try exporting it again."
        case .compressedTakeoutNeedsUnzip:
            "Unzip the Google Takeout archive in Files, then choose its Saved Places CSV or JSON file."
        case .unsupportedFile:
            "Choose a CSV, JSON, TXT, Markdown, or RTF file."
        }
    }
}

struct PlaceImportFileContents: Equatable {
    let text: String
    let fileName: String
}

enum PlaceImportFileReader {
    static func read(_ url: URL) throws -> PlaceImportFileContents {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "zip" {
            throw PlaceImportParsingError.compressedTakeoutNeedsUnzip
        }

        guard let data = try? Data(contentsOf: url) else {
            throw PlaceImportParsingError.unreadableFile
        }

        if fileExtension == "rtf" {
            guard let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else {
                throw PlaceImportParsingError.unreadableFile
            }
            return PlaceImportFileContents(text: attributed.string, fileName: fileName)
        }

        guard ["csv", "json", "txt", "md", "markdown"].contains(fileExtension) else {
            throw PlaceImportParsingError.unsupportedFile
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else {
            throw PlaceImportParsingError.unreadableFile
        }
        return PlaceImportFileContents(text: text, fileName: fileName)
    }
}

enum PlaceImportParser {
    static func parse(
        source: PlaceImportSource,
        text: String,
        fileName: String? = nil
    ) throws -> [PlaceImportSeed] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlaceImportParsingError.emptyInput
        }

        let fileExtension = fileName.flatMap { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        let parsed: [PlaceImportSeed]
        if fileExtension == "json" || looksLikeJSON(trimmed) {
            parsed = jsonSeeds(from: trimmed)
        } else if fileExtension == "csv" || looksLikeCSV(trimmed) {
            parsed = csvSeeds(from: trimmed)
        } else {
            parsed = lineSeeds(from: trimmed)
        }

        let deduped = deduplicate(parsed)
        guard !deduped.isEmpty else {
            throw PlaceImportParsingError.noPlacesFound
        }

        return deduped
    }

    static func manualHint(from text: String) -> (name: String, area: String?)? {
        let cleaned = cleanLine(text)
            .components(separatedBy: "#")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else { return nil }
        let parts = splitNameAndArea(cleaned)
        guard let name = parts.name else { return nil }
        return (name, parts.area)
    }

    private static func lineSeeds(from text: String) -> [PlaceImportSeed] {
        text.components(separatedBy: .newlines)
            .enumerated()
            .flatMap { index, rawLine in
                seeds(fromLine: rawLine, lineNumber: index + 1)
            }
    }

    private static func seeds(fromLine rawLine: String, lineNumber: Int) -> [PlaceImportSeed] {
        let line = cleanLine(rawLine)
        guard !line.isEmpty else { return [] }

        let links = urls(in: line)
        if links.count > 1 {
            return links.map { link in
                PlaceImportSeed(
                    rawText: link,
                    nameHint: nil,
                    areaHint: nil,
                    sourceURLString: link,
                    sourceLine: lineNumber
                )
            }
        }

        let link = links.first
        var hintText = line
        if let link {
            hintText = hintText.replacingOccurrences(of: link, with: "")
            hintText = hintText.trimmingCharacters(in: CharacterSet(charactersIn: " |-"))
        }
        let hint = splitNameAndArea(hintText)

        guard link != nil || hint.name != nil else { return [] }
        return [
            PlaceImportSeed(
                rawText: line,
                nameHint: hint.name,
                areaHint: hint.area,
                sourceURLString: link,
                sourceLine: lineNumber
            )
        ]
    }

    private static func csvSeeds(from text: String) -> [PlaceImportSeed] {
        let rows = CSVDocument.parse(text)
        guard let headers = rows.first?.map(normalizedHeader), !headers.isEmpty else {
            return []
        }

        let recognizedHeaders = Set([
            "title", "name", "place", "business", "location", "address", "city", "area",
            "url", "google maps url", "maps url", "location url", "note", "notes", "comment"
        ])
        guard !Set(headers).isDisjoint(with: recognizedHeaders) else {
            return lineSeeds(from: text)
        }

        return rows.dropFirst().enumerated().compactMap { offset, fields in
            var values: [String: String] = [:]
            for (index, header) in headers.enumerated() where index < fields.count {
                let value = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    values[header] = value
                }
            }

            let name = firstValue(in: values, keys: ["title", "name", "place", "business", "location"])
            let url = firstValue(in: values, keys: ["url", "google maps url", "maps url", "location url"])
            let area = firstValue(in: values, keys: ["address", "city", "area"])
            let note = firstValue(in: values, keys: ["note", "notes", "comment"])
            let noteHint = note.flatMap(manualHint)
            let resolvedName = normalizedOptional(name) ?? noteHint?.name
            let resolvedArea = normalizedOptional(area) ?? noteHint?.area

            guard resolvedName != nil || normalizedOptional(url) != nil else { return nil }
            let raw = fields.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
            return PlaceImportSeed(
                rawText: raw,
                nameHint: resolvedName,
                areaHint: resolvedArea,
                sourceURLString: normalizedOptional(url),
                sourceLine: offset + 2
            )
        }
    }

    private static func jsonSeeds(from text: String) -> [PlaceImportSeed] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

        var dictionaries: [[String: Any]] = []
        collectDictionaries(from: value, into: &dictionaries)

        return dictionaries.enumerated().compactMap { index, dictionary in
            let pairs: [(String, String)] = dictionary.compactMap { key, value in
                guard let string = value as? String else { return nil }
                return (normalizedHeader(key), string)
            }
            let values = Dictionary(uniqueKeysWithValues: pairs)
            let name = firstValue(in: values, keys: ["title", "name", "place", "business", "location"])
            let url = firstValue(in: values, keys: ["url", "google maps url", "maps url", "location url"])
            let area = firstValue(in: values, keys: ["address", "city", "area"])
            guard normalizedOptional(name) != nil || normalizedOptional(url) != nil else { return nil }

            return PlaceImportSeed(
                rawText: normalizedOptional(name) ?? normalizedOptional(url) ?? "Imported place",
                nameHint: normalizedOptional(name),
                areaHint: normalizedOptional(area),
                sourceURLString: normalizedOptional(url),
                sourceLine: index + 1
            )
        }
    }

    private static func collectDictionaries(from value: Any, into output: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            output.append(dictionary)
            for nested in dictionary.values {
                collectDictionaries(from: nested, into: &output)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collectDictionaries(from: nested, into: &output)
            }
        }
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        text.hasPrefix("{") || text.hasPrefix("[")
    }

    private static func looksLikeCSV(_ text: String) -> Bool {
        guard let firstLine = text.components(separatedBy: .newlines).first else { return false }
        let normalized = firstLine.lowercased()
        return normalized.contains(",")
            && ["title", "name", "place", "location", "url", "address"]
                .contains(where: normalized.contains)
    }

    private static func cleanLine(_ rawLine: String) -> String {
        rawLine
            .replacingOccurrences(
                of: #"^\s*(?:[-*]|\d+[.)]|\u2022)\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitNameAndArea(_ value: String) -> (name: String?, area: String?) {
        let cleaned = value
            .replacingOccurrences(of: "\u{2014}", with: " - ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " |,-"))
        guard !cleaned.isEmpty else { return (nil, nil) }

        for separator in [" | ", " - ", ","] {
            let parts = cleaned.components(separatedBy: separator)
            if parts.count > 1 {
                let name = normalizedOptional(parts[0])
                let area = normalizedOptional(parts.dropFirst().joined(separator: separator == "," ? "," : separator))
                return (name, area)
            }
        }
        return (cleaned, nil)
    }

    private static func urls(in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s]+"#) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return String(value[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        }
    }

    private static func deduplicate(_ seeds: [PlaceImportSeed]) -> [PlaceImportSeed] {
        var seen = Set<String>()
        return seeds.filter { seed in
            let key = [seed.sourceURLString, seed.nameHint, seed.areaHint]
                .compactMap(normalizedOptional)
                .joined(separator: "|")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return true
        }
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func firstValue(in values: [String: String], keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] }.first
    }
}

enum PlaceImportSourceDetector {
    static func source(for seed: PlaceImportSeed) -> PlaceImportSource {
        guard let sourceURLString = seed.sourceURLString,
              let url = URL(string: sourceURLString),
              let host = url.host?.lowercased()
        else {
            return .textNotes
        }

        if host == "maps.app.goo.gl"
            || host == "maps.google.com"
            || (host.hasSuffix(".google.com") && url.path.lowercased().contains("/maps"))
            || (host == "goo.gl" && url.path.lowercased().hasPrefix("/maps"))
        {
            return .googleMaps
        }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") || host == "instagr.am" {
            return .instagram
        }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            return .tiktok
        }
        return .textNotes
    }
}

private enum CSVDocument {
    static func parse(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
            } else {
                field.append(character)
            }
            index += 1
        }

        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows
    }
}
