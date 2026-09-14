import MapKit
import XCTest
@testable import Wander

@MainActor
final class MapAnnotationVisibilityTests: XCTestCase {
    func testMapKitCollisionSuppressionAndZoomReveal() async throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let delegate = CollisionDelegate()
        map.delegate = delegate
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = map.bounds
        let controller = UIViewController()
        controller.view = map
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            withExtendedLifetime(delegate) {}
        }

        let pins = [0.0, 0.00003].map { offset in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: 34 + offset, longitude: -118)
            return annotation
        }
        func zoom(_ span: Double) {
            map.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.000015, longitude: -118),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ), animated: false)
        }
        func visibleCount() -> Int {
            pins.filter { MapHitTesting.isAnnotationViewVisible(map.view(for: $0), in: map) }.count
        }
        func capture(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        zoom(0.01)
        map.addAnnotations(pins)
        for _ in 0..<100 where visibleCount() != 1 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(map.annotations(in: map.visibleMapRect).count, 2,
                       "Both coordinates remain in the viewport, as in the original bug")
        XCTAssertEqual(visibleCount(), 1, "The collision-hidden pin must not be selectable")
        capture("Zoomed out - one selectable pin")

        zoom(0.0001)
        for _ in 0..<100 where visibleCount() != 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(visibleCount(), 2, "Zooming in must make both rendered pins selectable")
        capture("Zoomed in - two selectable pins")
    }

    func testCollisionHiddenPinBecomesSelectableOnlyAfterItReappears() {
        let (map, _, pin) = fixture()
        XCTAssertTrue(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        pin.isHidden = true
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        pin.isHidden = false
        XCTAssertTrue(MapHitTesting.isAnnotationViewVisible(pin, in: map))
    }

    func testMissingDetachedAndReusedViewsCannotBeSelected() {
        let (map, _, pin) = fixture()
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(nil, in: map))
        pin.removeFromSuperview()
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        let otherMap = MKMapView(frame: map.frame)
        otherMap.addSubview(pin)
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
    }

    func testTransparentPinIsRejectedButVisibleDimmedPinRemainsSelectable() {
        let (map, _, pin) = fixture()
        pin.alpha = 0
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        pin.alpha = 0.35
        XCTAssertTrue(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        pin.layer.isHidden = true
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
    }

    func testHiddenAndTransparentAncestorSuppressSelection() {
        let (map, container, pin) = fixture()
        container.isHidden = true
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        container.isHidden = false
        container.alpha = 0
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        container.alpha = 0.05
        pin.alpha = 0.05
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        container.alpha = 1
        pin.alpha = 1
        XCTAssertTrue(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        map.isHidden = true
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
    }

    func testOffscreenAndEmptyViewsCannotBeSelected() {
        let (map, _, pin) = fixture()
        pin.frame.origin = CGPoint(x: 400, y: 700)
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
        pin.frame = CGRect(x: 20, y: 20, width: 0, height: 0)
        XCTAssertFalse(MapHitTesting.isAnnotationViewVisible(pin, in: map))
    }

    private func fixture() -> (MKMapView, UIView, MKAnnotationView) {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let container = UIView(frame: map.bounds)
        let pin = MKAnnotationView(annotation: MKPointAnnotation(), reuseIdentifier: nil)
        pin.frame = CGRect(x: 100, y: 100, width: 44, height: 44)
        map.addSubview(container)
        container.addSubview(pin)
        return (map, container, pin)
    }
}

@MainActor
private final class CollisionDelegate: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
        view.image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        view.displayPriority = .defaultHigh
        view.collisionMode = .circle
        return view
    }
}
