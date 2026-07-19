import Foundation

struct PlaceImportHTTPResponse {
    let data: Data
    let finalURL: URL
    let statusCode: Int
    let mimeType: String?
}

@MainActor
protocol PlaceImportHTTPFetching {
    func response(for request: URLRequest) async throws -> PlaceImportHTTPResponse
}

@MainActor
final class URLSessionPlaceImportHTTPClient: PlaceImportHTTPFetching {
    func response(for request: URLRequest) async throws -> PlaceImportHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url
        else {
            throw URLError(.badServerResponse)
        }
        return PlaceImportHTTPResponse(
            data: data,
            finalURL: finalURL,
            statusCode: httpResponse.statusCode,
            mimeType: httpResponse.mimeType
        )
    }
}

struct GoogleMapsSharedList: Equatable {
    let name: String
    let seeds: [PlaceImportSeed]
}

enum GoogleMapsSharedListLoadResult: Equatable {
    case list(GoogleMapsSharedList)
    case singlePlace(expandedURLString: String)
    case unavailable(String)
}

@MainActor
protocol GoogleMapsSharedListLoading {
    func load(from url: URL) async -> GoogleMapsSharedListLoadResult
}

@MainActor
final class GoogleMapsSharedListImporter: GoogleMapsSharedListLoading {
    private let httpClient: any PlaceImportHTTPFetching

    init(httpClient: any PlaceImportHTTPFetching = URLSessionPlaceImportHTTPClient()) {
        self.httpClient = httpClient
    }

    func load(from url: URL) async -> GoogleMapsSharedListLoadResult {
        guard Self.isGoogleMapsURL(url) else {
            return .singlePlace(expandedURLString: url.absoluteString)
        }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = "GET"
            request.setValue("rec.me public list importer", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

            let page = try await httpClient.response(for: request)
            guard (200..<400).contains(page.statusCode), page.data.count <= 4_000_000 else {
                return .unavailable(Self.unavailableMessage)
            }

            let html = String(data: page.data, encoding: .utf8) ?? ""
            let endpoint = Self.listID(in: page.finalURL).flatMap(Self.listEndpoint)
                ?? Self.preloadedListEndpoint(in: html)

            guard let endpoint else {
                if Self.isListShapedURL(page.finalURL) || Self.isListShapedURL(url) {
                    return .unavailable(Self.unavailableMessage)
                }
                return .singlePlace(expandedURLString: page.finalURL.absoluteString)
            }

            var listRequest = URLRequest(
                url: endpoint,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            listRequest.httpMethod = "GET"
            listRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            listRequest.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")

            let payload = try await httpClient.response(for: listRequest)
            guard (200..<300).contains(payload.statusCode), payload.data.count <= 20_000_000 else {
                return .unavailable(Self.unavailableMessage)
            }
            return .list(try GoogleMapsSharedListParser.parse(payload.data))
        } catch {
            return .unavailable(Self.unavailableMessage)
        }
    }

    private static let unavailableMessage =
        "This Google Maps list could not be read. Make sure anyone with the link can view it, then retry."

    private static func isGoogleMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.app.goo.gl"
            || host == "goo.gl"
            || host == "g.co"
            || host == "google.com"
            || host.hasSuffix(".google.com")
    }

    private static func isListShapedURL(_ url: URL) -> Bool {
        listID(in: url) != nil
    }

    private static func listID(in url: URL) -> String? {
        let value = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let patterns = [
            #"/placelists/list/([A-Za-z0-9_-]+)"#,
            #"!11m2!2s([A-Za-z0-9_-]+)!3e3"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = expression.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: value)
            else { continue }
            return String(value[valueRange])
        }
        return nil
    }

    private static func preloadedListEndpoint(in html: String) -> URL? {
        let pattern = #"href=\"([^\"]*entitylist/getlist[^\"]*)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }

        var value = String(html[valueRange])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        if value.hasPrefix("/") {
            value = "https://www.google.com\(value)"
        }
        return URL(string: value)
    }

    private static func listEndpoint(for listID: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/preview/entitylist/getlist")
        components?.queryItems = [
            URLQueryItem(name: "authuser", value: "0"),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "us"),
            URLQueryItem(
                name: "pb",
                value: "!1m4!1s\(listID)!2e1!3m1!1e1!2e2!3e2!4i1000"
            )
        ]
        return components?.url
    }
}

enum GoogleMapsSharedListParsingError: Error, Equatable {
    case invalidPayload
    case emptyList
}

enum GoogleMapsSharedListParser {
    static func parse(_ data: Data) throws -> GoogleMapsSharedList {
        guard var raw = String(data: data, encoding: .utf8),
              let firstArray = raw.firstIndex(of: "[")
        else {
            throw GoogleMapsSharedListParsingError.invalidPayload
        }
        raw = String(raw[firstArray...])
        guard let jsonData = raw.data(using: .utf8),
              let outer = try JSONSerialization.jsonObject(with: jsonData) as? [Any],
              let root = outer.first as? [Any],
              root.indices.contains(8),
              let entries = root[8] as? [Any]
        else {
            throw GoogleMapsSharedListParsingError.invalidPayload
        }

        let listName = string(at: 4, in: root) ?? "Google Maps list"
        var seen = Set<String>()
        var seeds: [PlaceImportSeed] = []

        for (offset, rawEntry) in entries.enumerated() {
            guard let entry = rawEntry as? [Any],
                  let name = string(at: 2, in: entry)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { continue }

            let placeInfo = array(at: 1, in: entry)
            let address = placeInfo.flatMap { string(at: 4, in: $0) ?? string(at: 2, in: $0) }
            let coordinates = placeInfo.flatMap { array(at: 5, in: $0) }
            let latitude = coordinates.flatMap { number(at: 2, in: $0) }
            let longitude = coordinates.flatMap { number(at: 3, in: $0) }
            let placeID = placeInfo.flatMap { string(at: 7, in: $0) }
            let note = string(at: 3, in: entry)
            let fallbackIdentity = [
                name,
                address ?? "",
                latitude.map { String($0) } ?? "",
                longitude.map { String($0) } ?? ""
            ]
                .joined(separator: "|")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let identity = placeID ?? fallbackIdentity
            guard seen.insert(identity).inserted else { continue }

            let sourceURLString = placeID.map {
                "https://www.google.com/maps/place/?q=place_id:\($0)"
            }
            let rawText = [name, address, note]
                .compactMap { value -> String? in
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !value.isEmpty
                    else { return nil }
                    return value
                }
                .joined(separator: " | ")

            seeds.append(
                PlaceImportSeed(
                    rawText: rawText,
                    nameHint: name,
                    areaHint: address,
                    sourceURLString: sourceURLString,
                    sourceLine: offset + 1,
                    latitude: latitude,
                    longitude: longitude,
                    sourceProvider: placeID == nil ? nil : "google_maps",
                    sourceProviderPlaceID: placeID
                )
            )
        }

        guard !seeds.isEmpty else {
            throw GoogleMapsSharedListParsingError.emptyList
        }
        return GoogleMapsSharedList(name: listName, seeds: seeds)
    }

    private static func array(at index: Int, in array: [Any]) -> [Any]? {
        guard array.indices.contains(index) else { return nil }
        return array[index] as? [Any]
    }

    private static func string(at index: Int, in array: [Any]) -> String? {
        guard array.indices.contains(index) else { return nil }
        return array[index] as? String
    }

    private static func number(at index: Int, in array: [Any]) -> Double? {
        guard array.indices.contains(index) else { return nil }
        return (array[index] as? NSNumber)?.doubleValue
    }
}
