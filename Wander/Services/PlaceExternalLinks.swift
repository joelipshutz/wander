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
                  isDirectReservationProviderURL(url)
            else {
                continue
            }

            return PlaceExternalAction(
                kind: .reserve,
                title: "Reservation",
                systemImage: "calendar",
                url: url
            )
        }

        return nil
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

    private static func isDirectReservationProviderURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if matches(host: host, domain: "resy.com") {
            guard let venuesIndex = pathComponents.firstIndex(of: "venues") else { return false }
            return pathComponents.indices.contains(pathComponents.index(after: venuesIndex))
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

        guard pathComponents.first == "booking",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }

        return components.queryItems?.contains { item in
            item.name.caseInsensitiveCompare("rid") == .orderedSame
                || item.name.caseInsensitiveCompare("restref") == .orderedSame
        } == true
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
