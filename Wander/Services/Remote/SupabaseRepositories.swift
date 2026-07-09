import Foundation

struct SupabaseProfileRepository: ProfileRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func currentProfile() async throws -> LocalProfile? {
        let rows: [RemoteCurrentProfileDTO] = try await rpc.call(
            "current_profile",
            params: EmptyParams()
        )
        return rows.first?.localProfile()
    }

    func profile(id: String) async throws -> ProfileViewState {
        throw WanderRemoteError.notImplemented("profile_visible_places profile shell")
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        let rows: [RemoteProfileShellDTO] = try await rpc.call(
            "search_profiles_by_handle",
            params: SearchProfilesParams(query: handleQuery)
        )
        return rows.map { $0.profileShell() }
    }
}

struct SupabaseProfileAvatarRepository: ProfileAvatarRepository {
    private static let bucket = "profile-avatars"
    private let rpc: RemoteProcedureCalling
    private let storage: RemoteStorageCalling
    private let versionProvider: () -> String

    init(
        rpc: RemoteProcedureCalling,
        storage: RemoteStorageCalling,
        versionProvider: @escaping () -> String = { UUID().uuidString }
    ) {
        self.rpc = rpc
        self.storage = storage
        self.versionProvider = versionProvider
    }

    func uploadAvatar(jpegData: Data, userID: String) async throws -> ProfileAvatarResult {
        let path = try avatarPath(userID: userID)
        try await storage.uploadObject(
            bucket: Self.bucket,
            path: path,
            data: jpegData,
            contentType: "image/jpeg",
            upsert: true
        )

        let avatarURL = try storage.publicObjectURL(
            bucket: Self.bucket,
            path: path,
            cacheBust: versionProvider()
        ).absoluteString
        let response: UpdateProfileAvatarResponse = try await rpc.call(
            "update_profile_avatar",
            params: UpdateProfileAvatarParams(avatarURL: avatarURL, storagePath: path)
        )

        guard let storedAvatarURL = response.avatarURL, !storedAvatarURL.isEmpty,
              let storedPath = response.avatarStoragePath, !storedPath.isEmpty
        else {
            throw WanderRemoteError.invalidResponse("Profile avatar update returned no avatar URL")
        }

        return ProfileAvatarResult(avatarURL: storedAvatarURL, storagePath: storedPath)
    }

    func deleteAvatar(userID: String) async throws {
        let path = try avatarPath(userID: userID)
        try await storage.deleteObject(bucket: Self.bucket, path: path)

        let _: UpdateProfileAvatarResponse = try await rpc.call(
            "update_profile_avatar",
            params: UpdateProfileAvatarParams(avatarURL: nil, storagePath: nil)
        )
    }

    private func avatarPath(userID: String) throws -> String {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty,
              !trimmedUserID.contains("/"),
              !trimmedUserID.contains("..")
        else {
            throw WanderRemoteError.invalidResponse("Invalid profile avatar owner id")
        }

        return "\(trimmedUserID)/avatar.jpg"
    }
}

struct SupabaseFollowRepository: FollowRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func follow(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "follow_user",
            params: FollowUserParams(profileID: userID, source: FollowSource.profile.rawValue)
        )
    }

    func unfollow(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call("unfollow_user", params: ProfileIDParams(profileID: userID))
    }

    func followers(userID: String) async throws -> [ProfileShell] {
        let rows: [RemoteProfileShellDTO] = try await rpc.call(
            "profile_followers",
            params: ProfileIDParams(profileID: userID)
        )
        return rows.map { $0.profileShell() }
    }

    func following(userID: String) async throws -> [ProfileShell] {
        let rows: [RemoteProfileShellDTO] = try await rpc.call(
            "profile_following",
            params: ProfileIDParams(profileID: userID)
        )
        return rows.map { $0.profileShell() }
    }

    func relationship(to userID: String) async throws -> ViewerRelationship {
        let response: ProfileRelationshipResponse = try await rpc.call(
            "profile_relationship",
            params: ProfileIDParams(profileID: userID)
        )
        guard let relationship = ViewerRelationship(rawValue: response.value) else {
            throw WanderRemoteError.invalidResponse("Unknown profile relationship: \(response.value)")
        }
        return relationship
    }
}

struct SupabaseBlockRepository: BlockRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func block(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call("block_user", params: ProfileIDParams(profileID: userID))
    }

    func unblock(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call("unblock_user", params: ProfileIDParams(profileID: userID))
    }

    func blockedProfiles() async throws -> [ProfileShell] {
        throw WanderRemoteError.notImplemented("blocked profiles RPC")
    }

    func isBlocked(userID: String) async throws -> Bool {
        throw WanderRemoteError.notImplemented("is blocked RPC")
    }
}

struct SupabasePlaceRepository: PlaceRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func places(in viewport: MapViewport) async throws -> [VisiblePlace] {
        let rows: [RemoteVisiblePlaceDTO] = try await rpc.call(
            "visible_places_in_view",
            params: VisiblePlacesParams(
                minLat: viewport.minLatitude,
                minLng: viewport.minLongitude,
                maxLat: viewport.maxLatitude,
                maxLng: viewport.maxLongitude,
                statusFilter: nil,
                categoryFilter: nil,
                ownerScope: nil
            )
        )
        return try rows.map { try $0.visiblePlace() }
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        throw WanderRemoteError.notImplemented("remote current location place resolution")
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        throw WanderRemoteError.notImplemented("remote manual place resolution")
    }
}

struct SupabaseUserPlaceRepository: UserPlaceRepository, SocialPlaceSaveRepository {
    private let rpc: RemoteProcedureCalling
    private let userPlaceDeleter: RemoteUserPlaceDeleting?

    init(rpc: RemoteProcedureCalling, userPlaceDeleter: RemoteUserPlaceDeleting? = nil) {
        self.rpc = rpc
        self.userPlaceDeleter = userPlaceDeleter
    }

    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] {
        let rows: [RemoteVisiblePlaceDTO] = try await rpc.call(
            "profile_visible_places",
            params: ProfileVisiblePlacesParams(
                profileID: userID,
                statusFilter: filters.statuses.isEmpty ? nil : filters.statuses.map(\.rawValue).sorted(),
                categoryFilter: filters.normalizedCategories.isEmpty ? nil : filters.normalizedCategories.sorted()
            )
        )
        return try rows.map { try $0.visiblePlace() }
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        let result: SaveOwnPlaceResponse = try await rpc.call(
            "save_own_place",
            params: SaveOwnPlaceParams(draft: draft)
        )
        return SaveResult(userPlaceID: result.userPlaceID, syncState: .synced, placeID: result.placeID)
    }

    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {
        throw WanderRemoteError.notImplemented("update visibility RPC")
    }

    func delete(userPlaceID: String) async throws {
        guard let userPlaceDeleter else {
            throw WanderRemoteError.notConfigured
        }

        try await userPlaceDeleter.deleteUserPlace(userPlaceID: userPlaceID)
    }

    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String) async throws -> SaveResult {
        let result: SaveVisiblePlaceResponse = try await rpc.call(
            "save_visible_place",
            params: SaveVisiblePlaceParams(inputPlaceID: placeID, inputSourceUserPlaceID: sourceUserPlaceID)
        )
        return SaveResult(userPlaceID: result.userPlaceID, syncState: .synced)
    }
}

struct SupabaseExtractionRepository: ExtractionRepository {
    private let rpc: RemoteProcedureCalling
    private let functions: RemoteFunctionCalling?

    init(rpc: RemoteProcedureCalling, functions: RemoteFunctionCalling? = nil) {
        self.rpc = rpc
        self.functions = functions
    }

    func enqueue(_ draft: ExtractionJobDraft) async throws -> ExtractionJobEnqueueResult {
        let response: EnqueueExtractionJobResponse = try await rpc.call(
            "enqueue_extraction_job",
            params: EnqueueExtractionJobParams(draft: draft)
        )
        return try response.result()
    }

    func process(jobID: String) async throws -> ExtractionJobResult {
        guard let functions else {
            throw WanderRemoteError.notConfigured
        }

        let response: ExtractionJobResultResponse = try await functions.invoke(
            "extraction-worker",
            body: ProcessExtractionJobParams(jobID: jobID)
        )
        return try response.result()
    }

    func result(jobID: String) async throws -> ExtractionJobResult {
        let response: ExtractionJobResultResponse = try await rpc.call(
            "get_extraction_job",
            params: ExtractionJobIDParams(inputJobID: jobID)
        )
        return try response.result()
    }
}

struct SupabasePlaceListRepository: PlaceListRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func visibleLists() async throws -> [RemotePlaceListSummary] {
        let rows: [RemotePlaceListSummaryDTO] = try await rpc.call(
            "visible_place_lists",
            params: EmptyParams()
        )
        return rows.map { $0.summary() }
    }

    func detail(listID: String) async throws -> RemotePlaceListDetail? {
        let detail: RemotePlaceListDetailDTO? = try await rpc.call(
            "place_list_detail",
            params: PlaceListIDParams(inputListID: listID)
        )
        return detail?.detail()
    }

    func upsert(_ draft: PlaceListUpsertDraft) async throws -> String {
        try await rpc.call(
            "upsert_place_list",
            params: UpsertPlaceListParams(draft: draft)
        )
    }

    func delete(listID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "delete_place_list",
            params: PlaceListIDParams(inputListID: listID)
        )
    }

    func setCollaborators(listID: String, userIDs: [String]) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "set_place_list_collaborators",
            params: SetPlaceListCollaboratorsParams(inputListID: listID, collaboratorUserIDs: userIDs)
        )
    }

    func addItem(_ draft: PlaceListItemDraft) async throws -> String {
        try await rpc.call(
            "add_place_list_item",
            params: AddPlaceListItemParams(draft: draft)
        )
    }

    func removeItem(listID: String, itemID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "remove_place_list_item",
            params: RemovePlaceListItemParams(inputListID: listID, inputItemID: itemID)
        )
    }
}

struct SupabaseDiscoverFilterRepository: DiscoverFilterParsingRepository {
    private let functions: RemoteFunctionCalling

    init(functions: RemoteFunctionCalling) {
        self.functions = functions
    }

    func parseFilters(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        var filters: DiscoverFilters = try await functions.invoke(
            "parse-discover-query",
            body: ParseDiscoverQueryParams(query: query, schema: schema)
        )
        filters.categories = Set(filters.categories.map(WanderPlaceCategory.normalizedPrimaryCategory))
        return filters
    }
}

struct RemoteDiscoverFilterParser: LLMFilterParser {
    private let repository: any DiscoverFilterParsingRepository
    private let fallback: any LLMFilterParser

    init(
        repository: any DiscoverFilterParsingRepository,
        fallback: any LLMFilterParser = DeterministicFilterParser()
    ) {
        self.repository = repository
        self.fallback = fallback
    }

    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        do {
            return try await repository.parseFilters(query: query, schema: schema)
        } catch {
            return try await fallback.parse(query: query, schema: schema)
        }
    }
}

struct SupabaseListSuggestionRepository: ListSuggestionRepository {
    private let functions: RemoteFunctionCalling

    init(functions: RemoteFunctionCalling) {
        self.functions = functions
    }

    func suggestions(payload: ListSuggestionPayload) async throws -> ListSuggestionFunctionResponse {
        try await functions.invoke(
            "suggest-list-places",
            body: payload
        )
    }
}

struct SupabaseNotificationRepository: NotificationRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func preferences() async throws -> NotificationPreferences {
        let response: NotificationPreferencesResponse = try await rpc.call(
            "get_notification_preferences",
            params: EmptyParams()
        )
        return response.preferences
    }

    func updatePreferences(_ update: NotificationPreferencesUpdate) async throws -> NotificationPreferences {
        let response: NotificationPreferencesResponse = try await rpc.call(
            "update_notification_preferences",
            params: UpdateNotificationPreferencesParams(update: update)
        )
        return response.preferences
    }

    func registerPushToken(_ token: String, environment: PushTokenEnvironment, appBundleID: String) async throws -> String {
        let response: RegisterPushTokenResponse = try await rpc.call(
            "register_push_token",
            params: RegisterPushTokenParams(
                inputDeviceToken: token,
                inputEnvironment: environment.rawValue,
                inputAppBundleID: appBundleID
            )
        )
        return response.value
    }

    func unregisterPushToken(_ token: String, environment: PushTokenEnvironment?) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "unregister_push_token",
            params: UnregisterPushTokenParams(
                inputDeviceToken: token,
                inputEnvironment: environment?.rawValue
            )
        )
    }
}

private struct SearchProfilesParams: Encodable {
    let query: String
}

private struct EmptyParams: Encodable {}

private struct NotificationPreferencesResponse: Decodable {
    let pushEnabled: Bool
    let socialGraphEnabled: Bool
    let sharedListsEnabled: Bool
    let recommendationsEnabled: Bool
    let captureEnabled: Bool
    let discoveryDigestEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case socialGraphEnabled = "social_graph_enabled"
        case sharedListsEnabled = "shared_lists_enabled"
        case recommendationsEnabled = "recommendations_enabled"
        case captureEnabled = "capture_enabled"
        case discoveryDigestEnabled = "discovery_digest_enabled"
    }

    var preferences: NotificationPreferences {
        NotificationPreferences(
            pushEnabled: pushEnabled,
            socialGraphEnabled: socialGraphEnabled,
            sharedListsEnabled: sharedListsEnabled,
            recommendationsEnabled: recommendationsEnabled,
            captureEnabled: captureEnabled,
            discoveryDigestEnabled: discoveryDigestEnabled
        )
    }
}

private struct UpdateNotificationPreferencesParams: Encodable {
    let inputPreferences: NotificationPreferencesPatch

    init(update: NotificationPreferencesUpdate) {
        self.inputPreferences = NotificationPreferencesPatch(update: update)
    }

    enum CodingKeys: String, CodingKey {
        case inputPreferences = "input_preferences"
    }
}

private struct NotificationPreferencesPatch: Encodable {
    let pushEnabled: Bool?
    let socialGraphEnabled: Bool?
    let sharedListsEnabled: Bool?
    let recommendationsEnabled: Bool?
    let captureEnabled: Bool?
    let discoveryDigestEnabled: Bool?

    init(update: NotificationPreferencesUpdate) {
        self.pushEnabled = update.pushEnabled
        self.socialGraphEnabled = update.socialGraphEnabled
        self.sharedListsEnabled = update.sharedListsEnabled
        self.recommendationsEnabled = update.recommendationsEnabled
        self.captureEnabled = update.captureEnabled
        self.discoveryDigestEnabled = update.discoveryDigestEnabled
    }

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case socialGraphEnabled = "social_graph_enabled"
        case sharedListsEnabled = "shared_lists_enabled"
        case recommendationsEnabled = "recommendations_enabled"
        case captureEnabled = "capture_enabled"
        case discoveryDigestEnabled = "discovery_digest_enabled"
    }
}

private struct RegisterPushTokenParams: Encodable {
    let inputDeviceToken: String
    let inputEnvironment: String
    let inputAppBundleID: String

    enum CodingKeys: String, CodingKey {
        case inputDeviceToken = "input_device_token"
        case inputEnvironment = "input_environment"
        case inputAppBundleID = "input_app_bundle_id"
    }
}

private struct RegisterPushTokenResponse: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }
}

private struct UnregisterPushTokenParams: Encodable {
    let inputDeviceToken: String
    let inputEnvironment: String?

    enum CodingKeys: String, CodingKey {
        case inputDeviceToken = "input_device_token"
        case inputEnvironment = "input_environment"
    }
}

private struct PlaceListIDParams: Encodable {
    let inputListID: String

    enum CodingKeys: String, CodingKey {
        case inputListID = "input_list_id"
    }
}

private struct UpsertPlaceListParams: Encodable {
    let inputList: UpsertPlaceListBody

    init(draft: PlaceListUpsertDraft) {
        self.inputList = UpsertPlaceListBody(draft: draft)
    }

    enum CodingKeys: String, CodingKey {
        case inputList = "input_list"
    }
}

private struct UpsertPlaceListBody: Encodable {
    let id: String?
    let name: String
    let description: String
    let visibility: String

    init(draft: PlaceListUpsertDraft) {
        self.id = draft.id
        self.name = draft.name
        self.description = draft.description
        self.visibility = draft.visibility.rawValue
    }
}

private struct SetPlaceListCollaboratorsParams: Encodable {
    let inputListID: String
    let collaboratorUserIDs: [String]

    enum CodingKeys: String, CodingKey {
        case inputListID = "input_list_id"
        case collaboratorUserIDs = "collaborator_user_ids"
    }
}

private struct AddPlaceListItemParams: Encodable {
    let inputListID: String
    let inputPlaceID: String
    let inputOwnerUserPlaceID: String?
    let inputSourceUserPlaceID: String?

    init(draft: PlaceListItemDraft) {
        self.inputListID = draft.listID
        self.inputPlaceID = draft.placeID
        self.inputOwnerUserPlaceID = draft.ownerUserPlaceID
        self.inputSourceUserPlaceID = draft.sourceUserPlaceID
    }

    enum CodingKeys: String, CodingKey {
        case inputListID = "input_list_id"
        case inputPlaceID = "input_place_id"
        case inputOwnerUserPlaceID = "input_owner_user_place_id"
        case inputSourceUserPlaceID = "input_source_user_place_id"
    }
}

private struct RemovePlaceListItemParams: Encodable {
    let inputListID: String
    let inputItemID: String

    enum CodingKeys: String, CodingKey {
        case inputListID = "input_list_id"
        case inputItemID = "input_item_id"
    }
}

private struct UpdateProfileAvatarParams: Encodable {
    let avatarURL: String?
    let storagePath: String?

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
        case storagePath = "storage_path"
    }
}

private struct UpdateProfileAvatarResponse: Decodable {
    let avatarURL: String?
    let avatarStoragePath: String?

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
        case avatarStoragePath = "avatar_storage_path"
    }
}

private struct ParseDiscoverQueryParams: Encodable {
    let query: String
    let schema: DiscoverFilterSchema
}

private struct ProfileIDParams: Encodable {
    let profileID: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
    }
}

private struct ProfileRelationshipResponse: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }
}

private struct FollowUserParams: Encodable {
    let profileID: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case source
    }
}

private struct VisiblePlacesParams: Encodable {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double
    let statusFilter: [String]?
    let categoryFilter: [String]?
    let ownerScope: [String]?

    enum CodingKeys: String, CodingKey {
        case minLat = "min_lat"
        case minLng = "min_lng"
        case maxLat = "max_lat"
        case maxLng = "max_lng"
        case statusFilter = "status_filter"
        case categoryFilter = "category_filter"
        case ownerScope = "owner_scope"
    }
}

private struct ProfileVisiblePlacesParams: Encodable {
    let profileID: String
    let statusFilter: [String]?
    let categoryFilter: [String]?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case statusFilter = "status_filter"
        case categoryFilter = "category_filter"
    }
}

private struct SaveVisiblePlaceParams: Encodable {
    let inputPlaceID: String
    let inputSourceUserPlaceID: String

    enum CodingKeys: String, CodingKey {
        case inputPlaceID = "input_place_id"
        case inputSourceUserPlaceID = "input_source_user_place_id"
    }
}

private struct SaveVisiblePlaceResponse: Decodable {
    let userPlaceID: String

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
    }
}

private struct EnqueueExtractionJobParams: Encodable {
    let inputSourceArtifact: EnqueueSourceArtifactParams
    let inputJob: EnqueueJobParams

    init(draft: ExtractionJobDraft) {
        self.inputSourceArtifact = EnqueueSourceArtifactParams(sourceArtifact: draft.sourceArtifact)
        self.inputJob = EnqueueJobParams(draft: draft)
    }

    enum CodingKeys: String, CodingKey {
        case inputSourceArtifact = "input_source_artifact"
        case inputJob = "input_job"
    }
}

private struct EnqueueSourceArtifactParams: Encodable {
    let type: String
    let originalInput: String
    let normalizedInput: String
    let normalizedSourceHash: String
    let localAssetRef: String?
    let remoteAssetRef: String?

    init(sourceArtifact: SourceArtifactDraft) {
        self.type = sourceArtifact.type
        self.originalInput = sourceArtifact.originalInput
        self.normalizedInput = sourceArtifact.normalizedInput
        self.normalizedSourceHash = sourceArtifact.normalizedSourceHash
        self.localAssetRef = sourceArtifact.localAssetRef
        self.remoteAssetRef = sourceArtifact.remoteAssetRef
    }

    enum CodingKeys: String, CodingKey {
        case type
        case originalInput = "original_input"
        case normalizedInput = "normalized_input"
        case normalizedSourceHash = "normalized_source_hash"
        case localAssetRef = "local_asset_ref"
        case remoteAssetRef = "remote_asset_ref"
    }
}

private struct EnqueueJobParams: Encodable {
    let sourceType: String
    let normalizedSourceHash: String
    let providerStepsJSON: [String]

    init(draft: ExtractionJobDraft) {
        self.sourceType = draft.sourceType
        self.normalizedSourceHash = draft.normalizedSourceHash
        self.providerStepsJSON = draft.providerSteps
    }

    enum CodingKeys: String, CodingKey {
        case sourceType = "source_type"
        case normalizedSourceHash = "normalized_source_hash"
        case providerStepsJSON = "provider_steps_json"
    }
}

private struct EnqueueExtractionJobResponse: Decodable {
    let sourceArtifactID: String
    let extractionJobID: String
    let status: String
    let attemptCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceArtifactID = "source_artifact_id"
        case extractionJobID = "extraction_job_id"
        case status
        case attemptCount = "attempt_count"
    }

    func result() throws -> ExtractionJobEnqueueResult {
        guard let extractionStatus = ExtractionStatus(rawValue: status) else {
            throw WanderRemoteError.invalidResponse("Unknown extraction status: \(status)")
        }

        return ExtractionJobEnqueueResult(
            sourceArtifactID: sourceArtifactID,
            extractionJobID: extractionJobID,
            status: extractionStatus,
            attemptCount: attemptCount
        )
    }
}

private struct ProcessExtractionJobParams: Encodable {
    let jobID: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}

private struct ExtractionJobIDParams: Encodable {
    let inputJobID: String

    enum CodingKeys: String, CodingKey {
        case inputJobID = "input_job_id"
    }
}

private struct ExtractionJobResultResponse: Decodable {
    let extractionJobID: String
    let status: String
    let attemptCount: Int
    let providerStepsJSON: [String]
    let extractedCandidatesJSON: [ExtractionCandidateResponse]
    let confidence: Double
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case extractionJobID = "extraction_job_id"
        case status
        case attemptCount = "attempt_count"
        case providerStepsJSON = "provider_steps_json"
        case extractedCandidatesJSON = "extracted_candidates_json"
        case confidence
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    func result() throws -> ExtractionJobResult {
        guard let extractionStatus = ExtractionStatus(rawValue: status) else {
            throw WanderRemoteError.invalidResponse("Unknown extraction status: \(status)")
        }

        return ExtractionJobResult(
            extractionJobID: extractionJobID,
            status: extractionStatus,
            attemptCount: attemptCount,
            providerSteps: providerStepsJSON,
            candidates: extractedCandidatesJSON.map(\.placeCandidate),
            confidence: confidence,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
    }
}

private struct ExtractionCandidateResponse: Decodable {
    let id: String
    let name: String
    let category: String
    let primaryCategory: String?
    let subcategory: String?
    let categorySource: String?
    let categoryConfidence: Double?
    let rawProviderType: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case primaryCategory = "primary_category"
        case subcategory
        case categorySource = "category_source"
        case categoryConfidence = "category_confidence"
        case rawProviderType = "raw_provider_type"
        case address
        case locality
        case region
        case country
        case latitude
        case longitude
        case sourceProvider = "source_provider"
        case sourceProviderPlaceID = "source_provider_place_id"
        case confidence
    }

    var placeCandidate: PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name,
            category: category,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: categorySource ?? PlaceCategorySource.provider.rawValue,
            categoryConfidence: categoryConfidence,
            rawProviderType: rawProviderType ?? category,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider ?? "extraction",
            sourceProviderPlaceID: sourceProviderPlaceID,
            confidence: confidence
        )
    }
}

private struct SaveOwnPlaceParams: Encodable {
    let inputPlace: SaveOwnPlacePlaceParams
    let inputUserPlace: SaveOwnPlaceUserPlaceParams
    let inputAttributes: [SaveOwnPlaceAttributeParams]

    init(draft: UserPlaceDraft) throws {
        self.inputPlace = SaveOwnPlacePlaceParams(place: draft.place)
        self.inputUserPlace = SaveOwnPlaceUserPlaceParams(draft: draft)
        self.inputAttributes = try draft.attributes.map(SaveOwnPlaceAttributeParams.init)
    }

    enum CodingKeys: String, CodingKey {
        case inputPlace = "input_place"
        case inputUserPlace = "input_user_place"
        case inputAttributes = "input_attributes"
    }
}

private struct SaveOwnPlacePlaceParams: Encodable {
    let canonicalName: String
    let category: String
    let primaryCategory: String
    let subcategory: String?
    let categorySource: String
    let categoryConfidence: Double?
    let rawProviderType: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String?
    let confidence: Double?

    init(place: PlaceDraft) {
        self.canonicalName = place.canonicalName
        self.category = place.category
        self.primaryCategory = place.primaryCategory
        self.subcategory = place.subcategory
        self.categorySource = place.categorySource
        self.categoryConfidence = place.categoryConfidence
        self.rawProviderType = place.rawProviderType
        self.address = place.address
        self.locality = place.locality
        self.region = place.region
        self.country = place.country
        self.latitude = place.latitude
        self.longitude = place.longitude
        self.sourceProvider = place.sourceProvider
        self.sourceProviderPlaceID = place.sourceProviderPlaceID ?? place.serverID ?? place.localID
        self.confidence = place.confidence
    }

    enum CodingKeys: String, CodingKey {
        case canonicalName = "canonical_name"
        case category
        case primaryCategory = "primary_category"
        case subcategory
        case categorySource = "category_source"
        case categoryConfidence = "category_confidence"
        case rawProviderType = "raw_provider_type"
        case address
        case locality
        case region
        case country
        case latitude
        case longitude
        case sourceProvider = "source_provider"
        case sourceProviderPlaceID = "source_provider_place_id"
        case confidence
    }
}

private struct SaveOwnPlaceUserPlaceParams: Encodable {
    let status: String
    let visibility: String
    let note: String?
    let ratingSignal: String?
    let ratingScore: Double?
    let categoryOverride: String?
    let subcategoryOverride: String?
    let categoryOverrideSource: String?
    let categoryOverrideConfidence: Double?
    let nearbyConfirmed: Bool
    let sourceType: String

    init(draft: UserPlaceDraft) {
        self.status = draft.status.rawValue
        self.visibility = draft.visibility.rawValue
        self.note = draft.note
        self.ratingSignal = nil
        self.ratingScore = draft.ratingScore
        self.categoryOverride = draft.categoryOverride
        self.subcategoryOverride = draft.subcategoryOverride
        self.categoryOverrideSource = draft.categoryOverrideSource
        self.categoryOverrideConfidence = draft.categoryOverrideConfidence
        self.nearbyConfirmed = draft.nearbyConfirmed
        self.sourceType = draft.sourceType
    }

    enum CodingKeys: String, CodingKey {
        case status
        case visibility
        case note
        case ratingSignal = "rating_signal"
        case ratingScore = "rating_score"
        case categoryOverride = "category_override"
        case subcategoryOverride = "subcategory_override"
        case categoryOverrideSource = "category_override_source"
        case categoryOverrideConfidence = "category_override_confidence"
        case nearbyConfirmed = "nearby_confirmed"
        case sourceType = "source_type"
    }
}

private struct SaveOwnPlaceAttributeParams: Encodable {
    let questionKey: String
    let valueType: String
    let value: JSONValue

    init(draft: PlaceAttributeDraft) throws {
        self.questionKey = draft.questionKey
        self.valueType = draft.valueType
        self.value = try Self.decodeValue(draft.valueJSON)
    }

    enum CodingKeys: String, CodingKey {
        case questionKey = "question_key"
        case valueType = "value_type"
        case value
    }

    private static func decodeValue(_ valueJSON: String) throws -> JSONValue {
        guard let data = valueJSON.data(using: .utf8) else {
            throw WanderRemoteError.invalidResponse("Attribute value is not UTF-8 JSON")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct SaveOwnPlaceResponse: Decodable {
    let userPlaceID: String
    let placeID: String

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
        case placeID = "place_id"
    }
}
