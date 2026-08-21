import XCTest
@testable import Wander

final class AddCameraPresentationTests: XCTestCase {
    func testAuthorizedAvailableCameraPresentsFullScreenCaptureRoute() {
        var presentation = AddCameraPresentationState()

        let requestsPermission = presentation.requestCamera(
            isAvailable: true,
            authorization: .authorized
        )

        XCTAssertFalse(requestsPermission)
        XCTAssertEqual(presentation.route, .camera)
    }

    func testUnavailableCameraPresentsRecoverableState() {
        var presentation = AddCameraPresentationState()

        let requestsPermission = presentation.requestCamera(
            isAvailable: false,
            authorization: .authorized
        )

        XCTAssertFalse(requestsPermission)
        XCTAssertEqual(presentation.route, .unavailable)
    }

    func testDeniedCameraPresentsPermissionRecovery() {
        var presentation = AddCameraPresentationState()

        let requestsPermission = presentation.requestCamera(
            isAvailable: true,
            authorization: .denied
        )

        XCTAssertFalse(requestsPermission)
        XCTAssertEqual(presentation.route, .permissionDenied)
    }

    func testUndeterminedCameraWaitsForPermissionBeforePresentation() {
        var presentation = AddCameraPresentationState()

        let requestsPermission = presentation.requestCamera(
            isAvailable: true,
            authorization: .notDetermined
        )

        XCTAssertTrue(requestsPermission)
        XCTAssertNil(presentation.route)

        presentation.completePermissionRequest(granted: true, isAvailable: true)

        XCTAssertEqual(presentation.route, .camera)
    }

    func testDeniedPermissionRequestEndsInRecoveryState() {
        var presentation = AddCameraPresentationState()
        _ = presentation.requestCamera(
            isAvailable: true,
            authorization: .notDetermined
        )

        presentation.completePermissionRequest(granted: false, isAvailable: true)

        XCTAssertEqual(presentation.route, .permissionDenied)
    }

    func testGallerySwitchWaitsForCameraDismissalAndConsumesOnce() {
        var presentation = AddCameraPresentationState(route: .camera)

        presentation.switchToPhotoLibrary()

        XCTAssertNil(presentation.route)
        XCTAssertTrue(presentation.presentsPhotoLibraryAfterDismissal)
        XCTAssertTrue(presentation.consumePhotoLibraryPresentation())
        XCTAssertFalse(presentation.consumePhotoLibraryPresentation())
    }

    func testCameraCancelClearsRouteWithoutOpeningLibrary() {
        var presentation = AddCameraPresentationState(route: .camera)

        presentation.dismissCapture()

        XCTAssertNil(presentation.route)
        XCTAssertFalse(presentation.consumePhotoLibraryPresentation())
    }
}
