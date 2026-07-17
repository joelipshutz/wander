import Foundation
import ImageIO
import NaturalLanguage
import UIKit
import Vision

struct SocialImportMetadata: Equatable {
    let title: String?
    let caption: String?
    let authorName: String?
    let thumbnailURL: URL?

    var evidenceText: String {
        var seen = Set<String>()
        return [caption, title]
            .compactMap { value -> String? in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty,
                      seen.insert(value).inserted
                else { return nil }
                return value
            }
            .joined(separator: "\n")
    }
}

@MainActor
protocol SocialImportMetadataProviding {
    func metadata(for url: URL, source: PlaceImportSource) async -> SocialImportMetadata?
}

@MainActor
final class PublicSocialImportMetadataProvider: SocialImportMetadataProviding {
    private struct TikTokResponse: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailURL: URL?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }

    private let httpClient: any PlaceImportHTTPFetching

    init(httpClient: any PlaceImportHTTPFetching = URLSessionPlaceImportHTTPClient()) {
        self.httpClient = httpClient
    }

    func metadata(for url: URL, source: PlaceImportSource) async -> SocialImportMetadata? {
        switch source {
        case .tiktok:
            return await tiktokMetadata(for: url)
        case .instagram:
            return await instagramMetadata(for: url)
        case .googleMaps, .textNotes:
            return nil
        }
    }

    private func tiktokMetadata(for url: URL) async -> SocialImportMetadata? {
        if let metadata = await requestTikTokMetadata(for: url) {
            return metadata
        }

        guard let expandedURL = await expandedURL(for: url), expandedURL != url else { return nil }
        return await requestTikTokMetadata(for: expandedURL)
    }

    private func requestTikTokMetadata(for url: URL) async -> SocialImportMetadata? {
        var components = URLComponents(string: "https://www.tiktok.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let endpoint = components?.url else { return nil }

        var request = URLRequest(url: endpoint, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let response = try? await httpClient.response(for: request),
              (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(TikTokResponse.self, from: response.data)
        else { return nil }

        return SocialImportMetadata(
            title: payload.title?.trimmedNil,
            caption: payload.title?.trimmedNil,
            authorName: payload.authorName?.trimmedNil,
            thumbnailURL: payload.thumbnailURL
        )
    }

    private func instagramMetadata(for url: URL) async -> SocialImportMetadata? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let response = try? await httpClient.response(for: request),
              (200..<300).contains(response.statusCode),
              response.data.count <= 5_000_000,
              let html = String(data: response.data, encoding: .utf8)
        else { return nil }
        return PublicSocialHTMLMetadataParser.metadata(from: html)
    }

    private func expandedURL(for url: URL) async -> URL? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("rec.me social link resolver", forHTTPHeaderField: "User-Agent")
        guard let response = try? await httpClient.response(for: request),
              (200..<400).contains(response.statusCode)
        else { return nil }
        return response.finalURL
    }
}

enum PublicSocialHTMLMetadataParser {
    static func metadata(from html: String) -> SocialImportMetadata? {
        let title = firstMetaContent(in: html, keys: ["og:title", "twitter:title"])
        let caption = firstMetaContent(in: html, keys: ["og:description", "description"])
        let image = firstMetaContent(in: html, keys: ["og:image", "twitter:image"])
            .flatMap(URL.init(string:))
        guard title != nil || caption != nil || image != nil else { return nil }

        return SocialImportMetadata(
            title: title?.trimmedNil,
            caption: caption?.trimmedNil,
            authorName: instagramAuthor(from: title),
            thumbnailURL: image
        )
    }

    private static func firstMetaContent(in html: String, keys: [String]) -> String? {
        guard let tagExpression = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let acceptedKeys = Set(keys.map { $0.lowercased() })
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for tagMatch in tagExpression.matches(in: html, range: range) {
            guard let tagRange = Range(tagMatch.range, in: html) else { continue }
            let attributes = metaAttributes(in: String(html[tagRange]))
            guard let metadataKey = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  acceptedKeys.contains(metadataKey),
                  let content = attributes["content"]
            else { continue }
            return decodeHTMLEntities(content)
        }
        return nil
    }

    private static func metaAttributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)

        return expression.matches(in: tag, range: range).reduce(into: [:]) { attributes, match in
            guard match.numberOfRanges == 5,
                  let nameRange = Range(match.range(at: 1), in: tag)
            else { return }
            let value = (2...4).compactMap { capture -> String? in
                guard match.range(at: capture).location != NSNotFound,
                      let valueRange = Range(match.range(at: capture), in: tag)
                else { return nil }
                return String(tag[valueRange])
            }.first
            if let value {
                attributes[String(tag[nameRange]).lowercased()] = value
            }
        }
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ).string
        else {
            return value.replacingOccurrences(of: "&amp;", with: "&")
        }
        return decoded
    }

    private static func instagramAuthor(from title: String?) -> String? {
        guard let title,
              let range = title.range(of: " on Instagram", options: .caseInsensitive)
        else { return nil }
        return String(title[..<range.lowerBound]).trimmedNil
    }
}

@MainActor
protocol SocialThumbnailTextRecognizing {
    func recognizedText(at url: URL) async -> String?
}

@MainActor
final class VisionSocialThumbnailTextRecognizer: SocialThumbnailTextRecognizing {
    private let httpClient: any PlaceImportHTTPFetching

    init(httpClient: any PlaceImportHTTPFetching = URLSessionPlaceImportHTTPClient()) {
        self.httpClient = httpClient
    }

    func recognizedText(at url: URL) async -> String? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let response = try? await httpClient.response(for: request),
              (200..<300).contains(response.statusCode),
              response.data.count <= 10_000_000,
              response.mimeType?.hasPrefix("image/") != false
        else { return nil }

        let data = response.data
        return await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: cgImageOrientation(for: image.imageOrientation),
                options: [:]
            )
            try? handler.perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.trimmedNil
        }.value
    }
}

struct SocialPlaceSearchHint: Equatable {
    let name: String
    let area: String?
}

enum SocialPlaceHintExtractor {
    static func hints(
        from metadata: SocialImportMetadata,
        recognizedText: String?,
        limit: Int = 12
    ) -> [SocialPlaceSearchHint] {
        let evidence = metadata.evidenceText
        var results: [SocialPlaceSearchHint] = []

        appendExplicitLocationHints(from: evidence, to: &results)
        appendHandles(from: evidence, to: &results)
        appendPhraseHints(from: evidence, to: &results)
        appendNamedEntities(from: evidence, to: &results)

        if let recognizedText {
            for query in PhotoPlaceTextExtractor.searchQueries(from: recognizedText, limit: 6) {
                append(parsedHint(from: query), to: &results)
            }
        }

        return Array(results.prefix(limit))
    }

    private static func appendExplicitLocationHints(
        from text: String,
        to output: inout [SocialPlaceSearchHint]
    ) {
        let patterns = [
            #"📍\s*([^#\n]{3,120})"#,
            #"(?i)(?:location|located)\s*[:\-]\s*([^#\n]{3,120})"#,
            #"(?i)\(\s*location\s*:\s*([^\)\n]{3,120})\)"#
        ]
        for pattern in patterns {
            for value in captures(pattern: pattern, in: text) {
                append(parsedHint(from: value), to: &output)
            }
        }
    }

    private static func appendHandles(from text: String, to output: inout [SocialPlaceSearchHint]) {
        for handle in captures(pattern: #"@([A-Za-z0-9._]{3,40})"#, in: text) {
            let name = readableHandle(handle)
            guard !isGenericSocialTerm(name) else { continue }
            append(SocialPlaceSearchHint(name: name, area: nil), to: &output)
        }

        for hashtag in captures(pattern: #"#([A-Za-z][A-Za-z0-9_]{3,40})"#, in: text) {
            let name = readableHandle(hashtag)
            guard !isGenericSocialTerm(name), containsBusinessToken(name) else { continue }
            append(SocialPlaceSearchHint(name: name, area: nil), to: &output)
        }
    }

    private static func appendPhraseHints(from text: String, to output: inout [SocialPlaceSearchHint]) {
        let pattern = #"(?i)\b(?:called|at|from|visited|visit|trying|place is)\s+@?([^#\n.!?]{3,90})"#
        for value in captures(pattern: pattern, in: text) {
            let cleaned = trimPhrase(value)
            append(parsedHint(from: cleaned), to: &output)
        }
    }

    private static func appendNamedEntities(from text: String, to output: inout [SocialPlaceSearchHint]) {
        guard !text.isEmpty else { return }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var organizations: [String] = []
        var places: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tag == .organizationName {
                organizations.append(value)
            } else if tag == .placeName {
                places.append(value)
            }
            return true
        }

        let area = places.first(where: { !$0.isEmpty })
        for organization in organizations where !isGenericSocialTerm(organization) {
            append(SocialPlaceSearchHint(name: organization, area: area), to: &output)
        }
    }

    private static func parsedHint(from rawValue: String) -> SocialPlaceSearchHint? {
        var value = rawValue
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'()[]"))
        guard !value.isEmpty else { return nil }

        if let range = value.range(of: " in ", options: [.caseInsensitive, .backwards]) {
            let name = String(value[..<range.lowerBound]).trimmedNil
            let area = String(value[range.upperBound...]).trimmedNil
            if let name, !isGenericSocialTerm(name) {
                return SocialPlaceSearchHint(name: name, area: area)
            }
        }

        guard let hint = PlaceImportParser.manualHint(from: value),
              !isGenericSocialTerm(hint.name)
        else { return nil }
        value = hint.name
        return SocialPlaceSearchHint(name: value, area: hint.area)
    }

    private static func append(
        _ hint: SocialPlaceSearchHint?,
        to output: inout [SocialPlaceSearchHint]
    ) {
        guard let hint,
              hint.name.count >= 3,
              hint.name.count <= 80,
              !isGenericSocialTerm(hint.name),
              hasDistinctiveVenueToken(hint.name)
        else { return }
        let key = normalized(hint.name) + "|" + normalized(hint.area ?? "")
        guard !output.contains(where: {
            normalized($0.name) + "|" + normalized($0.area ?? "") == key
        }) else { return }
        output.append(hint)
    }

    private static func captures(pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern), !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[valueRange])
        }
    }

    private static func readableHandle(_ rawValue: String) -> String {
        var value = rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(
                of: #"([a-z0-9])([A-Z])"#,
                with: "$1 $2",
                options: .regularExpression
            )

        let businessTokens = [
            "restaurant", "coffee", "bakery", "kitchen", "market", "farms",
            "tacos", "pizza", "sushi", "cafe", "grill", "deli", "hotel", "bar"
        ]
        for token in businessTokens where !value.contains(" ") || !value.lowercased().contains(" \(token)") {
            value = value.replacingOccurrences(
                of: token,
                with: " \(token) ",
                options: .caseInsensitive
            )
        }
        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimPhrase(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let endings = [" and ", " with ", " where ", " for ", " which ", " serving "]
        for ending in endings {
            if let range = value.range(of: ending, options: .caseInsensitive) {
                value = String(value[..<range.lowerBound])
            }
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
    }

    private static func containsBusinessToken(_ value: String) -> Bool {
        let normalizedValue = normalized(value)
        return [
            "restaurant", "coffee", "cafe", "bakery", "kitchen", "market", "farms",
            "tacos", "pizza", "sushi", "grill", "deli", "hotel", "bar", "eatery"
        ].contains(where: normalizedValue.contains)
    }

    private static func isGenericSocialTerm(_ value: String) -> Bool {
        let key = normalized(value)
        guard key.count >= 3 else { return true }
        return genericTerms.contains(key)
            || key.hasPrefix("instagram")
            || key.hasPrefix("tiktok")
    }

    private static func hasDistinctiveVenueToken(_ value: String) -> Bool {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let tokens = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return tokens.contains { token in
            token.count >= 2 && !genericVenueTokens.contains(token)
        }
    }

    private static let genericTerms: Set<String> = [
        "food", "foodie", "foodtok", "foodtiktok", "restaurant", "restaurants",
        "reels", "reel", "viral", "fyp", "foryou", "foryoupage", "explore",
        "lafood", "lafoodie", "losangeles", "california", "travel", "creator",
        "coffee", "coffeeshop", "cafe", "localcoffee", "localcoffeeshop"
    ]

    private static let genericVenueTokens: Set<String> = [
        "a", "an", "and", "at", "best", "cafe", "coffee", "coffeehouse", "food",
        "for", "in", "instagram", "local", "new", "of", "place", "restaurant",
        "shop", "spot", "the", "tiktok", "to", "try", "viral", "visit"
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

private func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: .up
    case .down: .down
    case .left: .left
    case .right: .right
    case .upMirrored: .upMirrored
    case .downMirrored: .downMirrored
    case .leftMirrored: .leftMirrored
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
}

private extension String {
    var trimmedNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
