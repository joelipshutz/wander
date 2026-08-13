import SwiftUI
import SwiftData
#if DEBUG
import UIKit
#endif

@main
struct WanderApp: App {
    @UIApplicationDelegateAdaptor(WanderAppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var entryCoordinator: AppEntryCoordinator
    @StateObject private var pushNotifications: PushNotificationManager
    #if DEBUG
    @StateObject private var mapCaptureBackend: WanderBackend
    #endif
    private let analytics: AnalyticsClient
    private let analyticsLifecycle: AppAnalyticsLifecycleTracker
    private let discoverParser: any LLMFilterParser

    init() {
        let configuration = WanderBackendConfiguration.current()
        let analyticsClient: AnalyticsClient
        if let postHog = PostHogAnalyticsClient(configuration: .current()) {
            analyticsClient = postHog
        } else {
            analyticsClient = NoopAnalyticsClient()
        }
        let contextualAnalytics = ContextualAnalyticsClient(client: analyticsClient)
        analytics = contextualAnalytics
        analyticsLifecycle = AppAnalyticsLifecycleTracker(analytics: contextualAnalytics)
        _pushNotifications = StateObject(
            wrappedValue: PushNotificationManager(analytics: contextualAnalytics)
        )
        let authStore: AuthSessionStore
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WanderAuthenticatedUITest") {
            authStore = AuthSessionStore(
                provider: PreviewAuthSessionProvider(
                    state: .signedIn(
                        AuthSession(
                            userID: "user_joe",
                            displayName: "Joe",
                            handle: "joe"
                        )
                    )
                )
            )
        } else {
            authStore = AuthSessionStore(provider: ClerkAuthService(configuration: configuration))
        }
        #else
        authStore = AuthSessionStore(provider: ClerkAuthService(configuration: configuration))
        #endif
        let backendStore = WanderBackend(configuration: configuration, authSession: authStore)
        discoverParser = Self.makeDiscoverParser(configuration: configuration, authStore: authStore)
        _auth = StateObject(wrappedValue: authStore)
        _backend = StateObject(wrappedValue: backendStore)
        _entryCoordinator = StateObject(
            wrappedValue: AppEntryCoordinator(
                auth: authStore,
                backend: backendStore,
                analytics: contextualAnalytics
            )
        )
        #if DEBUG
        _mapCaptureBackend = StateObject(wrappedValue: Self.makeMapCaptureBackend())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let streakMockupPage = SaveStreakMockupPage.resolved() {
                SaveStreakMockupRoot(page: streakMockupPage)
            } else if let futureDateMockupPage = FutureDateSaveMockupPage.resolved() {
                FutureDateSaveMockupRoot(page: futureDateMockupPage)
            } else if let inviteMockupPage = InviteMockupPage.resolved() {
                InviteMockupRoot(page: inviteMockupPage)
            } else if ProcessInfo.processInfo.arguments.contains("-WanderAuthUITest") {
                ClerkNativeAuthView(mode: .signIn)
                    .environmentObject(auth)
            } else if ProcessInfo.processInfo.arguments.contains("-WanderOnboardingUITestSignedOut") {
                LoggedOutCarouselView(analytics: NoopAnalyticsClient(), getStarted: {}, logIn: {})
            } else if ProcessInfo.processInfo.arguments.contains("-WanderMapCapture") {
                mapCaptureRoot
            } else if let profileMockupPage = ProfileRedesignMockupPage.resolved() {
                ProfileRedesignMockupRoot(page: profileMockupPage)
            } else if let carouselMockupPage = PlacePhotoCarouselMockupPage.resolved() {
                PlacePhotoCarouselMockupRoot(page: carouselMockupPage)
            } else if let activityMockupPage = PlaceActivityMockupPage.resolved() {
                PlaceActivityMockupRoot(page: activityMockupPage)
            } else if ProcessInfo.processInfo.arguments.contains("-WanderActivityShareMockup") {
                ActivitySharePreviewMockupRoot()
            } else if PlaceImportAdaptiveMockupPage.isPresented {
                PlaceImportAdaptiveMockupRoot()
                    .environmentObject(auth)
                    .environmentObject(backend)
            } else if PlaceImportCandidateMockupPage.isPresented {
                PlaceImportCandidateMockupRoot()
                    .environmentObject(auth)
                    .environmentObject(backend)
            } else if let mockupPage = CategoryTaxonomyMockupPage.resolved() {
                CategoryTaxonomyMockupRoot(page: mockupPage)
            } else {
                appRoot
            }
            #else
            appRoot
            #endif
        }
    }

    private var appRoot: some View {
        AppEntryView(
            coordinator: entryCoordinator,
            analytics: analytics,
            analyticsLifecycle: analyticsLifecycle,
            parser: discoverParser
        )
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(pushNotifications)
            .modelContainer(WanderModelContainer.preview)
    }

    #if DEBUG
    private var mapCaptureRoot: some View {
        WanderRootView(analytics: NoopAnalyticsClient(), parser: DeterministicFilterParser())
            .environmentObject(auth)
            .environmentObject(mapCaptureBackend)
            .environmentObject(pushNotifications)
            .modelContainer(WanderModelContainer.preview)
    }

    @MainActor
    static func makeMapCaptureBackend() -> WanderBackend {
        WanderBackend(placePhotoRepository: MapCapturePlacePhotoRepository())
    }
    #endif

    private static func makeDiscoverParser(
        configuration: WanderBackendConfiguration,
        authStore: AuthSessionStore
    ) -> any LLMFilterParser {
        guard configuration.isSupabaseConfigured else {
            return DeterministicFilterParser()
        }

        let client = WanderSupabaseClient(configuration: configuration, authSession: authStore)
        return RemoteDiscoverFilterParser(
            repository: SupabaseDiscoverFilterRepository(functions: client)
        )
    }
}

#if DEBUG
/// Keeps deterministic design and screenshot captures photo-first without
/// weakening the authenticated production `place-photo` boundary.
@MainActor
struct MapCapturePlacePhotoRepository: PlacePhotoRepository {
    private static let assetName = "PlaceCarouselPhotos"
    private static let tileCount = 4

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        if request.skipsGooglePlacesLookup {
            return try await visibleUserPhoto(for: request)
        }
        return photo(
            provider: "google_places",
            providerPlaceID: "capture-google-\(Self.tileIndex(for: request.lookupKey))",
            request: request
        )
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        photo(
            provider: "visit_photo",
            providerPlaceID: "capture-visit-\(Self.tileIndex(for: request.lookupKey))",
            request: request
        )
    }

    func visiblePhotoGalleryPage(
        placeID: String,
        after cursor: PlacePhotoGalleryCursor?,
        limit: Int
    ) async throws -> PlacePhotoGalleryPage {
        PlacePhotoGalleryPage(items: [], nextCursor: nil, hasMore: false)
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        let tileIndex = Self.tileIndex(from: photo.providerPlaceID)
        guard let image = Self.croppedAssetImage(tileIndex: tileIndex),
              let data = image.pngData()
        else {
            throw WanderRemoteError.invalidResponse("Map capture photo asset is unavailable")
        }
        return data
    }

    static func tileIndex(for key: String) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(tileCount))
    }

    private func photo(
        provider: String,
        providerPlaceID: String,
        request: PlacePhotoRequest
    ) -> PlacePhoto {
        let tileIndex = Self.tileIndex(from: providerPlaceID)
        let tileSize = Self.croppedAssetImage(tileIndex: tileIndex)?.size
        return PlacePhoto(
            provider: provider,
            providerPlaceID: providerPlaceID,
            providerPrimaryType: "restaurant",
            providerTypes: ["restaurant", "food", "point_of_interest"],
            photoURLString: "capture://place-carousel/\(tileIndex)",
            width: tileSize.map { Int($0.width) },
            height: tileSize.map { Int($0.height) },
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: provider == "google_places"
                ? Self.googleMapsSourceURLString(for: request.name)
                : nil,
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
    }

    private static func tileIndex(from providerPlaceID: String) -> Int {
        guard let suffix = providerPlaceID.split(separator: "-").last,
              let index = Int(suffix)
        else {
            return 0
        }
        return max(0, min(index, tileCount - 1))
    }

    private static func croppedAssetImage(tileIndex: Int) -> UIImage? {
        guard let sourceImage = UIImage(named: assetName),
              let sourceCGImage = sourceImage.cgImage
        else {
            return nil
        }

        let normalizedIndex = max(0, min(tileIndex, tileCount - 1))
        let tileWidth = sourceCGImage.width / 2
        let tileHeight = sourceCGImage.height / 2
        let cropRect = CGRect(
            x: (normalizedIndex % 2) * tileWidth,
            y: (normalizedIndex / 2) * tileHeight,
            width: tileWidth,
            height: tileHeight
        )
        guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(
            cgImage: croppedCGImage,
            scale: sourceImage.scale,
            orientation: sourceImage.imageOrientation
        )
    }

    private static func googleMapsSourceURLString(for placeName: String) -> String? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: placeName)
        ]
        return components?.url?.absoluteString
    }
}
#endif

enum WanderAppSessionDestination: Equatable {
    case loading
    case signIn
    case authenticated
    case unavailable(String)
}

@MainActor
struct WanderAppEntryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    private let analytics: AnalyticsClient
    private let parser: any LLMFilterParser
    @State private var hasResolvedSession = false
    @State private var sessionRefreshGeneration = 0
    @State private var authenticatedUserID: String?
    @State private var deepLinkInbox = WanderDeepLinkInbox()

    init(analytics: AnalyticsClient, parser: any LLMFilterParser) {
        self.analytics = analytics
        self.parser = parser
    }

    var body: some View {
        let destination = Self.destination(
            for: auth.state,
            hasResolvedSession: hasResolvedSession,
            isSessionValidated: auth.isSessionValidated
        )

        ZStack {
            if let session = auth.state.session {
                WanderRootView(
                    initialSession: session,
                    isSessionValidated: auth.isSessionValidated,
                    deepLinkLaunchRequest: deepLinkInbox.request(
                        ifSessionValidated: auth.isSessionValidated
                    ),
                    onDeepLinkLaunchRequestHandled: { requestID in
                        deepLinkInbox.consume(requestID)
                    },
                    analytics: analytics,
                    parser: parser
                )
                .id(session.userID)
                .allowsHitTesting(destination == .authenticated)
                .accessibilityHidden(destination != .authenticated)
            }

            sessionOverlay(for: destination)
        }
        .task(id: sessionRefreshGeneration) {
            await resolveSession()
        }
        .onOpenURL { url in
            deepLinkInbox.receive(url)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            auth.beginSessionValidation()
            hasResolvedSession = false
            sessionRefreshGeneration &+= 1
        }
        .onChange(of: auth.state, initial: true) { _, state in
            let newUserID: String?
            newUserID = state.session?.userID
            if authenticatedUserID != newUserID {
                if authenticatedUserID != nil {
                    WanderWidgetSnapshotPublisher.clear()
                    pushNotifications.clearAuthenticatedSessionState()
                }
                authenticatedUserID = newUserID
                if let newUserID, auth.isSessionValidated {
                    WanderAppDelegate.setAuthenticatedSessionActive(userID: newUserID)
                }
            }
            guard newUserID == nil else { return }
            analytics.resetIdentity()
            WanderWidgetSnapshotPublisher.clear()
        }
        .onChange(of: destination, initial: true) { _, destination in
            switch destination {
            case .authenticated:
                if auth.isSessionValidated, case .signedIn(let session) = auth.state {
                    WanderAppDelegate.setAuthenticatedSessionActive(userID: session.userID)
                }
            case .signIn, .unavailable:
                pushNotifications.clearAuthenticatedSessionState()
            case .loading:
                WanderAppDelegate.beginAuthenticatedSessionValidation()
            }
        }
    }

    @ViewBuilder
    private func sessionOverlay(for destination: WanderAppSessionDestination) -> some View {
        switch destination {
        case .loading:
            sessionLoadingView
        case .signIn:
            ClerkNativeAuthView(isDismissable: false)
        case .authenticated:
            EmptyView()
        case .unavailable(let message):
            authUnavailableView(message: message)
        }
    }

    private var sessionLoadingView: some View {
        VStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text("Checking your session…")
                .font(.body.weight(.semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private func authUnavailableView(message: String) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: WanderTheme.spacing4) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .accessibilityHidden(true)
                    VStack(spacing: WanderTheme.spacing2) {
                        Text("Sign in is unavailable")
                            .font(.title2.weight(.bold))
                        Text(message)
                            .font(.body)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .multilineTextAlignment(.center)
                    }
                    WanderPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                        auth.beginSessionValidation()
                        hasResolvedSession = false
                        sessionRefreshGeneration &+= 1
                    }
                }
                .padding(WanderTheme.spacing4)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    static func destination(
        for state: AuthState,
        hasResolvedSession: Bool,
        isSessionValidated: Bool = true
    ) -> WanderAppSessionDestination {
        guard hasResolvedSession else { return .loading }
        switch state {
        case .loading:
            return .loading
        case .signedOut:
            return .signIn
        case .signedIn:
            return isSessionValidated ? .authenticated : .loading
        case .offline:
            return .authenticated
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    private func resolveSession() async {
        await auth.refreshSession()
        guard !Task.isCancelled else { return }
        hasResolvedSession = true
    }
}
