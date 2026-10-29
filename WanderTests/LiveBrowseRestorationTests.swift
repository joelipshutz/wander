import MapKit
import XCTest
@testable import Wander

@MainActor
final class LiveBrowseRestorationTests: XCTestCase {
    func testGPSJitterDoesNotChangeTheQueryButAccumulatedMovementDoes() {
        let origin = CLLocationCoordinate2D(latitude: 40.7, longitude: -74)
        XCTAssertTrue(LiveLocationRefreshPolicy.shouldMove(from: nil, to: origin))
        XCTAssertFalse(LiveLocationRefreshPolicy.shouldMove(from: origin, to: origin))
        XCTAssertFalse(LiveLocationRefreshPolicy.shouldMove(from: origin, to: .init(latitude: 40.7002, longitude: -74)))
        XCTAssertTrue(LiveLocationRefreshPolicy.shouldMove(from: origin, to: .init(latitude: 40.704, longitude: -74)))
        XCTAssertTrue(LiveLocationRefreshPolicy.shouldMove(from: origin, to: .init(latitude: 47.6, longitude: -122.3)))
    }

    func testRestorationIsAccountScopedBoundedAndExpires() throws {
        let name = "live-restoration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date.now
        var selection = LiveBrowseSelection(now: now)
        selection.activityType = .checkIns; selection.time = .week
        let region = LiveMapCameraPolicy.locationRegion(.init(latitude: 40.7, longitude: -74))
        let saved = LiveBrowseRestoration(selection: selection, audience: .onlyFriends, area: nil,
            boundary: nil, region: region, detent: 2, now: now)
        saved.save(userID: "one", defaults: defaults)
        XCTAssertNil(LiveBrowseRestoration.load(userID: "two", defaults: defaults, now: now))
        let restored = try XCTUnwrap(LiveBrowseRestoration.load(userID: "one", defaults: defaults, now: now.addingTimeInterval(120)))
        XCTAssertEqual(restored.selection, selection)
        XCTAssertEqual(restored.audience, .onlyFriends)
        XCTAssertEqual(restored.detent, 2)
        XCTAssertEqual(restored.region.center.latitude, 40.7)
        XCTAssertNil(LiveBrowseRestoration.load(userID: "one", defaults: defaults, now: now.addingTimeInterval(21_600)))
        XCTAssertNil(defaults.data(forKey: LiveBrowseRestoration.key("one")))
    }

    func testRestoredPannedCameraKeepsActualGPSAnchorSeparate() throws {
        let gps = CLLocationCoordinate2D(latitude: 40.7, longitude: -74)
        let panned = LiveMapCameraPolicy.locationRegion(.init(latitude: 40.9, longitude: -74))
        let saved = LiveBrowseRestoration(selection: .init(), audience: .everyone, area: nil,
            boundary: nil, region: panned, detent: 1, lastLocation: gps)
        let copy = try JSONDecoder().decode(LiveBrowseRestoration.self, from: JSONEncoder().encode(saved))
        let fix = try XCTUnwrap(copy.lastLocation)
        XCTAssertEqual(copy.region.center.latitude, 40.9)
        XCTAssertFalse(LiveLocationRefreshPolicy.shouldMove(from: .init(latitude: fix.latitude, longitude: fix.longitude), to: gps))
    }

    func testMalformedFutureAndInvalidGeometryCannotRestore() throws {
        let name = "live-restoration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date.now
        for data in [Data("invalid".utf8), Data(repeating: 0, count: 65_537)] {
            defaults.set(data, forKey: LiveBrowseRestoration.key("one"))
            XCTAssertNil(LiveBrowseRestoration.load(userID: "one", defaults: defaults, now: now))
        }
        let region = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 0, longitudeDelta: 0))
        let invalid = LiveBrowseRestoration(selection: .init(), audience: .everyone, area: nil,
            boundary: nil, region: region, detent: 1)
        XCTAssertFalse(invalid.isValid(now: .now))
        let future = LiveBrowseRestoration(selection: .init(), audience: .everyone, area: nil, boundary: nil,
            region: LiveMapCameraPolicy.locationRegion(.init(latitude: 0, longitude: 0)), detent: 1, now: now.addingTimeInterval(1))
        XCTAssertFalse(future.isValid(now: now))
    }
}
