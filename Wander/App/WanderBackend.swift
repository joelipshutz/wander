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
    let extractionRepository: (any ExtractionRepository)?
    let listSuggestionRepository: (any ListSuggestionRepository)?

    init(configuration: WanderBackendConfiguration, authSession: any AuthSessionProviding) {
        self.configuration = configuration

        if configuration.isSupabaseConfigured {
            let client = WanderSupabaseClient(configuration: configuration, authSession: authSession)
            self.profileRepository = SupabaseProfileRepository(rpc: client)
            self.profileAvatarRepository = SupabaseProfileAvatarRepository(rpc: client, storage: client)
            self.followRepository = SupabaseFollowRepository(rpc: client)
            self.blockRepository = SupabaseBlockRepository(rpc: client)
            self.placeRepository = SupabasePlaceRepository(rpc: client)
            let userPlaceRepository = SupabaseUserPlaceRepository(rpc: client)
            self.userPlaceRepository = userPlaceRepository
            self.socialPlaceSaveRepository = userPlaceRepository
            self.extractionRepository = SupabaseExtractionRepository(rpc: client, functions: client)
            self.listSuggestionRepository = SupabaseListSuggestionRepository(functions: client)
        } else {
            self.profileRepository = nil
            self.profileAvatarRepository = nil
            self.followRepository = nil
            self.blockRepository = nil
            self.placeRepository = nil
            self.userPlaceRepository = nil
            self.socialPlaceSaveRepository = nil
            self.extractionRepository = nil
            self.listSuggestionRepository = nil
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
        extractionRepository: (any ExtractionRepository)? = nil,
        listSuggestionRepository: (any ListSuggestionRepository)? = nil
    ) {
        self.configuration = configuration
        self.profileRepository = profileRepository
        self.profileAvatarRepository = profileAvatarRepository
        self.followRepository = followRepository
        self.blockRepository = blockRepository
        self.placeRepository = placeRepository
        self.userPlaceRepository = userPlaceRepository
        self.socialPlaceSaveRepository = socialPlaceSaveRepository
        self.extractionRepository = extractionRepository
        self.listSuggestionRepository = listSuggestionRepository
    }

    var canUseRemoteData: Bool {
        profileRepository != nil
            || profileAvatarRepository != nil
            || followRepository != nil
            || blockRepository != nil
            || placeRepository != nil
            || userPlaceRepository != nil
            || socialPlaceSaveRepository != nil
            || extractionRepository != nil
            || listSuggestionRepository != nil
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

    func listSuggestions(payload: ListSuggestionPayload) async throws -> ListSuggestionFunctionResponse {
        guard let listSuggestionRepository else {
            throw WanderRemoteError.notConfigured
        }

        return try await listSuggestionRepository.suggestions(payload: payload)
    }
}
