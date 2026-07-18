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

struct RemoteCurrentProfileDTO: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let defaultVisibility: String
    let isPrivateProfile: Bool
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
            isPrivateProfile: isPrivateProfile,
            defaultVisibility: PlaceVisibility(rawValue: defaultVisibility) ?? .followers,
            syncState: .synced,
            createdAt: createdAt
        )
    }
}

struct RemoteVisiblePlaceDTO: Codable, Equatable {
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

        let owner = LocalProfile(
            localID: ownerUserID,
            serverID: ownerUserID,
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
            serverID: userPlaceID,
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
            attributes: attributes.map { $0.localAttribute(userPlaceID: userPlaceID) }
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
