import Contacts
import CoreLocation
import Foundation

enum OnboardingLocationPermissionAction: Equatable {
    case skip
    case request
    case openSettings
    case continueWithoutAccess
}

enum OnboardingLocationPermissionPolicy {
    static func action(for status: CLAuthorizationStatus) -> OnboardingLocationPermissionAction {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            .skip
        case .notDetermined:
            .request
        case .denied:
            .openSettings
        case .restricted:
            .continueWithoutAccess
        @unknown default:
            .continueWithoutAccess
        }
    }

    static func primaryTitle(for status: CLAuthorizationStatus) -> String {
        switch action(for: status) {
        case .skip, .request:
            "Use my location"
        case .openSettings:
            "Open Settings"
        case .continueWithoutAccess:
            "Continue without location"
        }
    }
}

@MainActor
final class OnboardingContactsPermissionManager: ObservableObject {
    @Published private(set) var authorizationStatus: CNAuthorizationStatus

    private let store: CNContactStore

    init(store: CNContactStore = CNContactStore()) {
        self.store = store
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            do {
                let granted = try await store.requestAccess(for: .contacts)
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                return granted
            } catch {
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                return false
            }
        @unknown default:
            return false
        }
    }
}

@MainActor
final class OnboardingLocationPermissionManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<Bool, Never>?

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    @discardableResult
    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard authorizationStatus != .notDetermined else { return }
        let granted = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        continuation?.resume(returning: granted)
        continuation = nil
    }
}
