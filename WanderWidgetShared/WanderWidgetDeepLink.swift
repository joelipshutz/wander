import Foundation

struct WanderCalendarDate: Equatable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )
        guard let date = calendar.date(from: components) else { return nil }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year,
              validated.month == month,
              validated.day == day
        else {
            return nil
        }

        self.year = year
        self.month = month
        self.day = day
    }

    init?(urlValue: String) {
        let parts = urlValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    var urlValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )
    }
}

enum WanderDeepLinkRoute: Equatable, Sendable {
    case quickCapture
    case addSearch(query: String)
    case map
    case quickSearch(query: String?)
    case nearbyPlace(candidateID: String)
    case profileCalendar
    case profileCalendarDate(WanderCalendarDate)
    case sharedProfile(profileID: String)
    case sharedPlace(placeID: String)
    case sharedActivity(activityID: String)
    case sharedList(listID: String)
    case listInvite(token: String)

    var url: URL? {
        switch self {
        case .quickCapture:
            WanderWidgetConstants.quickCaptureURL
        case .addSearch(let query):
            Self.addSearchURL(query: query)
        case .map:
            WanderWidgetConstants.mapURL
        case .quickSearch(let query):
            Self.quickSearchURL(query: query)
        case .nearbyPlace(let candidateID):
            Self.nearbyPlaceURL(candidateID: candidateID)
        case .profileCalendar:
            WanderWidgetConstants.profileCalendarURL
        case .profileCalendarDate(let date):
            Self.profileCalendarDateURL(date)
        case .sharedProfile(let profileID):
            Self.sharedEntityURL(root: "profiles", identifier: profileID)
        case .sharedPlace(let placeID):
            Self.sharedEntityURL(root: "places", identifier: placeID)
        case .sharedActivity(let activityID):
            Self.sharedEntityURL(root: "activities", identifier: activityID)
        case .sharedList(let listID):
            Self.sharedEntityURL(root: "lists", identifier: listID)
        case .listInvite(let token):
            Self.sharedEntityURL(root: "invites", identifier: token)
        }
    }

    static func parse(_ url: URL) -> Self? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil
        else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "recme":
            guard let host = components.host?.lowercased() else { return nil }
            return parseAppURL(host: host, components: components)
        case "https":
            guard components.host?.lowercased() == "getrec.me" else { return nil }
            return parseUniversalLink(components: components)
        default:
            return nil
        }
    }

    private static func parseAppURL(
        host: String,
        components: URLComponents
    ) -> Self? {
        let pathSegments = Self.pathSegments(from: components)

        switch (host, pathSegments) {
        case ("add", ["here-now"]):
            guard hasNoQuery(in: components) else { return nil }
            return .quickCapture

        case ("add", ["search"]):
            guard let wrappedQuery = searchQuery(in: components),
                  let query = wrappedQuery
            else { return nil }
            return .addSearch(query: query)

        case ("map", []):
            guard hasNoQuery(in: components) else { return nil }
            return .map

        case ("map", ["search"]):
            guard let query = searchQuery(in: components) else { return nil }
            return .quickSearch(query: query)

        case ("add", let segments)
            where segments.count == 2 && segments[0] == "nearby":
            let candidateID = segments[1]
            guard hasNoQuery(in: components),
                  !candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return .nearbyPlace(candidateID: candidateID)

        case ("profile", ["calendar"]):
            guard hasNoQuery(in: components) else { return nil }
            return .profileCalendar

        case ("profile", let segments)
            where segments.count == 2 && segments[0] == "calendar":
            let value = segments[1]
            guard hasNoQuery(in: components),
                  let date = WanderCalendarDate(urlValue: value)
            else {
                return nil
            }
            return .profileCalendarDate(date)

        case ("profiles", let segments):
            guard segments.count == 1,
                  let profileID = segments.first,
                  isValidSharedIdentifier(
                    profileID,
                    root: "profiles",
                    components: components
                  )
            else {
                return nil
            }
            return .sharedProfile(profileID: profileID)

        case ("places", let segments):
            guard segments.count == 1,
                  let placeID = segments.first,
                  isValidSharedIdentifier(
                    placeID,
                    root: "places",
                    components: components
                  )
            else {
                return nil
            }
            return .sharedPlace(placeID: placeID)

        case ("activities", let segments):
            guard segments.count == 1,
                  let activityID = segments.first,
                  isValidSharedIdentifier(
                    activityID,
                    root: "activities",
                    components: components
                  )
            else {
                return nil
            }
            return .sharedActivity(activityID: activityID)

        case ("lists", let segments):
            guard segments.count == 1,
                  let listID = segments.first,
                  isValidSharedIdentifier(
                    listID,
                    root: "lists",
                    components: components
                  )
            else {
                return nil
            }
            return .sharedList(listID: listID)

        case ("invites", let segments):
            guard segments.count == 1,
                  let token = segments.first,
                  isValidSharedIdentifier(
                    token,
                    root: "invites",
                    components: components
                  )
            else {
                return nil
            }
            return .listInvite(token: token)

        default:
            return nil
        }
    }

    private static func parseUniversalLink(
        components: URLComponents
    ) -> Self? {
        let segments = pathSegments(from: components)
        guard segments.count == 2,
              let root = segments.first,
              let identifier = segments.last,
              isValidSharedIdentifier(
                identifier,
                root: root,
                components: components
              )
        else {
            return nil
        }

        switch root {
        case "profiles":
            return .sharedProfile(profileID: identifier)
        case "places":
            return .sharedPlace(placeID: identifier)
        case "activities":
            return .sharedActivity(activityID: identifier)
        case "lists":
            return .sharedList(listID: identifier)
        case "invites":
            return .listInvite(token: identifier)
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

    private static func addSearchURL(query: String) -> URL? {
        guard let query = normalizedQuery(query) else { return nil }
        var components = baseComponents(host: "add", path: "/search")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private static func profileCalendarDateURL(_ date: WanderCalendarDate) -> URL {
        baseComponents(host: "profile", path: "/calendar/\(date.urlValue)").url!
    }

    private static func nearbyPlaceURL(candidateID: String) -> URL? {
        guard !candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encodedID = candidateID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
        else {
            return nil
        }

        var components = baseComponents(host: "add", path: "")
        components.percentEncodedPath = "/nearby/\(encodedID)"
        return components.url
    }

    private static func sharedEntityURL(
        root: String,
        identifier: String
    ) -> URL? {
        guard isValidSharedIdentifier(identifier, root: root),
              let encodedID = identifier.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "getrec.me"
        components.percentEncodedPath = "/\(root)/\(encodedID)"
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

    private static func isValidSharedIdentifier(
        _ identifier: String,
        root: String,
        components: URLComponents? = nil
    ) -> Bool {
        guard components.map({ hasNoQuery(in: $0) }) ?? true,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              identifier.utf8.count <= 256
        else {
            return false
        }

        switch root {
        case "profiles":
            return true
        case "places", "activities", "lists":
            return UUID(uuidString: identifier) != nil
        case "invites":
            return identifier.range(
                of: "^[a-fA-F0-9]{48}$",
                options: .regularExpression
            ) != nil
        default:
            return false
        }
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
