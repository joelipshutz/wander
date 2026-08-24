import Foundation

enum FeatureFlagResolution: Equatable {
    case unresolved
    case resolved(userID: String, values: [FeatureFlagKey: ResolvedFeatureFlagValue])
    case failed(userID: String)

    func isPending(for userID: String) -> Bool {
        switch self {
        case .unresolved:
            true
        case .resolved(let resolvedUserID, _), .failed(let resolvedUserID):
            resolvedUserID != userID
        }
    }
}

enum DebugSettingsAccessPolicy {
    static func isEntitled(serverFlag: Bool?) -> Bool {
        isEntitled(serverFlag: serverFlag, isSimulator: isSimulatorBuild)
    }

    static func isEntitled(serverFlag: Bool?, isSimulator: Bool) -> Bool {
        isSimulator || serverFlag == true
    }

    private static var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

enum SemanticPlaceSearchAccessPolicy {
    static func isEnabled(serverFlag: Bool?) -> Bool {
        isEnabled(serverFlag: serverFlag, isDebugBuild: isDebugBuild)
    }

    static func isEnabled(serverFlag: Bool?, isDebugBuild: Bool) -> Bool {
        // Debug builds use the same resolved flag as TestFlight so an explicit
        // Off override can actually disable the feature on a developer device.
        _ = isDebugBuild
        return serverFlag == true
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

@MainActor
protocol FeatureFlagRepository {
    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue]
}

@MainActor
final class WanderBackend: ObservableObject {
    private static let placePhotoMetadataCacheLimit = 256

    let configuration: WanderBackendConfiguration
    let photoCacheScopeID = UUID()
    let featureFlagRepository: (any FeatureFlagRepository)?
    let profileRepository: (any ProfileRepository)?
    let profileAvatarRepository: (any ProfileAvatarRepository)?
    let followRepository: (any FollowRepository)?
    let blockRepository: (any BlockRepository)?
    let muteRepository: (any MuteRepository)?
    let communityReportRepository: (any CommunityReportRepository)?
    let placeRepository: (any PlaceRepository)?
    let feedRepository: (any FeedRepository)?
    let activityEngagementRepository: (any ActivityEngagementRepository)?
    let userPlaceRepository: (any UserPlaceRepository)?
    let socialPlaceSaveRepository: (any SocialPlaceSaveRepository)?
    let visitRepository: (any VisitRepository)?
    let extractionRepository: (any ExtractionRepository)?
    let placeListRepository: (any PlaceListRepository)?
    let surfaceSnapshotRepository: (any SurfaceSnapshotRepository)?
    let listSuggestionRepository: (any ListSuggestionRepository)?
    let placePhotoRepository: (any PlacePhotoRepository)?
    let notificationRepository: (any NotificationRepository)?
    let sharedVisitRepository: (any SharedVisitRepository)?
    @Published private(set) var featureFlagResolution: FeatureFlagResolution = .unresolved
    private var featureFlagRefreshGeneration = 0
    private let featureFlagDeviceOverrides: FeatureFlagDeviceOverrideSnapshot
    private var placePhotoCache: [String: PlacePhoto] = [:]
    private var placePhotoCacheRecency: [String] = []
    private var placePhotoTasks: [String: Task<PlacePhoto, Error>] = [:]
    private let placePhotoImageCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private var placePhotoImageTasks: [String: Task<Data, Error>] = [:]

    init(configuration: WanderBackendConfiguration, authSession: any AuthSessionProviding) {
        self.configuration = configuration
        self.featureFlagDeviceOverrides = FeatureFlagOverrideStore().launchSnapshot()

        if configuration.isSupabaseConfigured {
            let client = WanderSupabaseClient(configuration: configuration, authSession: authSession)
            self.featureFlagRepository = SupabaseFeatureFlagRepository(table: client)
            self.profileRepository = SupabaseProfileRepository(rpc: client)
            self.profileAvatarRepository = SupabaseProfileAvatarRepository(rpc: client, storage: client)
            self.followRepository = SupabaseFollowRepository(rpc: client)
            self.blockRepository = SupabaseBlockRepository(rpc: client)
            self.muteRepository = SupabaseMuteRepository(rpc: client)
            self.communityReportRepository = SupabaseCommunityReportRepository(rpc: client)
            self.placeRepository = SupabasePlaceRepository(rpc: client, functions: client)
            self.feedRepository = SupabaseFeedRepository(rpc: client)
            self.activityEngagementRepository = SupabaseActivityEngagementRepository(rpc: client)
            let userPlaceRepository = SupabaseUserPlaceRepository(rpc: client)
            self.userPlaceRepository = userPlaceRepository
            self.socialPlaceSaveRepository = userPlaceRepository
            self.visitRepository = SupabaseVisitRepository(table: client, storage: client)
            self.extractionRepository = SupabaseExtractionRepository(rpc: client, functions: client)
            self.placeListRepository = SupabasePlaceListRepository(rpc: client)
            self.surfaceSnapshotRepository = SupabaseSurfaceSnapshotRepository(rpc: client)
            self.listSuggestionRepository = SupabaseListSuggestionRepository(functions: client)
            self.placePhotoRepository = SupabasePlacePhotoRepository(rpc: client, functions: client, storage: client)
            self.notificationRepository = SupabaseNotificationRepository(rpc: client)
            self.sharedVisitRepository = SupabaseSharedVisitRepository(rpc: client, table: client, storage: client)
        } else {
            self.featureFlagRepository = nil
            self.profileRepository = nil
            self.profileAvatarRepository = nil
            self.followRepository = nil
            self.blockRepository = nil
            self.muteRepository = nil
            self.communityReportRepository = nil
            self.placeRepository = nil
            self.feedRepository = nil
            self.activityEngagementRepository = nil
            self.userPlaceRepository = nil
            self.socialPlaceSaveRepository = nil
            self.visitRepository = nil
            self.extractionRepository = nil
            self.placeListRepository = nil
            self.surfaceSnapshotRepository = nil
            self.listSuggestionRepository = nil
            self.placePhotoRepository = nil
            self.notificationRepository = nil
            self.sharedVisitRepository = nil
        }
    }

    init(
        configuration: WanderBackendConfiguration = WanderBackendConfiguration(
            clerkPublishableKey: nil,
            clerkFrontendAPI: nil,
            supabaseURL: nil,
            supabasePublishableKey: nil
        ),
        profileRepository: (any ProfileRepository)? = nil,
        profileAvatarRepository: (any ProfileAvatarRepository)? = nil,
        followRepository: (any FollowRepository)? = nil,
        blockRepository: (any BlockRepository)? = nil,
        muteRepository: (any MuteRepository)? = nil,
        communityReportRepository: (any CommunityReportRepository)? = nil,
        placeRepository: (any PlaceRepository)? = nil,
        feedRepository: (any FeedRepository)? = nil,
        activityEngagementRepository: (any ActivityEngagementRepository)? = nil,
        userPlaceRepository: (any UserPlaceRepository)? = nil,
        socialPlaceSaveRepository: (any SocialPlaceSaveRepository)? = nil,
        visitRepository: (any VisitRepository)? = nil,
        extractionRepository: (any ExtractionRepository)? = nil,
        placeListRepository: (any PlaceListRepository)? = nil,
        surfaceSnapshotRepository: (any SurfaceSnapshotRepository)? = nil,
        listSuggestionRepository: (any ListSuggestionRepository)? = nil,
        placePhotoRepository: (any PlacePhotoRepository)? = nil,
        notificationRepository: (any NotificationRepository)? = nil,
        sharedVisitRepository: (any SharedVisitRepository)? = nil,
        featureFlagRepository: (any FeatureFlagRepository)? = nil,
        featureFlagDeviceOverrides: FeatureFlagDeviceOverrideSnapshot = FeatureFlagOverrideStore().launchSnapshot()
    ) {
        self.configuration = configuration
        self.featureFlagDeviceOverrides = featureFlagDeviceOverrides
        self.featureFlagRepository = featureFlagRepository
        self.profileRepository = profileRepository
        self.profileAvatarRepository = profileAvatarRepository
        self.followRepository = followRepository
        self.blockRepository = blockRepository
        self.muteRepository = muteRepository
        self.communityReportRepository = communityReportRepository
        self.placeRepository = placeRepository
        self.feedRepository = feedRepository
        self.activityEngagementRepository = activityEngagementRepository
        self.userPlaceRepository = userPlaceRepository
        self.socialPlaceSaveRepository = socialPlaceSaveRepository
        self.visitRepository = visitRepository
        self.extractionRepository = extractionRepository
        self.placeListRepository = placeListRepository
        self.surfaceSnapshotRepository = surfaceSnapshotRepository
        self.listSuggestionRepository = listSuggestionRepository
        self.placePhotoRepository = placePhotoRepository
        self.notificationRepository = notificationRepository
        self.sharedVisitRepository = sharedVisitRepository
    }

    var canUseRemoteData: Bool {
        featureFlagRepository != nil
            || profileRepository != nil
            || profileAvatarRepository != nil
            || followRepository != nil
            || blockRepository != nil
            || muteRepository != nil
            || communityReportRepository != nil
            || placeRepository != nil
            || feedRepository != nil
            || activityEngagementRepository != nil
            || userPlaceRepository != nil
            || socialPlaceSaveRepository != nil
            || visitRepository != nil
            || extractionRepository != nil
            || placeListRepository != nil
            || surfaceSnapshotRepository != nil
            || listSuggestionRepository != nil
            || placePhotoRepository != nil
            || notificationRepository != nil
            || sharedVisitRepository != nil
    }

    func refreshFeatureFlags(for userID: String) async {
        featureFlagRefreshGeneration &+= 1
        let refreshGeneration = featureFlagRefreshGeneration

        guard let featureFlagRepository else {
            guard refreshGeneration == featureFlagRefreshGeneration else { return }
            featureFlagResolution = .failed(userID: userID)
            return
        }

        do {
            let values = try await featureFlagRepository.resolvedFlags(for: userID)
            try Task.checkCancellation()
            guard refreshGeneration == featureFlagRefreshGeneration else { return }
            featureFlagResolution = .resolved(userID: userID, values: values)
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == featureFlagRefreshGeneration else { return }
            featureFlagResolution = .failed(userID: userID)
        }
    }

    func clearFeatureFlags() {
        featureFlagRefreshGeneration &+= 1
        featureFlagResolution = .unresolved
    }

    func featureFlag(_ key: FeatureFlagKey, for userID: String) -> Bool? {
        guard key.definition.valueKind == .boolean else { return nil }
        return resolvedFeatureFlag(key, for: userID)?.isEnabled
    }

    func integerFeatureFlag(_ key: FeatureFlagKey, for userID: String) -> Int? {
        resolvedFeatureFlag(key, for: userID)?.integerValue
    }

    func deviceFeatureFlagOverride(
        _ key: FeatureFlagKey,
        for userID: String
    ) -> FeatureFlagValue? {
        featureFlagDeviceOverrides.override(for: key, userID: userID)
    }

    func remoteFeatureFlag(
        _ key: FeatureFlagKey,
        for userID: String
    ) -> ResolvedFeatureFlagValue? {
        guard case .resolved(let resolvedUserID, let values) = featureFlagResolution,
              resolvedUserID == userID
        else { return nil }
        return values[key]
    }

    func resolvedFeatureFlag(
        _ key: FeatureFlagKey,
        for userID: String
    ) -> ResolvedFeatureFlagValue? {
        if let override = featureFlagDeviceOverrides.override(for: key, userID: userID) {
            return ResolvedFeatureFlagValue(value: override, source: .deviceOverride)
        }
        if let remote = remoteFeatureFlag(key, for: userID) {
            return remote
        }
        guard !featureFlagResolution.isPending(for: userID) else { return nil }
        return ResolvedFeatureFlagValue(
            value: key.definition.bundledDefault,
            source: .bundledDefault
        )
    }

    var canSyncProfileAvatars: Bool {
        profileAvatarRepository != nil
    }

    func placePhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        guard let placePhotoRepository else {
            throw WanderRemoteError.notConfigured
        }
        let key = request.lookupKey
        if let cached = placePhotoCache[key] {
            markPlacePhotoRecentlyUsed(key)
            return cached
        }
        if let existingTask = placePhotoTasks[key] {
            return try await existingTask.value
        }

        let task = Task { @MainActor in
            try await placePhotoRepository.photo(for: request)
        }
        placePhotoTasks[key] = task
        do {
            let photo = try await task.value
            placePhotoTasks[key] = nil
            cachePlacePhoto(photo, for: key)
            return photo
        } catch {
            placePhotoTasks[key] = nil
            throw error
        }
    }

    func cachedPlacePhoto(for request: PlacePhotoRequest) -> PlacePhoto? {
        let key = request.lookupKey
        guard let photo = placePhotoCache[key] else { return nil }
        markPlacePhotoRecentlyUsed(key)
        return photo
    }

    func visibleUserPlacePhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        guard let placePhotoRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await placePhotoRepository.visibleUserPhoto(for: request)
    }

    func visiblePlacePhotoGalleryPage(
        placeID: String,
        after cursor: PlacePhotoGalleryCursor?,
        limit: Int = 40
    ) async throws -> PlacePhotoGalleryPage {
        guard let placePhotoRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await placePhotoRepository.visiblePhotoGalleryPage(
            placeID: placeID,
            after: cursor,
            limit: limit
        )
    }

    func placePhotoImageData(
        for photo: PlacePhoto,
        canonicalPlaceKey: String
    ) async throws -> Data {
        guard let placePhotoRepository else {
            throw WanderRemoteError.notConfigured
        }
        let key = "\(canonicalPlaceKey.utf8.count):\(canonicalPlaceKey)\(photo.cacheKey)"
        if let cached = placePhotoImageCache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let existingTask = placePhotoImageTasks[key] {
            return try await existingTask.value
        }

        let task = Task { @MainActor in
            try await placePhotoRepository.imageData(for: photo)
        }
        placePhotoImageTasks[key] = task
        do {
            let data = try await task.value
            placePhotoImageTasks[key] = nil
            placePhotoImageCache.setObject(
                data as NSData,
                forKey: key as NSString,
                cost: data.count
            )
            return data
        } catch {
            placePhotoImageTasks[key] = nil
            throw error
        }
    }

    private func cachePlacePhoto(_ photo: PlacePhoto, for key: String) {
        placePhotoCache[key] = photo
        markPlacePhotoRecentlyUsed(key)

        while placePhotoCache.count > Self.placePhotoMetadataCacheLimit,
              let oldestKey = placePhotoCacheRecency.first {
            placePhotoCacheRecency.removeFirst()
            placePhotoCache.removeValue(forKey: oldestKey)
        }
    }

    private func markPlacePhotoRecentlyUsed(_ key: String) {
        placePhotoCacheRecency.removeAll { $0 == key }
        placePhotoCacheRecency.append(key)
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileRepository.searchProfiles(handleQuery: handleQuery)
    }

    func discoverProfileRecommendations(limit: Int = 20) async throws -> [DiscoverPeopleRecommendation] {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileRepository.discoverProfileRecommendations(limit: limit)
    }

    func currentProfile() async throws -> LocalProfile? {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileRepository.currentProfile()
    }

    func isProfileHandleAvailable(_ handle: String) async throws -> Bool {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await profileRepository.isHandleAvailable(handle)
    }

    func profile(id: String) async throws -> ProfileViewState {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await profileRepository.profile(id: id)
    }

    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await profileRepository.updateCurrentProfile(update)
    }

    func updateProfilePrivacy(isPrivateProfile: Bool, defaultVisibility: PlaceVisibility) async throws -> LocalProfile {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await profileRepository.updatePrivacy(
            isPrivateProfile: isPrivateProfile,
            defaultVisibility: defaultVisibility
        )
    }

    func uploadProfileAvatar(jpegData: Data, userID: String) async throws -> ProfileAvatarResult {
        guard let profileAvatarRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileAvatarRepository.uploadAvatar(jpegData: jpegData, userID: userID)
    }

    func deleteProfileAvatar(userID: String) async throws {
        guard let profileAvatarRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await profileAvatarRepository.deleteAvatar(userID: userID)
    }

    func visiblePlaces(in viewport: MapViewport) async throws -> [VisiblePlace] {
        guard let placeRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeRepository.places(in: viewport)
    }

    func searchRecmePlaces(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        guard let placeRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeRepository.searchRecmePlaces(request)
    }

    func searchRecmePlaces(
        _ request: RecmePlaceSearchRequest,
        includesSemanticProvider: Bool
    ) async throws -> RecmePlaceSearchOutcome {
        guard let placeRepository else {
            throw WanderRemoteError.notConfigured
        }

        guard includesSemanticProvider else {
            let lexical = try await placeRepository.searchRecmePlaces(request)
            return RecmePlaceSearchFusion.outcome(
                lexical: lexical,
                semantic: [],
                semanticStatus: .disabled,
                limit: request.limit
            )
        }

        let lexicalTask = Task { @MainActor in
            await placeSearchAttempt {
                try await placeRepository.searchRecmePlaces(request)
            }
        }
        let semanticTask = Task { @MainActor in
            await placeSearchAttempt {
                try await placeRepository.searchRecmePlacesSemantic(request)
            }
        }
        let (lexicalResult, semanticResult) = await withTaskCancellationHandler {
            await (lexicalTask.value, semanticTask.value)
        } onCancel: {
            lexicalTask.cancel()
            semanticTask.cancel()
        }

        switch (lexicalResult, semanticResult) {
        case (.success(let lexical), .success(let semantic)):
            return RecmePlaceSearchFusion.outcome(
                lexical: lexical,
                semantic: semantic,
                semanticStatus: .succeeded,
                limit: request.limit
            )
        case (.success(let lexical), .failure):
            return RecmePlaceSearchFusion.outcome(
                lexical: lexical,
                semantic: [],
                semanticStatus: .failed,
                limit: request.limit
            )
        case (.failure, .success(let semantic)):
            return RecmePlaceSearchFusion.outcome(
                lexical: [],
                semantic: semantic,
                semanticStatus: .succeeded,
                limit: request.limit
            )
        case (.failure(let lexicalError), .failure):
            throw lexicalError
        }
    }

    private func placeSearchAttempt(
        _ operation: @escaping @MainActor () async throws -> [PlaceCandidate]
    ) async -> Result<[PlaceCandidate], Error> {
        do {
            return .success(try await operation())
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            return .failure(error)
        }
    }

    func featuredPlaces(in viewport: MapViewport) async throws -> [VisiblePlace] {
        guard let placeRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeRepository.featuredPlaces(in: viewport)
    }

    func sharedPlace(id: String) async throws -> PlaceCandidate? {
        guard let placeRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeRepository.sharedPlace(id: id)
    }

    func userPlaces(for userID: String, filters: PlaceFilters = PlaceFilters()) async throws -> [VisiblePlace] {
        guard let userPlaceRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await userPlaceRepository.userPlaces(for: userID, filters: filters)
    }

    func follow(userID: String) async throws {
        guard let followRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await followRepository.follow(userID: userID)
    }

    func unfollow(userID: String) async throws {
        guard let followRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await followRepository.unfollow(userID: userID)
    }

    func followers(userID: String) async throws -> [ProfileShell] {
        guard let followRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await followRepository.followers(userID: userID)
    }

    func following(userID: String) async throws -> [ProfileShell] {
        guard let followRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await followRepository.following(userID: userID)
    }

    func relationship(to userID: String) async throws -> ViewerRelationship {
        guard let followRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await followRepository.relationship(to: userID)
    }

    func block(userID: String) async throws {
        guard let blockRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await blockRepository.block(userID: userID)
    }

    func unblock(userID: String) async throws {
        guard let blockRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await blockRepository.unblock(userID: userID)
    }

    func blockedProfiles() async throws -> [ProfileShell] {
        guard let blockRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await blockRepository.blockedProfiles()
    }

    func mute(userID: String) async throws {
        guard let muteRepository else { throw WanderRemoteError.notConfigured }
        try await muteRepository.mute(userID: userID)
    }

    func unmute(userID: String) async throws {
        guard let muteRepository else { throw WanderRemoteError.notConfigured }
        try await muteRepository.unmute(userID: userID)
    }

    func mutedProfiles() async throws -> [ProfileShell] {
        guard let muteRepository else { throw WanderRemoteError.notConfigured }
        return try await muteRepository.mutedProfiles()
    }

    func submitCommunityReport(_ submission: CommunityReportSubmission) async throws -> CommunityReportReceipt {
        guard let communityReportRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await communityReportRepository.submit(submission)
    }

    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String) async throws -> SaveResult {
        guard let socialPlaceSaveRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await socialPlaceSaveRepository.saveVisiblePlace(
            placeID: placeID,
            sourceUserPlaceID: sourceUserPlaceID
        )
    }

    func saveUserPlace(_ draft: UserPlaceDraft) async throws -> SaveResult {
        guard let userPlaceRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await userPlaceRepository.save(draft)
    }

    func saveCheckIn(_ draft: CheckInSaveDraft) async throws -> CheckInSaveResult {
        guard let userPlaceRepository else {
            throw WanderRemoteError.notConfigured
        }

        if let checkInRepository = userPlaceRepository as? any CheckInRepository {
            return try await checkInRepository.saveCheckIn(draft)
        }

        // Test and local repository fallback. Production Supabase repositories
        // implement CheckInRepository so the parent and visit write atomically.
        let saveResult = try await userPlaceRepository.save(draft.userPlace)
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }
        let visitDraft = PlaceVisitDraft(
            id: draft.visit.id,
            userPlaceID: saveResult.userPlaceID,
            visitedAt: draft.visit.visitedAt,
            note: draft.visit.note,
            ratingScore: draft.visit.ratingScore,
            attributeAnswersJSON: draft.visit.attributeAnswersJSON,
            backfilledFromUserPlace: false
        )
        let visitResult = try await visitRepository.upsertVisit(visitDraft)
        return CheckInSaveResult(saveResult: saveResult, visitResult: visitResult)
    }

    func ownWannaGoPlans() async throws -> [OwnWannaGoPlan] {
        guard let userPlaceRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await userPlaceRepository.ownWannaGoPlans()
    }

    func deleteUserPlace(userPlaceID: String) async throws {
        guard let userPlaceRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await userPlaceRepository.delete(userPlaceID: userPlaceID)
    }

    func visits(for userPlaceID: String) async throws -> [PlaceVisitResult] {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await visitRepository.visits(for: userPlaceID)
    }

    func upsertVisit(_ draft: PlaceVisitDraft) async throws -> PlaceVisitResult {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await visitRepository.upsertVisit(draft)
    }

    func deleteVisit(visitID: String) async throws {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await visitRepository.deleteVisit(visitID: visitID)
    }

    func deleteCheckIn(visitID: String) async throws -> CheckInDeleteResult {
        if let checkInRepository = userPlaceRepository as? any CheckInRepository {
            return try await checkInRepository.deleteCheckIn(visitID: visitID)
        }

        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }
        try await visitRepository.deleteVisit(visitID: visitID)
        return CheckInDeleteResult(
            visitID: visitID,
            userPlaceID: nil,
            transition: .checkedIn
        )
    }

    func photos(for visitID: String) async throws -> [VisitPhotoResult] {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await visitRepository.photos(for: visitID)
    }

    func upsertVisitPhotoMetadata(_ draft: VisitPhotoDraft) async throws -> VisitPhotoResult {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await visitRepository.upsertPhotoMetadata(draft)
    }

    func uploadVisitPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await visitRepository.uploadPhotoData(bucket: bucket, path: path, data: data, contentType: contentType)
    }

    func deleteVisitPhoto(photoID: String, bucket: String, path: String) async throws {
        guard let visitRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await visitRepository.deletePhoto(photoID: photoID, bucket: bucket, path: path)
    }

    func enqueueExtractionJob(_ draft: ExtractionJobDraft) async throws -> ExtractionJobEnqueueResult {
        guard let extractionRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await extractionRepository.enqueue(draft)
    }

    func processExtractionJob(jobID: String) async throws -> ExtractionJobResult {
        guard let extractionRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await extractionRepository.process(jobID: jobID)
    }

    func extractionJobResult(jobID: String) async throws -> ExtractionJobResult {
        guard let extractionRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await extractionRepository.result(jobID: jobID)
    }

    func visiblePlaceLists() async throws -> [RemotePlaceListSummary] {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.visibleLists()
    }

    func placeListDetail(listID: String) async throws -> RemotePlaceListDetail? {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.detail(listID: listID)
    }

    func currentUserCalendarSnapshot() async throws -> CurrentUserCalendarRemoteSnapshot {
        guard let surfaceSnapshotRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await surfaceSnapshotRepository.currentUserCalendarSnapshot()
    }

    func placeListsSnapshot() async throws -> PlaceListsRemoteSnapshot {
        guard let surfaceSnapshotRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await surfaceSnapshotRepository.placeListsSnapshot()
    }

    func socialSurfaceSnapshot(in viewport: MapViewport) async throws -> SocialSurfaceRemoteSnapshot {
        guard let surfaceSnapshotRepository else {
            throw WanderRemoteError.notConfigured
        }
        return try await surfaceSnapshotRepository.socialSurfaceSnapshot(in: viewport)
    }

    func upsertPlaceList(_ draft: PlaceListUpsertDraft) async throws -> String {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.upsert(draft)
    }

    func deletePlaceList(listID: String) async throws {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await placeListRepository.delete(listID: listID)
    }

    func leavePlaceList(listID: String) async throws {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await placeListRepository.leave(listID: listID)
    }

    func setPlaceListCollaborators(listID: String, userIDs: [String]) async throws {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await placeListRepository.setCollaborators(listID: listID, userIDs: userIDs)
    }

    func addPlaceListItem(_ draft: PlaceListItemDraft) async throws -> String {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.addItem(draft)
    }

    func removePlaceListItem(listID: String, itemID: String) async throws {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await placeListRepository.removeItem(listID: listID, itemID: itemID)
    }

    func createPlaceListInvite(listID: String) async throws -> PlaceListInviteCreation {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.createInvite(listID: listID)
    }

    func resolvePlaceListInvite(token: String) async throws -> PlaceListInviteResolution {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.resolveInvite(token: token)
    }

    func acceptPlaceListInvite(token: String) async throws -> String {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await placeListRepository.acceptInvite(token: token)
    }

    func revokePlaceListInvite(token: String) async throws {
        guard let placeListRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await placeListRepository.revokeInvite(token: token)
    }

    func listSuggestions(payload: ListSuggestionPayload) async throws -> ListSuggestionFunctionResponse {
        guard let listSuggestionRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await listSuggestionRepository.suggestions(payload: payload)
    }

    var canRegisterPushNotifications: Bool {
        notificationRepository != nil
    }

    func notificationPreferences() async throws -> NotificationPreferences {
        guard let notificationRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await notificationRepository.preferences()
    }

    func updateNotificationPreferences(_ update: NotificationPreferencesUpdate) async throws -> NotificationPreferences {
        guard let notificationRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await notificationRepository.updatePreferences(update)
    }

    func registerPushToken(_ token: String, environment: PushTokenEnvironment, appBundleID: String) async throws -> String {
        guard let notificationRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await notificationRepository.registerPushToken(token, environment: environment, appBundleID: appBundleID)
    }

    func unregisterPushToken(_ token: String, environment: PushTokenEnvironment?) async throws {
        guard let notificationRepository else {
            throw WanderRemoteError.notConfigured
        }

        try await notificationRepository.unregisterPushToken(token, environment: environment)
    }

    var canUseSharedVisits: Bool {
        sharedVisitRepository != nil
    }

    func createSharedVisitInvites(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.createInvites(
            sourceVisitID: sourceVisitID,
            inviteeUserIDs: inviteeUserIDs
        )
    }

    func sharedVisitInviteeUserIDs(sourceVisitID: String) async throws -> [String] {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.inviteeUserIDs(sourceVisitID: sourceVisitID)
    }

    func setSharedVisitInvitees(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.setInvitees(
            sourceVisitID: sourceVisitID,
            inviteeUserIDs: inviteeUserIDs
        )
    }

    func sharedVisitInbox(before: Date? = nil, limit: Int = 50) async throws -> [SharedVisitInvitation] {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.inbox(before: before, limit: limit)
    }

    func sharedVisitContext(participantID: String, generation: Int) async throws -> SharedVisitInvitation? {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.context(participantID: participantID, generation: generation)
    }

    func resolveSharedVisitDestination(participantID: String, generation: Int) async throws -> SharedVisitDestination? {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.resolveDestination(participantID: participantID, generation: generation)
    }

    func acceptSharedVisit(_ draft: SharedVisitAcceptanceDraft) async throws -> SharedVisitAcceptanceResult {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.accept(draft)
    }

    func declineSharedVisit(participantID: String, generation: Int) async throws {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        try await sharedVisitRepository.decline(participantID: participantID, generation: generation)
    }

    func sharedVisitCompanions(visitIDs: [String]) async throws -> [SharedVisitCompanion] {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.companionContext(visitIDs: visitIDs)
    }

    func downloadSharedVisitPhoto(bucket: String, path: String) async throws -> Data {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        return try await sharedVisitRepository.downloadPhotoData(bucket: bucket, path: path)
    }

    func uploadSharedVisitPhoto(bucket: String, path: String, data: Data, contentType: String) async throws {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        try await sharedVisitRepository.uploadPhotoData(
            bucket: bucket,
            path: path,
            data: data,
            contentType: contentType
        )
    }

    func markSharedVisitPhotoUploaded(photoID: String) async throws {
        guard let sharedVisitRepository else { throw WanderRemoteError.notConfigured }
        try await sharedVisitRepository.markPhotoUploaded(photoID: photoID)
    }
}
