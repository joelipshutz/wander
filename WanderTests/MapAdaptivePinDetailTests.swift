import XCTest
import MapKit
@testable import Wander

final class MapAdaptivePinDetailTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 0, width: 390, height: 800)

    func testWideViewKeepsScatteredCategoriesAndRepresentsEveryOtherPlaceAsADot() {
        var policy = MapAdaptivePinDetailPolicy()
        let candidates = grid()
        let categories = policy.resolve(candidates, metersPerPoint: 40, viewport: viewport)
        XCTAssertGreaterThan(categories.count, 4)
        XCTAssertLessThan(categories.count, candidates.count / 3)
        for quadrant in [CGRect(x: 0, y: 0, width: 195, height: 400),
                         CGRect(x: 195, y: 0, width: 195, height: 400),
                         CGRect(x: 0, y: 400, width: 195, height: 400),
                         CGRect(x: 195, y: 400, width: 195, height: 400)] {
            XCTAssertTrue(candidates.contains { categories.contains($0.id) && quadrant.contains($0.point) })
        }
        XCTAssertEqual(categories.union(Set(candidates.map(\.id)).subtracting(categories)).count, candidates.count)
    }

    func testCloseZoomExpandsEveryPinEvenAtIdenticalCoordinates() {
        var policy = MapAdaptivePinDetailPolicy()
        let candidates = (0..<500).map {
            MapAdaptivePinDetailPolicy.Candidate(id: "pin-\($0)", point: CGPoint(x: 150, y: 300))
        }
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 40, viewport: viewport).count, 1)
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 3, viewport: viewport).count, 500)
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 3.8, viewport: viewport).count, 500)
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 4.1, viewport: viewport).count, 1)
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 3.8, viewport: viewport).count, 1)
    }

    func testCategoryRepresentativesSurviveReorderingAndSmallCameraMovement() {
        let candidates = grid()
        var first = MapAdaptivePinDetailPolicy()
        var second = MapAdaptivePinDetailPolicy()
        let expected = first.resolve(candidates, metersPerPoint: 40, viewport: viewport)
        XCTAssertEqual(second.resolve(Array(candidates.reversed()), metersPerPoint: 40, viewport: viewport), expected)
        let moved = candidates.map {
            MapAdaptivePinDetailPolicy.Candidate(id: $0.id, point: CGPoint(x: $0.point.x + 1, y: $0.point.y + 1))
        }
        XCTAssertEqual(first.resolve(moved, metersPerPoint: 40.01, viewport: viewport), expected)
    }

    func testSelectedDotPromotesWithoutDroppingOtherCandidatesAndFiltersPruneState() {
        var policy = MapAdaptivePinDetailPolicy()
        var candidates = grid()
        let original = policy.resolve(candidates, metersPerPoint: 40, viewport: viewport)
        let selectedIndex = candidates.firstIndex { !original.contains($0.id) }!
        candidates[selectedIndex].isSelected = true
        let selectedID = candidates[selectedIndex].id
        XCTAssertTrue(policy.resolve(candidates, metersPerPoint: 40, viewport: viewport).contains(selectedID))
        let remaining = candidates.filter { $0.id != selectedID }
        XCTAssertFalse(policy.resolve(remaining, metersPerPoint: 40, viewport: viewport).contains(selectedID))
        XCTAssertTrue(policy.resolve([], metersPerPoint: 40, viewport: viewport).isEmpty)
    }

    func testOffscreenPinsCannotCrowdOutVisibleCategoryPins() {
        var policy = MapAdaptivePinDetailPolicy()
        let candidates = [
            MapAdaptivePinDetailPolicy.Candidate(id: "outside", point: CGPoint(x: -1, y: 200)),
            MapAdaptivePinDetailPolicy.Candidate(id: "inside", point: CGPoint(x: 1, y: 200))
        ]
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 40, viewport: viewport), ["inside"])
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: .nan, viewport: viewport).count, 2)
    }

    func testThousandsOfPinsHaveNoCountCapAtCloseZoom() {
        var policy = MapAdaptivePinDetailPolicy()
        let candidates = (0..<5_000).map {
            MapAdaptivePinDetailPolicy.Candidate(id: "pin-\($0)",
                point: CGPoint(x: 20 + $0 % 350, y: 20 + $0 % 750))
        }
        XCTAssertFalse(policy.resolve(candidates, metersPerPoint: 100, viewport: viewport).isEmpty)
        XCTAssertEqual(policy.resolve(candidates, metersPerPoint: 2, viewport: viewport).count, 5_000)
    }

    @MainActor
    func testNativeDotRenderingSelectionAppearanceAndReuse() {
        func descriptor(selected: Bool = false, wanna: Bool = false) -> NativeMapAnnotationDescriptor {
            NativeMapAnnotationDescriptor(
                id: "pin", kind: .saved("pin"), title: "Fixture", emoji: "☕️",
                coordinate: CLLocationCoordinate2D(latitude: 34, longitude: -118),
                outlines: [.init(ownership: .currentUser, status: wanna ? .wannaGo : .been)],
                isSearchResult: false, isSelected: selected, opacity: 1, animatesEntrance: false,
                entranceDelay: 0, accessibilityLabel: "Fixture", bounceRevision: 0,
                keepsVisibleWhenColliding: true, detail: .dot
            )
        }
        let view = NativeMapPinAnnotationView(annotation: nil, reuseIdentifier: nil)
        view.configure(descriptor: descriptor(), isDark: false, reduceMotion: true)
        let filled = view.image?.pngData()
        XCTAssertEqual(view.image?.size.width, 16)
        XCTAssertEqual(view.displayPriority, .required)
        XCTAssertEqual(view.accessibilityValue, "Map dot")
        view.configure(descriptor: descriptor(wanna: true), isDark: false, reduceMotion: true)
        XCTAssertNotEqual(view.image?.pngData(), filled, "Wanna dots must be hollow")
        let light = view.image?.pngData()
        view.configure(descriptor: descriptor(wanna: true), isDark: true, reduceMotion: true)
        XCTAssertNotEqual(view.image?.pngData(), light)
        view.configure(descriptor: descriptor(selected: true), isDark: true, reduceMotion: true)
        XCTAssertGreaterThan(view.image?.size.width ?? 0, 40)
        XCTAssertEqual(view.accessibilityValue, "Category pin")
        view.prepareForReuse()
        view.configure(descriptor: descriptor(), isDark: false, reduceMotion: true)
        XCTAssertEqual(view.image?.size.width, 16)
        XCTAssertEqual(view.centerOffset, .zero)
        XCTAssertEqual(view.alpha, 1)
    }

    private func grid() -> [MapAdaptivePinDetailPolicy.Candidate] {
        (0..<200).map { index in
            let x = CGFloat(20 + (index % 10) * 36)
            let y = CGFloat(30 + (index / 10) * 38)
            return MapAdaptivePinDetailPolicy.Candidate(id: "pin-\(index)", point: CGPoint(x: x, y: y))
        }
    }
}
