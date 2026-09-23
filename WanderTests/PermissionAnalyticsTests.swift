import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import UserNotifications
import XCTest
@testable import Wander

final class PermissionAnalyticsTests: XCTestCase {
    func testLimitedAccessAndUnaskedPermissionsRemainDistinct() {
        XCTAssertEqual(PermissionAnalytics.notificationStatus(.provisional), .limited)
        XCTAssertEqual(PermissionAnalytics.notificationStatus(.notDetermined), .notDetermined)
        if #available(iOS 18.0, *) {
            XCTAssertEqual(PermissionAnalytics.contactsStatus(.limited), .limited)
        }
        XCTAssertEqual(PermissionAnalytics.contactsStatus(.restricted), .restricted)
        XCTAssertEqual(PermissionAnalytics.locationStatus(.authorizedWhenInUse), .enabled)
        XCTAssertEqual(PermissionAnalytics.locationStatus(.authorizedAlways), .enabled)
        XCTAssertEqual(PermissionAnalytics.locationStatus(.denied), .denied)
    }

    func testCalendarWriteOnlyCannotEnableReservationImport() {
        XCTAssertEqual(PermissionAnalytics.calendarStatus(.writeOnly), .restricted)
        XCTAssertEqual(PermissionAnalytics.calendarStatus(.fullAccess), .enabled)
        XCTAssertEqual(PermissionAnalytics.calendarStatus(.notDetermined), .notDetermined)
    }

    func testMediaPermissionsAndUnknownsDoNotBecomeEnabled() {
        XCTAssertEqual(PermissionAnalytics.cameraStatus(.denied), .denied)
        XCTAssertEqual(PermissionAnalytics.microphoneStatus(.undetermined), .notDetermined)
        XCTAssertEqual(PermissionAnalytics.microphoneStatus(.granted), .enabled)
        XCTAssertEqual(PermissionAnalytics.photoStatus(.authorized), .enabled)
        let unknown = PermissionAnalytics.event(permission: "camera", status: .unknown)
        XCTAssertEqual(unknown.properties["enabled"], "false")
        XCTAssertEqual(unknown.properties["status"], "unknown")
    }

    @MainActor
    func testReadingSystemSettingsReturnsOnlySevenCoarsePermissionObservations() async {
        let events = await PermissionAnalytics.currentEvents()
        XCTAssertEqual(Set(events.compactMap { $0.properties["permission"] }), [
            "notifications", "location", "contacts", "camera", "microphone", "calendar", "save_photos"
        ])
        XCTAssertEqual(events.count, 7)
        for event in events {
            XCTAssertEqual(event.name, "permission_status_observed")
            XCTAssertEqual(Set(event.properties.keys), ["permission", "status", "enabled", "observation_source"])
            XCTAssertEqual(WanderAnalyticsSchema.sanitized(event), event)
        }
    }
}
