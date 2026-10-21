import XCTest
import MapKit
@testable import Wander

final class LiveMapSearchPolicyTests: XCTestCase {
    private let layout = LiveMapSearchLayout(size: CGSize(width: 390, height: 800), controlsHeight: 120, drawerHeight: 384)

    func testInitialAndProgrammaticCameraChangesDoNotOfferSearch() {
        var state = LiveMapSearchState()
        state.observe(camera: camera(), layout: layout, positionedByUser: false)
        state.observe(camera: camera(latitude: 40), layout: layout, positionedByUser: false)
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 40), layout: layout, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testUserPanZoomAndRotationOfferSearchWithoutAQueryCommit() {
        for moved in [camera(latitude: 34.1), camera(distance: 4_000), camera(heading: 20), camera(pitch: 20)] {
            var state = initializedState()
            state.observe(camera: moved, layout: layout, positionedByUser: true)
            XCTAssertTrue(state.shouldOfferSearch)
        }
    }

    func testSettlingNoiseAndEquivalentWrappedHeadingDoNotOfferSearch() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 34.000001, distance: 5_001, heading: 360),
                      layout: layout, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testReturningToUnsearchedCameraRemovesPendingSearch() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
        state.observe(camera: camera(), layout: layout, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testCommitHidesSearchUntilAnotherUserMovement() {
        var state = initializedState()
        let moved = camera(latitude: 35)
        state.observe(camera: moved, layout: layout, positionedByUser: true)
        state.didCommit()
        state.observe(camera: moved, layout: layout, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 35.1), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
    }

    func testDrawerAndControlLayoutChangesNeverCreatePendingSearch() {
        var state = initializedState()
        let collapsed = LiveMapSearchLayout(size: layout.size, controlsHeight: 120, drawerHeight: 70)
        let reframed = camera(latitude: 34.01)
        state.observe(camera: reframed, layout: collapsed, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: reframed, layout: collapsed, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
        let largerText = LiveMapSearchLayout(size: layout.size, controlsHeight: 190, drawerHeight: 70)
        state.observe(camera: camera(latitude: 34.02), layout: largerText, positionedByUser: true)
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testDrawerLayoutDoesNotDiscardAnAlreadyPendingSearch() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        let expanded = LiveMapSearchLayout(size: layout.size, controlsHeight: 0, drawerHeight: 792)
        state.observe(camera: camera(latitude: 35), layout: expanded, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
    }

    func testProgrammaticRecenterAndNewAccountResetPendingSearch() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        state.willMoveProgrammatically()
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 40), layout: layout, positionedByUser: false)
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 41), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
        state = LiveMapSearchState()
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testAnimatedDrawerRebasesAllProgrammaticCallbacksThenAcceptsNextRealPan() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        state.didCommit()
        let collapsed = LiveMapSearchLayout(size: layout.size, controlsHeight: 120, drawerHeight: 70)
        state.rebaseForPresentationChange()
        // The view writes the exact current pose as a programmatic position.
        // Native insets then settle through multiple poses at the final layout.
        for latitude in [35.01, 35.02, 35.03] {
            state.observe(camera: camera(latitude: latitude), layout: collapsed, positionedByUser: false)
            XCTAssertFalse(state.shouldOfferSearch)
        }
        state.observe(camera: camera(latitude: 35.04), layout: collapsed, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
    }

    func testTabOrDetailReturnRebasesEvenWhenFinalLayoutIsUnchanged() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        state.didCommit()
        state.rebaseForPresentationChange()
        state.observe(camera: camera(latitude: 35.01), layout: layout, positionedByUser: false)
        state.observe(camera: camera(latitude: 35.02), layout: layout, positionedByUser: false)
        XCTAssertFalse(state.shouldOfferSearch)
        state.observe(camera: camera(latitude: 35.03), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
    }

    func testPendingPanSurvivesLayoutAndReturnWithoutCommittingItsQuery() {
        var state = initializedState()
        state.observe(camera: camera(latitude: 35), layout: layout, positionedByUser: true)
        state.rebaseForPresentationChange()
        for latitude in [35.01, 35.02] {
            state.observe(camera: camera(latitude: latitude), layout: layout, positionedByUser: false)
            XCTAssertTrue(state.shouldOfferSearch)
        }
        state.observe(camera: camera(latitude: 35.02), layout: layout, positionedByUser: true)
        XCTAssertTrue(state.shouldOfferSearch)
        state.didCommit()
        state.observe(camera: camera(latitude: 35.02), layout: layout, positionedByUser: false)
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testLayoutCallbackWithStickyUserProvenanceRequestsAnExplicitReset() {
        var state = initializedState()
        let collapsed = LiveMapSearchLayout(size: layout.size, controlsHeight: 120, drawerHeight: 70)
        XCTAssertTrue(state.observe(camera: camera(latitude: 34.01), layout: collapsed, positionedByUser: true))
        XCTAssertFalse(state.shouldOfferSearch)
        // The caller reasserts that exact pose, clearing the retained user bit.
        XCTAssertFalse(state.observe(camera: camera(latitude: 34.02), layout: collapsed, positionedByUser: false))
        XCTAssertFalse(state.shouldOfferSearch)
    }

    func testVisibleMapProjectionExcludesControlsAndDrawer() throws {
        var convertedPoints: [CGPoint] = []
        func coordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
            .init(latitude: 35 - Double(point.y) / 1_000, longitude: -119 + Double(point.x) / 1_000)
        }
        let area = try XCTUnwrap(LiveMapSearchGeometry.area(layout: layout, longitudeSpan: 1) { point in
            convertedPoints.append(point)
            return coordinate(point)
        })
        XCTAssertEqual(layout.visibleRect, CGRect(x: 0, y: 120, width: 390, height: 296))
        XCTAssertEqual(convertedPoints, [CGPoint(x: 0, y: 0), CGPoint(x: 390, y: 0),
                                         CGPoint(x: 390, y: 296), CGPoint(x: 0, y: 296)])
        XCTAssertTrue(area.contains(coordinate(CGPoint(x: 195, y: 148))))
        XCTAssertFalse(area.contains(coordinate(CGPoint(x: 195, y: -60))))
        XCTAssertFalse(area.contains(coordinate(CGPoint(x: 195, y: 356))))
    }

    func testContentProjectionDoesNotDoubleCountControlsOrSystemSafeAreas() throws {
        // First row is the measured native geometry: outer y62/height729,
        // inset Map y188/height533, drawer y721. Other rows cover a compact
        // phone and taller controls/half drawer. All coordinates are points.
        let cases: [(screen: CGSize, top: CGFloat, bottom: CGFloat, controls: CGFloat,
                     drawer: CGFloat, expected: CGRect)] = [
            (.init(width: 402, height: 874), 62, 83, 126, 70,
             .init(x: 0, y: 188, width: 402, height: 533)),
            (.init(width: 375, height: 667), 20, 49, 126, 70,
             .init(x: 0, y: 146, width: 375, height: 402)),
            (.init(width: 402, height: 874), 62, 83, 190, 350,
             .init(x: 0, y: 252, width: 402, height: 189))
        ]
        for sample in cases {
            let layout = LiveMapSearchLayout(
                size: CGSize(width: sample.screen.width, height: sample.screen.height - sample.top - sample.bottom),
                controlsHeight: sample.controls, drawerHeight: sample.drawer)
            var screenPoints: [CGPoint] = []
            func coordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
                .init(latitude: 35 - Double(point.y) / 1_000, longitude: -119 + Double(point.x) / 1_000)
            }
            let area = try XCTUnwrap(LiveMapSearchGeometry.area(layout: layout, longitudeSpan: 1) { local in
                // Reproduce the measured MapProxy local-to-screen basis.
                let screen = CGPoint(x: local.x, y: local.y + sample.top + sample.controls)
                screenPoints.append(screen)
                return coordinate(screen)
            })
            let rect = sample.expected
            XCTAssertEqual(screenPoints, [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                          CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
            XCTAssertTrue(area.contains(coordinate(CGPoint(x: rect.midX, y: rect.midY))))
            XCTAssertFalse(area.contains(coordinate(CGPoint(x: rect.midX, y: rect.minY - 10))))
            XCTAssertFalse(area.contains(coordinate(CGPoint(x: rect.midX, y: rect.maxY + 10))))
        }
    }

    func testProjectionPreservesRotatedFootprintInsteadOfEnclosingRegion() throws {
        let area = try XCTUnwrap(LiveMapSearchGeometry.area(layout: layout, longitudeSpan: 2) { point in
            .init(latitude: 34 + Double(point.x + point.y) / 1_000,
                  longitude: -118 + Double(point.x - point.y) / 1_000)
        })
        XCTAssertTrue(area.contains(.init(latitude: 34.343, longitude: -117.953)))
        XCTAssertFalse(area.contains(.init(latitude: 34.18, longitude: -118.22)),
                       "A point inside the enclosing latitude/longitude box can still be offscreen.")
    }

    func testAntimeridianProjectionKeepsBothEdgesWithoutOppositeWorld() throws {
        let worldEdge = LiveMapSearchLayout(size: CGSize(width: 200, height: 200), controlsHeight: 0, drawerHeight: 0)
        let area = try XCTUnwrap(LiveMapSearchGeometry.area(layout: worldEdge, longitudeSpan: 2) { point in
            let longitude = 179 + Double(point.x) / 100
            return .init(latitude: Double(point.y) / 100,
                         longitude: longitude > 180 ? longitude - 360 : longitude)
        })
        XCTAssertTrue(area.contains(.init(latitude: 1, longitude: 179.5)))
        XCTAssertTrue(area.contains(.init(latitude: 1, longitude: -179.5)))
        XCTAssertFalse(area.contains(.init(latitude: 1, longitude: 0)))
    }

    func testTooWideOrOccludedMapDoesNotProjectOrBroadenQuery() {
        var conversions = 0
        for span in [180.0, 360.0, .infinity, .nan, 0.0] {
            XCTAssertNil(LiveMapSearchGeometry.area(layout: layout, longitudeSpan: span) { _ in
                conversions += 1
                return .init(latitude: 34, longitude: -118)
            })
        }
        let hidden = LiveMapSearchLayout(size: layout.size, controlsHeight: 120, drawerHeight: 792)
        XCTAssertNil(LiveMapSearchGeometry.area(layout: hidden, longitudeSpan: 1) { _ in
            conversions += 1
            return .init(latitude: 34, longitude: -118)
        })
        XCTAssertEqual(conversions, 0)
    }

    func testMissingMapProjectionRejectsEntireArea() {
        var conversions = 0
        XCTAssertNil(LiveMapSearchGeometry.area(layout: layout, longitudeSpan: 1) { point in
            conversions += 1
            return point.x == 0 ? nil : .init(latitude: Double(point.y) / 100, longitude: -118)
        })
        XCTAssertEqual(conversions, 4)
    }

    func testAreaOriginHasCorrectDrawingActionAndSummary() throws {
        let area = try XCTUnwrap(LiveDrawnArea(coordinates: [
            .init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 2),
            .init(latitude: 2, longitude: 2), .init(latitude: 2, longitude: 0)]))
        let searched = LiveSelectedArea.mapViewport(area)
        let drawn = LiveSelectedArea.drawn(area)
        XCTAssertEqual(searched.boundary, drawn.boundary)
        XCTAssertEqual(searched.summary, "Map area")
        XCTAssertEqual(searched.drawActionTitle, "Draw area")
        XCTAssertEqual(drawn.summary, "Drawn area")
        XCTAssertEqual(drawn.drawActionTitle, "Redraw")
    }

    private func initializedState() -> LiveMapSearchState {
        var state = LiveMapSearchState()
        state.observe(camera: camera(), layout: layout, positionedByUser: false)
        return state
    }

    private func camera(latitude: Double = 34, distance: Double = 5_000,
                        heading: Double = 0, pitch: Double = 0) -> LiveMapSearchCamera {
        .init(latitude: latitude, longitude: -118, distance: distance, heading: heading, pitch: pitch)
    }
}
