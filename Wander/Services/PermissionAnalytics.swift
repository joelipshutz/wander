import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Photos
import UserNotifications

/// Read authorization only. This never prompts, reads personal content, or starts location updates.
enum PermissionAnalytics {
    enum Status: String {
        case enabled, limited, denied, restricted, notDetermined = "not_determined", unknown
    }

    static func event(permission: String, status: Status) -> AnalyticsEvent {
        AnalyticsEvent(name: "permission_status_observed", properties: [
            "permission": permission,
            "status": status.rawValue,
            "enabled": status == .enabled || status == .limited ? "true" : "false",
            "observation_source": "system_settings"
        ])
    }

    @MainActor
    static func currentEvents() async -> [AnalyticsEvent] {
        let notifications = await UNUserNotificationCenter.current().notificationSettings()
        let location = CLLocationManager()
        return [
            event(permission: "notifications", status: notificationStatus(notifications.authorizationStatus)),
            event(permission: "location", status: locationStatus(location.authorizationStatus)),
            event(permission: "contacts", status: contactsStatus(CNContactStore.authorizationStatus(for: .contacts))),
            event(permission: "camera", status: cameraStatus(AVCaptureDevice.authorizationStatus(for: .video))),
            event(permission: "microphone", status: microphoneStatus(AVAudioApplication.shared.recordPermission)),
            event(permission: "calendar", status: calendarStatus(EKEventStore.authorizationStatus(for: .event))),
            event(permission: "save_photos", status: photoStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly)))
        ]
    }

    static func notificationStatus(_ value: UNAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .enabled
        case .provisional, .ephemeral: .limited
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func locationStatus(_ value: CLAuthorizationStatus) -> Status {
        switch value {
        case .authorizedAlways, .authorizedWhenInUse: .enabled
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func contactsStatus(_ value: CNAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .enabled
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func cameraStatus(_ value: AVAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .enabled
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func microphoneStatus(_ value: AVAudioApplication.recordPermission) -> Status {
        switch value {
        case .granted: .enabled
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func calendarStatus(_ value: EKAuthorizationStatus) -> Status {
        switch value {
        case .fullAccess: .enabled
        // Write-only access cannot support the app's reservation import.
        case .writeOnly: .restricted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        default: .unknown
        }
    }

    static func photoStatus(_ value: PHAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .enabled
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }
}
