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
        let retainedUserInfo = pendingResponses.compactMap { response in
            response.expectedUserID == expectedUserID ? response.userInfo : nil
        }
        state = .unknown
        authenticatedUserID = nil
        self.expectedUserID = expectedUserID
        validationGeneration &+= 1
        pendingResponses = expectedUserID.map { retainedUserID in
            retainedUserInfo.map {
                PendingResponse(
                    userInfo: $0,
                    expectedUserID: retainedUserID,
                    validationGeneration: validationGeneration
                )
            }
        } ?? []
    }

    @discardableResult
    func authenticate(userID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        state = .authenticated
        authenticatedUserID = userID
        expectedUserID = userID
        pendingResponses.removeAll {
            $0.expectedUserID != userID || $0.validationGeneration != validationGeneration
        }
        return !pendingResponses.isEmpty
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
            guard let authenticatedUserID else { return nil }
            pendingResponses.append(
                PendingResponse(
                    userInfo: userInfo,
                    expectedUserID: authenticatedUserID,
                    validationGeneration: validationGeneration
                )
            )
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
        let hasPendingResponse = authenticatedNotificationGate.authenticate(userID: userID)
        UserDefaults.standard.set(userID, forKey: lastValidatedUserIDKey)
        guard hasPendingResponse else { return }

        Task { @MainActor in
            #if DEBUG
            WanderDebugLog.remote.debug("notification response release signaled after auth validation")
            #endif
            NotificationCenter.default.post(
                name: Self.didReceiveNotificationResponse,
                object: nil
            )
        }
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
        #if DEBUG
        WanderDebugLog.remote.debug("notification response received action=\(response.actionIdentifier, privacy: .public)")
        #endif
        if let receivingUserID = Self.receiveAuthenticatedNotificationUserInfo(boxedUserInfo.value) {
            Task { @MainActor in
                guard Self.shouldAcceptAuthenticatedNotification(for: receivingUserID) else {
                    #if DEBUG
                    WanderDebugLog.remote.debug("notification response dropped after auth gate")
                    #endif
                    return
                }
                #if DEBUG
                WanderDebugLog.remote.debug("notification response posting to app")
                #endif
                NotificationCenter.default.post(
                    name: Self.didReceiveNotificationResponse,
                    object: nil,
                    userInfo: [Self.userInfoKey: boxedUserInfo.value]
                )
            }
        } else {
            #if DEBUG
            WanderDebugLog.remote.debug("notification response buffered or dropped by auth gate")
            #endif
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
    case profile(id: String)
    case people(NotificationPeopleMode)
    case list(id: String)
    case listInvite(token: String)
    case place(id: String)
    case activityComments(id: String)
    case sharedVisit(participantID: String, generation: Int)
    case calendarReservation(id: String)
    case drafts(extractionJobID: String?)
    case importReview(batchIDs: [String])
    case discover
}

struct NotificationNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let destination: NotificationDestination
}

@MainActor
final class PushNotificationManager: ObservableObject {
    private struct InFlightEnrollment {
        let id: UUID
        let userID: String
        let task: Task<NotificationPreferences?, Never>
    }

    private struct InFlightTokenRegistration {
        let id: UUID
        let userID: String
        let task: Task<Bool, Never>
    }

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var isRegisteringToken = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var navigationRequest: NotificationNavigationRequest?
    @Published private(set) var wannaGoRemindersEnabled: Bool
    @Published private(set) var saveStreakRemindersEnabled = false
    @Published private(set) var pushEnabled = false
    @Published private(set) var hasLoadedNotificationPreferences = false
    @Published private(set) var notificationPreferencesUserID: String?

    private let userDefaults: UserDefaults
    private let analytics: AnalyticsClient
    private let saveStreakReminderAnalytics: SaveStreakReminderAnalytics
    private let tokenKey = "wander.apnsDeviceToken"
    private static let wannaGoRemindersKey = "wander.wannaGoRemindersEnabled"
    private static let saveStreakRemindersKeyPrefix = "wander.saveStreakRemindersEnabled."
    private var saveStreakReminderUserID: String?
    private var handledEventIDs: [String] = []
    private var inFlightEnrollment: InFlightEnrollment?
    private var inFlightTokenRegistration: InFlightTokenRegistration?
    private var tokenRegistrationBlockedUserIDs: Set<String> = []
    private var tokenTeardownDepthByUserID: [String: Int] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.userDefaults = userDefaults
        self.analytics = analytics
        self.saveStreakReminderAnalytics = SaveStreakReminderAnalytics(
            analytics: analytics,
            userDefaults: userDefaults
        )
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

    var notificationsAreEnabled: Bool {
        Self.notificationsAreEnabled(
            pushEnabled: pushEnabled,
            authorizationStatus: authorizationStatus
        )
    }

    nonisolated static func notificationsAreEnabled(
        pushEnabled: Bool,
        authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        let authorizationAllowsNotifications: Bool
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationAllowsNotifications = true
        case .denied, .notDetermined:
            authorizationAllowsNotifications = false
        @unknown default:
            authorizationAllowsNotifications = false
        }
        return pushEnabled && authorizationAllowsNotifications
    }

    static func shouldRefreshRemoteRegistration(
        isSignedIn: Bool,
        backendCanRegister: Bool,
        pushEnabled: Bool,
        authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        let authorizationAllowsRegistration: Bool
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationAllowsRegistration = true
        case .denied, .notDetermined:
            authorizationAllowsRegistration = false
        @unknown default:
            authorizationAllowsRegistration = false
        }

        return isSignedIn
            && backendCanRegister
            && pushEnabled
            && authorizationAllowsRegistration
    }

    func refreshRemoteRegistrationIfNeeded(
        backend: WanderBackend,
        authSession: any AuthSessionProviding
    ) async {
        guard case .signedIn(let session) = authSession.state,
              isCurrentNotificationAccount(session.userID, authSession: authSession) else { return }
        await refreshAuthorizationStatus()
        guard isTokenRegistrationAllowed(session.userID, authSession: authSession) else { return }
        guard Self.shouldRefreshRemoteRegistration(
            isSignedIn: authSession.state.isSignedIn,
            backendCanRegister: backend.canRegisterPushNotifications,
            pushEnabled: pushEnabled,
            authorizationStatus: authorizationStatus
        ) else { return }

        guard isTokenRegistrationAllowed(session.userID, authSession: authSession) else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await registerStoredDeviceTokenIfPossible(backend: backend, authSession: authSession)
    }

    func refreshAuthorizationStatus() async {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-WanderNotificationAuthorizationNotDeterminedFixture") {
            authorizationStatus = .notDetermined
            return
        }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func clearAuthenticatedSessionState() {
        if let saveStreakReminderUserID {
            saveStreakReminderAnalytics.clearOpenAttribution(userID: saveStreakReminderUserID)
        }
        navigationRequest = nil
        handledEventIDs.removeAll()
        bindNotificationPreferences(to: nil)
        saveStreakReminderUserID = nil
        saveStreakRemindersEnabled = false
        WanderAppDelegate.setAuthenticatedSessionSignedOut()
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func bindNotificationPreferences(to userID: String?) {
        guard notificationPreferencesUserID != userID else { return }
        let previousUserID = notificationPreferencesUserID
        inFlightEnrollment?.task.cancel()
        inFlightTokenRegistration?.task.cancel()
        notificationPreferencesUserID = userID
        if let previousUserID {
            tokenRegistrationBlockedUserIDs.remove(previousUserID)
            tokenTeardownDepthByUserID.removeValue(forKey: previousUserID)
        }
        pushEnabled = false
        hasLoadedNotificationPreferences = false
        wannaGoRemindersEnabled = false
        saveStreakReminderUserID = nil
        saveStreakRemindersEnabled = false
    }

    @discardableResult
    func requestAuthorizationAndRegister(
        userID: String,
        authSession: any AuthSessionProviding
    ) async -> Bool {
        guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return false }
        isRequestingAuthorization = true
        lastErrorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return false }
            await refreshAuthorizationStatus()
            guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return false }
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
        expectedUserID: String,
        authSession: any AuthSessionProviding
    ) async -> NotificationPreferences? {
        guard tokenTeardownDepthByUserID[expectedUserID, default: 0] == 0 else {
            return nil
        }
        // Only an explicit enable action may reopen registration after a disable
        // teardown. Passive APNs callbacks remain blocked until then.
        tokenRegistrationBlockedUserIDs.remove(expectedUserID)
        if let inFlightEnrollment {
            if inFlightEnrollment.userID == expectedUserID {
                return await inFlightEnrollment.task.value
            }
            inFlightEnrollment.task.cancel()
            _ = await inFlightEnrollment.task.value
            if self.inFlightEnrollment?.id == inFlightEnrollment.id {
                self.inFlightEnrollment = nil
            }
        }

        let enrollmentID = UUID()
        let enrollmentTask = Task<NotificationPreferences?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performNotificationEnrollment(
                backend: backend,
                expectedUserID: expectedUserID,
                authSession: authSession
            )
        }
        inFlightEnrollment = InFlightEnrollment(
            id: enrollmentID,
            userID: expectedUserID,
            task: enrollmentTask
        )
        let result = await enrollmentTask.value
        if inFlightEnrollment?.id == enrollmentID {
            inFlightEnrollment = nil
        }
        return result
    }

    private func performNotificationEnrollment(
        backend: WanderBackend,
        expectedUserID: String,
        authSession: any AuthSessionProviding
    ) async -> NotificationPreferences? {
        guard case .signedIn(let session) = authSession.state,
              session.userID == expectedUserID,
              backend.canRegisterPushNotifications else {
            lastErrorMessage = "Sign in to turn on notifications."
            return nil
        }
        let userID = expectedUserID
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }

        lastErrorMessage = nil
        await refreshAuthorizationStatus()
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
        if authorizationStatus == .denied {
            lastErrorMessage = "Enable alerts in iOS Settings, then try again."
            return nil
        }

        if authorizationStatus == .notDetermined {
            guard await requestAuthorizationAndRegister(
                userID: userID,
                authSession: authSession
            ) else { return nil }
        } else {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            UIApplication.shared.registerForRemoteNotifications()
        }

        guard let token = await storedDeviceTokenWaitingForRegistration(
            userID: userID,
            authSession: authSession
        ) else {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            lastErrorMessage = "This device did not finish registering with Apple. Try again."
            await disablePreferencesAfterFailedEnrollment(
                backend: backend,
                userID: userID,
                authSession: authSession
            )
            return nil
        }

        isRegisteringToken = true
        defer { isRegisteringToken = false }

        guard await registerPushTokenSerialized(
            token,
            backend: backend,
            userID: userID,
            authSession: authSession
        ) else {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            await disablePreferencesAfterFailedEnrollment(
                backend: backend,
                userID: userID,
                authSession: authSession
            )
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            lastErrorMessage = "rec.me could not finish notification setup. Try again."
            return nil
        }

        do {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            let preferences = try await backend.updateNotificationPreferences(.allEnabled)
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            guard applyNotificationPreferences(preferences, for: userID) else {
                return nil
            }
            return preferences
        } catch {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            try? await backend.unregisterPushToken(token, environment: Self.environment)
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            await disablePreferencesAfterFailedEnrollment(
                backend: backend,
                userID: userID,
                authSession: authSession
            )
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            lastErrorMessage = "rec.me could not finish notification setup. Try again."
            #if DEBUG
            WanderDebugLog.remote.error("transactional push enrollment failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            return nil
        }
    }

    func disableNotifications(
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding
    ) async -> NotificationPreferences? {
        beginTokenTeardown(for: userID)
        defer { endTokenTeardown(for: userID) }
        await cancelAndAwaitRegistration(for: userID)
        guard backend.canRegisterPushNotifications,
              isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
        lastErrorMessage = nil

        do {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            let preferences = try await backend.updateNotificationPreferences(.allDisabled)
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            guard applyNotificationPreferences(preferences, for: userID) else { return nil }
            await cancelAllWannaGoReminders(userID: userID, authSession: authSession)
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            await cancelAllSaveStreakReminders(userID: userID, authSession: authSession)
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            _ = await unregisterStoredDeviceTokenIfPossible(
                backend: backend,
                userID: userID,
                authSession: authSession
            )
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return nil }
            return preferences
        } catch {
            lastErrorMessage = "Could not disable notifications. Try again."
            return nil
        }
    }

    func handleRegisteredDeviceToken(
        _ data: Data,
        backend: WanderBackend,
        authSession: any AuthSessionProviding
    ) async {
        let token = Self.hexString(from: data)
        userDefaults.set(token, forKey: tokenKey)
        await registerStoredDeviceTokenIfPossible(backend: backend, authSession: authSession)
    }

    func handleRegistrationFailure(_ error: Error) {
        lastErrorMessage = "Could not register this device for notifications."
        #if DEBUG
        WanderDebugLog.remote.error("push token registration failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
        #endif
    }

    @discardableResult
    func registerStoredDeviceTokenIfPossible(
        backend: WanderBackend,
        authSession: any AuthSessionProviding
    ) async -> Bool {
        guard case .signedIn(let session) = authSession.state,
              isTokenRegistrationAllowed(session.userID, authSession: authSession),
              backend.canRegisterPushNotifications,
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return false
        }

        isRegisteringToken = true
        lastErrorMessage = nil
        defer { isRegisteringToken = false }

        return await registerPushTokenSerialized(
            token,
            backend: backend,
            userID: session.userID,
            authSession: authSession
        )
    }

    @discardableResult
    func unregisterStoredDeviceTokenIfPossible(
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding
    ) async -> Bool {
        beginTokenTeardown(for: userID)
        defer { endTokenTeardown(for: userID) }
        await cancelAndAwaitRegistration(for: userID)
        guard backend.canRegisterPushNotifications,
              isCurrentNotificationAccount(userID, authSession: authSession),
              let token = userDefaults.string(forKey: tokenKey),
              !token.isEmpty
        else {
            return true
        }

        for attempt in 0..<2 {
            do {
                guard isCurrentNotificationAccount(userID, authSession: authSession) else { return false }
                try await backend.unregisterPushToken(token, environment: Self.environment)
                return isCurrentNotificationAccount(userID, authSession: authSession)
            } catch {
                guard attempt == 0,
                      isCurrentNotificationAccount(userID, authSession: authSession) else {
                    lastErrorMessage = "Notifications are off, but this device could not be fully disconnected."
                    #if DEBUG
                    WanderDebugLog.remote.error("push token unregister failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
                    #endif
                    return false
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    func restoreRegistrationAfterFailedAccountTeardown(
        userID: String,
        backend: WanderBackend,
        authSession: any AuthSessionProviding
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        tokenRegistrationBlockedUserIDs.remove(userID)
        await refreshRemoteRegistrationIfNeeded(backend: backend, authSession: authSession)
    }

    private func registerPushTokenSerialized(
        _ token: String,
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding
    ) async -> Bool {
        guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return false }
        if let registration = inFlightTokenRegistration {
            if registration.userID == userID {
                return await registration.task.value
            }
            registration.task.cancel()
            _ = await registration.task.value
            if inFlightTokenRegistration?.id == registration.id {
                inFlightTokenRegistration = nil
            }
        }

        let registrationID = UUID()
        let registrationTask = Task { @MainActor [weak self] in
            guard let self,
                  self.isTokenRegistrationAllowed(userID, authSession: authSession) else {
                return false
            }
            do {
                _ = try await backend.registerPushToken(
                    token,
                    environment: Self.environment,
                    appBundleID: Bundle.main.bundleIdentifier ?? "com.grayline.wander"
                )
                return self.isTokenRegistrationAllowed(userID, authSession: authSession)
            } catch {
                if self.isTokenRegistrationAllowed(userID, authSession: authSession) {
                    self.lastErrorMessage = "Could not sync notification settings."
                }
                #if DEBUG
                WanderDebugLog.remote.error("push token sync failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
                #endif
                return false
            }
        }
        inFlightTokenRegistration = InFlightTokenRegistration(
            id: registrationID,
            userID: userID,
            task: registrationTask
        )
        let result = await registrationTask.value
        if inFlightTokenRegistration?.id == registrationID {
            inFlightTokenRegistration = nil
        }
        return result
    }

    private func cancelAndAwaitRegistration(for userID: String) async {
        let registration = inFlightTokenRegistration?.userID == userID
            ? inFlightTokenRegistration
            : nil
        let enrollment = inFlightEnrollment?.userID == userID
            ? inFlightEnrollment
            : nil
        registration?.task.cancel()
        enrollment?.task.cancel()
        if let registration {
            _ = await registration.task.value
            if inFlightTokenRegistration?.id == registration.id {
                inFlightTokenRegistration = nil
            }
        }
        if let enrollment {
            _ = await enrollment.task.value
            if inFlightEnrollment?.id == enrollment.id {
                inFlightEnrollment = nil
            }
        }
    }

    @discardableResult
    func handleNotificationResponse(
        userInfo: [AnyHashable: Any],
        userID: String? = nil
    ) -> Bool {
        let eventID = Self.eventID(from: userInfo)
        if let eventID, handledEventIDs.contains(eventID) {
            return false
        }
        guard let destination = Self.destination(from: userInfo) else {
            #if DEBUG
            WanderDebugLog.remote.debug("notification response has no routable destination")
            #endif
            return false
        }
        if let eventID {
            handledEventIDs.append(eventID)
            if handledEventIDs.count > 100 {
                handledEventIDs.removeFirst(handledEventIDs.count - 100)
            }
        }
        navigationRequest = NotificationNavigationRequest(destination: destination)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.notificationOpened,
                properties: [
                    "notification_type": Self.analyticsNotificationType(from: userInfo),
                    "delivery_channel": Self.deliveryChannel(eventID: eventID),
                    "route": Self.analyticsRoute(for: destination)
                ]
            )
        )
        if let userID = userID ?? saveStreakReminderUserID {
            saveStreakReminderAnalytics.recordOpened(
                userInfo: userInfo,
                userID: userID
            )
        }
        #if DEBUG
        WanderDebugLog.remote.debug("notification navigation request created destination=\(String(describing: destination), privacy: .public)")
        #endif
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
            return (data?["actor_user_id"] as? String).map { .profile(id: $0) }
                ?? .people(.followers)
        case "mutual_follow":
            return (data?["actor_user_id"] as? String).map { .profile(id: $0) }
                ?? .people(.friends)
        case "list_collaborator_added", "list_place_added":
            return (data?["list_id"] as? String).map { .list(id: $0) }
        case "place_saved_from_your_map", "followed_place_visit", WannaGoReminderPlanner.notificationType:
            return (data?["place_id"] as? String).map { .place(id: $0) }
        case "activity_liked", "activity_commented":
            return (data?["activity_id"] as? String).map { .activityComments(id: $0) }
        case "shared_visit":
            guard let participantID = data?["participant_id"] as? String,
                  let generation = integerValue(data?["invitation_generation"])
            else { return nil }
            return .sharedVisit(participantID: participantID, generation: generation)
        case "capture_ready":
            return .drafts(extractionJobID: data?["extraction_job_id"] as? String)
        case "import_finished":
            let batchIDs = data?["batch_ids"] as? [String] ?? []
            return batchIDs.isEmpty ? nil : .importReview(batchIDs: batchIDs)
        case "calendar_reservation_live", "calendar_reservation_follow_up":
            return (data?["reservation_id"] as? String).map { .calendarReservation(id: $0) }
        case "followed_activity_digest":
            return .discover
        default:
            return nil
        }
    }

    private static func eventID(from userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["recme"] as? [String: Any])?["event_id"] as? String
    }

    private static func analyticsNotificationType(
        from userInfo: [AnyHashable: Any]
    ) -> String {
        let value = (userInfo["recme"] as? [String: Any])?["notification_type"] as? String
        let allowedTypes: Set<String> = [
            "activity_commented",
            "activity_liked",
            "capture_ready",
            "calendar_reservation_follow_up",
            "calendar_reservation_live",
            "followed_activity_digest",
            "followed_place_visit",
            "followed_you",
            "import_finished",
            "list_collaborator_added",
            "list_place_added",
            "mutual_follow",
            "place_saved_from_your_map",
            "save_streak_reminder",
            "shared_visit",
            "wanna_go_reminder"
        ]
        return value.flatMap { allowedTypes.contains($0) ? $0 : nil } ?? "unknown"
    }

    private static func deliveryChannel(eventID: String?) -> String {
        guard let eventID else { return "unknown" }
        return UUID(uuidString: eventID) == nil ? "local" : "remote"
    }

    private static func analyticsRoute(for destination: NotificationDestination) -> String {
        switch destination {
        case .quickCapture:
            return "quick_capture"
        case .profile:
            return "profile"
        case .people:
            return "people"
        case .list:
            return "list"
        case .listInvite:
            return "list_invite"
        case .place:
            return "place"
        case .activityComments:
            return "activity_comments"
        case .sharedVisit:
            return "shared_visit"
        case .calendarReservation:
            return "calendar_reservation"
        case .drafts:
            return "drafts"
        case .importReview:
            return "import_review"
        case .discover:
            return "discover"
        }
    }

    static func destination(
        from url: URL,
        notificationType: String? = nil
    ) -> NotificationDestination? {
        if let route = WanderDeepLinkRoute.parse(url) {
            switch route {
            case .quickCapture:
                return .quickCapture
            case .sharedProfile(let profileID):
                return .profile(id: profileID)
            case .sharedPlace(let placeID):
                return .place(id: placeID)
            case .sharedActivity(let activityID):
                return .activityComments(id: activityID)
            case .sharedList(let listID):
                return .list(id: listID)
            case .listInvite(let token):
                return .listInvite(token: token)
            case .calendarReservation(let reservationID):
                return .calendarReservation(id: reservationID)
            default:
                break
            }
        }

        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard let root = components.first else { return nil }
        let identifier = components.dropFirst().first

        switch root {
        case "profiles", "profile":
            return identifier.map { .profile(id: $0) }
        case "lists":
            return identifier.map { .list(id: $0) }
        case "places":
            return identifier.map { .place(id: $0) }
        case "activities":
            return identifier.map { .activityComments(id: $0) }
        case "shared-visits":
            guard let identifier,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let generationString = components.queryItems?.first(where: { $0.name == "generation" })?.value,
                  let generation = Int(generationString)
            else { return nil }
            return .sharedVisit(participantID: identifier, generation: generation)
        case "reservations":
            return identifier.flatMap { reservationID in
                UUID(uuidString: reservationID).map { _ in
                    .calendarReservation(id: reservationID)
                }
            }
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

    @discardableResult
    func applyNotificationPreferences(
        _ preferences: NotificationPreferences,
        for userID: String
    ) -> Bool {
        guard notificationPreferencesUserID == userID else { return false }
        pushEnabled = preferences.pushEnabled
        hasLoadedNotificationPreferences = true
        wannaGoRemindersEnabled = preferences.pushEnabled && preferences.wannaGoRemindersEnabled
        userDefaults.set(wannaGoRemindersEnabled, forKey: Self.wannaGoRemindersKey)
        refreshSaveStreakReminderPreference()
        return true
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
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding,
        now: Date = .now
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        await refreshAuthorizationStatus()
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let center = UNUserNotificationCenter.current()
        let existingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(WannaGoReminderPlanner.notificationIdentifierPrefix) }
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }

        let plans = WannaGoReminderPlanner.plans(for: items, now: now)
        if !existingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)
        }
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }

        let intents: [ClientNotificationIntent] = if wannaGoRemindersEnabled,
                                                     canRegisterForRemoteNotifications {
            plans.map { plan in
                let plannedDate = WannaGoDate.storageString(from: plan.item.plannedDate)
                let displayDate = WannaGoDate.displayString(for: plan.item.plannedDate)
                let encodedPlaceID = plan.item.placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                    ?? plan.item.placeID
                return ClientNotificationIntent(
                    intentKey: "\(plan.item.userPlaceID):\(plannedDate)",
                    title: "Wanna go reminder",
                    body: "You wanted to try \(plan.item.placeName) on \(displayDate).",
                    deeplinkURL: "recme://places/\(encodedPlaceID)",
                    data: [
                        "place_id": .string(plan.item.placeID),
                        "user_place_id": .string(plan.item.userPlaceID),
                        "planned_date": .string(plannedDate)
                    ],
                    earliestAt: plan.fireDate,
                    latestAt: plan.fireDate.addingTimeInterval(24 * 60 * 60),
                    priority: 40,
                    conflictGroup: "wanna:\(plan.item.userPlaceID)",
                    recipientTimezone: TimeZone.autoupdatingCurrent.identifier
                )
            }
        } else {
            []
        }

        do {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
            _ = try await backend.reconcileClientNotificationIntents(
                source: WannaGoReminderPlanner.notificationType,
                intents: intents
            )
        } catch {
            if isCurrentNotificationAccount(userID, authSession: authSession) {
                lastErrorMessage = "Could not sync Wanna go reminders."
            }
            #if DEBUG
            WanderDebugLog.remote.error("wanna reminder reconciliation failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    func cancelAllWannaGoReminders(
        userID: String,
        authSession: any AuthSessionProviding
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(WannaGoReminderPlanner.notificationIdentifierPrefix) }
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func notifyImportMatchingFinished(
        batchIDs: [String],
        matchedCount: Int,
        needsReviewCount: Int,
        sourceRetryCount: Int
    ) async -> Bool {
        guard !batchIDs.isEmpty else { return false }
        await refreshAuthorizationStatus()
        guard canRegisterForRemoteNotifications else { return false }

        let content = UNMutableNotificationContent()
        if matchedCount == 0, needsReviewCount == 0, sourceRetryCount > 0 {
            content.title = sourceRetryCount == 1
                ? "Your source scan needs a retry"
                : "\(sourceRetryCount) source scans need a retry"
            content.body = "Open rec.me to retry the incomplete source scan."
        } else if sourceRetryCount > 0 {
            content.title = "Your import is ready"
            content.body = "\(matchedCount) matched. Open rec.me to review and retry the incomplete source scan."
        } else if needsReviewCount > 0 {
            content.title = "Your import is ready"
            content.body = "\(matchedCount) matched. \(needsReviewCount) need a quick look."
        } else {
            content.title = "Your import is ready"
            content.body = matchedCount == 1
                ? "1 place is ready to add to your map."
                : "\(matchedCount) places are ready to add to your map."
        }
        content.sound = .default
        let eventID = "local-import-\(UUID().uuidString.lowercased())"
        content.userInfo = [
            "recme": [
                "event_id": eventID,
                "notification_type": "import_finished",
                "data": ["batch_ids": batchIDs]
            ]
        ]
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: eventID,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                )
            )
            return true
        } catch {
            #if DEBUG
            WanderDebugLog.imports.error(
                "import matching notification failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            return false
        }
    }

    func notifyImportFinished(
        batchIDs: [String],
        savedCount: Int,
        needsReviewCount: Int,
        sourceRetryCount: Int = 0,
        backend: WanderBackend
    ) async {
        guard !batchIDs.isEmpty else { return }
        await refreshAuthorizationStatus()
        guard canRegisterForRemoteNotifications else { return }

        let copy = PlaceImportFinishedNotificationCopy.make(
            savedCount: savedCount,
            needsReviewCount: needsReviewCount,
            sourceRetryCount: sourceRetryCount
        )
        let requestedAt = Date.now
        do {
            _ = try await backend.reconcileClientNotificationIntents(
                source: "import_finished",
                intents: [
                    ClientNotificationIntent(
                        intentKey: UUID().uuidString.lowercased(),
                        title: copy.title,
                        body: copy.body,
                        deeplinkURL: nil,
                        data: ["batch_ids": .array(batchIDs.map(JSONValue.string))],
                        earliestAt: requestedAt,
                        latestAt: requestedAt.addingTimeInterval(24 * 60 * 60),
                        priority: 50,
                        conflictGroup: "import_finished",
                        recipientTimezone: TimeZone.autoupdatingCurrent.identifier
                    )
                ]
            )
        } catch {
            #if DEBUG
            WanderDebugLog.imports.error(
                "import completion notification failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
        }
    }

    func reconcileSaveStreakReminder(
        _ summary: SaveStreakSummary,
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding,
        now: Date = .now,
        cancelledBySaveStatus: PlaceStatus? = nil
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        await refreshAuthorizationStatus()
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let productionRequests = pendingRequests.filter {
            SaveStreakReminderPlanner.productionReminderIdentifiers(in: [$0.identifier]).isEmpty == false
        }
        let identifiers = productionRequests.map(\.identifier)

        let plans = SaveStreakReminderPlanner.plans(for: summary, now: now)

        guard saveStreakRemindersEnabled, canRegisterForRemoteNotifications, !plans.isEmpty else {
            if summary.isTodayCovered,
               let cancelledBySaveStatus {
                for request in productionRequests {
                    saveStreakReminderAnalytics.recordCancelledBySave(
                        request: request,
                        status: cancelledBySaveStatus,
                        streakCount: summary.currentCount
                    )
                }
            }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
            do {
                _ = try await backend.reconcileClientNotificationIntents(
                    source: SaveStreakReminderPlanner.notificationType,
                    intents: []
                )
            } catch {
                if isCurrentNotificationAccount(userID, authSession: authSession) {
                    lastErrorMessage = "Could not sync save streak reminders."
                }
            }
            return
        }

        let staleRequests = productionRequests
        if summary.isTodayCovered,
           let cancelledBySaveStatus {
            for request in staleRequests {
                saveStreakReminderAnalytics.recordCancelledBySave(
                    request: request,
                    status: cancelledBySaveStatus,
                    streakCount: summary.currentCount
                )
            }
        }
        if !staleRequests.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleRequests.map(\.identifier))
        }
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }

        let intents = plans.map { plan in
            let copy = plan.copyVariant.copy(streakCount: plan.streakCount)
            return ClientNotificationIntent(
                intentKey: "\(plan.kind.rawValue):\(Int(plan.fireDate.timeIntervalSince1970))",
                title: copy.title,
                body: copy.body,
                deeplinkURL: "recme://add/here-now",
                data: [
                    "streak_count": .string("\(plan.streakCount)"),
                    "copy_variant": .string(plan.copyVariant.rawValue),
                    "scheduled_weekday": .string(plan.scheduledWeekday),
                    "reminder_kind": .string(plan.kind.rawValue)
                ],
                earliestAt: plan.fireDate,
                latestAt: plan.fireDate.addingTimeInterval(4 * 60 * 60),
                priority: 30,
                conflictGroup: "save_streak",
                recipientTimezone: TimeZone.autoupdatingCurrent.identifier
            )
        }
        do {
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
            let result = try await backend.reconcileClientNotificationIntents(
                source: SaveStreakReminderPlanner.notificationType,
                intents: intents
            )
            guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
            for plan in plans.prefix(result.createdCount) {
                saveStreakReminderAnalytics.recordScheduled(plan)
            }
        } catch {
            if isCurrentNotificationAccount(userID, authSession: authSession) {
                lastErrorMessage = "Could not sync save streak reminders."
            }
            #if DEBUG
            WanderDebugLog.remote.error("save streak reminder reconciliation failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    @discardableResult
    func recordSaveCompletedAfterReminderOpen(
        userID: String,
        status: PlaceStatus,
        streakCount: Int,
        savedAt: Date
    ) -> Bool {
        saveStreakReminderAnalytics.recordSaveCompletedAfterOpen(
            userID: userID,
            status: status,
            streakCount: streakCount,
            now: savedAt
        )
    }

    func cancelAllSaveStreakReminders(
        userID: String,
        authSession: any AuthSessionProviding
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SaveStreakReminderPlanner.notificationIdentifierPrefix) }
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllRemindersAfterSignOut(authSession: any AuthSessionProviding) async {
        guard notificationPreferencesUserID == nil,
              authSession.state.session == nil else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter {
                $0.hasPrefix(WannaGoReminderPlanner.notificationIdentifierPrefix)
                    || $0.hasPrefix(SaveStreakReminderPlanner.notificationIdentifierPrefix)
            }
        guard notificationPreferencesUserID == nil,
              authSession.state.session == nil,
              !identifiers.isEmpty else { return }
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

    private func storedDeviceTokenWaitingForRegistration(
        userID: String,
        authSession: any AuthSessionProviding
    ) async -> String? {
        guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return nil }
        if let token = userDefaults.string(forKey: tokenKey), !token.isEmpty {
            return token
        }

        UIApplication.shared.registerForRemoteNotifications()
        for _ in 0..<80 {
            guard isTokenRegistrationAllowed(userID, authSession: authSession) else { return nil }
            if let token = userDefaults.string(forKey: tokenKey), !token.isEmpty {
                return token
            }
            try? await Task.sleep(for: .milliseconds(125))
        }
        return nil
    }

    private func disablePreferencesAfterFailedEnrollment(
        backend: WanderBackend,
        userID: String,
        authSession: any AuthSessionProviding
    ) async {
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        let didApplyPreferences: Bool
        if let preferences = try? await backend.updateNotificationPreferences(.allDisabled) {
            didApplyPreferences = applyNotificationPreferences(preferences, for: userID)
        } else {
            didApplyPreferences = applyNotificationPreferences(.allDisabled, for: userID)
        }
        guard didApplyPreferences,
              isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        await cancelAllWannaGoReminders(userID: userID, authSession: authSession)
        guard isCurrentNotificationAccount(userID, authSession: authSession) else { return }
        await cancelAllSaveStreakReminders(userID: userID, authSession: authSession)
    }

    private func isCurrentNotificationAccount(
        _ userID: String,
        authSession: any AuthSessionProviding
    ) -> Bool {
        !Task.isCancelled
            && notificationPreferencesUserID == userID
            && authSession.state.session?.userID == userID
    }

    private func isTokenRegistrationAllowed(
        _ userID: String,
        authSession: any AuthSessionProviding
    ) -> Bool {
        isCurrentNotificationAccount(userID, authSession: authSession)
            && !tokenRegistrationBlockedUserIDs.contains(userID)
            && tokenTeardownDepthByUserID[userID, default: 0] == 0
    }

    private func beginTokenTeardown(for userID: String) {
        tokenRegistrationBlockedUserIDs.insert(userID)
        tokenTeardownDepthByUserID[userID, default: 0] += 1
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    private func endTokenTeardown(for userID: String) {
        let remainingDepth = tokenTeardownDepthByUserID[userID, default: 0] - 1
        if remainingDepth > 0 {
            tokenTeardownDepthByUserID[userID] = remainingDepth
        } else {
            tokenTeardownDepthByUserID.removeValue(forKey: userID)
        }
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
