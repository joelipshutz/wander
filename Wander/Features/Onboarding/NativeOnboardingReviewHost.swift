#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// This route uses the app's production views. Only repository data is local,
/// so recording a session cannot create an account, contact a member or upload.
enum NativeOnboardingReviewRoute: String {
    case welcome, signup, login, identity, location, contacts, friends, notifications, founders
    case friendsEmpty = "friends-empty"
    case friendsFailure = "friends-failure"

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let index = arguments.firstIndex(of: "-WanderNativeOnboardingReview"),
              arguments.indices.contains(index + 1) else {
            return ProcessInfo.processInfo.environment["WANDER_NATIVE_ONBOARDING_REVIEW"].flatMap(Self.init(rawValue:))
        }
        return Self(rawValue: arguments[index + 1])
    }

    var initialStep: OnboardingStep? {
        if self == .friendsEmpty || self == .friendsFailure { return .friends }
        return OnboardingStep(rawValue: rawValue)
    }
    var authMode: NativeAuthMode? {
        switch self {
        case .signup: .signUp
        case .login: .signIn
        default: nil
        }
    }
}

@MainActor
struct NativeOnboardingReviewHost: View {
    let route: NativeOnboardingReviewRoute
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var entryCoordinator: AppEntryCoordinator
    @StateObject private var pushNotifications = PushNotificationManager(analytics: NoopAnalyticsClient())
    @StateObject private var productUpsells = ProductUpsellCoordinator()
    @StateObject private var calendarReservations = CalendarReservationManager(analytics: NoopAnalyticsClient())
    @State private var startsOnboarding = false
    @State private var completed = false

    static let session = AuthSession(userID: "native-review-user", displayName: "", handle: "")

    init(route: NativeOnboardingReviewRoute) {
        self.route = route
        // A review launch always starts a fresh fictional journey; real users'
        // onboarding and playback progress are untouched.
        UserDefaults.standard.removeObject(forKey: "astir.founders-welcome.v1.\(Self.session.userID)")
        let repository = NativeOnboardingReviewRepository(route: route)
        let backend = WanderBackend(
            profileRepository: repository,
            profileAvatarRepository: repository,
            followRepository: repository,
            notificationRepository: SimulatorNotificationRepository()
        )
        let auth = AuthSessionStore(
            provider: PreviewAuthSessionProvider(
                state: route.initialStep == nil && route != .founders ? .signedOut : .signedIn(Self.session),
                canPresentNativeAuth: true,
                nativeAuthFailure: AuthSessionError.cancelled,
                emailVerificationSession: Self.session,
                passwordAuthSession: Self.session
            )
        )
        _backend = StateObject(wrappedValue: backend)
        _auth = StateObject(wrappedValue: auth)
        _entryCoordinator = StateObject(wrappedValue: AppEntryCoordinator(
            auth: auth, backend: backend, analytics: NoopAnalyticsClient(),
            usesLocalSimulatorTestSession: true,
            forcedLocalSimulatorOnboardingStep: .identity
        ))
    }

    var body: some View {
        Group {
            if route == .welcome {
                AppEntryView(
                    coordinator: entryCoordinator,
                    analytics: NoopAnalyticsClient(),
                    analyticsLifecycle: AppAnalyticsLifecycleTracker(analytics: NoopAnalyticsClient()),
                    parser: DeterministicFilterParser()
                )
            } else if route == .founders && !completed {
                FoundersWelcomeView(
                    initialPosition: Double(ProcessInfo.processInfo.environment["WANDER_FOUNDERS_REVIEW_POSITION"] ?? "0") ?? 0,
                    finish: { completed = true }
                )
            } else if completed {
                FoundersWelcomeGate(userID: Self.session.userID, isEligible: route != .founders) {
                    WanderRootView(
                        initialSession: auth.state.session,
                        isFirstVisitWalkthroughEligible: true,
                        analytics: NoopAnalyticsClient(),
                        parser: DeterministicFilterParser()
                    )
                    .environmentObject(WanderApp.makeMapCaptureBackend())
                }
            } else if let step = route.initialStep ?? (startsOnboarding ? .identity : nil) {
                OnboardingFlowView(
                    session: Self.session, initialStep: step,
                    analytics: NoopAnalyticsClient(), saveProgress: { _ in },
                    complete: { _ in completed = true }
                )
            } else {
                SignedOutOnboardingFlowView(
                    analytics: NoopAnalyticsClient()
                )
                .onAppear {
                    if let mode = route.authMode { auth.beginSignIn(mode: mode) }
                }
            }
        }
        .environmentObject(auth)
        .environmentObject(backend)
        .environmentObject(pushNotifications)
        .environmentObject(productUpsells)
        .environmentObject(calendarReservations)
        .modelContainer(WanderModelContainer.preview)
        .astirAdaptiveBrandMode()
        .overlay {
            if route != .welcome, let presentation = productUpsells.activePresentation {
                ProductUpsellScreen(presentation: presentation, analytics: NoopAnalyticsClient())
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .environmentObject(pushNotifications)
                    .environmentObject(productUpsells)
                    .astirAdaptiveBrandMode()
            }
        }
        .task { productUpsells.bind(to: Self.session.userID) }
        .onChange(of: auth.state) { _, state in
            if state.isSignedIn { startsOnboarding = true }
        }
    }
}

/// In-memory members support the same asynchronous APIs as the app. The
/// recording board identifies these names as sample data, not real contacts.
@MainActor
private final class NativeOnboardingReviewRepository: ProfileRepository, FollowRepository, ProfileAvatarRepository {
    private let route: NativeOnboardingReviewRoute
    private var profileValue = LocalProfile(localID: "native-review-user", handle: "", displayName: "")
    private var followed = Set<String>()
    private let people: [ProfileShell] = [
        ("mina", "Mina Park"), ("theo", "Theo Chen"), ("jules", "Jules Rivera"), ("sam", "Sam Lee")
    ].enumerated().map { index, person in
        ProfileShell(id: "native-review-\(person.0)", handle: person.0, displayName: person.1,
                     avatarURL: NativeOnboardingReviewRepository.portraitURL(index: index), bio: nil, relationship: .nonFollower)
    }

    /// Existing public-safe bundled portraits exercise the same image loader as
    /// real profile URLs. They are sample data, never claimed to be matched contacts.
    private static func portraitURL(index: Int) -> String? {
        guard let sheet = UIImage(named: "PlaceCarouselAvatars")?.cgImage else { return nil }
        let side = sheet.width / 2
        let rect = CGRect(x: (index % 2) * side, y: (index / 2) * side, width: side, height: side)
        guard let crop = sheet.cropping(to: rect), let data = UIImage(cgImage: crop).pngData() else { return nil }
        let url = URL.cachesDirectory.appending(path: "native-review-portrait-\(index).png")
        do { try data.write(to: url, options: .atomic); return url.absoluteString }
        catch { return nil }
    }

    init(route: NativeOnboardingReviewRoute) { self.route = route }

    func currentProfile() async throws -> LocalProfile? { profileValue }
    func isHandleAvailable(_ handle: String) async throws -> Bool {
        !handle.isEmpty && handle != "taken"
    }
    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile {
        if let value = update.displayName { profileValue.displayName = value }
        if let value = update.handle { profileValue.handle = value }
        if update.markOnboardingComplete { profileValue.onboardingCompletedAt = .now }
        return profileValue
    }
    func profile(id: String) async throws -> ProfileViewState {
        guard let person = people.first(where: { $0.id == id }) else { throw WanderRemoteError.notConfigured }
        return ProfileViewState(shell: person, visiblePlaces: [], canFollow: true, canBlock: true, isBlocked: false)
    }
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        let query = handleQuery.lowercased()
        return people.filter { $0.handle.hasPrefix(query) || $0.displayName.lowercased().hasPrefix(query) }
    }
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        if route == .friendsFailure { throw URLError(.notConnectedToInternet) }
        if route == .friendsEmpty { return [] }
        return people.prefix(limit).enumerated().map {
            DiscoverPeopleRecommendation(profile: $0.element, reason: .suggested, rank: $0.offset)
        }
    }
    func follow(userID: String) async throws { followed.insert(userID) }
    func unfollow(userID: String) async throws { followed.remove(userID) }
    func followers(userID: String) async throws -> [ProfileShell] { [] }
    func following(userID: String) async throws -> [ProfileShell] { people.filter { followed.contains($0.id) } }
    func relationship(to userID: String) async throws -> ViewerRelationship {
        followed.contains(userID) ? .follower : .nonFollower
    }
    func uploadAvatar(jpegData: Data, userID: String) async throws -> ProfileAvatarResult {
        let path = URL.documentsDirectory.appending(path: "native-review-avatar.jpg")
        try jpegData.write(to: path)
        profileValue.avatarURL = path.absoluteString
        return ProfileAvatarResult(avatarURL: path.absoluteString, storagePath: path.path)
    }
    func deleteAvatar(userID: String) async throws { profileValue.avatarURL = nil }
}
#endif
