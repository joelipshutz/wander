import XCTest
@testable import Wander

final class PhotoZoomStateTests: XCTestCase {
    private let viewport = CGSize(width: 320, height: 480)

    func testMagnificationClampsToSupportedScaleRange() {
        var state = PhotoZoomState()

        state.finishMagnification(10, viewportSize: viewport)
        XCTAssertEqual(state.scale, PhotoZoomState.maximumScale)

        state.finishMagnification(0.01, viewportSize: viewport)
        XCTAssertEqual(state.scale, PhotoZoomState.minimumScale)
        XCTAssertEqual(state.offset, .zero)
    }

    func testDragIsIgnoredUntilPhotoIsZoomed() {
        var state = PhotoZoomState()

        state.finishDrag(CGSize(width: 80, height: -60), viewportSize: viewport)

        XCTAssertEqual(state.offset, .zero)
    }

    func testZoomedDragIsClampedInsideViewportBounds() {
        var state = PhotoZoomState()
        state.finishMagnification(2, viewportSize: viewport)

        state.finishDrag(CGSize(width: 1_000, height: -1_000), viewportSize: viewport)

        XCTAssertEqual(state.offset.width, 160)
        XCTAssertEqual(state.offset.height, -240)
    }

    func testDoubleTapTogglesBetweenTwoTimesAndRestingScale() {
        var state = PhotoZoomState()

        state.toggleZoom(viewportSize: viewport)
        XCTAssertEqual(state.scale, 2)
        XCTAssertTrue(state.isZoomed)

        state.finishDrag(CGSize(width: 40, height: 50), viewportSize: viewport)
        state.toggleZoom(viewportSize: viewport)
        XCTAssertEqual(state.scale, PhotoZoomState.minimumScale)
        XCTAssertEqual(state.offset, .zero)
        XCTAssertFalse(state.isZoomed)
    }

    func testAccessibilityZoomActionsRespectLimitsAndResetOffset() {
        var state = PhotoZoomState()

        for _ in 0..<10 {
            state.zoomIn(viewportSize: viewport)
        }
        XCTAssertEqual(state.scale, PhotoZoomState.maximumScale)

        state.finishDrag(CGSize(width: 50, height: 50), viewportSize: viewport)
        for _ in 0..<10 {
            state.zoomOut(viewportSize: viewport)
        }
        XCTAssertEqual(state.scale, PhotoZoomState.minimumScale)
        XCTAssertEqual(state.offset, .zero)
    }

    func testProductionFullScreenPhotoViewersUseSharedZoomSurface() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gallerySource = try String(
            contentsOf: projectRoot
                .appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift"),
            encoding: .utf8
        )
        let activitySource = try String(
            contentsOf: projectRoot
                .appendingPathComponent("Wander/Features/Map/MapScreen.swift"),
            encoding: .utf8
        )
        let profileSource = try String(
            contentsOf: projectRoot
                .appendingPathComponent("Wander/Features/Profile/ProfileEditScreen.swift"),
            encoding: .utf8
        )

        let galleryViewer = try XCTUnwrap(
            gallerySource
                .components(separatedBy: "private struct PlacePhotoGalleryViewer: View")
                .dropFirst()
                .first?
                .components(separatedBy: "private var positionIndicator")
                .first
        )
        let activityViewer = try XCTUnwrap(
            activitySource
                .components(separatedBy: "private struct PlaceActivityPhotoViewer: View")
                .dropFirst()
                .first?
                .components(separatedBy: "private struct VisitPhotoFullScreenImage: View")
                .first
        )
        let profileViewer = try XCTUnwrap(
            profileSource
                .components(separatedBy: "struct ProfilePhotoFullScreenViewer: View")
                .dropFirst()
                .first?
                .components(separatedBy: "private struct ProfileEditFieldRow: View")
                .first
        )

        XCTAssertTrue(galleryViewer.contains("ZoomablePhoto {"))
        XCTAssertTrue(activityViewer.contains("ZoomablePhoto {"))
        XCTAssertTrue(profileViewer.contains("ZoomablePhoto {"))
    }
}
