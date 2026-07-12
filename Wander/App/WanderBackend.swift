import Foundation

@MainActor
final class WanderBackend: ObservableObject {
    let configuration: WanderBackendConfiguration
    let profileRepository: (any ProfileRepository)?
    let profileAvatarRepository: (any ProfileAvatarRepository)?
    let followRepository: (any FollowRepository)?
    let blockRepository: (any BlockRepository)?
    let placeRepository: (any PlaceRepository)?
    let userPlaceRepository: (any UserPlaceRepository)?
    let socialPlaceSaveRepository: (any SocialPlaceSaveRepository)?
    let visitRepository: (any VisitRepository)?
    let extractionRepository: (any ExtractionRepository)?
    let placeListRepository: (any PlaceListRepository)?
    let listSuggestionRepository: (any ListSuggestionRepository)?
    let notificationRepository: (any NotificationRepository)?

    init(configuration: WanderBackendConfiguration, authSession: any AuthSessionProviding) {
        self.configuration = configuration

        if configuration.isSupabaseConfigured {
            let client = WanderSupabaseClient(configuration: configuration, authSession: authSession)
            self.profileRepository = SupabaseProfileRepository(rpc: client)
            self.profileAvatarRepository = SupabaseProfileAvatarRepository(rpc: client, storage: client)
            self.followRepository = SupabaseFollowRepository(rpc: client)
            self.blockRepository = SupabaseBlockRepository(rpc: client)
            self.placeRepository = SupabasePlaceRepository(rpc: client)
            let userPlaceRepository = SupabaseUserPlaceRepository(rpc: client, userPlaceDeleter: client)
            self.userPlaceRepository = userPlaceRepository
            self.socialPlaceSaveRepository = userPlaceRepository
            self.visitRepository = SupabaseVisitRepository(table: client, storage: client)
            self.extractionRepository = SupabaseExtractionRepository(rpc: client, functions: client)
            self.placeListRepository = SupabasePlaceListRepository(rpc: client)
            self.listSuggestionRepository = SupabaseListSuggestionRepository(functions: client)
            self.notificationRepository = SupabaseNotificationRepository(rpc: client)
        } else {
            self.profileRepository = nil
            self.profileAvatarRepository = nil
            self.followRepository = nil
            self.blockRepository = nil
            self.placeRepository = nil
            self.userPlaceRepository = nil
            self.socialPlaceSaveRepository = nil
            self.visitRepository = nil
            self.extractionRepository = nil
            self.placeListRepository = nil
            self.listSuggestionRepository = nil
            self.notificationRepository = nil
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
        placeRepository: (any PlaceRepository)? = nil,
        userPlaceRepository: (any UserPlaceRepository)? = nil,
        socialPlaceSaveRepository: (any SocialPlaceSaveRepository)? = nil,
        visitRepository: (any VisitRepository)? = nil,
        extractionRepository: (any ExtractionRepository)? = nil,
        placeListRepository: (any PlaceListRepository)? = nil,
        listSuggestionRepository: (any ListSuggestionRepository)? = nil,
        notificationRepository: (any NotificationRepository)? = nil
    ) {
        self.configuration = configuration
        self.profileRepository = profileRepository
        self.profileAvatarRepository = profileAvatarRepository
        self.followRepository = followRepository
        self.blockRepository = blockRepository
        self.placeRepository = placeRepository
        self.userPlaceRepository = userPlaceRepository
        self.socialPlaceSaveRepository = socialPlaceSaveRepository
        self.visitRepository = visitRepository
        self.extractionRepository = extractionRepository
        self.placeListRepository = placeListRepository
        self.listSuggestionRepository = listSuggestionRepository
        self.notificationRepository = notificationRepository
    }

    var canUseRemoteData: Bool {
        profileRepository != nil
            || profileAvatarRepository != nil
            || followRepository != nil
            || blockRepository != nil
            || placeRepository != nil
            || userPlaceRepository != nil
            || socialPlaceSaveRepository != nil
            || visitRepository != nil
            || extractionRepository != nil
            || placeListRepository != nil
            || listSuggestionRepository != nil
            || notificationRepository != nil
    }

    var canSyncProfileAvatars: Bool {
        profileAvatarRepository != nil
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileRepository.searchProfiles(handleQuery: handleQuery)
    }

    func currentProfile() async throws -> LocalProfile? {
        guard let profileRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await profileRepository.currentProfile()
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
}
