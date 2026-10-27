import MapKit

/// Presentation geometry only. Inputs must already pass the Feed's access policy.
struct LiveDrawnArea: Equatable {
    struct Vertex: Equatable {
        let latitude: Double
        let longitude: Double
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    let vertices: [Vertex]

    init?(coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 3, coordinates.count <= 512,
              coordinates.allSatisfy(CLLocationCoordinate2DIsValid) else { return nil }
        let query = LiveFeedQuery(polygon: coordinates.map {
            LiveFeedQuery.Vertex(latitude: $0.latitude, longitude: $0.longitude)
        })
        guard query.isValid else { return nil }
        let points = coordinates.map(MKMapPoint.init)
        let origin = points[0]
        let area = abs(zip(points, Array(points.dropFirst()) + [points[0]]).reduce(0.0) {
            $0 + ($1.0.x - origin.x) * ($1.1.y - origin.y) - ($1.1.x - origin.x) * ($1.0.y - origin.y)
        }) / 2
        guard area > 1 else { return nil }
        vertices = coordinates.map { Vertex(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Unwrap longitudes around the first vertex, including areas crossing ±180°.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        let referenceLongitude = vertices[0].longitude
        func unwrap(_ longitude: Double) -> Double {
            var delta = longitude - referenceLongitude
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            return delta
        }
        let queryX = unwrap(coordinate.longitude)
        var inside = false
        for index in vertices.indices {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            let ax = unwrap(a.longitude) - queryX, bx = unwrap(b.longitude) - queryX
            let ay = a.latitude - coordinate.latitude, by = b.latitude - coordinate.latitude
            let cross = ax * by - bx * ay
            if abs(cross) < 0.000000001,
               min(ax, bx) <= 0, max(ax, bx) >= 0,
               min(ay, by) <= 0, max(ay, by) >= 0 { return true }
            if (ay > 0) != (by > 0), 0 < (bx - ax) * -ay / (by - ay) + ax {
                inside.toggle()
            }
        }
        return inside
    }
}

enum LiveActivityFilter: String, CaseIterable, Identifiable {
    case all = "All", checkIns = "Check-ins", wannas = "Wannas"
    var id: Self { self }
    func includes(_ activity: FeedActivity) -> Bool {
        switch self {
        case .all: true
        case .checkIns: activity.resolvedTicketKind == .checkIn
        case .wannas: activity.resolvedTicketKind == .wanna
        }
    }
}

enum LiveTimeFilter: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30, all = 0
    var id: Self { self }
    var title: String {
        switch self { case .day: "Past 24 hours"; case .week: "Past 7 days"; case .month: "Past 30 days"; case .all: "All time" }
    }
    func includes(_ date: Date, now: Date) -> Bool {
        rawValue == 0 || (date >= now.addingTimeInterval(-Double(rawValue) * 86_400) && date <= now.addingTimeInterval(300))
    }
}

enum LiveMapCameraPolicy {
    /// The eighth-nearest authorized place sets density. Sparse networks expand
    /// naturally; dense local networks remain local. Never rerun after user pan.
    static func region(coordinates: [CLLocationCoordinate2D], anchor: CLLocationCoordinate2D?) -> MKCoordinateRegion? {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let center = anchor ?? valid.first else { return nil }
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let distances = valid.map { origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }.sorted()
        let distance = distances.isEmpty ? 2_500 : distances[min(7, distances.count - 1)]
        let span = min(20_000_000, max(4_000, distance * 2.8))
        return MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
    }
}

enum LiveNavigationPolicy {
    static let tabs: [WanderTab] = [.discover, .lists, .profile]
    static func isEnabled(_ resolved: ResolvedFeatureFlagValue?, isolatedSimulatorReview: Bool) -> Bool {
        if isolatedSimulatorReview, resolved == nil || resolved?.source == .bundledDefault { return true }
        return resolved?.isEnabled == true
    }
    static func tab(for legacyTab: WanderTab) -> WanderTab {
        switch legacyTab { case .map, .events, .add: .discover; default: legacyTab }
    }
}

/// The navigation experiment is fixed after its first resolved value for this
/// launch. Background remote refreshes must not dismantle an open composer.
struct LiveExperienceLaunchPolicy {
    private var choices: [String: Bool] = [:]
    func value(for userID: String) -> Bool? { choices[userID] }
    mutating func resolve(for userID: String, flag: ResolvedFeatureFlagValue?, isolatedSimulatorReview: Bool) {
        guard choices[userID] == nil, flag != nil || isolatedSimulatorReview else { return }
        choices[userID] = LiveNavigationPolicy.isEnabled(flag, isolatedSimulatorReview: isolatedSimulatorReview)
    }
}
