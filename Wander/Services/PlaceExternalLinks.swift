import Foundation

struct PlaceExternalAction: Identifiable, Equatable {
    enum Kind: String {
        case website
        case call
        case order
        case reserve
        case menu
        case deliverySearch
        case reservationSearch
        case directions
    }

    let kind: Kind
    let title: String
    let systemImage: String
    let url: URL

    var id: String {
        "\(kind.rawValue)|\(url.absoluteString)"
    }
}

enum PlaceExternalLinks {
    typealias ReservationPageLoader = @Sendable (URLRequest) async throws -> (Data, URL?)

    static func websiteURL(from rawValue: String?) -> URL? {
        guard let rawValue = trimmed(rawValue) else { return nil }

        let candidate = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let url = components.url
        else {
            return nil
        }
        return url
    }

    static func callURL(phoneNumber: String?) -> URL? {
        guard let phoneNumber = trimmed(phoneNumber) else { return nil }

        let allowed = CharacterSet(charactersIn: "+0123456789")
        let sanitized = phoneNumber
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()

        let digitCount = sanitized.filter(\.isNumber).count
        guard digitCount >= 3,
              digitCount <= 20,
              sanitized.first != "+"
                  || sanitized.dropFirst().allSatisfy(\.isNumber)
        else {
            return nil
        }

        return URL(string: "tel:\(sanitized)")
    }

    static func visibleBusinessActions(
        websiteURLString: String?,
        phoneNumber: String?,
        actionLinksJSON: String?
    ) -> [PlaceExternalAction] {
        var actions: [PlaceExternalAction] = []

        if let website = websiteURL(from: websiteURLString) {
            actions.append(
                PlaceExternalAction(kind: .website, title: "Website", systemImage: "globe", url: website)
            )
        }

        if let call = callURL(phoneNumber: phoneNumber) {
            actions.append(
                PlaceExternalAction(kind: .call, title: "Call", systemImage: "phone.fill", url: call)
            )
        }

        actions.append(contentsOf: PlaceActionLink.decode(actionLinksJSON).compactMap(action(from:)))
        return deduped(actions)
    }

    static func googleMapsDirectionsURL(
        placeName: String,
        latitude: Double,
        longitude: Double
    ) -> URL? {
        guard isValid(latitude: latitude, longitude: longitude) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/maps/dir/"
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(latitude),\(longitude)")
        ]
        return components.url
    }

    static func googleMapsSearchURL(
        placeName: String,
        address: String? = nil,
        locality: String? = nil
    ) -> URL? {
        let query = [
            trimmed(placeName),
            trimmed(address),
            trimmed(locality)
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")

        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/maps/search/"
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query)
        ]
        return components.url
    }

    static func reservationAction(actionLinksJSON: String?) -> PlaceExternalAction? {
        for link in PlaceActionLink.decode(actionLinksJSON)
        where link.kind == .reserve && link.confidence == .exact {
            guard let url = websiteURL(from: link.urlString),
                  let action = reservationAction(url: url)
            else {
                continue
            }
            return action
        }

        return nil
    }

    static func discoverReservationAction(
        actionLinksJSON: String?,
        websiteURLString: String?,
        pageLoader: ReservationPageLoader? = nil
    ) async -> PlaceExternalAction? {
        if let knownAction = reservationAction(actionLinksJSON: actionLinksJSON) {
            return knownAction
        }

        guard let websiteURL = safeReservationDiscoveryWebsite(from: websiteURLString) else {
            return nil
        }
        if let directAction = reservationAction(url: websiteURL) {
            return directAction
        }

        let loader = pageLoader ?? loadReservationPage
        guard let homePage = try? await loader(reservationRequest(for: websiteURL)) else {
            return nil
        }
        let homePageURL = homePage.1 ?? websiteURL
        if let redirectedAction = reservationAction(url: homePageURL) {
            return redirectedAction
        }

        let homeHTML = decodedHTML(from: homePage.0)
        if let providerAction = firstDirectReservationAction(in: homeHTML, relativeTo: homePageURL) {
            return providerAction
        }

        let reservationPages = linkedURLs(in: homeHTML, relativeTo: homePageURL)
            .filter {
                $0.scheme?.lowercased() == "https"
                    && isSameWebsite($0, as: homePageURL)
                    && looksLikeReservationPage($0)
            }
            .prefix(2)

        for reservationPageURL in reservationPages {
            guard !Task.isCancelled,
                  let reservationPage = try? await loader(reservationRequest(for: reservationPageURL))
            else {
                continue
            }
            let finalURL = reservationPage.1 ?? reservationPageURL
            if let redirectedAction = reservationAction(url: finalURL) {
                return redirectedAction
            }
            let reservationHTML = decodedHTML(from: reservationPage.0)
            if let providerAction = firstDirectReservationAction(in: reservationHTML, relativeTo: finalURL) {
                return providerAction
            }
        }

        return nil
    }

    static func reservationAction(url: URL?) -> PlaceExternalAction? {
        guard let url,
              let secureURL = secureReservationProviderURL(from: url),
              isDirectReservationProviderURL(secureURL)
        else { return nil }
        return PlaceExternalAction(
            kind: .reserve,
            title: "Reservation",
            systemImage: "calendar",
            url: secureURL
        )
    }

    static func shareSummary(placeName: String, locality: String?, status: PlaceStatus?) -> String {
        let placeLine = [
            trimmed(placeName),
            trimmed(locality)
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")

        guard let status else { return placeLine }
        return "\(placeLine) · \(status.displayTitle)"
    }

    static func directionsAction(placeName: String, latitude: Double, longitude: Double) -> PlaceExternalAction? {
        guard let url = googleMapsDirectionsURL(placeName: placeName, latitude: latitude, longitude: longitude) else { return nil }
        return PlaceExternalAction(kind: .directions, title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill", url: url)
    }

    private static func action(from link: PlaceActionLink) -> PlaceExternalAction? {
        guard let url = websiteURL(from: link.urlString) else { return nil }

        switch (link.kind, link.confidence) {
        case (.order, .exact):
            return PlaceExternalAction(kind: .order, title: actionTitle(link.title, fallback: "Order"), systemImage: "bag.fill", url: url)
        case (.reserve, .exact):
            return PlaceExternalAction(kind: .reserve, title: actionTitle(link.title, fallback: "Reserve"), systemImage: "calendar.badge.plus", url: url)
        case (.menu, .exact):
            return PlaceExternalAction(kind: .menu, title: actionTitle(link.title, fallback: "Menu"), systemImage: "menucard.fill", url: url)
        case (.deliverySearch, _), (.order, .search):
            return PlaceExternalAction(kind: .deliverySearch, title: "Find delivery", systemImage: "magnifyingglass", url: url)
        case (.reservationSearch, _), (.reserve, .search):
            return PlaceExternalAction(kind: .reservationSearch, title: "Find reservations", systemImage: "magnifyingglass", url: url)
        case (.website, _):
            return PlaceExternalAction(kind: .website, title: actionTitle(link.title, fallback: "Website"), systemImage: "globe", url: url)
        case (.menu, .search):
            return PlaceExternalAction(kind: .deliverySearch, title: "Find menu", systemImage: "magnifyingglass", url: url)
        }
    }

    private static func actionTitle(_ title: String, fallback: String) -> String {
        trimmed(title) ?? fallback
    }

    private static func loadReservationPage(_ request: URLRequest) async throws -> (Data, URL?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse {
            guard (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased()
            guard contentType == nil || contentType?.contains("text/html") == true else {
                throw URLError(.cannotDecodeContentData)
            }
        }
        return (Data(data.prefix(750_000)), response.url)
    }

    private static func reservationRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("rec.me reservation link resolver", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func safeReservationDiscoveryWebsite(from rawValue: String?) -> URL? {
        guard let url = websiteURL(from: rawValue),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host != "localhost",
              !host.hasSuffix(".local"),
              !host.contains(":")
        else {
            return nil
        }

        let hostParts = host.split(separator: ".")
        let isIPv4Address = hostParts.count == 4 && hostParts.allSatisfy { Int($0) != nil }
        return isIPv4Address ? nil : url
    }

    private static func decodedHTML(from data: Data) -> String {
        let html = String(decoding: data, as: UTF8.self)
        return html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    private static func firstDirectReservationAction(
        in html: String,
        relativeTo baseURL: URL
    ) -> PlaceExternalAction? {
        for url in linkedURLs(in: html, relativeTo: baseURL) {
            if let action = reservationAction(url: url) {
                return action
            }
        }
        return nil
    }

    private static func linkedURLs(in html: String, relativeTo baseURL: URL) -> [URL] {
        let patterns = [
            #"(?i)\bhref\s*=\s*["']([^"']+)["']"#,
            #"(?i)https?://[^\s"'<>]+"#
        ]
        var urls: [URL] = []
        var seen = Set<String>()

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in expression.matches(in: html, range: range) {
                let captureIndex = match.numberOfRanges > 1 ? 1 : 0
                guard let matchRange = Range(match.range(at: captureIndex), in: html) else { continue }
                let rawValue = String(html[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,;"))
                guard let url = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false
                else {
                    continue
                }
                let key = url.absoluteString.lowercased()
                if seen.insert(key).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private static func isSameWebsite(_ lhs: URL, as rhs: URL) -> Bool {
        normalizedWebsiteHost(lhs.host) == normalizedWebsiteHost(rhs.host)
    }

    private static func normalizedWebsiteHost(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    private static func looksLikeReservationPage(_ url: URL) -> Bool {
        let value = [url.path, url.query, url.fragment]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return ["reservation", "reserve", "booking", "book-a-table", "bookatable"]
            .contains { value.contains($0) }
    }

    private static func isDirectReservationProviderURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if matches(host: host, domain: "resy.com") {
            if let venuesIndex = pathComponents.firstIndex(of: "venues"),
               pathComponents.indices.contains(pathComponents.index(after: venuesIndex)) {
                return true
            }
            if pathComponents.first == "cities",
               pathComponents.count == 3,
               let venueSlug = pathComponents.last,
               !["search", "collections", "events", "guides"].contains(venueSlug) {
                return true
            }
            let providerValue = [url.query, url.fragment]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return providerValue.contains("venue_id=")
                || providerValue.contains("venueid=")
                || providerValue.contains("/venues/")
        }

        let openTableDomains = [
            "opentable.com",
            "opentable.ca",
            "opentable.co.uk",
            "opentable.com.au",
            "opentable.de",
            "opentable.ie",
            "opentable.jp",
            "opentable.nl"
        ]
        guard openTableDomains.contains(where: { matches(host: host, domain: $0) }) else {
            return false
        }

        if pathComponents.first == "r", pathComponents.count >= 2 {
            return true
        }

        guard pathComponents.first != "s",
              pathComponents.first != "search",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }

        return components.queryItems?.contains { item in
            item.name.caseInsensitiveCompare("rid") == .orderedSame
                || item.name.caseInsensitiveCompare("restref") == .orderedSame
        } == true
    }

    private static func secureReservationProviderURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedReservationProviderHost(host)
        else { return nil }

        if url.scheme?.lowercased() == "https" {
            return url
        }
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func isSupportedReservationProviderHost(_ host: String) -> Bool {
        matches(host: host, domain: "resy.com") || [
            "opentable.com",
            "opentable.ca",
            "opentable.co.uk",
            "opentable.com.au",
            "opentable.de",
            "opentable.ie",
            "opentable.jp",
            "opentable.nl"
        ].contains(where: { matches(host: host, domain: $0) })
    }

    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    private static func deduped(_ actions: [PlaceExternalAction]) -> [PlaceExternalAction] {
        var seen = Set<String>()
        var deduped: [PlaceExternalAction] = []

        for action in actions {
            let key = action.url.absoluteString.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(action)
        }

        return deduped
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func isValid(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
