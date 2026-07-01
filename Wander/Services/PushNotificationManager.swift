import Foundation
import UIKit
import UserNotifications

final class WanderAppDelegate: NSObject, UIApplicationDelegate {
    static let didRegisterForRemoteNotifications = Notification.Name("WanderDidRegisterForRemoteNotifications")
    static let didFailToRegisterForRemoteNotifications = Notification.Name("WanderDidFailToRegisterForRemoteNotifications")
    static let deviceTokenKey = "deviceToken"
    static let errorKey = "error"

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(
            name: Self.didRegisterForRemoteNotifications,
            object: nil,
            userInfo: [Self.deviceTokenKey: deviceToken]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: Self.didFailToRegisterForRemoteNotifications,
            object: nil,
            userInfo: [Self.errorKey: error]
        )
    }
}

@MainActor
final class PushNotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var isRegisteringToken = false
    @Published private(set) var lastErrorMessage: String?

    private let userDefaults: UserDefaults
    private let tokenKey = "wander.apnsDeviceToken"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var statusTitle: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Off in iOS Settings"
        case .notDetermined:
            return "Not set up"
        @unknown default:
            return "Unknown"
        }
    }

    var canRequestAuthorization: Bool {
        authorizationStatus == .notDetermined
    }

    var canRegisterForRemoteNotifications: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationAndRegister() async {
        isRequestingAuthorization = true
        lastErrorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            lastErrorMessage = "Could not request notification permission."
        }
    }

    func handleRegisteredDeviceToken(_ data: Data, backend: WanderBackend, authState: AuthState) async {
        let token = Self.hexString(from: data)
        userDefaults.set(token, forKey: tokenKey)
        await registerStoredDeviceTokenIfPossible(backend: backend, authState: authState)
    }

    func handleRegistrationFailure(_ error: Error) {
        lastErrorMessage = "Could not register this device for notifications."
        #if DEBUG
        WanderDebugLog.remote.error("push token registration failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
        #endif
    }

    func registerStoredDeviceTokenIfPossible(backend: WanderBackend, authState: AuthState) async {
        guard case .signedIn = authState,
              backend.canRegisterPushNotifications,
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return
        }

        isRegisteringToken = true
        lastErrorMessage = nil
        defer { isRegisteringToken = false }

        do {
            _ = try await backend.registerPushToken(
                token,
                environment: Self.environment,
                appBundleID: Bundle.main.bundleIdentifier ?? "com.grayline.wander"
            )
        } catch {
            lastErrorMessage = "Could not sync notification settings."
            #if DEBUG
            WanderDebugLog.remote.error("push token sync failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    func unregisterStoredDeviceTokenIfPossible(backend: WanderBackend) async {
        guard backend.canRegisterPushNotifications,
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return
        }

        do {
            try await backend.unregisterPushToken(token, environment: Self.environment)
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("push token unregister failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    static var environment: PushTokenEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
