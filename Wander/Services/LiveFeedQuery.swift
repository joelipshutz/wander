import Foundation
import CoreLocation

/// Immutable committed Live filters. Keep the time window fixed until the user
/// applies a change or explicitly refreshes it; cursors are bound to this query.
struct LiveFeedQuery: Equatable, Sendable {
    enum ActivityType: String, Codable, Sendable { case all, checkIns = "check_ins", wannas }
    struct Vertex: Codable, Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }
    let occurredAfter: Date?
    let occurredBefore: Date?
    let activityType: ActivityType
    let polygon: [Vertex]?
    let center: Vertex?
    let radiusMeters: Int?
    let categoryIDs: [String]
    let personIDs: [String]
    private let polygonIsValid: Bool

    init(occurredAfter: Date? = nil, occurredBefore: Date? = nil,
         activityType: ActivityType = .all, polygon: [Vertex]? = nil,
         center: Vertex? = nil, radiusMeters: Int? = nil,
         categoryIDs: Set<String> = [], personIDs: Set<String> = []) {
        // Use the same millisecond precision as the wire representation.
        self.occurredAfter = occurredAfter.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970 * 1_000) / 1_000) }
        self.occurredBefore = occurredBefore.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970 * 1_000) / 1_000) }
        self.activityType = activityType
        self.polygon = polygon
        self.center = center
        self.radiusMeters = radiusMeters
        self.categoryIDs = categoryIDs.sorted()
        self.personIDs = personIDs.sorted()
        self.polygonIsValid = Self.validPolygon(polygon)
    }

    /// Reusing an already-validated polygon avoids rechecking every edge pair
    /// for each visible Feed row when classifying an expanded section.
    private init(olderThan source: LiveFeedQuery) {
        occurredAfter = nil
        occurredBefore = source.occurredAfter ?? source.occurredBefore
        activityType = source.activityType
        polygon = source.polygon
        center = source.center
        radiusMeters = source.radiusMeters
        categoryIDs = source.categoryIDs
        personIDs = source.personIDs
        polygonIsValid = source.polygonIsValid
    }

    var isValid: Bool {
        if let occurredAfter, !occurredAfter.timeIntervalSince1970.isFinite { return false }
        if let occurredBefore, !occurredBefore.timeIntervalSince1970.isFinite { return false }
        if let occurredAfter, let occurredBefore, occurredAfter > occurredBefore { return false }
        guard categoryIDs.count <= 100, personIDs.count <= 100,
              personIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.unicodeScalars.count <= 256 }),
              categoryIDs.allSatisfy({ $0.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil }) else { return false }
        if let center {
            guard center.latitude.isFinite, center.longitude.isFinite,
                  (-90...90).contains(center.latitude), (-180...180).contains(center.longitude),
                  let radiusMeters, (100...25_000).contains(radiusMeters) else { return false }
        } else if radiusMeters != nil { return false }
        return polygonIsValid
    }

    /// Fixture parity and a final presentation guard. Production filtering is
    /// authoritative on the server before its limit, never a loaded-page scan.
    func includes(_ activity: FeedActivity) -> Bool {
        guard isValid else { return false }
        if let occurredAfter, activity.occurredAt < occurredAfter { return false }
        if let occurredBefore, activity.occurredAt > occurredBefore { return false }
        switch activityType {
        case .all: break
        case .checkIns: if activity.resolvedTicketKind != .checkIn { return false }
        case .wannas: if activity.resolvedTicketKind != .wanna { return false }
        }
        if !personIDs.isEmpty, !personIDs.contains(activity.actor.id) { return false }
        if !categoryIDs.isEmpty {
            guard let place = activity.place, categoryIDs.contains(Self.categoryID(for: place)) else { return false }
        }
        if let center, let radiusMeters {
            guard let place = activity.place?.place,
                  place.latitude.isFinite, place.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(.init(latitude: place.latitude, longitude: place.longitude)) else { return false }
            guard CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) <= Double(radiusMeters) else { return false }
        }
        guard polygon != nil else { return true }
        guard let place = activity.place?.place else { return false }
        return contains(latitude: place.latitude, longitude: place.longitude)
    }

    /// Live's server projection supplies the viewer's canonical taxonomy. Do
    /// not reinterpret it from provider hints or another member's override.
    static func categoryID(for place: VisiblePlace) -> String {
        place.userPlace.viewerPrimaryCategory.map(WanderPlaceCategory.normalizedPrimaryCategory)
            ?? place.effectiveCategory
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        guard let polygon, let origin = polygon.first, isValid,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return false }
        func unwrap(_ value: Double) -> Double {
            var result = value - origin.longitude
            while result > 180 { result -= 360 }
            while result < -180 { result += 360 }
            return result
        }
        let x = unwrap(longitude)
        var inside = false
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let ax = unwrap(a.longitude) - x, bx = unwrap(b.longitude) - x
            let ay = a.latitude - latitude, by = b.latitude - latitude
            let cross = ax * by - bx * ay
            if abs(cross) < 0.000000001, min(ax, bx) <= 0, max(ax, bx) >= 0,
               min(ay, by) <= 0, max(ay, by) >= 0 { return true }
            if (ay > 0) != (by > 0), 0 < (bx - ax) * -ay / (by - ay) + ax { inside.toggle() }
        }
        return inside
    }

    static func timestamp(_ date: Date?) -> String? {
        date?.ISO8601Format(.init(includingFractionalSeconds: true))
    }

    private static func validPolygon(_ vertices: [Vertex]?) -> Bool {
        guard let vertices else { return true }
        guard (3...512).contains(vertices.count), vertices.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }) else { return false }
        let unwrapped = vertices.map { vertex -> Vertex in
            var x = vertex.longitude - vertices[0].longitude
            while x > 180 { x -= 360 }
            while x < -180 { x += 360 }
            return Vertex(latitude: vertex.latitude, longitude: x)
        }
        // A stationary drawing sample can repeat its neighbor. PostGIS accepts
        // those zero-length edges; normalize them for the same validity result.
        var points = unwrapped.reduce(into: [Vertex]()) { result, point in
            if result.last != point { result.append(point) }
        }
        if points.first == points.last { points.removeLast() }
        guard points.count >= 3 else { return false }
        guard let west = points.map(\.longitude).min(), let east = points.map(\.longitude).max(),
              east - west < 180 else { return false }
        let area = points.indices.reduce(0.0) { partial, index in
            let a = points[index], b = points[(index + 1) % points.count]
            return partial + a.longitude * b.latitude - b.longitude * a.latitude
        }
        guard area.isFinite, abs(area) > 0 else { return false }
        func cross(_ a: Vertex, _ b: Vertex, _ c: Vertex) -> Double {
            (b.longitude-a.longitude)*(c.latitude-a.latitude) - (b.latitude-a.latitude)*(c.longitude-a.longitude)
        }
        func onSegment(_ a: Vertex, _ b: Vertex, _ c: Vertex) -> Bool {
            cross(a,b,c) == 0 && min(a.longitude,b.longitude) <= c.longitude && c.longitude <= max(a.longitude,b.longitude)
                && min(a.latitude,b.latitude) <= c.latitude && c.latitude <= max(a.latitude,b.latitude)
        }
        // Validate once at Apply, never on every row or camera update.
        for i in points.indices {
            let nextI = (i+1) % points.count
            for j in points.indices where j > i {
                let nextJ = (j+1) % points.count
                if nextI == j || nextJ == i { continue }
                let a = points[i], b = points[nextI], c = points[j], d = points[nextJ]
                if onSegment(a,b,c) || onSegment(a,b,d) || onSegment(c,d,a) || onSegment(c,d,b)
                    || (cross(a,b,c)*cross(a,b,d) < 0 && cross(c,d,a)*cross(c,d,b) < 0) { return false }
            }
        }
        return true
    }
}


/// Expansion changes only discovery filters. The selected audience, visibility,
/// block rules and short-lived social authorization remain owned by WanderStore.
enum LiveFeedExpansionStage: Int, CaseIterable, Identifiable, Sendable {
    case selected, older, allActivity
    var id: Int { rawValue }
}

struct LiveFeedActivitySection: Identifiable {
    let stage: LiveFeedExpansionStage
    let groups: [FeedActivityGroup]
    var id: LiveFeedExpansionStage { stage }
}

extension LiveFeedQuery {
    var hasDiscoveryFilters: Bool {
        activityType != .all || polygon != nil || center != nil
            || !categoryIDs.isEmpty || !personIDs.isEmpty
    }

    func nextExpansion(after stage: LiveFeedExpansionStage) -> LiveFeedExpansionStage? {
        guard isValid else { return nil }
        switch stage {
        case .selected:
            if occurredAfter != nil { return .older }
            return hasDiscoveryFilters ? .allActivity : nil
        case .older:
            return hasDiscoveryFilters ? .allActivity : nil
        case .allActivity:
            return nil
        }
    }

    func expandedQuery(for stage: LiveFeedExpansionStage) -> LiveFeedQuery {
        switch stage {
        case .selected: return self
        case .older:
            // Keep the inclusive boundary: the server may store submillisecond
            // timestamps. ID deduplication removes the boundary overlap without
            // skipping activity immediately before the selected window.
            return LiveFeedQuery(olderThan: self)
        case .allActivity:
            return LiveFeedQuery(occurredBefore: occurredBefore)
        }
    }

    func expansionStage(for activity: FeedActivity) -> LiveFeedExpansionStage {
        if includes(activity) { return .selected }
        if occurredAfter != nil, expandedQuery(for: .older).includes(activity) { return .older }
        return .allActivity
    }

    func includes(_ activity: FeedActivity, through stage: LiveFeedExpansionStage) -> Bool {
        guard isValid else { return false }
        if includes(activity) { return true }
        if stage.rawValue >= LiveFeedExpansionStage.older.rawValue,
           occurredAfter != nil, expandedQuery(for: .older).includes(activity) { return true }
        return stage == .allActivity && expandedQuery(for: .allActivity).includes(activity)
    }
}


extension LiveFeedQuery {
    /// Featured's anonymous aggregate is a place recommendation, never a social post.
    func includesFeatured(_ visible: VisiblePlace) -> Bool {
        guard isValid, personIDs.isEmpty, activityType != .wannas,
              visible.userPlace.status == .been else { return false }
        let date = visible.userPlace.visitedAt ?? visible.userPlace.savedAt
        if let occurredAfter, date < occurredAfter { return false }
        if let occurredBefore, date > occurredBefore { return false }
        if !categoryIDs.isEmpty, !categoryIDs.contains(Self.categoryID(for: visible)) { return false }
        let place = visible.place
        if polygon != nil && !contains(latitude: place.latitude, longitude: place.longitude) { return false }
        if let center, let radiusMeters,
           CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) > Double(radiusMeters) { return false }
        return true
    }
}
