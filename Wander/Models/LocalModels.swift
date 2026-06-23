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

    init(localID: String, serverID: String? = nil, canonicalName: String, category: String, address: String? = nil, locality: String? = nil, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double, sourceProvider: String = "mapkit", sourceProviderPlaceID: String? = nil, confidence: Double? = nil, websiteURLString: String? = nil, phoneNumber: String? = nil, timeZoneIdentifier: String? = nil, actionLinksJSON: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.localID = localID
        self.serverID = serverID
        self.canonicalName = canonicalName
        self.category = category
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

    init(localID: String, serverID: String? = nil, userID: String, placeID: String, status: PlaceStatus, visibility: PlaceVisibility, note: String? = nil, ratingSignal: String? = nil, nearbyConfirmed: Bool = false, visitedAt: Date? = nil, savedAt: Date = .now, sourceType: String, sourceArtifactID: String? = nil, sourceUserPlaceID: String? = nil, attributionUserID: String? = nil, syncState: SyncState = .localOnly, localUpdatedAt: Date = .now, serverUpdatedAt: Date? = nil, lastSyncError: String? = nil, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.localID = localID
        self.serverID = serverID
        self.userID = userID
        self.placeID = placeID
        self.statusRaw = status.rawValue
        self.note = note
        self.ratingSignal = ratingSignal
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
