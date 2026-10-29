import MapKit

/// A small UI bookmark, never a persisted authorization receipt or social page.
struct LiveBrowseRestoration: Codable {
    static var enabledForProcess: Bool {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-WanderAuthenticatedUITest") {
            return arguments.contains("-WanderLiveRestorationUITest")
        }
        #endif
        return true
    }
    static let maximumAge: TimeInterval = 6 * 60 * 60
    let version: Int
    let savedAt: Date
    let selection: LiveBrowseSelection
    let audience: FeedAudience
    let area: LiveSelectedArea?
    let boundary: LiveDrawnArea?
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
    let detent: Int
    let lastLocation: LiveFeedQuery.Vertex?

    init(selection: LiveBrowseSelection, audience: FeedAudience, area: LiveSelectedArea?,
         boundary: LiveDrawnArea?, region: MKCoordinateRegion, detent: Int,
         lastLocation: CLLocationCoordinate2D? = nil, now: Date = .now) {
        version = 1; savedAt = now; self.selection = selection; self.audience = audience
        self.area = area; self.boundary = boundary; self.detent = detent
        self.lastLocation = lastLocation.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        latitude = region.center.latitude; longitude = region.center.longitude
        latitudeDelta = region.span.latitudeDelta; longitudeDelta = region.span.longitudeDelta
    }
    var region: MKCoordinateRegion {
        .init(center: .init(latitude: latitude, longitude: longitude),
              span: .init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
    func isValid(now: Date) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return version == 1 && age.isFinite && age >= 0 && age < Self.maximumAge
            && selection.isValid && selection.personIDs.count <= 100 && selection.categoryIDs.count <= 100
            && CLLocationCoordinate2DIsValid(region.center) && latitude.isFinite && longitude.isFinite
            && latitudeDelta.isFinite && longitudeDelta.isFinite
            && latitudeDelta > 0 && latitudeDelta <= 180 && longitudeDelta > 0 && longitudeDelta < 180
            && (lastLocation.map { $0.latitude.isFinite && $0.longitude.isFinite && CLLocationCoordinate2DIsValid(.init(latitude: $0.latitude, longitude: $0.longitude)) } ?? true)
            && (0...2).contains(detent)
            && [area?.boundary, boundary].compactMap { $0 }.allSatisfy {
                LiveDrawnArea(coordinates: $0.vertices.map(\.coordinate)) != nil
            }
    }
    static func key(_ userID: String) -> String { "astir.live.restoration.v1.\(userID)" }
    func save(userID: String, defaults: UserDefaults = .standard) {
        guard isValid(now: savedAt), let data = try? JSONEncoder().encode(self), data.count <= 65_536 else { return }
        defaults.set(data, forKey: Self.key(userID))
    }
    static func load(userID: String, defaults: UserDefaults = .standard, now: Date = .now) -> Self? {
        guard let data = defaults.data(forKey: key(userID)), data.count <= 65_536,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid(now: now) else {
            defaults.removeObject(forKey: key(userID)); return nil
        }
        return value
    }
}

enum LiveLocationRefreshPolicy {
    /// Anchor to the last committed fix so repeated small steps eventually count
    /// as movement. Small GPS changes do not mint a different polygon/query.
    static func shouldMove(from previous: CLLocationCoordinate2D?, to current: CLLocationCoordinate2D) -> Bool {
        guard let previous else { return true }
        return CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude)) >= 250
    }
}
