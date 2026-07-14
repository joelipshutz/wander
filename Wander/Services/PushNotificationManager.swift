import Foundation
import UIKit
@preconcurrency import UserNotifications

private final class NotificationUserInfoBox: @unchecked Sendable {
    let value: [AnyHashable: Any]

    init(_ value: [AnyHashable: Any]) {
        self.value = value
    }
}

private final class NotificationResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[AnyHashable: Any]] = []

    func append(_ value: [AnyHashable: Any]) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func takeFirst() -> [AnyHashable: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

final class WanderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let didRegisterForRemoteNotifications = Notification.Name("WanderDidRegisterForRemoteNotifications")
    static let didFailToRegisterForRemoteNotifications = Notification.Name("WanderDidFailToRegisterForRemoteNotifications")
    nonisolated static let didReceiveNotificationResponse = Notification.Name("WanderDidReceiveNotificationResponse")
    nonisolated static let didReceiveRemoteNotification = Notification.Name("WanderDidReceiveRemoteNotification")
    static let deviceTokenKey = "deviceToken"
    static let errorKey = "error"
    nonisolated static let userInfoKey = "userInfo"
    private nonisolated static let notificationResponseBuffer = NotificationResponseBuffer()

    static func takePendingNotificationUserInfo() -> [AnyHashable: Any]? {
        notificationResponseBuffer.takeFirst()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let boxedUserInfo = NotificationUserInfoBox(notification.request.content.userInfo)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Self.didReceiveRemoteNotification,
                object: nil,
                userInfo: [Self.userInfoKey: boxedUserInfo.value]
            )
        }
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let boxedUserInfo = NotificationUserInfoBox(response.notification.request.content.userInfo)
        Self.notificationResponseBuffer.append(boxedUserInfo.value)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Self.didReceiveNotificationResponse,
                object: nil,
                userInfo: [Self.userInfoKey: boxedUserInfo.value]
            )
        }
        completionHandler()
    }
}

enum NotificationPeopleMode: String, Equatable {
    case following
    case followers
    case friends
}

enum NotificationDestination: Equatable {
    case people(NotificationPeopleMode)
    case list(id: String)
    case place(id: String)
    case sharedVisit(participantID: String, generation: Int)
    case drafts(extractionJobID: String?)
    case discover
}

struct NotificationNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let destination: NotificationDestination
}

@MainActor
final class PushNotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var isRegisteringToken = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var navigationRequest: NotificationNavigationRequest?

    private let userDefaults: UserDefaults
    private let tokenKey = "wander.apnsDeviceToken"
    private var handledEventIDs: [String] = []

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

    func clearLastError() {
        lastErrorMessage = nil
    }

    @discardableResult
    func requestAuthorizationAndRegister() async -> Bool {
        isRequestingAuthorization = true
        lastErrorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            lastErrorMessage = "Could not request notification permission."
            return false
        }
    }

    func enableNotifications(
        backend: WanderBackend,
        authState: AuthState
    ) async -> NotificationPreferences? {
        guard case .signedIn = authState, backend.canRegisterPushNotifications else {
            lastErrorMessage = "Sign in to turn on notifications."
            return nil
        }

        lastErrorMessage = nil
        await refreshAuthorizationStatus()
        if authorizationStatus == .denied {
            lastErrorMessage = "Enable alerts in iOS Settings, then try again."
            return nil
        }

        if authorizationStatus == .notDetermined {
            guard await requestAuthorizationAndRegister() else { return nil }
        } else {
            UIApplication.shared.registerForRemoteNotifications()
        }

        guard let token = await storedDeviceTokenWaitingForRegistration() else {
            lastErrorMessage = "This device did not finish registering with Apple. Try again."
            await disablePreferencesAfterFailedEnrollment(backend: backend)
            return nil
        }

        isRegisteringToken = true
        defer { isRegisteringToken = false }

        do {
            _ = try await backend.registerPushToken(
                token,
                environment: Self.environment,
                appBundleID: Bundle.main.bundleIdentifier ?? "com.grayline.wander"
            )
            return try await backend.updateNotificationPreferences(.allEnabled)
        } catch {
            try? await backend.unregisterPushToken(token, environment: Self.environment)
            await disablePreferencesAfterFailedEnrollment(backend: backend)
            lastErrorMessage = "rec.me could not finish notification setup. Try again."
            #if DEBUG
            WanderDebugLog.remote.error("transactional push enrollment failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            return nil
        }
    }

    func disableNotifications(backend: WanderBackend) async -> NotificationPreferences? {
        guard backend.canRegisterPushNotifications else { return nil }
        lastErrorMessage = nil

        do {
            let preferences = try await backend.updateNotificationPreferences(.allDisabled)
            _ = await unregisterStoredDeviceTokenIfPossible(backend: backend)
            return preferences
        } catch {
            lastErrorMessage = "Could not disable notifications. Try again."
            return nil
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

    @discardableResult
    func registerStoredDeviceTokenIfPossible(backend: WanderBackend, authState: AuthState) async -> Bool {
        guard case .signedIn = authState,
              backend.canRegisterPushNotifications,
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return false
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
            return true
        } catch {
            lastErrorMessage = "Could not sync notification settings."
            #if DEBUG
            WanderDebugLog.remote.error("push token sync failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            return false
        }
    }

    @discardableResult
    func unregisterStoredDeviceTokenIfPossible(backend: WanderBackend) async -> Bool {
        guard backend.canRegisterPushNotifications,
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return true
        }

        do {
            try await backend.unregisterPushToken(token, environment: Self.environment)
            return true
        } catch {
            lastErrorMessage = "Notifications are off, but this device could not be fully disconnected."
            #if DEBUG
            WanderDebugLog.remote.error("push token unregister failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            return false
        }
    }

    @discardableResult
    func handleNotificationResponse(userInfo: [AnyHashable: Any]) -> Bool {
        let eventID = Self.eventID(from: userInfo)
        if let eventID, handledEventIDs.contains(eventID) {
            return false
        }
        guard let destination = Self.destination(from: userInfo) else { return false }
        if let eventID {
            handledEventIDs.append(eventID)
            if handledEventIDs.count > 100 {
                handledEventIDs.removeFirst(handledEventIDs.count - 100)
            }
        }
        navigationRequest = NotificationNavigationRequest(destination: destination)
        return true
    }

    func openSharedVisit(participantID: String, generation: Int) {
        navigationRequest = NotificationNavigationRequest(
            destination: .sharedVisit(participantID: participantID, generation: generation)
        )
    }

    func consumeNavigationRequest(id: UUID) {
        guard navigationRequest?.id == id else { return }
        navigationRequest = nil
    }

    static func destination(from userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        let payload = userInfo["recme"] as? [String: Any]
        let notificationType = payload?["notification_type"] as? String
        let deeplink = (payload?["deeplink_url"] as? String).flatMap(URL.init(string:))
        let data = payload?["data"] as? [String: Any]

        if let deeplink, let destination = destination(from: deeplink, notificationType: notificationType) {
            return destination
        }

        switch notificationType {
        case "followed_you":
            return .people(.followers)
        case "mutual_follow":
            return .people(.friends)
        case "list_collaborator_added", "list_place_added":
            return (data?["list_id"] as? String).map { .list(id: $0) }
        case "place_saved_from_your_map", "followed_place_visit":
            return (data?["place_id"] as? String).map { .place(id: $0) }
        case "shared_visit":
            guard let participantID = data?["participant_id"] as? String,
                  let generation = integerValue(data?["invitation_generation"])
            else { return nil }
            return .sharedVisit(participantID: participantID, generation: generation)
        case "capture_ready":
            return .drafts(extractionJobID: data?["extraction_job_id"] as? String)
        case "followed_activity_digest":
            return .discover
        default:
            return nil
        }
    }

    private static func eventID(from userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["recme"] as? [String: Any])?["event_id"] as? String
    }

    static func destination(
        from url: URL,
        notificationType: String? = nil
    ) -> NotificationDestination? {
        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard let root = components.first else { return nil }
        let identifier = components.dropFirst().first

        switch root {
        case "profiles", "profile":
            return .people(notificationType == "mutual_follow" ? .friends : .followers)
        case "lists":
            return identifier.map { .list(id: $0) }
        case "places":
            return identifier.map { .place(id: $0) }
        case "shared-visits":
            guard let identifier,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let generationString = components.queryItems?.first(where: { $0.name == "generation" })?.value,
                  let generation = Int(generationString)
            else { return nil }
            return .sharedVisit(participantID: identifier, generation: generation)
        case "extraction-jobs":
            return .drafts(extractionJobID: identifier)
        case "discover":
            return .discover
        default:
            return nil
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

    private func storedDeviceTokenWaitingForRegistration() async -> String? {
        if let token = userDefaults.string(forKey: tokenKey), !token.isEmpty {
            return token
        }

        UIApplication.shared.registerForRemoteNotifications()
        for _ in 0..<80 {
            if let token = userDefaults.string(forKey: tokenKey), !token.isEmpty {
                return token
            }
            try? await Task.sleep(for: .milliseconds(125))
        }
        return nil
    }

    private func disablePreferencesAfterFailedEnrollment(backend: WanderBackend) async {
        _ = try? await backend.updateNotificationPreferences(.allDisabled)
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
