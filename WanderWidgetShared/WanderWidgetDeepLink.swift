import Foundation

enum WanderDeepLinkRoute: Equatable, Sendable {
    case quickCapture
    case quickSearch(query: String?)
    case profileCalendar
    case sharedProfile(profileID: String)

    var url: URL? {
        switch self {
        case .quickCapture:
            WanderWidgetConstants.quickCaptureURL
        case .quickSearch(let query):
            Self.quickSearchURL(query: query)
        case .profileCalendar:
            WanderWidgetConstants.profileCalendarURL
        case .sharedProfile(let profileID):
            Self.sharedProfileURL(profileID: profileID)
        }
    }

    static func parse(_ url: URL) -> Self? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "recme",
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil
        else {
            return nil
        }

        let pathSegments = Self.pathSegments(from: components)

        switch (host, pathSegments) {
        case ("add", ["here-now"]):
            guard hasNoQuery(in: components) else { return nil }
            return .quickCapture

        case ("map", ["search"]):
            guard let query = searchQuery(in: components) else { return nil }
            return .quickSearch(query: query)

        case ("profile", ["calendar"]):
            guard hasNoQuery(in: components) else { return nil }
            return .profileCalendar

        case ("profiles", let segments):
            guard segments.count == 1,
                  let profileID = segments.first,
                  hasNoQuery(in: components),
                  !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return .sharedProfile(profileID: profileID)

        default:
            return nil
        }
    }

    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return allowed
    }()

    private static func quickSearchURL(query: String?) -> URL {
        guard let query = normalizedQuery(query) else {
            return WanderWidgetConstants.quickSearchURL
        }

        var components = baseComponents(host: "map", path: "/search")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }

    private static func sharedProfileURL(profileID: String) -> URL? {
        guard !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encodedID = profileID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
        else {
            return nil
        }

        var components = baseComponents(host: "profiles", path: "")
        components.percentEncodedPath = "/\(encodedID)"
        return components.url
    }

    private static func baseComponents(host: String, path: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = "recme"
        components.host = host
        components.path = path
        return components
    }

    private static func normalizedQuery(_ query: String?) -> String? {
        guard let query else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func pathSegments(from components: URLComponents) -> [String] {
        guard components.percentEncodedPath.hasPrefix("/") else { return [] }
        let encodedSegments = components.percentEncodedPath
            .dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)
        guard !encodedSegments.isEmpty else { return [] }

        var segments: [String] = []
        for encodedSegment in encodedSegments {
            guard !encodedSegment.isEmpty,
                  let segment = String(encodedSegment).removingPercentEncoding
            else {
                return []
            }
            segments.append(segment)
        }
        return segments
    }

    private static func hasNoQuery(in components: URLComponents) -> Bool {
        components.percentEncodedQuery == nil
    }

    private static func searchQuery(in components: URLComponents) -> String?? {
        guard components.percentEncodedQuery != "" else { return nil }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ $0.name == "q" }), items.count <= 1 else {
            return nil
        }
        return .some(normalizedQuery(items.first?.value))
    }
}
