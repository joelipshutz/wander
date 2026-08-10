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
        placeName: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        allowsOfficialReservationPageFallback: Bool = false,
        pageLoader: ReservationPageLoader? = nil
    ) async -> PlaceExternalAction? {
        if let knownAction = reservationAction(actionLinksJSON: actionLinksJSON) {
            return knownAction
        }
        if let catalogAction = curatedReservationAction(
            placeName: placeName,
            region: region
        ) {
            return catalogAction
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
        if let providerAction = firstDirectReservationAction(
            in: homeHTML,
            relativeTo: homePageURL,
            placeName: placeName,
            locality: locality,
            region: region
        ) {
            return providerAction
        }
        var naturePortalFallback = allowsOfficialReservationPageFallback
            ? firstNatureReservationPortalAction(in: homeHTML, relativeTo: homePageURL)
            : nil

        let reservationPages = reservationPageURLs(
            in: homeHTML,
            relativeTo: homePageURL,
            includeNatureTerms: allowsOfficialReservationPageFallback
        )
            .filter {
                $0.scheme?.lowercased() == "https"
                    && isSameWebsite($0, as: homePageURL)
            }
            .prefix(3)

        var officialReservationFallback: PlaceExternalAction?

        for reservationPageURL in reservationPages {
            if allowsOfficialReservationPageFallback,
               officialReservationFallback == nil {
                officialReservationFallback = officialReservationAction(url: reservationPageURL)
            }
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
            if let providerAction = firstDirectReservationAction(
                in: reservationHTML,
                relativeTo: finalURL,
                placeName: placeName,
                locality: locality,
                region: region
            ) {
                return providerAction
            }
            if allowsOfficialReservationPageFallback,
               naturePortalFallback == nil {
                naturePortalFallback = firstNatureReservationPortalAction(
                    in: reservationHTML,
                    relativeTo: finalURL
                )
            }
        }

        return naturePortalFallback ?? officialReservationFallback
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
            return reservationAction(url: url)
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
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 6)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("rec.me reservation link resolver", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func safeReservationDiscoveryWebsite(from rawValue: String?) -> URL? {
        guard let rawURL = websiteURL(from: rawValue),
              var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = rawURL.host?.lowercased(),
              !host.isEmpty,
              host != "localhost",
              !host.hasSuffix(".local"),
              !host.contains(":")
        else {
            return nil
        }

        components.scheme = "https"
        guard let url = components.url else { return nil }

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
        relativeTo baseURL: URL,
        placeName: String? = nil,
        locality: String? = nil,
        region: String? = nil
    ) -> PlaceExternalAction? {
        linkedURLCandidates(in: html, relativeTo: baseURL)
            .compactMap { candidate -> (PlaceExternalAction, Int)? in
                guard let action = reservationAction(url: candidate.url) else { return nil }
                return (
                    action,
                    reservationCandidateScore(
                        candidate,
                        placeName: placeName,
                        locality: locality,
                        region: region
                    )
                )
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private struct LinkedURLCandidate {
        let url: URL
        let context: String
    }

    private static func linkedURLCandidates(in html: String, relativeTo baseURL: URL) -> [LinkedURLCandidate] {
        let patterns = [
            #"(?i)\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?i)https?://[^\s\"'<>]+"#
        ]
        let htmlNSString = html as NSString
        var candidates: [LinkedURLCandidate] = []

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: htmlNSString.length)
            for match in expression.matches(in: html, range: range) {
                let captureIndex = match.numberOfRanges > 1 ? 1 : 0
                let rawRange = match.range(at: captureIndex)
                guard rawRange.location != NSNotFound else { continue }
                let rawValue = htmlNSString.substring(with: rawRange)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,;"))
                guard let url = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false
                else { continue }

                let contextStart = max(0, match.range.location - 220)
                let contextEnd = min(htmlNSString.length, NSMaxRange(match.range) + 220)
                let context = htmlNSString
                    .substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                candidates.append(LinkedURLCandidate(url: url, context: context))
            }
        }
        return candidates
    }

    private static func reservationCandidateScore(
        _ candidate: LinkedURLCandidate,
        placeName: String?,
        locality: String?,
        region: String?
    ) -> Int {
        let value = normalizedMatchText("\(candidate.url.absoluteString) \(candidate.context)")
        var score = 0

        if let locality = normalizedMatchPhrase(locality), value.contains(locality) {
            score += 100
        }
        if let region = normalizedMatchPhrase(region), region.count >= 3, value.contains(region) {
            score += 30
        }

        let nameTokens = significantMatchTokens(placeName)
        let matchingNameTokens = nameTokens.filter { value.contains($0) }
        score += matchingNameTokens.count * 5
        if !nameTokens.isEmpty, matchingNameTokens.count == nameTokens.count {
            score += 20
        }
        return score
    }

    private static func normalizedMatchPhrase(_ value: String?) -> String? {
        let normalized = normalizedMatchText(value ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedMatchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func significantMatchTokens(_ value: String?) -> [String] {
        let stopWords: Set<String> = ["and", "bar", "cafe", "restaurant", "the"]
        return normalizedMatchText(value ?? "")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private struct CuratedReservationLink {
        let names: Set<String>
        let regions: Set<String>
        let urlString: String
    }

    private static let curatedReservationLinks: [CuratedReservationLink] = [
        CuratedReservationLink(
            names: ["gjelina"],
            regions: ["ca", "california"],
            urlString: "https://www.opentable.com/gjelina"
        ),
        CuratedReservationLink(
            names: ["rvr"],
            regions: ["ca", "california"],
            urlString: "https://resy.com/cities/los-angeles-ca/venues/rvr"
        ),
        CuratedReservationLink(
            names: ["bestia"],
            regions: ["ca", "california"],
            urlString: "https://www.opentable.com/r/bestia-reservations-los-angeles"
        ),
        CuratedReservationLink(
            names: ["bavel"],
            regions: ["ca", "california"],
            urlString: "https://www.opentable.com/r/bavel-reservations-los-angeles"
        ),
        CuratedReservationLink(
            names: ["girl the goat", "girl and the goat"],
            regions: ["ca", "california"],
            urlString: "https://www.opentable.com/r/girl-and-the-goat-la-reservations-los-angeles"
        ),
        CuratedReservationLink(
            names: ["mother wolf"],
            regions: ["ca", "california"],
            urlString: "https://resy.com/cities/la/mother-wolf"
        ),
        CuratedReservationLink(
            names: ["wawona campground"],
            regions: ["ca", "california"],
            urlString: "https://www.recreation.gov/camping/campgrounds/232446"
        ),
        CuratedReservationLink(
            names: ["pinnacles campground"],
            regions: ["ca", "california"],
            urlString: "https://www.recreation.gov/camping/campgrounds/234015"
        ),
        CuratedReservationLink(
            names: ["convict lake campground"],
            regions: ["ca", "california"],
            urlString: "https://www.recreation.gov/camping/campgrounds/234311"
        )
    ]

    private static func curatedReservationAction(
        placeName: String?,
        region: String?
    ) -> PlaceExternalAction? {
        guard let name = normalizedMatchPhrase(placeName),
              let region = normalizedMatchPhrase(region),
              let match = curatedReservationLinks.first(where: {
                  $0.names.contains(name) && $0.regions.contains(region)
              }),
              let url = URL(string: match.urlString)
        else { return nil }

        return reservationAction(url: url)
    }

    private static func firstNatureReservationPortalAction(
        in html: String,
        relativeTo baseURL: URL
    ) -> PlaceExternalAction? {
        for url in linkedURLs(in: html, relativeTo: baseURL) {
            guard let secureURL = secureNatureReservationPortalURL(from: url) else { continue }
            return PlaceExternalAction(
                kind: .reserve,
                title: "Reservation",
                systemImage: "calendar",
                url: secureURL
            )
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

    private static func reservationPageURLs(
        in html: String,
        relativeTo baseURL: URL,
        includeNatureTerms: Bool
    ) -> [URL] {
        var urls = linkedURLs(in: html, relativeTo: baseURL).filter {
            isLikelyHTMLPageURL($0)
                && looksLikeReservationPage($0, includeNatureTerms: includeNatureTerms)
        }
        var seen = Set(urls.map { $0.absoluteString.lowercased() })

        let anchorPattern = #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
        guard let expression = try? NSRegularExpression(pattern: anchorPattern) else {
            return urls
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html)
            else { continue }

            let linkText = String(html[textRange])
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .lowercased()
            guard containsReservationLanguage(linkText, includeNatureTerms: includeNatureTerms),
                  let url = URL(string: String(html[hrefRange]), relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false
            else { continue }

            let key = url.absoluteString.lowercased()
            if seen.insert(key).inserted {
                urls.append(url)
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

    private static func looksLikeReservationPage(_ url: URL, includeNatureTerms: Bool) -> Bool {
        let value = [url.path, url.query, url.fragment]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return containsReservationLanguage(value, includeNatureTerms: includeNatureTerms)
    }

    private static func containsReservationLanguage(_ value: String, includeNatureTerms: Bool) -> Bool {
        var terms = ["reservation", "reserve", "booking", "book-a-table", "bookatable", "book-now"]
        if includeNatureTerms {
            terms.append(contentsOf: ["camping", "campground", "permit", "timed-entry", "tickets"])
        }
        return terms.contains { value.contains($0) }
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
            "opentable.es",
            "opentable.fr",
            "opentable.hk",
            "opentable.ie",
            "opentable.it",
            "opentable.jp",
            "opentable.nl",
            "opentable.sg",
            "opentable.ae",
            "opentable.co.th",
            "opentable.com.mx",
            "opentable.com.tw"
        ]
        if openTableDomains.contains(where: { matches(host: host, domain: $0) }) {
            if pathComponents.first == "r", pathComponents.count >= 2 {
                return true
            }

            guard pathComponents.first != "s",
                  pathComponents.first != "search",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return false }

            if components.queryItems?.contains(where: { item in
                item.name.caseInsensitiveCompare("rid") == .orderedSame
                    || item.name.caseInsensitiveCompare("restref") == .orderedSame
            }) == true {
                return true
            }

            if pathComponents.count == 1,
               let restaurantSlug = pathComponents.first?.lowercased() {
                let nonRestaurantPaths: Set<String> = [
                    "about", "affiliate", "blog", "business", "concierge", "events",
                    "home", "login", "open", "private-dining", "restaurants",
                    "restaurant-solutions", "s", "search", "start"
                ]
                return restaurantSlug.count >= 2
                    && !nonRestaurantPaths.contains(restaurantSlug)
                    && !restaurantSlug.hasSuffix("-restaurants")
            }

            return false
        }

        return isDirectNatureReservationProviderURL(url)
    }

    private static func isDirectNatureReservationProviderURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        let fragment = url.fragment?.lowercased() ?? ""
        let query = url.query?.lowercased() ?? ""

        if matches(host: host, domain: "recreation.gov") {
            let directPrefixes = [
                "/camping/campgrounds/", "/permits/", "/ticket/facility/",
                "/timed-entry/", "/lottery/", "/tree-permits/"
            ]
            return directPrefixes.contains { path.hasPrefix($0) && path.count > $0.count }
        }

        if matches(host: host, domain: "reserveamerica.com") {
            return path.contains("/camping/")
                || path.contains("/explore/")
                || path.contains("campgrounddetails.do")
                || path.contains("facilitydetails.do")
                || query.contains("parkid=")
        }

        if matches(host: host, domain: "reservecalifornia.com")
            || matches(host: host, domain: "goingtocamp.com") {
            let route = "\(path) \(fragment) \(query)"
            return ["park/", "campground", "facility", "reservation", "reserve"]
                .contains { route.contains($0) }
        }

        let stateReservationDomains = [
            "camping.hawaii.gov",
            "reserve.floridastateparks.org",
            "reservations.gooutdoorsflorida.com"
        ]
        guard stateReservationDomains.contains(where: { matches(host: host, domain: $0) }) else {
            return false
        }
        let route = "\(path) \(fragment) \(query)"
        return !route.trimmingCharacters(in: .whitespaces).isEmpty
            && !route.contains("search")
    }

    private static func officialReservationAction(url: URL) -> PlaceExternalAction? {
        guard url.scheme?.lowercased() == "https",
              isLikelyHTMLPageURL(url),
              looksLikeReservationPage(url, includeNatureTerms: true)
        else { return nil }
        return PlaceExternalAction(
            kind: .reserve,
            title: "Reservation",
            systemImage: "calendar",
            url: url
        )
    }

    private static func secureNatureReservationPortalURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isNatureReservationProviderHost(host),
              isLikelyHTMLPageURL(url),
              !url.path.lowercased().contains("search")
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

    private static func isLikelyHTMLPageURL(_ url: URL) -> Bool {
        let rejectedExtensions: Set<String> = [
            "css", "gif", "ico", "jpeg", "jpg", "js", "json", "pdf", "png",
            "svg", "webp", "xml", "zip"
        ]
        return !rejectedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isNatureReservationProviderHost(_ host: String) -> Bool {
        [
            "recreation.gov",
            "reserveamerica.com",
            "reservecalifornia.com",
            "goingtocamp.com",
            "camping.hawaii.gov",
            "reserve.floridastateparks.org",
            "reservations.gooutdoorsflorida.com"
        ].contains(where: { matches(host: host, domain: $0) })
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
            "opentable.es",
            "opentable.fr",
            "opentable.hk",
            "opentable.ie",
            "opentable.it",
            "opentable.jp",
            "opentable.nl",
            "opentable.sg",
            "opentable.ae",
            "opentable.co.th",
            "opentable.com.mx",
            "opentable.com.tw",
            "recreation.gov",
            "reserveamerica.com",
            "reservecalifornia.com",
            "goingtocamp.com",
            "camping.hawaii.gov",
            "reserve.floridastateparks.org",
            "reservations.gooutdoorsflorida.com"
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
