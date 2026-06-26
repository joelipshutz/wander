import Foundation

struct LinkPlaceParser {
    func manualInput(from input: LinkPlaceInput) -> ManualPlaceInput? {
        let rawValue = input.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }

        guard let url = URL(string: rawValue),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased()
        else {
            return ManualPlaceInput(name: rawValue, areaHint: nil, category: nil)
        }

        if let queryValue = queryPlaceName(from: components) {
            return ManualPlaceInput(name: queryValue, areaHint: areaHint(from: components), category: nil)
        }

        if isGoogleMapsHost(host) || isAppleMapsHost(host) {
            return mapPathInput(from: components)
        }

        if isInstagramLocationURL(host: host, components: components) {
            return instagramLocationInput(from: components)
        }

        if isInstagramHost(host) {
            return instagramProfileInput(from: components)
        }

        return nil
    }

    func isShortMapLink(_ input: LinkPlaceInput) -> Bool {
        let rawValue = input.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawValue),
              let host = url.host?.lowercased()
        else {
            return false
        }

        return host == "maps.app.goo.gl"
            || host == "goo.gl"
            || host == "g.co"
            || host == "maps.apple"
            || host == "maps.google.com" && url.path.lowercased().contains("/maps")
    }

    private func queryPlaceName(from components: URLComponents) -> String? {
        let preferredKeys = ["q", "query", "name", "title", "place", "destination", "daddr", "address"]
        return firstQueryValue(in: components, keys: preferredKeys)
            ?? appleMapsAddressValue(in: components.queryItems ?? []).flatMap(cleanedPlaceText)
            ?? appleMapsPathName(from: components)
    }

    private func areaHint(from components: URLComponents) -> String? {
        firstAreaHint(in: components, keys: ["near", "ll", "sll", "center", "coordinate"])
    }

    private func firstQueryValue(in components: URLComponents, keys: [String]) -> String? {
        let items = components.queryItems ?? []

        for key in keys {
            guard let value = items.first(where: { $0.name.lowercased() == key })?.value,
                  let cleaned = cleanedPlaceText(value)
            else {
                continue
            }
            return cleaned
        }

        return nil
    }

    private func firstAreaHint(in components: URLComponents, keys: [String]) -> String? {
        let items = components.queryItems ?? []

        for key in keys {
            guard let value = items.first(where: { $0.name.lowercased() == key })?.value else {
                continue
            }

            let decoded = value.removingPercentEncoding ?? value
            let trimmed = decoded
                .replacingOccurrences(of: "+", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func appleMapsAddressValue(in items: [URLQueryItem]) -> String? {
        let mapAddressKeys = ["auid", "address", "q", "name", "title"]

        for item in items {
            let name = item.name.lowercased()
            guard name.hasPrefix(mapAddressKeys[0]) == false,
                  mapAddressKeys.contains(where: { name.contains($0) }),
                  let value = item.value,
                  value.range(of: "[A-Za-z]", options: .regularExpression) != nil
            else {
                continue
            }
            return value
        }

        return nil
    }

    private func appleMapsPathName(from components: URLComponents) -> String? {
        let pieces = normalizedPathPieces(from: components)
        guard let index = pieces.firstIndex(where: { $0.lowercased() == "place" }),
              pieces.indices.contains(index + 1)
        else { return nil }

        return cleanedPlaceText(pieces[index + 1])
    }

    private func mapPathInput(from components: URLComponents) -> ManualPlaceInput? {
        let pieces = normalizedPathPieces(from: components)
        guard let index = pieces.firstIndex(where: { ["place", "search"].contains($0.lowercased()) }),
              pieces.indices.contains(index + 1),
              let name = cleanedPlaceText(pieces[index + 1])
        else {
            return nil
        }

        return ManualPlaceInput(name: name, areaHint: nil, category: nil)
    }

    private func instagramLocationInput(from components: URLComponents) -> ManualPlaceInput? {
        let pieces = normalizedPathPieces(from: components)
        guard let index = pieces.firstIndex(where: { $0.lowercased() == "locations" }),
              pieces.indices.contains(index + 2),
              let name = cleanedPlaceText(pieces[index + 2])
        else {
            return nil
        }

        return ManualPlaceInput(name: name, areaHint: nil, category: nil)
    }

    private func instagramProfileInput(from components: URLComponents) -> ManualPlaceInput? {
        let pieces = normalizedPathPieces(from: components)
        guard pieces.count == 1,
              let username = pieces.first,
              isReservedInstagramPath(username) == false,
              let name = cleanedPlaceText(username)
        else {
            return nil
        }

        return ManualPlaceInput(name: name, areaHint: nil, category: nil)
    }

    private func normalizedPathPieces(from components: URLComponents) -> [String] {
        components.path
            .split(separator: "/")
            .map(String.init)
            .compactMap { piece -> String? in
                guard !piece.hasPrefix("@"), !piece.hasPrefix("data=") else { return nil }
                return piece.removingPercentEncoding ?? piece
            }
    }

    private func isGoogleMapsHost(_ host: String) -> Bool {
        host == "maps.google.com" || host.contains(".google.") || host == "google.com"
    }

    private func isAppleMapsHost(_ host: String) -> Bool {
        host == "maps.apple.com"
    }

    private func isInstagramLocationURL(host: String, components: URLComponents) -> Bool {
        isInstagramHost(host)
            ? components.path.lowercased().contains("/explore/locations/")
            : false
    }

    private func isInstagramHost(_ host: String) -> Bool {
        host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    private func isReservedInstagramPath(_ value: String) -> Bool {
        let reservedPaths: Set<String> = [
            "about",
            "accounts",
            "api",
            "developer",
            "direct",
            "explore",
            "legal",
            "oauth",
            "p",
            "privacy",
            "reel",
            "reels",
            "stories",
            "terms",
            "tv"
        ]
        return reservedPaths.contains(value.lowercased())
    }

    private func cleanedPlaceText(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        let trimmed = decoded
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("@"),
              !trimmed.contains("!"),
              !isLikelyCoordinate(trimmed)
        else {
            return nil
        }

        return trimmed
    }

    private func isLikelyCoordinate(_ value: String) -> Bool {
        let pattern = #"^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
