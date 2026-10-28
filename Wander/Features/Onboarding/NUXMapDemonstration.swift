import MapKit

/// Detached models used only by the Map tour. Never inserted into the user's store.
@MainActor
enum NUXMapDemonstration {
    static func center() -> CLLocationCoordinate2D {
        let manager = CLLocationManager()
        if !ProcessInfo.processInfo.arguments.contains("-WanderUseDemoFixtures"),
           [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus),
           let location = manager.location,
           abs(location.timestamp.timeIntervalSinceNow) < 300 {
            return location.coordinate
        }
        let fallback = FirstVisitParkSuggestionPolicy.hotchkissPark
        return CLLocationCoordinate2D(latitude: fallback.latitude ?? 34.00585, longitude: fallback.longitude ?? -118.4842)
    }

    static func places(around center: CLLocationCoordinate2D) -> [VisiblePlace] {
        let examples = [
            ("Coffee Spot", "cafe", -0.0018, 0.0014),
            ("Neighborhood Park", "park", 0.0012, -0.0016),
            ("Dinner Spot", "restaurant", 0.0031, 0.0017),
            ("Weekend Bakery", "bakery", -0.0029, -0.0026),
            ("A Favorite Bookstore", "bookstore", 0.0005, 0.0035),
            ("Something To Try", "restaurant", -0.0006, -0.0040),
            ("A Little Getaway", "park", 0.0038, -0.0030),
            ("Morning Coffee", "cafe", -0.0039, 0.0030)
        ]
        return examples.enumerated().map { index, example in
            let id = "nux-demo-\(index)"
            let owner = LocalProfile(localID: "nux-demo-owner-\(index % 3)",
                                     handle: "example\(index % 3)", displayName: "Example")
            let place = LocalPlace(localID: id, canonicalName: example.0, category: example.1,
                                   latitude: center.latitude + example.2,
                                   longitude: center.longitude + example.3, sourceProvider: "nux_demo")
            let save = LocalUserPlace(localID: id + "-save", userID: owner.id, placeID: id,
                                      status: index.isMultiple(of: 3) ? .wannaGo : .been,
                                      visibility: .followers, sourceType: "nux_demo")
            return VisiblePlace(id: id, place: place, userPlace: save, owner: owner)
        }
    }
}
