import Foundation
import UIKit
@preconcurrency import UserNotifications

private final class NotificationUserInfoBox: @unchecked Sendable {
    let value: [AnyHashable: Any]

    init(_ value: [AnyHashable: Any]) {
        self.value = value
    }
}

private final class AuthenticatedNotificationGate: @unchecked Sendable {
    private enum State: Equatable {
        case unknown
        case authenticated
        case signedOut
    }

    private struct PendingResponse {
        let userInfo: [AnyHashable: Any]
        let expectedUserID: String
        let validationGeneration: Int
    }

    private let lock = NSLock()
    private var state: State = .unknown
    private var authenticatedUserID: String?
    private var expectedUserID: String?
    private var validationGeneration = 0
    private var pendingResponses: [PendingResponse] = []

    func beginValidation(expectedUserID: String?) {
        lock.lock()
        defer { lock.unlock() }
        if state == .unknown, self.expectedUserID == expectedUserID {
            return
        }
        state = .unknown
        authenticatedUserID = nil
        self.expectedUserID = expectedUserID
        validationGeneration &+= 1
        pendingResponses.removeAll()
    }

    func authenticate(userID: String) {
        lock.lock()
        defer { lock.unlock() }
        state = .authenticated
        authenticatedUserID = userID
        expectedUserID = userID
        pendingResponses.removeAll {
            $0.expectedUserID != userID || $0.validationGeneration != validationGeneration
        }
    }

    func signOut() {
        lock.lock()
        state = .signedOut
        authenticatedUserID = nil
        expectedUserID = nil
        validationGeneration &+= 1
        pendingResponses.removeAll()
        lock.unlock()
    }

    func receive(_ userInfo: [AnyHashable: Any]) -> String? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .authenticated:
            return authenticatedUserID
        case .unknown:
            guard let expectedUserID else { return nil }
            pendingResponses.append(
                PendingResponse(
                    userInfo: userInfo,
                    expectedUserID: expectedUserID,
                    validationGeneration: validationGeneration
                )
            )
            return nil
        case .signedOut:
            return nil
        }
    }

    func takeFirst(for userID: String) -> [AnyHashable: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .authenticated, authenticatedUserID == userID,
              let index = pendingResponses.firstIndex(where: {
                  $0.expectedUserID == userID
                      && $0.validationGeneration == validationGeneration
              })
        else { return nil }
        return pendingResponses.remove(at: index).userInfo
    }

    func isAuthenticated(userID: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .authenticated else { return false }
        return userID.map { $0 == authenticatedUserID } ?? true
    }

    func isBuffering() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .unknown && expectedUserID != nil
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
    private nonisolated static let authenticatedNotificationGate = AuthenticatedNotificationGate()
    private nonisolated static let lastValidatedUserIDKey = "wander.lastValidatedNotificationUserID"

    static func takePendingNotificationUserInfo(for userID: String) -> [AnyHashable: Any]? {
        authenticatedNotificationGate.takeFirst(for: userID)
    }

    nonisolated static func setAuthenticatedSessionActive(userID: String) {
        authenticatedNotificationGate.authenticate(userID: userID)
        UserDefaults.standard.set(userID, forKey: lastValidatedUserIDKey)
    }

    nonisolated static func setAuthenticatedSessionSignedOut() {
        authenticatedNotificationGate.signOut()
        UserDefaults.standard.removeObject(forKey: lastValidatedUserIDKey)
    }

    nonisolated static func beginAuthenticatedSessionValidation(expectedUserID: String? = nil) {
        let expectedUserID = expectedUserID
            ?? UserDefaults.standard.string(forKey: lastValidatedUserIDKey)
        authenticatedNotificationGate.beginValidation(expectedUserID: expectedUserID)
    }

    nonisolated static func shouldAcceptAuthenticatedNotification(for userID: String? = nil) -> Bool {
        authenticatedNotificationGate.isAuthenticated(userID: userID)
    }

    nonisolated static func shouldBufferAuthenticatedNotification() -> Bool {
        authenticatedNotificationGate.isBuffering()
    }

    nonisolated static func receiveAuthenticatedNotificationUserInfo(
        _ userInfo: [AnyHashable: Any]
    ) -> String? {
        authenticatedNotificationGate.receive(userInfo)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.beginAuthenticatedSessionValidation()
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
        guard Self.shouldAcceptAuthenticatedNotification() else {
            completionHandler([])
            return
        }
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
        if let receivingUserID = Self.receiveAuthenticatedNotificationUserInfo(boxedUserInfo.value) {
            Task { @MainActor in
                guard Self.shouldAcceptAuthenticatedNotification(for: receivingUserID) else { return }
                NotificationCenter.default.post(
                    name: Self.didReceiveNotificationResponse,
                    object: nil,
                    userInfo: [Self.userInfoKey: boxedUserInfo.value]
                )
            }
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
    case quickCapture
    case people(NotificationPeopleMode)
    case list(id: String)
    case listInvite(token: String)
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
    @Published private(set) var wannaGoRemindersEnabled: Bool
    @Published private(set) var saveStreakRemindersEnabled = false

    private let userDefaults: UserDefaults
    private let tokenKey = "wander.apnsDeviceToken"
    private static let wannaGoRemindersKey = "wander.wannaGoRemindersEnabled"
    private static let saveStreakRemindersKeyPrefix = "wander.saveStreakRemindersEnabled."
    private var pushEnabled = false
    private var saveStreakReminderUserID: String?
    private var handledEventIDs: [String] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.wannaGoRemindersEnabled = userDefaults.bool(forKey: Self.wannaGoRemindersKey)
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

    func clearAuthenticatedSessionState() {
        navigationRequest = nil
        handledEventIDs.removeAll()
        applyNotificationPreferences(.allDisabled)
        saveStreakReminderUserID = nil
        saveStreakRemindersEnabled = false
        WanderAppDelegate.setAuthenticatedSessionSignedOut()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
            let preferences = try await backend.updateNotificationPreferences(.allEnabled)
            applyNotificationPreferences(preferences)
            return preferences
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
            applyNotificationPreferences(preferences)
            await cancelAllWannaGoReminders()
            await cancelAllSaveStreakReminders()
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
        route(to: .sharedVisit(participantID: participantID, generation: generation))
    }

    /// Reuses the app's existing cross-tab destination handoff for in-app
    /// actions (for example, Feed's `View list`) as well as push responses.
    func route(to destination: NotificationDestination) {
        navigationRequest = NotificationNavigationRequest(destination: destination)
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
        case SaveStreakReminderPlanner.notificationType:
            return .quickCapture
        case "followed_you":
            return .people(.followers)
        case "mutual_follow":
            return .people(.friends)
        case "list_collaborator_added", "list_place_added":
            return (data?["list_id"] as? String).map { .list(id: $0) }
        case "place_saved_from_your_map", "followed_place_visit", WannaGoReminderPlanner.notificationType:
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
        if let route = WanderDeepLinkRoute.parse(url) {
            switch route {
            case .quickCapture:
                return .quickCapture
            case .sharedProfile:
                return .people(notificationType == "mutual_follow" ? .friends : .followers)
            case .sharedPlace(let placeID):
                return .place(id: placeID)
            case .sharedList(let listID):
                return .list(id: listID)
            case .listInvite(let token):
                return .listInvite(token: token)
            default:
                break
            }
        }

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

    func applyNotificationPreferences(_ preferences: NotificationPreferences) {
        pushEnabled = preferences.pushEnabled
        wannaGoRemindersEnabled = preferences.pushEnabled && preferences.wannaGoRemindersEnabled
        userDefaults.set(wannaGoRemindersEnabled, forKey: Self.wannaGoRemindersKey)
        refreshSaveStreakReminderPreference()
    }

    func configureSaveStreakReminders(for userID: String) {
        saveStreakReminderUserID = userID
        refreshSaveStreakReminderPreference()
    }

    func setSaveStreakRemindersEnabled(_ enabled: Bool, for userID: String) {
        saveStreakReminderUserID = userID
        userDefaults.set(enabled, forKey: Self.saveStreakRemindersKeyPrefix + userID)
        refreshSaveStreakReminderPreference()
    }

    func reconcileWannaGoReminders(
        _ items: [WannaGoReminderItem],
        now: Date = .now
    ) async {
        await refreshAuthorizationStatus()
        let center = UNUserNotificationCenter.current()
        let existingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(WannaGoReminderPlanner.notificationIdentifierPrefix) }

        guard wannaGoRemindersEnabled, canRegisterForRemoteNotifications else {
            if !existingIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)
            }
            return
        }

        let plans = WannaGoReminderPlanner.plans(for: items, now: now)
        if !existingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)
        }

        for plan in plans {
            do {
                try await center.add(WannaGoReminderPlanner.request(for: plan))
            } catch {
                lastErrorMessage = "Could not schedule a Wanna go reminder."
                #if DEBUG
                WanderDebugLog.remote.error("wanna reminder scheduling failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
                #endif
            }
        }
    }

    func cancelAllWannaGoReminders() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(WannaGoReminderPlanner.notificationIdentifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func reconcileSaveStreakReminder(
        _ summary: SaveStreakSummary,
        now: Date = .now
    ) async {
        await refreshAuthorizationStatus()
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SaveStreakReminderPlanner.notificationIdentifierPrefix) }

        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        guard saveStreakRemindersEnabled,
              canRegisterForRemoteNotifications,
              let plan = SaveStreakReminderPlanner.plan(for: summary, now: now)
        else {
            return
        }

        do {
            try await center.add(SaveStreakReminderPlanner.request(for: plan))
        } catch {
            lastErrorMessage = "Could not schedule a save streak reminder."
            #if DEBUG
            WanderDebugLog.remote.error("save streak reminder scheduling failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    func cancelAllSaveStreakReminders() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SaveStreakReminderPlanner.notificationIdentifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    #if DEBUG
    @discardableResult
    func scheduleDebugSaveStreakReminder(_ summary: SaveStreakSummary) async -> Bool {
        await refreshAuthorizationStatus()
        guard saveStreakRemindersEnabled, canRegisterForRemoteNotifications else {
            lastErrorMessage = "Turn on save streak reminders first."
            return false
        }

        do {
            try await UNUserNotificationCenter.current().add(
                SaveStreakReminderPlanner.debugRequest(for: summary)
            )
            return true
        } catch {
            lastErrorMessage = "Could not schedule the test reminder."
            return false
        }
    }
    #endif

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
        if let preferences = try? await backend.updateNotificationPreferences(.allDisabled) {
            applyNotificationPreferences(preferences)
        } else {
            applyNotificationPreferences(.allDisabled)
        }
        await cancelAllWannaGoReminders()
        await cancelAllSaveStreakReminders()
    }

    private func refreshSaveStreakReminderPreference() {
        guard let userID = saveStreakReminderUserID else {
            saveStreakRemindersEnabled = false
            return
        }

        let key = Self.saveStreakRemindersKeyPrefix + userID
        let isEnabledForAccount = userDefaults.object(forKey: key).map { _ in
            userDefaults.bool(forKey: key)
        } ?? true
        saveStreakRemindersEnabled = pushEnabled && isEnabledForAccount
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
