import Foundation

private struct RemoteFeatureFlagDTO: Decodable {
    let key: String
    let userID: String?
    let enabled: Bool
    let valueType: String?
    let integerValue: Int?

    enum CodingKeys: String, CodingKey {
        case key
        case userID = "user_id"
        case enabled
        case valueType = "value_type"
        case integerValue = "integer_value"
    }

    func value(for key: FeatureFlagKey) -> FeatureFlagValue? {
        let value: FeatureFlagValue?
        switch valueType ?? FeatureFlagValueKind.boolean.rawValue {
        case FeatureFlagValueKind.boolean.rawValue:
            value = .boolean(enabled)
        case FeatureFlagValueKind.integer.rawValue:
            value = integerValue.map(FeatureFlagValue.integer)
        default:
            value = nil
        }
        guard let value, key.definition.accepts(value) else { return nil }
        return value
    }
}

struct SupabaseFeatureFlagRepository: FeatureFlagRepository {
    private let table: RemoteTableCalling

    init(table: RemoteTableCalling) {
        self.table = table
    }

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        let rows: [RemoteFeatureFlagDTO] = try await table.select(
            table: "feature_flags",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "key,user_id,enabled,value_type,integer_value"
                ),
                URLQueryItem(
                    name: "key",
                    value: "in.(\(FeatureFlagKey.allCases.map(\.rawValue).joined(separator: ",")))"
                )
            ]
        )

        var values: [FeatureFlagKey: ResolvedFeatureFlagValue] = [:]
        for row in rows where row.userID == nil {
            guard let key = FeatureFlagKey(rawValue: row.key),
                  let value = row.value(for: key)
            else { continue }
            values[key] = ResolvedFeatureFlagValue(
                value: value,
                source: .globalDefault
            )
        }
        for row in rows where row.userID == userID {
            guard let key = FeatureFlagKey(rawValue: row.key),
                  key.definition.allowsRemoteAccountOverride,
                  let value = row.value(for: key)
            else { continue }
            values[key] = ResolvedFeatureFlagValue(
                value: value,
                source: .accountOverride
            )
        }
        return values
    }
}

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

    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile {
        try CommunityContentPolicy.validate(update.displayName, update.handle, update.bio, update.homeArea)
        let response: RemoteCurrentProfileDTO = try await rpc.call(
            "update_own_profile",
            params: UpdateOwnProfileParams(
                displayName: update.displayName,
                handle: update.handle,
                bio: update.bio,
                homeArea: update.homeArea,
                defaultVisibility: update.defaultVisibility?.rawValue,
                isPrivateProfile: update.isPrivateProfile,
                markOnboardingComplete: update.markOnboardingComplete
            )
        )
        return response.localProfile()
    }

    func isHandleAvailable(_ handle: String) async throws -> Bool {
        try await rpc.call(
            "profile_handle_available",
            params: ProfileHandleAvailableParams(handle: handle)
        )
    }

    func profile(id: String) async throws -> ProfileViewState {
        let rows: [RemoteProfileShellDTO] = try await rpc.call(
            "profile_detail",
            params: ProfileDetailParams(profileID: id)
        )
        guard let shell = rows.first?.profileShell() else {
            throw WanderRemoteError.invalidResponse("Profile detail returned no visible profile")
        }
        return ProfileViewState(
            shell: shell,
            visiblePlaces: [],
            canFollow: shell.relationship == .nonFollower,
            canBlock: shell.relationship != .owner,
            isBlocked: false
        )
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        let rows: [RemoteProfileShellDTO] = try await rpc.call(
            "search_profiles_by_handle",
            params: SearchProfilesParams(query: handleQuery)
        )
        return rows.map { $0.profileShell() }
    }

    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        let rows: [RemoteDiscoverPeopleRecommendationDTO] = try await rpc.call(
            "discover_profile_recommendations",
            params: DiscoverProfileRecommendationsParams(limit: limit)
        )
        return rows.map { $0.recommendation() }
    }

    func updatePrivacy(isPrivateProfile: Bool, defaultVisibility: PlaceVisibility) async throws -> LocalProfile {
        let response: RemoteCurrentProfileDTO = try await rpc.call(
            "update_profile_privacy",
            params: UpdateProfilePrivacyParams(
                isPrivateProfile: isPrivateProfile,
                defaultVisibility: defaultVisibility.rawValue
            )
        )
        return response.localProfile()
    }
}

private struct DiscoverProfileRecommendationsParams: Encodable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "input_limit"
    }
}

private struct UpdateProfilePrivacyParams: Encodable {
    let isPrivateProfile: Bool
    let defaultVisibility: String

    enum CodingKeys: String, CodingKey {
        case isPrivateProfile = "input_is_private_profile"
        case defaultVisibility = "input_default_visibility"
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
        let rows: [RemoteProfileShellDTO] = try await rpc.call("blocked_profiles", params: EmptyParams())
        return rows.map { $0.profileShell() }
    }

    func isBlocked(userID: String) async throws -> Bool {
        throw WanderRemoteError.notImplemented("is blocked RPC")
    }
}

struct SupabaseMuteRepository: MuteRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func mute(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call("mute_profile", params: ProfileIDParams(profileID: userID))
    }

    func unmute(userID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call("unmute_profile", params: ProfileIDParams(profileID: userID))
    }

    func mutedProfiles() async throws -> [ProfileShell] {
        let rows: [RemoteProfileShellDTO] = try await rpc.call("muted_profiles", params: EmptyParams())
        return rows.map { $0.profileShell() }
    }
}

struct SupabaseCommunityReportRepository: CommunityReportRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func submit(_ submission: CommunityReportSubmission) async throws -> CommunityReportReceipt {
        return try await rpc.call(
            "submit_content_report",
            params: SubmitContentReportParams(submission: submission)
        )
    }
}

private struct SubmitContentReportParams: Encodable {
    let subjectKind: String
    let subjectID: String
    let reportedUserID: String
    let reason: String
    let details: String?

    init(submission: CommunityReportSubmission) {
        subjectKind = submission.subject.kind.rawValue
        subjectID = submission.subject.subjectID
        reportedUserID = submission.subject.reportedUserID
        reason = submission.reason.rawValue
        details = submission.details
    }

    enum CodingKeys: String, CodingKey {
        case subjectKind = "input_subject_kind"
        case subjectID = "input_subject_id"
        case reportedUserID = "input_reported_user_id"
        case reason = "input_reason"
        case details = "input_details"
    }
}

struct SupabasePlaceRepository: PlaceRepository {
    private let rpc: RemoteProcedureCalling
    private let functions: (any RemoteFunctionCalling)?

    init(rpc: RemoteProcedureCalling, functions: (any RemoteFunctionCalling)? = nil) {
        self.rpc = rpc
        self.functions = functions
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

    func searchRecmePlaces(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        let rows: [RemoteRecmePlaceSearchDTO] = try await rpc.call(
            "search_recme_places",
            params: RecmePlaceSearchParams(request: request)
        )
        return rows.compactMap { $0.placeCandidate() }
    }

    func searchRecmePlacesSemantic(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        guard let functions else {
            throw WanderRemoteError.notConfigured
        }
        let response: SemanticPlaceSearchFunctionResponse = try await functions.invoke(
            "semantic-place-search",
            body: SemanticPlaceSearchBody(request: request)
        )
        return response.candidates.compactMap { $0.placeCandidate() }
    }

    func featuredPlaces(in viewport: MapViewport) async throws -> [VisiblePlace] {
        let rows: [RemoteVisiblePlaceDTO] = try await rpc.call(
            "featured_places_in_view",
            params: FeaturedPlacesParams(
                minLat: viewport.minLatitude,
                minLng: viewport.minLongitude,
                maxLat: viewport.maxLatitude,
                maxLng: viewport.maxLongitude
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

    func sharedPlace(id: String) async throws -> PlaceCandidate? {
        guard UUID(uuidString: id) != nil else { return nil }
        let preview: PublicSharedPlacePreview = try await rpc.call(
            "public_web_preview",
            params: PublicWebPreviewParams(
                inputKind: "place",
                inputIdentifier: id
            )
        )
        return preview.placeCandidate()
    }
}

private struct SemanticPlaceSearchBody: Encodable {
    let query: String
    let categories: [String]
    let area: String?
    let favoriteOnly: Bool
    let scope: String
    let limit: Int

    init(request: RecmePlaceSearchRequest) {
        query = request.semanticQuery
        categories = request.categories
        area = request.area
        favoriteOnly = request.favoriteOnly
        scope = request.scope.rawValue
        limit = request.limit
    }

    enum CodingKeys: String, CodingKey {
        case query
        case categories
        case area
        case favoriteOnly = "favorite_only"
        case scope
        case limit
    }
}

private struct SemanticPlaceSearchFunctionResponse: Decodable {
    let candidates: [RemoteRecmePlaceSearchDTO]
}

private struct RecmePlaceSearchParams: Encodable {
    let inputQuery: String
    let inputCategories: [String]?
    let inputArea: String?
    let inputFavoriteOnly: Bool
    let inputScope: String
    let inputLimit: Int

    init(request: RecmePlaceSearchRequest) {
        inputQuery = request.query
        inputCategories = request.categories.isEmpty ? nil : request.categories
        inputArea = request.area
        inputFavoriteOnly = request.favoriteOnly
        inputScope = request.scope.rawValue
        inputLimit = request.limit
    }

    enum CodingKeys: String, CodingKey {
        case inputQuery = "input_query"
        case inputCategories = "input_categories"
        case inputArea = "input_area"
        case inputFavoriteOnly = "input_favorite_only"
        case inputScope = "input_scope"
        case inputLimit = "input_limit"
    }
}

private struct RemoteRecmePlaceSearchDTO: Decodable {
    let id: String
    let canonicalName: String
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
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
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

    func placeCandidate() -> PlaceCandidate? {
        guard !canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              !sourceProviderPlaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return PlaceCandidate(
            id: id,
            name: canonicalName,
            category: category,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: categorySource ?? PlaceCategorySource.provider.rawValue,
            categoryConfidence: categoryConfidence,
            rawProviderType: rawProviderType,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            confidence: confidence ?? 1
        )
    }
}

private struct PublicWebPreviewParams: Encodable {
    let inputKind: String
    let inputIdentifier: String

    enum CodingKeys: String, CodingKey {
        case inputKind = "input_kind"
        case inputIdentifier = "input_identifier"
    }
}

private struct PublicSharedPlacePreview: Decodable {
    let isAvailable: Bool
    let placeID: String?
    let title: String?
    let category: String?
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
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case placeID = "place_id"
        case title
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

    func placeCandidate() -> PlaceCandidate? {
        guard isAvailable,
              let placeID,
              let title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let latitude,
              (-90...90).contains(latitude),
              let longitude,
              (-180...180).contains(longitude)
        else {
            return nil
        }

        let resolvedCategory = primaryCategory ?? category ?? "place"
        return PlaceCandidate(
            id: placeID,
            name: title,
            category: resolvedCategory,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: categorySource ?? PlaceCategorySource.legacy.rawValue,
            categoryConfidence: categoryConfidence,
            rawProviderType: rawProviderType,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider ?? "recme",
            sourceProviderPlaceID: sourceProviderPlaceID,
            confidence: confidence ?? 1
        )
    }
}

struct SupabaseFeedRepository: FeedRepository {
    private let rpc: RemoteProcedureCalling
    private let storage: (any RemoteStorageCalling)?

    init(rpc: RemoteProcedureCalling, storage: (any RemoteStorageCalling)? = nil) {
        self.rpc = rpc
        self.storage = storage ?? (rpc as? any RemoteStorageCalling)
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        let response: RemoteFollowedFeedPageDTO = try await rpc.call(
            "followed_feed",
            params: FollowedFeedParams(before: before, limit: min(max(limit, 1), 50))
        )
        let activityIDs = Array(
            Set(response.activity.compactMap { item in
                UUID(uuidString: item.id)?.uuidString.lowercased()
            })
        ).sorted()
        let mediaRows: [RemoteActivityMediaDTO]
        if activityIDs.isEmpty {
            mediaRows = []
        } else {
            mediaRows = (try? await rpc.call(
                "activity_media",
                params: ActivityEngagementSummariesParams(activityIDs: activityIDs)
            )) ?? []
        }
        let mediaByActivityID = Dictionary(
            mediaRows.map { ($0.activityID.lowercased(), $0.media) },
            uniquingKeysWith: { current, _ in current }
        )
        return try await response.followedFeedPage(
            storage: storage,
            mediaByActivityID: mediaByActivityID
        )
    }
}

struct SupabaseActivityEngagementRepository: ActivityEngagementRepository {
    private let rpc: RemoteProcedureCalling
    private let storage: (any RemoteStorageCalling)?

    init(rpc: RemoteProcedureCalling, storage: (any RemoteStorageCalling)? = nil) {
        self.rpc = rpc
        self.storage = storage ?? (rpc as? any RemoteStorageCalling)
    }

    func activity(id: String) async throws -> FeedActivity {
        let response: RemoteFeedActivityDTO = try await rpc.call(
            "activity_detail",
            params: ActivityDetailParams(activityID: id)
        )
        let mediaRows: [RemoteActivityMediaDTO] = (try? await rpc.call(
            "activity_media",
            params: ActivityEngagementSummariesParams(activityIDs: [id])
        )) ?? []
        return try await response.activity(
            storage: storage,
            mediaOverride: mediaRows.first(where: { $0.activityID == id })?.media
        )
    }

    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] {
        let rows: [RemoteActivityEngagementSummaryDTO] = try await rpc.call(
            "activity_engagement_summaries",
            params: ActivityEngagementSummariesParams(activityIDs: activityIDs)
        )
        return rows.map(\.summary)
    }

    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] {
        let rows: [RemotePlaceActivityEngagementDTO] = try await rpc.call(
            "place_activity_engagement_summaries",
            params: PlaceActivityEngagementSummariesParams(userPlaceIDs: userPlaceIDs)
        )
        return try rows.map { try $0.match() }
    }

    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary {
        let response: RemoteActivityEngagementSummaryDTO = try await rpc.call(
            "set_activity_like",
            params: SetActivityLikeParams(activityID: activityID, isLiked: isLiked)
        )
        return response.summary
    }

    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        let response: RemoteActivityCommentsPageDTO = try await rpc.call(
            "activity_comments",
            params: ActivityCommentsParams(
                activityID: activityID,
                before: before,
                limit: min(max(limit, 1), 100)
            )
        )
        return response.page
    }

    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        try CommunityContentPolicy.validate(body)
        let response: RemoteActivityCommentPostDTO = try await rpc.call(
            "add_activity_comment",
            params: AddActivityCommentParams(activityID: activityID, body: body)
        )
        return response.result
    }

    func deleteComment(commentID: String) async throws -> ActivityEngagementSummary {
        let response: RemoteActivityEngagementSummaryDTO = try await rpc.call(
            "delete_own_activity_comment",
            params: DeleteActivityCommentParams(commentID: commentID)
        )
        return response.summary
    }
}

struct SupabaseUserPlaceRepository: UserPlaceRepository, SocialPlaceSaveRepository, CheckInRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
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

    func ownWannaGoPlans() async throws -> [OwnWannaGoPlan] {
        let rows: [RemoteOwnWannaGoPlanDTO] = try await rpc.call(
            "own_wanna_go_plans",
            params: EmptyParams()
        )
        return try rows.map { try $0.plan() }
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        try CommunityContentPolicy.validate(
            draft.place.canonicalName,
            draft.place.address,
            draft.place.locality,
            draft.place.region,
            draft.place.country,
            draft.note
        )
        for attribute in draft.attributes {
            try CommunityContentPolicy.validateJSONText(attribute.valueJSON)
        }
        let result: SaveOwnPlaceResponse = try await rpc.call(
            "save_own_place",
            params: SaveOwnPlaceParams(draft: draft)
        )
        return SaveResult(userPlaceID: result.userPlaceID, syncState: .synced, placeID: result.placeID)
    }

    func saveCheckIn(_ draft: CheckInSaveDraft) async throws -> CheckInSaveResult {
        try CommunityContentPolicy.validate(
            draft.userPlace.place.canonicalName,
            draft.userPlace.place.address,
            draft.userPlace.place.locality,
            draft.userPlace.place.region,
            draft.userPlace.place.country,
            draft.userPlace.note,
            draft.visit.note,
            draft.historicalWant?.note
        )
        try CommunityContentPolicy.validateJSONText(draft.visit.attributeAnswersJSON)
        let result: SaveOwnCheckInResponse = try await rpc.call(
            "save_own_check_in",
            params: SaveOwnCheckInParams(draft: draft)
        )
        return CheckInSaveResult(
            saveResult: SaveResult(
                userPlaceID: result.userPlaceID,
                syncState: .synced,
                placeID: result.placeID
            ),
            visitResult: PlaceVisitResult(
                visitID: result.visitID,
                userPlaceID: result.userPlaceID,
                visitedAt: result.visitedAt,
                note: result.note,
                ratingScore: result.ratingScore,
                tags: result.tags,
                backfilledFromUserPlace: result.backfilledFromUserPlace
            )
        )
    }

    func deleteCheckIn(visitID: String) async throws -> CheckInDeleteResult {
        let result: DeleteOwnCheckInResponse = try await rpc.call(
            "delete_own_check_in",
            params: DeleteOwnCheckInParams(inputVisitID: visitID)
        )
        guard let transition = CheckInDeleteTransition(rawValue: result.transition) else {
            throw WanderRemoteError.invalidResponse("Unknown check-in delete transition: \(result.transition)")
        }
        return CheckInDeleteResult(
            visitID: result.visitID,
            userPlaceID: result.userPlaceID,
            transition: transition
        )
    }

    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {
        throw WanderRemoteError.notImplemented("update visibility RPC")
    }

    func delete(userPlaceID: String) async throws {
        let _: DeleteOwnUserPlaceResponse = try await rpc.call(
            "delete_own_user_place",
            params: DeleteOwnUserPlaceParams(inputUserPlaceID: userPlaceID)
        )
    }

    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String) async throws -> SaveResult {
        let result: SaveVisiblePlaceResponse = try await rpc.call(
            "save_visible_place",
            params: SaveVisiblePlaceParams(inputPlaceID: placeID, inputSourceUserPlaceID: sourceUserPlaceID)
        )
        return SaveResult(userPlaceID: result.userPlaceID, syncState: .synced)
    }
}

struct SupabaseVisitRepository: VisitRepository {
    private let table: RemoteTableCalling
    private let storage: RemoteStorageCalling

    init(table: RemoteTableCalling, storage: RemoteStorageCalling) {
        self.table = table
        self.storage = storage
    }

    func visits(for userPlaceID: String) async throws -> [PlaceVisitResult] {
        let rows: [PlaceVisitRow] = try await table.select(
            table: "place_visits",
            queryItems: [
                URLQueryItem(name: "select", value: PlaceVisitRow.selectColumns),
                URLQueryItem(name: "user_place_id", value: "eq.\(userPlaceID)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "visited_at.desc")
            ]
        )
        return rows.map(\.result)
    }

    func upsertVisit(_ draft: PlaceVisitDraft) async throws -> PlaceVisitResult {
        try CommunityContentPolicy.validate(draft.note)
        try CommunityContentPolicy.validateJSONText(draft.attributeAnswersJSON)
        let body = PlaceVisitUpsertBody(draft: draft)
        let rows: [PlaceVisitRow] = try await table.upsert(
            table: "place_visits",
            body: [body],
            onConflict: "id"
        )
        guard let row = rows.first else {
            throw WanderRemoteError.invalidResponse("place_visits upsert returned no rows")
        }
        return row.result
    }

    func deleteVisit(visitID: String) async throws {
        try await table.delete(
            table: "place_visits",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(visitID)")]
        )
    }

    func photos(for visitID: String) async throws -> [VisitPhotoResult] {
        let rows: [VisitPhotoRow] = try await table.select(
            table: "visit_photos",
            queryItems: [
                URLQueryItem(name: "select", value: VisitPhotoRow.selectColumns),
                URLQueryItem(name: "visit_id", value: "eq.\(visitID)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "sort_order.asc,created_at.asc")
            ]
        )
        var results: [VisitPhotoResult] = []
        for row in rows {
            let remoteURL = try await storage.signedObjectURL(
                bucket: row.storageBucket,
                path: row.storagePath,
                expiresIn: 3600
            )
            results.append(row.result(remoteURLString: remoteURL.absoluteString))
        }
        return results
    }

    func visibleUploadedPhotos(for visitID: String) async throws -> [VisitPhotoResult] {
        let rows: [VisitPhotoRow] = try await table.select(
            table: "visit_photos",
            queryItems: [
                URLQueryItem(name: "select", value: VisitPhotoRow.selectColumns),
                URLQueryItem(name: "visit_id", value: "eq.\(visitID)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "upload_state", value: "eq.uploaded"),
                URLQueryItem(name: "order", value: "sort_order.asc,created_at.asc")
            ]
        )
        var results: [VisitPhotoResult] = []
        results.reserveCapacity(rows.count)
        for row in rows {
            do {
                let remoteURL = try await storage.signedObjectURL(
                    bucket: row.storageBucket,
                    path: row.storagePath,
                    expiresIn: 3600
                )
                results.append(row.result(remoteURLString: remoteURL.absoluteString))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One missing object must not suppress the visit's other
                // uploaded photos. The store preserves a cached URL when a
                // fresh signature is temporarily unavailable.
                results.append(row.result(remoteURLString: nil))
            }
        }
        return results
    }

    func upsertPhotoMetadata(_ draft: VisitPhotoDraft) async throws -> VisitPhotoResult {
        let body = VisitPhotoUpsertBody(draft: draft)
        let rows: [VisitPhotoRow] = try await table.upsert(
            table: "visit_photos",
            body: [body],
            onConflict: "id"
        )
        guard let row = rows.first else {
            throw WanderRemoteError.invalidResponse("visit_photos upsert returned no rows")
        }
        return row.result()
    }

    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        try await storage.uploadObject(bucket: bucket, path: path, data: data, contentType: contentType, upsert: true)
        return try await storage.signedObjectURL(bucket: bucket, path: path, expiresIn: 3600)
    }

    func deletePhoto(photoID: String, bucket: String, path: String) async throws {
        try await storage.deleteObject(bucket: bucket, path: path)
        try await table.delete(
            table: "visit_photos",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(photoID)")]
        )
    }
}

private struct PlaceVisitRow: Decodable {
    static let selectColumns = "id,user_place_id,visited_at,note,rating_score,tags,backfilled_from_user_place,created_at,updated_at,deleted_at"

    let id: String
    let userPlaceID: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let tags: [String]
    let backfilledFromUserPlace: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userPlaceID = "user_place_id"
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case tags
        case backfilledFromUserPlace = "backfilled_from_user_place"
    }

    var result: PlaceVisitResult {
        PlaceVisitResult(
            visitID: id,
            userPlaceID: userPlaceID,
            visitedAt: visitedAt,
            note: note,
            ratingScore: ratingScore,
            tags: tags,
            backfilledFromUserPlace: backfilledFromUserPlace
        )
    }
}

private struct PlaceVisitUpsertBody: Encodable {
    let id: String?
    let userPlaceID: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswers: [VisitAttributeAnswer]
    let backfilledFromUserPlace: Bool
    let deletedAt: Date?

    init(draft: PlaceVisitDraft) {
        self.id = draft.id
        self.userPlaceID = draft.userPlaceID
        self.visitedAt = draft.visitedAt
        self.note = draft.note
        self.ratingScore = PlaceRating.normalized(draft.ratingScore)
        self.attributeAnswers = Self.decodedAttributeAnswers(draft.attributeAnswersJSON)
        self.backfilledFromUserPlace = draft.backfilledFromUserPlace
        self.deletedAt = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userPlaceID = "user_place_id"
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case attributeAnswers = "attribute_answers"
        case backfilledFromUserPlace = "backfilled_from_user_place"
        case deletedAt = "deleted_at"
    }

    private static func decodedAttributeAnswers(_ json: String) -> [VisitAttributeAnswer] {
        guard let data = json.data(using: .utf8),
              let answers = try? JSONDecoder().decode([VisitAttributeAnswer].self, from: data)
        else {
            return []
        }
        return answers
    }
}

private struct VisitPhotoRow: Decodable {
    static let selectColumns = "id,visit_id,storage_bucket,storage_path,content_type,byte_size,width,height,captured_at,sort_order,upload_state,created_at,updated_at,deleted_at"

    let id: String
    let visitID: String
    let storageBucket: String
    let storagePath: String
    let contentType: String?
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int
    let uploadStateRaw: String

    enum CodingKeys: String, CodingKey {
        case id
        case visitID = "visit_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case width
        case height
        case capturedAt = "captured_at"
        case sortOrder = "sort_order"
        case uploadStateRaw = "upload_state"
    }

    func result(remoteURLString: String? = nil) -> VisitPhotoResult {
        VisitPhotoResult(
            photoID: id,
            visitID: visitID,
            storageBucket: storageBucket,
            storagePath: storagePath,
            remoteURLString: remoteURLString,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            capturedAt: capturedAt,
            sortOrder: sortOrder,
            uploadState: VisitPhotoUploadState(rawValue: uploadStateRaw) ?? .pendingUpload
        )
    }
}

private struct VisitPhotoUpsertBody: Encodable {
    let id: String?
    let visitID: String
    let storageBucket: String
    let storagePath: String
    let contentType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int
    let uploadStateRaw: String
    let deletedAt: Date?

    init(draft: VisitPhotoDraft) {
        self.id = draft.id
        self.visitID = draft.visitID
        self.storageBucket = draft.storageBucket
        self.storagePath = draft.storagePath
        self.contentType = draft.contentType ?? "image/jpeg"
        self.byteSize = draft.byteSize
        self.width = draft.width
        self.height = draft.height
        self.capturedAt = draft.capturedAt
        self.sortOrder = draft.sortOrder
        self.uploadStateRaw = draft.uploadState == .uploading ? VisitPhotoUploadState.pendingUpload.rawValue : draft.uploadState.rawValue
        self.deletedAt = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case visitID = "visit_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case width
        case height
        case capturedAt = "captured_at"
        case sortOrder = "sort_order"
        case uploadStateRaw = "upload_state"
        case deletedAt = "deleted_at"
    }
}

struct SupabaseSharedVisitRepository: SharedVisitRepository {
    private let rpc: RemoteProcedureCalling
    private let table: RemoteTableCalling
    private let storage: RemoteStorageCalling

    init(rpc: RemoteProcedureCalling, table: RemoteTableCalling, storage: RemoteStorageCalling) {
        self.rpc = rpc
        self.table = table
        self.storage = storage
    }

    func createInvites(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        let rows: [SharedVisitInviteRow] = try await rpc.call(
            "create_shared_visit_invites",
            params: CreateSharedVisitInvitesParams(
                sourceVisitID: sourceVisitID,
                inviteeUserIDs: inviteeUserIDs
            )
        )
        return rows.map(\.result)
    }

    func inviteeUserIDs(sourceVisitID: String) async throws -> [String] {
        let rows: [SharedVisitInviteeRow] = try await rpc.call(
            "list_shared_visit_invitees",
            params: SharedVisitSourceVisitParams(sourceVisitID: sourceVisitID)
        )
        return rows.map(\.inviteeUserID)
    }

    func setInvitees(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        let rows: [SharedVisitInviteRow] = try await rpc.call(
            "set_shared_visit_invitees",
            params: CreateSharedVisitInvitesParams(
                sourceVisitID: sourceVisitID,
                inviteeUserIDs: inviteeUserIDs
            )
        )
        return rows.map(\.result)
    }

    func inbox(before: Date?, limit: Int) async throws -> [SharedVisitInvitation] {
        let rows: [SharedVisitInvitationRow] = try await rpc.call(
            "list_shared_visit_inbox",
            params: SharedVisitInboxParams(before: before, limit: limit)
        )
        return rows.map(\.invitation)
    }

    func context(participantID: String, generation: Int) async throws -> SharedVisitInvitation? {
        let rows: [SharedVisitInvitationRow] = try await rpc.call(
            "get_shared_visit_context",
            params: SharedVisitContextParams(participantID: participantID, generation: generation)
        )
        return rows.first?.invitation
    }

    func resolveDestination(participantID: String, generation: Int) async throws -> SharedVisitDestination? {
        let rows: [SharedVisitDestinationRow] = try await rpc.call(
            "resolve_shared_visit_destination",
            params: SharedVisitContextParams(participantID: participantID, generation: generation)
        )
        return rows.first?.destination
    }

    func accept(_ draft: SharedVisitAcceptanceDraft) async throws -> SharedVisitAcceptanceResult {
        let response: SharedVisitAcceptanceResponse = try await rpc.call(
            "accept_shared_visit",
            params: SharedVisitAcceptanceParams(draft: draft)
        )
        return response.result
    }

    func decline(participantID: String, generation: Int) async throws {
        let _: Bool = try await rpc.call(
            "decline_shared_visit",
            params: SharedVisitContextParams(participantID: participantID, generation: generation)
        )
    }

    func companionContext(visitIDs: [String]) async throws -> [SharedVisitCompanion] {
        guard !visitIDs.isEmpty else { return [] }
        let rows: [SharedVisitCompanionRow] = try await rpc.call(
            "get_shared_visit_companion_context",
            params: SharedVisitCompanionParams(visitIDs: Array(visitIDs.prefix(50)))
        )
        return rows.map(\.companion)
    }

    func downloadPhotoData(bucket: String, path: String) async throws -> Data {
        try await storage.downloadObject(bucket: bucket, path: path)
    }

    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws {
        try await storage.uploadObject(
            bucket: bucket,
            path: path,
            data: data,
            contentType: contentType,
            upsert: true
        )
    }

    func markPhotoUploaded(photoID: String) async throws {
        let _: [VisitPhotoRow] = try await table.update(
            table: "visit_photos",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(photoID)")],
            body: SharedVisitPhotoUploadedBody()
        )
    }
}

private struct CreateSharedVisitInvitesParams: Encodable {
    let sourceVisitID: String
    let inviteeUserIDs: [String]

    enum CodingKeys: String, CodingKey {
        case sourceVisitID = "input_source_visit_id"
        case inviteeUserIDs = "input_invitee_user_ids"
    }
}

private struct SharedVisitSourceVisitParams: Encodable {
    let sourceVisitID: String

    enum CodingKeys: String, CodingKey {
        case sourceVisitID = "input_source_visit_id"
    }
}

private struct SharedVisitInviteeRow: Decodable {
    let inviteeUserID: String

    enum CodingKeys: String, CodingKey {
        case inviteeUserID = "invitee_user_id"
    }
}

private struct SharedVisitInviteRow: Decodable {
    let participantID: String
    let inviteeUserID: String
    let participantStatus: String
    let invitationGeneration: Int

    enum CodingKeys: String, CodingKey {
        case participantID = "participant_id"
        case inviteeUserID = "invitee_user_id"
        case participantStatus = "participant_status"
        case invitationGeneration = "invitation_generation"
    }

    var result: SharedVisitInviteResult {
        SharedVisitInviteResult(
            participantID: participantID,
            inviteeUserID: inviteeUserID,
            status: SharedVisitParticipantStatus(rawValue: participantStatus) ?? .pending,
            invitationGeneration: invitationGeneration
        )
    }
}

private struct SharedVisitInboxParams: Encodable {
    let before: Date?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case before = "input_before"
        case limit = "input_limit"
    }
}

private struct SharedVisitContextParams: Encodable {
    let participantID: String
    let generation: Int

    enum CodingKeys: String, CodingKey {
        case participantID = "input_participant_id"
        case generation = "input_generation"
    }
}

private struct SharedVisitInvitationRow: Decodable {
    let participantID: String
    let groupID: String
    let invitationGeneration: Int
    let snapshotRevision: Int
    let participantStatus: String
    let invitedAt: Date
    let sourceVisitID: String
    let sourceOwnerUserID: String
    let sourceOwnerHandle: String
    let sourceOwnerDisplayName: String
    let sourceOwnerAvatarURL: String?
    let placeID: String
    let canonicalName: String
    let category: String
    let primaryCategory: String?
    let subcategory: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String?
    let sourceSnapshot: SharedVisitSnapshotRow

    enum CodingKeys: String, CodingKey {
        case participantID = "participant_id"
        case groupID = "group_id"
        case invitationGeneration = "invitation_generation"
        case snapshotRevision = "snapshot_revision"
        case participantStatus = "participant_status"
        case invitedAt = "invited_at"
        case sourceVisitID = "source_visit_id"
        case sourceOwnerUserID = "source_owner_user_id"
        case sourceOwnerHandle = "source_owner_handle"
        case sourceOwnerDisplayName = "source_owner_display_name"
        case sourceOwnerAvatarURL = "source_owner_avatar_url"
        case placeID = "place_id"
        case canonicalName = "canonical_name"
        case category
        case primaryCategory = "primary_category"
        case subcategory
        case address
        case locality
        case region
        case country
        case latitude
        case longitude
        case sourceProvider = "source_provider"
        case sourceProviderPlaceID = "source_provider_place_id"
        case sourceSnapshot = "source_snapshot"
    }

    var invitation: SharedVisitInvitation {
        SharedVisitInvitation(
            participantID: participantID,
            groupID: groupID,
            invitationGeneration: invitationGeneration,
            snapshotRevision: snapshotRevision,
            status: SharedVisitParticipantStatus(rawValue: participantStatus) ?? .pending,
            invitedAt: invitedAt,
            sourceVisitID: sourceVisitID,
            sourceOwnerUserID: sourceOwnerUserID,
            sourceOwnerHandle: sourceOwnerHandle,
            sourceOwnerDisplayName: sourceOwnerDisplayName,
            sourceOwnerAvatarURL: sourceOwnerAvatarURL,
            placeID: placeID,
            placeName: canonicalName,
            category: category,
            primaryCategory: primaryCategory ?? category,
            subcategory: subcategory,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            visitedAt: sourceSnapshot.visitedAt,
            note: sourceSnapshot.note,
            ratingScore: sourceSnapshot.ratingScore,
            attributeAnswers: sourceSnapshot.attributeAnswers,
            tags: sourceSnapshot.tags,
            photos: sourceSnapshot.photos
        )
    }
}

private struct SharedVisitSnapshotRow: Decodable {
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswers: [VisitAttributeAnswer]
    let tags: [String]
    let photoRows: [SharedVisitPhotoSnapshotRow]

    enum CodingKeys: String, CodingKey {
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case attributeAnswers = "attribute_answers"
        case tags
        case photoRows = "photos"
    }

    var photos: [SharedVisitPhotoSnapshot] { photoRows.map(\.snapshot) }
}

private struct SharedVisitPhotoSnapshotRow: Decodable {
    let photoID: String
    let storageBucket: String
    let storagePath: String
    let contentType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case width
        case height
        case capturedAt = "captured_at"
        case sortOrder = "sort_order"
    }

    var snapshot: SharedVisitPhotoSnapshot {
        SharedVisitPhotoSnapshot(
            photoID: photoID,
            storageBucket: storageBucket,
            storagePath: storagePath,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            capturedAt: capturedAt,
            sortOrder: sortOrder
        )
    }
}

private struct SharedVisitAcceptanceParams: Encodable {
    let participantID: String
    let generation: Int
    let snapshotRevision: Int
    let operationID: String
    let userPlaceID: String
    let visitID: String
    let userPlace: SharedVisitUserPlacePayload
    let visit: SharedVisitVisitPayload
    let attributes: [SharedVisitAttributePayload]
    let selectedPhotoIDs: [String]

    init(draft: SharedVisitAcceptanceDraft) {
        participantID = draft.participantID
        generation = draft.invitationGeneration
        snapshotRevision = draft.snapshotRevision
        operationID = draft.operationID
        userPlaceID = draft.userPlaceID
        visitID = draft.visitID
        userPlace = SharedVisitUserPlacePayload(visibility: draft.visibility.rawValue)
        visit = SharedVisitVisitPayload(draft: draft)
        attributes = draft.attributes.map(SharedVisitAttributePayload.init)
        selectedPhotoIDs = draft.selectedPhotoIDs
    }

    enum CodingKeys: String, CodingKey {
        case participantID = "input_participant_id"
        case generation = "input_generation"
        case snapshotRevision = "input_snapshot_revision"
        case operationID = "input_operation_id"
        case userPlaceID = "input_user_place_id"
        case visitID = "input_visit_id"
        case userPlace = "input_user_place"
        case visit = "input_visit"
        case attributes = "input_attributes"
        case selectedPhotoIDs = "input_selected_photo_ids"
    }
}

private struct SharedVisitUserPlacePayload: Encodable {
    let visibility: String
}

private struct SharedVisitVisitPayload: Encodable {
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswers: [SharedVisitAttributePayload]

    init(draft: SharedVisitAcceptanceDraft) {
        visitedAt = draft.visitedAt
        note = draft.note
        ratingScore = PlaceRating.normalized(draft.ratingScore)
        attributeAnswers = draft.attributes.map(SharedVisitAttributePayload.init)
    }

    enum CodingKeys: String, CodingKey {
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case attributeAnswers = "attribute_answers"
    }
}

private struct SharedVisitAttributePayload: Encodable {
    let questionKey: String
    let valueType: String
    let value: JSONValue

    init(_ draft: PlaceAttributeDraft) {
        questionKey = draft.questionKey
        valueType = draft.valueType
        value = (try? JSONDecoder().decode(JSONValue.self, from: Data(draft.valueJSON.utf8))) ?? .null
    }

    enum CodingKeys: String, CodingKey {
        case questionKey = "question_key"
        case valueType = "value_type"
        case value
    }
}

private struct SharedVisitAcceptanceResponse: Decodable {
    let operationID: String
    let participantID: String
    let userPlaceID: String
    let visitID: String
    let backfilledFromUserPlace: Bool
    let statusRaw: String
    let photoCopies: [SharedVisitPhotoCopyRow]

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case participantID = "participant_id"
        case userPlaceID = "user_place_id"
        case visitID = "visit_id"
        case backfilledFromUserPlace = "backfilled_from_user_place"
        case statusRaw = "status"
        case photoCopies = "photo_copies"
    }

    var result: SharedVisitAcceptanceResult {
        SharedVisitAcceptanceResult(
            operationID: operationID,
            participantID: participantID,
            userPlaceID: userPlaceID,
            visitID: visitID,
            backfilledFromUserPlace: backfilledFromUserPlace,
            status: SharedVisitParticipantStatus(rawValue: statusRaw) ?? .accepted,
            photoCopies: photoCopies.map(\.copy)
        )
    }
}

private struct SharedVisitPhotoCopyRow: Decodable {
    let sourcePhotoID: String
    let sourceBucket: String
    let sourcePath: String
    let destinationPhotoID: String
    let destinationBucket: String
    let destinationPath: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case sourcePhotoID = "source_photo_id"
        case sourceBucket = "source_bucket"
        case sourcePath = "source_path"
        case destinationPhotoID = "destination_photo_id"
        case destinationBucket = "destination_bucket"
        case destinationPath = "destination_path"
        case contentType = "content_type"
    }

    var copy: SharedVisitPhotoCopy {
        SharedVisitPhotoCopy(
            sourcePhotoID: sourcePhotoID,
            sourceBucket: sourceBucket,
            sourcePath: sourcePath,
            destinationPhotoID: destinationPhotoID,
            destinationBucket: destinationBucket,
            destinationPath: destinationPath,
            contentType: contentType
        )
    }
}

private struct SharedVisitDestinationRow: Decodable {
    let participantID: String
    let requestedGeneration: Int
    let currentGeneration: Int
    let routeStatus: String
    let placeID: String
    let acceptedVisitID: String?
    let sourceVisitID: String

    enum CodingKeys: String, CodingKey {
        case participantID = "participant_id"
        case requestedGeneration = "requested_generation"
        case currentGeneration = "current_generation"
        case routeStatus = "route_status"
        case placeID = "place_id"
        case acceptedVisitID = "accepted_visit_id"
        case sourceVisitID = "source_visit_id"
    }

    var destination: SharedVisitDestination {
        SharedVisitDestination(
            participantID: participantID,
            requestedGeneration: requestedGeneration,
            currentGeneration: currentGeneration,
            status: routeStatus,
            placeID: placeID,
            acceptedVisitID: acceptedVisitID,
            sourceVisitID: sourceVisitID
        )
    }
}

private struct SharedVisitCompanionParams: Encodable {
    let visitIDs: [String]

    enum CodingKeys: String, CodingKey {
        case visitIDs = "input_visit_ids"
    }
}

private struct SharedVisitCompanionRow: Decodable {
    let visitID: String
    let userID: String
    let handle: String
    let displayName: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case visitID = "visit_id"
        case userID = "companion_user_id"
        case handle = "companion_handle"
        case displayName = "companion_display_name"
        case avatarURL = "companion_avatar_url"
    }

    var companion: SharedVisitCompanion {
        SharedVisitCompanion(
            visitID: visitID,
            userID: userID,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL
        )
    }
}

private struct SharedVisitPhotoUploadedBody: Encodable {
    let uploadState = VisitPhotoUploadState.uploaded.rawValue

    enum CodingKeys: String, CodingKey {
        case uploadState = "upload_state"
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
        try CommunityContentPolicy.validate(draft.name, draft.description)
        return try await rpc.call(
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

    func leave(listID: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "leave_place_list",
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

    func createInvite(listID: String) async throws -> PlaceListInviteCreation {
        try await rpc.call(
            "create_place_list_invite",
            params: PlaceListIDParams(inputListID: listID)
        )
    }

    func resolveInvite(token: String) async throws -> PlaceListInviteResolution {
        try await rpc.call(
            "resolve_place_list_invite",
            params: PlaceListInviteTokenParams(inputToken: token)
        )
    }

    func acceptInvite(token: String) async throws -> String {
        try await rpc.call(
            "accept_place_list_invite",
            params: PlaceListInviteTokenParams(inputToken: token)
        )
    }

    func revokeInvite(token: String) async throws {
        let _: EmptyRPCResponse = try await rpc.call(
            "revoke_place_list_invite",
            params: PlaceListInviteTokenParams(inputToken: token)
        )
    }
}

private struct RemoteProfileRelationshipDTO: Decodable {
    let profileID: String
    let relationship: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case relationship
    }

    func pair() throws -> (String, ViewerRelationship) {
        guard let value = ViewerRelationship(rawValue: relationship) else {
            throw WanderRemoteError.invalidResponse("Unknown profile relationship: \(relationship)")
        }
        return (profileID, value)
    }
}

private struct RemoteCurrentUserCalendarSnapshotDTO: Decodable {
    let places: [RemoteVisiblePlaceDTO]
    let visits: [PlaceVisitRow]
}

private struct RemotePlaceListsSnapshotDTO: Decodable {
    let summaries: [RemotePlaceListSummaryDTO]
    let details: [RemotePlaceListDetailDTO]
    let ownerPlaces: [RemoteVisiblePlaceDTO]
    let relationships: [RemoteProfileRelationshipDTO]

    enum CodingKeys: String, CodingKey {
        case summaries
        case details
        case ownerPlaces = "owner_places"
        case relationships
    }
}

private struct RemoteSocialSurfaceSnapshotDTO: Decodable {
    let following: [RemoteProfileShellDTO]
    let followers: [RemoteProfileShellDTO]
    let viewportPlaces: [RemoteVisiblePlaceDTO]
    let wannaGoPlans: [RemoteOwnWannaGoPlanDTO]
    let followedPlaces: [RemoteVisiblePlaceDTO]
    let relationships: [RemoteProfileRelationshipDTO]

    enum CodingKeys: String, CodingKey {
        case following
        case followers
        case viewportPlaces = "viewport_places"
        case wannaGoPlans = "wanna_go_plans"
        case followedPlaces = "followed_places"
        case relationships
    }
}

struct SupabaseSurfaceSnapshotRepository: SurfaceSnapshotRepository {
    private let rpc: RemoteProcedureCalling

    init(rpc: RemoteProcedureCalling) {
        self.rpc = rpc
    }

    func currentUserCalendarSnapshot() async throws -> CurrentUserCalendarRemoteSnapshot {
        let response: RemoteCurrentUserCalendarSnapshotDTO = try await rpc.call(
            "current_user_calendar_snapshot",
            params: EmptyParams()
        )
        return CurrentUserCalendarRemoteSnapshot(
            visiblePlaces: try response.places.map { try $0.visiblePlace() },
            visits: response.visits.map(\.result)
        )
    }

    func placeListsSnapshot() async throws -> PlaceListsRemoteSnapshot {
        let response: RemotePlaceListsSnapshotDTO = try await rpc.call(
            "visible_place_lists_snapshot",
            params: EmptyParams()
        )
        let ownerPlaces = try response.ownerPlaces.map { try $0.visiblePlace() }
        var visiblePlacesByOwnerID = Dictionary(
            uniqueKeysWithValues: Set(response.summaries.map(\.ownerUserID)).map {
                ($0, [VisiblePlace]())
            }
        )
        for place in ownerPlaces {
            visiblePlacesByOwnerID[place.owner.id, default: []].append(place)
        }
        return PlaceListsRemoteSnapshot(
            summaries: response.summaries.map { $0.summary() },
            details: response.details.map { $0.detail() },
            visiblePlacesByOwnerID: visiblePlacesByOwnerID,
            relationshipsByOwnerID: try Self.relationships(response.relationships)
        )
    }

    func socialSurfaceSnapshot(in viewport: MapViewport) async throws -> SocialSurfaceRemoteSnapshot {
        let response: RemoteSocialSurfaceSnapshotDTO = try await rpc.call(
            "social_surface_snapshot",
            params: SocialSurfaceSnapshotParams(viewport: viewport)
        )
        let followedPlaces = try response.followedPlaces.map { try $0.visiblePlace() }
        var visiblePlacesByOwnerID = Dictionary(
            uniqueKeysWithValues: Set(response.following.map(\.id)).map {
                ($0, [VisiblePlace]())
            }
        )
        for place in followedPlaces {
            visiblePlacesByOwnerID[place.owner.id, default: []].append(place)
        }
        return SocialSurfaceRemoteSnapshot(
            following: response.following.map { $0.profileShell() },
            followers: response.followers.map { $0.profileShell() },
            viewportPlaces: try response.viewportPlaces.map { try $0.visiblePlace() },
            ownWannaGoPlans: try response.wannaGoPlans.map { try $0.plan() },
            visiblePlacesByOwnerID: visiblePlacesByOwnerID,
            relationshipsByOwnerID: try Self.relationships(response.relationships)
        )
    }

    private static func relationships(
        _ rows: [RemoteProfileRelationshipDTO]
    ) throws -> [String: ViewerRelationship] {
        var result: [String: ViewerRelationship] = [:]
        for row in rows {
            let (profileID, relationship) = try row.pair()
            guard result.updateValue(relationship, forKey: profileID) == nil else {
                throw WanderRemoteError.invalidResponse(
                    "Surface snapshot contained duplicate relationship: \(profileID)"
                )
            }
        }
        return result
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

private struct SocialImportUnderstandingBody: Encodable {
    let schemaVersion = 1
    let platform: String
    let url: String
    let clientRequestID: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case platform
        case url
        case clientRequestID = "client_request_id"
    }
}

private struct SocialImportUnderstandingFunctionResponse: Decodable {
    struct Hint: Decodable {
        struct ResolvedPlace: Decodable {
            let provider: String
            let providerPlaceID: String
            let name: String
            let formattedAddress: String?
            let locality: String?
            let region: String?
            let country: String?
            let latitude: Double
            let longitude: Double
            let primaryType: String?
            let types: [String]?

            enum CodingKeys: String, CodingKey {
                case provider
                case providerPlaceID = "provider_place_id"
                case name
                case formattedAddress = "formatted_address"
                case locality
                case region
                case country
                case latitude
                case longitude
                case primaryType = "primary_type"
                case types
            }
        }

        let name: String
        let area: String?
        let modality: String
        let classification: String
        let resolvedPlaces: [ResolvedPlace]?

        enum CodingKeys: String, CodingKey {
            case name
            case area
            case modality
            case classification
            case resolvedPlaces = "resolved_places"
        }
    }

    let schemaVersion: Int
    let outcome: String
    let providerPath: String?
    let hints: [Hint]
    let mediaCount: Int?
    let modelAttemptCount: Int?
    let failureCategory: String?
    let declaredCountComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case outcome
        case providerPath = "provider_path"
        case hints
        case mediaCount = "media_count"
        case modelAttemptCount = "model_attempt_count"
        case failureCategory = "failure_category"
        case declaredCountComplete = "declared_count_complete"
    }
}

struct SupabaseSocialImportUnderstandingRepository: SocialImportUnderstandingRepository {
    private static let maximumHints = 150
    private let functions: RemoteFunctionCalling

    init(functions: RemoteFunctionCalling) {
        self.functions = functions
    }

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        guard [.instagram, .tiktok].contains(source),
              url.scheme?.lowercased() == "https"
        else {
            throw WanderRemoteError.invalidResponse("Unsupported social import source")
        }

        let response: SocialImportUnderstandingFunctionResponse = try await functions.invoke(
            "social-import-understand",
            body: SocialImportUnderstandingBody(
                platform: source.rawValue,
                url: url.absoluteString,
                clientRequestID: clientRequestID
            )
        )
        guard response.schemaVersion == 1 else {
            throw WanderRemoteError.invalidResponse("Unsupported social import response schema")
        }

        let decodedOutcome: SocialImportUnderstandingOutcome
        switch response.outcome {
        case "ok":
            decodedOutcome = .ok
        case "partial":
            decodedOutcome = .partial
        case "no_places":
            decodedOutcome = .noPlaces
        case "fallback":
            decodedOutcome = .fallback
        default:
            throw WanderRemoteError.invalidResponse("Unknown social import response outcome")
        }

        let providerPath = Self.providerPath(response.providerPath)
        let serverReasoningIsAuthoritative = providerPath == "apify_gemini"
        var seen = Set<String>()
        let hints = response.hints.prefix(Self.maximumHints).compactMap { hint -> SocialPlaceSearchHint? in
            guard ["destination", "itinerary"].contains(hint.classification),
                  let name = Self.cleaned(hint.name, maximumLength: 160)
            else { return nil }
            let area = Self.cleaned(hint.area, maximumLength: 160)
            let evidence: SocialPlaceSearchHint.Evidence
            switch hint.modality {
            case "tagged_location":
                evidence = .explicitLocation
            case "image_text", "video_text":
                evidence = .imageText
            case "caption", "speech":
                evidence = .itineraryPhrase
            default:
                return nil
            }
            let identity = [name, area ?? ""]
                .joined(separator: "|")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(identity).inserted else { return nil }
            return SocialPlaceSearchHint(
                name: name,
                area: area,
                evidence: evidence,
                isServerGrounded: serverReasoningIsAuthoritative,
                resolvedCandidates: serverReasoningIsAuthoritative
                    ? Self.resolvedCandidates(from: hint.resolvedPlaces)
                    : []
            )
        }

        let outcome: SocialImportUnderstandingOutcome
        switch decodedOutcome {
        case .ok where hints.isEmpty:
            // A complete, honestly empty model result is distinct from a
            // malformed hint set and may authoritatively report no places.
            outcome = response.hints.isEmpty ? .noPlaces : .fallback
        case .partial where hints.isEmpty:
            // An incomplete scan cannot authoritatively say there are no
            // places. Preserve both the on-device caption/Vision rescue path
            // and the incomplete signal so recovered rows remain retryable.
            outcome = .partial
        default:
            outcome = decodedOutcome
        }

        return SocialImportUnderstandingResult(
            outcome: outcome,
            hints: hints,
            diagnostics: SocialImportUnderstandingDiagnostics(
                providerPath: providerPath,
                mediaCount: Self.clamped(response.mediaCount, maximum: Self.maximumHints),
                modelAttemptCount: Self.clamped(response.modelAttemptCount, maximum: 6),
                failureCategory: Self.cleaned(response.failureCategory, maximumLength: 64),
                declaredCountComplete: response.declaredCountComplete == true
            )
        )
    }

    private static func providerPath(_ value: String?) -> String {
        switch value {
        case "apify_gemini", "apify_deterministic":
            value ?? "unknown"
        default:
            "unknown"
        }
    }

    private static func resolvedCandidates(
        from values: [SocialImportUnderstandingFunctionResponse.Hint.ResolvedPlace]?
    ) -> [PlaceCandidate] {
        var seen = Set<String>()
        return (values ?? []).prefix(3).compactMap { value in
            guard value.provider == "google_places",
                  let providerPlaceID = cleaned(value.providerPlaceID, maximumLength: 300),
                  seen.insert(providerPlaceID).inserted,
                  let name = cleaned(value.name, maximumLength: 200),
                  value.latitude.isFinite,
                  (-90...90).contains(value.latitude),
                  value.longitude.isFinite,
                  (-180...180).contains(value.longitude)
            else { return nil }
            let rawProviderType = cleaned(value.primaryType, maximumLength: 100)
                ?? value.types?.compactMap { cleaned($0, maximumLength: 100) }.first
            return PlaceCandidate(
                id: "google-places-\(providerPlaceID)",
                name: name,
                category: rawProviderType ?? WanderPlaceCategory.fallbackPlace,
                rawProviderType: rawProviderType,
                address: cleaned(value.formattedAddress, maximumLength: 500),
                locality: cleaned(value.locality, maximumLength: 160),
                region: cleaned(value.region, maximumLength: 160),
                country: cleaned(value.country, maximumLength: 160),
                latitude: value.latitude,
                longitude: value.longitude,
                sourceProvider: "google_places",
                sourceProviderPlaceID: providerPlaceID,
                confidence: 1
            )
        }
    }

    private static func clamped(_ value: Int?, maximum: Int) -> Int {
        max(0, min(maximum, value ?? 0))
    }

    private static func cleaned(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let withoutControls = value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let cleaned = withoutControls
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= maximumLength else { return nil }
        return cleaned
    }
}

@MainActor
final class RemoteDiscoverFilterParser: LLMFilterParser {
    private enum ParseError: Error {
        case semanticEmpty
    }

    private let repository: any DiscoverFilterParsingRepository
    private let fallback: any LLMFilterParser
    private(set) var parseSource: DiscoverParseSource = .remote

    init(
        repository: any DiscoverFilterParsingRepository,
        fallback: any LLMFilterParser = DeterministicFilterParser()
    ) {
        self.repository = repository
        self.fallback = fallback
    }

    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        do {
            let remoteFilters = try await repository.parseFilters(query: query, schema: schema)
            let filters = DiscoverSemanticNormalizer.normalized(remoteFilters, query: query)
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.hasRecognizedFacet else {
                throw ParseError.semanticEmpty
            }
            parseSource = .remote
            return filters
        } catch {
            let fallbackFilters = try await fallback.parse(query: query, schema: schema)
            let filters = DiscoverSemanticNormalizer.normalized(fallbackFilters, query: query)
            parseSource = .deterministicFallback
            return filters
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

enum PlacePhotoNetworkSession {
    static let memoryCapacity = 16 * 1_024 * 1_024
    static let diskCapacity = 96 * 1_024 * 1_024

    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "recme-place-photos"
        )
        return URLSession(configuration: configuration)
    }()
}

struct SupabasePlacePhotoRepository: PlacePhotoRepository {
    private static let maximumGalleryPlaceCount = 64
    private let rpc: (any RemoteProcedureCalling)?
    private let functions: RemoteFunctionCalling
    private let storage: (any RemoteStorageCalling)?
    private let photoSession: URLSession

    init(
        functions: RemoteFunctionCalling,
        photoSession: URLSession = PlacePhotoNetworkSession.shared
    ) {
        self.rpc = nil
        self.functions = functions
        self.storage = nil
        self.photoSession = photoSession
    }

    init(
        rpc: RemoteProcedureCalling,
        functions: RemoteFunctionCalling,
        storage: RemoteStorageCalling,
        photoSession: URLSession = PlacePhotoNetworkSession.shared
    ) {
        self.rpc = rpc
        self.functions = functions
        self.storage = storage
        self.photoSession = photoSession
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        if request.skipsGooglePlacesLookup {
            return try await visibleUserPhoto(for: request)
        }

        do {
            return try await functions.invoke(
                "place-photo",
                body: request
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let providerError = error
            guard request.requiresPhoto else {
                throw providerError
            }
            do {
                return try await visibleUserPhoto(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw providerError
            }
        }
    }

    func photos(for requests: [PlacePhotoRequest]) async throws -> [PlacePhotoBatchResult] {
        let uniqueRequests = Array(
            Dictionary(
                requests.map { ($0.canonicalPhotoCacheKey, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )
        guard !uniqueRequests.isEmpty else { return [] }

        var results: [PlacePhotoBatchResult] = []
        for chunkStart in stride(from: 0, to: uniqueRequests.count, by: 32) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + 32, uniqueRequests.count)
            let chunk = Array(uniqueRequests[chunkStart..<chunkEnd])
            do {
                let response: PlacePhotoBatchResponse = try await functions.invoke(
                    "place-photo",
                    body: PlacePhotoBatchRequest(requests: chunk)
                )
                results.append(contentsOf: response.results.compactMap { item in
                    guard chunk.indices.contains(item.index), let photo = item.photo else {
                        return nil
                    }
                    return PlacePhotoBatchResult(
                        canonicalPlaceKey: chunk[item.index].canonicalPhotoCacheKey,
                        photo: photo
                    )
                })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Rolling deploy compatibility: older Edge Functions accept only
                // one request. Keep correctness while the batch endpoint lands.
                for request in chunk {
                    try Task.checkCancellation()
                    do {
                        let photo = try await photo(for: request)
                        results.append(
                            PlacePhotoBatchResult(
                                canonicalPlaceKey: request.canonicalPhotoCacheKey,
                                photo: photo
                            )
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        continue
                    }
                }
            }
        }
        return results
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        if let eligibleUserIDs = request.eligibleUserIDs {
            return try await visibleUserPhoto(
                for: request,
                contributedByUserIDs: eligibleUserIDs
            )
        }

        guard let rpc,
              let placeID = request.placeID,
              UUID(uuidString: placeID) != nil
        else {
            throw WanderRemoteError.invalidResponse("Place has no shared user-photo fallback")
        }

        let rows: [FirstVisiblePlacePhotoRow] = try await rpc.call(
            "first_visible_place_photo",
            params: FirstVisiblePlacePhotoParams(inputPlaceID: placeID)
        )
        guard let row = rows.first else {
            throw WanderRemoteError.invalidResponse("Place has no visible user photo")
        }
        return row.photo
    }

    func visibleUserPhotos(for requests: [PlacePhotoRequest]) async throws -> [PlacePhotoBatchResult] {
        guard let rpc else {
            return try await visibleUserPhotosIndividually(for: requests)
        }

        let eligibleUserIDs = requests.first?.eligibleUserIDs?.sorted()
        guard requests.allSatisfy({ $0.eligibleUserIDs?.sorted() == eligibleUserIDs }) else {
            return try await visibleUserPhotosIndividually(for: requests)
        }

        let requestsByPlaceID = Dictionary(
            requests.compactMap { request -> (String, PlacePhotoRequest)? in
                guard let placeID = request.placeID, UUID(uuidString: placeID) != nil else {
                    return nil
                }
                return (placeID.lowercased(), request)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !requestsByPlaceID.isEmpty else { return [] }

        do {
            let rows: [FirstVisiblePlacePhotoBatchRow] = try await rpc.call(
                "first_visible_place_photos_by_users",
                params: FirstVisiblePlacePhotoBatchParams(
                    inputPlaceIDs: Array(requestsByPlaceID.keys),
                    inputUserIDs: eligibleUserIDs
                )
            )
            return rows.compactMap { row in
                guard let request = requestsByPlaceID[row.placeID.lowercased()] else {
                    return nil
                }
                return PlacePhotoBatchResult(
                    canonicalPlaceKey: request.canonicalPhotoCacheKey,
                    photo: row.photo
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Rolling migration compatibility. The list batcher still bounds
            // image downloads while the RPC reaches every environment.
            return try await visibleUserPhotosIndividually(for: requests)
        }
    }

    func visiblePhotoGalleryPage(
        placeIDs: [String],
        after cursor: PlacePhotoGalleryCursor?,
        limit: Int
    ) async throws -> PlacePhotoGalleryPage {
        guard let rpc else {
            throw WanderRemoteError.notConfigured
        }
        let canonicalPlaceIDs = Array(
            Set(placeIDs.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() })
        )
            .sorted()
            .prefix(Self.maximumGalleryPlaceCount)
            .map { $0 }
        guard !canonicalPlaceIDs.isEmpty else {
            throw WanderRemoteError.invalidResponse("Place photo gallery requires a canonical place id")
        }

        let pageSize = min(max(limit, 1), 100)
        let rows: [VisiblePlacePhotoGalleryRow] = try await rpc.call(
            "visible_place_photos_for_places",
            params: VisiblePlacePhotoGalleryParams(
                inputPlaceIDs: canonicalPlaceIDs,
                inputAfterCreatedAt: cursor?.createdAt,
                inputAfterSortOrder: cursor?.sortOrder,
                inputAfterPhotoID: cursor?.photoID,
                inputLimit: pageSize
            )
        )
        let items = rows.map(\.galleryItem)
        let nextCursor = rows.last.map {
            PlacePhotoGalleryCursor(
                createdAt: $0.createdAt,
                sortOrder: $0.sortOrder,
                photoID: $0.photoID
            )
        }
        return PlacePhotoGalleryPage(
            items: items,
            nextCursor: nextCursor,
            hasMore: rows.count == pageSize
        )
    }

    private func visibleUserPhoto(
        for request: PlacePhotoRequest,
        contributedByUserIDs userIDs: [String]
    ) async throws -> PlacePhoto {
        let eligibleUserIDs = Array(
            Set(userIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        )
            .filter { !$0.isEmpty }
            .sorted()
        guard let rpc,
              let placeID = request.placeID,
              UUID(uuidString: placeID) != nil,
              !eligibleUserIDs.isEmpty
        else {
            throw WanderRemoteError.invalidResponse("Place has no eligible list photo contributors")
        }

        let rows: [FirstVisiblePlacePhotoRow] = try await rpc.call(
            "first_visible_place_photo_by_users",
            params: FirstVisiblePlacePhotoByUsersParams(
                inputPlaceID: placeID,
                inputUserIDs: eligibleUserIDs
            )
        )
        guard let row = rows.first else {
            throw WanderRemoteError.invalidResponse("Place has no eligible list contributor photo")
        }
        return row.photo
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        try await imageData(for: photo, variant: .fullscreen)
    }

    func imageData(for photo: PlacePhoto, variant: PlacePhotoRenderVariant) async throws -> Data {
        if let storageBucket = photo.storageBucket,
           let storagePath = photo.storagePath,
           let storage {
            do {
                return try await storage.downloadImage(
                    bucket: storageBucket,
                    path: storagePath,
                    variant: variant
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard variant.maximumPixelDimension != nil else { throw error }
                return try await storage.downloadObject(bucket: storageBucket, path: storagePath)
            }
        }

        guard let photoURL = photo.photoURL else {
            throw WanderRemoteError.invalidResponse("Place photo has no readable source")
        }

        var request = URLRequest(url: photoURL)
        request.cachePolicy = .useProtocolCachePolicy
        let (data, response) = try await photoSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw WanderRemoteError.invalidResponse("Place photo download failed")
        }
        return data
    }

    private func visibleUserPhotosIndividually(
        for requests: [PlacePhotoRequest]
    ) async throws -> [PlacePhotoBatchResult] {
        var results: [PlacePhotoBatchResult] = []
        for request in requests {
            try Task.checkCancellation()
            do {
                let photo = try await visibleUserPhoto(for: request)
                results.append(
                    PlacePhotoBatchResult(
                        canonicalPlaceKey: request.canonicalPhotoCacheKey,
                        photo: photo
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return results
    }
}

private struct PlacePhotoBatchRequest: Encodable {
    let requests: [PlacePhotoRequest]
}

private struct PlacePhotoBatchResponse: Decodable {
    let results: [PlacePhotoBatchItem]
}

private struct PlacePhotoBatchItem: Decodable {
    let index: Int
    let photo: PlacePhoto?
}

private struct FirstVisiblePlacePhotoBatchParams: Encodable {
    let inputPlaceIDs: [String]
    let inputUserIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case inputPlaceIDs = "input_place_ids"
        case inputUserIDs = "input_user_ids"
    }
}

private struct FirstVisiblePlacePhotoBatchRow: Decodable {
    let placeID: String
    let photoID: String
    let storageBucket: String
    let storagePath: String
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case photoID = "photo_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case width
        case height
    }

    var photo: PlacePhoto {
        PlacePhoto(
            provider: "visit_photo",
            providerPlaceID: photoID,
            photoURLString: "",
            width: width,
            height: height,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: storageBucket,
            storagePath: storagePath,
            localAssetRef: nil
        )
    }
}

private struct FirstVisiblePlacePhotoParams: Encodable {
    let inputPlaceID: String

    enum CodingKeys: String, CodingKey {
        case inputPlaceID = "input_place_id"
    }
}

private struct FirstVisiblePlacePhotoByUsersParams: Encodable {
    let inputPlaceID: String
    let inputUserIDs: [String]

    enum CodingKeys: String, CodingKey {
        case inputPlaceID = "input_place_id"
        case inputUserIDs = "input_user_ids"
    }
}

private struct VisiblePlacePhotoGalleryParams: Encodable {
    let inputPlaceIDs: [String]
    let inputAfterCreatedAt: Date?
    let inputAfterSortOrder: Int?
    let inputAfterPhotoID: String?
    let inputLimit: Int

    enum CodingKeys: String, CodingKey {
        case inputPlaceIDs = "input_place_ids"
        case inputAfterCreatedAt = "input_after_created_at"
        case inputAfterSortOrder = "input_after_sort_order"
        case inputAfterPhotoID = "input_after_photo_id"
        case inputLimit = "input_limit"
    }
}

private struct VisiblePlacePhotoGalleryRow: Decodable {
    let photoID: String
    let storageBucket: String
    let storagePath: String
    let width: Int?
    let height: Int?
    let capturedAt: Date
    let createdAt: Date
    let sortOrder: Int
    let contributorUserID: String
    let contributorDisplayName: String
    let contributorHandle: String
    let contributorAvatarURLString: String?
    let statusRaw: String

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case width
        case height
        case capturedAt = "captured_at"
        case createdAt = "created_at"
        case sortOrder = "sort_order"
        case contributorUserID = "contributor_user_id"
        case contributorDisplayName = "contributor_display_name"
        case contributorHandle = "contributor_handle"
        case contributorAvatarURLString = "contributor_avatar_url"
        case statusRaw = "status"
    }

    var galleryItem: PlacePhotoGalleryItem {
        PlacePhotoGalleryItem(
            photo: PlacePhoto(
                provider: "visit_photo",
                providerPlaceID: photoID,
                photoURLString: "",
                width: width,
                height: height,
                authorName: nil,
                authorProfileURLString: nil,
                authorAvatarURLString: nil,
                sourcePhotoURLString: nil,
                flagContentURLString: nil,
                storageBucket: storageBucket,
                storagePath: storagePath,
                localAssetRef: nil
            ),
            contributor: PlacePhotoContributor(
                userID: contributorUserID,
                displayName: contributorDisplayName,
                handle: contributorHandle,
                avatarURLString: contributorAvatarURLString
            ),
            capturedAt: capturedAt,
            status: PlaceStatus(rawValue: statusRaw)
        )
    }
}

private struct FirstVisiblePlacePhotoRow: Decodable {
    let photoID: String
    let storageBucket: String
    let storagePath: String
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case width
        case height
    }

    var photo: PlacePhoto {
        PlacePhoto(
            provider: "visit_photo",
            providerPlaceID: photoID,
            photoURLString: "",
            width: width,
            height: height,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: storageBucket,
            storagePath: storagePath,
            localAssetRef: nil
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

    func reconcileClientNotificationIntents(
        source: String,
        intents: [ClientNotificationIntent]
    ) async throws -> NotificationIntentReconciliationResult {
        let response: NotificationIntentReconciliationResponse = try await rpc.call(
            "reconcile_client_notification_intents",
            params: ReconcileClientNotificationIntentsParams(
                inputSource: source,
                inputIntents: intents.map(ClientNotificationIntentDTO.init)
            )
        )
        return NotificationIntentReconciliationResult(
            queuedCount: response.queuedCount,
            createdCount: response.createdCount ?? response.queuedCount
        )
    }

    func syncCalendarReservations(
        _ reservations: [CalendarReservationSyncItem],
        windowStart: Date,
        windowEnd: Date
    ) async throws -> CalendarReservationSyncResult {
        let response: CalendarReservationSyncResponse = try await rpc.call(
            "sync_calendar_reservations",
            params: SyncCalendarReservationsParams(
                inputReservations: reservations,
                inputWindowStart: windowStart,
                inputWindowEnd: windowEnd
            )
        )
        return CalendarReservationSyncResult(
            syncedCount: response.syncedCount,
            queuedCount: response.queuedCount,
            cancelledCount: response.cancelledCount
        )
    }

    func calendarReservation(id: String) async throws -> CalendarReservationPrompt? {
        let response: CalendarReservationPromptResponse? = try await rpc.call(
            "get_calendar_reservation",
            params: CalendarReservationIDParams(inputReservationID: id)
        )
        return response?.prompt
    }

    func completeCalendarReservation(id: String) async throws -> Bool {
        try await rpc.call(
            "complete_calendar_reservation",
            params: CalendarReservationIDParams(inputReservationID: id)
        )
    }
}

private struct SearchProfilesParams: Encodable {
    let query: String
}

private struct EmptyParams: Encodable {}

private struct UpdateOwnProfileParams: Encodable {
    let displayName: String?
    let handle: String?
    let bio: String?
    let homeArea: String?
    let defaultVisibility: String?
    let isPrivateProfile: Bool?
    let markOnboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "input_display_name"
        case handle = "input_handle"
        case bio = "input_bio"
        case homeArea = "input_home_area"
        case defaultVisibility = "input_default_visibility"
        case isPrivateProfile = "input_is_private_profile"
        case markOnboardingComplete = "input_mark_onboarding_complete"
    }
}

private struct ProfileHandleAvailableParams: Encodable {
    let handle: String

    enum CodingKeys: String, CodingKey {
        case handle = "input_handle"
    }
}

private struct NotificationPreferencesResponse: Decodable {
    let pushEnabled: Bool
    let socialGraphEnabled: Bool
    let sharedListsEnabled: Bool
    let sharedVisitsEnabled: Bool?
    let recommendationsEnabled: Bool
    let captureEnabled: Bool
    let discoveryDigestEnabled: Bool
    let followedActivityEnabled: Bool
    let engagementEnabled: Bool?
    let wannaGoRemindersEnabled: Bool?
    let reservationRemindersEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case socialGraphEnabled = "social_graph_enabled"
        case sharedListsEnabled = "shared_lists_enabled"
        case sharedVisitsEnabled = "shared_visits_enabled"
        case recommendationsEnabled = "recommendations_enabled"
        case captureEnabled = "capture_enabled"
        case discoveryDigestEnabled = "discovery_digest_enabled"
        case followedActivityEnabled = "followed_activity_enabled"
        case engagementEnabled = "engagement_enabled"
        case wannaGoRemindersEnabled = "wanna_go_reminders_enabled"
        case reservationRemindersEnabled = "reservation_reminders_enabled"
    }

    var preferences: NotificationPreferences {
        NotificationPreferences(
            pushEnabled: pushEnabled,
            socialGraphEnabled: socialGraphEnabled,
            sharedListsEnabled: sharedListsEnabled,
            sharedVisitsEnabled: sharedVisitsEnabled ?? true,
            recommendationsEnabled: recommendationsEnabled,
            captureEnabled: captureEnabled,
            discoveryDigestEnabled: discoveryDigestEnabled,
            followedActivityEnabled: followedActivityEnabled,
            engagementEnabled: engagementEnabled ?? false,
            wannaGoRemindersEnabled: wannaGoRemindersEnabled ?? false,
            reservationRemindersEnabled: reservationRemindersEnabled ?? false
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
    let sharedVisitsEnabled: Bool?
    let recommendationsEnabled: Bool?
    let captureEnabled: Bool?
    let discoveryDigestEnabled: Bool?
    let followedActivityEnabled: Bool?
    let engagementEnabled: Bool?
    let wannaGoRemindersEnabled: Bool?
    let reservationRemindersEnabled: Bool?

    init(update: NotificationPreferencesUpdate) {
        self.pushEnabled = update.pushEnabled
        self.socialGraphEnabled = update.socialGraphEnabled
        self.sharedListsEnabled = update.sharedListsEnabled
        self.sharedVisitsEnabled = update.sharedVisitsEnabled
        self.recommendationsEnabled = update.recommendationsEnabled
        self.captureEnabled = update.captureEnabled
        self.discoveryDigestEnabled = update.discoveryDigestEnabled
        self.followedActivityEnabled = update.followedActivityEnabled
        self.engagementEnabled = update.engagementEnabled
        self.wannaGoRemindersEnabled = update.wannaGoRemindersEnabled
        self.reservationRemindersEnabled = update.reservationRemindersEnabled
    }

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case socialGraphEnabled = "social_graph_enabled"
        case sharedListsEnabled = "shared_lists_enabled"
        case sharedVisitsEnabled = "shared_visits_enabled"
        case recommendationsEnabled = "recommendations_enabled"
        case captureEnabled = "capture_enabled"
        case discoveryDigestEnabled = "discovery_digest_enabled"
        case followedActivityEnabled = "followed_activity_enabled"
        case engagementEnabled = "engagement_enabled"
        case wannaGoRemindersEnabled = "wanna_go_reminders_enabled"
        case reservationRemindersEnabled = "reservation_reminders_enabled"
    }
}

private struct ReconcileClientNotificationIntentsParams: Encodable {
    let inputSource: String
    let inputIntents: [ClientNotificationIntentDTO]

    enum CodingKeys: String, CodingKey {
        case inputSource = "input_source"
        case inputIntents = "input_intents"
    }
}

private struct ClientNotificationIntentDTO: Encodable {
    let intentKey: String
    let title: String
    let body: String
    let deeplinkURL: String?
    let data: [String: JSONValue]
    let earliestAt: Date
    let latestAt: Date
    let priority: Int
    let conflictGroup: String?
    let recipientTimezone: String?

    init(_ intent: ClientNotificationIntent) {
        intentKey = intent.intentKey
        title = intent.title
        body = intent.body
        deeplinkURL = intent.deeplinkURL
        data = intent.data
        earliestAt = intent.earliestAt
        latestAt = intent.latestAt
        priority = intent.priority
        conflictGroup = intent.conflictGroup
        recipientTimezone = intent.recipientTimezone
    }

    enum CodingKeys: String, CodingKey {
        case intentKey = "intent_key"
        case title
        case body
        case deeplinkURL = "deeplink_url"
        case data
        case earliestAt = "earliest_at"
        case latestAt = "latest_at"
        case priority
        case conflictGroup = "conflict_group"
        case recipientTimezone = "recipient_timezone"
    }
}

private struct NotificationIntentReconciliationResponse: Decodable {
    let queuedCount: Int
    let createdCount: Int?

    enum CodingKeys: String, CodingKey {
        case queuedCount = "queued_count"
        case createdCount = "created_count"
    }
}

private struct SyncCalendarReservationsParams: Encodable {
    let inputReservations: [CalendarReservationSyncItem]
    let inputWindowStart: Date
    let inputWindowEnd: Date

    enum CodingKeys: String, CodingKey {
        case inputReservations = "input_reservations"
        case inputWindowStart = "input_window_start"
        case inputWindowEnd = "input_window_end"
    }
}

private struct CalendarReservationSyncResponse: Decodable {
    let syncedCount: Int
    let queuedCount: Int
    let cancelledCount: Int

    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case queuedCount = "queued_count"
        case cancelledCount = "cancelled_count"
    }
}

private struct CalendarReservationIDParams: Encodable {
    let inputReservationID: String

    enum CodingKeys: String, CodingKey {
        case inputReservationID = "input_reservation_id"
    }
}

private struct CalendarReservationPromptResponse: Decodable {
    let id: String
    let canonicalName: String
    let locality: String?
    let sourceProvider: String
    let sourceProviderPlaceID: String
    let startAt: Date
    let endAt: Date
    let eventTimezone: String
    let resolvedPlaceID: String?
    let isCompleted: Bool
    let isCancelled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case locality
        case sourceProvider = "source_provider"
        case sourceProviderPlaceID = "source_provider_place_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case eventTimezone = "event_timezone"
        case resolvedPlaceID = "resolved_place_id"
        case isCompleted = "is_completed"
        case isCancelled = "is_cancelled"
    }

    var prompt: CalendarReservationPrompt {
        CalendarReservationPrompt(
            id: id,
            canonicalName: canonicalName,
            locality: locality,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            startAt: startAt,
            endAt: endAt,
            eventTimezone: eventTimezone,
            resolvedPlaceID: resolvedPlaceID,
            isCompleted: isCompleted,
            isCancelled: isCancelled
        )
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

private struct PlaceListInviteTokenParams: Encodable {
    let inputToken: String

    enum CodingKeys: String, CodingKey {
        case inputToken = "input_token"
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

private struct ProfileDetailParams: Encodable {
    let profileID: String

    enum CodingKeys: String, CodingKey {
        case profileID = "input_profile_id"
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

private struct FeaturedPlacesParams: Encodable {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double

    enum CodingKeys: String, CodingKey {
        case minLat = "min_lat"
        case minLng = "min_lng"
        case maxLat = "max_lat"
        case maxLng = "max_lng"
    }
}

private struct SocialSurfaceSnapshotParams: Encodable {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double

    init(viewport: MapViewport) {
        minLat = viewport.minLatitude
        minLng = viewport.minLongitude
        maxLat = viewport.maxLatitude
        maxLng = viewport.maxLongitude
    }

    enum CodingKeys: String, CodingKey {
        case minLat = "min_lat"
        case minLng = "min_lng"
        case maxLat = "max_lat"
        case maxLng = "max_lng"
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

private struct FollowedFeedParams: Encodable {
    let before: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case before = "input_before"
        case limit = "input_limit"
    }
}

private struct ActivityEngagementSummariesParams: Encodable {
    let activityIDs: [String]

    enum CodingKeys: String, CodingKey {
        case activityIDs = "input_activity_ids"
    }
}

private struct ActivityDetailParams: Encodable {
    let activityID: String

    enum CodingKeys: String, CodingKey {
        case activityID = "input_activity_id"
    }
}

private struct PlaceActivityEngagementSummariesParams: Encodable {
    let userPlaceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case userPlaceIDs = "input_user_place_ids"
    }
}

private struct SetActivityLikeParams: Encodable {
    let activityID: String
    let isLiked: Bool

    enum CodingKeys: String, CodingKey {
        case activityID = "input_activity_id"
        case isLiked = "input_is_liked"
    }
}

private struct ActivityCommentsParams: Encodable {
    let activityID: String
    let before: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case activityID = "input_activity_id"
        case before = "input_before"
        case limit = "input_limit"
    }
}

private struct AddActivityCommentParams: Encodable {
    let activityID: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case activityID = "input_activity_id"
        case body = "input_body"
    }
}

private struct DeleteActivityCommentParams: Encodable {
    let commentID: String

    enum CodingKeys: String, CodingKey {
        case commentID = "input_comment_id"
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

private struct SaveOwnCheckInParams: Encodable {
    let inputPlace: SaveOwnPlacePlaceParams
    let inputUserPlace: SaveOwnPlaceUserPlaceParams
    let inputAttributes: [SaveOwnPlaceAttributeParams]
    let inputVisit: SaveOwnCheckInVisitParams
    let inputHistoricalWant: SaveOwnCheckInHistoricalWantParams?

    init(draft: CheckInSaveDraft) throws {
        inputPlace = SaveOwnPlacePlaceParams(place: draft.userPlace.place)
        inputUserPlace = SaveOwnPlaceUserPlaceParams(draft: draft.userPlace)
        inputAttributes = try draft.userPlace.attributes.map(SaveOwnPlaceAttributeParams.init)
        inputVisit = try SaveOwnCheckInVisitParams(draft: draft.visit)
        inputHistoricalWant = try draft.historicalWant.map(SaveOwnCheckInHistoricalWantParams.init)
    }

    enum CodingKeys: String, CodingKey {
        case inputPlace = "input_place"
        case inputUserPlace = "input_user_place"
        case inputAttributes = "input_attributes"
        case inputVisit = "input_visit"
        case inputHistoricalWant = "input_historical_want"
    }
}

private struct SaveOwnCheckInVisitParams: Encodable {
    let id: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswers: JSONValue

    init(draft: PlaceVisitDraft) throws {
        guard let id = draft.id, UUID(uuidString: id) != nil else {
            throw WanderRemoteError.invalidResponse("Explicit check-ins require a stable UUID")
        }
        self.id = id
        visitedAt = draft.visitedAt
        note = draft.note
        ratingScore = PlaceRating.normalized(draft.ratingScore)
        attributeAnswers = try Self.decodeJSON(draft.attributeAnswersJSON)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case attributeAnswers = "attribute_answers"
    }

    private static func decodeJSON(_ value: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))
    }
}

private struct SaveOwnCheckInHistoricalWantParams: Encodable {
    let note: String?
    let attributeAnswers: JSONValue
    let tags: [String]
    let wantedAt: Date

    init(draft: HistoricalWantSnapshotDraft) throws {
        note = draft.note
        attributeAnswers = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(draft.attributeAnswersJSON.utf8)
        )
        tags = draft.tags
        wantedAt = draft.wantedAt
    }

    enum CodingKeys: String, CodingKey {
        case note
        case attributeAnswers = "attribute_answers"
        case tags
        case wantedAt = "wanted_at"
    }
}

private struct SaveOwnCheckInResponse: Decodable {
    let userPlaceID: String
    let placeID: String
    let visitID: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let tags: [String]
    let backfilledFromUserPlace: Bool

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
        case placeID = "place_id"
        case visitID = "visit_id"
        case visitedAt = "visited_at"
        case note
        case ratingScore = "rating_score"
        case tags
        case backfilledFromUserPlace = "backfilled_from_user_place"
    }
}

private struct DeleteOwnCheckInParams: Encodable {
    let inputVisitID: String

    enum CodingKeys: String, CodingKey {
        case inputVisitID = "input_visit_id"
    }
}

private struct DeleteOwnCheckInResponse: Decodable {
    let visitID: String
    let userPlaceID: String?
    let transition: String

    enum CodingKeys: String, CodingKey {
        case visitID = "visit_id"
        case userPlaceID = "user_place_id"
        case transition
    }
}

private struct DeleteOwnUserPlaceParams: Encodable {
    let inputUserPlaceID: String

    enum CodingKeys: String, CodingKey {
        case inputUserPlaceID = "input_user_place_id"
    }
}

private struct DeleteOwnUserPlaceResponse: Decodable {
    let userPlaceID: String
    let transition: String

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
        case transition
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
    let plannedDate: String?
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
        self.plannedDate = draft.plannedDate.map { WannaGoDate.storageString(from: $0) }
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
        case plannedDate = "planned_date"
        case sourceType = "source_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(visibility, forKey: .visibility)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(ratingSignal, forKey: .ratingSignal)
        try container.encodeIfPresent(ratingScore, forKey: .ratingScore)
        try container.encodeIfPresent(categoryOverride, forKey: .categoryOverride)
        try container.encodeIfPresent(subcategoryOverride, forKey: .subcategoryOverride)
        try container.encodeIfPresent(categoryOverrideSource, forKey: .categoryOverrideSource)
        try container.encodeIfPresent(categoryOverrideConfidence, forKey: .categoryOverrideConfidence)
        try container.encode(nearbyConfirmed, forKey: .nearbyConfirmed)
        try container.encode(plannedDate, forKey: .plannedDate)
        try container.encode(sourceType, forKey: .sourceType)
    }
}

private struct RemoteOwnWannaGoPlanDTO: Decodable {
    let userPlaceID: String
    let placeID: String
    let plannedDate: String

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
        case placeID = "place_id"
        case plannedDate = "planned_date"
    }

    func plan() throws -> OwnWannaGoPlan {
        guard let plannedDate = WannaGoDate.date(fromStorageString: plannedDate) else {
            throw WanderRemoteError.invalidResponse("Invalid Wanna planned date: \(plannedDate)")
        }
        return OwnWannaGoPlan(
            userPlaceID: userPlaceID,
            placeID: placeID,
            plannedDate: plannedDate
        )
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
