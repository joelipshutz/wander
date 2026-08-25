import Foundation

struct RemoteProfileShellDTO: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let isPrivateProfile: Bool?
    let createdAt: Date?
    let relationship: String?

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case homeArea = "home_area"
        case isPrivateProfile = "is_private_profile"
        case createdAt = "created_at"
        case relationship
    }

    func profileShell(fallbackRelationship: ViewerRelationship = .nonFollower) -> ProfileShell {
        ProfileShell(
            id: id,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            homeArea: homeArea,
            isPrivateProfile: isPrivateProfile,
            createdAt: createdAt,
            relationship: relationship.flatMap(ViewerRelationship.init(rawValue:)) ?? fallbackRelationship
        )
    }
}

struct RemoteDiscoverPeopleRecommendationDTO: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let createdAt: Date?
    let relationship: String?
    let reasonKind: String
    let sharedFollowCount: Int
    let resultRank: Int

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case homeArea = "home_area"
        case createdAt = "created_at"
        case relationship
        case reasonKind = "reason_kind"
        case sharedFollowCount = "shared_follow_count"
        case resultRank = "result_rank"
    }

    func recommendation() -> DiscoverPeopleRecommendation {
        let profile = ProfileShell(
            id: id,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            homeArea: homeArea,
            isPrivateProfile: false,
            createdAt: createdAt,
            relationship: relationship.flatMap(ViewerRelationship.init(rawValue:)) ?? .nonFollower
        )
        let reason: DiscoverPeopleRecommendationReason = switch reasonKind {
        case "follows_you": .followsYou
        case "shared_follows": .sharedFollows(max(sharedFollowCount, 1))
        default: .suggested
        }
        return DiscoverPeopleRecommendation(profile: profile, reason: reason, rank: resultRank)
    }
}

struct RemoteCurrentProfileDTO: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let defaultVisibility: String
    let isPrivateProfile: Bool
    let onboardingCompletedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case homeArea = "home_area"
        case defaultVisibility = "default_visibility"
        case isPrivateProfile = "is_private_profile"
        case onboardingCompletedAt = "onboarding_completed_at"
        case createdAt = "created_at"
    }

    func localProfile() -> LocalProfile {
        LocalProfile(
            localID: "local_profile_current",
            serverID: id,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            homeArea: homeArea,
            onboardingCompletedAt: onboardingCompletedAt,
            isPrivateProfile: isPrivateProfile,
            defaultVisibility: PlaceVisibility(rawValue: defaultVisibility) ?? .followers,
            syncState: .synced,
            createdAt: createdAt
        )
    }
}

struct RemoteVisiblePlaceDTO: Codable, Equatable {
    private enum ViewerTaxonomyKey {
        static let primaryCategory = "__viewer_taxonomy_primary_category"
        static let subcategory = "__viewer_taxonomy_subcategory"
        static let foodType = "__viewer_taxonomy_food_type"
        static let all = Set([primaryCategory, subcategory, foodType])
    }

    let userPlaceID: String
    let placeID: String
    let ownerUserID: String
    let ownerHandle: String
    let ownerDisplayName: String
    let ownerAvatarURL: String?
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
    let timeZoneIdentifier: String?
    let latitude: Double
    let longitude: Double
    let status: String
    let visibility: String
    let note: String?
    let visitedAt: Date?
    let savedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let ratingSignal: String?
    let ratingScore: Double?
    let recommendedScore: Double?
    let recommendedCount: Int?
    let communitySaveCount: Int?
    let categoryOverride: String?
    let subcategoryOverride: String?
    let categoryOverrideSource: String?
    let categoryOverrideConfidence: Double?
    let sourceType: String
    let attributes: [RemotePlaceAttributeDTO]

    enum CodingKeys: String, CodingKey {
        case userPlaceID = "user_place_id"
        case placeID = "place_id"
        case ownerUserID = "owner_user_id"
        case ownerHandle = "owner_handle"
        case ownerDisplayName = "owner_display_name"
        case ownerAvatarURL = "owner_avatar_url"
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
        case timeZoneIdentifier = "time_zone_identifier"
        case latitude
        case longitude
        case status
        case visibility
        case note
        case visitedAt = "visited_at"
        case savedAt = "saved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ratingSignal = "rating_signal"
        case ratingScore = "rating_score"
        case recommendedScore = "recommended_score"
        case recommendedCount = "recommended_count"
        case communitySaveCount = "community_save_count"
        case categoryOverride = "category_override"
        case subcategoryOverride = "subcategory_override"
        case categoryOverrideSource = "category_override_source"
        case categoryOverrideConfidence = "category_override_confidence"
        case sourceType = "source_type"
        case attributes
    }

    func visiblePlace() throws -> VisiblePlace {
        guard let parsedStatus = PlaceStatus(rawValue: status) else {
            throw WanderRemoteError.invalidResponse("Unknown place status: \(status)")
        }
        guard let parsedVisibility = PlaceVisibility(rawValue: visibility) else {
            throw WanderRemoteError.invalidResponse("Unknown place visibility: \(visibility)")
        }

        var projectedTaxonomy: [String: String] = [:]
        for attribute in attributes {
            guard ViewerTaxonomyKey.all.contains(attribute.questionKey),
                  case .string(let value) = attribute.value
            else { continue }

            // Viewer projections are appended after persisted attributes by the RPCs.
            // Older builds could write a projected row back, so prefer the final
            // server-derived value instead of trapping on a duplicate dictionary key.
            projectedTaxonomy[attribute.questionKey] = value
        }
        let visibleAttributes = attributes.filter {
            !ViewerTaxonomyKey.all.contains($0.questionKey)
        }
        let isCommunityAggregate = ownerUserID == FeaturedCommunityPlaceSignal.ownerID
        let owner = LocalProfile(
            localID: ownerUserID,
            serverID: isCommunityAggregate ? nil : ownerUserID,
            handle: ownerHandle,
            displayName: ownerDisplayName,
            avatarURL: ownerAvatarURL,
            syncState: .synced
        )
        let place = LocalPlace(
            localID: placeID,
            serverID: placeID,
            canonicalName: canonicalName,
            category: category,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: categorySource ?? PlaceCategorySource.legacy.rawValue,
            categoryConfidence: categoryConfidence,
            rawProviderType: rawProviderType ?? category,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: userPlaceID,
            serverID: isCommunityAggregate ? nil : userPlaceID,
            userID: ownerUserID,
            placeID: placeID,
            status: parsedStatus,
            visibility: parsedVisibility,
            note: note,
            ratingSignal: ratingSignal,
            ratingScore: ratingScore,
            recommendedScore: recommendedScore,
            recommendedCount: recommendedCount ?? 0,
            categoryOverride: categoryOverride,
            subcategoryOverride: subcategoryOverride,
            categoryOverrideSource: categoryOverrideSource,
            categoryOverrideConfidence: categoryOverrideConfidence,
            viewerPrimaryCategory: projectedTaxonomy[ViewerTaxonomyKey.primaryCategory],
            viewerSubcategory: projectedTaxonomy[ViewerTaxonomyKey.subcategory],
            viewerFoodType: projectedTaxonomy[ViewerTaxonomyKey.foodType],
            visitedAt: visitedAt,
            savedAt: savedAt,
            sourceType: sourceType,
            syncState: .synced,
            localUpdatedAt: updatedAt,
            serverUpdatedAt: updatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        return VisiblePlace(
            id: userPlaceID,
            place: place,
            userPlace: userPlace,
            owner: owner,
            attributes: visibleAttributes.map { $0.localAttribute(userPlaceID: userPlaceID) },
            communitySaveCount: communitySaveCount ?? 0
        )
    }
}

struct RemotePlaceAttributeDTO: Codable, Equatable {
    let questionDefinitionID: String?
    let questionKey: String
    let valueType: String
    let value: JSONValue
    let prompt: String?
    let options: [JSONValue]
    let isSystem: Bool

    enum CodingKeys: String, CodingKey {
        case questionDefinitionID = "question_definition_id"
        case questionKey = "question_key"
        case valueType = "value_type"
        case value
        case prompt
        case options
        case isSystem = "is_system"
    }

    func localAttribute(userPlaceID: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "remote_attr_\(userPlaceID)_\(questionKey)",
            userPlaceID: userPlaceID,
            questionKey: questionKey,
            valueType: valueType,
            valueJSON: value.encodedJSONString,
            syncState: .synced
        )
    }
}

struct RemoteFeedMediaDTO: Codable, Equatable {
    let id: String
    let urlString: String?
    let storageBucket: String?
    let storagePath: String?
    let accessibilityLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case urlString = "url"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case accessibilityLabel = "accessibility_label"
    }

    @MainActor
    func preview(storage: (any RemoteStorageCalling)?) async -> FeedMediaPreview {
        var resolvedURLString = urlString
        if resolvedURLString == nil,
           let storage,
           let storageBucket,
           let storagePath {
            if let signedURL = try? await storage.signedObjectURL(
                bucket: storageBucket,
                path: storagePath,
                expiresIn: 3_600
            ) {
                resolvedURLString = signedURL.absoluteString
            }
        }
        return FeedMediaPreview(
            id: id,
            urlString: resolvedURLString,
            accessibilityLabel: accessibilityLabel
        )
    }
}

struct RemoteActivityMediaDTO: Codable, Equatable {
    let activityID: String
    let media: [RemoteFeedMediaDTO]

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case media
    }
}

struct RemoteFeedListDTO: Codable, Equatable {
    let id: String
    let ownerUserID: String
    let name: String
    let description: String
    let visibility: String
    let itemCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name
        case description
        case visibility
        case itemCount = "item_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func localList() -> LocalPlaceList {
        LocalPlaceList(
            localID: "remote_feed_list_\(id)",
            serverID: id,
            ownerUserID: ownerUserID,
            name: name,
            description: description,
            visibility: PlaceListVisibility(rawValue: visibility) ?? .followers,
            syncState: .synced,
            cachedItemCount: itemCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct RemoteFeedActivityDTO: Codable, Equatable {
    let id: String
    let eventType: String
    let occurredAt: Date
    let actor: RemoteProfileShellDTO
    let place: RemoteVisiblePlaceDTO?
    let list: RemoteFeedListDTO?
    let note: String?
    let rating: Double?
    let media: [RemoteFeedMediaDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case actor
        case place
        case list
        case note
        case rating
        case media
    }

    @MainActor
    func activity(
        storage: (any RemoteStorageCalling)? = nil,
        mediaOverride: [RemoteFeedMediaDTO]? = nil
    ) async throws -> FeedActivity {
        guard let kind = FeedActivityKind(rawValue: eventType) else {
            throw WanderRemoteError.invalidResponse("Unknown Feed event type: \(eventType)")
        }
        var renderedMedia: [FeedMediaPreview] = []
        let sourceMedia = mediaOverride ?? media
        renderedMedia.reserveCapacity(sourceMedia.count)
        for item in sourceMedia {
            renderedMedia.append(await item.preview(storage: storage))
        }
        return FeedActivity(
            id: id,
            kind: kind,
            actor: actor.profileShell(fallbackRelationship: .follower),
            place: try place?.visiblePlace(),
            list: list?.localList(),
            occurredAt: occurredAt,
            note: note,
            rating: rating,
            media: renderedMedia
        )
    }
}

struct RemoteFeedFeaturedPlaceDTO: Codable, Equatable {
    let place: RemoteVisiblePlaceDTO
    let reason: String

    func featuredPlace(actor activityActor: ProfileShell? = nil) throws -> FeedFeaturedPlace {
        let visiblePlace = try place.visiblePlace()
        let actor = ProfileShell(
            id: activityActor?.id ?? visiblePlace.owner.id,
            handle: activityActor?.handle ?? visiblePlace.owner.handle,
            displayName: activityActor?.displayName ?? visiblePlace.owner.displayName,
            avatarURL: activityActor?.avatarURL ?? visiblePlace.owner.avatarURL,
            bio: activityActor?.bio ?? visiblePlace.owner.bio,
            homeArea: activityActor?.homeArea ?? visiblePlace.owner.homeArea,
            isPrivateProfile: activityActor?.isPrivateProfile ?? visiblePlace.owner.isPrivateProfile,
            createdAt: activityActor?.createdAt ?? visiblePlace.owner.createdAt,
            relationship: activityActor?.relationship ?? .follower
        )
        return FeedFeaturedPlace(visiblePlace: visiblePlace, actor: actor, reason: reason)
    }
}

struct RemoteFollowedFeedPageDTO: Codable, Equatable {
    let activity: [RemoteFeedActivityDTO]
    let featuredPlaces: [RemoteFeedFeaturedPlaceDTO]
    let nextCursor: String?
    let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case activity
        case featuredPlaces = "featured_places"
        case nextCursor = "next_cursor"
        case fetchedAt = "fetched_at"
    }

    @MainActor
    func followedFeedPage() async throws -> FollowedFeedPage {
        var renderedActivity: [FeedActivity] = []
        renderedActivity.reserveCapacity(activity.count)
        for item in activity {
            renderedActivity.append(try await item.activity())
        }
        let actorsByID = Dictionary(
            renderedActivity.map { ($0.actor.id, $0.actor) },
            uniquingKeysWith: { current, _ in current }
        )

        return FollowedFeedPage(
            activity: renderedActivity,
            featuredPlaces: try featuredPlaces.map {
                try $0.featuredPlace(actor: actorsByID[$0.place.ownerUserID])
            },
            nextCursor: nextCursor,
            fetchedAt: fetchedAt
        )
    }
}

struct RemoteActivityEngagementSummaryDTO: Codable, Equatable {
    let activityID: String
    let likeCount: Int
    let commentCount: Int
    let viewerHasLiked: Bool

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case viewerHasLiked = "viewer_has_liked"
    }

    var summary: ActivityEngagementSummary {
        ActivityEngagementSummary(
            activityID: activityID,
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked
        )
    }
}

struct RemotePlaceActivityEngagementDTO: Codable, Equatable {
    let activityID: String
    let userPlaceID: String
    let visitID: String?
    let eventType: String
    let occurredAt: Date
    let likeCount: Int
    let commentCount: Int
    let viewerHasLiked: Bool

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case userPlaceID = "user_place_id"
        case visitID = "visit_id"
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case viewerHasLiked = "viewer_has_liked"
    }

    func match() throws -> PlaceActivityEngagementMatch {
        guard let kind = FeedActivityKind(rawValue: eventType) else {
            throw WanderRemoteError.invalidResponse("Unknown activity engagement event type: \(eventType)")
        }
        return PlaceActivityEngagementMatch(
            activityID: activityID,
            userPlaceID: userPlaceID,
            visitID: visitID,
            kind: kind,
            occurredAt: occurredAt,
            engagement: ActivityEngagementSummary(
                activityID: activityID,
                likeCount: likeCount,
                commentCount: commentCount,
                viewerHasLiked: viewerHasLiked
            )
        )
    }
}

struct RemoteActivityCommentDTO: Codable, Equatable {
    let id: String
    let activityID: String
    let author: RemoteProfileShellDTO
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activity_id"
        case author
        case body
        case createdAt = "created_at"
    }

    var comment: ActivityComment {
        ActivityComment(
            id: id,
            activityID: activityID,
            author: author.profileShell(fallbackRelationship: .nonFollower),
            body: body,
            createdAt: createdAt
        )
    }
}

struct RemoteActivityCommentsPageDTO: Codable, Equatable {
    let comments: [RemoteActivityCommentDTO]
    let nextCursor: String?
    let engagement: RemoteActivityEngagementSummaryDTO

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
        case engagement
    }

    var page: ActivityCommentsPage {
        ActivityCommentsPage(
            comments: comments.map(\.comment),
            nextCursor: nextCursor,
            engagement: engagement.summary
        )
    }
}

struct RemoteActivityCommentPostDTO: Codable, Equatable {
    let comment: RemoteActivityCommentDTO
    let engagement: RemoteActivityEngagementSummaryDTO

    var result: ActivityCommentPostResult {
        ActivityCommentPostResult(
            comment: comment.comment,
            engagement: engagement.summary
        )
    }
}

struct RemotePlaceListCollaboratorDTO: Codable, Equatable {
    let userID: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case role
    }

    var record: PlaceListCollaboratorRecord {
        PlaceListCollaboratorRecord(
            userID: userID,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            role: role.flatMap(PlaceListRole.init(rawValue:)) ?? .collaborator
        )
    }
}

struct RemotePlaceListRowDTO: Codable, Equatable {
    let id: String
    let ownerUserID: String
    let ownerHandle: String?
    let ownerDisplayName: String?
    let ownerAvatarURL: String?
    let name: String
    let description: String
    let visibility: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case ownerHandle = "owner_handle"
        case ownerDisplayName = "owner_display_name"
        case ownerAvatarURL = "owner_avatar_url"
        case name
        case description
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    func localList(itemCount: Int? = nil) -> LocalPlaceList {
        LocalPlaceList(
            localID: "remote_list_\(id)",
            serverID: id,
            ownerUserID: ownerUserID,
            name: name,
            description: description,
            visibility: PlaceListVisibility(rawValue: visibility) ?? .followers,
            syncState: .synced,
            cachedItemCount: itemCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    var ownerShell: ProfileShell {
        ProfileShell(
            id: ownerUserID,
            handle: ownerHandle ?? ownerUserID,
            displayName: ownerDisplayName ?? ownerHandle ?? "Friend",
            avatarURL: ownerAvatarURL,
            bio: nil,
            relationship: .nonFollower
        )
    }
}

struct RemotePlaceListSummaryDTO: Codable, Equatable {
    let id: String
    let ownerUserID: String
    let ownerHandle: String
    let ownerDisplayName: String
    let ownerAvatarURL: String?
    let name: String
    let description: String
    let visibility: String
    let createdAt: Date
    let updatedAt: Date
    let collaborators: [RemotePlaceListCollaboratorDTO]
    let itemCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case ownerHandle = "owner_handle"
        case ownerDisplayName = "owner_display_name"
        case ownerAvatarURL = "owner_avatar_url"
        case name
        case description
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case collaborators
        case itemCount = "item_count"
    }

    func summary() -> RemotePlaceListSummary {
        let row = RemotePlaceListRowDTO(
            id: id,
            ownerUserID: ownerUserID,
            ownerHandle: ownerHandle,
            ownerDisplayName: ownerDisplayName,
            ownerAvatarURL: ownerAvatarURL,
            name: name,
            description: description,
            visibility: visibility,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: nil
        )
        return RemotePlaceListSummary(
            list: row.localList(itemCount: itemCount),
            owner: row.ownerShell,
            collaborators: collaborators.map(\.record),
            itemCount: itemCount
        )
    }
}

struct RemotePlaceListItemDTO: Codable, Equatable {
    let id: String
    let listID: String
    let placeID: String
    let ownerUserPlaceID: String?
    let sourceUserPlaceID: String?
    let addedByUserID: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case listID = "list_id"
        case placeID = "place_id"
        case ownerUserPlaceID = "owner_user_place_id"
        case sourceUserPlaceID = "source_user_place_id"
        case addedByUserID = "added_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var localItem: LocalPlaceListItem {
        LocalPlaceListItem(
            localID: "remote_list_item_\(id)",
            serverID: id,
            listID: listID,
            placeID: placeID,
            ownerUserPlaceID: ownerUserPlaceID,
            sourceUserPlaceID: sourceUserPlaceID,
            addedByUserID: addedByUserID,
            syncState: .synced,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

struct RemotePlaceListDetailDTO: Codable, Equatable {
    let list: RemotePlaceListRowDTO
    let collaborators: [RemotePlaceListCollaboratorDTO]
    let items: [RemotePlaceListItemDTO]

    func detail() -> RemotePlaceListDetail {
        RemotePlaceListDetail(
            list: list.localList(itemCount: items.filter { $0.deletedAt == nil }.count),
            collaborators: collaborators.map(\.record),
            items: items.map(\.localItem)
        )
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var encodedJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "null"
        }

        return encoded
    }
}
