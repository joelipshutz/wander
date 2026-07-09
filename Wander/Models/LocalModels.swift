import Foundation
import SwiftData

@Model
final class LocalProfile {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var handle: String
    var searchHandle: String
    var displayName: String
    var avatarURL: String?
    var bio: String?
    var homeArea: String?
    var isPrivateProfile: Bool
    var defaultVisibilityRaw: String
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        handle: String,
        displayName: String,
        avatarURL: String? = nil,
        bio: String? = nil,
        homeArea: String? = nil,
        isPrivateProfile: Bool = false,
        defaultVisibility: PlaceVisibility = .followers,
        syncState: SyncState = .localOnly,
        localUpdatedAt: Date = .now,
        serverUpdatedAt: Date? = nil,
        lastSyncError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.handle = handle
        self.searchHandle = handle.lowercased()
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
        self.homeArea = homeArea
        self.isPrivateProfile = isPrivateProfile
        self.defaultVisibilityRaw = defaultVisibility.rawValue
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var defaultVisibility: PlaceVisibility { PlaceVisibility(rawValue: defaultVisibilityRaw) ?? .followers }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalFollow {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var followerUserID: String
    var followedUserID: String
    var sourceRaw: String
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date

    init(localID: String, serverID: String? = nil, followerUserID: String, followedUserID: String, source: FollowSource, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.localID = localID
        self.serverID = serverID
        self.followerUserID = followerUserID
        self.followedUserID = followedUserID
        self.sourceRaw = source.rawValue
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var id: String { serverID ?? localID }
    var source: FollowSource { FollowSource(rawValue: sourceRaw) ?? .profile }
}

@Model
final class LocalBlock {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var blockerUserID: String
    var blockedUserID: String
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date

    init(localID: String, serverID: String? = nil, blockerUserID: String, blockedUserID: String, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now) {
        self.localID = localID
        self.serverID = serverID
        self.blockerUserID = blockerUserID
        self.blockedUserID = blockedUserID
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
    }

    var id: String { serverID ?? localID }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalPlace {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var canonicalName: String
    var category: String
    var primaryCategory: String
    var subcategory: String?
    var categorySource: String
    var categoryConfidence: Double?
    var rawProviderType: String?
    var address: String?
    var locality: String?
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var sourceProvider: String
    var sourceProviderPlaceID: String?
    var confidence: Double?
    var websiteURLString: String?
    var phoneNumber: String?
    var timeZoneIdentifier: String?
    var actionLinksJSON: String?
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date

    init(localID: String, serverID: String? = nil, canonicalName: String, category: String, primaryCategory: String? = nil, subcategory: String? = nil, categorySource: String = PlaceCategorySource.provider.rawValue, categoryConfidence: Double? = nil, rawProviderType: String? = nil, address: String? = nil, locality: String? = nil, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double, sourceProvider: String = "mapkit", sourceProviderPlaceID: String? = nil, confidence: Double? = nil, websiteURLString: String? = nil, phoneNumber: String? = nil, timeZoneIdentifier: String? = nil, actionLinksJSON: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
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
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var id: String { serverID ?? localID }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalUserPlace {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var userID: String
    var placeID: String
    var statusRaw: String
    var note: String?
    var ratingSignal: String?
    var ratingScore: Double?
    var recommendedScore: Double?
    var recommendedCount: Int
    var categoryOverride: String?
    var subcategoryOverride: String?
    var categoryOverrideSource: String?
    var categoryOverrideConfidence: Double?
    var visibilityRaw: String
    var nearbyConfirmed: Bool
    var visitedAt: Date?
    var savedAt: Date
    var sourceType: String
    var sourceArtifactID: String?
    var sourceUserPlaceID: String?
    var attributionUserID: String?
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(localID: String, serverID: String? = nil, userID: String, placeID: String, status: PlaceStatus, visibility: PlaceVisibility, note: String? = nil, ratingSignal: String? = nil, ratingScore: Double? = nil, recommendedScore: Double? = nil, recommendedCount: Int = 0, categoryOverride: String? = nil, subcategoryOverride: String? = nil, categoryOverrideSource: String? = nil, categoryOverrideConfidence: Double? = nil, nearbyConfirmed: Bool = false, visitedAt: Date? = nil, savedAt: Date = .now, sourceType: String, sourceArtifactID: String? = nil, sourceUserPlaceID: String? = nil, attributionUserID: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.localID = localID
        self.serverID = serverID
        self.userID = userID
        self.placeID = placeID
        self.statusRaw = status.rawValue
        self.note = note
        self.ratingSignal = ratingSignal
        self.ratingScore = PlaceRating.normalized(ratingScore)
        self.recommendedScore = recommendedScore
        self.recommendedCount = recommendedCount
        self.categoryOverride = categoryOverride.map(WanderPlaceCategory.normalizedPrimaryCategory)
        self.subcategoryOverride = WanderPlaceCategory.normalizedSubcategory(subcategoryOverride)
        self.categoryOverrideSource = categoryOverrideSource
        self.categoryOverrideConfidence = categoryOverrideConfidence
        self.visibilityRaw = visibility.rawValue
        self.nearbyConfirmed = nearbyConfirmed
        self.visitedAt = visitedAt
        self.savedAt = savedAt
        self.sourceType = sourceType
        self.sourceArtifactID = sourceArtifactID
        self.sourceUserPlaceID = sourceUserPlaceID
        self.attributionUserID = attributionUserID
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var status: PlaceStatus { PlaceStatus(rawValue: statusRaw) ?? .wannaGo }
    var visibility: PlaceVisibility { PlaceVisibility(rawValue: visibilityRaw) ?? .followers }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalPlaceAttribute {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var userPlaceID: String
    var questionKey: String
    var valueType: String
    var valueJSON: String
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date

    init(localID: String, serverID: String? = nil, userPlaceID: String, questionKey: String, valueType: String, valueJSON: String, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.localID = localID
        self.serverID = serverID
        self.userPlaceID = userPlaceID
        self.questionKey = questionKey
        self.valueType = valueType
        self.valueJSON = valueJSON
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var id: String { serverID ?? localID }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalPlaceVisit {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var userPlaceID: String
    var visitedAt: Date
    var note: String?
    var ratingScore: Double?
    var attributeAnswersJSON: String
    var tagsJSON: String
    var backfilledFromUserPlace: Bool
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        userPlaceID: String,
        visitedAt: Date = .now,
        note: String? = nil,
        ratingScore: Double? = nil,
        attributeAnswersJSON: String = "[]",
        tags: [String] = [],
        backfilledFromUserPlace: Bool = false,
        syncState: SyncState = .localOnly,
        localUpdatedAt: Date = .now,
        serverUpdatedAt: Date? = nil,
        lastSyncError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.userPlaceID = userPlaceID
        self.visitedAt = visitedAt
        self.note = note
        self.ratingScore = PlaceRating.normalized(ratingScore)
        self.attributeAnswersJSON = attributeAnswersJSON
        self.tagsJSON = Self.encoded(tags)
        self.backfilledFromUserPlace = backfilledFromUserPlace
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
    var tags: [String] { (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? [] }

    func setDerivedTags(_ tags: [String]) {
        tagsJSON = Self.encoded(tags)
    }

    private static func encoded(_ tags: [String]) -> String {
        guard let data = try? JSONEncoder().encode(tags),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return encoded
    }
}

@Model
final class LocalVisitPhoto {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var visitID: String
    var storageBucket: String
    var storagePath: String?
    var localAssetRef: String?
    var remoteURLString: String?
    var contentType: String?
    var byteSize: Int?
    var width: Int?
    var height: Int?
    var capturedAt: Date?
    var sortOrder: Int
    var uploadStateRaw: String
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        visitID: String,
        storageBucket: String = "visit-photos",
        storagePath: String? = nil,
        localAssetRef: String? = nil,
        remoteURLString: String? = nil,
        contentType: String? = nil,
        byteSize: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        capturedAt: Date? = nil,
        sortOrder: Int = 0,
        uploadState: VisitPhotoUploadState = .pendingUpload,
        syncState: SyncState = .localOnly,
        localUpdatedAt: Date = .now,
        serverUpdatedAt: Date? = nil,
        lastSyncError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.visitID = visitID
        self.storageBucket = storageBucket
        self.storagePath = storagePath
        self.localAssetRef = localAssetRef
        self.remoteURLString = remoteURLString
        self.contentType = contentType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
        self.sortOrder = sortOrder
        self.uploadStateRaw = uploadState.rawValue
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var uploadState: VisitPhotoUploadState { VisitPhotoUploadState(rawValue: uploadStateRaw) ?? .pendingUpload }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

@Model
final class LocalSourceArtifact {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var userID: String
    var type: String
    var originalInput: String
    var normalizedInput: String
    var normalizedSourceHash: String
    var localAssetRef: String?
    var remoteAssetRef: String?
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var deletedAt: Date?

    init(localID: String, serverID: String? = nil, userID: String, type: String, originalInput: String, normalizedInput: String, normalizedSourceHash: String, localAssetRef: String? = nil, remoteAssetRef: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, deletedAt: Date? = nil) {
        self.localID = localID
        self.serverID = serverID
        self.userID = userID
        self.type = type
        self.originalInput = originalInput
        self.normalizedInput = normalizedInput
        self.normalizedSourceHash = normalizedSourceHash
        self.localAssetRef = localAssetRef
        self.remoteAssetRef = remoteAssetRef
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LocalExtractionJob {
    @Attribute(.unique) var localID: String
    var serverID: String?
    var sourceArtifactID: String
    var ownerUserID: String
    var sourceType: String
    var normalizedSourceHash: String
    var statusRaw: String
    var attemptCount: Int
    var providerStepsJSON: String
    var extractedCandidatesJSON: String
    var selectedPlaceID: String?
    var confidence: Double
    var errorCode: String?
    var errorMessage: String?
    var syncStateRaw: String
    var localUpdatedAt: Date
    var serverUpdatedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
    var updatedAt: Date

    init(localID: String, serverID: String? = nil, sourceArtifactID: String, ownerUserID: String, sourceType: String, normalizedSourceHash: String, status: ExtractionStatus, attemptCount: Int = 0, providerStepsJSON: String = "[]", extractedCandidatesJSON: String = "[]", selectedPlaceID: String? = nil, confidence: Double = 0, errorCode: String? = nil, errorMessage: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.localID = localID
        self.serverID = serverID
        self.sourceArtifactID = sourceArtifactID
        self.ownerUserID = ownerUserID
        self.sourceType = sourceType
        self.normalizedSourceHash = normalizedSourceHash
        self.statusRaw = status.rawValue
        self.attemptCount = attemptCount
        self.providerStepsJSON = providerStepsJSON
        self.extractedCandidatesJSON = extractedCandidatesJSON
        self.selectedPlaceID = selectedPlaceID
        self.confidence = confidence
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.syncStateRaw = syncState.rawValue
        self.localUpdatedAt = localUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ExtractionStatus { ExtractionStatus(rawValue: statusRaw) ?? .pending }
}

@Model
final class SyncOperation {
    @Attribute(.unique) var localID: String
    var entityName: String
    var entityID: String
    var operation: String
    var stateRaw: String
    var attemptCount: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(localID: String, entityName: String, entityID: String, operation: String, state: SyncState = .pendingCreate, attemptCount: Int = 0, lastError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.localID = localID
        self.entityName = entityName
        self.entityID = entityID
        self.operation = operation
        self.stateRaw = state.rawValue
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
