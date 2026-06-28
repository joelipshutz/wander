import Foundation

struct RemoteProfileShellDTO: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let relationship: String?

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case homeArea = "home_area"
        case relationship
    }

    func profileShell(fallbackRelationship: ViewerRelationship = .nonFollower) -> ProfileShell {
        ProfileShell(
            id: id,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
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

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case homeArea = "home_area"
        case defaultVisibility = "default_visibility"
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
            defaultVisibility: PlaceVisibility(rawValue: defaultVisibility) ?? .followers,
            syncState: .synced
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
    let latitude: Double
    let longitude: Double
    let status: String
    let visibility: String
    let note: String?
    let ratingSignal: String?
    let ratingScore: Int?
    let recommendedScore: Double?
    let recommendedCount: Int?
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
        case latitude
        case longitude
        case status
        case visibility
        case note
        case ratingSignal = "rating_signal"
        case ratingScore = "rating_score"
        case recommendedScore = "recommended_score"
        case recommendedCount = "recommended_count"
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
            latitude: latitude,
            longitude: longitude,
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
            sourceType: sourceType,
            syncState: .synced
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
