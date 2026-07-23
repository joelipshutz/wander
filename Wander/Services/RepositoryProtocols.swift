import CoreLocation
import Foundation

struct ProfileShell: Identifiable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let homeArea: String?
    let isPrivateProfile: Bool?
    let createdAt: Date?
    let relationship: ViewerRelationship

    init(
        id: String,
        handle: String,
        displayName: String,
        avatarURL: String?,
        bio: String?,
        homeArea: String? = nil,
        isPrivateProfile: Bool? = nil,
        createdAt: Date? = nil,
        relationship: ViewerRelationship
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
        self.homeArea = homeArea
        self.isPrivateProfile = isPrivateProfile
        self.createdAt = createdAt
        self.relationship = relationship
    }
}

struct ProfileViewState {
    let shell: ProfileShell
    let visiblePlaces: [VisiblePlace]
    let canFollow: Bool
    let canBlock: Bool
    let isBlocked: Bool
}

enum DiscoverPeopleRecommendationReason: Equatable {
    case followsYou
    case sharedFollows(Int)
    case suggested

    func displayText(for profile: ProfileShell) -> String {
        switch self {
        case .followsYou:
            return "Follows you"
        case .sharedFollows(let count):
            return count == 1
                ? "1 person you follow follows \(profile.displayName)"
                : "\(count) people you follow follow \(profile.displayName)"
        case .suggested:
            return "Suggested by rec.me"
        }
    }
}

struct DiscoverPeopleRecommendation: Identifiable, Equatable {
    let profile: ProfileShell
    let reason: DiscoverPeopleRecommendationReason
    let rank: Int

    var id: String { profile.id }
}

enum DiscoverPeopleRecommendationsState: Equatable {
    case idle
    case loading
    case loaded([DiscoverPeopleRecommendation])
    case failed
}

struct MapViewport: Equatable {
    let minLatitude: Double
    let minLongitude: Double
    let maxLatitude: Double
    let maxLongitude: Double
}

struct PlaceFilters: Equatable {
    var statuses: Set<PlaceStatus> = []
    var categories: Set<String> = []
    var ownerScopes: Set<String> = []
    var ownerIDs: Set<String> = []

    var normalizedCategories: Set<String> {
        Set(categories.map(WanderPlaceCategory.normalizedPrimaryCategory))
    }
}

struct ManualPlaceInput: Equatable {
    let name: String
    let areaHint: String?
    let category: String?
}

struct LinkPlaceInput: Equatable {
    let rawValue: String
}

struct PlaceCandidate: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let category: String
    let primaryCategory: String
    let subcategory: String?
    let categorySource: String
    let categoryConfidence: Double?
    let rawProviderType: String?
    var address: String? = nil
    var locality: String? = nil
    var region: String? = nil
    var country: String? = nil
    let latitude: Double?
    let longitude: Double?
    var sourceProvider: String = "mapkit"
    var sourceProviderPlaceID: String? = nil
    var distanceMeters: Double? = nil
    var websiteURLString: String? = nil
    var phoneNumber: String? = nil
    var timeZoneIdentifier: String? = nil
    var actionLinksJSON: String? = nil
    let confidence: Double

    init(
        id: String,
        name: String,
        category: String,
        primaryCategory: String? = nil,
        subcategory: String? = nil,
        categorySource: String = PlaceCategorySource.provider.rawValue,
        categoryConfidence: Double? = nil,
        rawProviderType: String? = nil,
        address: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        country: String? = nil,
        latitude: Double?,
        longitude: Double?,
        sourceProvider: String = "mapkit",
        sourceProviderPlaceID: String? = nil,
        distanceMeters: Double? = nil,
        websiteURLString: String? = nil,
        phoneNumber: String? = nil,
        timeZoneIdentifier: String? = nil,
        actionLinksJSON: String? = nil,
        confidence: Double
    ) {
        let categoryInput = WanderPlaceCategory.categoryInferenceInput(
            category: category,
            rawProviderType: rawProviderType
        )
        let assignment = primaryCategory.map {
            WanderPlaceCategory.assignment(
                primaryCategory: $0,
                subcategory: subcategory,
                source: categorySource,
                confidence: categoryConfidence,
                rawProviderType: rawProviderType ?? category
            )
        } ?? WanderPlaceCategory.assignment(
            forRawCategory: categoryInput,
            source: categorySource,
            confidence: categoryConfidence,
            rawProviderType: rawProviderType ?? category
        )

        self.id = id
        self.name = name
        self.category = assignment.legacyCategory
        self.primaryCategory = assignment.primaryCategory
        self.subcategory = assignment.subcategory
        self.categorySource = assignment.source
        self.categoryConfidence = assignment.confidence ?? categoryConfidence ?? confidence
        self.rawProviderType = assignment.rawProviderType
        self.address = address
        self.locality = locality
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.sourceProvider = sourceProvider
        self.sourceProviderPlaceID = sourceProviderPlaceID
        self.distanceMeters = distanceMeters
        self.websiteURLString = websiteURLString
        self.phoneNumber = phoneNumber
        self.timeZoneIdentifier = timeZoneIdentifier
        self.actionLinksJSON = actionLinksJSON
        self.confidence = confidence
    }
}

struct PlaceActionLink: Equatable, Codable, Identifiable {
    enum Kind: String, Codable {
        case website
        case order
        case reserve
        case menu
        case deliverySearch
        case reservationSearch
    }

    enum Source: String, Codable {
        case mapkit
        case userCaptured
        case backendExtraction
        case providerSearch
    }

    enum Confidence: String, Codable {
        case exact
        case search
    }

    let kind: Kind
    let title: String
    let urlString: String
    let source: Source
    let confidence: Confidence

    var id: String {
        "\(kind.rawValue)|\(source.rawValue)|\(urlString)"
    }
}

extension PlaceCandidate {
    var categoryAssignment: PlaceCategoryAssignment {
        PlaceCategoryAssignment(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            source: categorySource,
            confidence: categoryConfidence,
            rawProviderType: rawProviderType
        )
    }

    var categoryEmoji: String {
        WanderPlaceCategory.emoji(for: categoryAssignment, name: name)
    }

    func recategorized(as category: String) -> PlaceCandidate {
        recategorized(
            as: WanderPlaceCategory.assignment(
                forRawCategory: category,
                source: PlaceCategorySource.user.rawValue,
                confidence: 1,
                rawProviderType: rawProviderType ?? category
            )
        )
    }

    func recategorized(as assignment: PlaceCategoryAssignment) -> PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name,
            category: assignment.legacyCategory,
            primaryCategory: assignment.primaryCategory,
            subcategory: assignment.subcategory,
            categorySource: assignment.source,
            categoryConfidence: assignment.confidence,
            rawProviderType: assignment.rawProviderType ?? rawProviderType,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            distanceMeters: distanceMeters,
            websiteURLString: websiteURLString,
            phoneNumber: phoneNumber,
            timeZoneIdentifier: timeZoneIdentifier,
            actionLinksJSON: actionLinksJSON,
            confidence: confidence
        )
    }

    var actionLinks: [PlaceActionLink] {
        PlaceActionLink.decode(actionLinksJSON)
    }

    var previewFormattedDistance: String? {
        guard let distanceMeters else { return nil }

        let miles = distanceMeters / 1_609.344
        if miles < 0.1 {
            return "nearby"
        }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }

    func previewSubtitle(
        includeDistance: Bool = true,
        includeCategory: Bool = true,
        trailingParts: [String?] = [],
        fallback: String? = nil
    ) -> String {
        let locality = Self.trimmed(self.locality)
        let address = Self.addressWithoutDuplicateLocality(self.address, locality: locality)
        let categoryDisplay = WanderPlaceCategory.display(for: categoryAssignment).compactTitle
        let category = includeCategory && !categoryDisplay.isEmpty && self.primaryCategory != "place" ? categoryDisplay : nil
        let baseParts: [String?] = [
            includeDistance ? previewFormattedDistance : nil,
            address,
            locality,
            category
        ]
        let parts = Self.dedupedDisplayParts(baseParts + trailingParts)

        guard !parts.isEmpty else {
            return fallback ?? "confidence \(Int(confidence * 100))%"
        }

        return parts.joined(separator: " · ")
    }

    private static func addressWithoutDuplicateLocality(_ address: String?, locality: String?) -> String? {
        guard var address = trimmed(address) else { return nil }
        guard let locality else { return address }

        let normalizedAddress = normalizedDisplayPart(address)
        let normalizedLocality = normalizedDisplayPart(locality)
        if normalizedAddress == normalizedLocality {
            return nil
        }

        let commaParts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if commaParts.count > 1,
           commaParts.dropFirst().contains(where: { normalizedDisplayPart($0) == normalizedLocality }),
           let streetAddress = commaParts.first,
           normalizedDisplayPart(streetAddress) != normalizedLocality {
            return streetAddress
        }

        let suffixes = [", \(locality)", " \(locality)"]
        for suffix in suffixes where address.lowercased().hasSuffix(suffix.lowercased()) {
            address.removeLast(suffix.count)
            address = address.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            return address.isEmpty ? nil : address
        }

        return address
    }

    private static func dedupedDisplayParts(_ parts: [String?]) -> [String] {
        var seen = Set<String>()
        var displayParts: [String] = []

        for part in parts {
            guard let trimmed = trimmed(part) else { continue }
            let normalized = normalizedDisplayPart(trimmed)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            displayParts.append(trimmed)
        }

        return displayParts
    }

    private static func normalizedDisplayPart(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

extension PlaceActionLink {
    static func decode(_ json: String?) -> [PlaceActionLink] {
        guard let json,
              let data = json.data(using: .utf8),
              let links = try? JSONDecoder().decode([PlaceActionLink].self, from: data)
        else {
            return []
        }
        return links
    }

    static func encode(_ links: [PlaceActionLink]) -> String? {
        guard !links.isEmpty,
              let data = try? JSONEncoder().encode(links),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }
}

struct PlaceDraft: Equatable {
    let localID: String
    let serverID: String?
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
    var websiteURLString: String? = nil
    var phoneNumber: String? = nil
    var timeZoneIdentifier: String? = nil
    var actionLinksJSON: String? = nil

    init(
        localID: String,
        serverID: String?,
        canonicalName: String,
        category: String,
        primaryCategory: String? = nil,
        subcategory: String? = nil,
        categorySource: String = PlaceCategorySource.provider.rawValue,
        categoryConfidence: Double? = nil,
        rawProviderType: String? = nil,
        address: String?,
        locality: String?,
        region: String?,
        country: String?,
        latitude: Double,
        longitude: Double,
        sourceProvider: String,
        sourceProviderPlaceID: String?,
        confidence: Double?,
        websiteURLString: String? = nil,
        phoneNumber: String? = nil,
        timeZoneIdentifier: String? = nil,
        actionLinksJSON: String? = nil
    ) {
        let categoryInput = WanderPlaceCategory.categoryInferenceInput(
            category: category,
            rawProviderType: rawProviderType
        )
        let assignment = primaryCategory.map {
            WanderPlaceCategory.assignment(
                primaryCategory: $0,
                subcategory: subcategory,
                source: categorySource,
                confidence: categoryConfidence,
                rawProviderType: rawProviderType ?? category
            )
        } ?? WanderPlaceCategory.assignment(
            forRawCategory: categoryInput,
            source: categorySource,
            confidence: categoryConfidence,
            rawProviderType: rawProviderType ?? category
        )

        self.localID = localID
        self.serverID = serverID
        self.canonicalName = canonicalName
        self.category = assignment.legacyCategory
        self.primaryCategory = assignment.primaryCategory
        self.subcategory = assignment.subcategory
        self.categorySource = assignment.source
        self.categoryConfidence = assignment.confidence ?? categoryConfidence ?? confidence
        self.rawProviderType = assignment.rawProviderType
        self.address = address
        self.locality = locality
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.sourceProvider = sourceProvider
        self.sourceProviderPlaceID = sourceProviderPlaceID
        self.confidence = confidence
        self.websiteURLString = websiteURLString
        self.phoneNumber = phoneNumber
        self.timeZoneIdentifier = timeZoneIdentifier
        self.actionLinksJSON = actionLinksJSON
    }
}

struct UserPlaceDraft: Equatable {
    let place: PlaceDraft
    let status: PlaceStatus
    let visibility: PlaceVisibility
    let note: String?
    let ratingSignal: String?
    let ratingScore: Double?
    let categoryOverride: String?
    let subcategoryOverride: String?
    let categoryOverrideSource: String?
    let categoryOverrideConfidence: Double?
    let nearbyConfirmed: Bool
    let sourceType: String
    let attributes: [PlaceAttributeDraft]

    init(
        place: PlaceDraft,
        status: PlaceStatus,
        visibility: PlaceVisibility,
        note: String?,
        ratingSignal: String? = nil,
        ratingScore: Double? = nil,
        categoryOverride: String? = nil,
        subcategoryOverride: String? = nil,
        categoryOverrideSource: String? = nil,
        categoryOverrideConfidence: Double? = nil,
        nearbyConfirmed: Bool,
        sourceType: String,
        attributes: [PlaceAttributeDraft]
    ) {
        self.place = place
        self.status = status
        self.visibility = visibility
        self.note = note
        self.ratingSignal = ratingSignal
        self.ratingScore = PlaceRating.scoreForSave(status: status, score: ratingScore)
        self.categoryOverride = categoryOverride
        self.subcategoryOverride = subcategoryOverride
        self.categoryOverrideSource = categoryOverrideSource
        self.categoryOverrideConfidence = categoryOverrideConfidence
        self.nearbyConfirmed = nearbyConfirmed
        self.sourceType = sourceType
        self.attributes = attributes
    }
}

struct PlaceAttributeDraft: Equatable {
    let questionKey: String
    let valueType: String
    let valueJSON: String

    init(questionKey: String, valueType: String, valueJSON: String) {
        self.questionKey = questionKey
        self.valueType = valueType
        self.valueJSON = valueJSON
    }

    init(questionKey: String, valueType: String, stringValue: String) {
        self.questionKey = questionKey
        self.valueType = valueType
        self.valueJSON = Self.encoded(stringValue)
    }

    init(questionKey: String, valueType: String, stringValues: [String]) {
        self.questionKey = questionKey
        self.valueType = valueType
        self.valueJSON = Self.encoded(stringValues)
    }

    private static func encoded<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "null"
        }

        return encoded
    }
}

struct VisitAttributeAnswer: Codable, Equatable {
    let questionKey: String
    let valueType: String
    let value: JSONValue

    enum CodingKeys: String, CodingKey {
        case questionKey = "question_key"
        case valueType = "value_type"
        case value
    }
}

enum VisitAttributeAnswers {
    static func encoded(from attributes: [PlaceAttributeDraft]) -> String {
        let answers = attributes.map { attribute in
            VisitAttributeAnswer(
                questionKey: attribute.questionKey,
                valueType: attribute.valueType,
                value: decodedJSONValue(attribute.valueJSON)
            )
        }

        guard let data = try? JSONEncoder().encode(answers),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return encoded
    }

    static func drafts(fromAttributeAnswersJSON attributeAnswersJSON: String) -> [PlaceAttributeDraft] {
        guard let data = attributeAnswersJSON.data(using: .utf8),
              let answers = try? JSONDecoder().decode([VisitAttributeAnswer].self, from: data)
        else {
            return []
        }

        return answers.map { answer in
            PlaceAttributeDraft(
                questionKey: answer.questionKey,
                valueType: answer.valueType,
                valueJSON: encodedJSONValue(answer.value)
            )
        }
    }

    static func tags(from attributes: [PlaceAttributeDraft]) -> [String] {
        normalizedTags(
            attributes
                .filter { $0.valueType == "multi_tag" }
                .flatMap { stringValues(from: $0.valueJSON) }
        )
    }

    static func tags(fromAttributeAnswersJSON attributeAnswersJSON: String) -> [String] {
        guard let data = attributeAnswersJSON.data(using: .utf8),
              let answers = try? JSONDecoder().decode([VisitAttributeAnswer].self, from: data)
        else {
            return []
        }

        return normalizedTags(
            answers
                .filter { $0.valueType == "multi_tag" }
                .flatMap { answer -> [String] in
                    guard case .array(let values) = answer.value else { return [] }
                    return values.compactMap { value in
                        guard case .string(let string) = value else { return nil }
                        return string
                    }
                }
        )
    }

    private static func decodedJSONValue(_ json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .null
        }

        return value
    }

    private static func encodedJSONValue(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "null"
        }

        return encoded
    }

    private static func stringValues(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return values
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for tag in tags {
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            normalized.append(value)
        }

        return normalized.sorted()
    }
}

struct PlaceVisitDraft: Equatable {
    let id: String?
    let userPlaceID: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswersJSON: String
    let backfilledFromUserPlace: Bool
}

struct PlaceVisitResult: Equatable {
    let visitID: String
    let userPlaceID: String
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let tags: [String]
    let backfilledFromUserPlace: Bool
}

struct VisitPhotoDraft: Equatable {
    let id: String?
    let visitID: String
    let storageBucket: String
    let storagePath: String
    let remoteURLString: String?
    let contentType: String?
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int
    let uploadState: VisitPhotoUploadState
}

struct VisitPhotoResult: Equatable {
    let photoID: String
    let visitID: String
    let storageBucket: String
    let storagePath: String
    let remoteURLString: String?
    let contentType: String?
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int
    let uploadState: VisitPhotoUploadState
}

struct PlacePhotoRequest: Encodable, Equatable {
    let placeID: String?
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?
    let requiresPhoto: Bool
    let eligibleUserIDs: [String]?

    init(
        placeID: String? = nil,
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        sourceProvider: String?,
        sourceProviderPlaceID: String?,
        requiresPhoto: Bool = true,
        eligibleUserIDs: [String]? = nil
    ) {
        self.placeID = placeID
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.sourceProvider = sourceProvider
        self.sourceProviderPlaceID = sourceProviderPlaceID
        self.requiresPhoto = requiresPhoto
        self.eligibleUserIDs = eligibleUserIDs
    }

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case name
        case address
        case latitude
        case longitude
        case sourceProvider = "source_provider"
        case sourceProviderPlaceID = "source_provider_place_id"
        case requiresPhoto = "requires_photo"
    }

    var lookupKey: String {
        let coordinate = [latitude, longitude]
            .compactMap { $0.map { String(format: "%.5f", $0) } }
            .joined(separator: ",")
        var components = [placeID, sourceProvider, sourceProviderPlaceID, name, address, coordinate]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !requiresPhoto {
            components.append("metadata-only")
        }
        return components.joined(separator: "|")
    }

    var skipsGooglePlacesLookup: Bool {
        let provider = sourceProvider?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return provider == "coordinate"
            || sourceProviderPlaceID?.lowercased().hasPrefix("coordinate_") == true
            || normalizedName == "dropped pin"
    }

    func restrictingVisibleUserPhotos(to userIDs: [String]) -> PlacePhotoRequest {
        PlacePhotoRequest(
            placeID: placeID,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            requiresPhoto: requiresPhoto,
            eligibleUserIDs: userIDs
        )
    }
}

struct PlacePhoto: Decodable, Equatable {
    let provider: String
    let providerPlaceID: String
    let providerPrimaryType: String?
    let providerTypes: [String]?
    let photoURLString: String
    let width: Int?
    let height: Int?
    let authorName: String?
    let authorProfileURLString: String?
    let authorAvatarURLString: String?
    let sourcePhotoURLString: String?
    let flagContentURLString: String?
    let storageBucket: String?
    let storagePath: String?
    let localAssetRef: String?

    init(
        provider: String,
        providerPlaceID: String,
        providerPrimaryType: String? = nil,
        providerTypes: [String]? = nil,
        photoURLString: String,
        width: Int?,
        height: Int?,
        authorName: String?,
        authorProfileURLString: String?,
        authorAvatarURLString: String?,
        sourcePhotoURLString: String?,
        flagContentURLString: String?,
        storageBucket: String?,
        storagePath: String?,
        localAssetRef: String?
    ) {
        self.provider = provider
        self.providerPlaceID = providerPlaceID
        self.providerPrimaryType = providerPrimaryType
        self.providerTypes = providerTypes
        self.photoURLString = photoURLString
        self.width = width
        self.height = height
        self.authorName = authorName
        self.authorProfileURLString = authorProfileURLString
        self.authorAvatarURLString = authorAvatarURLString
        self.sourcePhotoURLString = sourcePhotoURLString
        self.flagContentURLString = flagContentURLString
        self.storageBucket = storageBucket
        self.storagePath = storagePath
        self.localAssetRef = localAssetRef
    }

    init(localVisitPhoto photo: LocalVisitPhoto) {
        self.init(
            provider: "visit_photo",
            providerPlaceID: photo.id,
            photoURLString: photo.remoteURLString ?? "",
            width: photo.width,
            height: photo.height,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: photo.storageBucket,
            storagePath: photo.storagePath,
            localAssetRef: photo.localAssetRef
        )
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case providerPlaceID = "provider_place_id"
        case providerPrimaryType = "provider_primary_type"
        case providerTypes = "provider_types"
        case photoURLString = "photo_url"
        case width
        case height
        case authorName = "author_name"
        case authorProfileURLString = "author_profile_url"
        case authorAvatarURLString = "author_avatar_url"
        case sourcePhotoURLString = "source_photo_url"
        case flagContentURLString = "flag_content_url"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case localAssetRef = "local_asset_ref"
    }

    var photoURL: URL? { URL(string: photoURLString) }
    var authorProfileURL: URL? { authorProfileURLString.flatMap(URL.init(string:)) }
    var authorAvatarURL: URL? { authorAvatarURLString.flatMap(URL.init(string:)) }
    var sourcePhotoURL: URL? { sourcePhotoURLString.flatMap(URL.init(string:)) }
    var isGooglePlacesPhoto: Bool { provider == "google_places" }

    var cacheKey: String {
        [provider, providerPlaceID, photoURLString, storageBucket, storagePath, localAssetRef]
            .compactMap { $0 }
            .joined(separator: "|")
    }
}

struct SaveResult: Equatable {
    let userPlaceID: String
    let syncState: SyncState
    let placeID: String?

    init(userPlaceID: String, syncState: SyncState, placeID: String? = nil) {
        self.userPlaceID = userPlaceID
        self.syncState = syncState
        self.placeID = placeID
    }
}

struct SourceArtifactDraft: Equatable {
    let type: String
    let originalInput: String
    let normalizedInput: String
    let normalizedSourceHash: String
    let localAssetRef: String?
    let remoteAssetRef: String?
}

struct ExtractionJobDraft: Equatable {
    let sourceArtifact: SourceArtifactDraft
    let sourceType: String
    let normalizedSourceHash: String
    let providerSteps: [String]
}

struct ExtractionJobEnqueueResult: Equatable {
    let sourceArtifactID: String
    let extractionJobID: String
    let status: ExtractionStatus
    let attemptCount: Int
}

struct ExtractionJobResult: Equatable {
    let extractionJobID: String
    let status: ExtractionStatus
    let attemptCount: Int
    let providerSteps: [String]
    let candidates: [PlaceCandidate]
    let confidence: Double
    let errorCode: String?
    let errorMessage: String?
}

struct PlaceListCollaboratorRecord: Equatable {
    let userID: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let role: PlaceListRole

    var profileShell: ProfileShell {
        ProfileShell(
            id: userID,
            handle: handle,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: nil,
            relationship: .nonFollower
        )
    }
}

struct RemotePlaceListSummary: Equatable {
    let list: LocalPlaceList
    let owner: ProfileShell
    let collaborators: [PlaceListCollaboratorRecord]
    let itemCount: Int
}

struct RemotePlaceListDetail: Equatable {
    let list: LocalPlaceList
    let collaborators: [PlaceListCollaboratorRecord]
    let items: [LocalPlaceListItem]
}

struct PlaceListUpsertDraft: Equatable {
    let id: String?
    let name: String
    let description: String
    let visibility: PlaceListVisibility
}

struct PlaceListItemDraft: Equatable {
    let listID: String
    let placeID: String
    let ownerUserPlaceID: String?
    let sourceUserPlaceID: String?
}

struct ProfileAvatarResult: Equatable {
    let avatarURL: String
    let storagePath: String
}

struct ProfileDetailsUpdate: Equatable {
    let displayName: String?
    let handle: String?
    let bio: String?
    let homeArea: String?
    let defaultVisibility: PlaceVisibility?
    let isPrivateProfile: Bool?

    init(
        displayName: String? = nil,
        handle: String? = nil,
        bio: String? = nil,
        homeArea: String? = nil,
        defaultVisibility: PlaceVisibility? = nil,
        isPrivateProfile: Bool? = nil
    ) {
        self.displayName = displayName
        self.handle = handle
        self.bio = bio
        self.homeArea = homeArea
        self.defaultVisibility = defaultVisibility
        self.isPrivateProfile = isPrivateProfile
    }
}

enum PushTokenEnvironment: String, Equatable {
    case sandbox
    case production
}

struct NotificationPreferences: Equatable {
    var pushEnabled: Bool = false
    var socialGraphEnabled: Bool = false
    var sharedListsEnabled: Bool = false
    var sharedVisitsEnabled: Bool = false
    var recommendationsEnabled: Bool = false
    var captureEnabled: Bool = false
    var discoveryDigestEnabled: Bool = false
    var followedActivityEnabled: Bool = false

    static let allEnabled = NotificationPreferences(
        pushEnabled: true,
        socialGraphEnabled: true,
        sharedListsEnabled: true,
        sharedVisitsEnabled: true,
        recommendationsEnabled: true,
        captureEnabled: true,
        discoveryDigestEnabled: true,
        followedActivityEnabled: true
    )

    static let allDisabled = NotificationPreferences(
        pushEnabled: false,
        socialGraphEnabled: false,
        sharedListsEnabled: false,
        sharedVisitsEnabled: false,
        recommendationsEnabled: false,
        captureEnabled: false,
        discoveryDigestEnabled: false,
        followedActivityEnabled: false
    )
}

struct NotificationPreferencesUpdate: Equatable {
    var pushEnabled: Bool?
    var socialGraphEnabled: Bool?
    var sharedListsEnabled: Bool?
    var sharedVisitsEnabled: Bool?
    var recommendationsEnabled: Bool?
    var captureEnabled: Bool?
    var discoveryDigestEnabled: Bool?
    var followedActivityEnabled: Bool?

    init(
        pushEnabled: Bool? = nil,
        socialGraphEnabled: Bool? = nil,
        sharedListsEnabled: Bool? = nil,
        sharedVisitsEnabled: Bool? = nil,
        recommendationsEnabled: Bool? = nil,
        captureEnabled: Bool? = nil,
        discoveryDigestEnabled: Bool? = nil,
        followedActivityEnabled: Bool? = nil
    ) {
        self.pushEnabled = pushEnabled
        self.socialGraphEnabled = socialGraphEnabled
        self.sharedListsEnabled = sharedListsEnabled
        self.sharedVisitsEnabled = sharedVisitsEnabled
        self.recommendationsEnabled = recommendationsEnabled
        self.captureEnabled = captureEnabled
        self.discoveryDigestEnabled = discoveryDigestEnabled
        self.followedActivityEnabled = followedActivityEnabled
    }

    static let allEnabled = NotificationPreferencesUpdate(
        pushEnabled: true,
        socialGraphEnabled: true,
        sharedListsEnabled: true,
        sharedVisitsEnabled: true,
        recommendationsEnabled: true,
        captureEnabled: true,
        discoveryDigestEnabled: true,
        followedActivityEnabled: true
    )

    static let allDisabled = NotificationPreferencesUpdate(
        pushEnabled: false,
        socialGraphEnabled: false,
        sharedListsEnabled: false,
        sharedVisitsEnabled: false,
        recommendationsEnabled: false,
        captureEnabled: false,
        discoveryDigestEnabled: false,
        followedActivityEnabled: false
    )
}

enum SharedVisitParticipantStatus: String, Codable, Equatable {
    case owner
    case pending
    case accepted
    case declined
    case cancelled
    case expired
    case removed
}

struct SharedVisitPhotoSnapshot: Identifiable, Codable, Equatable {
    let photoID: String
    let storageBucket: String
    let storagePath: String
    let contentType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let capturedAt: Date?
    let sortOrder: Int

    var id: String { photoID }
}

struct SharedVisitInvitation: Identifiable, Codable, Equatable {
    let participantID: String
    let groupID: String
    let invitationGeneration: Int
    let snapshotRevision: Int
    let status: SharedVisitParticipantStatus
    let invitedAt: Date
    let sourceVisitID: String
    let sourceOwnerUserID: String
    let sourceOwnerHandle: String
    let sourceOwnerDisplayName: String
    let sourceOwnerAvatarURL: String?
    let placeID: String
    let placeName: String
    let category: String
    let primaryCategory: String
    let subcategory: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String?
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributeAnswers: [VisitAttributeAnswer]
    let tags: [String]
    let photos: [SharedVisitPhotoSnapshot]

    var id: String { participantID }

    var categoryAssignment: PlaceCategoryAssignment {
        PlaceCategoryAssignment(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            source: PlaceCategorySource.legacy.rawValue,
            confidence: nil,
            rawProviderType: category
        )
    }

    var restaurantCuisine: String? {
        guard let answer = attributeAnswers.first(where: {
            $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine
        }) else {
            return nil
        }

        switch answer.value {
        case .string(let value):
            return value
        case .array(let values):
            for value in values {
                if case .string(let string) = value {
                    return string
                }
            }
            return nil
        default:
            return nil
        }
    }

    var categoryEmoji: String {
        WanderPlaceCategory.emoji(
            for: categoryAssignment,
            cuisine: restaurantCuisine,
            name: placeName
        )
    }

    var candidate: PlaceCandidate {
        PlaceCandidate(
            id: placeID,
            name: placeName,
            category: primaryCategory,
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            categorySource: PlaceCategorySource.legacy.rawValue,
            categoryConfidence: nil,
            rawProviderType: category,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            confidence: 1
        )
    }

    var attributeDrafts: [PlaceAttributeDraft] {
        attributeAnswers.map { answer in
            let data = (try? JSONEncoder().encode(answer.value)) ?? Data("null".utf8)
            return PlaceAttributeDraft(
                questionKey: answer.questionKey,
                valueType: answer.valueType,
                valueJSON: String(data: data, encoding: .utf8) ?? "null"
            )
        }
    }
}

struct SharedVisitInviteResult: Equatable {
    let participantID: String
    let inviteeUserID: String
    let status: SharedVisitParticipantStatus
    let invitationGeneration: Int
}

struct PendingSharedVisitInvite: Identifiable, Codable, Equatable {
    let id: String
    let ownerUserID: String
    let sourceVisitID: String
    let inviteeUserIDs: [String]
    let createdAt: Date
}

struct SharedVisitAcceptanceIdentifiers: Equatable {
    let operationID: String
    let userPlaceID: String
    let visitID: String

    static func deterministic(participantID: String, generation: Int) -> SharedVisitAcceptanceIdentifiers {
        let prefix = "shared-visit:\(participantID):\(generation)"
        return SharedVisitAcceptanceIdentifiers(
            operationID: stableUUID(for: "\(prefix):operation"),
            userPlaceID: stableUUID(for: "\(prefix):user-place"),
            visitID: stableUUID(for: "\(prefix):visit")
        )
    }

    private static func stableUUID(for value: String) -> String {
        let bytes = Array(value.utf8)
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 1_099_511_628_211

        for byte in bytes {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
        }
        for byte in bytes.reversed() {
            second = (second ^ UInt64(byte)) &* 1_099_511_628_211
        }

        var uuidBytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        uuidBytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian, Array.init))
        uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80

        let hex = uuidBytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }
}

struct SharedVisitAcceptanceDraft: Equatable {
    let participantID: String
    let invitationGeneration: Int
    let snapshotRevision: Int
    let operationID: String
    let userPlaceID: String
    let visitID: String
    let visibility: PlaceVisibility
    let visitedAt: Date
    let note: String?
    let ratingScore: Double?
    let attributes: [PlaceAttributeDraft]
    let selectedPhotoIDs: [String]
}

struct SharedVisitPhotoCopy: Equatable {
    let sourcePhotoID: String
    let sourceBucket: String
    let sourcePath: String
    let destinationPhotoID: String
    let destinationBucket: String
    let destinationPath: String
    let contentType: String
}

struct SharedVisitAcceptanceResult: Equatable {
    let operationID: String
    let participantID: String
    let userPlaceID: String
    let visitID: String
    let backfilledFromUserPlace: Bool
    let status: SharedVisitParticipantStatus
    let photoCopies: [SharedVisitPhotoCopy]
}

struct SharedVisitCompanion: Identifiable, Equatable {
    let visitID: String
    let userID: String
    let handle: String
    let displayName: String
    let avatarURL: String?

    var id: String { "\(visitID):\(userID)" }
}

struct SharedVisitDestination: Equatable {
    let participantID: String
    let requestedGeneration: Int
    let currentGeneration: Int
    let status: String
    let placeID: String
    let acceptedVisitID: String?
    let sourceVisitID: String
}

enum SharedVisitDestinationResolution: Equatable {
    case resolved(SharedVisitDestination)
    case unavailable
    case retryableFailure
}

@MainActor
protocol ProfileRepository {
    func currentProfile() async throws -> LocalProfile?
    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile
    func profile(id: String) async throws -> ProfileViewState
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell]
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation]
    func updatePrivacy(isPrivateProfile: Bool, defaultVisibility: PlaceVisibility) async throws -> LocalProfile
}

extension ProfileRepository {
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        throw WanderRemoteError.notImplemented("profile recommendations RPC")
    }

    func updatePrivacy(isPrivateProfile: Bool, defaultVisibility: PlaceVisibility) async throws -> LocalProfile {
        throw WanderRemoteError.notImplemented("profile privacy RPC")
    }
}

extension ProfileRepository {
    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile {
        throw WanderRemoteError.notImplemented("update current profile")
    }
}

@MainActor
protocol ProfileAvatarRepository {
    func uploadAvatar(jpegData: Data, userID: String) async throws -> ProfileAvatarResult
    func deleteAvatar(userID: String) async throws
}

@MainActor
protocol FollowRepository {
    func follow(userID: String) async throws
    func unfollow(userID: String) async throws
    func followers(userID: String) async throws -> [ProfileShell]
    func following(userID: String) async throws -> [ProfileShell]
    func relationship(to userID: String) async throws -> ViewerRelationship
}

@MainActor
protocol BlockRepository {
    func block(userID: String) async throws
    func unblock(userID: String) async throws
    func blockedProfiles() async throws -> [ProfileShell]
    func isBlocked(userID: String) async throws -> Bool
}

@MainActor
protocol MuteRepository {
    func mute(userID: String) async throws
    func unmute(userID: String) async throws
    func mutedProfiles() async throws -> [ProfileShell]
}

@MainActor
protocol PlaceCandidateResolving {
    func resolveCurrentLocation() async throws -> [PlaceCandidate]
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate]
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate]
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate]
}

@MainActor
protocol PlaceRepository {
    func places(in viewport: MapViewport) async throws -> [VisiblePlace]
    func resolveCurrentLocation() async throws -> [PlaceCandidate]
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate]
}

@MainActor
protocol FeedRepository {
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage
}

@MainActor
protocol UserPlaceRepository {
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace]
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws
    func delete(userPlaceID: String) async throws
}

@MainActor
protocol SocialPlaceSaveRepository {
    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String) async throws -> SaveResult
}

@MainActor
protocol PlacePhotoRepository {
    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto
    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto
    func imageData(for photo: PlacePhoto) async throws -> Data
}

@MainActor
protocol VisitRepository {
    func visits(for userPlaceID: String) async throws -> [PlaceVisitResult]
    func upsertVisit(_ draft: PlaceVisitDraft) async throws -> PlaceVisitResult
    func deleteVisit(visitID: String) async throws
    func photos(for visitID: String) async throws -> [VisitPhotoResult]
    func upsertPhotoMetadata(_ draft: VisitPhotoDraft) async throws -> VisitPhotoResult
    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws -> URL
    func deletePhoto(photoID: String, bucket: String, path: String) async throws
}

@MainActor
protocol ExtractionRepository {
    func enqueue(_ draft: ExtractionJobDraft) async throws -> ExtractionJobEnqueueResult
    func process(jobID: String) async throws -> ExtractionJobResult
    func result(jobID: String) async throws -> ExtractionJobResult
}

@MainActor
protocol PlaceListRepository {
    func visibleLists() async throws -> [RemotePlaceListSummary]
    func detail(listID: String) async throws -> RemotePlaceListDetail?
    func upsert(_ draft: PlaceListUpsertDraft) async throws -> String
    func delete(listID: String) async throws
    func setCollaborators(listID: String, userIDs: [String]) async throws
    func addItem(_ draft: PlaceListItemDraft) async throws -> String
    func removeItem(listID: String, itemID: String) async throws
}

@MainActor
protocol DiscoverRepository {
    func parseFilters(query: String) async throws -> DiscoverFilters
    func search(filters: DiscoverFilters) async throws -> DiscoverResults
}

@MainActor
protocol DiscoverFilterParsingRepository {
    func parseFilters(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters
}

@MainActor
protocol ListSuggestionRepository {
    func suggestions(payload: ListSuggestionPayload) async throws -> ListSuggestionFunctionResponse
}

@MainActor
protocol NotificationRepository {
    func preferences() async throws -> NotificationPreferences
    func updatePreferences(_ update: NotificationPreferencesUpdate) async throws -> NotificationPreferences
    func registerPushToken(_ token: String, environment: PushTokenEnvironment, appBundleID: String) async throws -> String
    func unregisterPushToken(_ token: String, environment: PushTokenEnvironment?) async throws
}

@MainActor
protocol SharedVisitRepository {
    func createInvites(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult]
    func inviteeUserIDs(sourceVisitID: String) async throws -> [String]
    func setInvitees(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult]
    func inbox(before: Date?, limit: Int) async throws -> [SharedVisitInvitation]
    func context(participantID: String, generation: Int) async throws -> SharedVisitInvitation?
    func resolveDestination(participantID: String, generation: Int) async throws -> SharedVisitDestination?
    func accept(_ draft: SharedVisitAcceptanceDraft) async throws -> SharedVisitAcceptanceResult
    func decline(participantID: String, generation: Int) async throws
    func companionContext(visitIDs: [String]) async throws -> [SharedVisitCompanion]
    func downloadPhotoData(bucket: String, path: String) async throws -> Data
    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws
    func markPhotoUploaded(photoID: String) async throws
}
