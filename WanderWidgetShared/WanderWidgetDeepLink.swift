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
    case map
    case quickSearch(query: String?)
    case nearbyPlace(candidateID: String)
    case profileCalendar
    case profileCalendarDate(WanderCalendarDate)
    case sharedProfile(profileID: String)

    var url: URL? {
        switch self {
        case .quickCapture:
            WanderWidgetConstants.quickCaptureURL
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
