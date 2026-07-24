import Foundation

enum ProfileCalendarActivityState: String, Equatable, Hashable {
    case none
    case visit
    case wanna
    case both
}

struct ProfileCalendarDaySummary: Identifiable, Equatable, Hashable {
    let date: Date
    let visitCount: Int
    let wannaCount: Int
    let visitPlaceIDs: [String]
    let wannaPlaceIDs: [String]

    var id: Date { date }

    var state: ProfileCalendarActivityState {
        switch (visitCount > 0, wannaCount > 0) {
        case (true, true): .both
        case (true, false): .visit
        case (false, true): .wanna
        case (false, false): .none
        }
    }

    var placeIDs: [String] {
        Array(Set(visitPlaceIDs).union(wannaPlaceIDs)).sorted()
    }

    static func empty(on date: Date) -> Self {
        ProfileCalendarDaySummary(
            date: date,
            visitCount: 0,
            wannaCount: 0,
            visitPlaceIDs: [],
            wannaPlaceIDs: []
        )
    }
}

struct ProfileInsights: Equatable {
    let month: Date
    let monthDaySummaries: [Date: ProfileCalendarDaySummary]
    let monthVisitCount: Int
    let monthWannaCount: Int
    let monthSpotCount: Int
    let monthCategoryCount: Int
    let monthCityCount: Int
    let mapPoints: [ProfileMapPoint]
    let placeSummaries: [ProfileSummaryItem]
    let citySummaries: [ProfileSummaryItem]
    let countrySummaries: [ProfileSummaryItem]

    var mapCityCount: Int {
        Set(mapPoints.compactMap { CityCanonicalizer.comparisonKey($0.city) }).count
    }

    var monthVisitCounts: [Date: Int] {
        monthDaySummaries.compactMapValues { summary in
            summary.visitCount > 0 ? summary.visitCount : nil
        }
    }

    var monthWannaCounts: [Date: Int] {
        monthDaySummaries.compactMapValues { summary in
            summary.wannaCount > 0 ? summary.wannaCount : nil
        }
    }

    var monthPlaceIDs: [Date: [String]] {
        monthDaySummaries.mapValues(\.placeIDs)
    }
}

struct ProfileMapPoint: Identifiable, Equatable {
    let id: String
    let name: String
    let city: String?
    let latitude: Double
    let longitude: Double
}

struct ProfileSummaryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    let total: Int
    let placeIDs: [String]

    var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total) * 100).rounded())
    }
}

enum CityCanonicalizer {
    private static let lowercaseConnectors: Set<String> = [
        "da", "das", "de", "del", "di", "do", "dos", "du", "la", "las", "le", "los", "of", "van", "von"
    ]

    static func comparisonKey(_ value: String?) -> String? {
        guard let cleaned = cleaned(value) else { return nil }
        return cleaned
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    static func preferredName(_ values: [String]) -> String? {
        let cleanedValues = values.compactMap { cleaned($0) }
        guard !cleanedValues.isEmpty else { return nil }
        let counts = Dictionary(grouping: cleanedValues, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount != rhsCount { return lhsCount > rhsCount }

            let lhsScore = casingScore(lhs)
            let rhsScore = casingScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }

            let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs < rhs
        }.first
    }

    private static func cleaned(_ value: String?) -> String? {
        let collapsed = value?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let collapsed, !collapsed.isEmpty else { return nil }
        return collapsed
    }

    private static func casingScore(_ value: String) -> Int {
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let hasUppercase = letters.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasLowercase = letters.contains { CharacterSet.lowercaseLetters.contains($0) }
        var score = hasUppercase && hasLowercase ? 2 : -2

        if value.first?.isUppercase == true {
            score += 1
        }
        for (index, word) in value.split(separator: " ").enumerated() where index > 0 {
            let normalized = word.lowercased()
            if lowercaseConnectors.contains(normalized), String(word) == normalized {
                score += 2
            }
        }
        return score
    }
}

final class ProfileInsightsCache {
    private var lastKey: ProfileInsightsCacheKey?
    private var lastInsights: ProfileInsights?

    private(set) var computationCount = 0

    func present(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        month: Date,
        calendar: Calendar = .current,
        dataRevision: UInt64? = nil
    ) -> ProfileInsights {
        let key = ProfileInsightsCacheKey(
            ownerID: ownerID,
            userPlaces: userPlaces,
            visits: visits,
            places: places,
            month: month,
            calendar: calendar,
            dataRevision: dataRevision
        )
        if key == lastKey, let lastInsights {
            return lastInsights
        }

        let insights = ProfileInsightsPresenter.present(
            ownerID: ownerID,
            userPlaces: userPlaces,
            visits: visits,
            places: places,
            month: month,
            calendar: calendar
        )
        lastKey = key
        lastInsights = insights
        computationCount += 1
        return insights
    }
}

private struct ProfileInsightsCacheKey: Equatable {
    let ownerID: String
    let month: Date
    let calendar: Calendar
    let localeIdentifier: String
    let dataRevision: UInt64?
    let inputFingerprint: ProfileInsightsInputFingerprint?

    init(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        month: Date,
        calendar: Calendar,
        dataRevision: UInt64?
    ) {
        self.ownerID = ownerID
        self.month = month
        self.calendar = calendar
        localeIdentifier = Locale.current.identifier
        self.dataRevision = dataRevision
        inputFingerprint = dataRevision == nil
            ? ProfileInsightsInputFingerprint(
                ownerID: ownerID,
                userPlaces: userPlaces,
                visits: visits,
                places: places,
                month: month,
                calendar: calendar
            )
            : nil
    }
}

private struct ProfileInsightsInputFingerprint: Equatable {
    let ownerID: String
    let userPlaces: [UserPlaceFingerprint]
    let visits: [VisitFingerprint]
    let places: [PlaceFingerprint]
    let month: Date
    let calendar: Calendar
    let localeIdentifier: String

    init(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        month: Date,
        calendar: Calendar
    ) {
        self.ownerID = ownerID
        self.userPlaces = userPlaces.map(UserPlaceFingerprint.init)
        self.visits = visits.map(VisitFingerprint.init)
        self.places = places.map(PlaceFingerprint.init)
        self.month = month
        self.calendar = calendar
        localeIdentifier = Locale.current.identifier
    }
}

private struct UserPlaceFingerprint: Equatable {
    let localID: String
    let serverID: String?
    let userID: String
    let placeID: String
    let statusRaw: String
    let categoryOverride: String?
    let savedAt: Date
    let historicalWantedAt: Date?
    let deletedAt: Date?

    init(_ userPlace: LocalUserPlace) {
        localID = userPlace.localID
        serverID = userPlace.serverID
        userID = userPlace.userID
        placeID = userPlace.placeID
        statusRaw = userPlace.statusRaw
        categoryOverride = userPlace.categoryOverride
        savedAt = userPlace.savedAt
        historicalWantedAt = userPlace.historicalWantedAt
        deletedAt = userPlace.deletedAt
    }
}

private struct VisitFingerprint: Equatable {
    let localID: String
    let serverID: String?
    let userPlaceID: String
    let visitedAt: Date
    let deletedAt: Date?

    init(_ visit: LocalPlaceVisit) {
        localID = visit.localID
        serverID = visit.serverID
        userPlaceID = visit.userPlaceID
        visitedAt = visit.visitedAt
        deletedAt = visit.deletedAt
    }
}

private struct PlaceFingerprint: Equatable {
    let localID: String
    let serverID: String?
    let canonicalName: String
    let primaryCategory: String
    let locality: String?
    let country: String?
    let latitudeBitPattern: UInt64
    let longitudeBitPattern: UInt64

    init(_ place: LocalPlace) {
        localID = place.localID
        serverID = place.serverID
        canonicalName = place.canonicalName
        primaryCategory = place.primaryCategory
        locality = place.locality
        country = place.country
        latitudeBitPattern = place.latitude.bitPattern
        longitudeBitPattern = place.longitude.bitPattern
    }
}

private struct ProfileCalendarDayAccumulator {
    var visitCount = 0
    var wannaCount = 0
    var visitPlaceIDs: Set<String> = []
    var wannaPlaceIDs: Set<String> = []

    func summary(on date: Date) -> ProfileCalendarDaySummary {
        ProfileCalendarDaySummary(
            date: date,
            visitCount: visitCount,
            wannaCount: wannaCount,
            visitPlaceIDs: visitPlaceIDs.sorted(),
            wannaPlaceIDs: wannaPlaceIDs.sorted()
        )
    }
}

private struct ProfileWannaActivity {
    let userPlace: LocalUserPlace
    let savedAt: Date
}

enum ProfileInsightsPresenter {
    static func present(
        ownerID: String,
        userPlaces: [LocalUserPlace],
        visits: [LocalPlaceVisit],
        places: [LocalPlace],
        month: Date,
        calendar: Calendar = .current
    ) -> ProfileInsights {
        let activeOwnerPlaces = uniqueUserPlaces(userPlaces.filter {
            $0.userID == ownerID && $0.deletedAt == nil
        })
        let activeBeen = activeOwnerPlaces.filter {
            $0.status == .been
        }
        let userPlaceByID = keyedUserPlaces(activeBeen)
        let placeByID = keyedPlaces(places)
        let activeVisits = uniqueVisits(visits.filter {
            $0.deletedAt == nil && userPlaceByID[$0.userPlaceID] != nil
        })
        let monthInterval = calendar.dateInterval(of: .month, for: month)
        let monthVisits = activeVisits.filter { visit in
            monthInterval?.contains(visit.visitedAt) == true
        }
        let wannaActivities = activeOwnerPlaces.compactMap { userPlace -> ProfileWannaActivity? in
            switch userPlace.status {
            case .wannaGo:
                ProfileWannaActivity(userPlace: userPlace, savedAt: userPlace.savedAt)
            case .been:
                userPlace.historicalWantedAt.map {
                    ProfileWannaActivity(userPlace: userPlace, savedAt: $0)
                }
            }
        }
        let monthWannaActivities = wannaActivities.filter { activity in
            monthInterval?.contains(activity.savedAt) == true
        }

        var dayAccumulators: [Date: ProfileCalendarDayAccumulator] = [:]
        for visit in monthVisits {
            let day = calendar.startOfDay(for: visit.visitedAt)
            dayAccumulators[day, default: ProfileCalendarDayAccumulator()].visitCount += 1
            if let userPlace = userPlaceByID[visit.userPlaceID] {
                let canonicalPlaceID = placeByID[userPlace.placeID]?.id ?? userPlace.placeID
                dayAccumulators[day, default: ProfileCalendarDayAccumulator()]
                    .visitPlaceIDs
                    .insert(canonicalPlaceID)
            }
        }
        for activity in monthWannaActivities {
            let day = calendar.startOfDay(for: activity.savedAt)
            dayAccumulators[day, default: ProfileCalendarDayAccumulator()].wannaCount += 1
            let canonicalPlaceID = placeByID[activity.userPlace.placeID]?.id ?? activity.userPlace.placeID
            dayAccumulators[day, default: ProfileCalendarDayAccumulator()]
                .wannaPlaceIDs
                .insert(canonicalPlaceID)
        }
        let monthDaySummaries = Dictionary(
            uniqueKeysWithValues: dayAccumulators.map { day, accumulator in
                (day, accumulator.summary(on: day))
            }
        )

        let monthUserPlaces = uniqueUserPlaces(
            monthVisits.compactMap { userPlaceByID[$0.userPlaceID] }
        )
        let monthPlaces = monthUserPlaces.compactMap { placeByID[$0.placeID] }
        let distinctMonthCategories: Set<String> = Set(monthUserPlaces.compactMap { userPlace in
            guard let place = placeByID[userPlace.placeID] else { return nil }
            return resolvedCategory(userPlace: userPlace, place: place)
        })
        let distinctMonthCities = Set(monthPlaces.compactMap { CityCanonicalizer.comparisonKey($0.locality) })

        let uniqueBeen = uniqueUserPlaces(activeBeen)
        let beenPlaces = uniqueBeen.compactMap { userPlace -> (LocalUserPlace, LocalPlace)? in
            guard let place = placeByID[userPlace.placeID] else { return nil }
            return (userPlace, place)
        }
        let mapPoints = beenPlaces.compactMap { _, place -> ProfileMapPoint? in
            guard validCoordinate(latitude: place.latitude, longitude: place.longitude) else { return nil }
            return ProfileMapPoint(
                id: place.id,
                name: place.canonicalName,
                city: normalized(place.locality),
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return ProfileInsights(
            month: calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month,
            monthDaySummaries: monthDaySummaries,
            monthVisitCount: monthVisits.count,
            monthWannaCount: monthWannaActivities.count,
            monthSpotCount: monthUserPlaces.count,
            monthCategoryCount: distinctMonthCategories.count,
            monthCityCount: distinctMonthCities.count,
            mapPoints: mapPoints,
            placeSummaries: summaries(
                values: beenPlaces.map { (resolvedCategory(userPlace: $0.0, place: $0.1), $0.1.id) },
                title: { WanderPlaceCategory.broadCategory(for: $0) },
                total: beenPlaces.count
            ),
            citySummaries: citySummaries(
                values: beenPlaces.compactMap { item in
                    normalized(item.1.locality).map { ($0, item.1.id) }
                },
                total: beenPlaces.count
            ),
            countrySummaries: summaries(
                values: beenPlaces.compactMap { item in
                    CountryCanonicalizer.canonicalName(item.1.country).map { ($0, item.1.id) }
                },
                title: { $0 },
                total: beenPlaces.count
            )
        )
    }

    private static func keyedUserPlaces(_ userPlaces: [LocalUserPlace]) -> [String: LocalUserPlace] {
        var result: [String: LocalUserPlace] = [:]
        for userPlace in userPlaces {
            result[userPlace.id] = userPlace
            result[userPlace.localID] = userPlace
            if let serverID = userPlace.serverID {
                result[serverID] = userPlace
            }
        }
        return result
    }

    private static func keyedPlaces(_ places: [LocalPlace]) -> [String: LocalPlace] {
        var result: [String: LocalPlace] = [:]
        for place in places {
            result[place.id] = place
            result[place.localID] = place
            if let serverID = place.serverID {
                result[serverID] = place
            }
        }
        return result
    }

    private static func uniqueUserPlaces(_ values: [LocalUserPlace]) -> [LocalUserPlace] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueVisits(_ values: [LocalPlaceVisit]) -> [LocalPlaceVisit] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func resolvedCategory(userPlace: LocalUserPlace, place: LocalPlace) -> String {
        WanderPlaceCategory.normalizedPrimaryCategory(userPlace.categoryOverride ?? place.primaryCategory)
    }

    private static func summaries(
        values: [(value: String, placeID: String)],
        title: (String) -> String,
        total: Int
    ) -> [ProfileSummaryItem] {
        let groups = Dictionary(grouping: values, by: \.value)
        return groups.map { key, group in
            ProfileSummaryItem(
                id: key,
                title: title(key),
                count: group.count,
                total: total,
                placeIDs: Array(Set(group.map(\.placeID))).sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func citySummaries(
        values: [(value: String, placeID: String)],
        total: Int
    ) -> [ProfileSummaryItem] {
        let keyedValues = values.compactMap { entry -> (key: String, value: String, placeID: String)? in
            guard let key = CityCanonicalizer.comparisonKey(entry.value) else { return nil }
            return (key, entry.value, entry.placeID)
        }
        let groups = Dictionary(grouping: keyedValues, by: \.key)
        return groups.compactMap { key, group in
            guard let title = CityCanonicalizer.preferredName(group.map(\.value)) else { return nil }
            return ProfileSummaryItem(
                id: key,
                title: title,
                count: group.count,
                total: total,
                placeIDs: Array(Set(group.map(\.placeID))).sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && abs(latitude) <= 90
            && abs(longitude) <= 180
            && !(latitude == 0 && longitude == 0)
    }
}
