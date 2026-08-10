import XCTest
@testable import Wander

final class ProfilePhotoCropStateTests: XCTestCase {
    private let landscapeImage = CGSize(width: 1_200, height: 800)
    private let viewport = CGSize(width: 300, height: 300)

    func testInitialCropCentersTheLargestSquareInsideLandscapeImage() {
        let state = ProfilePhotoCropState()

        let rect = state.sourceCropRect(
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        XCTAssertEqual(rect.origin.x, 200, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 800, accuracy: 0.001)
        XCTAssertEqual(rect.height, 800, accuracy: 0.001)
    }

    func testZoomNarrowsTheSelectedSourceRegionAroundCenter() {
        var state = ProfilePhotoCropState()
        state.finishMagnification(
            2,
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        let rect = state.sourceCropRect(
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        XCTAssertEqual(state.scale, 2, accuracy: 0.001)
        XCTAssertEqual(rect.origin.x, 400, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 200, accuracy: 0.001)
        XCTAssertEqual(rect.width, 400, accuracy: 0.001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
    }

    func testDragMovesCropToTheVisibleImageArea() {
        var state = ProfilePhotoCropState()
        state.finishMagnification(
            2,
            imageSize: landscapeImage,
            viewportSize: viewport
        )
        state.finishDrag(
            CGSize(width: 150, height: -150),
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        let rect = state.sourceCropRect(
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        XCTAssertEqual(rect.origin.x, 200, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 400, accuracy: 0.001)
        XCTAssertEqual(rect.width, 400, accuracy: 0.001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
    }

    func testZoomAndDragClampToSupportedImageBounds() {
        var state = ProfilePhotoCropState()
        state.finishMagnification(
            20,
            imageSize: landscapeImage,
            viewportSize: viewport
        )
        state.finishDrag(
            CGSize(width: 10_000, height: 10_000),
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        let rect = state.sourceCropRect(
            imageSize: landscapeImage,
            viewportSize: viewport
        )

        XCTAssertEqual(state.scale, ProfilePhotoCropState.maximumScale)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, landscapeImage.width + 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, landscapeImage.height + 0.001)
    }
}
