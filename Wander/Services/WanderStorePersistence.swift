import Foundation

struct WanderStorePersistence {
    let load: () -> WanderStoreSnapshot?
    let save: (WanderStoreSnapshot) -> Void

    @MainActor
    static let live = file(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("wander-store-v1.json")
    )

    static func file(url: URL) -> WanderStorePersistence {
        WanderStorePersistence(
            load: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(WanderStoreSnapshot.self, from: data)
            },
            save: { snapshot in
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(snapshot)
                    try data.write(to: url, options: [.atomic])
                } catch {
                    #if DEBUG
                    print("Wander local persistence failed: \(error)")
                    #endif
                }
            }
        )
    }
}

struct WanderStoreSnapshot: Codable, Equatable {
    static let currentSavedPlaceResetVersion = 1

    let currentUser: ProfileRecord
    let profiles: [ProfileRecord]
    let places: [PlaceRecord]
    let userPlaces: [UserPlaceRecord]
    let placeAttributes: [PlaceAttributeRecord]
    let follows: [FollowRecord]
    let blocks: [BlockRecord]
    let placeLists: [PlaceListRecord]?
    let placeListMembers: [PlaceListMemberRecord]?
    let placeListItems: [PlaceListItemRecord]?
    let unresolvedDrafts: [UnresolvedDraftRecord]
    let sourceArtifacts: [SourceArtifactRecord]
    let extractionJobs: [ExtractionJobRecord]
    let savedPlaceResetVersion: Int?
    let defaultVisibilityRaw: String
    let isPrivateProfile: Bool?
    let autoSaveListAddsToWant: Bool?
    let savedAt: Date

    @MainActor
    init(store: WanderStore) {
        currentUser = ProfileRecord(store.currentUser)
        profiles = store.profiles.map(ProfileRecord.init)
        places = store.places.map(PlaceRecord.init)
        userPlaces = store.userPlaces.map(UserPlaceRecord.init)
        placeAttributes = store.placeAttributes.map(PlaceAttributeRecord.init)
        follows = store.follows.map(FollowRecord.init)
        blocks = store.blocks.map(BlockRecord.init)
        placeLists = store.placeLists.map(PlaceListRecord.init)
        placeListMembers = store.placeListMembers.map(PlaceListMemberRecord.init)
        placeListItems = store.placeListItems.map(PlaceListItemRecord.init)
        unresolvedDrafts = store.unresolvedDrafts.map(UnresolvedDraftRecord.init)
        sourceArtifacts = store.sourceArtifacts.map(SourceArtifactRecord.init)
        extractionJobs = store.extractionJobs.map(ExtractionJobRecord.init)
        savedPlaceResetVersion = Self.currentSavedPlaceResetVersion
        defaultVisibilityRaw = store.defaultVisibility.rawValue
        isPrivateProfile = store.isPrivateProfile
        autoSaveListAddsToWant = store.autoSaveListAddsToWant
        savedAt = .now
    }

    func restoredState(contactProvider: FakeContactProvider) -> RestoredState {
        let shouldResetSavedPlaces = (savedPlaceResetVersion ?? 0) < Self.currentSavedPlaceResetVersion
        let restoredCurrentUser = currentUser.model()
        var restoredProfiles = profiles.map { $0.model() }
        restoredProfiles.removeAll { $0.id == restoredCurrentUser.id || $0.localID == restoredCurrentUser.localID }
        restoredProfiles.insert(restoredCurrentUser, at: 0)

        return RestoredState(
            currentUser: restoredCurrentUser,
            profiles: restoredProfiles,
            places: shouldResetSavedPlaces ? [] : places.map { $0.model() },
            userPlaces: shouldResetSavedPlaces ? [] : userPlaces.map { $0.model() },
            placeAttributes: shouldResetSavedPlaces ? [] : placeAttributes.map { $0.model() },
            follows: follows.map { $0.model() },
            blocks: blocks.map { $0.model() },
            placeLists: placeLists?.map { $0.model() } ?? [],
            placeListMembers: placeListMembers?.map { $0.model() } ?? [],
            placeListItems: shouldResetSavedPlaces ? [] : placeListItems?.map { $0.model() } ?? [],
            unresolvedDrafts: shouldResetSavedPlaces ? [] : unresolvedDrafts.map { $0.model() },
            sourceArtifacts: shouldResetSavedPlaces ? [] : sourceArtifacts.map { $0.model() },
            extractionJobs: shouldResetSavedPlaces ? [] : extractionJobs.map { $0.model() },
            contactProvider: contactProvider,
            defaultVisibility: PlaceVisibility(rawValue: defaultVisibilityRaw) ?? restoredCurrentUser.defaultVisibility,
            isPrivateProfile: isPrivateProfile ?? restoredCurrentUser.isPrivateProfile,
            autoSaveListAddsToWant: autoSaveListAddsToWant ?? true,
            didApplySavedPlaceReset: shouldResetSavedPlaces
        )
    }

    struct RestoredState {
        let currentUser: LocalProfile
        let profiles: [LocalProfile]
        let places: [LocalPlace]
        let userPlaces: [LocalUserPlace]
        let placeAttributes: [LocalPlaceAttribute]
        let follows: [LocalFollow]
        let blocks: [LocalBlock]
        let placeLists: [LocalPlaceList]
        let placeListMembers: [LocalPlaceListMember]
        let placeListItems: [LocalPlaceListItem]
        let unresolvedDrafts: [UnresolvedDraft]
        let sourceArtifacts: [LocalSourceArtifact]
        let extractionJobs: [LocalExtractionJob]
        let contactProvider: FakeContactProvider
        let defaultVisibility: PlaceVisibility
        let isPrivateProfile: Bool
        let autoSaveListAddsToWant: Bool
        let didApplySavedPlaceReset: Bool
    }

    struct ProfileRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let handle: String
        let displayName: String
        let avatarURL: String?
        let bio: String?
        let homeArea: String?
        let isPrivateProfile: Bool?
        let defaultVisibilityRaw: String
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        init(_ profile: LocalProfile) {
            localID = profile.localID
            serverID = profile.serverID
            handle = profile.handle
            displayName = profile.displayName
            avatarURL = profile.avatarURL
            bio = profile.bio
            homeArea = profile.homeArea
            isPrivateProfile = profile.isPrivateProfile
            defaultVisibilityRaw = profile.defaultVisibilityRaw
            syncStateRaw = profile.syncStateRaw
            localUpdatedAt = profile.localUpdatedAt
            serverUpdatedAt = profile.serverUpdatedAt
            lastSyncError = profile.lastSyncError
            createdAt = profile.createdAt
            updatedAt = profile.updatedAt
            deletedAt = profile.deletedAt
        }

        func model() -> LocalProfile {
            LocalProfile(
                localID: localID,
                serverID: serverID,
                handle: handle,
                displayName: displayName,
                avatarURL: avatarURL,
                bio: bio,
                homeArea: homeArea,
                isPrivateProfile: isPrivateProfile ?? false,
                defaultVisibility: PlaceVisibility(rawValue: defaultVisibilityRaw) ?? .followers,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
        }
    }

    struct PlaceRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
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
        let sourceProviderPlaceID: String?
        let confidence: Double?
        let websiteURLString: String?
        let phoneNumber: String?
        let timeZoneIdentifier: String?
        let actionLinksJSON: String?
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date

        init(_ place: LocalPlace) {
            localID = place.localID
            serverID = place.serverID
            canonicalName = place.canonicalName
            category = place.category
            primaryCategory = place.primaryCategory
            subcategory = place.subcategory
            categorySource = place.categorySource
            categoryConfidence = place.categoryConfidence
            rawProviderType = place.rawProviderType
            address = place.address
            locality = place.locality
            region = place.region
            country = place.country
            latitude = place.latitude
            longitude = place.longitude
            sourceProvider = place.sourceProvider
            sourceProviderPlaceID = place.sourceProviderPlaceID
            confidence = place.confidence
            websiteURLString = place.websiteURLString
            phoneNumber = place.phoneNumber
            timeZoneIdentifier = place.timeZoneIdentifier
            actionLinksJSON = place.actionLinksJSON
            syncStateRaw = place.syncStateRaw
            localUpdatedAt = place.localUpdatedAt
            serverUpdatedAt = place.serverUpdatedAt
            lastSyncError = place.lastSyncError
            createdAt = place.createdAt
            updatedAt = place.updatedAt
        }

        func model() -> LocalPlace {
            LocalPlace(
                localID: localID,
                serverID: serverID,
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
                sourceProvider: sourceProvider,
                sourceProviderPlaceID: sourceProviderPlaceID,
                confidence: confidence,
                websiteURLString: websiteURLString,
                phoneNumber: phoneNumber,
                timeZoneIdentifier: timeZoneIdentifier,
                actionLinksJSON: actionLinksJSON,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    struct UserPlaceRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let userID: String
        let placeID: String
        let statusRaw: String
        let note: String?
        let ratingSignal: String?
        let ratingScore: Int?
        let recommendedScore: Double?
        let recommendedCount: Int?
        let categoryOverride: String?
        let subcategoryOverride: String?
        let categoryOverrideSource: String?
        let categoryOverrideConfidence: Double?
        let visibilityRaw: String
        let nearbyConfirmed: Bool
        let visitedAt: Date?
        let savedAt: Date
        let sourceType: String
        let sourceArtifactID: String?
        let sourceUserPlaceID: String?
        let attributionUserID: String?
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        init(_ userPlace: LocalUserPlace) {
            localID = userPlace.localID
            serverID = userPlace.serverID
            userID = userPlace.userID
            placeID = userPlace.placeID
            statusRaw = userPlace.statusRaw
            note = userPlace.note
            ratingSignal = userPlace.ratingSignal
            ratingScore = userPlace.ratingScore
            recommendedScore = userPlace.recommendedScore
            recommendedCount = userPlace.recommendedCount
            categoryOverride = userPlace.categoryOverride
            subcategoryOverride = userPlace.subcategoryOverride
            categoryOverrideSource = userPlace.categoryOverrideSource
            categoryOverrideConfidence = userPlace.categoryOverrideConfidence
            visibilityRaw = userPlace.visibilityRaw
            nearbyConfirmed = userPlace.nearbyConfirmed
            visitedAt = userPlace.visitedAt
            savedAt = userPlace.savedAt
            sourceType = userPlace.sourceType
            sourceArtifactID = userPlace.sourceArtifactID
            sourceUserPlaceID = userPlace.sourceUserPlaceID
            attributionUserID = userPlace.attributionUserID
            syncStateRaw = userPlace.syncStateRaw
            localUpdatedAt = userPlace.localUpdatedAt
            serverUpdatedAt = userPlace.serverUpdatedAt
            lastSyncError = userPlace.lastSyncError
            createdAt = userPlace.createdAt
            updatedAt = userPlace.updatedAt
            deletedAt = userPlace.deletedAt
        }

        func model() -> LocalUserPlace {
            LocalUserPlace(
                localID: localID,
                serverID: serverID,
                userID: userID,
                placeID: placeID,
                status: PlaceStatus(rawValue: statusRaw) ?? .wannaGo,
                visibility: PlaceVisibility(rawValue: visibilityRaw) ?? .followers,
                note: note,
                ratingSignal: ratingSignal,
                ratingScore: ratingScore,
                recommendedScore: recommendedScore,
                recommendedCount: recommendedCount ?? 0,
                categoryOverride: categoryOverride,
                subcategoryOverride: subcategoryOverride,
                categoryOverrideSource: categoryOverrideSource,
                categoryOverrideConfidence: categoryOverrideConfidence,
                nearbyConfirmed: nearbyConfirmed,
                visitedAt: visitedAt,
                savedAt: savedAt,
                sourceType: sourceType,
                sourceArtifactID: sourceArtifactID,
                sourceUserPlaceID: sourceUserPlaceID,
                attributionUserID: attributionUserID,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
        }
    }

    struct PlaceAttributeRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let userPlaceID: String
        let questionKey: String
        let valueType: String
        let valueJSON: String
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date

        init(_ attribute: LocalPlaceAttribute) {
            localID = attribute.localID
            serverID = attribute.serverID
            userPlaceID = attribute.userPlaceID
            questionKey = attribute.questionKey
            valueType = attribute.valueType
            valueJSON = attribute.valueJSON
            syncStateRaw = attribute.syncStateRaw
            localUpdatedAt = attribute.localUpdatedAt
            serverUpdatedAt = attribute.serverUpdatedAt
            lastSyncError = attribute.lastSyncError
            createdAt = attribute.createdAt
            updatedAt = attribute.updatedAt
        }

        func model() -> LocalPlaceAttribute {
            LocalPlaceAttribute(
                localID: localID,
                serverID: serverID,
                userPlaceID: userPlaceID,
                questionKey: questionKey,
                valueType: valueType,
                valueJSON: valueJSON,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    struct FollowRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let followerUserID: String
        let followedUserID: String
        let sourceRaw: String
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date

        init(_ follow: LocalFollow) {
            localID = follow.localID
            serverID = follow.serverID
            followerUserID = follow.followerUserID
            followedUserID = follow.followedUserID
            sourceRaw = follow.sourceRaw
            syncStateRaw = follow.syncStateRaw
            localUpdatedAt = follow.localUpdatedAt
            serverUpdatedAt = follow.serverUpdatedAt
            lastSyncError = follow.lastSyncError
            createdAt = follow.createdAt
            updatedAt = follow.updatedAt
        }

        func model() -> LocalFollow {
            LocalFollow(
                localID: localID,
                serverID: serverID,
                followerUserID: followerUserID,
                followedUserID: followedUserID,
                source: FollowSource(rawValue: sourceRaw) ?? .profile,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    struct BlockRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let blockerUserID: String
        let blockedUserID: String
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date

        init(_ block: LocalBlock) {
            localID = block.localID
            serverID = block.serverID
            blockerUserID = block.blockerUserID
            blockedUserID = block.blockedUserID
            syncStateRaw = block.syncStateRaw
            localUpdatedAt = block.localUpdatedAt
            serverUpdatedAt = block.serverUpdatedAt
            lastSyncError = block.lastSyncError
            createdAt = block.createdAt
        }

        func model() -> LocalBlock {
            LocalBlock(
                localID: localID,
                serverID: serverID,
                blockerUserID: blockerUserID,
                blockedUserID: blockedUserID,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt
            )
        }
    }

    struct PlaceListRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let ownerUserID: String
        let name: String
        let description: String
        let visibilityRaw: String
        let syncStateRaw: String
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        init(_ list: LocalPlaceList) {
            localID = list.localID
            serverID = list.serverID
            ownerUserID = list.ownerUserID
            name = list.name
            description = list.description
            visibilityRaw = list.visibilityRaw
            syncStateRaw = list.syncStateRaw
            createdAt = list.createdAt
            updatedAt = list.updatedAt
            deletedAt = list.deletedAt
        }

        func model() -> LocalPlaceList {
            LocalPlaceList(
                localID: localID,
                serverID: serverID,
                ownerUserID: ownerUserID,
                name: name,
                description: description,
                visibility: PlaceListVisibility(rawValue: visibilityRaw) ?? .followers,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
        }
    }

    struct PlaceListMemberRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let listID: String
        let userID: String
        let roleRaw: String
        let createdAt: Date
        let deletedAt: Date?

        init(_ member: LocalPlaceListMember) {
            localID = member.localID
            serverID = member.serverID
            listID = member.listID
            userID = member.userID
            roleRaw = member.roleRaw
            createdAt = member.createdAt
            deletedAt = member.deletedAt
        }

        func model() -> LocalPlaceListMember {
            LocalPlaceListMember(
                localID: localID,
                serverID: serverID,
                listID: listID,
                userID: userID,
                role: PlaceListRole(rawValue: roleRaw) ?? .collaborator,
                createdAt: createdAt,
                deletedAt: deletedAt
            )
        }
    }

    struct PlaceListItemRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let listID: String
        let placeID: String
        let ownerUserPlaceID: String?
        let sourceUserPlaceID: String?
        let addedByUserID: String
        let syncStateRaw: String
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        init(_ item: LocalPlaceListItem) {
            localID = item.localID
            serverID = item.serverID
            listID = item.listID
            placeID = item.placeID
            ownerUserPlaceID = item.ownerUserPlaceID
            sourceUserPlaceID = item.sourceUserPlaceID
            addedByUserID = item.addedByUserID
            syncStateRaw = item.syncStateRaw
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            deletedAt = item.deletedAt
        }

        func model() -> LocalPlaceListItem {
            LocalPlaceListItem(
                localID: localID,
                serverID: serverID,
                listID: listID,
                placeID: placeID,
                ownerUserPlaceID: ownerUserPlaceID,
                sourceUserPlaceID: sourceUserPlaceID,
                addedByUserID: addedByUserID,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
        }
    }

    struct UnresolvedDraftRecord: Codable, Equatable {
        let id: String
        let sourceTypeRaw: String
        let title: String
        let message: String
        let sourceArtifactID: String?
        let extractionJobID: String?
        let createdAt: Date

        init(_ draft: UnresolvedDraft) {
            id = draft.id
            sourceTypeRaw = draft.sourceType.rawValue
            title = draft.title
            message = draft.message
            sourceArtifactID = draft.sourceArtifactID
            extractionJobID = draft.extractionJobID
            createdAt = draft.createdAt
        }

        func model() -> UnresolvedDraft {
            UnresolvedDraft(
                id: id,
                sourceType: AddSourceType(rawValue: sourceTypeRaw) ?? .manual,
                title: title,
                message: message,
                sourceArtifactID: sourceArtifactID,
                extractionJobID: extractionJobID,
                createdAt: createdAt
            )
        }
    }

    struct SourceArtifactRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let userID: String
        let type: String
        let originalInput: String
        let normalizedInput: String
        let normalizedSourceHash: String
        let localAssetRef: String?
        let remoteAssetRef: String?
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let deletedAt: Date?

        init(_ artifact: LocalSourceArtifact) {
            localID = artifact.localID
            serverID = artifact.serverID
            userID = artifact.userID
            type = artifact.type
            originalInput = artifact.originalInput
            normalizedInput = artifact.normalizedInput
            normalizedSourceHash = artifact.normalizedSourceHash
            localAssetRef = artifact.localAssetRef
            remoteAssetRef = artifact.remoteAssetRef
            syncStateRaw = artifact.syncStateRaw
            localUpdatedAt = artifact.localUpdatedAt
            serverUpdatedAt = artifact.serverUpdatedAt
            lastSyncError = artifact.lastSyncError
            createdAt = artifact.createdAt
            deletedAt = artifact.deletedAt
        }

        func model() -> LocalSourceArtifact {
            LocalSourceArtifact(
                localID: localID,
                serverID: serverID,
                userID: userID,
                type: type,
                originalInput: originalInput,
                normalizedInput: normalizedInput,
                normalizedSourceHash: normalizedSourceHash,
                localAssetRef: localAssetRef,
                remoteAssetRef: remoteAssetRef,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                deletedAt: deletedAt
            )
        }
    }

    struct ExtractionJobRecord: Codable, Equatable {
        let localID: String
        let serverID: String?
        let sourceArtifactID: String
        let ownerUserID: String
        let sourceType: String
        let normalizedSourceHash: String
        let statusRaw: String
        let attemptCount: Int
        let providerStepsJSON: String
        let extractedCandidatesJSON: String
        let selectedPlaceID: String?
        let confidence: Double
        let errorCode: String?
        let errorMessage: String?
        let syncStateRaw: String
        let localUpdatedAt: Date
        let serverUpdatedAt: Date?
        let lastSyncError: String?
        let createdAt: Date
        let updatedAt: Date

        init(_ job: LocalExtractionJob) {
            localID = job.localID
            serverID = job.serverID
            sourceArtifactID = job.sourceArtifactID
            ownerUserID = job.ownerUserID
            sourceType = job.sourceType
            normalizedSourceHash = job.normalizedSourceHash
            statusRaw = job.statusRaw
            attemptCount = job.attemptCount
            providerStepsJSON = job.providerStepsJSON
            extractedCandidatesJSON = job.extractedCandidatesJSON
            selectedPlaceID = job.selectedPlaceID
            confidence = job.confidence
            errorCode = job.errorCode
            errorMessage = job.errorMessage
            syncStateRaw = job.syncStateRaw
            localUpdatedAt = job.localUpdatedAt
            serverUpdatedAt = job.serverUpdatedAt
            lastSyncError = job.lastSyncError
            createdAt = job.createdAt
            updatedAt = job.updatedAt
        }

        func model() -> LocalExtractionJob {
            LocalExtractionJob(
                localID: localID,
                serverID: serverID,
                sourceArtifactID: sourceArtifactID,
                ownerUserID: ownerUserID,
                sourceType: sourceType,
                normalizedSourceHash: normalizedSourceHash,
                status: ExtractionStatus(rawValue: statusRaw) ?? .pending,
                attemptCount: attemptCount,
                providerStepsJSON: providerStepsJSON,
                extractedCandidatesJSON: extractedCandidatesJSON,
                selectedPlaceID: selectedPlaceID,
                confidence: confidence,
                errorCode: errorCode,
                errorMessage: errorMessage,
                syncState: SyncState(rawValue: syncStateRaw) ?? .localOnly,
                localUpdatedAt: localUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                lastSyncError: lastSyncError,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }
}
