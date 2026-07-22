import Foundation
import ImageIO
import UIKit
import Vision

struct SocialImportMediaEvidence: Equatable, Sendable {
    let accessibilityText: String?
    let imageURL: URL?
}

enum SocialMediaURLPolicy {
    static func isInstagramPageURL(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    static func isInstagramMediaURL(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        return isHost(host, in: ["cdninstagram.com", "fbcdn.net"])
    }

    static func isTikTokMediaURL(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        return isHost(
            host,
            in: ["tiktokcdn.com", "tiktokcdn-us.com", "ibytedtos.com", "byteoversea.com", "muscdn.com"]
        )
    }

    static func isTrustedSocialMediaURL(_ url: URL) -> Bool {
        isInstagramMediaURL(url) || isTikTokMediaURL(url)
    }

    static func permitsMediaRedirect(from originalURL: URL, to finalURL: URL) -> Bool {
        guard isTrustedSocialMediaURL(originalURL), isTrustedSocialMediaURL(finalURL),
              let originalHost = originalURL.host?.lowercased(),
              let finalHost = finalURL.host?.lowercased()
        else { return false }
        if originalHost == finalHost { return true }
        if isInstagramMediaURL(originalURL), isInstagramMediaURL(finalURL) { return true }
        let tiktokMediaDomains = ["tiktokcdn.com", "tiktokcdn-us.com", "ibytedtos.com", "byteoversea.com"]
        return isHost(originalHost, in: tiktokMediaDomains)
            && isHost(finalHost, in: tiktokMediaDomains)
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    private static func isHost(_ host: String, in domains: [String]) -> Bool {
        domains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

struct SocialImportMetadata: Equatable, Sendable {
    let title: String?
    let caption: String?
    let authorName: String?
    let thumbnailURL: URL?
    let mediaItems: [SocialImportMediaEvidence]

    init(
        title: String?,
        caption: String?,
        authorName: String?,
        thumbnailURL: URL?,
        mediaItems: [SocialImportMediaEvidence] = []
    ) {
        self.title = title
        self.caption = caption
        self.authorName = authorName
        self.thumbnailURL = thumbnailURL
        self.mediaItems = mediaItems
    }

    var primaryEvidenceText: String {
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

private struct ParsedInstagramPage: Sendable {
    let openGraph: SocialImportMetadata?
    let embedded: InstagramEmbeddedPostEvidence?
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
            thumbnailURL: payload.thumbnailURL.flatMap { thumbnailURL in
                SocialMediaURLPolicy.isTikTokMediaURL(thumbnailURL) ? thumbnailURL : nil
            }
        )
    }

    private func instagramMetadata(for url: URL) async -> SocialImportMetadata? {
        guard let shortcode = InstagramEmbeddedPostParser.shortcode(from: url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let response = try? await httpClient.response(for: request),
              (200..<300).contains(response.statusCode),
              SocialMediaURLPolicy.isInstagramPageURL(response.finalURL),
              response.data.count <= 5_000_000,
              let html = String(data: response.data, encoding: .utf8)
        else { return nil }
        let parsingTask = Task.detached(priority: .userInitiated) {
            ParsedInstagramPage(
                openGraph: PublicSocialHTMLMetadataParser.metadata(from: html),
                embedded: InstagramEmbeddedPostParser.evidence(
                    from: html,
                    expectedCode: shortcode
                )
            )
        }
        let parsed = await withTaskCancellationHandler {
            await parsingTask.value
        } onCancel: {
            parsingTask.cancel()
        }
        let openGraph = parsed.openGraph.map { metadata in
            SocialImportMetadata(
                title: metadata.title,
                caption: metadata.caption,
                authorName: metadata.authorName,
                thumbnailURL: metadata.thumbnailURL.flatMap { imageURL in
                    SocialMediaURLPolicy.isInstagramMediaURL(imageURL) ? imageURL : nil
                }
            )
        }
        guard let embedded = parsed.embedded else { return openGraph }

        let trustedOpenGraphImage = openGraph?.thumbnailURL.flatMap { imageURL in
            SocialMediaURLPolicy.isInstagramMediaURL(imageURL) ? imageURL : nil
        }

        return SocialImportMetadata(
            title: openGraph?.title,
            caption: embedded.caption ?? openGraph?.caption,
            authorName: openGraph?.authorName,
            thumbnailURL: trustedOpenGraphImage ?? embedded.mediaItems.first?.imageURL,
            mediaItems: embedded.mediaItems
        )
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
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        let tags = tagExpression.matches(in: html, range: range).compactMap { match -> [String: String]? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            return metaAttributes(in: String(html[tagRange]))
        }
        for key in keys.map({ $0.lowercased() }) {
            for attributes in tags {
                guard (attributes["property"] ?? attributes["name"])?.lowercased() == key,
                      let content = attributes["content"]
                else { continue }
                return decodeHTMLEntities(content)
            }
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

struct InstagramEmbeddedPostEvidence: Equatable, Sendable {
    let caption: String?
    let mediaItems: [SocialImportMediaEvidence]
}

enum InstagramEmbeddedPostParser {
    private static let maximumScriptBytes = 1_500_000
    private static let maximumVisitedNodes = 100_000
    private static let maximumTotalVisitedNodes = 300_000
    private static let maximumDepth = 40

    static func shortcode(from url: URL) -> String? {
        guard SocialMediaURLPolicy.isInstagramPageURL(url) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2,
              ["p", "reel", "tv"].contains(components[0].lowercased())
        else { return nil }
        let value = components[1]
        guard value.range(of: #"^[A-Za-z0-9_-]{5,30}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func evidence(
        from html: String,
        expectedCode: String,
        maxMediaItems: Int = 16
    ) -> InstagramEmbeddedPostEvidence? {
        guard !html.isEmpty, maxMediaItems > 0,
              let scriptExpression = try? NSRegularExpression(
                pattern: #"<script\b([^>]*)>(.*?)</script>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
              )
        else { return nil }

        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var bestEvidence: InstagramEmbeddedPostEvidence?
        var totalRemainingNodes = maximumTotalVisitedNodes
        for match in scriptExpression.matches(in: html, range: htmlRange) {
            guard !Task.isCancelled, totalRemainingNodes > 0 else { break }
            guard match.numberOfRanges == 3,
                  let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html),
                  isJSONScriptAttributes(String(html[attributesRange]))
            else { continue }

            let body = String(html[bodyRange])
            guard body.utf8.count <= maximumScriptBytes,
                  let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            var remainingNodes = min(maximumVisitedNodes, totalRemainingNodes)
            let startingNodes = remainingNodes
            collectBestMatchingEvidence(
                in: root,
                expectedCode: expectedCode,
                maxMediaItems: maxMediaItems,
                depth: 0,
                remainingNodes: &remainingNodes,
                bestEvidence: &bestEvidence
            )
            totalRemainingNodes -= startingNodes - remainingNodes
        }
        return bestEvidence
    }

    private static func isJSONScriptAttributes(_ attributes: String) -> Bool {
        attributes.range(
            of: #"\btype\s*=\s*([\"'])application/json\1"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil
    }

    private static func collectBestMatchingEvidence(
        in value: Any,
        expectedCode: String,
        maxMediaItems: Int,
        depth: Int,
        remainingNodes: inout Int,
        bestEvidence: inout InstagramEmbeddedPostEvidence?
    ) {
        guard !Task.isCancelled, depth <= maximumDepth, remainingNodes > 0 else { return }
        remainingNodes -= 1

        if let dictionary = value as? [String: Any] {
            if dictionary["code"] as? String == expectedCode,
               dictionary["carousel_media"] is [Any],
               let evidence = postEvidence(from: dictionary, maxMediaItems: maxMediaItems),
               isBetter(evidence, than: bestEvidence) {
                bestEvidence = evidence
            }
            for child in dictionary.values {
                collectBestMatchingEvidence(
                    in: child,
                    expectedCode: expectedCode,
                    maxMediaItems: maxMediaItems,
                    depth: depth + 1,
                    remainingNodes: &remainingNodes,
                    bestEvidence: &bestEvidence
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectBestMatchingEvidence(
                    in: child,
                    expectedCode: expectedCode,
                    maxMediaItems: maxMediaItems,
                    depth: depth + 1,
                    remainingNodes: &remainingNodes,
                    bestEvidence: &bestEvidence
                )
            }
        }
    }

    private static func isBetter(
        _ candidate: InstagramEmbeddedPostEvidence,
        than current: InstagramEmbeddedPostEvidence?
    ) -> Bool {
        guard let current else { return true }
        let candidateImageCount = candidate.mediaItems.lazy.compactMap(\.imageURL).count
        let currentImageCount = current.mediaItems.lazy.compactMap(\.imageURL).count
        if candidateImageCount != currentImageCount {
            return candidateImageCount > currentImageCount
        }
        if candidate.mediaItems.count != current.mediaItems.count {
            return candidate.mediaItems.count > current.mediaItems.count
        }
        return (candidate.caption?.count ?? 0) > (current.caption?.count ?? 0)
    }

    private static func postEvidence(
        from post: [String: Any],
        maxMediaItems: Int
    ) -> InstagramEmbeddedPostEvidence? {
        let caption = ((post["caption"] as? [String: Any])?["text"] as? String)?.trimmedNil
        let children = post["carousel_media"] as? [Any] ?? []
        var seenURLs = Set<String>()
        let mediaItems = children.prefix(maxMediaItems).compactMap { child -> SocialImportMediaEvidence? in
            guard let dictionary = child as? [String: Any] else { return nil }
            let accessibilityText = (dictionary["accessibility_caption"] as? String)?.trimmedNil
            let imageURL = imageURL(from: dictionary).flatMap { url -> URL? in
                guard seenURLs.insert(url.absoluteString).inserted else { return nil }
                return url
            }
            guard accessibilityText != nil || imageURL != nil else { return nil }
            return SocialImportMediaEvidence(
                accessibilityText: accessibilityText,
                imageURL: imageURL
            )
        }
        guard caption != nil || !mediaItems.isEmpty else { return nil }
        return InstagramEmbeddedPostEvidence(caption: caption, mediaItems: mediaItems)
    }

    private static func imageURL(from media: [String: Any]) -> URL? {
        if let versions = media["image_versions2"] as? [String: Any],
           let candidates = versions["candidates"] as? [Any] {
            let largestCandidate = candidates.compactMap { candidate -> (url: URL, pixels: Int)? in
                guard let dictionary = candidate as? [String: Any],
                      let url = validatedHTTPSURL(dictionary["url"])
                else { return nil }
                let width = dictionary["width"] as? Int ?? 0
                let height = dictionary["height"] as? Int ?? 0
                return (url, width * height)
            }
            .max { lhs, rhs in lhs.pixels < rhs.pixels }
            if let largestCandidate {
                return largestCandidate.url
            }
        }
        return validatedHTTPSURL(media["display_uri"])
    }

    private static func validatedHTTPSURL(_ value: Any?) -> URL? {
        guard let rawValue = value as? String,
              let url = URL(string: rawValue),
              SocialMediaURLPolicy.isInstagramMediaURL(url)
        else { return nil }
        return url
    }
}

@MainActor
protocol SocialThumbnailTextRecognizing: Sendable {
    func recognizedText(at url: URL) async -> String?
}

struct SocialTextObservation: Equatable {
    let text: String
    let boundingBox: CGRect
}

enum SocialImportCountry {
    static func isoCode(for value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return countryCodesByName[normalized(value)]
    }

    static func candidatesCompatibleWithExactCountry(
        _ candidates: [PlaceCandidate],
        areaHint: String?
    ) -> [PlaceCandidate] {
        guard let areaHint,
              !areaHint.contains(","),
              PlaceImportGeography.stateCode(in: areaHint) == nil,
              normalized(areaHint) != "georgia",
              let expectedCode = isoCode(for: areaHint)
        else { return candidates }

        return candidates.filter { candidate in
            guard let candidateCode = isoCode(for: candidate.country) else { return false }
            return candidateCode == expectedCode
        }
    }

    private static let countryCodesByName: [String: String] = {
        var result: [String: String] = [:]
        let locale = Locale(identifier: "en_US_POSIX")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            result[normalized(code)] = code
            if let name = locale.localizedString(forRegionCode: code) {
                result[normalized(name)] = code
            }
        }
        let aliases = [
            "usa": "US",
            "unitedstatesofamerica": "US",
            "uae": "AE",
            "thephilippines": "PH",
            "china": "CN",
            "republicofkorea": "KR",
            "southkorea": "KR",
            "czechrepublic": "CZ",
            "turkey": "TR",
            "vietnam": "VN",
            "bolivia": "BO",
            "venezuela": "VE",
            "tanzania": "TZ",
            "russia": "RU",
            "iran": "IR",
            "syria": "SY",
            "laos": "LA",
            "moldova": "MD",
            "brunei": "BN",
            "capeverde": "CV",
            "ivorycoast": "CI"
        ]
        for (name, code) in aliases {
            result[name] = code
        }
        return result
    }()

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum SocialGuideTextParser {
    private struct WorkingRow {
        var name: String
        var area: String
        let observation: SocialTextObservation
    }

    static func components(from line: String) -> (name: String, area: String)? {
        guard let components = rawComponents(from: line),
              SocialImportCountry.isoCode(for: components.area) != nil
        else { return nil }
        return components
    }

    static func rows(from observations: [SocialTextObservation]) -> [String] {
        var consumedContinuationIndices = Set<Int>()
        var workingRows = observations.enumerated().compactMap { index, observation -> WorkingRow? in
            if let components = rawComponents(from: observation.text) {
                return WorkingRow(
                    name: components.name,
                    area: components.area,
                    observation: observation
                )
            }
            guard let area = slashOnlyArea(from: observation.text) else { return nil }
            let maximumDistance = max(0.026, observation.boundingBox.height * 2)
            let nameFragments = observations.enumerated()
                .filter { candidateIndex, candidate in
                    candidateIndex != index
                        && !candidate.text.contains("/")
                        && candidate.boundingBox.minX < observation.boundingBox.minX
                        && abs(candidate.boundingBox.midY - observation.boundingBox.midY) <= maximumDistance
                        && isPossibleContinuation(cleanedLine(candidate.text))
                }
                .sorted { observationOrder($0.element, $1.element) }
            guard !nameFragments.isEmpty else { return nil }
            consumedContinuationIndices.formUnion(nameFragments.map { $0.offset })
            return WorkingRow(
                name: nameFragments.map { cleanedLine($0.element.text) }.joined(separator: " "),
                area: area,
                observation: observation
            )
        }
        .sorted { lhs, rhs in
            if lhs.observation.boundingBox.midY != rhs.observation.boundingBox.midY {
                return lhs.observation.boundingBox.midY > rhs.observation.boundingBox.midY
            }
            return lhs.observation.boundingBox.minX < rhs.observation.boundingBox.minX
        }
        guard !workingRows.isEmpty else { return [] }

        var continuations = Array(repeating: [SocialTextObservation](), count: workingRows.count)
        for (index, observation) in observations.enumerated()
        where !observation.text.contains("/") && !consumedContinuationIndices.contains(index) {
            let text = cleanedLine(observation.text)
            guard isPossibleContinuation(text) else { continue }
            guard let nearestIndex = workingRows.indices.min(by: { lhs, rhs in
                abs(workingRows[lhs].observation.boundingBox.midY - observation.boundingBox.midY)
                    < abs(workingRows[rhs].observation.boundingBox.midY - observation.boundingBox.midY)
            }) else { continue }
            let row = workingRows[nearestIndex]
            let distance = abs(row.observation.boundingBox.midY - observation.boundingBox.midY)
            let maximumDistance = max(0.02, row.observation.boundingBox.height * 1.35)
            guard distance <= maximumDistance else { continue }
            continuations[nearestIndex].append(observation)
        }

        for index in workingRows.indices {
            let continuationTexts = continuations[index]
                .sorted(by: observationOrder)
                .map { cleanedLine($0.text) }
            let countryIndices = countryContinuationIndices(
                area: workingRows[index].area,
                continuations: continuationTexts
            )
            for (continuationIndex, text) in continuationTexts.enumerated() {
                if countryIndices.contains(continuationIndex) {
                    workingRows[index].area = joined(workingRows[index].area, text)
                } else {
                    workingRows[index].name = joined(workingRows[index].name, text)
                }
            }
        }

        return workingRows.compactMap { row in
            guard SocialImportCountry.isoCode(for: row.area) != nil else { return nil }
            return "\(row.name) / \(row.area)"
        }
    }

    private static func rawComponents(from line: String) -> (name: String, area: String)? {
        let value = cleanedLine(line)
        guard let slashRange = value.range(of: "/", options: .backwards),
              let name = String(value[..<slashRange.lowerBound]).trimmedNil,
              let area = String(value[slashRange.upperBound...]).trimmedNil
        else { return nil }
        return (name, area)
    }

    private static func slashOnlyArea(from line: String) -> String? {
        let value = cleanedLine(line)
        guard value.hasPrefix("/"),
              let area = String(value.dropFirst()).trimmedNil,
              area.rangeOfCharacter(from: .letters) != nil,
              area == area.uppercased()
        else { return nil }
        return area
    }

    private static func cleanedLine(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "•", with: "·")
            .replacingOccurrences(
                of: #"(?i)\s+NEW\s+ENTRY\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*[$#]?\d{1,3}[.)]?\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPossibleContinuation(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .letters) != nil,
              value == value.uppercased()
        else { return false }
        let normalized = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).uppercased()
        let lettersOnly = normalized.filter(\.isLetter)
        return !entryFragments.contains(lettersOnly)
            && !normalized.contains("NEW ENTRY")
            && !normalized.contains("SPONSORED")
            && !normalized.contains("BEST COFFEE SHOP")
            && !normalized.contains("CAFETEROS DE COLOMBIA")
    }

    private static func countryContinuationIndices(
        area: String,
        continuations: [String]
    ) -> Set<Int> {
        if SocialImportCountry.isoCode(for: area) != nil {
            return []
        }
        let searchableCount = min(continuations.count, 8)
        guard searchableCount > 0 else { return [] }
        let masks = (1..<(1 << searchableCount)).sorted { lhs, rhs in
            if lhs.nonzeroBitCount != rhs.nonzeroBitCount {
                return lhs.nonzeroBitCount < rhs.nonzeroBitCount
            }
            return lhs < rhs
        }
        for mask in masks {
            let indices = (0..<searchableCount).filter { mask & (1 << $0) != 0 }
            let candidate = indices.reduce(area) { partial, index in
                joined(partial, continuations[index])
            }
            if SocialImportCountry.isoCode(for: candidate) != nil {
                return Set(indices)
            }
        }
        return []
    }

    private static func joined(_ first: String, _ second: String) -> String {
        [first, second]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func observationOrder(
        _ lhs: SocialTextObservation,
        _ rhs: SocialTextObservation
    ) -> Bool {
        if lhs.boundingBox.midY != rhs.boundingBox.midY {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private static let entryFragments: Set<String> = [
        "ENTRY", "INTRY", "ITRY", "NTRY", "TRY"
    ]
}

@MainActor
final class VisionSocialThumbnailTextRecognizer: SocialThumbnailTextRecognizing {
    private let httpClient: any PlaceImportHTTPFetching

    init(httpClient: any PlaceImportHTTPFetching = URLSessionPlaceImportHTTPClient()) {
        self.httpClient = httpClient
    }

    func recognizedText(at url: URL) async -> String? {
        guard SocialMediaURLPolicy.isTrustedSocialMediaURL(url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let response = try? await httpClient.response(for: request),
              (200..<300).contains(response.statusCode),
              SocialMediaURLPolicy.permitsMediaRedirect(from: url, to: response.finalURL),
              response.data.count <= 10_000_000,
              response.mimeType?.hasPrefix("image/") != false
        else { return nil }

        let data = response.data
        let recognitionTask = Task.detached(priority: .userInitiated) { () -> String? in
            guard !Task.isCancelled,
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage
            else { return nil }
            let orientation = cgImageOrientation(for: image.imageOrientation)
            let fullObservations = socialTextObservations(in: cgImage, orientation: orientation)
            guard !Task.isCancelled else { return nil }

            var guideRows: [String] = []
            if orientation == .up {
                let leftRows = SocialGuideTextParser.rows(
                    from: fullObservations.filter { $0.boundingBox.midX < 0.5 }
                )
                let rightRows = SocialGuideTextParser.rows(
                    from: fullObservations.filter { $0.boundingBox.midX >= 0.5 }
                )
                guideRows = leftRows + rightRows

                if guideRows.count >= 12,
                   let cropRectangles = denseGuideCropRectangles(
                       for: cgImage,
                       observations: fullObservations
                   ) {
                    let croppedRows = cropRectangles.flatMap { rectangle -> [String] in
                        guard let croppedImage = cgImage.cropping(to: rectangle) else { return [] }
                        return SocialGuideTextParser.rows(
                            from: socialTextObservations(in: croppedImage, orientation: .up)
                        )
                    }
                    if croppedRows.count >= guideRows.count {
                        guideRows = croppedRows
                    }
                }
            }

            if guideRows.count >= 12 {
                return guideRows.joined(separator: "\n")
            }
            let text = fullObservations
                .sorted { lhs, rhs in
                    if lhs.boundingBox.midY != rhs.boundingBox.midY {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .map(\.text)
                .joined(separator: "\n")
            return text.trimmedNil
        }
        return await withTaskCancellationHandler {
            await recognitionTask.value
        } onCancel: {
            recognitionTask.cancel()
        }
    }
}

private func socialTextObservations(
    in image: CGImage,
    orientation: CGImagePropertyOrientation
) -> [SocialTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    try? handler.perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string.trimmedNil else { return nil }
        return SocialTextObservation(text: text, boundingBox: observation.boundingBox)
    }
}

private func denseGuideCropRectangles(
    for image: CGImage,
    observations: [SocialTextObservation]
) -> [CGRect]? {
    let rowBoxes = observations
        .filter { $0.text.contains("/") }
        .map(\.boundingBox)
    guard rowBoxes.count >= 12,
          let minimumY = rowBoxes.map(\.minY).min(),
          let maximumY = rowBoxes.map(\.maxY).max()
    else { return nil }

    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let paddedTop = max(0, 1 - maximumY - 0.035)
    let paddedBottom = min(1, 1 - minimumY + 0.035)
    let snappedTop = (paddedTop * 100).rounded(.up) / 100
    let snappedBottom = (paddedBottom * 100).rounded(.down) / 100
    let top = snappedBottom - snappedTop >= 0.35 ? snappedTop : paddedTop
    let bottom = snappedBottom - snappedTop >= 0.35 ? snappedBottom : paddedBottom
    guard bottom - top >= 0.35 else { return nil }

    let y = floor(height * top)
    let cropHeight = floor(height * (bottom - top))
    let half = floor(width * 0.5)
    let overlap = floor(width * 0.025)
    return [
        CGRect(x: 0, y: y, width: half + overlap, height: cropHeight).integral,
        CGRect(x: half - overlap, y: y, width: width - half + overlap, height: cropHeight).integral
    ]
}

struct SocialPlaceSearchHint: Equatable {
    enum Evidence: Equatable {
        case explicitLocation
        case itineraryPhrase
        case acquisitionPhrase
        case imageText
        case namedEntity
        case itineraryHandle
        case socialHandle

        var shouldRemainVisibleWithoutCandidates: Bool {
            switch self {
            case .explicitLocation, .itineraryPhrase, .imageText:
                true
            case .acquisitionPhrase, .namedEntity, .itineraryHandle, .socialHandle:
                false
            }
        }

        var trustRank: Int {
            switch self {
            case .explicitLocation:
                5
            case .itineraryPhrase:
                4
            case .imageText:
                3
            case .acquisitionPhrase, .namedEntity:
                2
            case .itineraryHandle:
                1
            case .socialHandle:
                0
            }
        }

        var preservesCreatorNameWhenMatched: Bool {
            switch self {
            case .explicitLocation, .itineraryPhrase:
                true
            case .acquisitionPhrase, .imageText, .namedEntity, .itineraryHandle, .socialHandle:
                false
            }
        }
    }

    let name: String
    let area: String?
    let evidence: Evidence
}

enum SocialPlaceHintExtractor {
    static func hints(
        from metadata: SocialImportMetadata,
        recognizedTexts: [String],
        limit: Int = 150
    ) -> [SocialPlaceSearchHint] {
        let primaryEvidence = metadata.primaryEvidenceText
        var results: [SocialPlaceSearchHint] = []

        // Keep each carousel slide isolated. Combining OCR across slides can attach an
        // address or slogan from one image to a place name from another.
        for recognizedText in recognizedTexts {
            appendMediaTextHints(from: recognizedText, to: &results)
        }

        // Creator-authored copy is higher trust than Instagram's generated accessibility
        // captions. It can safely produce durable itinerary rows when MapKit has no match.
        appendExplicitLocationHints(from: primaryEvidence, to: &results)
        appendPhraseHints(from: primaryEvidence, to: &results)

        // Raw account handles are useful fallbacks, but remain non-durable and last in
        // the bounded search budget so they cannot crowd out named destinations.
        appendHandles(from: primaryEvidence, to: &results)

        let postArea = postWideArea(from: metadata)
        var contextualResults: [SocialPlaceSearchHint] = []
        for hint in results {
            append(
                SocialPlaceSearchHint(
                    name: hint.name,
                    area: hint.area ?? postArea,
                    evidence: hint.evidence
                ),
                to: &contextualResults
            )
        }
        return Array(contextualResults.prefix(limit))
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
                append(parsedHint(from: value, evidence: .explicitLocation), to: &output)
            }
        }
    }

    private static func appendHandles(from text: String, to output: inout [SocialPlaceSearchHint]) {
        for handle in captures(pattern: #"@([A-Za-z0-9._]{3,40})"#, in: text) {
            let name = readableHandle(handle)
            guard !isGenericSocialTerm(name) else { continue }
            append(
                SocialPlaceSearchHint(name: name, area: nil, evidence: .socialHandle),
                to: &output
            )
        }

        for hashtag in captures(pattern: #"#([A-Za-z][A-Za-z0-9_]{3,40})"#, in: text) {
            let name = readableHandle(hashtag)
            guard !isGenericSocialTerm(name), containsBusinessToken(name) else { continue }
            append(
                SocialPlaceSearchHint(name: name, area: nil, evidence: .socialHandle),
                to: &output
            )
        }
    }

    private static func appendPhraseHints(from text: String, to output: inout [SocialPlaceSearchHint]) {
        for value in captures(pattern: itineraryPattern, in: text) {
            let cleaned = trimPhrase(value)
            guard !isAttributionPhrase(cleaned) else { continue }
            let evidence: SocialPlaceSearchHint.Evidence = cleaned.hasPrefix("@")
                ? .itineraryHandle
                : .itineraryPhrase
            append(parsedHint(from: cleaned, evidence: evidence), to: &output)
        }

        for value in captures(pattern: acquisitionPattern, in: text) {
            let cleaned = trimPhrase(value)
            guard !isAttributionPhrase(cleaned) else { continue }
            let evidence: SocialPlaceSearchHint.Evidence = cleaned.hasPrefix("@")
                ? .itineraryHandle
                : .acquisitionPhrase
            append(parsedHint(from: cleaned, evidence: evidence), to: &output)
        }
    }

    private static func appendMediaTextHints(
        from text: String,
        to output: inout [SocialPlaceSearchHint]
    ) {
        let guideHints = text.components(separatedBy: .newlines).compactMap { line -> SocialPlaceSearchHint? in
            guard let components = SocialGuideTextParser.components(from: line) else { return nil }
            return SocialPlaceSearchHint(
                name: components.name,
                area: components.area,
                evidence: .imageText
            )
        }
        for hint in guideHints {
            append(hint, to: &output)
        }
        if guideHints.count >= 2 {
            // A dense, country-delimited guide already supplies authoritative row
            // boundaries. Generic adjacent-line guesses would merge neighboring shops.
            return
        }

        for value in captures(pattern: itineraryPattern, in: text) {
            let cleaned = trimPhrase(value)
            guard !isAttributionPhrase(cleaned) else { continue }
            guard let hint = parsedHint(from: cleaned, evidence: .imageText),
                  isStrongMediaPlaceName(hint.name)
            else { continue }
            append(hint, to: &output)
        }

        for query in adjacentNameLineQueries(from: text)
            + PhotoPlaceTextExtractor.searchQueries(from: text, limit: 12) {
            guard let hint = parsedHint(from: query, evidence: .imageText),
                  isStrongMediaPlaceName(hint.name)
            else { continue }
            append(hint, to: &output)
        }
    }

    private static func adjacentNameLineQueries(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }

        return (0..<(lines.count - 1)).compactMap { index in
            let first = lines[index]
            let second = lines[index + 1]
            guard isShortNameFragment(first), isShortNameFragment(second) else { return nil }
            return "\(first) \(second)"
        }
    }

    private static func isShortNameFragment(_ value: String) -> Bool {
        let words = mediaWords(in: value)
        guard (1...4).contains(words.count), value.count <= 40 else { return false }
        let letters = value.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        return value == value.uppercased()
            || value.split(separator: " ").allSatisfy { $0.first?.isUppercase == true }
    }

    private static func isStrongMediaPlaceName(_ value: String) -> Bool {
        let words = mediaWords(in: value)
        guard (2...6).contains(words.count) else { return false }
        let loweredWords = words.map { $0.lowercased() }
        guard mediaActionWords.isDisjoint(with: Set(loweredWords)) else { return false }

        let strongDesignatorCount = loweredWords.filter { strongPlaceDesignators.contains($0) }.count
        let weakDesignatorCount = loweredWords.filter { weakPlaceDesignators.contains($0) }.count
        let distinctiveCount = loweredWords.filter {
            !mediaGenericWords.contains($0)
                && !strongPlaceDesignators.contains($0)
                && !weakPlaceDesignators.contains($0)
        }.count
        if strongDesignatorCount > 0 {
            return distinctiveCount > 0
        }
        return weakDesignatorCount > 0 && distinctiveCount >= 2
    }

    private static func mediaWords(in value: String) -> [String] {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func parsedHint(
        from rawValue: String,
        evidence: SocialPlaceSearchHint.Evidence
    ) -> SocialPlaceSearchHint? {
        var value = rawValue
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'()[]"))
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("@") {
            let handleEnd = value.firstIndex(where: { $0.isWhitespace }) ?? value.endIndex
            let handle = readableHandle(String(value[value.index(after: value.startIndex)..<handleEnd]))
            let remainder = String(value[handleEnd...])
            if let areaRange = remainder.range(of: " in ", options: [.caseInsensitive, .backwards]),
               let area = String(remainder[areaRange.upperBound...]).trimmedNil {
                value = "\(handle) in \(area)"
            } else {
                value = handle
            }
        }

        if let range = value.range(of: " in ", options: [.caseInsensitive, .backwards]) {
            let name = String(value[..<range.lowerBound]).trimmedNil
            let area = String(value[range.upperBound...]).trimmedNil
            if let name, !isGenericSocialTerm(name) {
                return SocialPlaceSearchHint(name: name, area: area, evidence: evidence)
            }
        }

        guard let hint = PlaceImportParser.manualHint(from: value),
              !isGenericSocialTerm(hint.name)
        else { return nil }
        value = hint.name
        return SocialPlaceSearchHint(name: value, area: hint.area, evidence: evidence)
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
        if let existingIndex = output.firstIndex(where: {
            normalized($0.name) + "|" + normalized($0.area ?? "") == key
        }) {
            if hint.evidence.trustRank > output[existingIndex].evidence.trustRank {
                output[existingIndex] = hint
            }
            return
        }
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

    private static func isAttributionPhrase(_ value: String) -> Bool {
        let phrase = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(phrase.startIndex..<phrase.endIndex, in: phrase)
        return attributionPatterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
            return expression.firstMatch(in: phrase, range: range) != nil
        }
    }

    private static func postWideArea(from metadata: SocialImportMetadata) -> String? {
        // Post-wide geography must come from post-level author copy. A state that only
        // appears in one carousel slide cannot safely constrain every other slide.
        let evidence = metadata.primaryEvidenceText
        let stateCodes = PlaceImportGeography.mentionedStateCodes(in: evidence).filter { stateCode in
            guard let stateName = PlaceImportGeography.canonicalStateName(for: stateCode) else {
                return false
            }
            return stateParticipatesInTravelContext(stateName, evidence: evidence)
        }
        guard stateCodes.count == 1, let stateCode = stateCodes.first else { return nil }
        return PlaceImportGeography.canonicalStateName(for: stateCode)
    }

    private static func stateParticipatesInTravelContext(
        _ stateName: String,
        evidence: String
    ) -> Bool {
        let state = NSRegularExpression.escapedPattern(for: stateName)
        let contextualStateEnd = #"(?:['’]s)?(?=\s*(?:[.!?,;:#]|$|\b(?:again|and|across|during|for|from|in|next|on|this|through|today|tomorrow|to|with)\b))"#
        let patterns = [
            #"(?i)\b(?:road\s+trip|trip|travel(?:ing|ling)?|journey|tour|adventure|itinerary|guide)\b[^\n.!?]{0,70}?\b(?:through|to|in|around|across|for)\s+(?:the\s+)?(?:[a-z'’-]+\s+){0,3}\b"#
                + state + contextualStateEnd,
            #"(?i)\b(?:explore|exploring|visit|visiting|touring)\s+(?:the\s+)?"#
                + state + contextualStateEnd,
            #"(?im)^\s*"# + state
                + #"(?:['’]s)?[\s:—-]+(?:travel|road\s+trip|trip|adventure|itinerary|guide)\b"#
        ]
        let range = NSRange(evidence.startIndex..<evidence.endIndex, in: evidence)
        return patterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
            return expression.firstMatch(in: evidence, range: range) != nil
        }
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

    private static let itineraryPattern = #"(?i)\b(?:called|at|visited|visit|trying|place is)\s+(@?[^#\n.!?]{3,90}?)(?=\s+(?:and|then|afterwards?)[^#\n.!?]{0,60}\b(?:at|from|visited|visit)\s+|[#\n.!?]|$)"#

    private static let acquisitionPattern = #"(?i)\b(?:grab|grabbing|get|getting|order|ordering|buy|buying|pick(?:ed|ing)?\s+up|rent|renting|eat|eating|drink|drinking|try|trying)\b[^#\n.!?]{0,70}?\bfrom\s+(@?[^#\n.!?]{3,90}?)(?=[#\n.!?]|$)"#

    private static let attributionPatterns = [
        #"^(?:(?:the|a|an)\s+)?(?:creator|creators|founder|founders|owner|owners)\s+of\b"#,
        #"^(?:(?:the|a|an)\s+)?team\s+(?:behind|from)\b"#,
        #"^(?:(?:the|a|an)\s+)?veterans?\s+of\b"#,
        #"^(?:my|our|a|an|the)\s+friends?\b"#,
        #"^friends?\s+(?:behind|from|of|who)\b"#
    ]

    private static let strongPlaceDesignators: Set<String> = [
        "aquarium", "bakery", "beach", "brewery", "brewing", "falls", "farms",
        "gallery", "garden", "gardens", "gorge", "hotel", "inn", "lake", "lakes",
        "lodge", "market", "mercantile", "mountain", "mountains", "museum", "observatory",
        "overlook", "park", "petroglyph", "petroglyphs", "plaza", "range", "resort",
        "river", "shrine", "springs", "store", "supply", "temple", "theater", "theatre",
        "tower", "trail", "zoo"
    ]

    private static let weakPlaceDesignators: Set<String> = [
        "bar", "cafe", "coffee", "deli", "eatery", "grill", "kitchen", "restaurant"
    ]

    private static let mediaActionWords: Set<String> = [
        "admiring", "adventure", "at", "because", "finish", "fishing", "grab", "hike",
        "make", "may", "off", "road", "stay", "through", "trip", "you", "your"
    ]

    private static let mediaGenericWords: Set<String> = [
        "a", "an", "and", "big", "coffee", "cream", "food", "gourmet", "home", "ice",
        "local", "new", "of", "place", "shop", "spot", "the"
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
