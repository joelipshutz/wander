import CoreLocation
import Foundation

struct UnresolvedDraft: Identifiable, Equatable {
    let id: String
    let sourceType: AddSourceType
    let title: String
    let message: String
    let sourceArtifactID: String?
    let extractionJobID: String?
    let createdAt: Date
}

private extension UnresolvedDraft {
    var remoteExtractionJobID: String? {
        guard let extractionJobID,
              UUID(uuidString: extractionJobID) != nil
        else { return nil }
        return extractionJobID
    }
}

struct AuthGateCopy: Equatable {
    let title: String
    let message: String
    let primaryAction: String
    let secondaryAction: String?
}

private enum OwnPlaceSyncTrigger: String {
    case directSave = "direct_save"
    case failedRetry = "failed_retry"
    case signedInBackfill = "signed_in_backfill"
    case providerEnrichment = "provider_enrichment"
}

private enum OwnPlaceSyncOutcome {
    case succeeded
    case failed
    case skipped
}

struct RemoveSaveResult: Equatable {
    let userPlaceID: String
    let syncState: SyncState
}

struct LocalVisitPhotoInput: Equatable {
    let localAssetRef: String?
    let contentType: String
    let byteSize: Int
    let width: Int?
    let height: Int?
    let capturedAt: Date?

    init(
        localAssetRef: String?,
        contentType: String,
        byteSize: Int,
        width: Int?,
        height: Int?,
        capturedAt: Date? = nil
    ) {
        self.localAssetRef = localAssetRef
        self.contentType = contentType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }
}

private struct LocalRemoveSaveChange {
    let userPlaceID: String
    let removedUserPlaceIDs: [String]
    let remoteUserPlaceIDs: [String]
    let syncState: SyncState
}

struct ProfileStats: Equatable {
    let been: Int
    let checkIns: Int
    let wanna: Int
    let friends: Int

    init(been: Int, checkIns: Int? = nil, wanna: Int, friends: Int) {
        self.been = been
        self.checkIns = checkIns ?? been
        self.wanna = wanna
        self.friends = friends
    }
}

struct CurrentUserCalendarProjection {
    let visiblePlaces: [VisiblePlace]
    let visits: [LocalPlaceVisit]
    let isAuthoritative: Bool

    var places: [LocalPlace] {
        visiblePlaces.map(\.place)
    }

    var userPlaces: [LocalUserPlace] {
        visiblePlaces.map(\.userPlace)
    }

    var attributes: [LocalPlaceAttribute] {
        visiblePlaces.flatMap(\.attributes)
    }

    func profileStats(currentUserID: String, friends: Int) -> ProfileStats {
        let groups = VisiblePlaceGrouping.groups(
            from: visiblePlaces,
            currentUserID: currentUserID
        )
        let visitsByUserPlaceID = Dictionary(
            grouping: visits.filter { $0.deletedAt == nil },
            by: \.userPlaceID
        )
        let ownerPlacesByGroup = groups.map { group in
            group.places.filter {
                $0.owner.id == currentUserID && $0.userPlace.deletedAt == nil
            }
        }
        let checkedInGroups = ownerPlacesByGroup.compactMap { ownerPlaces -> [VisiblePlace]? in
            let checkedInPlaces = ownerPlaces.filter { $0.userPlace.status == .been }
            return checkedInPlaces.isEmpty ? nil : checkedInPlaces
        }
        let checkInCount = checkedInGroups.reduce(into: 0) { count, checkedInPlaces in
            let referenceIDs = checkedInPlaces.reduce(into: Set<String>()) {
                result, checkedInPlace in
                result.formUnion(
                    [
                        checkedInPlace.userPlace.id,
                        checkedInPlace.userPlace.localID,
                        checkedInPlace.userPlace.serverID
                    ].compactMap { $0 }
                )
            }
            let matchingVisitIDs = referenceIDs.reduce(into: Set<String>()) {
                result, referenceID in
                result.formUnion((visitsByUserPlaceID[referenceID] ?? []).map(\.id))
            }
            count += max(matchingVisitIDs.count, 1)
        }

        return ProfileStats(
            been: checkedInGroups.count,
            checkIns: checkInCount,
            wanna: ownerPlacesByGroup.filter { ownerPlaces in
                !ownerPlaces.contains { $0.userPlace.status == .been }
                    && ownerPlaces.contains { $0.userPlace.status == .wannaGo }
            }.count,
            friends: friends
        )
    }
}

struct SmartFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let query: String
}

@MainActor
final class WanderStore: ObservableObject {
    @Published private(set) var currentUser: LocalProfile
    @Published private(set) var profiles: [LocalProfile]
    @Published private(set) var places: [LocalPlace]
    @Published private(set) var userPlaces: [LocalUserPlace]
    @Published private(set) var placeAttributes: [LocalPlaceAttribute]
    @Published private(set) var placeVisits: [LocalPlaceVisit]
    @Published private(set) var visitPhotos: [LocalVisitPhoto]
    @Published private(set) var sharedVisitInvitations: [SharedVisitInvitation]
    @Published private(set) var pendingSharedVisitInvites: [PendingSharedVisitInvite]
    @Published private(set) var sharedVisitCompanionsByVisitID: [String: [SharedVisitCompanion]] = [:]
    private(set) var sharedVisitInboxUserID: String?
    @Published private(set) var follows: [LocalFollow]
    @Published private(set) var blocks: [LocalBlock]
    @Published private(set) var mutes: [LocalMute]
    @Published private(set) var placeLists: [LocalPlaceList]
    @Published private(set) var placeListMembers: [LocalPlaceListMember]
    @Published private(set) var placeListItems: [LocalPlaceListItem]
    @Published private(set) var unresolvedDrafts: [UnresolvedDraft] = []
    @Published private(set) var saveStreakDatesByUserID: [String: [Date]] = [:]
    @Published private(set) var saveStreakRecoveryDatesByUserID: [String: [Date]] = [:]
    @Published private(set) var saveStreakCelebration: SaveStreakCelebration?
    @Published private(set) var isSaveFlowPresented = false
    private var activeSaveFlowPresentationLayers: Set<SaveFlowPresentationLayer> = []

    var wannaGoReminderItems: [WannaGoReminderItem] {
        var remindersByPlaceID: [String: WannaGoReminderItem] = [:]

        for userPlace in userPlaces where userPlace.userID == currentUser.id
            && userPlace.status == .wannaGo
            && userPlace.deletedAt == nil {
            guard let plannedDate = userPlace.plannedDate,
                  let place = places.first(where: { place in
                      place.id == userPlace.placeID
                          || place.localID == userPlace.placeID
                          || place.serverID == userPlace.placeID
                  })
            else { continue }

            let routePlaceID = place.serverID ?? place.id
            remindersByPlaceID[routePlaceID] = WannaGoReminderItem(
                userPlaceID: userPlace.localID,
                placeID: routePlaceID,
                placeName: place.canonicalName,
                plannedDate: plannedDate
            )
        }

        for visiblePlace in remoteVisiblePlaceCache where visiblePlace.owner.id == currentUser.id
            && visiblePlace.userPlace.status == .wannaGo
            && visiblePlace.userPlace.deletedAt == nil {
            let routePlaceID = visiblePlace.place.serverID ?? visiblePlace.place.id
            guard remindersByPlaceID[routePlaceID] == nil,
                  let plannedDate = visiblePlace.userPlace.plannedDate
            else { continue }

            remindersByPlaceID[routePlaceID] = WannaGoReminderItem(
                userPlaceID: visiblePlace.userPlace.id,
                placeID: routePlaceID,
                placeName: visiblePlace.place.canonicalName,
                plannedDate: plannedDate
            )
        }

        return remindersByPlaceID.values.sorted { lhs, rhs in
            if lhs.plannedDate == rhs.plannedDate {
                return lhs.userPlaceID < rhs.userPlaceID
            }
            return lhs.plannedDate < rhs.plannedDate
        }
    }

    private var placeListSyncTask: (id: UUID, task: Task<Int, Never>)?
    private var individualPlaceListSyncTasks: [String: (id: UUID, task: Task<Bool, Never>)] = [:]
    private var visitPhotoUploadTask: (
        id: UUID,
        userID: String,
        task: Task<Int, Never>
    )?
    private var sharedVisitInboxTask: (
        id: UUID,
        userID: String,
        task: Task<[SharedVisitInvitation], Error>
    )?
    private var currentUserCalendarRefreshTask: (
        id: UUID,
        userID: String,
        task: Task<Bool, Never>
    )?
    private struct CurrentUserCalendarLocalFingerprint: Equatable {
        let userPlaces: [WanderStoreSnapshot.UserPlaceRecord]
        let attributes: [WanderStoreSnapshot.PlaceAttributeRecord]
        let visits: [WanderStoreSnapshot.PlaceVisitRecord]
    }
    @Published private(set) var isRefreshingCurrentUserCalendarData = false
    @Published private(set) var currentUserCalendarHydrationRevision: UInt64 = 0
    private var authoritativeCalendarUserID: String?
    private var currentUserCalendarLocalFingerprint: CurrentUserCalendarLocalFingerprint?
    private var currentUserCalendarLocalMutationRevision: UInt64 = 0
    private var isApplyingAcceptedCurrentUserCalendarHydration = false
    @Published private(set) var sourceArtifacts: [LocalSourceArtifact] = []
    @Published private(set) var extractionJobs: [LocalExtractionJob] = []
    @Published private(set) var remoteVisiblePlaceCache: [VisiblePlace] = [] {
        didSet {
            invalidatePresentationCaches()
        }
    }
    private(set) var lastRemoteError: String? = nil {
        willSet {
            guard newValue != lastRemoteError else { return }
            objectWillChange.send()
        }
    }
    @Published private(set) var followedFeedPage: FollowedFeedPage?
    @Published private(set) var feedLoadState: FeedLoadState = .idle
    @Published private(set) var lastFeedRefreshAt: Date?
    @Published private(set) var activityEngagementByID: [String: ActivityEngagementSummary] = [:]
    @Published private(set) var activityCommentsByID: [String: [ActivityComment]] = [:]
    @Published private(set) var placeActivityEngagementMatches: [PlaceActivityEngagementMatch] = []
    @Published private(set) var activityEngagementErrorByID: [String: String] = [:]
    private var pendingActivityLikeIDs = Set<String>()
    private var pendingActivityCommentDeletionIDs = Set<String>()
    @Published private(set) var lastDiscoverFilters = DiscoverFilters(query: "")
    private(set) var lastDiscoverParseSource: DiscoverParseSource = .deterministic
    @Published private(set) var discoverPeopleRecommendationsState: DiscoverPeopleRecommendationsState = .idle
    var defaultVisibility: PlaceVisibility {
        willSet {
            guard newValue != defaultVisibility else { return }
            objectWillChange.send()
        }
        didSet {
            guard oldValue != defaultVisibility else { return }
            currentUser.defaultVisibilityRaw = defaultVisibility.rawValue
            currentUser.updatedAt = .now
            currentUser.localUpdatedAt = .now
            persist()
        }
    }
    var isPrivateProfile: Bool {
        willSet {
            guard newValue != isPrivateProfile else { return }
            objectWillChange.send()
        }
        didSet {
            guard oldValue != isPrivateProfile else { return }
            currentUser.isPrivateProfile = isPrivateProfile
            currentUser.updatedAt = .now
            currentUser.localUpdatedAt = .now
            persist()
        }
    }
    var autoSaveListAddsToWant: Bool {
        willSet {
            guard newValue != autoSaveListAddsToWant else { return }
            objectWillChange.send()
        }
        didSet {
            guard oldValue != autoSaveListAddsToWant else { return }
            persist()
        }
    }
    var defaultMapFilter: MapSource {
        willSet {
            guard newValue != defaultMapFilter else { return }
            objectWillChange.send()
        }
        didSet {
            guard oldValue != defaultMapFilter else { return }
            persist()
        }
    }

    let contactProvider: any ContactProvider

    private let visibilityPolicy = VisibilityPolicy()
    private let parser: any LLMFilterParser
    private let placeResolver: PlaceCandidateResolving
    private let analytics: AnalyticsClient
    var productAnalytics: AnalyticsClient { analytics }
    private let persistence: WanderStorePersistence?
    private var persistenceDeferralDepth = 0
    private var persistenceRequestedWhileDeferred = false
    private var visiblePlacesCache: [(filters: PlaceFilters, places: [VisiblePlace])] = []
    private var visiblePlaceCountsByOwnerIDCache: [String: Int]?
    private var visiblePlacesByListIDCache: (listIDs: [String], placesByListID: [String: [VisiblePlace]])?
    private var firstVisitPhotosByPlaceIDCache: (
        revision: UInt64,
        userID: String,
        photos: [String: LocalVisitPhoto]
    )?
    private(set) var presentationRevision: UInt64 = 0
    private(set) var firstVisitPhotoIndexBuildCount = 0

    private struct RankedVisiblePlace {
        let index: Int
        let visiblePlace: VisiblePlace
    }

    private struct VisiblePlaceListLookup {
        var byUserPlaceID: [String: RankedVisiblePlace]
        var byPlaceID: [String: RankedVisiblePlace]
        let knownPlaceIDs: Set<String>
    }

    private struct LocalVisiblePlaceProjection {
        let places: [VisiblePlace]
        let listLookup: VisiblePlaceListLookup
    }

    private struct VisitReconciliationIndex {
        private let canonicalUserPlaceIDByReferenceID: [String: String]
        private var visitsByCanonicalUserPlaceID: [String: [LocalPlaceVisit]]
        private let attributesByCanonicalUserPlaceID: [String: [LocalPlaceAttribute]]

        init(
            userPlaces: [LocalUserPlace],
            visits: [LocalPlaceVisit],
            attributes: [LocalPlaceAttribute]
        ) {
            var canonicalUserPlaceIDByReferenceID: [String: String] = [:]
            canonicalUserPlaceIDByReferenceID.reserveCapacity(userPlaces.count * 2)
            for userPlace in userPlaces {
                var referenceIDs = [userPlace.id, userPlace.localID]
                if let serverID = userPlace.serverID {
                    referenceIDs.append(serverID)
                }
                let canonicalID = referenceIDs.compactMap { canonicalUserPlaceIDByReferenceID[$0] }.first
                    ?? userPlace.id
                for referenceID in referenceIDs where canonicalUserPlaceIDByReferenceID[referenceID] == nil {
                    canonicalUserPlaceIDByReferenceID[referenceID] = canonicalID
                }
            }

            self.canonicalUserPlaceIDByReferenceID = canonicalUserPlaceIDByReferenceID

            var visitsByCanonicalUserPlaceID: [String: [LocalPlaceVisit]] = [:]
            visitsByCanonicalUserPlaceID.reserveCapacity(userPlaces.count)
            for visit in visits {
                let canonicalID = canonicalUserPlaceIDByReferenceID[visit.userPlaceID] ?? visit.userPlaceID
                visitsByCanonicalUserPlaceID[canonicalID, default: []].append(visit)
            }
            self.visitsByCanonicalUserPlaceID = visitsByCanonicalUserPlaceID

            var attributesByCanonicalUserPlaceID: [String: [LocalPlaceAttribute]] = [:]
            attributesByCanonicalUserPlaceID.reserveCapacity(userPlaces.count)
            for attribute in attributes {
                let canonicalID = canonicalUserPlaceIDByReferenceID[attribute.userPlaceID] ?? attribute.userPlaceID
                attributesByCanonicalUserPlaceID[canonicalID, default: []].append(attribute)
            }
            self.attributesByCanonicalUserPlaceID = attributesByCanonicalUserPlaceID
        }

        func visits(for userPlace: LocalUserPlace) -> [LocalPlaceVisit] {
            visitsByCanonicalUserPlaceID[canonicalID(for: userPlace), default: []]
        }

        func activeVisits(for userPlace: LocalUserPlace) -> [LocalPlaceVisit] {
            visits(for: userPlace).filter { $0.deletedAt == nil }
        }

        func attributeDrafts(for userPlace: LocalUserPlace) -> [PlaceAttributeDraft] {
            attributesByCanonicalUserPlaceID[canonicalID(for: userPlace), default: []]
                .sorted { $0.questionKey < $1.questionKey }
                .map { attribute in
                    PlaceAttributeDraft(
                        questionKey: attribute.questionKey,
                        valueType: attribute.valueType,
                        valueJSON: attribute.valueJSON
                    )
                }
        }

        mutating func append(_ visit: LocalPlaceVisit) {
            let canonicalID = canonicalUserPlaceIDByReferenceID[visit.userPlaceID] ?? visit.userPlaceID
            visitsByCanonicalUserPlaceID[canonicalID, default: []].append(visit)
        }

        private func canonicalID(for userPlace: LocalUserPlace) -> String {
            canonicalUserPlaceIDByReferenceID[userPlace.id]
                ?? canonicalUserPlaceIDByReferenceID[userPlace.localID]
                ?? userPlace.id
        }
    }

    private var visiblePlaceListLookupCache: VisiblePlaceListLookup?
    private var visibleListFallbackResolutionCount = 0
    #if DEBUG
    private(set) var visiblePlaceProjectionBuildCount = 0
    private(set) var visiblePlaceOwnerCountBuildCount = 0
    #endif
    private struct CachedDiscoverParse {
        let filters: DiscoverFilters
        let source: DiscoverParseSource
    }

    private var discoverParseCache: [String: CachedDiscoverParse] = [:]
    private var discoverParseCacheOrder: [String] = []
    private static let discoverParseCacheCapacity = 50
    private(set) var providerCategoryEnrichmentAttemptedAtByKey: [String: Date] = [:]
    private static let defaultRemoteViewport = MapViewport(
        minLatitude: 33.95,
        minLongitude: -118.45,
        maxLatitude: 34.20,
        maxLongitude: -118.12
    )

    let smartFilters: [SmartFilter] = [
        SmartFilter(id: "hikes-la", title: "hikes in LA", query: "hikes in LA"),
        SmartFilter(id: "coffee-work", title: "coffee to work from", query: "coffee work friendly"),
        SmartFilter(id: "patio-bars", title: "patio bars", query: "bars patio"),
        SmartFilter(id: "friends-liked", title: "friends liked", query: "friends been")
    ]

    init(
        fixtures: WanderFixtures,
        placeResolver: PlaceCandidateResolving = MapKitPlaceResolver(),
        parser: any LLMFilterParser = DeterministicFilterParser(),
        analytics: AnalyticsClient = NoopAnalyticsClient(),
        persistence: WanderStorePersistence? = nil
    ) {
        self.placeResolver = placeResolver
        self.parser = parser
        self.analytics = analytics
        self.persistence = persistence

        var shouldPersistAfterRestore = false
        if let restored = persistence?.load()?.restoredState(contactProvider: fixtures.contactProvider) {
            self.currentUser = restored.currentUser
            self.profiles = restored.profiles
            self.places = restored.places
            self.userPlaces = restored.userPlaces
            self.placeAttributes = restored.placeAttributes
            self.remoteVisiblePlaceCache = restored.cachedCurrentUserVisiblePlaces
            self.placeVisits = restored.placeVisits
            self.visitPhotos = restored.visitPhotos
            self.sharedVisitInvitations = restored.sharedVisitInvitations
            self.sharedVisitInboxUserID = restored.sharedVisitInboxUserID
            self.pendingSharedVisitInvites = restored.pendingSharedVisitInvites
            self.follows = restored.follows
            self.blocks = restored.blocks
            self.mutes = restored.mutes
            self.placeLists = restored.placeLists
            self.placeListMembers = restored.placeListMembers
            self.placeListItems = restored.placeListItems
            self.unresolvedDrafts = restored.unresolvedDrafts
            self.sourceArtifacts = restored.sourceArtifacts
            self.extractionJobs = restored.extractionJobs
            self.contactProvider = restored.contactProvider
            self.defaultVisibility = restored.defaultVisibility
            self.isPrivateProfile = restored.isPrivateProfile
            self.autoSaveListAddsToWant = restored.autoSaveListAddsToWant
            self.defaultMapFilter = restored.defaultMapFilter
            self.providerCategoryEnrichmentAttemptedAtByKey = restored.providerCategoryEnrichmentAttemptedAtByKey
            self.saveStreakDatesByUserID = restored.saveStreakDatesByUserID
            self.saveStreakRecoveryDatesByUserID = restored.saveStreakRecoveryDatesByUserID
            shouldPersistAfterRestore = restored.didApplySavedPlaceReset
        } else {
            self.currentUser = fixtures.currentUser
            self.profiles = fixtures.profiles
            self.places = fixtures.places
            self.userPlaces = fixtures.userPlaces
            self.placeAttributes = fixtures.placeAttributes
            self.placeVisits = fixtures.placeVisits
            self.visitPhotos = fixtures.visitPhotos
            self.sharedVisitInvitations = []
            self.sharedVisitInboxUserID = nil
            self.pendingSharedVisitInvites = []
            self.follows = fixtures.follows
            self.blocks = fixtures.blocks
            self.mutes = fixtures.mutes
            self.placeLists = fixtures.placeLists
            self.placeListMembers = fixtures.placeListMembers
            self.placeListItems = fixtures.placeListItems
            self.contactProvider = fixtures.contactProvider
            self.defaultVisibility = fixtures.currentUser.defaultVisibility
            self.isPrivateProfile = fixtures.currentUser.isPrivateProfile
            self.autoSaveListAddsToWant = true
            self.defaultMapFilter = .featured
            self.saveStreakDatesByUserID = Dictionary(grouping: fixtures.userPlaces, by: \.userID)
                .mapValues { $0.map(\.savedAt) }
            self.saveStreakRecoveryDatesByUserID = [:]
        }

        self.currentUser.isPrivateProfile = self.isPrivateProfile
        self.currentUser.defaultVisibilityRaw = self.defaultVisibility.rawValue
        let reconciliationStartedAt = CFAbsoluteTimeGetCurrent()
        var reconciliationIndex = VisitReconciliationIndex(
            userPlaces: userPlaces,
            visits: placeVisits,
            attributes: placeAttributes
        )
        backfillMissingLegacyVisits(using: &reconciliationIndex)
        let backfillFinishedAt = CFAbsoluteTimeGetCurrent()
        refreshAllVisitDerivedState(using: reconciliationIndex)
        let reconciliationFinishedAt = CFAbsoluteTimeGetCurrent()
        WanderDebugLog.performance.notice(
            "store reconciliation user_places=\(self.userPlaces.count, privacy: .public) visits=\(self.placeVisits.count, privacy: .public) attributes=\(self.placeAttributes.count, privacy: .public) backfill_ms=\((backfillFinishedAt - reconciliationStartedAt) * 1_000, privacy: .public) refresh_ms=\((reconciliationFinishedAt - backfillFinishedAt) * 1_000, privacy: .public)"
        )
        currentUserCalendarLocalFingerprint = makeCurrentUserCalendarLocalFingerprint()

        if shouldPersistAfterRestore {
            persist()
        }
    }

    private func persist() {
        let persistenceSignpostID = WanderDebugLog.beginPerformanceInterval("Store Persistence")
        defer {
            WanderDebugLog.endPerformanceInterval(
                "Store Persistence",
                id: persistenceSignpostID
            )
        }
        reconcileCurrentUserCalendarLocalFingerprint()
        invalidatePresentationCaches()
        guard let persistence else { return }

        if persistenceDeferralDepth > 0 {
            persistenceRequestedWhileDeferred = true
            return
        }

        let snapshotSignpostID = WanderDebugLog.beginPerformanceInterval("Snapshot Build")
        let snapshot = WanderStoreSnapshot(store: self)
        WanderDebugLog.endPerformanceInterval("Snapshot Build", id: snapshotSignpostID)
        persistence.save(snapshot)
    }

    func flushPersistence() {
        persistence?.flush()
    }

    private func makeCurrentUserCalendarLocalFingerprint() -> CurrentUserCalendarLocalFingerprint {
        let ownedUserPlaces = userPlaces
            .filter { $0.userID == currentUser.id }
            .sorted { $0.localID < $1.localID }
        let ownedUserPlaceReferenceIDs = ownedUserPlaces.reduce(into: Set<String>()) {
            $0.formUnion(Self.referenceIDs(for: $1))
        }
        let ownedAttributes = placeAttributes
            .filter {
                !$0.localID.hasPrefix("remote_attr_")
                    && ownedUserPlaceReferenceIDs.contains($0.userPlaceID)
            }
            .sorted { $0.localID < $1.localID }
        let ownedVisits = placeVisits
            .filter {
                (!Self.isSyntheticRemoteProfileVisit($0) || $0.syncState != .synced)
                    && ownedUserPlaceReferenceIDs.contains($0.userPlaceID)
            }
            .sorted { $0.localID < $1.localID }

        return CurrentUserCalendarLocalFingerprint(
            userPlaces: ownedUserPlaces.map(WanderStoreSnapshot.UserPlaceRecord.init),
            attributes: ownedAttributes.map(WanderStoreSnapshot.PlaceAttributeRecord.init),
            visits: ownedVisits.map(WanderStoreSnapshot.PlaceVisitRecord.init)
        )
    }

    private func reconcileCurrentUserCalendarLocalFingerprint() {
        let fingerprint = makeCurrentUserCalendarLocalFingerprint()
        guard let previousFingerprint = currentUserCalendarLocalFingerprint else {
            currentUserCalendarLocalFingerprint = fingerprint
            return
        }
        guard fingerprint != previousFingerprint else { return }

        currentUserCalendarLocalFingerprint = fingerprint
        guard !isApplyingAcceptedCurrentUserCalendarHydration else { return }

        currentUserCalendarLocalMutationRevision &+= 1
        let wasAuthoritative = authoritativeCalendarUserID == currentUser.id
        authoritativeCalendarUserID = nil
        if wasAuthoritative {
            objectWillChange.send()
        }
    }

    private func withAcceptedCurrentUserCalendarHydration<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let wasApplyingAcceptedHydration = isApplyingAcceptedCurrentUserCalendarHydration
        isApplyingAcceptedCurrentUserCalendarHydration = true
        defer {
            currentUserCalendarLocalFingerprint = makeCurrentUserCalendarLocalFingerprint()
            isApplyingAcceptedCurrentUserCalendarHydration = wasApplyingAcceptedHydration
        }
        return try operation()
    }

    private func invalidatePresentationCaches() {
        visiblePlacesCache.removeAll(keepingCapacity: true)
        visiblePlaceCountsByOwnerIDCache = nil
        visiblePlacesByListIDCache = nil
        firstVisitPhotosByPlaceIDCache = nil
        visiblePlaceListLookupCache = nil
        presentationRevision &+= 1
    }

    @discardableResult
    func refreshSharedVisitInbox(backend: WanderBackend?) async -> Bool {
        guard let backend, backend.canUseSharedVisits else { return false }
        let requestUserID = currentUser.id

        let taskID: UUID
        let task: Task<[SharedVisitInvitation], Error>
        if let existingTask = sharedVisitInboxTask, existingTask.userID == requestUserID {
            taskID = existingTask.id
            task = existingTask.task
        } else {
            sharedVisitInboxTask?.task.cancel()
            taskID = UUID()
            let createdTask = Task { @MainActor in
                try await backend.sharedVisitInbox(limit: 50)
            }
            sharedVisitInboxTask = (taskID, requestUserID, createdTask)
            task = createdTask
        }

        defer {
            if sharedVisitInboxTask?.id == taskID {
                sharedVisitInboxTask = nil
            }
        }

        do {
            let invitations = try await task.value
            guard currentUser.id == requestUserID else { return false }
            sharedVisitInvitations = invitations
            sharedVisitInboxUserID = requestUserID
            lastRemoteError = nil
            persist()
            return true
        } catch {
            guard currentUser.id == requestUserID else { return false }
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    func refreshSharedVisitContext(
        participantID: String,
        generation: Int,
        backend: WanderBackend?
    ) async -> SharedVisitInvitation? {
        let requestUserID = currentUser.id
        guard let backend, backend.canUseSharedVisits else {
            return sharedVisitInvitations.first {
                $0.participantID == participantID && $0.invitationGeneration == generation
            }
        }

        do {
            guard let invitation = try await backend.sharedVisitContext(
                participantID: participantID,
                generation: generation
            ) else {
                guard currentUser.id == requestUserID else { return nil }
                sharedVisitInvitations.removeAll { $0.participantID == participantID }
                persist()
                return nil
            }
            guard currentUser.id == requestUserID else { return nil }
            sharedVisitInvitations.removeAll { $0.participantID == participantID }
            sharedVisitInvitations.append(invitation)
            sharedVisitInvitations.sort { $0.invitedAt > $1.invitedAt }
            sharedVisitInboxUserID = currentUser.id
            lastRemoteError = nil
            persist()
            return invitation
        } catch {
            guard currentUser.id == requestUserID else { return nil }
            lastRemoteError = remoteErrorMessage(error)
            return sharedVisitInvitations.first {
                $0.participantID == participantID && $0.invitationGeneration == generation
            }
        }
    }

    func resolveSharedVisitDestination(
        participantID: String,
        generation: Int,
        backend: WanderBackend?
    ) async -> SharedVisitDestinationResolution {
        guard let backend, backend.canUseSharedVisits else { return .retryableFailure }
        let requestUserID = currentUser.id
        do {
            let destination = try await backend.resolveSharedVisitDestination(
                participantID: participantID,
                generation: generation
            )
            guard currentUser.id == requestUserID else { return .retryableFailure }
            return destination.map(SharedVisitDestinationResolution.resolved) ?? .unavailable
        } catch {
            guard currentUser.id == requestUserID else { return .retryableFailure }
            lastRemoteError = remoteErrorMessage(error)
            return .retryableFailure
        }
    }

    func declineSharedVisit(
        participantID: String,
        generation: Int,
        backend: WanderBackend?
    ) async -> Bool {
        guard let backend, backend.canUseSharedVisits else { return false }
        let requestUserID = currentUser.id
        do {
            try await backend.declineSharedVisit(participantID: participantID, generation: generation)
            guard currentUser.id == requestUserID else { return false }
            sharedVisitInvitations.removeAll { $0.participantID == participantID }
            lastRemoteError = nil
            persist()
            return true
        } catch {
            guard currentUser.id == requestUserID else { return false }
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    func refreshSharedVisitCompanions(visitIDs: [String], backend: WanderBackend?) async {
        guard let backend, backend.canUseSharedVisits else { return }
        let requestUserID = currentUser.id
        let remoteIDs = Array(Set(visitIDs.filter { UUID(uuidString: $0) != nil })).prefix(50)
        guard !remoteIDs.isEmpty else { return }

        do {
            let companions = try await backend.sharedVisitCompanions(visitIDs: Array(remoteIDs))
            guard currentUser.id == requestUserID else { return }
            var grouped = Dictionary(grouping: companions, by: \.visitID)
            for visitID in remoteIDs where grouped[visitID] == nil {
                grouped[visitID] = []
            }
            sharedVisitCompanionsByVisitID.merge(grouped) { _, refreshed in refreshed }
            lastRemoteError = nil
        } catch {
            guard currentUser.id == requestUserID else { return }
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func sharedVisitCompanions(for visitID: String) -> [SharedVisitCompanion] {
        let ids = matchingVisitIDs(visitID)
        var seenUserIDs: Set<String> = []
        return ids
            .compactMap { sharedVisitCompanionsByVisitID[$0] }
            .flatMap { $0 }
            .filter { seenUserIDs.insert($0.userID).inserted }
    }

    func sharedVisitInviteeUserIDs(sourceVisitID: String, backend: WanderBackend?) async throws -> [String] {
        guard let backend, backend.canUseSharedVisits else { throw WanderRemoteError.notConfigured }
        let requestUserID = currentUser.id
        guard let visit = currentUserVisit(matching: sourceVisitID) else { return [] }

        if let pending = pendingSharedVisitInvites.last(where: {
            $0.ownerUserID == requestUserID && currentUserVisit(matching: $0.sourceVisitID)?.id == visit.id
        }) {
            return pending.inviteeUserIDs
        }

        guard let remoteVisitID = visit.serverID else { return [] }
        let inviteeUserIDs = try await backend.sharedVisitInviteeUserIDs(sourceVisitID: remoteVisitID)
        guard currentUser.id == requestUserID else { throw CancellationError() }
        return Array(Set(inviteeUserIDs)).sorted()
    }

    func queueSharedVisitInvites(sourceVisitID: String, inviteeUserIDs: [String]) {
        let normalizedInvitees = Array(Set(inviteeUserIDs.filter { !$0.isEmpty })).sorted()
        guard !normalizedInvitees.isEmpty else { return }

        queueSharedVisitInviteeReconciliation(
            sourceVisitID: sourceVisitID,
            inviteeUserIDs: normalizedInvitees
        )
        let properties = ["invitee_count": "\(normalizedInvitees.count)"]
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.sharedVisitInvitesQueued,
                properties: properties
            )
        )
        analytics.track(
            .engagement(
                need: .connect,
                action: .sharedVisitInvitesQueued,
                surface: "check_in",
                properties: properties
            )
        )
    }

    func queueSharedVisitInviteeReconciliation(sourceVisitID: String, inviteeUserIDs: [String]) {
        let normalizedInvitees = Array(Set(inviteeUserIDs.filter { !$0.isEmpty })).sorted()
        let sourceVisit = currentUserVisit(matching: sourceVisitID)

        pendingSharedVisitInvites.removeAll {
            $0.ownerUserID == currentUser.id
                && (
                    $0.sourceVisitID == sourceVisitID
                    || (
                        sourceVisit != nil
                        && currentUserVisit(matching: $0.sourceVisitID)?.id == sourceVisit?.id
                    )
                )
        }
        pendingSharedVisitInvites.append(
            PendingSharedVisitInvite(
                id: UUID().uuidString.lowercased(),
                ownerUserID: currentUser.id,
                sourceVisitID: sourceVisitID,
                inviteeUserIDs: normalizedInvitees,
                createdAt: .now
            )
        )
        setOptimisticSharedVisitCompanions(
            visitID: sourceVisit?.id ?? sourceVisitID,
            inviteeUserIDs: normalizedInvitees
        )
        persist()
    }

    @discardableResult
    func retryPendingSharedVisitInvites(backend: WanderBackend?) async -> Int {
        guard let backend, backend.canUseSharedVisits else { return 0 }
        let ownerUserID = currentUser.id
        var sentCount = 0

        for pending in pendingSharedVisitInvites where pending.ownerUserID == ownerUserID {
            guard currentUser.id == ownerUserID else { break }
            guard let visit = currentUserVisit(matching: pending.sourceVisitID) else {
                pendingSharedVisitInvites.removeAll { $0.id == pending.id }
                continue
            }
            if visit.serverID == nil || visit.syncState != .synced {
                _ = await syncVisit(visitID: visit.id, backend: backend)
            }
            guard currentUser.id == ownerUserID else { break }
            guard let remoteVisitID = visit.serverID else { continue }

            let sourcePhotos = photos(for: visit.id)
            guard sourcePhotos.allSatisfy({ $0.uploadState == .uploaded && $0.syncState == .synced }) else {
                continue
            }

            do {
                _ = try await backend.setSharedVisitInvitees(
                    sourceVisitID: remoteVisitID,
                    inviteeUserIDs: pending.inviteeUserIDs
                )
                guard currentUser.id == ownerUserID else { break }
                pendingSharedVisitInvites.removeAll { $0.id == pending.id }
                sentCount += pending.inviteeUserIDs.count
                lastRemoteError = nil
                await refreshSharedVisitCompanions(visitIDs: [remoteVisitID], backend: backend)
            } catch {
                guard currentUser.id == ownerUserID else { break }
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        persist()
        return sentCount
    }

    private func setOptimisticSharedVisitCompanions(visitID: String, inviteeUserIDs: [String]) {
        guard let visit = currentUserVisit(matching: visitID) else { return }
        let cacheVisitID = visit.serverID ?? visit.id
        sharedVisitCompanionsByVisitID[cacheVisitID] = inviteeUserIDs.compactMap { userID in
            guard let profile = profiles.first(where: { $0.id == userID }) else { return nil }
            return SharedVisitCompanion(
                visitID: cacheVisitID,
                userID: profile.id,
                handle: profile.handle,
                displayName: profile.displayName,
                avatarURL: profile.avatarURL
            )
        }
    }

    @discardableResult
    func retryPendingVisitPhotoUploads(backend: WanderBackend?) async -> Int {
        guard let backend else { return 0 }
        let uploadUserID = currentUser.id

        if let visitPhotoUploadTask,
           visitPhotoUploadTask.userID == uploadUserID {
            return await visitPhotoUploadTask.task.value
        }

        visitPhotoUploadTask?.task.cancel()
        let uploadID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return 0 }
            defer {
                if self.visitPhotoUploadTask?.id == uploadID {
                    self.visitPhotoUploadTask = nil
                }
            }
            return await self.performPendingVisitPhotoUploads(
                userID: uploadUserID,
                backend: backend
            )
        }
        visitPhotoUploadTask = (uploadID, uploadUserID, task)
        return await task.value
    }

    private func performPendingVisitPhotoUploads(
        userID uploadUserID: String,
        backend: WanderBackend
    ) async -> Int {
        var uploadedCount = 0
        var attemptedPhotoIDs: Set<String> = []

        while currentUser.id == uploadUserID, !Task.isCancelled {
            let pendingPhotos = visitPhotos.filter {
                !attemptedPhotoIDs.contains($0.id)
                    && $0.deletedAt == nil
                    && $0.syncState != .synced
                    && $0.syncState != .serverDenied
                    && $0.syncState != .tombstoned
                    && (
                        ($0.uploadState == .uploaded && $0.remoteURLString?.isEmpty == false)
                            || $0.localAssetRef?.isEmpty == false
                    )
                    && currentUserVisit(matching: $0.visitID) != nil
            }
            guard !pendingPhotos.isEmpty else { break }

            for photo in pendingPhotos {
                guard currentUser.id == uploadUserID, !Task.isCancelled else { break }
                attemptedPhotoIDs.insert(photo.id)
                let isAlreadyUploaded = photo.uploadState == .uploaded
                    && photo.remoteURLString?.isEmpty == false
                let data = isAlreadyUploaded
                    ? nil
                    : VisitPhotoLocalFileStore.data(from: photo.localAssetRef)
                guard data != nil || isAlreadyUploaded else { continue }
                let result = await uploadVisitPhoto(photoID: photo.id, data: data, backend: backend)
                guard currentUser.id == uploadUserID, !Task.isCancelled else { break }
                if result?.uploadState == .uploaded && result?.syncState == .synced {
                    uploadedCount += 1
                }
            }
        }
        return uploadedCount
    }

    private func withDeferredPersistence<Result>(_ operation: () throws -> Result) rethrows -> Result {
        persistenceDeferralDepth += 1
        defer {
            persistenceDeferralDepth -= 1
            if persistenceDeferralDepth == 0, persistenceRequestedWhileDeferred {
                persistenceRequestedWhileDeferred = false
                persist()
            }
        }
        return try operation()
    }

    /// Coalesces a group of local mutations into one snapshot write. Keep the
    /// operation synchronous so unrelated main-actor work cannot become part
    /// of the batch while it is suspended.
    func performBatchedLocalMutations<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try withDeferredPersistence(operation)
    }

    func apply(authState: AuthState) {
        switch authState {
        case .signedIn(let session), .offline(let session, _):
            let previousUserID = currentUser.id
            if previousUserID != session.userID {
                analytics.resetIdentity()
                clearSessionScopedRemoteState()
            }
            apply(session: session)
            if previousUserID != currentUser.id {
                discoverPeopleRecommendationsState = .idle
            }
            analytics.identify(userID: session.userID)
            #if DEBUG
            WanderDebugLog.sync.debug("store auth identified user=\(WanderDebugLog.shortID(session.userID), privacy: .public) pending_sync_count=\(self.pendingSyncCount, privacy: .public)")
            #endif
        case .signedOut, .unavailable:
            clearSessionScopedRemoteState()
            applySignedOutProfile()
            discoverPeopleRecommendationsState = .idle
            analytics.resetIdentity()
            #if DEBUG
            WanderDebugLog.sync.debug("store auth signed_out_or_unavailable pending_sync_count=\(self.pendingSyncCount, privacy: .public)")
            #endif
        case .loading:
            #if DEBUG
            WanderDebugLog.sync.debug("store auth loading pending_sync_count=\(self.pendingSyncCount, privacy: .public)")
            #endif
            break
        }
    }

    private func clearSessionScopedRemoteState() {
        cancelVisitPhotoUploadTask()
        cancelCurrentUserCalendarRefresh()
        authoritativeCalendarUserID = nil

        let hadRemoteState = !remoteVisiblePlaceCache.isEmpty
            || placeVisits.contains {
                Self.isSyntheticRemoteProfileVisit($0) && $0.syncState == .synced
            }
            || placeAttributes.contains { $0.localID.hasPrefix("remote_attr_") }
            || followedFeedPage != nil
            || feedLoadState != .idle
            || lastFeedRefreshAt != nil
            || !activityEngagementByID.isEmpty
            || !activityCommentsByID.isEmpty
            || !placeActivityEngagementMatches.isEmpty
            || lastRemoteError != nil
            || profiles.contains { $0.id != currentUser.id }
            || !follows.isEmpty
            || !blocks.isEmpty
            || !mutes.isEmpty
        guard hadRemoteState else { return }

        withDeferredPersistence {
            remoteVisiblePlaceCache = []
            placeVisits.removeAll {
                Self.isSyntheticRemoteProfileVisit($0) && $0.syncState == .synced
            }
            placeAttributes.removeAll {
                $0.localID.hasPrefix("remote_attr_")
            }
            followedFeedPage = nil
            feedLoadState = .idle
            lastFeedRefreshAt = nil
            activityEngagementByID = [:]
            activityCommentsByID = [:]
            placeActivityEngagementMatches = []
            activityEngagementErrorByID = [:]
            pendingActivityLikeIDs = []
            pendingActivityCommentDeletionIDs = []
            lastRemoteError = nil
            profiles = []
            follows = []
            blocks = []
            mutes = []
            objectWillChange.send()
            persist()
        }
    }

    var stats: ProfileStats {
        currentUserCalendarProjection.profileStats(
            currentUserID: currentUser.id,
            friends: profiles.filter { relationship(to: $0.id) == .mutual }.count
        )
    }

    var saveStreakSummary: SaveStreakSummary {
        SaveStreakCalculator.summary(
            saveDates: currentUserSaveStreakDates,
            recoveryDates: saveStreakRecoveryDatesByUserID[currentUser.id, default: []]
        )
    }

    func dismissSaveStreakCelebration(id: UUID) {
        guard saveStreakCelebration?.id == id else { return }
        saveStreakCelebration = nil
    }

    func saveFlowDidPresent(_ layer: SaveFlowPresentationLayer) {
        activeSaveFlowPresentationLayers.insert(layer)
        isSaveFlowPresented = !activeSaveFlowPresentationLayers.isEmpty
    }

    func saveFlowDidDismiss(_ layer: SaveFlowPresentationLayer) {
        activeSaveFlowPresentationLayers.remove(layer)
        isSaveFlowPresented = !activeSaveFlowPresentationLayers.isEmpty
    }

    private var currentUserSaveStreakDates: [Date] {
        let localDates = userPlaces
            .filter { $0.userID == currentUser.id }
            .map(\.savedAt)
        let remoteDates = remoteVisiblePlaceCache
            .filter { $0.owner.id == currentUser.id }
            .map(\.userPlace.savedAt)
        return saveStreakDatesByUserID[currentUser.id, default: []] + localDates + remoteDates
    }

    private func recordNewSaveForStreak(
        place: LocalPlace,
        status: PlaceStatus,
        savedAt: Date,
        previousSummary: SaveStreakSummary
    ) {
        let kind: SaveStreakCelebration.Kind = previousSummary.isTodayCovered
            ? .sameDayConfetti
            : .dailyTakeover

        let calendar = Calendar.current
        let recoveryDate: Date? = if previousSummary.isRecoveryAvailable {
            calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: savedAt)
            )
        } else {
            nil
        }
        if let recoveryDate {
            saveStreakRecoveryDatesByUserID[currentUser.id, default: []].append(recoveryDate)
        }

        saveStreakDatesByUserID[currentUser.id, default: []].append(savedAt)
        let updatedSummary = saveStreakSummary
        let detail = [place.locality, place.region]
            .compactMap { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " · ")

        let celebration = SaveStreakCelebration(
            kind: kind,
            placeName: place.canonicalName,
            placeDetail: detail.isEmpty ? nil : detail,
            status: status,
            streakCount: updatedSummary.currentCount,
            saveDate: savedAt,
            recoveryDate: recoveryDate
        )

        if saveStreakCelebration?.kind != .dailyTakeover || kind == .dailyTakeover {
            saveStreakCelebration = celebration
        }

        analytics.track(
            AnalyticsEvent(
                name: kind == .dailyTakeover
                    ? WanderAnalyticsEvents.saveStreakAdvanced
                    : WanderAnalyticsEvents.saveStreakSameDaySave,
                properties: [
                    "status": status.rawValue,
                    "streak_count": "\(updatedSummary.currentCount)"
                ]
            )
        )
        if kind == .dailyTakeover {
            analytics.track(
                .engagement(
                    need: .status,
                    action: .saveStreakAdvanced,
                    surface: "save_streak",
                    properties: [
                        "status": status.rawValue,
                        "streak_count": "\(updatedSummary.currentCount)"
                    ]
                )
            )
        }
        if recoveryDate != nil {
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.saveStreakRecovered,
                    properties: [
                        "status": status.rawValue,
                        "recovered_streak_count": "\(previousSummary.recoverableCount)",
                        "streak_count": "\(updatedSummary.currentCount)",
                        "recovery_cooldown_days": "\(SaveStreakWindow.recoveryCooldownDayCount)"
                    ]
                )
            )
        }
    }

    var pendingSyncCount: Int {
        let pendingUserPlaces = userPlaces.filter { $0.syncState != .synced }.count
        let pendingAttributes = placeAttributes.filter { $0.syncState != .synced }.count
        let pendingVisits = placeVisits.filter { $0.syncState != .synced }.count
        let pendingVisitPhotos = visitPhotos.filter { $0.syncState != .synced }.count
        let pendingArtifacts = sourceArtifacts.filter { SyncState(rawValue: $0.syncStateRaw) != .synced }.count
        let pendingJobs = extractionJobs.filter { SyncState(rawValue: $0.syncStateRaw) != .synced }.count

        return pendingUserPlaces
            + pendingAttributes
            + pendingVisits
            + pendingVisitPhotos
            + pendingArtifacts
            + pendingJobs
            + pendingSharedVisitInvites.count
            + unresolvedDrafts.count
    }

    func updateCurrentUserAvatarURL(_ avatarURL: String?) {
        objectWillChange.send()

        let now = Date()
        let currentLocalID = currentUser.localID
        let currentProfileID = currentUser.id

        currentUser.avatarURL = avatarURL
        currentUser.updatedAt = now
        currentUser.localUpdatedAt = now

        for profile in profiles where profile.localID == currentLocalID || profile.id == currentProfileID {
            profile.avatarURL = avatarURL
            profile.updatedAt = now
            profile.localUpdatedAt = now
        }

        persist()
    }

    func updateCurrentUserProfile(
        displayName: String? = nil,
        handle: String? = nil,
        bio: String? = nil,
        homeArea: String? = nil
    ) {
        objectWillChange.send()
        let now = Date.now
        let currentLocalID = currentUser.localID
        let currentProfileID = currentUser.id

        if let displayName {
            currentUser.displayName = displayName
        }
        if let handle {
            currentUser.handle = handle
            currentUser.searchHandle = handle.lowercased()
        }
        if let bio {
            currentUser.bio = normalizedOptionalProfileValue(bio)
        }
        if let homeArea {
            currentUser.homeArea = normalizedOptionalProfileValue(homeArea)
        }
        currentUser.updatedAt = now
        currentUser.localUpdatedAt = now

        for profile in profiles where profile.localID == currentLocalID || profile.id == currentProfileID {
            profile.displayName = currentUser.displayName
            profile.handle = currentUser.handle
            profile.searchHandle = currentUser.searchHandle
            profile.bio = currentUser.bio
            profile.homeArea = currentUser.homeArea
            profile.updatedAt = now
            profile.localUpdatedAt = now
        }

        persist()
    }

    func updateCurrentUserDetails(_ update: ProfileDetailsUpdate, backend: WanderBackend?) async throws {
        try CommunityContentPolicy.validate(update.displayName, update.handle, update.bio, update.homeArea)
        guard let backend, backend.profileRepository != nil else {
            updateCurrentUserProfile(
                displayName: update.displayName,
                handle: update.handle,
                bio: update.bio,
                homeArea: update.homeArea
            )
            return
        }

        do {
            let remoteProfile = try await backend.updateCurrentProfile(update)
            applyRemoteCurrentProfile(remoteProfile)
            lastRemoteError = nil
        } catch {
            let message = remoteErrorMessage(error)
            currentUser.syncStateRaw = SyncState.failed.rawValue
            currentUser.lastSyncError = message
            lastRemoteError = message
            objectWillChange.send()
            persist()
            throw error
        }
    }

    func resetAfterAccountDeletion() {
        placeListSyncTask?.task.cancel()
        individualPlaceListSyncTasks.values.forEach { $0.task.cancel() }
        placeListSyncTask = nil
        individualPlaceListSyncTasks.removeAll()
        cancelVisitPhotoUploadTask()
        cancelCurrentUserCalendarRefresh()
        authoritativeCalendarUserID = nil

        let empty = WanderFixtures.empty()
        currentUser = empty.currentUser
        profiles = empty.profiles
        places = []
        userPlaces = []
        placeAttributes = []
        placeVisits = []
        visitPhotos = []
        follows = []
        blocks = []
        mutes = []
        placeLists = []
        placeListMembers = []
        placeListItems = []
        unresolvedDrafts = []
        sourceArtifacts = []
        extractionJobs = []
        saveStreakDatesByUserID = [:]
        saveStreakRecoveryDatesByUserID = [:]
        saveStreakCelebration = nil
        remoteVisiblePlaceCache = []
        discoverPeopleRecommendationsState = .idle
        followedFeedPage = nil
        feedLoadState = .idle
        lastFeedRefreshAt = nil
        activityEngagementByID = [:]
        activityCommentsByID = [:]
        placeActivityEngagementMatches = []
        activityEngagementErrorByID = [:]
        pendingActivityLikeIDs = []
        pendingActivityCommentDeletionIDs = []
        lastRemoteError = nil
        lastDiscoverFilters = DiscoverFilters(query: "")
        lastDiscoverParseSource = .deterministic
        discoverParseCache.removeAll()
        discoverParseCacheOrder.removeAll()
        defaultVisibility = .followers
        isPrivateProfile = false
        autoSaveListAddsToWant = true
        defaultMapFilter = .featured
        persist()
    }

    private func normalizedOptionalProfileValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    var currentUserVisiblePlaces: [VisiblePlace] {
        visiblePlaces(filters: PlaceFilters(ownerScopes: ["you"]))
    }

    var currentUserCalendarProjection: CurrentUserCalendarProjection {
        let localOwnerPlaces = localVisiblePlaces(
            filters: PlaceFilters(ownerScopes: ["you"])
        ).places
        let remoteOwnerPlaces = remoteVisiblePlaceCache.filter {
            $0.owner.id == currentUser.id && $0.userPlace.deletedAt == nil
        }
        let isAuthoritative = authoritativeCalendarUserID == currentUser.id
        let dirtyRows = userPlaces.filter {
            $0.userID == currentUser.id && $0.syncState != .synced
        }
        let dirtyReferenceIDs = dirtyRows.reduce(into: Set<String>()) {
            $0.formUnion(Self.referenceIDs(for: $1))
        }
        let unshadowedRemotePlaces = remoteOwnerPlaces.filter {
            Self.referenceIDs(for: $0.userPlace).isDisjoint(with: dirtyReferenceIDs)
        }

        let projectedPlaces: [VisiblePlace]
        if isAuthoritative {
            let remoteReferenceIDs = remoteOwnerPlaces.reduce(into: Set<String>()) {
                $0.formUnion(Self.referenceIDs(for: $1.userPlace))
            }
            let preservedLocalRows = userPlaces.filter { userPlace in
                guard userPlace.userID == currentUser.id,
                      userPlace.deletedAt == nil
                else { return false }
                if userPlace.syncState != .synced {
                    return true
                }
                return Self.referenceIDs(for: userPlace)
                    .isDisjoint(with: remoteReferenceIDs)
                    && hasUnsyncedCalendarChildren(for: userPlace)
            }
            let preservedLocalReferenceIDs = preservedLocalRows.reduce(into: Set<String>()) {
                $0.formUnion(Self.referenceIDs(for: $1))
            }
            let preservedLocalPlaces = localOwnerPlaces.filter {
                !Self.referenceIDs(for: $0.userPlace)
                    .isDisjoint(with: preservedLocalReferenceIDs)
            }
            projectedPlaces = preservedLocalPlaces + unshadowedRemotePlaces
        } else {
            projectedPlaces = mergeCalendarVisiblePlaces(
                localOwnerPlaces + unshadowedRemotePlaces
            )
        }

        let projectedUserPlaceIDs = projectedPlaces.reduce(into: Set<String>()) {
            $0.formUnion(Self.referenceIDs(for: $1.userPlace))
        }
        let projectedVisits = mergeCalendarVisits(
            placeVisits.filter {
                $0.deletedAt == nil && projectedUserPlaceIDs.contains($0.userPlaceID)
            },
            isAuthoritative: isAuthoritative
        )

        return CurrentUserCalendarProjection(
            visiblePlaces: projectedPlaces,
            visits: projectedVisits,
            isAuthoritative: isAuthoritative
        )
    }

    private func hasUnsyncedCalendarChildren(for userPlace: LocalUserPlace) -> Bool {
        let userPlaceReferenceIDs = Self.referenceIDs(for: userPlace)
        if placeAttributes.contains(where: {
            userPlaceReferenceIDs.contains($0.userPlaceID)
                && $0.syncState != .synced
        }) {
            return true
        }
        return placeVisits.contains {
            userPlaceReferenceIDs.contains($0.userPlaceID)
                && $0.syncState != .synced
        }
    }

    /// Loads the local Feed fixture only when a remote Feed repository is not
    /// available. Production data is supplied by the server-side event
    /// projection; the fixture keeps demo and visual-QA launches deterministic.
    @discardableResult
    func refreshFollowedFeed(
        backend: WanderBackend?,
        preservingActivityID: String? = nil
    ) async -> Bool {
        let requestUserID = currentUser.id
        feedLoadState = followedFeedPage == nil ? .loading : .stale

        guard !Task.isCancelled else { return false }

        if let backend, let repository = backend.feedRepository {
            do {
                let page = try await loadFollowedFeed(from: repository)
                guard !Task.isCancelled, currentUser.id == requestUserID else { return false }
                let resolvedPage = mergingPinnedActivity(
                    into: page,
                    activityID: preservingActivityID
                )
                followedFeedPage = resolvedPage
                feedLoadState = .loaded
                lastFeedRefreshAt = page.fetchedAt
                lastRemoteError = nil
                await refreshActivityEngagement(
                    activityIDs: resolvedPage.activity.map(\.id),
                    backend: backend
                )
                return true
            } catch {
                guard !Task.isCancelled, currentUser.id == requestUserID else { return false }
                lastRemoteError = remoteErrorMessage(error)
                feedLoadState = followedFeedPage == nil ? .failed : .stale
                return false
            }
        }

        guard currentUser.id == requestUserID else { return false }
        let page = fixtureFollowedFeedPage(relativeTo: .now)
        followedFeedPage = mergingPinnedActivity(
            into: page,
            activityID: preservingActivityID
        )
        feedLoadState = .loaded
        lastFeedRefreshAt = page.fetchedAt
        seedFixtureActivityEngagement(for: page.activity)
        return true
    }

    private func mergingPinnedActivity(
        into refreshedPage: FollowedFeedPage,
        activityID: String?
    ) -> FollowedFeedPage {
        guard let activityID,
              !refreshedPage.activity.contains(where: { $0.id == activityID }),
              let pinnedActivity = followedFeedPage?.activity.first(where: { $0.id == activityID })
        else { return refreshedPage }

        return FollowedFeedPage(
            activity: FeedPresentation.newestFirst(refreshedPage.activity + [pinnedActivity]),
            featuredPlaces: refreshedPage.featuredPlaces,
            nextCursor: refreshedPage.nextCursor,
            fetchedAt: refreshedPage.fetchedAt
        )
    }

    func activityEngagement(for activityID: String) -> ActivityEngagementSummary {
        activityEngagementByID[activityID] ?? .empty(activityID: activityID)
    }

    @MainActor
    func activity(id activityID: String, backend: WanderBackend?) async -> FeedActivity? {
        let existing = followedFeedPage?.activity.first(where: { $0.id == activityID })

        guard UUID(uuidString: activityID) != nil,
              let repository = backend?.activityEngagementRepository
        else { return existing }

        do {
            let activity = try await repository.activity(id: activityID)
            let currentPage = followedFeedPage
            let mergedActivity = FeedPresentation.newestFirst(
                [activity] + (currentPage?.activity ?? []).filter { $0.id != activity.id }
            )
            followedFeedPage = FollowedFeedPage(
                activity: mergedActivity,
                featuredPlaces: currentPage?.featuredPlaces ?? [],
                nextCursor: currentPage?.nextCursor,
                fetchedAt: currentPage?.fetchedAt ?? .now
            )
            await refreshActivityEngagement(activityIDs: [activityID], backend: backend)
            return activity
        } catch {
            activityEngagementErrorByID[activityID] = remoteErrorMessage(error)
            return existing
        }
    }

    func activityComments(for activityID: String) -> [ActivityComment] {
        activityCommentsByID[activityID, default: []]
    }

    func activityEngagementError(for activityID: String) -> String? {
        activityEngagementErrorByID[activityID]
    }

    func canDeleteActivityComment(_ comment: ActivityComment) -> Bool {
        comment.author.id == currentUser.id
            && !comment.isPending
            && !pendingActivityCommentDeletionIDs.contains(comment.id)
    }

    func isActivityLikePending(_ activityID: String) -> Bool {
        pendingActivityLikeIDs.contains(activityID)
    }

    func refreshActivityEngagement(activityIDs: [String], backend: WanderBackend?) async {
        let remoteIDs = Array(Set(activityIDs.filter { UUID(uuidString: $0) != nil })).sorted()
        guard !remoteIDs.isEmpty,
              let repository = backend?.activityEngagementRepository
        else { return }

        do {
            let summaries = try await repository.summaries(activityIDs: remoteIDs)
            for summary in summaries where !pendingActivityLikeIDs.contains(summary.activityID) {
                activityEngagementByID[summary.activityID] = summary
                activityEngagementErrorByID[summary.activityID] = nil
            }
        } catch {
            let message = remoteErrorMessage(error)
            for activityID in remoteIDs {
                activityEngagementErrorByID[activityID] = message
            }
        }
    }

    func refreshPlaceActivityEngagement(userPlaceIDs: [String], backend: WanderBackend?) async {
        let remoteIDs = Array(Set(userPlaceIDs.filter { UUID(uuidString: $0) != nil })).sorted()
        guard !remoteIDs.isEmpty,
              let repository = backend?.activityEngagementRepository
        else { return }

        do {
            let matches = try await repository.placeActivitySummaries(userPlaceIDs: remoteIDs)
            let refreshedIDs = Set(remoteIDs)
            placeActivityEngagementMatches.removeAll { refreshedIDs.contains($0.userPlaceID) }
            placeActivityEngagementMatches.append(contentsOf: matches)
            for match in matches where !pendingActivityLikeIDs.contains(match.activityID) {
                activityEngagementByID[match.activityID] = match.engagement
                activityEngagementErrorByID[match.activityID] = nil
            }
        } catch {
            let message = remoteErrorMessage(error)
            for userPlaceID in remoteIDs {
                activityEngagementErrorByID["user-place:\(userPlaceID)"] = message
            }
        }
    }

    func placeActivityEngagementMatch(
        userPlaceID: String,
        visitID: String?,
        preferredKinds: [FeedActivityKind]
    ) -> PlaceActivityEngagementMatch? {
        let candidates = placeActivityEngagementMatches.filter { match in
            guard match.userPlaceID == userPlaceID else { return false }
            if let visitID {
                return match.visitID == visitID
            }
            // Remote place projections may not have materialized the explicit
            // visit locally yet. In that case the immutable event is still the
            // authority; choose the newest compatible event below instead of
            // disabling engagement on a valid history card.
            return preferredKinds.contains(match.kind)
        }

        return candidates.sorted { lhs, rhs in
            let lhsRank = preferredKinds.firstIndex(of: lhs.kind) ?? preferredKinds.count
            let rhsRank = preferredKinds.firstIndex(of: rhs.kind) ?? preferredKinds.count
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.activityID < rhs.activityID
        }.first
    }

    @discardableResult
    func toggleActivityLike(activityID: String, backend: WanderBackend?) async -> Bool {
        guard !pendingActivityLikeIDs.contains(activityID) else { return false }
        let previous = activityEngagement(for: activityID)
        let requestedLike = !previous.viewerHasLiked
        activityEngagementByID[activityID] = previous.settingLike(requestedLike)
        activityEngagementErrorByID[activityID] = nil

        guard UUID(uuidString: activityID) != nil,
              let repository = backend?.activityEngagementRepository
        else {
            trackActivityLike(requestedLike, outcome: "local_only")
            return true
        }

        pendingActivityLikeIDs.insert(activityID)
        defer { pendingActivityLikeIDs.remove(activityID) }
        do {
            activityEngagementByID[activityID] = try await repository.setLike(
                activityID: activityID,
                isLiked: requestedLike
            )
            trackActivityLike(requestedLike, outcome: "succeeded")
            return true
        } catch {
            activityEngagementByID[activityID] = previous
            activityEngagementErrorByID[activityID] = remoteErrorMessage(error)
            return false
        }
    }

    @discardableResult
    func refreshActivityComments(activityID: String, backend: WanderBackend?) async -> Bool {
        guard UUID(uuidString: activityID) != nil,
              let repository = backend?.activityEngagementRepository
        else { return true }

        do {
            let page = try await repository.comments(activityID: activityID, before: nil, limit: 50)
            let pendingDeletedComments = page.comments.filter {
                pendingActivityCommentDeletionIDs.contains($0.id)
            }
            activityCommentsByID[activityID] = page.comments.filter {
                !pendingActivityCommentDeletionIDs.contains($0.id)
            }.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
            let refreshedEngagement = pendingDeletedComments.reduce(page.engagement) { summary, _ in
                summary.removingComment()
            }
            if pendingActivityLikeIDs.contains(activityID) {
                let optimistic = activityEngagement(for: activityID)
                activityEngagementByID[activityID] = ActivityEngagementSummary(
                    activityID: activityID,
                    likeCount: optimistic.likeCount,
                    commentCount: refreshedEngagement.commentCount,
                    viewerHasLiked: optimistic.viewerHasLiked
                )
            } else {
                activityEngagementByID[activityID] = refreshedEngagement
            }
            activityEngagementErrorByID[activityID] = nil
            return true
        } catch {
            activityEngagementErrorByID[activityID] = remoteErrorMessage(error)
            return false
        }
    }

    @discardableResult
    func addActivityComment(activityID: String, body: String, backend: WanderBackend?) async -> Bool {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty, normalizedBody.count <= 1_000 else { return false }

        let previousSummary = activityEngagement(for: activityID)
        let pendingID = "pending-comment-\(UUID().uuidString.lowercased())"
        let pending = ActivityComment(
            id: pendingID,
            activityID: activityID,
            author: shell(for: currentUser),
            body: normalizedBody,
            createdAt: .now,
            isPending: true
        )
        activityCommentsByID[activityID, default: []].append(pending)
        activityEngagementByID[activityID] = previousSummary.addingComment()
        activityEngagementErrorByID[activityID] = nil

        guard UUID(uuidString: activityID) != nil,
              let repository = backend?.activityEngagementRepository
        else {
            activityCommentsByID[activityID] = activityComments(for: activityID).map { comment in
                guard comment.id == pendingID else { return comment }
                return ActivityComment(
                    id: comment.id,
                    activityID: comment.activityID,
                    author: comment.author,
                    body: comment.body,
                    createdAt: comment.createdAt
                )
            }
            trackActivityCommentCreated(outcome: "local_only")
            return true
        }

        do {
            let result = try await repository.addComment(activityID: activityID, body: normalizedBody)
            activityCommentsByID[activityID] = activityComments(for: activityID)
                .filter { $0.id != pendingID } + [result.comment]
            activityCommentsByID[activityID]?.sort { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
            activityEngagementByID[activityID] = result.engagement
            trackActivityCommentCreated(outcome: "succeeded")
            return true
        } catch {
            activityCommentsByID[activityID]?.removeAll { $0.id == pendingID }
            activityEngagementByID[activityID] = previousSummary
            activityEngagementErrorByID[activityID] = remoteErrorMessage(error)
            return false
        }
    }

    private func trackActivityLike(_ isLiked: Bool, outcome: String) {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.activityLikeChanged,
                properties: [
                    "is_liked": isLiked ? "true" : "false",
                    "outcome": outcome
                ]
            )
        )
        if isLiked {
            analytics.track(
                .engagement(
                    need: .connect,
                    action: .activityLiked,
                    surface: "activity",
                    properties: ["outcome": outcome]
                )
            )
        }
    }

    private func trackActivityCommentCreated(outcome: String) {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.activityCommentCreated,
                properties: ["outcome": outcome]
            )
        )
        analytics.track(
            .engagement(
                need: .connect,
                action: .activityCommented,
                surface: "activity",
                properties: ["outcome": outcome]
            )
        )
    }

    @discardableResult
    func deleteActivityComment(_ comment: ActivityComment, backend: WanderBackend?) async -> Bool {
        guard canDeleteActivityComment(comment),
              let previousIndex = activityComments(for: comment.activityID).firstIndex(where: { $0.id == comment.id })
        else { return false }

        let previousSummary = activityEngagement(for: comment.activityID)
        activityCommentsByID[comment.activityID]?.remove(at: previousIndex)
        activityEngagementByID[comment.activityID] = previousSummary.removingComment()
        activityEngagementErrorByID[comment.activityID] = nil

        guard UUID(uuidString: comment.id) != nil,
              UUID(uuidString: comment.activityID) != nil,
              let repository = backend?.activityEngagementRepository
        else { return true }

        pendingActivityCommentDeletionIDs.insert(comment.id)
        defer { pendingActivityCommentDeletionIDs.remove(comment.id) }
        do {
            activityEngagementByID[comment.activityID] = try await repository.deleteComment(commentID: comment.id)
            return true
        } catch {
            var restoredComments = activityComments(for: comment.activityID)
            if !restoredComments.contains(where: { $0.id == comment.id }) {
                restoredComments.insert(comment, at: min(previousIndex, restoredComments.count))
            }
            activityCommentsByID[comment.activityID] = restoredComments
            activityEngagementByID[comment.activityID] = previousSummary
            activityEngagementErrorByID[comment.activityID] = remoteErrorMessage(error)
            return false
        }
    }

    func activityBookmarkState(for visiblePlace: VisiblePlace) -> ActivityBookmarkState {
        guard let ownPlace = currentUserVisiblePlaces.first(where: {
            VisiblePlaceGrouping.matches($0, visiblePlace)
        }) else { return .notSaved }
        return ownPlace.userPlace.status == .wannaGo ? .wanna : .checkedIn
    }

    @discardableResult
    func removeActivityWanna(for visiblePlace: VisiblePlace, backend: WanderBackend?) async -> ActivityBookmarkState {
        guard let ownPlace = currentUserVisiblePlaces.first(where: {
            VisiblePlaceGrouping.matches($0, visiblePlace)
                && $0.userPlace.status == .wannaGo
        }) else {
            return activityBookmarkState(for: visiblePlace)
        }

        _ = await removeSave(userPlaceID: ownPlace.userPlace.id, backend: backend)
        return activityBookmarkState(for: visiblePlace)
    }

    private func seedFixtureActivityEngagement(for activity: [FeedActivity]) {
        let seedCounts = [(5, 2), (3, 1), (8, 3), (2, 0), (6, 1)]
        for (index, event) in activity.filter({ $0.place != nil }).enumerated()
            where activityEngagementByID[event.id] == nil {
            let seed = seedCounts[index % seedCounts.count]
            activityEngagementByID[event.id] = ActivityEngagementSummary(
                activityID: event.id,
                likeCount: seed.0,
                commentCount: seed.1
            )
        }
    }

    /// Clerk may report a signed-in user slightly before its first usable
    /// Supabase bearer token is available. Retry that narrow startup race once;
    /// ordinary transport and server failures remain visible to the caller.
    private func loadFollowedFeed(from repository: any FeedRepository) async throws -> FollowedFeedPage {
        do {
            return try await repository.followedFeed(before: nil, limit: 25)
        } catch {
            guard Self.shouldRetryFollowedFeed(after: error) else { throw error }
            try await Task.sleep(for: .milliseconds(300))
            return try await repository.followedFeed(before: nil, limit: 25)
        }
    }

    private static func shouldRetryFollowedFeed(after error: Error) -> Bool {
        if let authError = error as? AuthSessionError {
            return authError == .notSignedIn || authError == .tokenUnavailable
        }

        guard let remoteError = error as? WanderRemoteError else { return false }
        return remoteError == .notAuthenticated
    }

    private func fixtureFollowedFeedPage(relativeTo now: Date) -> FollowedFeedPage {
        let followedIDs = Set(following(of: currentUser.id).map(\.id))
        let followedPlaces = visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
            .filter { followedIDs.contains($0.owner.id) }
            .filter { !$0.owner.isPrivateProfile }
            .filter { !isMuted(userID: $0.owner.id) }

        func place(ownerID: String, placeID: String) -> VisiblePlace? {
            followedPlaces.first {
                $0.owner.id == ownerID && $0.place.id == placeID
            }
        }

        func actor(for visiblePlace: VisiblePlace) -> ProfileShell {
            shell(for: visiblePlace.owner)
        }

        func actorShell(for userID: String) -> ProfileShell? {
            profile(for: userID).map(shell(for:))
        }

        let mayaBarNido = place(ownerID: "user_maya", placeID: "place_bar_nido")
        let ryanNoodles = place(ownerID: "user_ryan", placeID: "place_noodles")
        let demoFernDesk = place(ownerID: "user_demo", placeID: "place_fern_desk_coffee")
        let ryanJuniper = place(ownerID: "user_ryan", placeID: "place_juniper_table")
        let mayaList = visiblePlaceLists.first { $0.id == "list_maya_sunset" }
        let ryanList = visiblePlaceLists.first { $0.id == "list_ryan_brooklyn_tables" }

        let activity = [
            mayaBarNido.map {
                FeedActivity(
                    id: "fixture-feed-maya-been-bar-nido",
                    kind: .placeBeen,
                    actor: actor(for: $0),
                    place: $0,
                    occurredAt: now.addingTimeInterval(-3 * 60 * 60),
                    note: $0.userPlace.note,
                    rating: $0.userPlace.ratingScore
                )
            },
            ryanNoodles.map {
                FeedActivity(
                    id: "fixture-feed-ryan-wanna-noodles",
                    kind: .placeWannaGo,
                    actor: actor(for: $0),
                    place: $0,
                    occurredAt: now.addingTimeInterval(-5 * 60 * 60),
                    note: $0.userPlace.note
                )
            },
            mayaList.flatMap { list in
                actorShell(for: list.ownerUserID).map { actor in
                FeedActivity(
                    id: "fixture-feed-maya-created-sunset-list",
                    kind: .listCreated,
                    actor: actor,
                    list: list,
                    occurredAt: now.addingTimeInterval(-9 * 60 * 60),
                    note: list.description
                )
                }
            },
            ryanJuniper.flatMap { visiblePlace in
                ryanList.map { list in
                    FeedActivity(
                        id: "fixture-feed-ryan-added-juniper-list",
                        kind: .listItemAdded,
                        actor: actor(for: visiblePlace),
                        place: visiblePlace,
                        list: list,
                        occurredAt: now.addingTimeInterval(-14 * 60 * 60),
                        rating: visiblePlace.userPlace.ratingScore
                    )
                }
            },
            demoFernDesk.map {
                FeedActivity(
                    id: "fixture-feed-demo-saved-fern-desk",
                    kind: .placeSaved,
                    actor: actor(for: $0),
                    place: $0,
                    occurredAt: now.addingTimeInterval(-26 * 60 * 60),
                    note: $0.userPlace.note
                )
            }
        ]
        .compactMap { $0 }

        let orderedActivity = FeedPresentation.newestFirst(activity, relativeTo: now)
        let savedPlaceIDs = Set(currentUserVisiblePlaces.map { $0.place.id })
        return FollowedFeedPage(
            activity: orderedActivity,
            featuredPlaces: FeedPresentation.featuredPlaces(
                from: orderedActivity,
                currentUserPlaceIDs: savedPlaceIDs,
                relativeTo: now
            ),
            nextCursor: nil,
            fetchedAt: now
        )
    }

    var effectiveDefaultVisibility: PlaceVisibility {
        isPrivateProfile ? .selfOnly : defaultVisibility.normalizedForStealthMode
    }

    func setPrivateProfile(_ enabled: Bool) {
        guard isPrivateProfile != enabled else { return }

        isPrivateProfile = enabled

        if enabled {
            makeCurrentUserContentPrivate()
        }
    }

    @discardableResult
    func updatePrivateProfile(_ enabled: Bool, backend: WanderBackend?) async -> Bool {
        guard let backend else {
            setPrivateProfile(enabled)
            persist()
            return true
        }

        do {
            let profile = try await backend.updateProfilePrivacy(
                isPrivateProfile: enabled,
                defaultVisibility: enabled ? .selfOnly : defaultVisibility.normalizedForStealthMode
            )
            applyRemoteCurrentProfile(profile)
            lastRemoteError = nil
            return true
        } catch {
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    var visiblePlaceLists: [LocalPlaceList] {
        placeLists
            .filter { list in
                guard list.deletedAt == nil else { return false }
                return canRead(list)
            }
            .sorted { lhs, rhs in
                if lhs.ownerUserID == currentUser.id && rhs.ownerUserID != currentUser.id { return true }
                if rhs.ownerUserID == currentUser.id && lhs.ownerUserID != currentUser.id { return false }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func visiblePlaceLists(scope: PlaceListScope) -> [LocalPlaceList] {
        visiblePlaceLists.filter { list in
            switch scope {
            case .mine:
                return list.ownerUserID == currentUser.id || isMember(of: list, userID: currentUser.id)
            case .friends:
                return list.ownerUserID != currentUser.id && !isMember(of: list, userID: currentUser.id)
            case .collabs:
                return isCollaborative(list)
                    && (list.ownerUserID == currentUser.id || isMember(of: list, userID: currentUser.id))
            }
        }
    }

    func canManage(_ list: LocalPlaceList) -> Bool {
        list.ownerUserID == currentUser.id
    }

    func canLeave(_ list: LocalPlaceList) -> Bool {
        !canManage(list) && isMember(of: list, userID: currentUser.id)
    }

    func canAddPlaces(to list: LocalPlaceList) -> Bool {
        canManage(list) || isMember(of: list, userID: currentUser.id)
    }

    private func isCollaborative(_ list: LocalPlaceList) -> Bool {
        placeListMembers.contains { member in
            member.listID == list.id && member.deletedAt == nil
        }
    }

    func collaborators(for list: LocalPlaceList) -> [LocalProfile] {
        placeListMembers
            .filter { $0.listID == list.id && $0.deletedAt == nil }
            .compactMap { member in profiles.first { $0.id == member.userID } }
            .filter { !isBlockedBetweenCurrentUser(and: $0.id) }
            .sorted { $0.handle < $1.handle }
    }

    func visiblePlaces(in list: LocalPlaceList) -> [VisiblePlace] {
        let candidates = visiblePlaces()
        let lookup = visiblePlaceListLookupCache ?? visiblePlaceListLookup(candidates: candidates)
        return listItems(for: list).compactMap { item in
            visiblePlace(for: item, lookup: lookup)
        }
    }

    func visiblePlacesByListID(in lists: [LocalPlaceList]) -> [String: [VisiblePlace]] {
        let listIDs = lists.map(\.id)
        if let cached = visiblePlacesByListIDCache, cached.listIDs == listIDs {
            return cached.placesByListID
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let candidates = visiblePlaces()
        let lookup = visiblePlaceListLookupCache ?? visiblePlaceListLookup(candidates: candidates)
        let candidatesReadyAt = CFAbsoluteTimeGetCurrent()
        let itemsByListID = visibleListItemsByListID(in: lists)
        let itemsReadyAt = CFAbsoluteTimeGetCurrent()
        visibleListFallbackResolutionCount = 0
        let placesByListID = Dictionary(uniqueKeysWithValues: lists.map { list in
            let visiblePlaces = itemsByListID[list.id, default: []].compactMap { item in
                visiblePlace(for: item, lookup: lookup)
            }
            return (list.id, visiblePlaces)
        })
        visiblePlacesByListIDCache = (listIDs, placesByListID)
        let finishedAt = CFAbsoluteTimeGetCurrent()
        WanderDebugLog.performance.notice(
            "list projection lists=\(lists.count, privacy: .public) candidates=\(candidates.count, privacy: .public) items=\(self.placeListItems.count, privacy: .public) fallbacks=\(self.visibleListFallbackResolutionCount, privacy: .public) candidate_ms=\((candidatesReadyAt - startedAt) * 1_000, privacy: .public) item_ms=\((itemsReadyAt - candidatesReadyAt) * 1_000, privacy: .public) resolve_ms=\((finishedAt - itemsReadyAt) * 1_000, privacy: .public)"
        )
        return placesByListID
    }

    func hasPlace(_ visiblePlace: VisiblePlace, in list: LocalPlaceList) -> Bool {
        listItems(for: list).contains { item in
            item.placeID == visiblePlace.place.id
                || item.ownerUserPlaceID == visiblePlace.userPlace.id
                || item.sourceUserPlaceID == visiblePlace.userPlace.id
        }
    }

    func hasCandidate(_ candidate: PlaceCandidate, in list: LocalPlaceList) -> Bool {
        guard let place = matchingPlace(for: candidate) else { return false }
        let placeIDs = Set([place.id, place.localID, place.serverID].compactMap { $0 })
        return listItems(for: list).contains { item in
            placeIDs.contains(item.placeID)
        }
    }

    func listSuggestions(for list: LocalPlaceList, limit: Int = 5) -> [ListPlaceSuggestion] {
        let existingPlaces = visiblePlaces(in: list)
        let existingPlaceIDs = Set(existingPlaces.map(\.place.id))
        let contextText = ([list.name, list.description] + existingPlaces.flatMap { visiblePlace in
            [
                visiblePlace.place.category,
                visiblePlace.place.locality,
                visiblePlace.place.region,
                visiblePlace.userPlace.note
            ]
            .compactMap { $0 }
        })
        .joined(separator: " ")
        .lowercased()
        let existingCategories = Set(existingPlaces.map { $0.place.category.lowercased() })
        let existingLocalities = Set(existingPlaces.compactMap { $0.place.locality?.lowercased() })
        let existingTags = Set(existingPlaces.flatMap { tagTokens(for: $0) })

        return visiblePlaces()
            .filter { !existingPlaceIDs.contains($0.place.id) }
            .map { visiblePlace in
                var score = 0.0
                var reasons: [String] = []
                let category = visiblePlace.place.category.lowercased()
                if existingCategories.contains(category) || contextText.contains(category) {
                    score += 4
                    reasons.append(visiblePlace.place.category)
                }
                if let locality = visiblePlace.place.locality?.lowercased(),
                   existingLocalities.contains(locality) || contextText.contains(locality) {
                    score += 2
                    reasons.append(visiblePlace.place.locality ?? locality)
                }
                let overlap = existingTags.intersection(tagTokens(for: visiblePlace))
                if !overlap.isEmpty {
                    score += Double(min(overlap.count, 3)) * 1.5
                    reasons.append(overlap.sorted().prefix(2).joined(separator: ", "))
                }
                if let rating = visiblePlace.recommendedScore {
                    score += max(0, rating - 3)
                }
                if visiblePlace.owner.id == currentUser.id {
                    score += 1
                }
                let reason = reasons.isEmpty ? "Similar to this list" : "Fits: \(reasons.prefix(2).joined(separator: " + "))"
                return ListPlaceSuggestion(visiblePlace: visiblePlace, reason: reason, score: score)
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.visiblePlace.place.canonicalName < $1.visiblePlace.place.canonicalName
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    func listSuggestions(for list: LocalPlaceList, limit: Int = 5, backend: WanderBackend?) async -> [ListPlaceSuggestion] {
        let fallback = listSuggestions(for: list, limit: limit)
        guard let backend else { return fallback }

        do {
            let response = try await backend.listSuggestions(payload: listSuggestionPayload(for: list, limit: limit))
            let candidatesByID = Dictionary(uniqueKeysWithValues: visiblePlaces().map { ($0.id, $0) })
            let remoteSuggestions = response.suggestions.compactMap { item -> ListPlaceSuggestion? in
                guard let visiblePlace = candidatesByID[item.visiblePlaceID],
                      !hasPlace(visiblePlace, in: list)
                else { return nil }
                return ListPlaceSuggestion(
                    visiblePlace: visiblePlace,
                    reason: item.reason,
                    score: item.score ?? 0
                )
            }
            return remoteSuggestions.isEmpty ? fallback : Array(remoteSuggestions.prefix(limit))
        } catch {
            lastRemoteError = remoteErrorMessage(error)
            return fallback
        }
    }

    @discardableResult
    func addVisiblePlace(_ visiblePlace: VisiblePlace, to list: LocalPlaceList, backend: WanderBackend?) async -> ListPlaceAddResult {
        guard canAddPlaces(to: list) else {
            return ListPlaceAddResult(outcome: .permissionDenied, createdWantSave: false, shouldExplainAutoSave: false)
        }
        guard !hasPlace(visiblePlace, in: list) else {
            return ListPlaceAddResult(outcome: .alreadyInList, createdWantSave: false, shouldExplainAutoSave: false)
        }

        let existingOwnSave = currentUserVisiblePlaces.first { currentUserPlace in
            VisiblePlaceGrouping.matches(currentUserPlace, visiblePlace)
        }
        var ownerUserPlaceID = existingOwnSave?.userPlace.id
        var createdWantSave = false
        if ownerUserPlaceID == nil && autoSaveListAddsToWant {
            let result = await saveVisiblePlace(visiblePlace, status: .wannaGo, backend: backend)
            ownerUserPlaceID = result.userPlaceID
            createdWantSave = true
        }

        let item = LocalPlaceListItem(
            localID: "local_list_item_\(slug(list.id))_\(slug(visiblePlace.place.canonicalName))_\(placeListItems.count + 1)",
            listID: list.id,
            placeID: visiblePlace.place.id,
            ownerUserPlaceID: ownerUserPlaceID,
            sourceUserPlaceID: visiblePlace.userPlace.id,
            addedByUserID: currentUser.id,
            syncState: .pendingCreate
        )
        placeListItems.append(item)
        if let index = placeLists.firstIndex(where: { $0.id == list.id }) {
            placeLists[index].updatedAt = .now
            if canManage(placeLists[index]) {
                placeLists[index].syncStateRaw = SyncState.pendingUpdate.rawValue
            }
            placeLists[index].cachedItemCount = listItems(for: placeLists[index]).count
        }
        persist()

        if let backend {
            await syncPlaceListItem(localOrServerID: item.id, listID: list.id, backend: backend)
        }

        return ListPlaceAddResult(outcome: .added, createdWantSave: createdWantSave, shouldExplainAutoSave: createdWantSave)
    }

    /// Adds an already-owned place to a list without rebuilding the visible
    /// place projection. Import batches use this inside a deferred-persistence
    /// transaction after saving the corresponding user place.
    @discardableResult
    func addCurrentUserPlace(
        userPlaceID: String,
        to list: LocalPlaceList
    ) -> ListPlaceAddResult {
        guard canAddPlaces(to: list),
              let userPlace = currentUserPlace(matching: userPlaceID)
        else {
            return ListPlaceAddResult(
                outcome: .permissionDenied,
                createdWantSave: false,
                shouldExplainAutoSave: false
            )
        }
        guard !listItems(for: list).contains(where: { item in
            item.placeID == userPlace.placeID
                || item.ownerUserPlaceID == userPlace.id
                || item.sourceUserPlaceID == userPlace.id
        }) else {
            return ListPlaceAddResult(
                outcome: .alreadyInList,
                createdWantSave: false,
                shouldExplainAutoSave: false
            )
        }

        let item = LocalPlaceListItem(
            localID: "local_list_item_\(slug(list.id))_\(slug(userPlace.placeID))_\(placeListItems.count + 1)",
            listID: list.id,
            placeID: userPlace.placeID,
            ownerUserPlaceID: userPlace.id,
            sourceUserPlaceID: userPlace.id,
            addedByUserID: currentUser.id,
            syncState: .pendingCreate
        )
        placeListItems.append(item)
        if let index = placeLists.firstIndex(where: { $0.id == list.id }) {
            placeLists[index].updatedAt = .now
            if canManage(placeLists[index]) {
                placeLists[index].syncStateRaw = SyncState.pendingUpdate.rawValue
            }
            placeLists[index].cachedItemCount = listItems(for: placeLists[index]).count
        }
        persist()
        return ListPlaceAddResult(
            outcome: .added,
            createdWantSave: false,
            shouldExplainAutoSave: false
        )
    }

    func addCandidate(_ candidate: PlaceCandidate, to list: LocalPlaceList, backend: WanderBackend?) async -> ListPlaceAddResult {
        guard canAddPlaces(to: list) else {
            return ListPlaceAddResult(outcome: .permissionDenied, createdWantSave: false, shouldExplainAutoSave: false)
        }

        if let existingVisiblePlace = matchingCurrentUserVisiblePlace(for: candidate) {
            return await addVisiblePlace(existingVisiblePlace, to: list, backend: backend)
        }

        if hasCandidate(candidate, in: list) {
            return ListPlaceAddResult(outcome: .alreadyInList, createdWantSave: false, shouldExplainAutoSave: false)
        }

        let saveResult = await saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: effectiveDefaultVisibility,
            note: nil,
            sourceType: .manual,
            backend: backend
        )

        guard let savedVisiblePlace = visiblePlaceForCurrentUser(userPlaceID: saveResult.userPlaceID) else {
            return ListPlaceAddResult(outcome: .permissionDenied, createdWantSave: true, shouldExplainAutoSave: true)
        }

        let result = await addVisiblePlace(savedVisiblePlace, to: list, backend: backend)
        return ListPlaceAddResult(
            outcome: result.outcome,
            createdWantSave: true,
            shouldExplainAutoSave: result.outcome == .added
        )
    }

    @discardableResult
    func removePlace(placeID: String, from list: LocalPlaceList) -> Bool {
        guard canManage(list),
              let itemIndex = placeListItems.firstIndex(where: { item in
                  item.listID == list.id
                      && item.placeID == placeID
                      && item.deletedAt == nil
              })
        else { return false }

        placeListItems[itemIndex].deletedAt = .now
        placeListItems[itemIndex].updatedAt = .now
        placeListItems[itemIndex].syncStateRaw = SyncState.pendingDelete.rawValue
        if let listIndex = placeLists.firstIndex(where: { $0.id == list.id }) {
            placeLists[listIndex].updatedAt = .now
            placeLists[listIndex].syncStateRaw = SyncState.pendingUpdate.rawValue
        }
        persist()
        return true
    }

    @discardableResult
    func createPlaceList(
        name: String,
        description: String,
        visibility: PlaceListVisibility,
        collaboratorUserIDs: [String] = []
    ) -> LocalPlaceList? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              CommunityContentPolicy.allows(trimmedName),
              CommunityContentPolicy.allows(description)
        else { return nil }

        let now = Date.now
        let list = LocalPlaceList(
            localID: "local_list_\(slug(currentUser.handle))_\(slug(trimmedName))_\(placeLists.count + 1)",
            ownerUserID: currentUser.id,
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibility,
            syncState: .pendingCreate,
            createdAt: now,
            updatedAt: now
        )
        placeLists.append(list)
        replaceCollaborators(for: list, with: collaboratorUserIDs, createdAt: now)
        let properties = [
            "visibility": visibility.rawValue,
            "collaborator_count": "\(Set(collaboratorUserIDs).count)"
        ]
        analytics.track(
            AnalyticsEvent(name: WanderAnalyticsEvents.placeListCreated, properties: properties)
        )
        analytics.track(
            .engagement(
                need: .expression,
                action: .listCreated,
                surface: "lists",
                properties: properties
            )
        )
        persist()
        return list
    }

    @discardableResult
    func updatePlaceList(
        id: String,
        name: String,
        description: String,
        visibility: PlaceListVisibility,
        collaboratorUserIDs: [String]
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              CommunityContentPolicy.allows(trimmedName),
              CommunityContentPolicy.allows(description),
              let index = placeLists.firstIndex(where: { $0.id == id || $0.localID == id || $0.serverID == id }),
              canManage(placeLists[index])
        else { return false }

        placeLists[index].name = trimmedName
        placeLists[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        placeLists[index].visibilityRaw = visibility.rawValue
        placeLists[index].updatedAt = .now
        if placeLists[index].syncState != .pendingCreate {
            placeLists[index].syncStateRaw = SyncState.pendingUpdate.rawValue
        }
        replaceCollaborators(for: placeLists[index], with: collaboratorUserIDs)
        persist()
        return true
    }

    @discardableResult
    func deletePlaceList(id: String) -> Bool {
        guard let index = placeLists.firstIndex(where: { $0.id == id || $0.localID == id || $0.serverID == id }),
              canManage(placeLists[index])
        else { return false }

        let now = Date.now
        let listID = placeLists[index].id
        placeLists[index].deletedAt = now
        placeLists[index].updatedAt = now
        placeLists[index].syncStateRaw = SyncState.pendingDelete.rawValue
        for memberIndex in placeListMembers.indices where placeListMembers[memberIndex].listID == listID {
            placeListMembers[memberIndex].deletedAt = now
        }
        for itemIndex in placeListItems.indices where placeListItems[itemIndex].listID == listID {
            placeListItems[itemIndex].deletedAt = now
            placeListItems[itemIndex].updatedAt = now
            placeListItems[itemIndex].syncStateRaw = SyncState.pendingDelete.rawValue
        }
        persist()
        return true
    }

    @discardableResult
    func setPlaceListCollaborators(listID: String, collaboratorUserIDs: [String]) -> Bool {
        guard let list = placeLists.first(where: { $0.id == listID || $0.localID == listID || $0.serverID == listID }),
              canManage(list)
        else { return false }

        replaceCollaborators(for: list, with: collaboratorUserIDs)
        if let index = placeLists.firstIndex(where: { $0.id == list.id }) {
            placeLists[index].updatedAt = .now
            if placeLists[index].syncState != .pendingCreate {
                placeLists[index].syncStateRaw = SyncState.pendingUpdate.rawValue
            }
        }
        persist()
        return true
    }

    @discardableResult
    func leavePlaceList(_ list: LocalPlaceList, backend: WanderBackend?) async -> Bool {
        guard canLeave(list) else { return false }

        guard let remoteListID = remoteID(list.serverID ?? list.id),
              let backend,
              backend.placeListRepository != nil
        else {
            markCurrentUserAsHavingLeft(list)
            lastRemoteError = nil
            return true
        }

        do {
            try await backend.leavePlaceList(listID: remoteListID)
            markCurrentUserAsHavingLeft(list)
            lastRemoteError = nil
            return true
        } catch {
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    @discardableResult
    func removePlace(placeID: String, from list: LocalPlaceList, backend: WanderBackend?) async -> Bool {
        let remoteListID = remoteID(list.serverID ?? list.id)
        let remoteItemID = placeListItems.first { item in
            item.listID == list.id
                && item.placeID == placeID
                && item.deletedAt == nil
        }.flatMap { remoteID($0.serverID) }

        let removed = removePlace(placeID: placeID, from: list)
        guard removed, let backend, let remoteListID, let remoteItemID else {
            return removed
        }

        do {
            try await backend.removePlaceListItem(listID: remoteListID, itemID: remoteItemID)
            if let index = placeListItems.firstIndex(where: { $0.serverID == remoteItemID }) {
                placeListItems[index].syncStateRaw = SyncState.tombstoned.rawValue
            }
            lastRemoteError = nil
            await refreshRemotePlaceLists(backend: backend)
        } catch {
            if let index = placeListItems.firstIndex(where: { $0.serverID == remoteItemID }) {
                placeListItems[index].syncStateRaw = SyncState.failed.rawValue
            }
            lastRemoteError = remoteErrorMessage(error)
            persist()
        }

        return removed
    }

    @discardableResult
    func syncPendingPlaceLists(backend: WanderBackend?) async -> Int {
        guard let backend else {
            #if DEBUG
            WanderDebugLog.sync.debug("place-list sync skipped reason=missing_backend")
            #endif
            return 0
        }

        if let placeListSyncTask {
            return await placeListSyncTask.task.value
        }

        let syncID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return 0 }
            return await self.performPendingPlaceListSync(backend: backend)
        }
        placeListSyncTask = (syncID, task)
        let syncedCount = await task.value
        if placeListSyncTask?.id == syncID {
            placeListSyncTask = nil
        }
        return syncedCount
    }

    private func performPendingPlaceListSync(backend: WanderBackend) async -> Int {
        var processedLocalIDs = Set<String>()
        var syncedCount = 0
        while let list = placeLists.first(where: { list in
            list.ownerUserID == currentUser.id
                && !processedLocalIDs.contains(list.localID)
                && isPendingPlaceListSyncCandidate(list)
        }) {
            processedLocalIDs.insert(list.localID)
            if await syncPlaceList(localOrServerID: list.id, backend: backend) {
                syncedCount += 1
            }
        }

        #if DEBUG
        WanderDebugLog.sync.debug("place-list sync completed synced_count=\(syncedCount, privacy: .public)")
        #endif

        return syncedCount
    }

    private func shouldBackfillLegacyPlaceList(_ list: LocalPlaceList) -> Bool {
        persistence != nil
            && list.deletedAt == nil
            && list.syncState != .tombstoned
            && remoteID(list.serverID ?? list.id) == nil
    }

    private func isPendingPlaceListSyncCandidate(_ list: LocalPlaceList) -> Bool {
        list.syncState == .pendingCreate
            || list.syncState == .pendingUpdate
            || list.syncState == .pendingDelete
            || list.syncState == .failed
            || shouldBackfillLegacyPlaceList(list)
    }

    private func shouldImmediatelyResyncPlaceList(localID: String) -> Bool {
        guard let list = placeLists.first(where: { $0.localID == localID }) else { return false }
        return list.syncState == .pendingCreate
            || list.syncState == .pendingUpdate
            || list.syncState == .pendingDelete
    }

    @discardableResult
    private func syncPlaceList(localOrServerID: String, backend: WanderBackend) async -> Bool {
        guard let list = placeLists.first(where: {
            $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID
        }) else { return false }

        let syncKey = list.localID
        if let existingTask = individualPlaceListSyncTasks[syncKey] {
            return await existingTask.task.value
        }

        let syncID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performPlaceListSync(localOrServerID: syncKey, backend: backend)
        }
        individualPlaceListSyncTasks[syncKey] = (syncID, task)
        let succeeded = await task.value
        if individualPlaceListSyncTasks[syncKey]?.id == syncID {
            individualPlaceListSyncTasks[syncKey] = nil
        }
        if shouldImmediatelyResyncPlaceList(localID: syncKey) {
            return await syncPlaceList(localOrServerID: syncKey, backend: backend)
        }
        return succeeded
    }

    @discardableResult
    private func performPlaceListSync(localOrServerID: String, backend: WanderBackend) async -> Bool {
        guard let index = placeLists.firstIndex(where: { $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID }),
              canManage(placeLists[index])
        else { return false }

        let list = placeLists[index]
        let previousID = list.id

        if list.deletedAt != nil || list.syncState == .pendingDelete {
            guard let remoteListID = remoteID(list.serverID ?? list.id) else {
                placeLists[index].syncStateRaw = SyncState.tombstoned.rawValue
                persist()
                return true
            }

            do {
                try await backend.deletePlaceList(listID: remoteListID)
                if let currentIndex = placeLists.firstIndex(where: { $0.id == previousID || $0.serverID == remoteListID }) {
                    placeLists[currentIndex].syncStateRaw = SyncState.tombstoned.rawValue
                }
                lastRemoteError = nil
                persist()
                return true
            } catch {
                if let currentIndex = placeLists.firstIndex(where: { $0.id == previousID || $0.serverID == remoteListID }) {
                    placeLists[currentIndex].syncStateRaw = SyncState.failed.rawValue
                }
                lastRemoteError = remoteErrorMessage(error)
                persist()
                return false
            }
        }

        let collaboratorUserIDs = placeListMembers
            .filter { $0.listID == previousID && $0.deletedAt == nil }
            .map(\.userID)
            .filter { $0 != currentUser.id }
            .sorted()
        let draft = PlaceListUpsertDraft(
            id: remoteID(list.serverID ?? list.id),
            name: list.name,
            description: list.description,
            visibility: list.visibility
        )

        #if DEBUG
        WanderDebugLog.sync.debug("place-list sync attempt list=\(WanderDebugLog.shortID(previousID), privacy: .public) state=\(list.syncState.rawValue, privacy: .public) has_remote_id=\((draft.id != nil), privacy: .public) collaborator_count=\(collaboratorUserIDs.count, privacy: .public)")
        #endif

        do {
            let remoteListID = try await backend.upsertPlaceList(draft)
            if let currentIndex = placeLists.firstIndex(where: { $0.id == previousID || $0.localID == list.localID || $0.serverID == remoteListID }) {
                placeLists[currentIndex].serverID = remoteListID
                replaceListIDReferences(previousID: previousID, canonicalID: placeLists[currentIndex].id)
                placeLists[currentIndex].cachedItemCount = listItems(for: placeLists[currentIndex]).count
            }

            try await backend.setPlaceListCollaborators(listID: remoteListID, userIDs: collaboratorUserIDs)

            let itemIDs = placeListItems
                .filter { $0.listID == remoteListID && $0.deletedAt == nil && $0.syncState != .synced }
                .map(\.id)
            for itemID in itemIDs {
                await syncPlaceListItem(localOrServerID: itemID, listID: remoteListID, backend: backend)
            }

            if let currentIndex = placeLists.firstIndex(where: { $0.localID == list.localID }),
               placeListMatchesSnapshot(placeLists[currentIndex], snapshot: list, collaboratorUserIDs: collaboratorUserIDs) {
                placeLists[currentIndex].syncStateRaw = SyncState.synced.rawValue
            }

            lastRemoteError = nil
            #if DEBUG
            WanderDebugLog.sync.debug("place-list sync success local_list=\(WanderDebugLog.shortID(previousID), privacy: .public) remote_list=\(WanderDebugLog.shortID(remoteListID), privacy: .public)")
            #endif
            persist()
            return true
        } catch {
            if let currentIndex = placeLists.firstIndex(where: { $0.id == previousID || $0.localID == list.localID }) {
                if placeListMatchesSnapshot(placeLists[currentIndex], snapshot: list, collaboratorUserIDs: collaboratorUserIDs) {
                    placeLists[currentIndex].syncStateRaw = SyncState.failed.rawValue
                }
            }
            lastRemoteError = remoteErrorMessage(error)
            #if DEBUG
            WanderDebugLog.sync.error("place-list sync failed list=\(WanderDebugLog.shortID(previousID), privacy: .public) error=\(WanderDebugLog.clean(self.lastRemoteError ?? String(describing: error)), privacy: .public)")
            #endif
            persist()
            return false
        }
    }

    private func placeListMatchesSnapshot(
        _ current: LocalPlaceList,
        snapshot: LocalPlaceList,
        collaboratorUserIDs: [String]
    ) -> Bool {
        current.name == snapshot.name
            && current.description == snapshot.description
            && current.visibilityRaw == snapshot.visibilityRaw
            && current.updatedAt == snapshot.updatedAt
            && current.deletedAt == snapshot.deletedAt
            && activeCollaboratorUserIDs(for: current) == collaboratorUserIDs
    }

    private func activeCollaboratorUserIDs(for list: LocalPlaceList) -> [String] {
        let listIDs = listReferenceIDs(for: list)
        return placeListMembers
            .filter { listIDs.contains($0.listID) && $0.deletedAt == nil }
            .map(\.userID)
            .filter { $0 != currentUser.id }
            .sorted()
    }

    private func syncPlaceListItem(localOrServerID: String, listID: String, backend: WanderBackend) async {
        guard let initialItem = placeListItems.first(where: { item in
            item.id == localOrServerID || item.localID == localOrServerID || item.serverID == localOrServerID
        }) else {
            return
        }

        if remoteID(initialItem.listID) == nil {
            _ = await syncPlaceList(localOrServerID: listID, backend: backend)
        }

        guard let itemIndex = placeListItems.firstIndex(where: { item in
            item.id == localOrServerID || item.localID == localOrServerID || item.serverID == localOrServerID
        }),
              placeListItems[itemIndex].deletedAt == nil,
              placeListItems[itemIndex].syncState != .synced,
              let draft = remoteItemDraft(for: placeListItems[itemIndex])
        else {
            return
        }

        do {
            let remoteItemID = try await backend.addPlaceListItem(draft)
            placeListItems[itemIndex].serverID = remoteItemID
            placeListItems[itemIndex].syncStateRaw = SyncState.synced.rawValue
            if let listIndex = placeLists.firstIndex(where: { $0.id == draft.listID || $0.serverID == draft.listID }) {
                placeLists[listIndex].syncStateRaw = SyncState.synced.rawValue
                placeLists[listIndex].cachedItemCount = listItems(for: placeLists[listIndex]).count
                placeLists[listIndex].updatedAt = .now
            }
            lastRemoteError = nil
            persist()
        } catch {
            placeListItems[itemIndex].syncStateRaw = SyncState.failed.rawValue
            lastRemoteError = remoteErrorMessage(error)
            persist()
        }
    }

    private func remoteItemDraft(for item: LocalPlaceListItem) -> PlaceListItemDraft? {
        guard let listID = remoteID(item.listID),
              let placeID = remotePlaceID(for: item.placeID)
        else {
            return nil
        }

        let ownerUserPlaceID = item.ownerUserPlaceID.flatMap(remoteUserPlaceID)
        let sourceUserPlaceID = item.sourceUserPlaceID.flatMap(remoteUserPlaceID)
        guard ownerUserPlaceID != nil || sourceUserPlaceID != nil else {
            return nil
        }

        return PlaceListItemDraft(
            listID: listID,
            placeID: placeID,
            ownerUserPlaceID: ownerUserPlaceID,
            sourceUserPlaceID: sourceUserPlaceID
        )
    }

    private func remotePlaceID(for localOrServerID: String) -> String? {
        if let remoteID = remoteID(localOrServerID) {
            return remoteID
        }

        return places.first { place in
            place.id == localOrServerID || place.localID == localOrServerID || place.serverID == localOrServerID
        }.flatMap { place in
            remoteID(place.serverID ?? place.id)
        }
    }

    private func remoteUserPlaceID(for localOrServerID: String) -> String? {
        if let remoteID = remoteID(localOrServerID) {
            return remoteID
        }

        return userPlaces.first { userPlace in
            userPlace.id == localOrServerID || userPlace.localID == localOrServerID || userPlace.serverID == localOrServerID
        }.flatMap { userPlace in
            remoteID(userPlace.serverID ?? userPlace.id)
        }
    }

    private func remoteID(_ value: String?) -> String? {
        guard let value, UUID(uuidString: value) != nil else { return nil }
        return value
    }

    private func canRead(_ list: LocalPlaceList) -> Bool {
        guard !isBlockedBetweenCurrentUser(and: list.ownerUserID) else { return false }
        if list.ownerUserID == currentUser.id { return true }
        if isMember(of: list, userID: currentUser.id) { return true }
        guard !list.isStealth else { return false }
        let relationship = relationship(to: list.ownerUserID)
        return relationship == .follower || relationship == .mutual
    }

    private func replaceCollaborators(for list: LocalPlaceList, with collaboratorUserIDs: [String], createdAt: Date = .now) {
        let allowedUserIDs = Set(
            collaboratorUserIDs
                .filter { $0 != currentUser.id }
                .filter { userID in profiles.contains { $0.id == userID } }
        )
        let listID = list.id
        let listIDs = listReferenceIDs(for: list)
        for memberIndex in placeListMembers.indices where listIDs.contains(placeListMembers[memberIndex].listID) {
            let memberUserID = placeListMembers[memberIndex].userID
            if allowedUserIDs.contains(memberUserID) {
                placeListMembers[memberIndex].deletedAt = nil
                placeListMembers[memberIndex].roleRaw = PlaceListRole.collaborator.rawValue
            } else {
                placeListMembers[memberIndex].deletedAt = .now
            }
        }

        let existingUserIDs = Set(placeListMembers.filter { listIDs.contains($0.listID) }.map(\.userID))
        for userID in allowedUserIDs where !existingUserIDs.contains(userID) {
            placeListMembers.append(
                LocalPlaceListMember(
                    localID: "local_list_member_\(slug(listID))_\(slug(userID))",
                    listID: listID,
                    userID: userID,
                    role: .collaborator,
                    createdAt: createdAt
                )
            )
        }
    }

    private func isMember(of list: LocalPlaceList, userID: String) -> Bool {
        let listIDs = listReferenceIDs(for: list)
        return placeListMembers.contains { member in
            listIDs.contains(member.listID) && member.userID == userID && member.deletedAt == nil
        }
    }

    private func markCurrentUserAsHavingLeft(_ list: LocalPlaceList) {
        let listIDs = listReferenceIDs(for: list)
        let now = Date.now
        for memberIndex in placeListMembers.indices where
            listIDs.contains(placeListMembers[memberIndex].listID)
                && placeListMembers[memberIndex].userID == currentUser.id
                && placeListMembers[memberIndex].deletedAt == nil {
            placeListMembers[memberIndex].deletedAt = now
        }
        persist()
    }

    private func listItems(for list: LocalPlaceList) -> [LocalPlaceListItem] {
        let listIDs = listReferenceIDs(for: list)
        return placeListItems
            .filter { listIDs.contains($0.listID) && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func listReferenceIDs(for list: LocalPlaceList) -> Set<String> {
        Set([list.id, list.localID, list.serverID].compactMap { $0 })
    }

    private func visibleListItemsByListID(in lists: [LocalPlaceList]) -> [String: [LocalPlaceListItem]] {
        var canonicalListIDByReferenceID: [String: String] = [:]
        canonicalListIDByReferenceID.reserveCapacity(lists.count * 2)
        for list in lists {
            for referenceID in listReferenceIDs(for: list) {
                canonicalListIDByReferenceID[referenceID] = list.id
            }
        }

        var itemsByListID: [String: [LocalPlaceListItem]] = [:]
        itemsByListID.reserveCapacity(lists.count)
        for item in placeListItems where item.deletedAt == nil {
            guard let canonicalListID = canonicalListIDByReferenceID[item.listID] else { continue }
            itemsByListID[canonicalListID, default: []].append(item)
        }
        for listID in itemsByListID.keys {
            itemsByListID[listID]?.sort { $0.createdAt < $1.createdAt }
        }
        return itemsByListID
    }

    private func visiblePlaceListLookup(candidates: [VisiblePlace]) -> VisiblePlaceListLookup {
        var lookup = VisiblePlaceListLookup(
            byUserPlaceID: [:],
            byPlaceID: [:],
            knownPlaceIDs: Set(
                places.flatMap { place in
                    [place.id, place.localID] + [place.serverID].compactMap { $0 }
                }
            )
        )
        lookup.byUserPlaceID.reserveCapacity(candidates.count * 2)
        lookup.byPlaceID.reserveCapacity(candidates.count * 2)

        for (index, candidate) in candidates.enumerated() {
            indexVisiblePlace(candidate, userPlaceID: candidate.id, placeID: candidate.place.id, at: index, in: &lookup)
        }

        return lookup
    }

    private func indexVisiblePlace(
        _ visiblePlace: VisiblePlace,
        userPlaceID: String,
        placeID: String,
        at index: Int,
        in lookup: inout VisiblePlaceListLookup
    ) {
        let ranked = RankedVisiblePlace(index: index, visiblePlace: visiblePlace)
        let userPlaceIDs = Set(
            [userPlaceID, visiblePlace.id, visiblePlace.userPlace.id, visiblePlace.userPlace.localID]
                + [visiblePlace.userPlace.serverID].compactMap { $0 }
        )
        for referenceID in userPlaceIDs where lookup.byUserPlaceID[referenceID] == nil {
            lookup.byUserPlaceID[referenceID] = ranked
        }

        let placeIDs = Set(
            [placeID, visiblePlace.place.id, visiblePlace.place.localID]
                + [visiblePlace.place.serverID].compactMap { $0 }
        )
        for referenceID in placeIDs where lookup.byPlaceID[referenceID] == nil {
            lookup.byPlaceID[referenceID] = ranked
        }
    }

    private func visiblePlace(for item: LocalPlaceListItem, lookup: VisiblePlaceListLookup) -> VisiblePlace? {
        if let ownerUserPlaceID = item.ownerUserPlaceID,
           let ownerMatch = lookup.byUserPlaceID[ownerUserPlaceID] {
            return ownerMatch.visiblePlace
        }

        if let sourceUserPlaceID = item.sourceUserPlaceID,
           let sourceMatch = lookup.byUserPlaceID[sourceUserPlaceID] {
            return sourceMatch.visiblePlace
        }

        if let samePlaceMatch = lookup.byPlaceID[item.placeID] {
            return samePlaceMatch.visiblePlace
        }

        // A canonical place with no indexed candidate is not visible to the current user.
        // Only pay for the compatibility scan when the item may use a legacy/local alias.
        guard !lookup.knownPlaceIDs.contains(item.placeID) else { return nil }

        visibleListFallbackResolutionCount += 1
        return fallbackVisiblePlace(for: item)
    }

    private func matchingCurrentUserVisiblePlace(for candidate: PlaceCandidate) -> VisiblePlace? {
        currentUserVisiblePlaces.first { visiblePlace in
            candidateMatches(candidate, place: visiblePlace.place)
        }
    }

    private func matchingPlace(for candidate: PlaceCandidate) -> LocalPlace? {
        places.first { place in
            candidateMatches(candidate, place: place)
        }
    }

    private func candidateMatches(_ candidate: PlaceCandidate, place: LocalPlace) -> Bool {
        VisiblePlaceGrouping.matches(place, candidate: candidate)
    }

    private func visiblePlaceForCurrentUser(userPlaceID: String) -> VisiblePlace? {
        guard let userPlace = userPlaces.first(where: { userPlace in
            userPlace.userID == currentUser.id
                && userPlace.deletedAt == nil
                && (userPlace.id == userPlaceID || userPlace.localID == userPlaceID || userPlace.serverID == userPlaceID)
        }),
              let place = places.first(where: { place in
                  place.id == userPlace.placeID || place.localID == userPlace.placeID || place.serverID == userPlace.placeID
              })
        else { return nil }

        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: currentUser)
    }

    private func fallbackVisiblePlace(for item: LocalPlaceListItem) -> VisiblePlace? {
        let placeIDs = matchingPlaceIDs(item.placeID)
        guard let place = places.first(where: { place in
            placeIDs.contains(place.id)
                || placeIDs.contains(place.localID)
                || place.serverID.map(placeIDs.contains) == true
        }) else {
            return nil
        }

        let preferredUserPlaceIDs = [item.ownerUserPlaceID, item.sourceUserPlaceID].compactMap { $0 }
        let samePlaceUserPlaces = userPlaces.filter { userPlace in
            userPlace.deletedAt == nil
                && placeIDs.contains(userPlace.placeID)
        }
        let preferredUserPlace = preferredUserPlaceIDs.compactMap { userPlaceID in
            samePlaceUserPlaces.first { userPlace in
                userPlace.id == userPlaceID || userPlace.localID == userPlaceID || userPlace.serverID == userPlaceID
            }
        }.first
        let currentUserPlace = samePlaceUserPlaces.first { $0.userID == currentUser.id }
        let visibleSocialPlace = samePlaceUserPlaces.first { userPlace in
            guard let owner = profiles.first(where: { $0.id == userPlace.userID }) else { return false }
            return visibilityPolicy.canSeePlace(
                viewerID: currentUser.id,
                ownerID: owner.id,
                visibility: userPlace.visibility,
                relationship: relationship(to: owner.id),
                isBlocked: isBlockedBetweenCurrentUser(and: owner.id)
            )
        }

        guard let userPlace = preferredUserPlace ?? currentUserPlace ?? visibleSocialPlace,
              let owner = profiles.first(where: { $0.id == userPlace.userID })
        else {
            return nil
        }

        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner,
            attributes: attributes(for: userPlace.id)
        )
    }

    private func listSuggestionPayload(for list: LocalPlaceList, limit: Int) -> ListSuggestionPayload {
        let existingPlaces = visiblePlaces(in: list)
        let existingPlaceIDs = Set(existingPlaces.map(\.place.id))
        let candidates = visiblePlaces()
            .filter { !existingPlaceIDs.contains($0.place.id) }
            .sorted { lhs, rhs in
                if lhs.owner.id == currentUser.id && rhs.owner.id != currentUser.id { return true }
                if rhs.owner.id == currentUser.id && lhs.owner.id != currentUser.id { return false }
                return lhs.place.canonicalName < rhs.place.canonicalName
            }

        return ListSuggestionPayload(
            listID: list.id,
            title: list.name,
            description: list.description,
            existingPlaces: existingPlaces.map(listSuggestionPlacePayload),
            candidatePlaces: candidates.map(listSuggestionPlacePayload),
            limit: limit
        )
    }

    private func listSuggestionPlacePayload(_ visiblePlace: VisiblePlace) -> ListSuggestionPlacePayload {
        let attributesText = attributes(for: visiblePlace.userPlace.id)
            .map(\.valueJSON)
            .joined(separator: " ")
        return ListSuggestionPlacePayload(
            visiblePlaceID: visiblePlace.id,
            placeID: visiblePlace.place.id,
            name: visiblePlace.place.canonicalName,
            category: visiblePlace.place.category,
            locality: visiblePlace.place.locality,
            region: visiblePlace.place.region,
            status: visiblePlace.userPlace.status,
            ratingScore: visiblePlace.userPlace.ratingScore,
            recommendedScore: visiblePlace.userPlace.recommendedScore,
            recommendedCount: visiblePlace.userPlace.recommendedCount,
            attributesText: attributesText
        )
    }

    func visiblePlaces(filters: PlaceFilters = PlaceFilters()) -> [VisiblePlace] {
        if let cached = visiblePlacesCache.first(where: { $0.filters == filters }) {
            return cached.places
        }

        #if DEBUG
        visiblePlaceProjectionBuildCount += 1
        #endif
        let localProjection = localVisiblePlaces(filters: filters)
        let remoteProjection = remoteVisiblePlaces(filters: filters)
        let projected = mergeVisiblePlaces(localProjection.places + remoteProjection)
        if filters == PlaceFilters() {
            var lookup = localProjection.listLookup
            for (offset, visiblePlace) in remoteProjection.enumerated() {
                indexVisiblePlace(
                    visiblePlace,
                    userPlaceID: visiblePlace.id,
                    placeID: visiblePlace.place.id,
                    at: localProjection.places.count + offset,
                    in: &lookup
                )
            }
            visiblePlaceListLookupCache = lookup
        }
        if visiblePlacesCache.count >= 16 {
            visiblePlacesCache.removeFirst()
        }
        visiblePlacesCache.append((filters: filters, places: projected))
        return projected
    }

    private func localVisiblePlaces(filters: PlaceFilters = PlaceFilters()) -> LocalVisiblePlaceProjection {
        let attributesByUserPlaceID = Dictionary(grouping: placeAttributes, by: \.userPlaceID)
        let placesByID = places.reduce(into: [String: LocalPlace]()) { result, place in
            if result[place.id] == nil {
                result[place.id] = place
            }
        }
        let profilesByID = profiles.reduce(into: [String: LocalProfile]()) { result, profile in
            if result[profile.id] == nil {
                result[profile.id] = profile
            }
        }
        let normalizedCategories = filters.normalizedCategories
        var visiblePlaces: [VisiblePlace] = []
        visiblePlaces.reserveCapacity(userPlaces.count)
        var listLookup = VisiblePlaceListLookup(
            byUserPlaceID: [:],
            byPlaceID: [:],
            knownPlaceIDs: Set(
                places.flatMap { place in
                    [place.id, place.localID] + [place.serverID].compactMap { $0 }
                }
            )
        )
        listLookup.byUserPlaceID.reserveCapacity(userPlaces.count)
        listLookup.byPlaceID.reserveCapacity(places.count)

        for userPlace in userPlaces {
            let userPlaceID = userPlace.id
            let placeID = userPlace.placeID
            guard userPlace.deletedAt == nil,
                  let place = placesByID[placeID],
                  let owner = profilesByID[userPlace.userID]
            else { continue }

            let relationship = relationship(to: owner.id)
            let blocked = isBlockedBetweenCurrentUser(and: owner.id)
            guard visibilityPolicy.canSeePlace(
                viewerID: currentUser.id,
                ownerID: owner.id,
                visibility: userPlace.visibility,
                relationship: relationship,
                isBlocked: blocked
            ) else { continue }

            let userPlaceIDs = Set([userPlace.id, userPlace.localID, userPlace.serverID].compactMap { $0 })
            let visibleAttributes = userPlaceIDs
                .flatMap { attributesByUserPlaceID[$0] ?? [] }
                .sorted { $0.questionKey < $1.questionKey }
            let visiblePlace = VisiblePlace(
                id: userPlaceID,
                place: place,
                userPlace: userPlace,
                owner: owner,
                attributes: visibleAttributes
            )
            guard filters.statuses.isEmpty || filters.statuses.contains(userPlace.status) else { continue }
            guard normalizedCategories.isEmpty || normalizedCategories.contains(visiblePlace.effectiveCategory) else { continue }
            guard filters.ownerIDs.isEmpty || filters.ownerIDs.contains(owner.id) else { continue }

            if !filters.ownerScopes.isEmpty {
                let isMine = owner.id == currentUser.id
                let isFriend = relationship == .mutual
                let isFollowing = relationship == .follower || relationship == .mutual
                let allowed = (filters.ownerScopes.contains("you") && isMine)
                    || (filters.ownerScopes.contains("friends") && isFriend)
                    || (filters.ownerScopes.contains("following") && isFollowing && !isMine)
                    || (filters.ownerScopes.contains("social") && !isMine)
                guard allowed else { continue }
            }

            let index = visiblePlaces.count
            visiblePlaces.append(visiblePlace)
            indexVisiblePlace(visiblePlace, userPlaceID: userPlaceID, placeID: placeID, at: index, in: &listLookup)
        }

        return LocalVisiblePlaceProjection(places: visiblePlaces, listLookup: listLookup)
    }

    private func remoteVisiblePlaces(filters: PlaceFilters) -> [VisiblePlace] {
        remoteVisiblePlaceCache
            .map(visiblePlaceWithLatestOwner)
            .filter { visiblePlace in
                guard !isBlockedBetweenCurrentUser(and: visiblePlace.owner.id) else { return false }
                guard filters.statuses.isEmpty || filters.statuses.contains(visiblePlace.userPlace.status) else { return false }
                let normalizedCategories = filters.normalizedCategories
                guard normalizedCategories.isEmpty || normalizedCategories.contains(visiblePlace.effectiveCategory) else { return false }
                guard filters.ownerIDs.isEmpty || filters.ownerIDs.contains(visiblePlace.owner.id) else { return false }

                guard !filters.ownerScopes.isEmpty else { return true }

                let isMine = visiblePlace.owner.id == currentUser.id
                let relationship = relationship(to: visiblePlace.owner.id)
                let isFriend = relationship == .mutual
                return (filters.ownerScopes.contains("you") && isMine)
                    || (filters.ownerScopes.contains("friends") && !isMine && (isFriend || visiblePlace.userPlace.visibility == .mutuals))
                    || (filters.ownerScopes.contains("following") && !isMine)
                    || (filters.ownerScopes.contains("social") && !isMine)
            }
    }

    private func visiblePlaceWithLatestOwner(_ visiblePlace: VisiblePlace) -> VisiblePlace {
        guard let owner = profiles.first(where: { $0.id == visiblePlace.owner.id || $0.handle == visiblePlace.owner.handle }) else {
            return visiblePlace
        }

        return VisiblePlace(
            id: visiblePlace.id,
            place: visiblePlace.place,
            userPlace: visiblePlace.userPlace,
            owner: owner,
            attributes: visiblePlace.attributes
        )
    }

    private func mergeVisiblePlaces(_ places: [VisiblePlace]) -> [VisiblePlace] {
        var seen = Set<String>()
        var merged: [VisiblePlace] = []

        for visiblePlace in places where !seen.contains(visiblePlace.id) {
            seen.insert(visiblePlace.id)
            merged.append(visiblePlace)
        }

        return merged
    }

    private func mergeCalendarVisiblePlaces(_ places: [VisiblePlace]) -> [VisiblePlace] {
        var seenReferenceIDs = Set<String>()
        var merged: [VisiblePlace] = []

        for visiblePlace in places {
            let referenceIDs = Self.referenceIDs(for: visiblePlace.userPlace)
            guard referenceIDs.isDisjoint(with: seenReferenceIDs) else { continue }
            seenReferenceIDs.formUnion(referenceIDs)
            merged.append(visiblePlace)
        }

        return merged
    }

    private func mergeCalendarVisits(
        _ visits: [LocalPlaceVisit],
        isAuthoritative: Bool
    ) -> [LocalPlaceVisit] {
        let ordered = visits.enumerated().sorted { lhs, rhs in
            let lhsPriority = Self.calendarVisitMergePriority(
                lhs.element,
                isAuthoritative: isAuthoritative
            )
            let rhsPriority = Self.calendarVisitMergePriority(
                rhs.element,
                isAuthoritative: isAuthoritative
            )
            return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
        }
        var seenReferenceIDs = Set<String>()
        var merged: [LocalPlaceVisit] = []

        for entry in ordered {
            let referenceIDs = Self.referenceIDs(for: entry.element)
            guard referenceIDs.isDisjoint(with: seenReferenceIDs) else { continue }
            seenReferenceIDs.formUnion(referenceIDs)
            merged.append(entry.element)
        }

        return merged
    }

    private static func calendarVisitMergePriority(
        _ visit: LocalPlaceVisit,
        isAuthoritative: Bool
    ) -> Int {
        if visit.syncState != .synced {
            return 0
        }
        if isSyntheticRemoteProfileVisit(visit) {
            return isAuthoritative ? 1 : 2
        }
        return isAuthoritative ? 2 : 1
    }

    private static func isSyntheticRemoteProfileVisit(_ visit: LocalPlaceVisit) -> Bool {
        visit.localID.hasPrefix("remote_profile_visit_")
    }

    private static func referenceIDs(for userPlace: LocalUserPlace) -> Set<String> {
        Set([userPlace.id, userPlace.localID, userPlace.serverID].compactMap { $0 })
    }

    private static func referenceIDs(for visit: LocalPlaceVisit) -> Set<String> {
        Set([visit.id, visit.localID, visit.serverID].compactMap { $0 })
    }

    func visiblePlaces(for profileID: String) -> [VisiblePlace] {
        visiblePlaces().filter { $0.owner.id == profileID }
    }

    func visiblePlaceCountsByOwnerID() -> [String: Int] {
        if let visiblePlaceCountsByOwnerIDCache {
            return visiblePlaceCountsByOwnerIDCache
        }

        #if DEBUG
        visiblePlaceOwnerCountBuildCount += 1
        #endif
        let counts = visiblePlaces().reduce(into: [String: Int]()) { result, visiblePlace in
            result[visiblePlace.owner.id, default: 0] += 1
        }
        visiblePlaceCountsByOwnerIDCache = counts
        return counts
    }

    func profile(for profileID: String) -> LocalProfile? {
        profiles.first { $0.id == profileID }
    }

    func placesInCommon(with profileID: String) -> [VisiblePlace] {
        guard profileID != currentUser.id else { return [] }
        let mine = VisiblePlaceGrouping.representativePlaces(
            from: currentUserVisiblePlaces,
            currentUserID: currentUser.id
        )
        let theirs = VisiblePlaceGrouping.representativePlaces(
            from: visiblePlaces(for: profileID),
            currentUserID: currentUser.id
        )
        return theirs.filter { theirPlace in
            mine.contains { myPlace in
                VisiblePlaceGrouping.matches(myPlace, theirPlace)
            }
        }
    }

    func attributes(for userPlaceID: String) -> [LocalPlaceAttribute] {
        let userPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        return placeAttributes
            .filter { userPlaceIDs.contains($0.userPlaceID) }
            .sorted { $0.questionKey < $1.questionKey }
    }

    func visits(for userPlaceID: String) -> [LocalPlaceVisit] {
        let userPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        return placeVisits
            .filter { userPlaceIDs.contains($0.userPlaceID) && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.visitedAt != rhs.visitedAt {
                    return lhs.visitedAt > rhs.visitedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func photos(for visitID: String) -> [LocalVisitPhoto] {
        let visitIDs = matchingVisitIDs(visitID)
        return visitPhotos
            .filter { visitIDs.contains($0.visitID) && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var deletedVisitPhotoReferenceIDs: Set<String> {
        visitPhotos.reduce(into: Set<String>()) { result, photo in
            guard photo.deletedAt != nil else { return }
            result.insert(photo.localID)
            if let serverID = photo.serverID {
                result.insert(serverID)
            }
        }
    }

    @discardableResult
    func applySharedVisitAcceptance(
        invitation: SharedVisitInvitation,
        draft: SharedVisitAcceptanceDraft,
        result: SharedVisitAcceptanceResult
    ) -> LocalPlaceVisit {
        let place = upsertPlace(from: invitation.candidate, sourceType: .socialSave)
        let now = Date.now
        let streakSummaryBeforeSave = saveStreakSummary
        let userPlace: LocalUserPlace
        let createdNewUserPlace: Bool

        if let existing = userPlaces.first(where: {
            $0.userID == currentUser.id
                && $0.deletedAt == nil
                && matchingPlaceIDs(place.id).contains($0.placeID)
        }) {
            if existing.status == .wannaGo {
                preserveHistoricalWant(for: existing, attributes: attributeDrafts(for: existing.id))
            }
            existing.serverID = result.userPlaceID
            existing.placeID = place.id
            existing.statusRaw = PlaceStatus.been.rawValue
            existing.visibilityRaw = draft.visibility.rawValue
            existing.note = draft.note
            existing.ratingScore = PlaceRating.normalized(draft.ratingScore)
            existing.visitedAt = draft.visitedAt
            existing.sourceType = AddSourceType.socialSave.rawValue
            existing.sourceUserPlaceID = nil
            existing.attributionUserID = invitation.sourceOwnerUserID
            existing.syncStateRaw = SyncState.synced.rawValue
            existing.serverUpdatedAt = now
            existing.lastSyncError = nil
            existing.updatedAt = now
            existing.localUpdatedAt = now
            userPlace = existing
            createdNewUserPlace = false
        } else {
            userPlace = LocalUserPlace(
                localID: "local_up_shared_\(result.userPlaceID)",
                serverID: result.userPlaceID,
                userID: currentUser.id,
                placeID: place.id,
                status: .been,
                visibility: draft.visibility,
                note: draft.note,
                ratingScore: draft.ratingScore,
                nearbyConfirmed: false,
                visitedAt: draft.visitedAt,
                savedAt: now,
                sourceType: AddSourceType.socialSave.rawValue,
                attributionUserID: invitation.sourceOwnerUserID,
                syncState: .synced,
                serverUpdatedAt: now
            )
            userPlaces.append(userPlace)
            createdNewUserPlace = true
        }

        replaceAttributes(for: userPlace.id, with: draft.attributes, syncState: .synced)

        let visit: LocalPlaceVisit
        if let existingVisit = placeVisits.first(where: {
            $0.serverID == result.visitID || $0.localID == result.visitID
        }) {
            existingVisit.userPlaceID = userPlace.id
            existingVisit.visitedAt = draft.visitedAt
            existingVisit.note = draft.note
            existingVisit.ratingScore = PlaceRating.normalized(draft.ratingScore)
            existingVisit.attributeAnswersJSON = VisitAttributeAnswers.encoded(from: draft.attributes)
            existingVisit.setDerivedTags(VisitAttributeAnswers.tags(from: draft.attributes))
            existingVisit.backfilledFromUserPlace = result.backfilledFromUserPlace
            existingVisit.syncStateRaw = SyncState.synced.rawValue
            existingVisit.serverUpdatedAt = now
            existingVisit.lastSyncError = nil
            existingVisit.deletedAt = nil
            existingVisit.updatedAt = now
            existingVisit.localUpdatedAt = now
            visit = existingVisit
        } else {
            visit = LocalPlaceVisit(
                localID: "local_visit_shared_\(result.visitID)",
                serverID: result.visitID,
                userPlaceID: userPlace.id,
                visitedAt: draft.visitedAt,
                note: draft.note,
                ratingScore: draft.ratingScore,
                attributeAnswersJSON: VisitAttributeAnswers.encoded(from: draft.attributes),
                tags: VisitAttributeAnswers.tags(from: draft.attributes),
                backfilledFromUserPlace: result.backfilledFromUserPlace,
                syncState: .synced,
                serverUpdatedAt: now
            )
            placeVisits.append(visit)
        }

        sharedVisitInvitations.removeAll { $0.participantID == invitation.participantID }
        refreshUserPlaceVisitSummary(userPlaceID: userPlace.id)
        if createdNewUserPlace {
            recordNewSaveForStreak(
                place: place,
                status: .been,
                savedAt: now,
                previousSummary: streakSummaryBeforeSave
            )
        }
        let acceptanceProperties = [
            "created_new_place": createdNewUserPlace ? "true" : "false",
            "photo_count": "\(result.photoCopies.count)"
        ]
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.sharedVisitAccepted,
                properties: acceptanceProperties
            )
        )
        analytics.track(
            .engagement(
                need: .status,
                action: .sharedVisitAccepted,
                surface: "shared_visit",
                properties: acceptanceProperties
            )
        )
        objectWillChange.send()
        persist()
        return visit
    }

    func recordAcceptedSharedVisitPhoto(
        copy: SharedVisitPhotoCopy,
        visitID: String,
        localAssetRef: String?,
        byteSize: Int?,
        width: Int?,
        height: Int?,
        uploaded: Bool = true
    ) {
        let now = Date.now
        if let existing = visitPhotos.first(where: {
            $0.serverID == copy.destinationPhotoID || $0.localID == copy.destinationPhotoID
        }) {
            existing.visitID = visitID
            existing.localAssetRef = localAssetRef
            existing.storageBucket = copy.destinationBucket
            existing.storagePath = copy.destinationPath
            existing.contentType = copy.contentType
            existing.byteSize = byteSize
            existing.width = width
            existing.height = height
            existing.uploadStateRaw = (uploaded ? VisitPhotoUploadState.uploaded : .pendingUpload).rawValue
            existing.syncStateRaw = (uploaded ? SyncState.synced : .pendingUpdate).rawValue
            existing.serverUpdatedAt = now
            existing.lastSyncError = nil
            existing.updatedAt = now
            existing.localUpdatedAt = now
        } else {
            visitPhotos.append(
                LocalVisitPhoto(
                    localID: "local_photo_shared_\(copy.destinationPhotoID)",
                    serverID: copy.destinationPhotoID,
                    visitID: visitID,
                    storageBucket: copy.destinationBucket,
                    storagePath: copy.destinationPath,
                    localAssetRef: localAssetRef,
                    contentType: copy.contentType,
                    byteSize: byteSize,
                    width: width,
                    height: height,
                    uploadState: uploaded ? .uploaded : .pendingUpload,
                    syncState: uploaded ? .synced : .pendingUpdate,
                    serverUpdatedAt: now
                )
            )
        }
        objectWillChange.send()
        persist()
    }

    func firstVisitPhoto(forPlaceID placeID: String) -> LocalVisitPhoto? {
        let placeIDs = matchingPlaceIDs(placeID)
        let userPlaceIDs = Set(
            userPlaces
                .filter {
                    $0.userID == currentUser.id
                        && $0.deletedAt == nil
                        && placeIDs.contains($0.placeID)
                }
                .flatMap { userPlace in
                    [userPlace.id, userPlace.localID, userPlace.serverID].compactMap { $0 }
                }
        )
        let visitIDs = Set(
            placeVisits
                .filter { $0.deletedAt == nil && userPlaceIDs.contains($0.userPlaceID) }
                .flatMap { visit in
                    [visit.id, visit.localID, visit.serverID].compactMap { $0 }
                }
        )

        return visitPhotos
            .filter { photo in
                guard photo.deletedAt == nil, visitIDs.contains(photo.visitID) else { return false }
                if let localAssetRef = photo.localAssetRef, !localAssetRef.isEmpty { return true }
                return photo.uploadState == .uploaded && photo.storagePath?.isEmpty == false
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.id < rhs.id
            }
            .first
    }

    func firstVisitPhotosByPlaceID() -> [String: LocalVisitPhoto] {
        if let cached = firstVisitPhotosByPlaceIDCache,
           cached.revision == presentationRevision,
           cached.userID == currentUser.id {
            return cached.photos
        }
        firstVisitPhotoIndexBuildCount += 1

        var placeReferencesByAlias: [String: Set<String>] = [:]
        placeReferencesByAlias.reserveCapacity(places.count * 2)
        for place in places {
            let references = Set([place.id, place.localID, place.serverID].compactMap { $0 })
            for reference in references {
                placeReferencesByAlias[reference] = references
            }
        }

        var placeReferencesByUserPlaceID: [String: Set<String>] = [:]
        placeReferencesByUserPlaceID.reserveCapacity(userPlaces.count * 2)
        for userPlace in userPlaces
        where userPlace.userID == currentUser.id && userPlace.deletedAt == nil {
            let placeReferences = placeReferencesByAlias[userPlace.placeID] ?? [userPlace.placeID]
            let userPlaceIDs = [userPlace.id, userPlace.localID]
                + [userPlace.serverID].compactMap { $0 }
            for userPlaceID in userPlaceIDs {
                placeReferencesByUserPlaceID[userPlaceID] = placeReferences
            }
        }

        var placeReferencesByVisitID: [String: Set<String>] = [:]
        placeReferencesByVisitID.reserveCapacity(placeVisits.count * 2)
        for visit in placeVisits where visit.deletedAt == nil {
            guard let placeReferences = placeReferencesByUserPlaceID[visit.userPlaceID] else { continue }
            let visitIDs = [visit.id, visit.localID]
                + [visit.serverID].compactMap { $0 }
            for visitID in visitIDs {
                placeReferencesByVisitID[visitID] = placeReferences
            }
        }

        let eligiblePhotos = visitPhotos
            .filter { photo in
                guard photo.deletedAt == nil, placeReferencesByVisitID[photo.visitID] != nil else { return false }
                if let localAssetRef = photo.localAssetRef, !localAssetRef.isEmpty { return true }
                return photo.uploadState == .uploaded && photo.storagePath?.isEmpty == false
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.id < rhs.id
            }

        var firstPhotoByPlaceID: [String: LocalVisitPhoto] = [:]
        firstPhotoByPlaceID.reserveCapacity(eligiblePhotos.count)
        var resolvedPlaceIDs = Set<String>()
        for photo in eligiblePhotos {
            guard let placeReferences = placeReferencesByVisitID[photo.visitID] else { continue }
            for placeID in placeReferences where !resolvedPlaceIDs.contains(placeID) {
                resolvedPlaceIDs.insert(placeID)
                firstPhotoByPlaceID[placeID] = photo
            }
        }

        firstVisitPhotosByPlaceIDCache = (
            revision: presentationRevision,
            userID: currentUser.id,
            photos: firstPhotoByPlaceID
        )
        return firstPhotoByPlaceID
    }

    @discardableResult
    func applyProviderCategoryEnrichment(
        placeID: String,
        primaryType: String?,
        types: [String],
        backend: WanderBackend?
    ) async -> Bool {
        let changedPlaceIDs = updateProviderCategoryMetadata(
            placeID: placeID,
            primaryType: primaryType,
            types: types,
            markGenericAsVerified: false
        )
        guard !changedPlaceIDs.isEmpty else { return false }

        let ownUserPlaceIDs = markOwnUserPlacesPending(forPlaceIDs: changedPlaceIDs)
        objectWillChange.send()
        persist()

        guard let backend else { return true }
        for userPlaceID in ownUserPlaceIDs {
            _ = await retryOwnPlaceSync(
                userPlaceID: userPlaceID,
                backend: backend,
                trigger: .providerEnrichment
            )
        }
        return true
    }

    @discardableResult
    func refreshOwnPlaceProviderCategories(
        backend: WanderBackend?,
        limit: Int = 4
    ) async -> Int {
        guard let backend,
              backend.placePhotoRepository != nil,
              limit > 0
        else {
            return 0
        }

        let enrichmentUserID = currentUser.id
        let ownPlaceIDs = Set(
            userPlaces
                .filter { $0.userID == enrichmentUserID && $0.deletedAt == nil }
                .flatMap { [$0.placeID, $0.id, $0.localID, $0.serverID].compactMap { $0 } }
        )
        let ownPlaces = places.filter { place in
            ownPlaceIDs.contains(place.id)
                || ownPlaceIDs.contains(place.localID)
                || place.serverID.map(ownPlaceIDs.contains) == true
        }

        let retryCutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        providerCategoryEnrichmentAttemptedAtByKey = providerCategoryEnrichmentAttemptedAtByKey.filter {
            $0.value >= retryCutoff
        }
        let requests = ownPlaces
            .filter {
                $0.categorySource != PlaceCategorySource.user.rawValue
                    && WanderPlaceCategory.providerAssignmentNeedsEnrichment($0.categoryAssignment)
            }
            .sorted { lhs, rhs in
                let lhsConfidence = lhs.categoryConfidence ?? 0
                let rhsConfidence = rhs.categoryConfidence ?? 0
                if lhsConfidence != rhsConfidence {
                    return lhsConfidence < rhsConfidence
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .compactMap { place -> (LocalPlace, PlacePhotoRequest)? in
                let request = PlacePhotoRequest(
                    placeID: place.id,
                    name: place.canonicalName,
                    address: place.address,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    sourceProvider: place.sourceProvider,
                    sourceProviderPlaceID: place.sourceProviderPlaceID,
                    requiresPhoto: false
                )
                guard !request.skipsGooglePlacesLookup,
                      providerCategoryEnrichmentAttemptedAtByKey[request.lookupKey] == nil
                else {
                    return nil
                }
                return (place, request)
            }
            .prefix(limit)

        var changedPlaceIDs = Set<String>()
        var attemptedRequest = false
        for (place, request) in requests {
            guard currentUser.id == enrichmentUserID, !Task.isCancelled else { break }
            providerCategoryEnrichmentAttemptedAtByKey[request.lookupKey] = .now
            attemptedRequest = true
            do {
                let photo = try await backend.placePhoto(for: request)
                guard photo.isGooglePlacesPhoto else { continue }
                changedPlaceIDs.formUnion(
                    updateProviderCategoryMetadata(
                        placeID: place.id,
                        primaryType: photo.providerPrimaryType,
                        types: photo.providerTypes ?? [],
                        markGenericAsVerified: true
                    )
                )
            } catch is CancellationError {
                break
            } catch {
                continue
            }
        }

        guard !changedPlaceIDs.isEmpty else {
            if attemptedRequest {
                persist()
            }
            return 0
        }
        let ownUserPlaceIDs = markOwnUserPlacesPending(forPlaceIDs: changedPlaceIDs)
        objectWillChange.send()
        persist()
        return ownUserPlaceIDs.count
    }

    private func updateProviderCategoryMetadata(
        placeID: String,
        primaryType: String?,
        types: [String],
        markGenericAsVerified: Bool
    ) -> Set<String> {
        var candidatePlaces = places.filter {
            $0.id == placeID || $0.localID == placeID || $0.serverID == placeID
        }
        candidatePlaces.append(contentsOf: remoteVisiblePlaceCache.compactMap { visiblePlace in
            let place = visiblePlace.place
            return place.id == placeID || place.localID == placeID || place.serverID == placeID
                ? place
                : nil
        })

        var seen = Set<ObjectIdentifier>()
        candidatePlaces = candidatePlaces.filter { seen.insert(ObjectIdentifier($0)).inserted }
        guard !candidatePlaces.isEmpty else { return [] }

        var changedPlaceIDs = Set<String>()
        for place in candidatePlaces {
            guard place.categorySource != PlaceCategorySource.user.rawValue else { continue }

            let existingAssignment = place.categoryAssignment
            let correctivePrimaryType = WanderPlaceCategory.correctiveProviderPrimaryType(
                primaryType,
                for: existingAssignment
            )
            let providerType = correctivePrimaryType ?? WanderPlaceCategory.preferredProviderType(
                primaryType: primaryType,
                types: types,
                matchingPrimaryCategory: existingAssignment.primaryCategory
            )

            if let providerType {
                let comparisonPrimary = correctivePrimaryType == nil
                    ? existingAssignment.primaryCategory
                    : WanderPlaceCategory.primaryCategory(for: providerType)
                let isMoreSpecific = WanderPlaceCategory.isMoreSpecificProviderType(
                    providerType,
                    than: existingAssignment.rawProviderType,
                    matchingPrimaryCategory: comparisonPrimary
                )
                if correctivePrimaryType != nil || isMoreSpecific {
                    let enrichedAssignment = WanderPlaceCategory.assignment(
                        forRawCategory: providerType,
                        source: PlaceCategorySource.provider.rawValue,
                        confidence: 0.98,
                        rawProviderType: providerType
                    )
                    let canApply = existingAssignment.primaryCategory == WanderPlaceCategory.fallbackPlace
                        || enrichedAssignment.primaryCategory == existingAssignment.primaryCategory
                        || correctivePrimaryType != nil
                    if canApply,
                       enrichedAssignment != existingAssignment {
                        place.category = enrichedAssignment.legacyCategory
                        place.primaryCategory = enrichedAssignment.primaryCategory
                        place.subcategory = enrichedAssignment.subcategory
                        place.categorySource = enrichedAssignment.source
                        place.categoryConfidence = enrichedAssignment.confidence
                        place.rawProviderType = enrichedAssignment.rawProviderType
                        place.updatedAt = .now
                        place.localUpdatedAt = .now
                        changedPlaceIDs.formUnion(placeIdentityIDs(place))
                        continue
                    }
                }
            }

            if markGenericAsVerified,
               WanderPlaceCategory.providerAssignmentNeedsEnrichment(existingAssignment),
               primaryType?.isEmpty == false || !types.isEmpty {
                place.categorySource = PlaceCategorySource.provider.rawValue
                place.categoryConfidence = 0.99
                place.updatedAt = .now
                place.localUpdatedAt = .now
                changedPlaceIDs.formUnion(placeIdentityIDs(place))
            }
        }
        return changedPlaceIDs
    }

    private func placeIdentityIDs(_ place: LocalPlace) -> Set<String> {
        Set([place.id, place.localID, place.serverID].compactMap { $0 })
    }

    private func markOwnUserPlacesPending(forPlaceIDs placeIDs: Set<String>) -> [String] {
        var userPlaceIDs: [String] = []
        let now = Date.now
        for userPlace in userPlaces where userPlace.userID == currentUser.id
            && userPlace.deletedAt == nil
            && placeIDs.contains(userPlace.placeID) {
            if userPlace.syncState == .synced {
                userPlace.syncStateRaw = SyncState.pendingUpdate.rawValue
            }
            userPlace.updatedAt = now
            userPlace.localUpdatedAt = now
            userPlaceIDs.append(userPlace.id)
        }
        return userPlaceIDs
    }

    @discardableResult
    private func updatePlaceClassificationAttributes(
        from drafts: [PlaceAttributeDraft],
        for userPlace: LocalUserPlace,
        at date: Date,
        clearsMissingCuisine: Bool = false
    ) -> Bool {
        let cuisine = drafts.last(where: {
            $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine
        })
        let userPlaceIDs = matchingUserPlaceIDs(userPlace.id)
        let droppedPinName = drafts.last(where: {
            $0.questionKey == PlaceMemoryAttributeKeys.droppedPinName
        })
        let semanticUpdates: [(draft: PlaceAttributeDraft?, key: String, clearsMissing: Bool)] = [
            (cuisine, PlaceMemoryAttributeKeys.restaurantCuisine, clearsMissingCuisine),
            (droppedPinName, PlaceMemoryAttributeKeys.droppedPinName, droppedPinName != nil)
        ]
        let pendingState: SyncState = userPlace.serverID == nil ? .pendingCreate : .pendingUpdate
        var didChange = false

        for update in semanticUpdates where update.draft != nil || update.clearsMissing {
            let existingAttributes = placeAttributes.filter {
                userPlaceIDs.contains($0.userPlaceID) && $0.questionKey == update.key
            }
            let shouldPersist = update.draft?.valueJSON != nil
                && update.draft?.valueJSON != "null"

            if shouldPersist,
               existingAttributes.count == 1,
               let existing = existingAttributes.first,
               existing.valueType == update.draft?.valueType,
               existing.valueJSON == update.draft?.valueJSON {
                continue
            }
            if !shouldPersist, existingAttributes.isEmpty {
                continue
            }

            placeAttributes.removeAll {
                userPlaceIDs.contains($0.userPlaceID) && $0.questionKey == update.key
            }
            if shouldPersist, let draft = update.draft {
                placeAttributes.append(
                    LocalPlaceAttribute(
                        localID: "local_attr_\(slug(userPlace.localID))_\(slug(draft.questionKey))",
                        userPlaceID: userPlace.id,
                        questionKey: draft.questionKey,
                        valueType: draft.valueType,
                        valueJSON: draft.valueJSON,
                        syncState: pendingState,
                        localUpdatedAt: date,
                        createdAt: date,
                        updatedAt: date
                    )
                )
            }
            didChange = true
        }

        guard didChange else { return false }

        userPlace.updatedAt = date
        userPlace.localUpdatedAt = date
        userPlace.lastSyncError = nil
        userPlace.syncStateRaw = pendingState.rawValue
        return true
    }

    @discardableResult
    func createVisit(
        userPlaceID: String,
        visitedAt: Date = .now,
        note: String? = nil,
        ratingScore: Double? = nil,
        attributes: [PlaceAttributeDraft] = [],
        visibility: PlaceVisibility? = nil
    ) -> LocalPlaceVisit? {
        guard let userPlace = currentUserPlace(matching: userPlaceID) else { return nil }

        let now = Date.now
        let isRepeatCheckIn = !visits(for: userPlace.id).isEmpty
        let attributeAnswersJSON = VisitAttributeAnswers.encoded(from: attributes)
        let visit = LocalPlaceVisit(
            localID: "local_visit_\(UUID().uuidString.lowercased())",
            serverID: UUID().uuidString.lowercased(),
            userPlaceID: userPlace.id,
            visitedAt: visitedAt,
            note: note,
            ratingScore: PlaceRating.scoreForSave(status: .been, score: ratingScore),
            attributeAnswersJSON: attributeAnswersJSON,
            tags: VisitAttributeAnswers.tags(from: attributes),
            syncState: .pendingCreate,
            localUpdatedAt: now,
            createdAt: now,
            updatedAt: now
        )

        if userPlace.status == .wannaGo {
            preserveHistoricalWant(for: userPlace, attributes: attributeDrafts(for: userPlace.id))
        }
        userPlace.plannedDate = nil
        if userPlace.status != .been {
            userPlace.statusRaw = PlaceStatus.been.rawValue
        }
        if let visibility {
            userPlace.visibilityRaw = visibilityForSave(visibility).rawValue
        }
        updatePlaceClassificationAttributes(from: attributes, for: userPlace, at: now)
        userPlace.updatedAt = now
        userPlace.localUpdatedAt = now
        userPlace.syncStateRaw = userPlace.serverID == nil ? SyncState.pendingCreate.rawValue : SyncState.pendingUpdate.rawValue
        placeVisits.append(visit)
        refreshUserPlaceVisitSummary(userPlaceID: userPlace.id)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.checkInCreated,
                properties: [
                    "is_repeat": isRepeatCheckIn ? "true" : "false",
                    "visibility": userPlace.visibility.rawValue,
                    "date_bucket": checkInDateBucket(visitedAt, now: now)
                ]
            )
        )
        analytics.track(
            .engagement(
                need: .expression,
                action: .checkInCreated,
                surface: "check_in",
                properties: [
                    "is_repeat": isRepeatCheckIn ? "true" : "false",
                    "visibility": userPlace.visibility.rawValue
                ]
            )
        )

        objectWillChange.send()
        persist()
        return visit
    }

    @discardableResult
    func updateVisit(
        visitID: String,
        visitedAt: Date? = nil,
        note: String? = nil,
        ratingScore: Double? = nil,
        attributes: [PlaceAttributeDraft]? = nil,
        categoryCandidate: PlaceCandidate? = nil,
        visibility: PlaceVisibility? = nil,
        replacesNote: Bool = false,
        replacesRating: Bool = false
    ) -> LocalPlaceVisit? {
        guard let visit = currentUserVisit(matching: visitID) else { return nil }

        let now = Date.now
        if let visitedAt {
            visit.visitedAt = visitedAt
        }
        if replacesNote {
            visit.note = note
        } else if let note {
            visit.note = note
        }
        if replacesRating {
            visit.ratingScore = PlaceRating.scoreForSave(status: .been, score: ratingScore)
        } else if let ratingScore {
            visit.ratingScore = PlaceRating.normalized(ratingScore)
        }
        if let attributes {
            visit.attributeAnswersJSON = VisitAttributeAnswers.encoded(from: attributes)
            visit.setDerivedTags(VisitAttributeAnswers.tags(from: attributes))
            if let userPlace = currentUserPlace(matching: visit.userPlaceID) {
                updatePlaceClassificationAttributes(
                    from: attributes,
                    for: userPlace,
                    at: now,
                    clearsMissingCuisine: true
                )
            }
        }
        if let categoryCandidate,
           let userPlace = currentUserPlace(matching: visit.userPlaceID) {
            let assignment = categoryOverrideAssignment(from: categoryCandidate)
            let categoryChanged = userPlace.categoryOverride != assignment?.primaryCategory
                || userPlace.subcategoryOverride != assignment?.subcategory
                || userPlace.categoryOverrideSource != assignment?.source
                || userPlace.categoryOverrideConfidence != assignment?.confidence
            if categoryChanged {
                applyCategoryOverride(assignment, to: userPlace)
                userPlace.updatedAt = now
                userPlace.localUpdatedAt = now
                userPlace.lastSyncError = nil
                userPlace.syncStateRaw = userPlace.serverID == nil
                    ? SyncState.pendingCreate.rawValue
                    : SyncState.pendingUpdate.rawValue
            }
        }
        visit.updatedAt = now
        visit.localUpdatedAt = now
        visit.syncStateRaw = visit.serverID == nil ? SyncState.pendingCreate.rawValue : SyncState.pendingUpdate.rawValue

        if let visibility,
           let userPlace = currentUserPlace(matching: visit.userPlaceID) {
            userPlace.visibilityRaw = visibilityForSave(visibility).rawValue
            userPlace.updatedAt = now
            userPlace.localUpdatedAt = now
            userPlace.syncStateRaw = userPlace.serverID == nil ? SyncState.pendingCreate.rawValue : SyncState.pendingUpdate.rawValue
        }

        refreshUserPlaceVisitSummary(userPlaceID: visit.userPlaceID)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.checkInEdited,
                properties: ["date_changed": visitedAt == nil ? "false" : "true"]
            )
        )
        objectWillChange.send()
        persist()
        return visit
    }

    @discardableResult
    func deleteVisit(visitID: String) -> Bool {
        guard let visit = currentUserVisit(matching: visitID) else { return false }
        let remoteOwnerPlace = remoteCurrentUserVisiblePlace(
            matching: visit.userPlaceID
        )

        let now = Date.now
        let visitIDs = matchingVisitIDs(visit.id)
        for photo in visitPhotos where visitIDs.contains(photo.visitID) && photo.deletedAt == nil {
            softDelete(photo, at: now)
        }
        softDelete(visit, at: now)

        if let userPlace = currentUserPlace(matching: visit.userPlaceID) {
            let remainingVisits = visits(for: userPlace.id)
            if remainingVisits.isEmpty {
                if !restoreHistoricalWantAfterLastVisit(userPlace, at: now) {
                    deleteUserPlaceAfterLastVisit(userPlace, at: now)
                }
            } else {
                refreshUserPlaceVisitSummary(userPlaceID: userPlace.id)
            }
        } else if let remoteOwnerPlace {
            let userPlaceReferenceIDs = Self.referenceIDs(
                for: remoteOwnerPlace.userPlace
            )
            let remainingVisits = placeVisits.filter {
                $0.deletedAt == nil
                    && userPlaceReferenceIDs.contains($0.userPlaceID)
            }
            if remainingVisits.isEmpty {
                let materializedUserPlace = materializeRemoteCurrentUserPlace(
                    remoteOwnerPlace
                )
                if !restoreHistoricalWantAfterLastVisit(
                    materializedUserPlace,
                    at: now
                ) {
                    deleteUserPlaceAfterLastVisit(materializedUserPlace, at: now)
                }
                remoteVisiblePlaceCache.removeAll {
                    $0.owner.id == currentUser.id
                        && VisiblePlaceGrouping.matches($0, remoteOwnerPlace)
                }
            }
        }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.checkInDeleted,
                properties: ["was_backfill": visit.backfilledFromUserPlace ? "true" : "false"]
            )
        )

        objectWillChange.send()
        persist()
        return true
    }

    @discardableResult
    func createVisitPhoto(
        visitID: String,
        storagePath: String? = nil,
        localAssetRef: String? = nil,
        remoteURLString: String? = nil,
        contentType: String? = "image/jpeg",
        byteSize: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        capturedAt: Date? = nil
    ) -> LocalVisitPhoto? {
        guard let visit = currentUserVisit(matching: visitID) else { return nil }

        let now = Date.now
        let nextSortOrder = (photos(for: visit.id).map(\.sortOrder).max() ?? -1) + 1
        let localID = "local_visit_photo_\(UUID().uuidString.lowercased())"
        let path = storagePath ?? "\(currentUser.id)/\(visit.id)/\(localID).jpg"
        let photo = LocalVisitPhoto(
            localID: localID,
            visitID: visit.id,
            storagePath: path,
            localAssetRef: localAssetRef,
            remoteURLString: remoteURLString,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            capturedAt: capturedAt,
            sortOrder: nextSortOrder,
            uploadState: remoteURLString == nil ? .pendingUpload : .uploaded,
            syncState: .pendingCreate,
            localUpdatedAt: now,
            createdAt: now,
            updatedAt: now
        )
        visitPhotos.append(photo)

        objectWillChange.send()
        persist()
        return photo
    }

    @discardableResult
    func createVisitPhotos(
        visitID: String,
        inputs: [LocalVisitPhotoInput]
    ) -> [LocalVisitPhoto] {
        withDeferredPersistence {
            inputs.compactMap { input in
                createVisitPhoto(
                    visitID: visitID,
                    localAssetRef: input.localAssetRef,
                    contentType: input.contentType,
                    byteSize: input.byteSize,
                    width: input.width,
                    height: input.height,
                    capturedAt: input.capturedAt
                )
            }
        }
    }

    @discardableResult
    func createVisitPhoto(
        visitID: String,
        data: Data,
        localAssetRef: String? = nil,
        contentType: String = "image/jpeg",
        width: Int? = nil,
        height: Int? = nil,
        capturedAt: Date? = nil,
        backend: WanderBackend?
    ) async -> LocalVisitPhoto? {
        guard let photo = createVisitPhoto(
            visitID: visitID,
            localAssetRef: localAssetRef,
            contentType: contentType,
            byteSize: data.count,
            width: width,
            height: height,
            capturedAt: capturedAt
        ) else {
            return nil
        }

        guard let backend else {
            return photo
        }

        _ = await retryPendingVisitPhotoUploads(backend: backend)
        return currentUserPhoto(matching: photo.id)
    }

    @discardableResult
    func deleteVisitPhoto(photoID: String) -> Bool {
        guard let photo = currentUserPhoto(matching: photoID) else { return false }

        softDelete(photo, at: .now)
        objectWillChange.send()
        persist()
        return true
    }

    func followers(of userID: String) -> [LocalProfile] {
        guard canReadGraph(for: userID) else { return [] }

        return follows
            .filter { $0.followedUserID == userID }
            .compactMap { follow in profiles.first { $0.id == follow.followerUserID } }
            .filter { canShowGraphProfile($0.id, for: userID) }
            .sorted { $0.handle < $1.handle }
    }

    func following(of userID: String) -> [LocalProfile] {
        guard canReadGraph(for: userID) else { return [] }

        return follows
            .filter { $0.followerUserID == userID }
            .compactMap { follow in profiles.first { $0.id == follow.followedUserID } }
            .filter { canShowGraphProfile($0.id, for: userID) }
            .sorted { $0.handle < $1.handle }
    }

    func friends(of userID: String) -> [LocalProfile] {
        let followerIDs = Set(follows.filter { $0.followedUserID == userID }.map(\.followerUserID))
        return following(of: userID)
            .filter { followerIDs.contains($0.id) }
            .sorted { $0.handle < $1.handle }
    }

    func relationship(to userID: String) -> ViewerRelationship {
        if userID == currentUser.id { return .owner }
        guard !isBlockedBetweenCurrentUser(and: userID) else { return .nonFollower }

        let iFollowThem = follows.contains { $0.followerUserID == currentUser.id && $0.followedUserID == userID }
        let theyFollowMe = follows.contains { $0.followerUserID == userID && $0.followedUserID == currentUser.id }

        if iFollowThem && theyFollowMe { return .mutual }
        if iFollowThem { return .follower }
        return .nonFollower
    }

    func viewerFollows(_ userID: String) -> Bool {
        let currentRelationship = relationship(to: userID)
        return currentRelationship == .follower || currentRelationship == .mutual
    }

    func hasAcknowledgedFollow(to userID: String) -> Bool {
        let viewerID = currentUser.id
        return follows.contains(where: { follow in
            let isViewerFollow = follow.followerUserID == viewerID
            let isTargetFollow = follow.followedUserID == userID
            let isAcknowledged = follow.syncStateRaw == SyncState.synced.rawValue
            return isViewerFollow && isTargetFollow && isAcknowledged
        })
    }

    func shell(for profile: LocalProfile) -> ProfileShell {
        ProfileShell(
            id: profile.id,
            handle: profile.handle,
            displayName: profile.displayName,
            avatarURL: profile.avatarURL,
            bio: profile.bio,
            homeArea: profile.homeArea,
            isPrivateProfile: profile.isPrivateProfile,
            createdAt: profile.createdAt,
            relationship: relationship(to: profile.id)
        )
    }

    func profileState(for profileID: String) -> ProfileViewState? {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return nil }
        let blocked = isBlockedBetweenCurrentUser(and: profile.id)
        return ProfileViewState(
            shell: shell(for: profile),
            visiblePlaces: blocked ? [] : visiblePlaces(for: profile.id),
            canFollow: profile.id != currentUser.id && !blocked && relationship(to: profile.id) == .nonFollower,
            canBlock: profile.id != currentUser.id,
            isBlocked: blocked
        )
    }

    func searchProfiles(handleQuery: String) -> [ProfileShell] {
        let normalized = handleQuery
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count >= 2 else { return [] }

        return profiles
            .filter { profile in
                let normalizedName = profile.displayName.lowercased()
                return profile.id != currentUser.id
                    && !profile.isPrivateProfile
                    && !isBlockedBetweenCurrentUser(and: profile.id)
                    && (
                        profile.searchHandle == normalized
                            || profile.searchHandle.hasPrefix(normalized)
                            || normalizedName.hasPrefix(normalized)
                    )
            }
            .map(shell(for:))
    }

    func discoverMembers(query: String, backend: WanderBackend? = nil) async -> [ProfileShell] {
        var profiles = searchProfiles(handleQuery: query)
        let normalizedProfileQuery = normalizedHandleQuery(query)

        if normalizedProfileQuery.count >= 2, let backend {
            do {
                let remoteProfiles = try await backend.searchProfiles(handleQuery: normalizedProfileQuery)
                try Task.checkCancellation()
                upsertRemoteProfileShells(remoteProfiles, preserveExistingProfileMetadataWhenMissing: true)
                profiles = mergeProfileShells(profiles + remoteProfiles)
                lastRemoteError = nil
            } catch is CancellationError {
                return profiles
            } catch {
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        return profiles
    }

    func refreshDiscoverPeopleRecommendations(
        backend: WanderBackend?,
        force: Bool = false,
        limit: Int = 20
    ) async {
        guard let backend, backend.profileRepository != nil else {
            discoverPeopleRecommendationsState = .idle
            return
        }

        if !force {
            switch discoverPeopleRecommendationsState {
            case .loading, .loaded:
                return
            case .idle, .failed:
                break
            }
        }

        let requestingUserID = currentUser.id
        discoverPeopleRecommendationsState = .loading

        do {
            let recommendations = try await backend.discoverProfileRecommendations(limit: limit)
            guard currentUser.id == requestingUserID else {
                discoverPeopleRecommendationsState = .idle
                return
            }

            let visibleRecommendations = recommendations.filter { recommendation in
                recommendation.profile.id != currentUser.id
                    && recommendation.profile.isPrivateProfile != true
                    && !isBlockedBetweenCurrentUser(and: recommendation.profile.id)
                    && !hasAcknowledgedFollow(to: recommendation.profile.id)
            }
            upsertRemoteProfileShells(
                visibleRecommendations.map(\.profile),
                preserveExistingProfileMetadataWhenMissing: true
            )
            discoverPeopleRecommendationsState = .loaded(visibleRecommendations)
            lastRemoteError = nil
        } catch {
            guard currentUser.id == requestingUserID else {
                discoverPeopleRecommendationsState = .idle
                return
            }
            lastRemoteError = remoteErrorMessage(error)
            discoverPeopleRecommendationsState = .failed
        }
    }

    func contactMatches() async -> [ContactMatch] {
        let matches = (try? await contactProvider.matches()) ?? []
        return matches.filter { match in
            guard let userID = match.userID else { return false }
            return !isBlockedBetweenCurrentUser(and: userID)
                && !isProfilePrivate(userID)
        }
    }

    func trackDiscoverSearchEvent(_ name: String, properties: [String: String]) {
        analytics.track(AnalyticsEvent(name: name, properties: properties))
    }

    func trackPlaceShareCompletion(completed: Bool) {
        let outcome = completed ? "shared" : "cancelled"
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.placeShareCompleted,
                properties: [
                    "surface": "map_place_card",
                    "outcome": outcome
                ]
            )
        )
        guard completed else { return }
        analytics.track(
            .engagement(
                need: .expression,
                action: .recommendationShared,
                surface: "map_place_card",
                properties: ["outcome": outcome]
            )
        )
    }

    func parseDiscover(query: String) async -> DiscoverFilters {
        let schema = DiscoverFilterSchema()
        let cacheKey = normalizedParseCacheKey(query, schema: schema)
        if let cached = discoverParseCache[cacheKey] {
            guard !Task.isCancelled else { return cached.filters }
            touchDiscoverParseCacheKey(cacheKey)
            if lastDiscoverFilters != cached.filters {
                lastDiscoverFilters = cached.filters
            }
            lastDiscoverParseSource = .cache
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverQueryParsed,
                    properties: [
                        "source": "cache",
                        "facet_count": "\(cached.filters.recognizedFacetCount)",
                        "opinion": cached.filters.opinion?.rawValue ?? "none",
                        "unsupported_count": "\(cached.filters.resolvedUnsupportedConcepts.count)"
                    ]
                )
            )
            return cached.filters
        }

        do {
            let parsedFilters = try await parser.parse(query: query, schema: schema)
            try Task.checkCancellation()
            let filters = DiscoverSemanticNormalizer.normalized(parsedFilters, query: query)
            let source = parser.parseSource
            cacheDiscoverParse(filters, source: source, key: cacheKey)
            if lastDiscoverFilters != filters {
                lastDiscoverFilters = filters
            }
            lastDiscoverParseSource = source
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverQueryParsed,
                    properties: [
                        "source": source.rawValue,
                        "facet_count": "\(filters.recognizedFacetCount)",
                        "opinion": filters.opinion?.rawValue ?? "none",
                        "unsupported_count": "\(filters.resolvedUnsupportedConcepts.count)"
                    ]
                )
            )
            return filters
        } catch is CancellationError {
            return DiscoverFilters(query: query)
        } catch {
            let fallback = DiscoverFilters(query: query)
            if lastDiscoverFilters != fallback {
                lastDiscoverFilters = fallback
            }
            lastDiscoverParseSource = .deterministicFallback
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverParseFailed,
                    properties: ["error_category": analyticsErrorCategory(error)]
                )
            )
            return fallback
        }
    }

    private func analyticsErrorCategory(_ error: Error) -> String {
        switch error {
        case is URLError:
            "network"
        case is DecodingError:
            "decoding"
        default:
            "other"
        }
    }

    func searchTrustedPlaces(
        query: String,
        scope: DiscoverPlaceScope = .everyone
    ) -> DiscoverResults {
        let filters = DeterministicFilterParser.filters(
            query: query,
            schema: DiscoverFilterSchema()
        )
        var placeFilters = PlaceFilters()
        placeFilters.statuses = filters.statuses
        placeFilters.categories = Set(filters.categories.map(WanderPlaceCategory.normalizedPrimaryCategory))
        placeFilters.ownerScopes = scope.ownerScopes
        if scope == .everyone, let relationship = filters.relationship {
            switch relationship {
            case .mutual:
                placeFilters.ownerScopes = ["friends"]
            case .follower:
                placeFilters.ownerScopes = ["following"]
            case .owner:
                placeFilters.ownerScopes = ["you"]
            case .nonFollower:
                placeFilters.ownerScopes = []
            }
        }
        let candidates = visiblePlaces(filters: placeFilters)
            .filter { visiblePlace in
                matchesArea(filters.area, visiblePlace: visiblePlace)
                    && matchesOwner(filters.ownerQuery, visiblePlace: visiblePlace)
                    && matchesTags(filters.tags, visiblePlace: visiblePlace)
                    && matchesOpinion(filters.opinion, visiblePlace: visiblePlace)
            }
        let queryPlan = TrustedPlaceSearchQuery(
            query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )
        let matches = rankedDiscoverMatches(
            TrustedPlaceSearch.matches(
                query: queryPlan,
                in: candidates
            )
        )
        let places = matches.map(\.place)
        let evidenceByUserPlaceID = Dictionary(
            uniqueKeysWithValues: matches.map { match in
                (
                    match.place.userPlace.id,
                    discoverMatchEvidence(
                        for: match.place,
                        filters: filters,
                        searchEvidence: match.evidence
                    )
                )
            }
        )
        return DiscoverResults(
            places: places,
            profiles: [],
            filters: filters,
            parseSource: .deterministic,
            evidenceByUserPlaceID: evidenceByUserPlaceID
        )
    }

    func recmePlaceSearchRequest(query: String, limit: Int = 20) async -> RecmePlaceSearchRequest? {
        let parsed = (try? await DeterministicFilterParser().parse(
            query: query,
            schema: DiscoverFilterSchema()
        )) ?? DiscoverFilters(query: query)
        let filters = DiscoverSemanticNormalizer.normalized(parsed, query: query)
        guard filters.ownerQuery == nil,
              filters.relationship != .nonFollower
        else {
            return nil
        }
        return DiscoverRecmePlaceSearchPlanner.request(query: query, filters: filters, limit: limit)
    }

    func discover(query: String, scope: DiscoverPlaceScope = .everyone, backend: WanderBackend? = nil) async -> DiscoverResults {
        let filters = await parseDiscover(query: query)
        guard !Task.isCancelled else {
            return DiscoverResults(
                places: [],
                profiles: [],
                filters: filters,
                parseSource: lastDiscoverParseSource
            )
        }
        var placeFilters = PlaceFilters()
        placeFilters.statuses = filters.statuses
        placeFilters.categories = Set(filters.categories.map(WanderPlaceCategory.normalizedPrimaryCategory))
        placeFilters.ownerScopes = scope.ownerScopes

        if scope == .everyone, let relationship = filters.relationship {
            switch relationship {
            case .mutual:
                placeFilters.ownerScopes = ["friends"]
            case .follower:
                placeFilters.ownerScopes = ["following"]
            case .owner:
                placeFilters.ownerScopes = ["you"]
            case .nonFollower:
                placeFilters.ownerScopes = []
            }
        }

        let hasSearchText = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let candidates = visiblePlaces(filters: placeFilters)
            .filter { visiblePlace in
                matchesArea(filters.area, visiblePlace: visiblePlace)
                    && matchesOwner(filters.ownerQuery, visiblePlace: visiblePlace)
                    && matchesTags(filters.tags, visiblePlace: visiblePlace)
                    && matchesOpinion(filters.opinion, visiblePlace: visiblePlace)
            }
        let queryPlan = TrustedPlaceSearchQuery(
            query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )
        var searchMatches: [TrustedPlaceSearchMatch]
        if hasSearchText {
            searchMatches = TrustedPlaceSearch.matches(query: queryPlan, in: candidates)
        } else {
            searchMatches = candidates.map {
                TrustedPlaceSearchMatch(place: $0, score: 0, evidence: [])
            }
        }

        if filters.sort == .ownerRatingDescending {
            searchMatches.sort { lhs, rhs in
                let lhsRating = lhs.place.userPlace.ratingScore ?? -.infinity
                let rhsRating = rhs.place.userPlace.ratingScore ?? -.infinity
                if lhsRating != rhsRating { return lhsRating > rhsRating }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.place.userPlace.savedAt != rhs.place.userPlace.savedAt {
                    return lhs.place.userPlace.savedAt > rhs.place.userPlace.savedAt
                }
                return lhs.place.userPlace.id < rhs.place.userPlace.id
            }
        } else {
            searchMatches = rankedDiscoverMatches(searchMatches)
        }
        let places = searchMatches.map(\.place)

        let evidenceByUserPlaceID = Dictionary(
            uniqueKeysWithValues: searchMatches.map { searchMatch in
                (
                    searchMatch.place.userPlace.id,
                    discoverMatchEvidence(
                        for: searchMatch.place,
                        filters: filters,
                        searchEvidence: queryPlan.requiredTokens.isEmpty ? [] : searchMatch.evidence
                    )
                )
            }
        )
        var profiles = searchProfiles(handleQuery: query)
        let normalizedProfileQuery = normalizedHandleQuery(query)

        if normalizedProfileQuery.count >= 2, let backend {
            do {
                let remoteProfiles = try await backend.searchProfiles(handleQuery: normalizedProfileQuery)
                try Task.checkCancellation()
                upsertRemoteProfileShells(remoteProfiles, preserveExistingProfileMetadataWhenMissing: true)
                profiles = mergeProfileShells(profiles + remoteProfiles)
                lastRemoteError = nil
            } catch is CancellationError {
                return DiscoverResults(
                    places: places,
                    profiles: profiles,
                    filters: filters,
                    parseSource: lastDiscoverParseSource,
                    evidenceByUserPlaceID: evidenceByUserPlaceID
                )
            } catch {
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        return DiscoverResults(
            places: places,
            profiles: profiles,
            filters: filters,
            parseSource: lastDiscoverParseSource,
            evidenceByUserPlaceID: evidenceByUserPlaceID
        )
    }

    private func rankedDiscoverMatches(
        _ matches: [TrustedPlaceSearchMatch]
    ) -> [TrustedPlaceSearchMatch] {
        matches.sorted { lhs, rhs in
            let lhsScore = lhs.score + discoverSocialAffinityBonus(for: lhs.place)
            let rhsScore = rhs.score + discoverSocialAffinityBonus(for: rhs.place)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.place.userPlace.savedAt != rhs.place.userPlace.savedAt {
                return lhs.place.userPlace.savedAt > rhs.place.userPlace.savedAt
            }
            return lhs.place.userPlace.id < rhs.place.userPlace.id
        }
    }

    private func discoverSocialAffinityBonus(for visiblePlace: VisiblePlace) -> Int {
        switch relationship(to: visiblePlace.owner.id) {
        case .owner:
            6
        case .mutual:
            4
        case .follower:
            2
        case .nonFollower:
            0
        }
    }

    func currentLocationCandidates() async throws -> [PlaceCandidate] {
        try await placeResolver.resolveCurrentLocation()
    }

    func manualCandidates(name: String, areaHint: String?, category: String?) async throws -> [PlaceCandidate] {
        try await placeResolver.resolveManualEntry(
            ManualPlaceInput(
                name: name,
                areaHint: areaHint,
                category: category
            )
        )
    }

    func photoTextCandidates(for query: String) async throws -> [PlaceCandidate] {
        try await placeResolver.resolveManualEntry(
            ManualPlaceInput(
                name: query,
                areaHint: nil,
                category: nil
            )
        )
    }

    func photoLocationCandidates(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        try await placeResolver.resolveNearbyPlaces(near: coordinate)
    }

    func linkCandidates(_ rawValue: String) async throws -> [PlaceCandidate] {
        try await placeResolver.resolveLink(LinkPlaceInput(rawValue: rawValue))
    }

    @discardableResult
    func saveCandidate(
        _ candidate: PlaceCandidate,
        status: PlaceStatus,
        visibility: PlaceVisibility,
        note: String?,
        sourceType: AddSourceType,
        ratingScore: Double? = nil,
        visitedAt: Date = .now,
        plannedDate: Date? = nil,
        attributes: [PlaceAttributeDraft]? = nil
    ) -> SaveResult {
        let resolvedVisibility = visibilityForSave(visibility)
        if status == .wannaGo,
           let existingPlace = place(matching: candidate),
           let existingUserPlace = currentUserPlace(for: existingPlace),
           existingUserPlace.status == .been {
            return SaveResult(
                userPlaceID: existingUserPlace.id,
                syncState: existingUserPlace.syncState
            )
        }

        let place = upsertPlace(from: candidate, sourceType: sourceType)
        let savedRatingScore = PlaceRating.scoreForSave(status: status, score: ratingScore)
        let categoryOverride = categoryOverrideAssignment(from: candidate)

        if let existing = userPlaces.first(where: { $0.userID == currentUser.id && $0.placeID == place.id && $0.deletedAt == nil }) {
            let previousStatus = existing.status
            let previousAttributeDrafts = attributeDrafts(for: existing.id)
            if previousStatus == .wannaGo, status == .been {
                preserveHistoricalWant(for: existing, attributes: previousAttributeDrafts)
            }

            if previousStatus == .been, status == .wannaGo {
                return SaveResult(userPlaceID: existing.id, syncState: existing.syncState)
            }

            existing.statusRaw = status.rawValue
            existing.visibilityRaw = resolvedVisibility.rawValue
            existing.note = note
            existing.plannedDate = status == .wannaGo
                ? plannedDate.map { WannaGoDate.normalized($0) }
                : nil
            existing.ratingScore = savedRatingScore
            existing.recommendedScore = savedRatingScore
            existing.recommendedCount = savedRatingScore == nil ? 0 : 1
            applyCategoryOverride(categoryOverride, to: existing)
            let attributeDrafts = attributes ?? previousAttributeDrafts
            if let attributes {
                existing.ratingSignal = ratingSignal(from: attributes)
                replaceAttributes(for: existing.id, with: attributes, syncState: .pendingUpdate)
            }
            if status == .been {
                if previousStatus == .been || previousStatus == .wannaGo {
                    _ = createVisit(
                        userPlaceID: existing.id,
                        visitedAt: visitedAt,
                        note: note,
                        ratingScore: savedRatingScore,
                        attributes: attributeDrafts,
                        visibility: resolvedVisibility
                    )
                    return SaveResult(userPlaceID: existing.id, syncState: existing.syncState)
                }
                _ = createVisit(
                    userPlaceID: existing.id,
                    visitedAt: visitedAt,
                    note: note,
                    ratingScore: savedRatingScore,
                    attributes: attributeDrafts,
                    visibility: resolvedVisibility
                )
                refreshUserPlaceVisitSummary(userPlaceID: existing.id)
            } else {
                softDeleteVisits(for: existing.id, at: .now)
                refreshUserPlaceVisitSummary(userPlaceID: existing.id)
            }
            existing.updatedAt = .now
            existing.localUpdatedAt = .now
            existing.syncStateRaw = SyncState.pendingUpdate.rawValue
            objectWillChange.send()
            persist()
            return SaveResult(userPlaceID: existing.id, syncState: existing.syncState)
        }

        let savedAt = Date.now
        let streakSummaryBeforeSave = saveStreakSummary
        let userPlace = LocalUserPlace(
            localID: "local_up_\(currentUser.handle)_\(slug(place.localID))",
            userID: currentUser.id,
            placeID: place.id,
            status: status,
            visibility: resolvedVisibility,
            note: note,
            ratingSignal: attributes.flatMap { ratingSignal(from: $0) },
            ratingScore: savedRatingScore,
            recommendedScore: savedRatingScore,
            recommendedCount: savedRatingScore == nil ? 0 : 1,
            categoryOverride: categoryOverride?.primaryCategory,
            subcategoryOverride: categoryOverride?.subcategory,
            categoryOverrideSource: categoryOverride?.source,
            categoryOverrideConfidence: categoryOverride?.confidence,
            nearbyConfirmed: sourceType == .currentLocation,
            savedAt: savedAt,
            plannedDate: status == .wannaGo
                ? plannedDate.map { WannaGoDate.normalized($0) }
                : nil,
            sourceType: sourceType.rawValue,
            syncState: .pendingCreate
        )
        userPlaces.append(userPlace)
        let attributeDrafts = attributes ?? []
        if let attributes {
            replaceAttributes(for: userPlace.id, with: attributes, syncState: .pendingCreate)
        }
        if status == .been {
            _ = createVisit(
                userPlaceID: userPlace.id,
                visitedAt: visitedAt,
                note: note,
                ratingScore: savedRatingScore,
                attributes: attributeDrafts,
                visibility: resolvedVisibility
            )
        }
        refreshUserPlaceVisitSummary(userPlaceID: userPlace.id)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.placeSaved,
                properties: ["source_type": sourceType.rawValue, "visibility": resolvedVisibility.rawValue, "status": status.rawValue]
            )
        )
        analytics.track(
            .engagement(
                need: .expression,
                action: .placeSaved,
                surface: "add",
                properties: ["source_type": sourceType.rawValue, "status": status.rawValue]
            )
        )
        recordNewSaveForStreak(
            place: place,
            status: status,
            savedAt: savedAt,
            previousSummary: streakSummaryBeforeSave
        )
        persist()
        return SaveResult(userPlaceID: userPlace.id, syncState: userPlace.syncState)
    }

    /// Import is idempotent. A repeated import may enrich a Wanna with its
    /// first Check In, but it must never create another visit for a place that
    /// is already Been or overwrite details the user previously entered.
    @discardableResult
    func saveImportedCandidate(
        _ candidate: PlaceCandidate,
        status: PlaceStatus,
        visibility: PlaceVisibility,
        note: String?,
        sourceType: AddSourceType,
        ratingScore: Double? = nil,
        visitedAt: Date = .now
    ) -> SaveResult {
        if let existingPlace = place(matching: candidate),
           let existingUserPlace = currentUserPlace(for: existingPlace) {
            if existingUserPlace.status == .been || status == .wannaGo {
                return SaveResult(
                    userPlaceID: existingUserPlace.id,
                    syncState: existingUserPlace.syncState,
                    placeID: existingPlace.serverID
                )
            }
            return saveCandidate(
                candidate,
                status: .been,
                visibility: existingUserPlace.visibility,
                note: existingUserPlace.note,
                sourceType: sourceType,
                ratingScore: ratingScore,
                visitedAt: visitedAt
            )
        }

        return saveCandidate(
            candidate,
            status: status,
            visibility: visibility,
            note: note,
            sourceType: sourceType,
            ratingScore: ratingScore,
            visitedAt: visitedAt
        )
    }

    func existingImportSave(matching candidate: PlaceCandidate) -> ExistingImportSave? {
        guard let place = place(matching: candidate),
              let userPlace = currentUserPlace(for: place)
        else { return nil }
        return ExistingImportSave(
            userPlaceID: userPlace.id,
            status: userPlace.status,
            syncState: userPlace.syncState,
            placeID: place.serverID
        )
    }

    /// Changes the status of a save created by an import without rebuilding it
    /// from the import's stale candidate fields. Verification can follow an
    /// Optional Details edit, so the current place memory is authoritative.
    @discardableResult
    func changeImportedSaveStatus(
        userPlaceID: String,
        to status: PlaceStatus,
        ratingScore: Double? = nil,
        visitedAt: Date = .now
    ) -> SaveResult? {
        guard let userPlace = currentUserPlace(matching: userPlaceID) else {
            return nil
        }
        guard userPlace.status != status else {
            return SaveResult(userPlaceID: userPlace.id, syncState: userPlace.syncState)
        }

        let now = Date.now
        if status == .been {
            let currentAttributes = attributeDrafts(for: userPlace.id)
            _ = createVisit(
                userPlaceID: userPlace.id,
                visitedAt: visitedAt,
                note: userPlace.note,
                ratingScore: ratingScore,
                attributes: currentAttributes,
                visibility: userPlace.visibility
            )
            return SaveResult(userPlaceID: userPlace.id, syncState: userPlace.syncState)
        }

        // A Check In's editor stores its details on the visit. Carry those
        // details forward to Wanna before removing the visits, while leaving
        // the current category override and visibility untouched.
        let latestVisit = visits(for: userPlace.id).max { lhs, rhs in
            if lhs.visitedAt != rhs.visitedAt {
                return lhs.visitedAt < rhs.visitedAt
            }
            return lhs.createdAt < rhs.createdAt
        }
        let currentAttributes = latestVisit.map {
            VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: $0.attributeAnswersJSON)
        } ?? attributeDrafts(for: userPlace.id)

        userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        if let latestVisit {
            userPlace.note = latestVisit.note
        }
        userPlace.ratingSignal = ratingSignal(from: currentAttributes)
        userPlace.ratingScore = nil
        userPlace.recommendedScore = nil
        userPlace.recommendedCount = 0
        userPlace.visitedAt = nil
        userPlace.plannedDate = nil
        userPlace.updatedAt = now
        userPlace.localUpdatedAt = now
        userPlace.lastSyncError = nil
        userPlace.syncStateRaw = userPlace.serverID == nil
            ? SyncState.pendingCreate.rawValue
            : SyncState.pendingUpdate.rawValue
        replaceAttributes(for: userPlace.id, with: currentAttributes, syncState: userPlace.syncState)
        softDeleteVisits(for: userPlace.id, at: now)
        objectWillChange.send()
        persist()
        return SaveResult(userPlaceID: userPlace.id, syncState: userPlace.syncState)
    }

    @discardableResult
    func saveCandidate(
        _ candidate: PlaceCandidate,
        status: PlaceStatus,
        visibility: PlaceVisibility,
        note: String?,
        sourceType: AddSourceType,
        ratingScore: Double? = nil,
        visitedAt: Date = .now,
        plannedDate: Date? = nil,
        attributes: [PlaceAttributeDraft]? = nil,
        backend: WanderBackend?
    ) async -> SaveResult {
        #if DEBUG
        WanderDebugLog.sync.debug("direct save requested source=\(sourceType.rawValue, privacy: .public) status=\(status.rawValue, privacy: .public) visibility=\(visibility.rawValue, privacy: .public) category=\(candidate.category, privacy: .public) backend_available=\((backend != nil), privacy: .public)")
        #endif
        let localResult = saveCandidate(
            candidate,
            status: status,
            visibility: visibility,
            note: note,
            sourceType: sourceType,
            ratingScore: ratingScore,
            visitedAt: visitedAt,
            plannedDate: plannedDate,
            attributes: attributes
        )
        #if DEBUG
        WanderDebugLog.sync.debug("direct save local row user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public) local_sync_state=\(localResult.syncState.rawValue, privacy: .public)")
        #endif

        if status == .wannaGo,
           currentUserPlace(matching: localResult.userPlaceID)?.status == .been {
            #if DEBUG
            WanderDebugLog.sync.debug("direct save skipped remote reason=already_checked_in user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public)")
            #endif
            return localResult
        }

        guard let backend else {
            #if DEBUG
            WanderDebugLog.sync.debug("direct save skipped remote reason=missing_backend user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public)")
            #endif
            return localResult
        }

        if status == .been,
           let explicitVisit = visits(for: localResult.userPlaceID)
            .first(where: { !$0.backfilledFromUserPlace && $0.syncState != .synced }) {
            let didSync = await syncVisit(visitID: explicitVisit.id, backend: backend)
            if didSync {
                await refreshRemoteVisiblePlaces(backend: backend)
            }
            let syncedUserPlace = currentUserPlace(matching: localResult.userPlaceID)
            let syncedPlace = syncedUserPlace.flatMap { userPlace in
                places.first {
                    $0.id == userPlace.placeID
                        || $0.localID == userPlace.placeID
                        || $0.serverID == userPlace.placeID
                }
            }
            return SaveResult(
                userPlaceID: syncedUserPlace?.id ?? localResult.userPlaceID,
                syncState: didSync ? .synced : .failed,
                placeID: syncedPlace?.serverID
            )
        }

        guard let draft = userPlaceDraft(for: localResult.userPlaceID) else {
            #if DEBUG
            WanderDebugLog.sync.debug("direct save skipped remote reason=missing_draft user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public)")
            #endif
            return localResult
        }

        let syncProperties = ownPlaceSyncProperties(
            userPlaceID: localResult.userPlaceID,
            draft: draft,
            trigger: .directSave
        )
        trackOwnPlaceSyncEvent(
            name: WanderAnalyticsEvents.ownPlaceSyncAttempted,
            properties: syncProperties
        )
        #if DEBUG
        WanderDebugLog.sync.debug("direct save remote attempt user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public) place_has_server_id=\((draft.place.serverID != nil), privacy: .public) attribute_count=\(draft.attributes.count, privacy: .public)")
        #endif

        do {
            let remoteResult = try await backend.saveUserPlace(draft)
            if let placeID = remoteResult.placeID {
                markPlace(localOrServerID: draft.place.localID, serverID: placeID, syncState: .synced)
            }
            markUserPlace(localOrServerID: localResult.userPlaceID, serverID: remoteResult.userPlaceID, syncState: .synced)
            lastRemoteError = nil
            trackOwnPlaceSyncEvent(
                name: WanderAnalyticsEvents.ownPlaceSyncSucceeded,
                properties: syncProperties
            )
            #if DEBUG
            WanderDebugLog.sync.debug("direct save remote success local_user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public) remote_user_place=\(WanderDebugLog.shortID(remoteResult.userPlaceID), privacy: .public) remote_place=\(WanderDebugLog.shortID(remoteResult.placeID), privacy: .public)")
            #endif
            await refreshRemoteVisiblePlaces(backend: backend)
            return remoteResult
        } catch {
            let message = remoteErrorMessage(error)
            markUserPlace(localOrServerID: localResult.userPlaceID, syncState: .failed, error: message)
            lastRemoteError = message
            trackOwnPlaceSyncEvent(
                name: WanderAnalyticsEvents.ownPlaceSyncFailed,
                properties: syncProperties.merging(["error_kind": remoteErrorKind(error)]) { _, new in new }
            )
            #if DEBUG
            WanderDebugLog.sync.error("direct save remote failed user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public) error_kind=\(self.remoteErrorKind(error), privacy: .public) error=\(WanderDebugLog.clean(message), privacy: .public)")
            #endif
            return SaveResult(userPlaceID: localResult.userPlaceID, syncState: .failed)
        }
    }

    @discardableResult
    func removeSave(userPlaceID: String) -> RemoveSaveResult? {
        guard let localChange = removeSaveLocally(userPlaceID: userPlaceID) else {
            return nil
        }

        return RemoveSaveResult(userPlaceID: localChange.userPlaceID, syncState: localChange.syncState)
    }

    @discardableResult
    func removeSave(userPlaceID: String, backend: WanderBackend?) async -> RemoveSaveResult? {
        guard let localChange = removeSaveLocally(userPlaceID: userPlaceID) else {
            return nil
        }

        guard let backend, !localChange.remoteUserPlaceIDs.isEmpty else {
            return RemoveSaveResult(userPlaceID: localChange.userPlaceID, syncState: localChange.syncState)
        }

        do {
            for remoteUserPlaceID in localChange.remoteUserPlaceIDs {
                try await backend.deleteUserPlace(userPlaceID: remoteUserPlaceID)
            }
            for removedUserPlaceID in localChange.removedUserPlaceIDs {
                markUserPlace(localOrServerID: removedUserPlaceID, syncState: .tombstoned)
            }
            lastRemoteError = nil
            await refreshRemoteVisiblePlaces(backend: backend)
            _ = await refreshRemoteCurrentUserCalendarData(backend: backend)
            return RemoveSaveResult(userPlaceID: localChange.userPlaceID, syncState: .tombstoned)
        } catch {
            let message = remoteErrorMessage(error)
            for removedUserPlaceID in localChange.removedUserPlaceIDs {
                markUserPlace(localOrServerID: removedUserPlaceID, syncState: .failed, error: message)
            }
            lastRemoteError = message
            return RemoveSaveResult(userPlaceID: localChange.userPlaceID, syncState: .failed)
        }
    }

    @discardableResult
    func createUnresolvedDraft(sourceType: AddSourceType, originalInput: String? = nil, localAssetRef: String? = nil) -> UnresolvedDraft {
        let title: String
        let message: String

        switch sourceType {
        case .link:
            title = "This link needs a little help."
            message = originalInput?.isEmpty == false ? originalInput ?? "Saved as a draft." : "Saved as a draft for extraction."
        case .photo:
            title = "Could not find a place in this photo."
            message = "We could not read a place from that photo yet. Add it manually if you want it on your map now."
        default:
            title = "Draft saved."
            message = "You can finish this manually."
        }

        let artifact = sourceType.createsSourceArtifact
            ? upsertSourceArtifact(sourceType: sourceType, originalInput: originalInput, localAssetRef: localAssetRef)
            : nil
        let job = artifact.map { upsertExtractionJob(sourceType: sourceType, artifact: $0) }
        if let existing = existingUnresolvedDraft(
            sourceType: sourceType,
            sourceArtifactID: artifact.map { $0.serverID ?? $0.localID },
            extractionJobID: job.map { $0.serverID ?? $0.localID }
        ) {
            return existing
        }

        let draft = UnresolvedDraft(
            id: "draft_\(sourceType.rawValue)_\(unresolvedDrafts.count + 1)",
            sourceType: sourceType,
            title: title,
            message: message,
            sourceArtifactID: artifact.map { $0.serverID ?? $0.localID },
            extractionJobID: job.map { $0.serverID ?? $0.localID },
            createdAt: .now
        )
        unresolvedDrafts.append(draft)
        persist()
        return draft
    }

    private func existingUnresolvedDraft(
        sourceType: AddSourceType,
        sourceArtifactID: String?,
        extractionJobID: String?
    ) -> UnresolvedDraft? {
        unresolvedDrafts.first { draft in
            guard draft.sourceType == sourceType else { return false }

            if let sourceArtifactID {
                return draft.sourceArtifactID == sourceArtifactID
            }

            if let extractionJobID {
                return draft.extractionJobID == extractionJobID
            }

            return false
        }
    }

    @discardableResult
    func createUnresolvedDraft(
        sourceType: AddSourceType,
        originalInput: String? = nil,
        localAssetRef: String? = nil,
        backend: WanderBackend?
    ) async -> UnresolvedDraft {
        let draft = createUnresolvedDraft(
            sourceType: sourceType,
            originalInput: originalInput,
            localAssetRef: localAssetRef
        )

        guard let backend else { return draft }
        await enqueueExtractionJob(for: draft, backend: backend)
        return updatedDraft(draft)
    }

    func enqueuePendingExtractionJobs(backend: WanderBackend) async {
        let pendingDrafts = unresolvedDrafts.filter { draft in
            guard let jobID = draft.extractionJobID,
                  let job = extractionJob(matching: jobID)
            else { return false }
            return job.serverID == nil || SyncState(rawValue: job.syncStateRaw) != .synced
        }

        for draft in pendingDrafts {
            await enqueueExtractionJob(for: draft, backend: backend)
        }
    }

    @discardableResult
    func retryFailedOwnPlaceSyncs(backend: WanderBackend?) async -> Int {
        guard let backend else {
            trackOwnPlaceSyncBatchSkipped(trigger: .failedRetry, reason: "missing_backend")
            #if DEBUG
            WanderDebugLog.sync.debug("failed retry skipped reason=missing_backend")
            #endif
            return 0
        }

        let deletedCount = await retryPendingUserPlaceDeletes(backend: backend)
        let retryableIDs = syncableOwnPlaceIDs { syncState in
            syncState == .failed
        }
        #if DEBUG
        WanderDebugLog.sync.debug("failed retry candidates count=\(retryableIDs.count, privacy: .public) states=\(self.syncCandidateStateSummary(), privacy: .public)")
        #endif
        let syncedCount = await syncOwnPlaces(withIDs: retryableIDs, backend: backend, trigger: .failedRetry)
        _ = await syncPendingVisits(backend: backend)
        return syncedCount + deletedCount
    }

    @discardableResult
    func syncUnsyncedOwnPlaces(backend: WanderBackend?) async -> Int {
        guard let backend else {
            trackOwnPlaceSyncBatchSkipped(trigger: .signedInBackfill, reason: "missing_backend")
            #if DEBUG
            WanderDebugLog.sync.debug("signed-in backfill skipped reason=missing_backend states=\(self.syncCandidateStateSummary(), privacy: .public)")
            #endif
            return 0
        }

        let deletedCount = await retryPendingUserPlaceDeletes(backend: backend)
        let syncableIDs = syncableOwnPlaceIDs { syncState in
            syncState != .synced
                && syncState != .pendingDelete
                && syncState != .serverDenied
                && syncState != .tombstoned
        }
        #if DEBUG
        WanderDebugLog.sync.debug("signed-in backfill candidates count=\(syncableIDs.count, privacy: .public) states=\(self.syncCandidateStateSummary(), privacy: .public)")
        #endif
        let syncedCount = await syncOwnPlaces(withIDs: syncableIDs, backend: backend, trigger: .signedInBackfill)
        _ = await syncPendingVisits(backend: backend)
        return syncedCount + deletedCount
    }

    @discardableResult
    func retryPendingUserPlaceDeletes(backend: WanderBackend?) async -> Int {
        guard let backend else { return 0 }
        let pendingRows = userPlaces.filter {
            $0.userID == currentUser.id
                && $0.deletedAt != nil
                && $0.serverID != nil
                && ($0.syncState == .pendingDelete || $0.syncState == .failed)
        }
        let rowsByRemoteID = Dictionary(
            grouping: pendingRows,
            by: { $0.serverID ?? $0.id }
        )

        var syncedCount = 0
        for remoteUserPlaceID in rowsByRemoteID.keys.sorted() {
            let rows = rowsByRemoteID[remoteUserPlaceID] ?? []
            do {
                try await backend.deleteUserPlace(userPlaceID: remoteUserPlaceID)
                for row in rows {
                    markUserPlace(localOrServerID: row.id, syncState: .tombstoned)
                }
                lastRemoteError = nil
                syncedCount += 1
            } catch {
                let message = remoteErrorMessage(error)
                for row in rows {
                    markUserPlace(
                        localOrServerID: row.id,
                        syncState: .failed,
                        error: message
                    )
                }
                lastRemoteError = message
            }
        }

        if syncedCount > 0 {
            _ = await refreshRemoteCurrentUserCalendarData(backend: backend)
        }
        return syncedCount
    }

    @discardableResult
    func syncPendingVisits(backend: WanderBackend?) async -> Int {
        guard let backend else { return 0 }

        var syncedCount = await retryPendingVisitDeletes(backend: backend)
        let visitIDs = placeVisits
            .filter { visit in
                guard let userPlace = userPlaces.first(where: { userPlace in
                    userPlace.userID == currentUser.id
                        && userPlace.deletedAt == nil
                        && (userPlace.id == visit.userPlaceID || userPlace.localID == visit.userPlaceID || userPlace.serverID == visit.userPlaceID)
                }) else {
                    return false
                }

                return visit.deletedAt == nil
                    && visit.syncState != .synced
                    && visit.syncState != .serverDenied
                    && visit.syncState != .tombstoned
                    && userPlace.status == .been
                    && userPlace.syncState != .pendingDelete
                    && userPlace.syncState != .serverDenied
                    && userPlace.syncState != .tombstoned
            }
            .map(\.id)

        for visitID in visitIDs {
            if await syncVisit(visitID: visitID, backend: backend) {
                syncedCount += 1
            }
        }
        return syncedCount
    }

    @discardableResult
    func syncVisit(visitID: String, backend: WanderBackend?) async -> Bool {
        guard let backend,
              let visit = placeVisits.first(where: { $0.deletedAt == nil && ($0.id == visitID || $0.localID == visitID || $0.serverID == visitID) }),
              let userPlace = userPlaces.first(where: { userPlace in
                  userPlace.deletedAt == nil
                      && (userPlace.id == visit.userPlaceID || userPlace.localID == visit.userPlaceID || userPlace.serverID == visit.userPlaceID)
              })
        else {
            return false
        }

        guard userPlace.status == .been,
              userPlace.syncState != .pendingDelete,
              userPlace.syncState != .serverDenied,
              userPlace.syncState != .tombstoned
        else {
            return false
        }

        if visit.backfilledFromUserPlace {
            if userPlace.serverID == nil || userPlace.syncState != .synced {
                let parentOutcome = await retryOwnPlaceSync(
                    userPlaceID: userPlace.id,
                    backend: backend,
                    trigger: .signedInBackfill
                )
                guard case .succeeded = parentOutcome else {
                    return false
                }
            }

            guard let remoteUserPlaceID = userPlace.serverID else {
                markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: "Missing remote user place id")
                return false
            }
            return await hydrateBackfilledVisit(visit, remoteUserPlaceID: remoteUserPlaceID, backend: backend)
        }

        if visit.serverID == nil {
            markPlaceVisit(localOrServerID: visit.id, serverID: UUID().uuidString.lowercased(), syncState: .pendingCreate)
        } else {
            markPlaceVisit(localOrServerID: visit.id, syncState: visit.serverUpdatedAt == nil ? .pendingCreate : .pendingUpdate)
        }

        guard let checkInDraft = checkInDraft(for: visit.id, userPlace: userPlace) else {
            markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: "Missing check-in draft")
            return false
        }

        do {
            let result = try await backend.saveCheckIn(checkInDraft)
            if let placeID = result.saveResult.placeID {
                markPlace(
                    localOrServerID: checkInDraft.userPlace.place.localID,
                    serverID: placeID,
                    syncState: .synced
                )
            }
            markUserPlace(
                localOrServerID: userPlace.id,
                serverID: result.saveResult.userPlaceID,
                syncState: .synced
            )
            markPlaceVisit(
                localOrServerID: visit.id,
                serverID: result.visitResult.visitID,
                syncState: .synced,
                result: result.visitResult
            )
            lastRemoteError = nil
            return true
        } catch {
            let message = remoteErrorMessage(error)
            markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: message)
            markUserPlace(localOrServerID: userPlace.id, syncState: .failed, error: message)
            lastRemoteError = message
            return false
        }
    }

    @discardableResult
    func retryPendingVisitDeletes(backend: WanderBackend?) async -> Int {
        guard let backend else { return 0 }
        let pendingIDs = placeVisits
            .filter {
                $0.deletedAt != nil
                    && $0.serverID != nil
                    && ($0.syncState == .pendingDelete || $0.syncState == .failed)
            }
            .map(\.id)

        var syncedCount = 0
        for visitID in pendingIDs {
            guard let visit = placeVisits.first(where: { $0.id == visitID || $0.localID == visitID || $0.serverID == visitID }),
                  let remoteVisitID = visit.serverID
            else { continue }

            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.checkInSyncRetried,
                    properties: ["operation": "delete"]
                )
            )
            do {
                _ = try await backend.deleteCheckIn(visitID: remoteVisitID)
                markPlaceVisit(localOrServerID: visit.id, syncState: .tombstoned)
                lastRemoteError = nil
                syncedCount += 1
            } catch {
                let message = remoteErrorMessage(error)
                markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: message)
                lastRemoteError = message
            }
        }
        if syncedCount > 0 {
            _ = await refreshRemoteCurrentUserCalendarData(backend: backend)
        }
        return syncedCount
    }

    @discardableResult
    func uploadVisitPhoto(photoID: String, data: Data?, backend: WanderBackend?) async -> LocalVisitPhoto? {
        guard let backend,
              let photo = currentUserPhoto(matching: photoID),
              let visit = currentUserVisit(matching: photo.visitID)
        else {
            return nil
        }

        if visit.serverID == nil || visit.syncState != .synced {
            _ = await syncVisit(visitID: visit.id, backend: backend)
        }

        guard let remoteVisitID = visit.serverID else {
            markVisitPhoto(localOrServerID: photo.id, syncState: .failed, uploadState: .failed, error: "Missing remote visit id")
            return photo
        }

        let remotePhotoID = photo.serverID ?? UUID().uuidString.lowercased()
        let contentType = photo.contentType ?? "image/jpeg"
        let storagePath = "\(currentUser.id)/\(remoteVisitID)/\(remotePhotoID).\(fileExtension(forContentType: contentType))"
        let alreadyUploaded = photo.uploadState == .uploaded
            && photo.remoteURLString?.isEmpty == false
        markVisitPhoto(
            localOrServerID: photo.id,
            serverID: remotePhotoID,
            visitID: remoteVisitID,
            storagePath: storagePath,
            syncState: alreadyUploaded ? .pendingUpdate : .pendingCreate,
            uploadState: alreadyUploaded ? .uploaded : .pendingUpload
        )

        do {
            if alreadyUploaded {
                guard let uploadedDraft = visitPhotoDraft(for: photo.id, uploadState: .uploaded) else {
                    markVisitPhoto(
                        localOrServerID: photo.id,
                        syncState: .failed,
                        uploadState: .uploaded,
                        error: "Missing uploaded visit photo draft"
                    )
                    return photo
                }
                let result = try await backend.upsertVisitPhotoMetadata(uploadedDraft)
                markVisitPhoto(
                    localOrServerID: photo.id,
                    syncState: .synced,
                    uploadState: result.uploadState,
                    result: result
                )
                lastRemoteError = nil
                return photo
            }

            guard let data else {
                markVisitPhoto(
                    localOrServerID: photo.id,
                    syncState: .failed,
                    uploadState: .failed,
                    error: "Missing local visit photo data"
                )
                return photo
            }
            guard let pendingDraft = visitPhotoDraft(for: photo.id, uploadState: .pendingUpload) else {
                markVisitPhoto(localOrServerID: photo.id, syncState: .failed, uploadState: .failed, error: "Missing visit photo draft")
                return photo
            }
            _ = try await backend.upsertVisitPhotoMetadata(pendingDraft)
            markVisitPhoto(localOrServerID: photo.id, syncState: .pendingUpdate, uploadState: .uploading)
            let remoteURL = try await backend.uploadVisitPhotoData(
                bucket: pendingDraft.storageBucket,
                path: pendingDraft.storagePath,
                data: data,
                contentType: contentType
            )
            markVisitPhoto(
                localOrServerID: photo.id,
                remoteURLString: remoteURL.absoluteString,
                syncState: .pendingUpdate,
                uploadState: .uploaded
            )
            if let uploadedDraft = visitPhotoDraft(for: photo.id, uploadState: .uploaded) {
                let result = try await backend.upsertVisitPhotoMetadata(uploadedDraft)
                markVisitPhoto(localOrServerID: photo.id, syncState: .synced, uploadState: result.uploadState, result: result)
            }
            lastRemoteError = nil
        } catch {
            let message = remoteErrorMessage(error)
            let latestPhoto = currentUserPhoto(matching: photo.id)
            let uploadState: VisitPhotoUploadState = latestPhoto?.uploadState == .uploaded
                && latestPhoto?.remoteURLString?.isEmpty == false
                ? .uploaded
                : .failed
            markVisitPhoto(
                localOrServerID: photo.id,
                syncState: .failed,
                uploadState: uploadState,
                error: message
            )
            lastRemoteError = message
        }

        return photo
    }

    @discardableResult
    func deleteVisit(visitID: String, backend: WanderBackend?) async -> Bool {
        let existingVisit = placeVisits.first { $0.id == visitID || $0.localID == visitID || $0.serverID == visitID }
        let remoteVisitID = existingVisit?.serverID
        let requiresRemoteDelete = existingVisit?.serverUpdatedAt != nil || existingVisit?.syncState != .pendingCreate
        let didDeleteLocally = deleteVisit(visitID: visitID)
        guard didDeleteLocally else { return false }
        guard requiresRemoteDelete, let backend, let remoteVisitID else {
            markPlaceVisit(localOrServerID: visitID, syncState: .tombstoned)
            return true
        }

        do {
            _ = try await backend.deleteCheckIn(visitID: remoteVisitID)
            markPlaceVisit(localOrServerID: visitID, syncState: .tombstoned)
            lastRemoteError = nil
            _ = await refreshRemoteCurrentUserCalendarData(backend: backend)
            return true
        } catch {
            let message = remoteErrorMessage(error)
            markPlaceVisit(localOrServerID: visitID, syncState: .failed, error: message)
            lastRemoteError = message
            return true
        }
    }

    @discardableResult
    func deleteVisitPhoto(photoID: String, backend: WanderBackend?) async -> Bool {
        let photo = visitPhotos.first { $0.id == photoID || $0.localID == photoID || $0.serverID == photoID }
        let remotePhotoID = photo?.serverID
        let storageBucket = photo?.storageBucket ?? "visit-photos"
        let storagePath = photo?.storagePath
        let didDeleteLocally = deleteVisitPhoto(photoID: photoID)
        guard didDeleteLocally else { return false }
        guard let backend, let remotePhotoID, let storagePath else { return true }

        do {
            try await backend.deleteVisitPhoto(photoID: remotePhotoID, bucket: storageBucket, path: storagePath)
            markVisitPhoto(localOrServerID: photoID, syncState: .tombstoned, uploadState: .failed)
            lastRemoteError = nil
            return true
        } catch {
            let message = remoteErrorMessage(error)
            markVisitPhoto(localOrServerID: photoID, syncState: .failed, uploadState: .failed, error: message)
            lastRemoteError = message
            return false
        }
    }

    private func syncOwnPlaces(withIDs userPlaceIDs: [String], backend: WanderBackend, trigger: OwnPlaceSyncTrigger) async -> Int {
        var syncedCount = 0
        var failedCount = 0
        var skippedCount = 0

        trackOwnPlaceSyncEvent(
            name: WanderAnalyticsEvents.ownPlaceSyncBatchStarted,
            properties: [
                "trigger": trigger.rawValue,
                "candidate_count": "\(userPlaceIDs.count)"
            ]
        )
        #if DEBUG
        WanderDebugLog.sync.debug("sync batch started trigger=\(trigger.rawValue, privacy: .public) candidate_count=\(userPlaceIDs.count, privacy: .public)")
        #endif

        for userPlaceID in userPlaceIDs {
            switch await retryOwnPlaceSync(
                userPlaceID: userPlaceID,
                backend: backend,
                trigger: trigger,
                refreshVisiblePlacesAfterSuccess: false
            ) {
            case .succeeded:
                syncedCount += 1
            case .failed:
                failedCount += 1
            case .skipped:
                skippedCount += 1
            }
        }

        trackOwnPlaceSyncEvent(
            name: WanderAnalyticsEvents.ownPlaceSyncBatchCompleted,
            properties: [
                "trigger": trigger.rawValue,
                "candidate_count": "\(userPlaceIDs.count)",
                "synced_count": "\(syncedCount)",
                "failed_count": "\(failedCount)",
                "skipped_count": "\(skippedCount)"
            ]
        )
        #if DEBUG
        WanderDebugLog.sync.debug("sync batch completed trigger=\(trigger.rawValue, privacy: .public) synced=\(syncedCount, privacy: .public) failed=\(failedCount, privacy: .public) skipped=\(skippedCount, privacy: .public)")
        #endif
        if syncedCount > 0 {
            await refreshRemoteVisiblePlaces(backend: backend)
        }

        return syncedCount
    }

    private func syncableOwnPlaceIDs(matching shouldSyncState: (SyncState) -> Bool) -> [String] {
        userPlaces
            .filter { userPlace in
                userPlace.userID == currentUser.id
                    && userPlace.deletedAt == nil
                    && userPlace.sourceType != AddSourceType.socialSave.rawValue
                    && shouldSyncState(userPlace.syncState)
            }
            .map(\.id)
    }

    func extractionJob(for draft: UnresolvedDraft) -> LocalExtractionJob? {
        guard let jobID = draft.extractionJobID else { return nil }
        return extractionJob(matching: jobID)
    }

    @discardableResult
    func processExtractionJob(for draft: UnresolvedDraft, backend: WanderBackend) async -> ExtractionJobResult? {
        guard let job = extractionJob(for: draft),
              let remoteJobID = job.serverID ?? draft.remoteExtractionJobID
        else { return nil }

        do {
            let result = try await backend.processExtractionJob(jobID: remoteJobID)
            applyExtractionResult(result)
            lastRemoteError = nil
            return result
        } catch {
            let message = remoteErrorMessage(error)
            job.syncStateRaw = SyncState.failed.rawValue
            job.lastSyncError = message
            job.errorCode = "process_failed"
            job.errorMessage = message
            job.updatedAt = .now
            job.localUpdatedAt = .now
            lastRemoteError = message
            objectWillChange.send()
            persist()
            return nil
        }
    }

    @discardableResult
    func refreshExtractionJob(for draft: UnresolvedDraft, backend: WanderBackend) async -> ExtractionJobResult? {
        guard let job = extractionJob(for: draft),
              let remoteJobID = job.serverID ?? draft.remoteExtractionJobID
        else { return nil }

        do {
            let result = try await backend.extractionJobResult(jobID: remoteJobID)
            applyExtractionResult(result)
            lastRemoteError = nil
            return result
        } catch {
            lastRemoteError = remoteErrorMessage(error)
            return nil
        }
    }

    func saveVisiblePlace(_ visiblePlace: VisiblePlace, status: PlaceStatus = .wannaGo) -> SaveResult {
        let copiedAttributes = attributes(for: visiblePlace.userPlace.id).map { attribute in
            PlaceAttributeDraft(questionKey: attribute.questionKey, valueType: attribute.valueType, valueJSON: attribute.valueJSON)
        }

        return saveCandidate(
            PlaceCandidate(
                id: visiblePlace.place.id,
                name: visiblePlace.place.canonicalName,
                category: visiblePlace.effectiveCategory,
                primaryCategory: visiblePlace.effectiveCategory,
                subcategory: visiblePlace.effectiveSubcategory,
                categorySource: visiblePlace.categoryAssignment.source,
                categoryConfidence: visiblePlace.categoryAssignment.confidence,
                rawProviderType: visiblePlace.place.rawProviderType,
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude,
                sourceProvider: visiblePlace.place.sourceProvider,
                sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID,
                websiteURLString: visiblePlace.place.websiteURLString,
                phoneNumber: visiblePlace.place.phoneNumber,
                timeZoneIdentifier: visiblePlace.place.timeZoneIdentifier,
                actionLinksJSON: visiblePlace.place.actionLinksJSON,
                confidence: visiblePlace.place.confidence ?? 1
            ),
            status: status,
            visibility: effectiveDefaultVisibility,
            note: visiblePlace.userPlace.note,
            sourceType: .socialSave,
            attributes: copiedAttributes
        )
    }

    @discardableResult
    func applyProviderBusinessMetadata(placeID: String, metadata: PlaceBusinessMetadata) -> Bool {
        var didChange = false
        var seenPlaces = Set<ObjectIdentifier>()
        let candidatePlaces = places + remoteVisiblePlaceCache.map(\.place)

        for place in candidatePlaces where place.id == placeID
            || place.localID == placeID
            || place.serverID == placeID {
            guard seenPlaces.insert(ObjectIdentifier(place)).inserted else { continue }

            let stored = PlaceBusinessMetadata(
                websiteURLString: place.websiteURLString,
                phoneNumber: place.phoneNumber,
                timeZoneIdentifier: place.timeZoneIdentifier
            )
            let merged = stored.mergingMissingValues(from: metadata)
            guard merged != stored else { continue }

            place.websiteURLString = merged.websiteURLString
            place.phoneNumber = merged.phoneNumber
            place.timeZoneIdentifier = merged.timeZoneIdentifier
            place.localUpdatedAt = .now
            place.updatedAt = .now
            didChange = true
        }

        if didChange {
            objectWillChange.send()
            persist()
        }
        return didChange
    }

    @discardableResult
    func saveVisiblePlace(_ visiblePlace: VisiblePlace, status: PlaceStatus = .wannaGo, backend: WanderBackend?) async -> SaveResult {
        let localResult = saveVisiblePlace(visiblePlace, status: status)

        if status == .wannaGo,
           currentUserPlace(matching: localResult.userPlaceID)?.status == .been {
            return localResult
        }

        guard let backend else {
            return localResult
        }
        guard let remoteIDs = remoteSocialSaveIDs(for: visiblePlace) else {
            return localResult
        }

        do {
            let remoteResult = try await backend.saveVisiblePlace(
                placeID: remoteIDs.placeID,
                sourceUserPlaceID: remoteIDs.sourceUserPlaceID
            )
            markUserPlace(localOrServerID: localResult.userPlaceID, serverID: remoteResult.userPlaceID, syncState: .synced)
            lastRemoteError = nil
            await refreshRemoteVisiblePlaces(backend: backend)
            return remoteResult
        } catch {
            let message = remoteErrorMessage(error)
            markUserPlace(localOrServerID: localResult.userPlaceID, syncState: .failed, error: message)
            lastRemoteError = message
            return SaveResult(userPlaceID: localResult.userPlaceID, syncState: .failed)
        }
    }

    func follow(userID: String, source: FollowSource = .profile) {
        guard userID != currentUser.id,
              !isBlockedBetweenCurrentUser(and: userID),
              !follows.contains(where: { $0.followerUserID == currentUser.id && $0.followedUserID == userID })
        else { return }

        follows.append(
            LocalFollow(
                localID: "local_follow_\(currentUser.id)_\(userID)",
                followerUserID: currentUser.id,
                followedUserID: userID,
                source: source,
                syncState: .pendingCreate
            )
        )
        trackFollowCreated(source: source, outcome: "local_only")
        persist()
    }

    @discardableResult
    func follow(userID: String, source: FollowSource = .profile, backend: WanderBackend?) async -> Bool {
        let follow = upsertFollow(userID: userID, source: source)

        guard let follow else {
            return relationship(to: userID) == .follower || relationship(to: userID) == .mutual
        }

        guard let backend else {
            trackFollowCreated(source: source, outcome: "queued")
            persist()
            return false
        }

        do {
            try await backend.follow(userID: userID)
            follow.syncStateRaw = SyncState.synced.rawValue
            follow.lastSyncError = nil
            follow.serverUpdatedAt = .now
            lastRemoteError = nil
            objectWillChange.send()
            persist()
            await refreshRemoteSocialGraph(backend: backend)
            await refreshRemoteVisiblePlaces(backend: backend)
            trackFollowCreated(source: source, outcome: "succeeded")
            return true
        } catch {
            follow.syncStateRaw = SyncState.failed.rawValue
            follow.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = follow.lastSyncError
            objectWillChange.send()
            persist()
            return false
        }
    }

    private func trackFollowCreated(source: FollowSource, outcome: String) {
        let properties = ["source": source.rawValue, "outcome": outcome]
        analytics.track(
            AnalyticsEvent(name: WanderAnalyticsEvents.followCreated, properties: properties)
        )
        analytics.track(
            .engagement(
                need: .connect,
                action: .followCreated,
                surface: source.rawValue,
                properties: ["outcome": outcome]
            )
        )
    }

    func unfollow(userID: String) {
        follows.removeAll { $0.followerUserID == currentUser.id && $0.followedUserID == userID }
        persist()
    }

    func unfollow(userID: String, backend: WanderBackend?) async {
        guard let follow = follows.first(where: { $0.followerUserID == currentUser.id && $0.followedUserID == userID }) else {
            return
        }

        guard let backend else {
            unfollow(userID: userID)
            return
        }

        follow.syncStateRaw = SyncState.pendingDelete.rawValue
        follow.lastSyncError = nil
        objectWillChange.send()
        persist()

        do {
            try await backend.unfollow(userID: userID)
            lastRemoteError = nil
            unfollow(userID: userID)
            await refreshRemoteSocialGraph(backend: backend)
            await refreshRemoteVisiblePlaces(backend: backend)
        } catch {
            follow.syncStateRaw = SyncState.failed.rawValue
            follow.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = follow.lastSyncError
            objectWillChange.send()
            persist()
        }
    }

    func block(userID: String) {
        guard userID != currentUser.id,
              !blocks.contains(where: { $0.blockerUserID == currentUser.id && $0.blockedUserID == userID })
        else { return }

        follows.removeAll { follow in
            (follow.followerUserID == currentUser.id && follow.followedUserID == userID)
                || (follow.followerUserID == userID && follow.followedUserID == currentUser.id)
        }
        blocks.append(
            LocalBlock(
                localID: "local_block_\(currentUser.id)_\(userID)",
                blockerUserID: currentUser.id,
                blockedUserID: userID,
                syncState: .pendingCreate
            )
        )
        persist()
    }

    func block(userID: String, backend: WanderBackend?) async {
        let block = upsertBlock(userID: userID)

        guard let block else {
            return
        }

        guard let backend else {
            persist()
            return
        }

        do {
            try await backend.block(userID: userID)
            block.syncStateRaw = SyncState.synced.rawValue
            block.lastSyncError = nil
            block.serverUpdatedAt = .now
            lastRemoteError = nil
            objectWillChange.send()
            persist()
            await refreshRemoteSocialGraph(backend: backend)
            await refreshRemoteVisiblePlaces(backend: backend)
        } catch {
            block.syncStateRaw = SyncState.failed.rawValue
            block.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = block.lastSyncError
            objectWillChange.send()
            persist()
        }
    }

    func block(profile: ProfileShell, backend: WanderBackend?) async {
        preserveBlockedProfileShell(profile)
        await block(userID: profile.id, backend: backend)
    }

    func unblock(userID: String) {
        blocks.removeAll { $0.blockerUserID == currentUser.id && $0.blockedUserID == userID }
        persist()
    }

    func unblock(userID: String, backend: WanderBackend?) async {
        guard let block = blocks.first(where: { $0.blockerUserID == currentUser.id && $0.blockedUserID == userID }) else {
            return
        }

        guard let backend else {
            unblock(userID: userID)
            return
        }

        block.syncStateRaw = SyncState.pendingDelete.rawValue
        block.lastSyncError = nil
        objectWillChange.send()
        persist()

        do {
            try await backend.unblock(userID: userID)
            lastRemoteError = nil
            unblock(userID: userID)
            await refreshRemoteSocialGraph(backend: backend)
            await refreshRemoteVisiblePlaces(backend: backend)
        } catch {
            block.syncStateRaw = SyncState.failed.rawValue
            block.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = block.lastSyncError
            objectWillChange.send()
            persist()
        }
    }

    func refreshRemoteVisiblePlaces(in viewport: MapViewport, backend: WanderBackend?) async {
        guard let backend else {
            return
        }

        do {
            let visiblePlaces = try await backend.visiblePlaces(in: viewport)
            replaceRemoteViewportVisiblePlaces(visiblePlaces)
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
        await refreshRemoteWannaGoPlans(backend: backend)
    }

    /// Fetches one Map viewport without replacing the store's profile-wide
    /// social cache. Map uses this lightweight path after camera gestures so a
    /// pan does not re-run the full social snapshot or Wanna plan refresh.
    func fetchRemoteViewportPlaces(
        in viewport: MapViewport,
        backend: WanderBackend?
    ) async -> [VisiblePlace]? {
        guard let backend, backend.placeRepository != nil else { return nil }
        let requestUserID = currentUser.id

        do {
            let visiblePlaces = try await backend.visiblePlaces(in: viewport)
            guard currentUser.id == requestUserID, !Task.isCancelled else { return nil }
            lastRemoteError = nil
            return visiblePlaces
        } catch {
            guard currentUser.id == requestUserID, !Task.isCancelled else { return nil }
            lastRemoteError = remoteErrorMessage(error)
            return nil
        }
    }

    /// Fetches the server-bounded community candidate set used only by
    /// Featured. It intentionally leaves the profile-wide social cache alone.
    func fetchRemoteFeaturedViewportPlaces(
        in viewport: MapViewport,
        backend: WanderBackend?
    ) async -> [VisiblePlace]? {
        guard let backend, backend.placeRepository != nil else { return nil }
        let requestUserID = currentUser.id

        do {
            let visiblePlaces = try await backend.featuredPlaces(in: viewport)
            guard currentUser.id == requestUserID, !Task.isCancelled else { return nil }
            lastRemoteError = nil
            return visiblePlaces
        } catch {
            guard currentUser.id == requestUserID, !Task.isCancelled else { return nil }
            lastRemoteError = remoteErrorMessage(error)
            return nil
        }
    }

    func refreshRemoteWannaGoPlans(backend: WanderBackend?) async {
        guard let backend, backend.userPlaceRepository != nil else {
            return
        }
        let requestUserID = currentUser.id

        do {
            let plans = try await backend.ownWannaGoPlans()
            guard currentUser.id == requestUserID, !Task.isCancelled else { return }
            applyRemoteWannaGoPlans(plans)
            lastRemoteError = nil
        } catch {
            guard currentUser.id == requestUserID, !Task.isCancelled else { return }
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    @discardableResult
    func refreshRemoteCurrentProfile(backend: WanderBackend?) async -> Bool {
        guard let backend else {
            return false
        }
        let requestUserID = currentUser.id

        do {
            guard let profile = try await backend.currentProfile(),
                  !Task.isCancelled,
                  currentUser.id == requestUserID,
                  profile.id == requestUserID
            else { return false }
            applyRemoteCurrentProfile(profile)
            lastRemoteError = nil
            return true
        } catch {
            guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    func refreshRemoteVisiblePlaces(backend: WanderBackend?) async {
        await refreshRemoteVisiblePlaces(in: Self.defaultRemoteViewport, backend: backend)
    }

    func refreshRemotePlaceLists(backend: WanderBackend?) async {
        guard let backend else {
            return
        }
        let refreshSignpostID = WanderDebugLog.beginPerformanceInterval("List Refresh Total")
        defer {
            WanderDebugLog.endPerformanceInterval(
                "List Refresh Total",
                id: refreshSignpostID
            )
        }

        do {
            if backend.surfaceSnapshotRepository != nil {
                let snapshot = try await backend.placeListsSnapshot()
                let applySignpostID = WanderDebugLog.beginPerformanceInterval("List Apply")
                withDeferredPersistence {
                    reconcileMissingRemotePlaceLists(with: snapshot.summaries)
                    upsertRemotePlaceListSummaries(snapshot.summaries)
                    for ownerID in snapshot.visiblePlacesByOwnerID.keys.sorted() {
                        guard let visiblePlaces = snapshot.visiblePlacesByOwnerID[ownerID] else {
                            continue
                        }
                        applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: ownerID)
                    }
                    for ownerID in snapshot.relationshipsByOwnerID.keys.sorted() {
                        guard ownerID != currentUser.id,
                              let relationship = snapshot.relationshipsByOwnerID[ownerID]
                        else {
                            continue
                        }
                        applyRemoteRelationship(profileID: ownerID, relationship: relationship)
                    }
                    for detail in snapshot.details {
                        upsertRemotePlaceListDetail(detail)
                    }
                    lastRemoteError = nil
                    persist()
                }
                WanderDebugLog.endPerformanceInterval("List Apply", id: applySignpostID)
                return
            }

            let summaries = try await backend.visiblePlaceLists()
            let ownerIDs = Set(summaries.map { $0.list.ownerUserID })
            var visiblePlacesByOwnerID: [String: [VisiblePlace]] = [:]
            var relationshipsByOwnerID: [String: ViewerRelationship] = [:]
            var details: [RemotePlaceListDetail] = []
            var firstRefreshError: Error?

            for ownerID in ownerIDs.sorted() {
                do {
                    visiblePlacesByOwnerID[ownerID] = try await backend.userPlaces(for: ownerID)
                } catch {
                    continue
                }
                guard ownerID != currentUser.id else { continue }
                do {
                    relationshipsByOwnerID[ownerID] = try await backend.relationship(to: ownerID)
                } catch {
                    continue
                }
            }

            for summary in summaries where UUID(uuidString: summary.list.id) != nil {
                do {
                    if let detail = try await backend.placeListDetail(listID: summary.list.id) {
                        details.append(detail)
                    }
                } catch {
                    firstRefreshError = firstRefreshError ?? error
                }
            }

            withDeferredPersistence {
                reconcileMissingRemotePlaceLists(with: summaries)
                upsertRemotePlaceListSummaries(summaries)
                for ownerID in ownerIDs.sorted() {
                    guard let visiblePlaces = visiblePlacesByOwnerID[ownerID] else { continue }
                    applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: ownerID)
                    if let relationship = relationshipsByOwnerID[ownerID] {
                        applyRemoteRelationship(profileID: ownerID, relationship: relationship)
                    }
                }
                for detail in details {
                    upsertRemotePlaceListDetail(detail)
                }
                lastRemoteError = firstRefreshError.map(remoteErrorMessage)
                persist()
            }
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func refreshRemotePlaceList(_ list: LocalPlaceList, backend: WanderBackend?) async {
        guard let backend,
              let remoteListID = list.serverID ?? (UUID(uuidString: list.id) != nil ? list.id : nil)
        else {
            return
        }

        var visiblePlaces: [VisiblePlace]?
        var relationship: ViewerRelationship?
        var detail: RemotePlaceListDetail?
        var firstRefreshError: Error?

        do {
            visiblePlaces = try await backend.userPlaces(for: list.ownerUserID)
        } catch {
            visiblePlaces = nil
        }

        if visiblePlaces != nil, list.ownerUserID != currentUser.id {
            do {
                relationship = try await backend.relationship(to: list.ownerUserID)
            } catch {
                relationship = nil
            }
        }

        do {
            detail = try await backend.placeListDetail(listID: remoteListID)
        } catch {
            firstRefreshError = firstRefreshError ?? error
        }

        withDeferredPersistence {
            if let visiblePlaces {
                applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: list.ownerUserID)
            }
            if let relationship {
                applyRemoteRelationship(profileID: list.ownerUserID, relationship: relationship)
            }
            if let detail {
                upsertRemotePlaceListDetail(detail)
            }
            lastRemoteError = firstRefreshError.map(remoteErrorMessage)
            persist()
        }
    }

    @discardableResult
    func refreshRemoteSocialSurfaces(backend: WanderBackend?) async -> Bool {
        await refreshRemoteSocialSurfaces(in: Self.defaultRemoteViewport, backend: backend)
    }

    @discardableResult
    func refreshRemoteSocialSurfaces(in viewport: MapViewport, backend: WanderBackend?) async -> Bool {
        guard let backend else { return false }
        let refreshSignpostID = WanderDebugLog.beginPerformanceInterval("Social Refresh Total")
        defer {
            WanderDebugLog.endPerformanceInterval(
                "Social Refresh Total",
                id: refreshSignpostID
            )
        }
        let requestUserID = currentUser.id
        guard !Task.isCancelled else { return false }

        if backend.surfaceSnapshotRepository != nil {
            do {
                let snapshot = try await backend.socialSurfaceSnapshot(in: viewport)
                guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
                let followedProfileIDs = snapshot.following
                    .map(\.id)
                    .filter { $0 != requestUserID }
                    .sorted()
                let applySignpostID = WanderDebugLog.beginPerformanceInterval("Social Apply")
                withDeferredPersistence {
                    upsertRemoteSocialGraph(
                        userID: requestUserID,
                        following: snapshot.following,
                        followers: snapshot.followers
                    )
                    replaceRemoteViewportVisiblePlaces(snapshot.viewportPlaces)
                    applyRemoteWannaGoPlans(snapshot.ownWannaGoPlans)
                    for profileID in followedProfileIDs {
                        if let visiblePlaces = snapshot.visiblePlacesByOwnerID[profileID] {
                            applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: profileID)
                        }
                        if let relationship = snapshot.relationshipsByOwnerID[profileID] {
                            applyRemoteRelationship(
                                profileID: profileID,
                                relationship: relationship
                            )
                        }
                    }
                    lastRemoteError = nil
                    persist()
                }
                WanderDebugLog.endPerformanceInterval("Social Apply", id: applySignpostID)
                return true
            } catch {
                guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
                lastRemoteError = remoteErrorMessage(error)
                return false
            }
        }

        let locallyFollowedProfileIDs = Set(following(of: requestUserID).map(\.id))
        var remoteFollowing: [ProfileShell]?
        var remoteFollowers: [ProfileShell]?
        var viewportPlaces: [VisiblePlace]?
        var ownWannaGoPlans: [OwnWannaGoPlan]?
        var visiblePlacesByOwnerID: [String: [VisiblePlace]] = [:]
        var relationshipsByOwnerID: [String: ViewerRelationship] = [:]
        var firstRefreshError: Error?

        if backend.followRepository != nil {
            do {
                remoteFollowing = try await backend.following(userID: requestUserID)
                guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
                remoteFollowers = try await backend.followers(userID: requestUserID)
            } catch {
                firstRefreshError = firstRefreshError ?? error
            }
            guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
        }
        if backend.placeRepository != nil {
            do {
                viewportPlaces = try await backend.visiblePlaces(in: viewport)
            } catch {
                firstRefreshError = firstRefreshError ?? error
            }
            guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
        }
        if backend.userPlaceRepository != nil {
            do {
                ownWannaGoPlans = try await backend.ownWannaGoPlans()
            } catch {
                firstRefreshError = firstRefreshError ?? error
            }
            guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
        }
        let followedProfileIDs = locallyFollowedProfileIDs
            .union(remoteFollowing?.map(\.id) ?? [])
            .subtracting([requestUserID])
            .sorted()

        for profileID in followedProfileIDs {
            guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
            if backend.userPlaceRepository != nil {
                do {
                    visiblePlacesByOwnerID[profileID] = try await backend.userPlaces(for: profileID)
                } catch {
                    firstRefreshError = firstRefreshError ?? error
                }
                guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
            }
            if backend.followRepository != nil {
                do {
                    relationshipsByOwnerID[profileID] = try await backend.relationship(to: profileID)
                } catch {
                    firstRefreshError = firstRefreshError ?? error
                }
                guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
            }
        }

        guard currentUser.id == requestUserID, !Task.isCancelled else { return false }
        withDeferredPersistence {
            if let remoteFollowing, let remoteFollowers {
                upsertRemoteSocialGraph(
                    userID: requestUserID,
                    following: remoteFollowing,
                    followers: remoteFollowers
                )
            }
            if let viewportPlaces {
                replaceRemoteViewportVisiblePlaces(viewportPlaces)
            }
            if let ownWannaGoPlans {
                applyRemoteWannaGoPlans(ownWannaGoPlans)
            }
            for profileID in followedProfileIDs {
                if let visiblePlaces = visiblePlacesByOwnerID[profileID] {
                    applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: profileID)
                }
                if let relationship = relationshipsByOwnerID[profileID] {
                    applyRemoteRelationship(profileID: profileID, relationship: relationship)
                }
            }
            lastRemoteError = firstRefreshError.map(remoteErrorMessage)
            persist()
        }
        return firstRefreshError == nil
    }

    func refreshRemoteProfileVisiblePlaces(profileID: String, backend: WanderBackend?) async {
        guard let backend else {
            return
        }

        do {
            let visiblePlaces = try await backend.userPlaces(for: profileID)
            applyRemoteProfileVisiblePlaces(visiblePlaces, profileID: profileID)
            if profileID != currentUser.id {
                try await refreshRemoteRelationship(to: profileID, backend: backend)
            }
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func refreshRemoteProfileData(profileID: String, backend: WanderBackend?) async {
        guard let backend else { return }
        if profileID == currentUser.id {
            await refreshRemoteCurrentUserProfileData(backend: backend)
            return
        }

        if backend.profileRepository != nil {
            do {
                let state = try await backend.profile(id: profileID)
                upsertRemoteProfileShells([state.shell], preserveExistingProfileMetadataWhenMissing: true)
                applyRemoteRelationship(profileID: profileID, relationship: state.shell.relationship)
            } catch {
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        await refreshRemoteProfileVisiblePlaces(profileID: profileID, backend: backend)
        await refreshRemoteSocialGraph(userID: profileID, backend: backend)
        await refreshRemoteProfileVisits(profileID: profileID, backend: backend)
    }

    func refreshRemoteCurrentUserProfileData(backend: WanderBackend?) async {
        guard let backend else { return }
        let requestUserID = currentUser.id
        _ = await refreshRemoteCurrentUserCalendarData(backend: backend)
        guard currentUser.id == requestUserID, !Task.isCancelled else { return }
        await refreshRemoteSocialGraph(userID: requestUserID, backend: backend)
    }

    @discardableResult
    func refreshRemoteCurrentUserCalendarData(backend: WanderBackend?) async -> Bool {
        guard let backend,
              backend.surfaceSnapshotRepository != nil || backend.userPlaceRepository != nil
        else { return true }
        let requestUserID = currentUser.id
        let taskID: UUID
        let task: Task<Bool, Never>

        if let existingTask = currentUserCalendarRefreshTask,
           existingTask.userID == requestUserID {
            taskID = existingTask.id
            task = existingTask.task
        } else {
            cancelCurrentUserCalendarRefresh()
            taskID = UUID()
            let expectedLocalMutationRevision = currentUserCalendarLocalMutationRevision
            let createdTask = Task { @MainActor [weak self] in
                guard let self else { return false }
                return await self.performCurrentUserCalendarRefresh(
                    userID: requestUserID,
                    expectedLocalMutationRevision: expectedLocalMutationRevision,
                    backend: backend
                )
            }
            currentUserCalendarRefreshTask = (taskID, requestUserID, createdTask)
            isRefreshingCurrentUserCalendarData = true
            task = createdTask
        }

        let refreshed = await task.value
        if currentUserCalendarRefreshTask?.id == taskID {
            currentUserCalendarRefreshTask = nil
            isRefreshingCurrentUserCalendarData = false
            if refreshed {
                currentUserCalendarHydrationRevision &+= 1
            }
        }
        return refreshed
    }

    private struct StagedCurrentUserCalendarData {
        let visiblePlaces: [VisiblePlace]
        let visitsByUserPlaceID: [String: [PlaceVisitResult]]?
    }

    private func performCurrentUserCalendarRefresh(
        userID: String,
        expectedLocalMutationRevision: UInt64,
        backend: WanderBackend
    ) async -> Bool {
        let refreshSignpostID = WanderDebugLog.beginPerformanceInterval("Calendar Refresh Total")
        defer {
            WanderDebugLog.endPerformanceInterval(
                "Calendar Refresh Total",
                id: refreshSignpostID
            )
        }
        do {
            let fetchedPlaces: [VisiblePlace]
            let fetchedVisits: [PlaceVisitResult]?
            if backend.surfaceSnapshotRepository != nil {
                let snapshot = try await backend.currentUserCalendarSnapshot()
                fetchedPlaces = snapshot.visiblePlaces
                fetchedVisits = snapshot.visits
            } else {
                fetchedPlaces = try await backend.userPlaces(for: userID)
                fetchedVisits = nil
            }
            guard currentUser.id == userID,
                  !Task.isCancelled,
                  currentUserCalendarLocalMutationRevision == expectedLocalMutationRevision
            else { return false }
            guard fetchedPlaces.allSatisfy({
                $0.owner.id == userID && $0.userPlace.userID == userID
            }) else {
                throw WanderRemoteError.invalidResponse(
                    "Current-user calendar response contained another owner's place"
                )
            }

            let visiblePlaces = fetchedPlaces.filter { $0.userPlace.deletedAt == nil }
            let userPlaceIDs = visiblePlaces.map(\.userPlace.id)
            guard Set(userPlaceIDs).count == userPlaceIDs.count else {
                throw WanderRemoteError.invalidResponse(
                    "Current-user calendar response contained duplicate user places"
                )
            }

            var visitsByUserPlaceID: [String: [PlaceVisitResult]]?
            if let fetchedVisits {
                var stagedVisits = Dictionary(
                    uniqueKeysWithValues: userPlaceIDs.map { ($0, [PlaceVisitResult]()) }
                )
                let validUserPlaceIDs = Set(userPlaceIDs)
                var seenVisitIDs = Set<String>()
                for visit in fetchedVisits {
                    guard validUserPlaceIDs.contains(visit.userPlaceID) else {
                        throw WanderRemoteError.invalidResponse(
                            "Current-user calendar visit response had the wrong parent"
                        )
                    }
                    guard seenVisitIDs.insert(visit.visitID).inserted else {
                        throw WanderRemoteError.invalidResponse(
                            "Current-user calendar response contained duplicate visits"
                        )
                    }
                    stagedVisits[visit.userPlaceID, default: []].append(visit)
                }
                visitsByUserPlaceID = stagedVisits
            } else if backend.visitRepository != nil {
                var stagedVisits: [String: [PlaceVisitResult]] = [:]
                var seenVisitIDs = Set<String>()
                for userPlaceID in userPlaceIDs.sorted() {
                    let visits = try await backend.visits(for: userPlaceID)
                    guard currentUser.id == userID,
                          !Task.isCancelled,
                          currentUserCalendarLocalMutationRevision == expectedLocalMutationRevision
                    else { return false }
                    guard visits.allSatisfy({ $0.userPlaceID == userPlaceID }) else {
                        throw WanderRemoteError.invalidResponse(
                            "Current-user calendar visit response had the wrong parent"
                        )
                    }
                    let visitIDs = visits.map(\.visitID)
                    guard Set(visitIDs).count == visitIDs.count,
                          seenVisitIDs.isDisjoint(with: visitIDs)
                    else {
                        throw WanderRemoteError.invalidResponse(
                            "Current-user calendar response contained duplicate visits"
                        )
                    }
                    seenVisitIDs.formUnion(visitIDs)
                    stagedVisits[userPlaceID] = visits
                }
                visitsByUserPlaceID = stagedVisits
            }

            guard currentUser.id == userID,
                  !Task.isCancelled,
                  currentUserCalendarLocalMutationRevision == expectedLocalMutationRevision
            else { return false }
            let applySignpostID = WanderDebugLog.beginPerformanceInterval("Calendar Apply")
            applyStagedCurrentUserCalendarData(
                StagedCurrentUserCalendarData(
                    visiblePlaces: visiblePlaces,
                    visitsByUserPlaceID: visitsByUserPlaceID
                ),
                userID: userID
            )
            WanderDebugLog.endPerformanceInterval("Calendar Apply", id: applySignpostID)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard currentUser.id == userID,
                  !Task.isCancelled,
                  currentUserCalendarLocalMutationRevision == expectedLocalMutationRevision
            else { return false }
            lastRemoteError = remoteErrorMessage(error)
            return false
        }
    }

    private func cancelCurrentUserCalendarRefresh() {
        currentUserCalendarRefreshTask?.task.cancel()
        currentUserCalendarRefreshTask = nil
        isRefreshingCurrentUserCalendarData = false
    }

    private func applyStagedCurrentUserCalendarData(
        _ staged: StagedCurrentUserCalendarData,
        userID: String
    ) {
        let previousOwnerPlaces = remoteVisiblePlaceCache.filter {
            $0.owner.id == userID
        }
        let scopedUserPlaceReferenceIDs = (
            userPlaces.filter { $0.userID == userID }.flatMap {
                Self.referenceIDs(for: $0)
            }
            + previousOwnerPlaces.flatMap {
                Self.referenceIDs(for: $0.userPlace)
            }
            + staged.visiblePlaces.flatMap {
                Self.referenceIDs(for: $0.userPlace)
            }
        ).reduce(into: Set<String>()) {
            $0.insert($1)
        }

        withAcceptedCurrentUserCalendarHydration {
            withDeferredPersistence {
                remoteVisiblePlaceCache = remoteVisiblePlaceCache.filter {
                    $0.owner.id != userID
                } + staged.visiblePlaces
                replaceRemoteCurrentUserAttributes(
                    with: staged.visiblePlaces,
                    scopedUserPlaceReferenceIDs: scopedUserPlaceReferenceIDs
                )
                if let visitsByUserPlaceID = staged.visitsByUserPlaceID {
                    reconcileCurrentUserCalendarVisits(
                        visitsByUserPlaceID,
                        scopedUserPlaceReferenceIDs: scopedUserPlaceReferenceIDs
                    )
                }
                authoritativeCalendarUserID = userID
                lastRemoteError = nil
                objectWillChange.send()
                persist()
            }
        }
    }

    private func replaceRemoteCurrentUserAttributes(
        with visiblePlaces: [VisiblePlace],
        scopedUserPlaceReferenceIDs: Set<String>
    ) {
        placeAttributes.removeAll {
            $0.localID.hasPrefix("remote_attr_")
                && scopedUserPlaceReferenceIDs.contains($0.userPlaceID)
        }
        placeAttributes.append(contentsOf: visiblePlaces.flatMap(\.attributes))
    }

    private func reconcileCurrentUserCalendarVisits(
        _ visitsByUserPlaceID: [String: [PlaceVisitResult]],
        scopedUserPlaceReferenceIDs: Set<String>
    ) {
        let remoteVisits = visitsByUserPlaceID
            .keys
            .sorted()
            .flatMap { visitsByUserPlaceID[$0] ?? [] }
        let remoteVisitsByID = Dictionary(
            uniqueKeysWithValues: remoteVisits.map { ($0.visitID, $0) }
        )
        let dirtyVisitReferenceIDs = placeVisits
            .filter {
                scopedUserPlaceReferenceIDs.contains($0.userPlaceID)
                    && $0.syncState != .synced
            }
            .reduce(into: Set<String>()) {
                $0.formUnion(Self.referenceIDs(for: $1))
            }
        var consumedRemoteVisitIDs = Set<String>()
        var reconciledVisits: [LocalPlaceVisit] = []
        reconciledVisits.reserveCapacity(placeVisits.count + remoteVisits.count)

        for visit in placeVisits {
            guard scopedUserPlaceReferenceIDs.contains(visit.userPlaceID),
                  visit.syncState == .synced
            else {
                reconciledVisits.append(visit)
                continue
            }

            let referenceIDs = Self.referenceIDs(for: visit)
            guard let remoteVisitID = referenceIDs.first(where: {
                remoteVisitsByID[$0] != nil
            }),
            !dirtyVisitReferenceIDs.contains(remoteVisitID),
            let result = remoteVisitsByID[remoteVisitID]
            else {
                continue
            }

            applyRemoteVisitResult(result, to: visit)
            consumedRemoteVisitIDs.insert(remoteVisitID)
            reconciledVisits.append(visit)
        }

        for result in remoteVisits
        where !consumedRemoteVisitIDs.contains(result.visitID)
            && !dirtyVisitReferenceIDs.contains(result.visitID) {
            reconciledVisits.append(
                LocalPlaceVisit(
                    localID: "remote_profile_visit_\(result.visitID)",
                    serverID: result.visitID,
                    userPlaceID: result.userPlaceID,
                    visitedAt: result.visitedAt,
                    note: result.note,
                    ratingScore: result.ratingScore,
                    tags: result.tags,
                    backfilledFromUserPlace: result.backfilledFromUserPlace,
                    syncState: .synced
                )
            )
        }

        placeVisits = reconciledVisits
    }

    private func applyRemoteVisitResult(
        _ result: PlaceVisitResult,
        to visit: LocalPlaceVisit
    ) {
        let now = Date.now
        visit.serverID = result.visitID
        visit.userPlaceID = result.userPlaceID
        visit.visitedAt = result.visitedAt
        visit.note = result.note
        visit.ratingScore = PlaceRating.normalized(result.ratingScore)
        visit.setDerivedTags(result.tags)
        visit.backfilledFromUserPlace = result.backfilledFromUserPlace
        visit.syncStateRaw = SyncState.synced.rawValue
        visit.localUpdatedAt = now
        visit.serverUpdatedAt = now
        visit.lastSyncError = nil
        visit.updatedAt = now
        visit.deletedAt = nil
    }

    @discardableResult
    private func refreshRemoteProfileVisits(profileID: String, backend: WanderBackend) async -> Bool {
        guard backend.visitRepository != nil else { return true }

        let remoteUserPlaces = remoteVisiblePlaceCache
            .filter { $0.owner.id == profileID && $0.userPlace.deletedAt == nil }
        let remoteUserPlaceIDs = Set(remoteUserPlaces.map(\.userPlace.id))
        guard !remoteUserPlaceIDs.isEmpty else { return true }

        var hydrated: [LocalPlaceVisit] = []
        var refreshedUserPlaceIDs: Set<String> = []
        var firstError: Error?
        for userPlaceID in remoteUserPlaceIDs.sorted() {
            do {
                let results = try await backend.visits(for: userPlaceID)
                refreshedUserPlaceIDs.insert(userPlaceID)
                hydrated.append(contentsOf: results.map { result in
                    LocalPlaceVisit(
                        localID: "remote_profile_visit_\(result.visitID)",
                        serverID: result.visitID,
                        userPlaceID: result.userPlaceID,
                        visitedAt: result.visitedAt,
                        note: result.note,
                        ratingScore: result.ratingScore,
                        tags: result.tags,
                        backfilledFromUserPlace: result.backfilledFromUserPlace,
                        syncState: .synced
                    )
                })
            } catch {
                firstError = firstError ?? error
            }
        }

        let hydratedIDs = Set(hydrated.map(\.id))
        placeVisits.removeAll { visit in
            Self.isSyntheticRemoteProfileVisit(visit)
                && visit.syncState == .synced
                && refreshedUserPlaceIDs.contains(visit.userPlaceID)
                && !hydratedIDs.contains(visit.id)
        }
        for remoteVisit in hydrated where !placeVisits.contains(where: { $0.id == remoteVisit.id }) {
            placeVisits.append(remoteVisit)
        }
        objectWillChange.send()
        persist()
        if let firstError {
            lastRemoteError = remoteErrorMessage(firstError)
            return false
        }
        lastRemoteError = nil
        return true
    }

    func refreshRemoteSocialGraph(userID: String? = nil, backend: WanderBackend?) async {
        guard let backend else {
            return
        }

        let graphUserID = userID ?? currentUser.id

        do {
            let following = try await backend.following(userID: graphUserID)
            let followers = try await backend.followers(userID: graphUserID)
            upsertRemoteSocialGraph(userID: graphUserID, following: following, followers: followers)
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    private func refreshRemoteRelationship(to profileID: String, backend: WanderBackend) async throws {
        let relationship = try await backend.relationship(to: profileID)
        applyRemoteRelationship(profileID: profileID, relationship: relationship)
    }

    func blockedProfiles() -> [ProfileShell] {
        blocks
            .filter { $0.blockerUserID == currentUser.id }
            .map { block in
                guard let profile = profiles.first(where: { $0.id == block.blockedUserID }) else {
                    return fallbackBlockedProfileShell(for: block.blockedUserID)
                }
                return shell(for: profile)
            }
    }

    func refreshRemoteBlocks(backend: WanderBackend?) async {
        guard let backend, backend.blockRepository != nil else { return }
        do {
            let shells = try await backend.blockedProfiles()
            let blockedIDs = Set(shells.map(\.id))
            for shell in shells {
                preserveBlockedProfileShell(shell)
            }
            blocks.removeAll {
                $0.blockerUserID == currentUser.id && !blockedIDs.contains($0.blockedUserID)
            }
            for profileID in blockedIDs where !blocks.contains(where: {
                $0.blockerUserID == currentUser.id && $0.blockedUserID == profileID
            }) {
                blocks.append(
                    LocalBlock(
                        localID: "remote_block_\(currentUser.id)_\(profileID)",
                        blockerUserID: currentUser.id,
                        blockedUserID: profileID,
                        syncState: .synced
                    )
                )
            }
            lastRemoteError = nil
            objectWillChange.send()
            persist()
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func isMuted(userID: String) -> Bool {
        mutes.contains {
            $0.muterUserID == currentUser.id
                && $0.mutedUserID == userID
                && $0.syncState != .pendingDelete
        }
    }

    func mutedProfiles() -> [ProfileShell] {
        mutes
            .filter { $0.muterUserID == currentUser.id && $0.syncState != .pendingDelete }
            .map { mute in
                profiles.first(where: { $0.id == mute.mutedUserID }).map(shell(for:))
                    ?? ProfileShell(
                        id: mute.mutedUserID,
                        handle: "muted-user",
                        displayName: "Muted user",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .nonFollower
                    )
            }
    }

    func mute(userID: String, backend: WanderBackend?) async {
        guard userID != currentUser.id, !isMuted(userID: userID) else { return }
        let mute = LocalMute(
            localID: "local_mute_\(currentUser.id)_\(userID)",
            muterUserID: currentUser.id,
            mutedUserID: userID,
            syncState: backend?.muteRepository == nil ? .localOnly : .pendingCreate
        )
        mutes.append(mute)
        objectWillChange.send()
        persist()

        guard let backend, backend.muteRepository != nil else { return }
        do {
            try await backend.mute(userID: userID)
            mute.syncStateRaw = SyncState.synced.rawValue
            mute.localUpdatedAt = .now
            mute.lastSyncError = nil
            lastRemoteError = nil
        } catch {
            mute.syncStateRaw = SyncState.failed.rawValue
            mute.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = mute.lastSyncError
        }
        objectWillChange.send()
        persist()
    }

    func unmute(userID: String, backend: WanderBackend?) async {
        guard let mute = mutes.first(where: { $0.muterUserID == currentUser.id && $0.mutedUserID == userID }) else {
            return
        }
        let previousState = mute.syncState
        mute.syncStateRaw = SyncState.pendingDelete.rawValue
        mute.localUpdatedAt = .now
        objectWillChange.send()
        persist()

        guard let backend, backend.muteRepository != nil else {
            mutes.removeAll { $0.id == mute.id }
            persist()
            return
        }
        do {
            try await backend.unmute(userID: userID)
            mutes.removeAll { $0.id == mute.id }
            lastRemoteError = nil
        } catch {
            mute.syncStateRaw = (previousState == .localOnly ? SyncState.localOnly : SyncState.failed).rawValue
            mute.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = mute.lastSyncError
        }
        objectWillChange.send()
        persist()
    }

    func refreshRemoteMutes(backend: WanderBackend?) async {
        guard let backend, backend.muteRepository != nil else { return }
        do {
            let shells = try await backend.mutedProfiles()
            upsertRemoteProfileShells(shells, preserveExistingProfileMetadataWhenMissing: true)
            let mutedIDs = Set(shells.map(\.id))
            mutes.removeAll {
                $0.muterUserID == currentUser.id && !mutedIDs.contains($0.mutedUserID)
            }
            for profileID in mutedIDs where !isMuted(userID: profileID) {
                mutes.append(
                    LocalMute(
                        localID: "remote_mute_\(currentUser.id)_\(profileID)",
                        muterUserID: currentUser.id,
                        mutedUserID: profileID,
                        syncState: .synced
                    )
                )
            }
            lastRemoteError = nil
            objectWillChange.send()
            persist()
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func authGate(for action: AddSourceType) -> AuthGateCopy {
        switch action {
        case .socialSave:
            AuthGateCopy(title: "Sign in to save from people", message: "Social saves sync to your map after you have an account.", primaryAction: "Sign in", secondaryAction: "Keep browsing")
        default:
            AuthGateCopy(title: "Sign in to sync this place", message: "Keep it on this phone for now, or sign in to back it up.", primaryAction: "Sign in", secondaryAction: "Keep it on this phone")
        }
    }

    private func isBlockedBetweenCurrentUser(and userID: String) -> Bool {
        isBlockedBetween(currentUser.id, and: userID)
    }

    private func isBlockedBetween(_ firstUserID: String, and secondUserID: String) -> Bool {
        blocks.contains { block in
            (block.blockerUserID == firstUserID && block.blockedUserID == secondUserID)
                || (block.blockerUserID == secondUserID && block.blockedUserID == firstUserID)
        }
    }

    private func canReadGraph(for userID: String) -> Bool {
        userID == currentUser.id || !isBlockedBetweenCurrentUser(and: userID)
    }

    private func canShowGraphProfile(_ profileID: String, for graphOwnerID: String) -> Bool {
        !isBlockedBetweenCurrentUser(and: profileID)
            && !isBlockedBetween(graphOwnerID, and: profileID)
    }

    private func isProfilePrivate(_ userID: String) -> Bool {
        profiles.first { $0.id == userID }?.isPrivateProfile == true
    }

    private func fallbackBlockedProfileShell(for userID: String) -> ProfileShell {
        let handle = slug(userID)
        return ProfileShell(
            id: userID,
            handle: handle.isEmpty ? "blocked-user" : handle,
            displayName: "Blocked user",
            avatarURL: nil,
            bio: nil,
            relationship: .nonFollower
        )
    }

    private func preserveBlockedProfileShell(_ shell: ProfileShell) {
        guard shell.id != currentUser.id else { return }

        if let existing = profiles.first(where: { $0.id == shell.id || $0.handle == shell.handle }) {
            existing.serverID = shell.id
            existing.handle = shell.handle
            existing.searchHandle = shell.handle.lowercased()
            existing.displayName = shell.displayName
            existing.avatarURL = shell.avatarURL
            existing.bio = shell.bio
            existing.syncStateRaw = SyncState.synced.rawValue
            existing.updatedAt = .now
        } else {
            profiles.append(
                LocalProfile(
                    localID: "blocked_profile_\(slug(shell.id))",
                    serverID: shell.id,
                    handle: shell.handle,
                    displayName: shell.displayName,
                    avatarURL: shell.avatarURL,
                    bio: shell.bio,
                    syncState: .synced
                )
            )
        }

        objectWillChange.send()
        persist()
    }

    private func visibilityForSave(_ visibility: PlaceVisibility) -> PlaceVisibility {
        isPrivateProfile ? .selfOnly : visibility
    }

    private func makeCurrentUserContentPrivate() {
        var didUpdate = false

        for userPlace in userPlaces where userPlace.userID == currentUser.id && userPlace.deletedAt == nil && userPlace.visibility != .selfOnly {
            userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
            userPlace.updatedAt = .now
            userPlace.localUpdatedAt = .now
            userPlace.syncStateRaw = userPlace.syncState == .synced ? SyncState.pendingUpdate.rawValue : userPlace.syncStateRaw
            didUpdate = true
        }

        if didUpdate {
            objectWillChange.send()
            persist()
        }
    }

    private func apply(session: AuthSession) {
        let previousCurrentUser = currentUser
        guard previousCurrentUser.id != session.userID else { return }

        if let previousUserID = previousCurrentUser.serverID, previousUserID != session.userID {
            providerCategoryEnrichmentAttemptedAtByKey = [:]
            cancelSharedVisitInboxTask()
            sharedVisitInvitations = []
            sharedVisitInboxUserID = nil
            sharedVisitCompanionsByVisitID = [:]
        } else if sharedVisitInboxUserID != nil, sharedVisitInboxUserID != session.userID {
            cancelSharedVisitInboxTask()
            sharedVisitInvitations = []
            sharedVisitInboxUserID = nil
            sharedVisitCompanionsByVisitID = [:]
        }
        let sessionHandle = normalizedSessionHandle(from: session)
        let handle = sessionHandle
        let displayName = normalizedSessionDisplayName(from: session, fallbackHandle: sessionHandle)
        let localID = "local_profile_current"
        let preferredVisibility = PlaceVisibility.selfOnly
        let preferredPrivateProfile = true
        let profile = LocalProfile(
            localID: localID,
            serverID: session.userID,
            handle: handle,
            displayName: displayName,
            avatarURL: nil,
            bio: nil,
            homeArea: nil,
            onboardingCompletedAt: nil,
            isPrivateProfile: preferredPrivateProfile,
            syncState: .synced,
            createdAt: .now
        )
        profile.defaultVisibilityRaw = preferredVisibility.rawValue

        withDeferredPersistence {
            currentUser = profile
            profiles.removeAll { $0.localID == localID || $0.serverID == session.userID }
            profiles.insert(profile, at: 0)
            defaultVisibility = preferredVisibility
            isPrivateProfile = preferredPrivateProfile
            defaultMapFilter = .featured
            claimGuestRowsIfNeeded(from: previousCurrentUser, to: profile)
            persist()
        }
    }

    private func claimGuestRowsIfNeeded(from previousProfile: LocalProfile, to signedInProfile: LocalProfile) {
        guard previousProfile.localID == "local_profile_current",
              previousProfile.serverID == nil,
              previousProfile.id != signedInProfile.id
        else { return }

        let previousUserID = previousProfile.id
        var didClaimRows = false

        for userPlace in userPlaces where userPlace.userID == previousUserID && userPlace.deletedAt == nil {
            userPlace.userID = signedInProfile.id
            userPlace.updatedAt = .now
            userPlace.localUpdatedAt = .now
            didClaimRows = true
        }

        for index in placeLists.indices where placeLists[index].ownerUserID == previousUserID && placeLists[index].deletedAt == nil {
            placeLists[index].ownerUserID = signedInProfile.id
            placeLists[index].updatedAt = .now
            if placeLists[index].serverID == nil && placeLists[index].syncState == .localOnly {
                placeLists[index].syncStateRaw = SyncState.pendingCreate.rawValue
            }
            didClaimRows = true
        }

        for index in placeListMembers.indices where placeListMembers[index].userID == previousUserID && placeListMembers[index].deletedAt == nil {
            placeListMembers[index].userID = signedInProfile.id
            didClaimRows = true
        }

        for index in placeListItems.indices where placeListItems[index].addedByUserID == previousUserID && placeListItems[index].deletedAt == nil {
            placeListItems[index].addedByUserID = signedInProfile.id
            placeListItems[index].updatedAt = .now
            didClaimRows = true
        }

        if let guestStreakDates = saveStreakDatesByUserID.removeValue(forKey: previousUserID),
           !guestStreakDates.isEmpty {
            saveStreakDatesByUserID[signedInProfile.id, default: []].append(contentsOf: guestStreakDates)
            didClaimRows = true
        }
        if let guestRecoveryDates = saveStreakRecoveryDatesByUserID.removeValue(forKey: previousUserID),
           !guestRecoveryDates.isEmpty {
            saveStreakRecoveryDatesByUserID[signedInProfile.id, default: []].append(contentsOf: guestRecoveryDates)
            didClaimRows = true
        }

        guard didClaimRows else { return }
        objectWillChange.send()
        persist()
    }

    private func applySignedOutProfile() {
        let localID = "local_profile_current"
        let preferredPrivateProfile = false
        cancelSharedVisitInboxTask()
        sharedVisitInvitations = []
        sharedVisitInboxUserID = nil
        sharedVisitCompanionsByVisitID = [:]
        let profile = LocalProfile(
            localID: localID,
            handle: "you",
            displayName: "You",
            avatarURL: nil,
            bio: nil,
            homeArea: nil,
            onboardingCompletedAt: nil,
            isPrivateProfile: preferredPrivateProfile,
            syncState: .localOnly,
            createdAt: .now
        )
        profile.defaultVisibilityRaw = PlaceVisibility.followers.rawValue

        withDeferredPersistence {
            currentUser = profile
            profiles.removeAll { $0.localID == localID }
            profiles.insert(profile, at: 0)
            defaultVisibility = .followers
            isPrivateProfile = false
            defaultMapFilter = .featured
            persist()
        }
    }

    private func cancelSharedVisitInboxTask() {
        sharedVisitInboxTask?.task.cancel()
        sharedVisitInboxTask = nil
    }

    private func cancelVisitPhotoUploadTask() {
        visitPhotoUploadTask?.task.cancel()
        visitPhotoUploadTask = nil
    }

    private func normalizedSessionHandle(from session: AuthSession) -> String {
        if let handle = session.handle.map(slug), !handle.isEmpty {
            return handle
        }

        if let emailLocalPart = session.email?.split(separator: "@").first.map(String.init),
           !slug(emailLocalPart).isEmpty {
            return slug(emailLocalPart)
        }

        let fallback = slug(session.userID)
        return fallback.isEmpty ? "you" : fallback
    }

    private func normalizedSessionDisplayName(from session: AuthSession, fallbackHandle: String) -> String {
        if let displayName = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        if let email = session.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }

        return fallbackHandle
    }

    private func upsertFollow(userID: String, source: FollowSource) -> LocalFollow? {
        guard userID != currentUser.id,
              !isBlockedBetweenCurrentUser(and: userID)
        else { return nil }

        if let existing = follows.first(where: { $0.followerUserID == currentUser.id && $0.followedUserID == userID }) {
            return existing
        }

        let follow = LocalFollow(
            localID: "local_follow_\(currentUser.id)_\(userID)",
            followerUserID: currentUser.id,
            followedUserID: userID,
            source: source,
            syncState: .pendingCreate
        )
        follows.append(follow)
        return follow
    }

    private func upsertBlock(userID: String) -> LocalBlock? {
        guard userID != currentUser.id else { return nil }

        follows.removeAll { follow in
            (follow.followerUserID == currentUser.id && follow.followedUserID == userID)
                || (follow.followerUserID == userID && follow.followedUserID == currentUser.id)
        }

        if let existing = blocks.first(where: { $0.blockerUserID == currentUser.id && $0.blockedUserID == userID }) {
            return existing
        }

        let block = LocalBlock(
            localID: "local_block_\(currentUser.id)_\(userID)",
            blockerUserID: currentUser.id,
            blockedUserID: userID,
            syncState: .pendingCreate
        )
        blocks.append(block)
        return block
    }

    private func userPlaceDraft(for userPlaceID: String) -> UserPlaceDraft? {
        guard let userPlace = userPlaces.first(where: { $0.id == userPlaceID || $0.localID == userPlaceID || $0.serverID == userPlaceID }),
              let place = places.first(where: { $0.id == userPlace.placeID || $0.localID == userPlace.placeID || $0.serverID == userPlace.placeID })
        else {
            return nil
        }

        let placeDraft = PlaceDraft(
            localID: place.localID,
            serverID: place.serverID,
            canonicalName: place.canonicalName,
            category: place.category,
            primaryCategory: place.primaryCategory,
            subcategory: place.subcategory,
            categorySource: place.categorySource,
            categoryConfidence: place.categoryConfidence,
            rawProviderType: place.rawProviderType,
            address: place.address,
            locality: place.locality,
            region: place.region,
            country: place.country,
            latitude: place.latitude,
            longitude: place.longitude,
            sourceProvider: place.sourceProvider,
            sourceProviderPlaceID: place.sourceProviderPlaceID,
            confidence: place.confidence,
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            timeZoneIdentifier: place.timeZoneIdentifier,
            actionLinksJSON: place.actionLinksJSON
        )

        let attributeDrafts = attributes(for: userPlace.id).map { attribute in
            PlaceAttributeDraft(
                questionKey: attribute.questionKey,
                valueType: attribute.valueType,
                valueJSON: attribute.valueJSON
            )
        }

        return UserPlaceDraft(
            place: placeDraft,
            status: userPlace.status,
            visibility: userPlace.visibility,
            note: userPlace.note,
            ratingSignal: userPlace.ratingSignal,
            ratingScore: userPlace.ratingScore,
            categoryOverride: userPlace.categoryOverride,
            subcategoryOverride: userPlace.subcategoryOverride,
            categoryOverrideSource: userPlace.categoryOverrideSource,
            categoryOverrideConfidence: userPlace.categoryOverrideConfidence,
            nearbyConfirmed: userPlace.nearbyConfirmed,
            plannedDate: userPlace.plannedDate,
            sourceType: userPlace.sourceType,
            attributes: attributeDrafts
        )
    }

    private func checkInDraft(
        for visitID: String,
        userPlace: LocalUserPlace
    ) -> CheckInSaveDraft? {
        guard let parentDraft = userPlaceDraft(for: userPlace.id),
              let visitDraft = visitDraft(
                  for: visitID,
                  remoteUserPlaceID: userPlace.serverID ?? userPlace.id
              )
        else {
            return nil
        }

        let historicalWant = userPlace.historicalWantedAt.map { wantedAt in
            HistoricalWantSnapshotDraft(
                note: userPlace.historicalWantNote,
                attributeAnswersJSON: userPlace.historicalWantAttributeAnswersJSON ?? "[]",
                tags: userPlace.historicalWantTags,
                wantedAt: wantedAt
            )
        }
        return CheckInSaveDraft(
            userPlace: parentDraft,
            visit: visitDraft,
            historicalWant: historicalWant
        )
    }

    private func checkInDateBucket(_ date: Date, now: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0)
        switch days {
        case 0:
            return "today"
        case 1...7:
            return "last_7_days"
        case 8...30:
            return "last_30_days"
        default:
            return "older"
        }
    }

    private func matchingUserPlaceIDs(_ userPlaceID: String) -> Set<String> {
        guard let userPlace = userPlaces.first(where: { $0.id == userPlaceID || $0.localID == userPlaceID || $0.serverID == userPlaceID }) else {
            return [userPlaceID]
        }

        var ids: Set<String> = [userPlaceID, userPlace.id, userPlace.localID]
        if let serverID = userPlace.serverID {
            ids.insert(serverID)
        }
        return ids
    }

    private func matchingVisitIDs(_ visitID: String) -> Set<String> {
        guard let visit = placeVisits.first(where: { $0.id == visitID || $0.localID == visitID || $0.serverID == visitID }) else {
            return [visitID]
        }

        var ids: Set<String> = [visitID, visit.id, visit.localID]
        if let serverID = visit.serverID {
            ids.insert(serverID)
        }
        return ids
    }

    private func currentUserPlace(matching userPlaceID: String) -> LocalUserPlace? {
        userPlaces.first { userPlace in
            userPlace.userID == currentUser.id
                && userPlace.deletedAt == nil
                && (userPlace.id == userPlaceID
                    || userPlace.localID == userPlaceID
                    || userPlace.serverID == userPlaceID)
        }
    }

    private func currentUserPlace(for place: LocalPlace) -> LocalUserPlace? {
        userPlaces.first { userPlace in
            userPlace.userID == currentUser.id
                && userPlace.deletedAt == nil
                && (userPlace.placeID == place.id
                    || userPlace.placeID == place.localID
                    || userPlace.placeID == place.serverID)
        }
    }

    private func currentUserVisit(matching visitID: String) -> LocalPlaceVisit? {
        guard let visit = placeVisits.first(where: { visit in
            visit.deletedAt == nil
                && (visit.id == visitID || visit.localID == visitID || visit.serverID == visitID)
        }) else {
            return nil
        }

        let isOwnedLocally = currentUserPlace(matching: visit.userPlaceID) != nil
        let isOwnedRemotely = remoteCurrentUserVisiblePlace(
            matching: visit.userPlaceID
        ) != nil
        return isOwnedLocally || isOwnedRemotely ? visit : nil
    }

    private func remoteCurrentUserVisiblePlace(
        matching userPlaceID: String
    ) -> VisiblePlace? {
        remoteVisiblePlaceCache.first { visiblePlace in
            visiblePlace.owner.id == currentUser.id
                && visiblePlace.userPlace.userID == currentUser.id
                && visiblePlace.userPlace.deletedAt == nil
                && Self.referenceIDs(for: visiblePlace.userPlace)
                    .contains(userPlaceID)
        }
    }

    private func materializeRemoteCurrentUserPlace(
        _ visiblePlace: VisiblePlace
    ) -> LocalUserPlace {
        let remoteReferenceIDs = Self.referenceIDs(for: visiblePlace.userPlace)
        if let existing = userPlaces.first(where: {
            $0.userID == currentUser.id
                && !Self.referenceIDs(for: $0).isDisjoint(with: remoteReferenceIDs)
        }) {
            return existing
        }

        if !places.contains(where: {
            $0.id == visiblePlace.place.id
                || $0.localID == visiblePlace.place.localID
                || ($0.serverID != nil && $0.serverID == visiblePlace.place.serverID)
        }) {
            places.append(visiblePlace.place)
        }
        userPlaces.append(visiblePlace.userPlace)
        return visiblePlace.userPlace
    }

    private func currentUserPhoto(matching photoID: String) -> LocalVisitPhoto? {
        guard let photo = visitPhotos.first(where: { photo in
            photo.deletedAt == nil
                && (photo.id == photoID || photo.localID == photoID || photo.serverID == photoID)
        }) else {
            return nil
        }

        return currentUserVisit(matching: photo.visitID) == nil ? nil : photo
    }

    private func attributeDrafts(for userPlaceID: String) -> [PlaceAttributeDraft] {
        attributes(for: userPlaceID).map {
            PlaceAttributeDraft(
                questionKey: $0.questionKey,
                valueType: $0.valueType,
                valueJSON: $0.valueJSON
            )
        }
    }

    private func preserveHistoricalWant(for userPlace: LocalUserPlace, attributes: [PlaceAttributeDraft]) {
        preserveHistoricalWant(
            for: userPlace,
            note: userPlace.note,
            attributes: attributes,
            wantedAt: userPlace.historicalWantedAt ?? userPlace.savedAt
        )
    }

    private func preserveHistoricalWant(
        for userPlace: LocalUserPlace,
        note: String?,
        attributes: [PlaceAttributeDraft],
        wantedAt: Date
    ) {
        userPlace.historicalWantNote = note
        userPlace.historicalWantAttributeAnswersJSON = VisitAttributeAnswers.encoded(from: attributes)
        userPlace.setHistoricalWantTags(VisitAttributeAnswers.tags(from: attributes))
        userPlace.historicalWantedAt = wantedAt
    }

    private func backfillMissingLegacyVisits(using index: inout VisitReconciliationIndex) {
        for userPlace in userPlaces where userPlace.userID == currentUser.id && userPlace.deletedAt == nil {
            let matchingVisits = index.visits(for: userPlace)
            if userPlace.status == .been, !matchingVisits.contains(where: { $0.deletedAt == nil }) {
                let previousVisitCount = placeVisits.count
                syncBackfilledVisit(
                    for: userPlace,
                    attributes: index.attributeDrafts(for: userPlace),
                    matchingVisits: matchingVisits
                )
                if placeVisits.count > previousVisitCount, let appendedVisit = placeVisits.last {
                    index.append(appendedVisit)
                }
            } else if userPlace.status != .been {
                let now = Date.now
                for visit in matchingVisits where visit.backfilledFromUserPlace && visit.deletedAt == nil {
                    softDelete(visit, at: now)
                }
            }
        }
    }

    private func syncBackfilledVisit(
        for userPlace: LocalUserPlace,
        attributes: [PlaceAttributeDraft]? = nil,
        matchingVisits: [LocalPlaceVisit]? = nil
    ) {
        let now = Date.now
        guard userPlace.deletedAt == nil, userPlace.status == .been else {
            softDeleteBackfilledVisits(for: userPlace.id, at: now)
            return
        }

        let candidateVisits: [LocalPlaceVisit]
        if let matchingVisits {
            candidateVisits = matchingVisits
        } else {
            let userPlaceIDs = matchingUserPlaceIDs(userPlace.id)
            candidateVisits = placeVisits.filter { userPlaceIDs.contains($0.userPlaceID) }
        }
        let hasExplicitVisit = candidateVisits.contains { visit in
            !visit.backfilledFromUserPlace && visit.deletedAt == nil
        }
        if hasExplicitVisit {
            return
        }

        let drafts = attributes ?? attributeDrafts(for: userPlace.id)
        let attributeAnswersJSON = VisitAttributeAnswers.encoded(from: drafts)
        let tags = VisitAttributeAnswers.tags(from: drafts)

        if let existing = candidateVisits.first(where: { $0.backfilledFromUserPlace }) {
            existing.userPlaceID = userPlace.id
            existing.visitedAt = userPlace.visitedAt ?? userPlace.savedAt
            existing.note = userPlace.note
            existing.ratingScore = userPlace.ratingScore
            existing.attributeAnswersJSON = attributeAnswersJSON
            existing.setDerivedTags(tags)
            existing.deletedAt = nil
            existing.updatedAt = now
            existing.localUpdatedAt = now
            existing.syncStateRaw = userPlace.syncStateRaw
            existing.lastSyncError = userPlace.lastSyncError
            existing.serverUpdatedAt = userPlace.serverUpdatedAt
            return
        }

        placeVisits.append(
            LocalPlaceVisit(
                localID: "local_visit_backfill_\(slug(userPlace.localID))",
                userPlaceID: userPlace.id,
                visitedAt: userPlace.visitedAt ?? userPlace.savedAt,
                note: userPlace.note,
                ratingScore: userPlace.ratingScore,
                attributeAnswersJSON: attributeAnswersJSON,
                tags: tags,
                backfilledFromUserPlace: true,
                syncState: userPlace.syncState,
                localUpdatedAt: userPlace.localUpdatedAt,
                serverUpdatedAt: userPlace.serverUpdatedAt,
                lastSyncError: userPlace.lastSyncError,
                createdAt: userPlace.createdAt,
                updatedAt: userPlace.updatedAt
            )
        )
    }

    private func refreshAllVisitDerivedState(using index: VisitReconciliationIndex) {
        for visit in placeVisits {
            visit.setDerivedTags(VisitAttributeAnswers.tags(fromAttributeAnswersJSON: visit.attributeAnswersJSON))
        }
        for userPlace in userPlaces where userPlace.userID == currentUser.id {
            updateVisitSummary(for: userPlace, activeVisits: index.activeVisits(for: userPlace))
        }
    }

    private func refreshUserPlaceVisitSummary(userPlaceID: String) {
        guard let userPlace = userPlaces.first(where: { userPlace in
            userPlace.id == userPlaceID || userPlace.localID == userPlaceID || userPlace.serverID == userPlaceID
        }) else {
            return
        }

        updateVisitSummary(for: userPlace, activeVisits: visits(for: userPlace.id))
    }

    private func updateVisitSummary(for userPlace: LocalUserPlace, activeVisits: [LocalPlaceVisit]) {
        guard userPlace.deletedAt == nil, userPlace.status == .been else {
            userPlace.ratingScore = nil
            userPlace.recommendedScore = nil
            userPlace.recommendedCount = 0
            return
        }

        let ratings = activeVisits.compactMap { PlaceRating.normalized($0.ratingScore) }
        if ratings.isEmpty {
            userPlace.ratingScore = nil
            userPlace.recommendedScore = nil
            userPlace.recommendedCount = 0
        } else {
            let average = ratings.reduce(0, +) / Double(ratings.count)
            let roundedAverage = (average * 10).rounded() / 10
            userPlace.ratingScore = roundedAverage
            userPlace.recommendedScore = roundedAverage
            userPlace.recommendedCount = ratings.count
        }

        if let latestVisitedAt = activeVisits.map(\.visitedAt).max() {
            userPlace.visitedAt = latestVisitedAt
        }
    }

    private func softDeleteBackfilledVisits(for userPlaceID: String, at date: Date) {
        let userPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        for visit in placeVisits where visit.backfilledFromUserPlace && userPlaceIDs.contains(visit.userPlaceID) && visit.deletedAt == nil {
            softDelete(visit, at: date)
        }
    }

    private func softDeleteVisits(for userPlaceID: String, at date: Date) {
        let userPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        for visit in placeVisits where userPlaceIDs.contains(visit.userPlaceID) && visit.deletedAt == nil {
            let visitIDs = matchingVisitIDs(visit.id)
            for photo in visitPhotos where visitIDs.contains(photo.visitID) && photo.deletedAt == nil {
                softDelete(photo, at: date)
            }
            softDelete(visit, at: date)
        }
    }

    private func softDelete(_ visit: LocalPlaceVisit, at date: Date) {
        visit.deletedAt = date
        visit.updatedAt = date
        visit.localUpdatedAt = date
        visit.lastSyncError = nil
        visit.syncStateRaw = visit.serverID == nil ? SyncState.tombstoned.rawValue : SyncState.pendingDelete.rawValue
    }

    private func softDelete(_ photo: LocalVisitPhoto, at date: Date) {
        photo.deletedAt = date
        photo.updatedAt = date
        photo.localUpdatedAt = date
        photo.lastSyncError = nil
        photo.uploadStateRaw = VisitPhotoUploadState.failed.rawValue
        photo.syncStateRaw = photo.serverID == nil ? SyncState.tombstoned.rawValue : SyncState.pendingDelete.rawValue
    }

    private func restoreHistoricalWantAfterLastVisit(_ userPlace: LocalUserPlace, at date: Date) -> Bool {
        guard let wantedAt = userPlace.historicalWantedAt else { return false }

        let drafts = VisitAttributeAnswers.drafts(
            fromAttributeAnswersJSON: userPlace.historicalWantAttributeAnswersJSON ?? "[]"
        )
        userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        userPlace.note = userPlace.historicalWantNote
        userPlace.ratingSignal = ratingSignal(from: drafts)
        userPlace.ratingScore = nil
        userPlace.recommendedScore = nil
        userPlace.recommendedCount = 0
        userPlace.visitedAt = nil
        userPlace.plannedDate = nil
        userPlace.savedAt = wantedAt
        userPlace.deletedAt = nil
        userPlace.updatedAt = date
        userPlace.localUpdatedAt = date
        userPlace.lastSyncError = nil
        userPlace.syncStateRaw = userPlace.serverID == nil ? SyncState.pendingCreate.rawValue : SyncState.pendingUpdate.rawValue
        replaceAttributes(for: userPlace.id, with: drafts, syncState: userPlace.syncState)
        return true
    }

    private func deleteUserPlaceAfterLastVisit(_ userPlace: LocalUserPlace, at date: Date) {
        userPlace.note = nil
        userPlace.ratingSignal = nil
        userPlace.ratingScore = nil
        userPlace.recommendedScore = nil
        userPlace.recommendedCount = 0
        userPlace.categoryOverride = nil
        userPlace.subcategoryOverride = nil
        userPlace.categoryOverrideSource = nil
        userPlace.categoryOverrideConfidence = nil
        userPlace.plannedDate = nil
        userPlace.deletedAt = date
        userPlace.updatedAt = date
        userPlace.localUpdatedAt = date
        userPlace.lastSyncError = nil
        userPlace.syncStateRaw = userPlace.serverID == nil ? SyncState.tombstoned.rawValue : SyncState.pendingDelete.rawValue
        placeAttributes.removeAll { matchingUserPlaceIDs(userPlace.id).contains($0.userPlaceID) }
    }

    private func matchingPlaceIDs(_ placeID: String) -> Set<String> {
        guard let place = places.first(where: { $0.id == placeID || $0.localID == placeID || $0.serverID == placeID }) else {
            return [placeID]
        }

        var ids: Set<String> = [placeID, place.id, place.localID]
        if let serverID = place.serverID {
            ids.insert(serverID)
        }
        return ids
    }

    private func markUserPlace(localOrServerID: String, serverID: String? = nil, syncState: SyncState, error: String? = nil) {
        guard let userPlace = userPlaces.first(where: { $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID }) else {
            return
        }

        let previousIDs = matchingUserPlaceIDs(localOrServerID)
        if let serverID {
            userPlace.serverID = serverID
        }
        userPlace.syncStateRaw = syncState.rawValue
        userPlace.lastSyncError = error
        userPlace.serverUpdatedAt = syncState == .synced ? .now : userPlace.serverUpdatedAt

        let canonicalUserPlaceID = serverID ?? userPlace.id
        for attribute in placeAttributes where previousIDs.contains(attribute.userPlaceID) {
            attribute.userPlaceID = canonicalUserPlaceID
            attribute.syncStateRaw = syncState.rawValue
            attribute.lastSyncError = error
            attribute.serverUpdatedAt = syncState == .synced ? .now : attribute.serverUpdatedAt
        }
        for visit in placeVisits where previousIDs.contains(visit.userPlaceID) {
            visit.userPlaceID = canonicalUserPlaceID
            if visit.backfilledFromUserPlace {
                visit.syncStateRaw = syncState.rawValue
                visit.lastSyncError = error
                visit.serverUpdatedAt = syncState == .synced ? .now : visit.serverUpdatedAt
            }
        }
        objectWillChange.send()
        persist()
    }

    private func markPlaceVisit(
        localOrServerID: String,
        serverID: String? = nil,
        syncState: SyncState,
        error: String? = nil,
        result: PlaceVisitResult? = nil
    ) {
        guard let visit = placeVisits.first(where: { $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID }) else {
            return
        }

        let previousIDs = matchingVisitIDs(localOrServerID)
        if let serverID {
            visit.serverID = serverID
        }
        if let result {
            visit.serverID = result.visitID
            visit.userPlaceID = result.userPlaceID
            visit.visitedAt = result.visitedAt
            visit.note = result.note
            visit.ratingScore = result.ratingScore
            visit.setDerivedTags(result.tags)
            visit.backfilledFromUserPlace = result.backfilledFromUserPlace
        }
        visit.syncStateRaw = syncState.rawValue
        visit.lastSyncError = error
        visit.serverUpdatedAt = syncState == .synced ? .now : visit.serverUpdatedAt
        visit.localUpdatedAt = .now
        visit.updatedAt = .now

        let canonicalVisitID = visit.serverID ?? visit.id
        for photo in visitPhotos where previousIDs.contains(photo.visitID) {
            photo.visitID = canonicalVisitID
        }

        refreshUserPlaceVisitSummary(userPlaceID: visit.userPlaceID)
        objectWillChange.send()
        persist()
    }

    private func markVisitPhoto(
        localOrServerID: String,
        serverID: String? = nil,
        visitID: String? = nil,
        storagePath: String? = nil,
        remoteURLString: String? = nil,
        syncState: SyncState,
        uploadState: VisitPhotoUploadState,
        error: String? = nil,
        result: VisitPhotoResult? = nil
    ) {
        guard let photo = visitPhotos.first(where: { $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID }) else {
            return
        }

        if let serverID {
            photo.serverID = serverID
        }
        if let visitID {
            photo.visitID = visitID
        }
        if let storagePath {
            photo.storagePath = storagePath
        }
        if let remoteURLString {
            photo.remoteURLString = remoteURLString
        }
        if let result {
            photo.serverID = result.photoID
            photo.visitID = result.visitID
            photo.storageBucket = result.storageBucket
            photo.storagePath = result.storagePath
            photo.contentType = result.contentType
            photo.byteSize = result.byteSize
            photo.width = result.width
            photo.height = result.height
            photo.capturedAt = result.capturedAt
            photo.sortOrder = result.sortOrder
            photo.uploadStateRaw = result.uploadState.rawValue
        } else {
            photo.uploadStateRaw = uploadState.rawValue
        }
        photo.syncStateRaw = syncState.rawValue
        photo.lastSyncError = error
        photo.serverUpdatedAt = syncState == .synced ? .now : photo.serverUpdatedAt
        photo.localUpdatedAt = .now
        photo.updatedAt = .now

        objectWillChange.send()
        persist()
    }

    private func visitDraft(for visitID: String, remoteUserPlaceID: String) -> PlaceVisitDraft? {
        guard let visit = placeVisits.first(where: { $0.deletedAt == nil && ($0.id == visitID || $0.localID == visitID || $0.serverID == visitID) }) else {
            return nil
        }

        return PlaceVisitDraft(
            id: visit.serverID,
            userPlaceID: remoteUserPlaceID,
            visitedAt: visit.visitedAt,
            note: visit.note,
            ratingScore: visit.ratingScore,
            attributeAnswersJSON: visit.attributeAnswersJSON,
            backfilledFromUserPlace: visit.backfilledFromUserPlace
        )
    }

    private func visitPhotoDraft(for photoID: String, uploadState: VisitPhotoUploadState) -> VisitPhotoDraft? {
        guard let photo = visitPhotos.first(where: { $0.deletedAt == nil && ($0.id == photoID || $0.localID == photoID || $0.serverID == photoID) }),
              let photoID = photo.serverID,
              let storagePath = photo.storagePath
        else {
            return nil
        }

        return VisitPhotoDraft(
            id: photoID,
            visitID: photo.visitID,
            storageBucket: photo.storageBucket,
            storagePath: storagePath,
            remoteURLString: photo.remoteURLString,
            contentType: photo.contentType,
            byteSize: photo.byteSize,
            width: photo.width,
            height: photo.height,
            capturedAt: photo.capturedAt,
            sortOrder: photo.sortOrder,
            uploadState: uploadState
        )
    }

    private func hydrateBackfilledVisit(_ visit: LocalPlaceVisit, remoteUserPlaceID: String, backend: WanderBackend) async -> Bool {
        do {
            let remoteVisits = try await backend.visits(for: remoteUserPlaceID)
            guard let result = remoteVisits.first(where: { $0.backfilledFromUserPlace }) else {
                markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: "Remote backfilled visit missing")
                return false
            }
            markPlaceVisit(localOrServerID: visit.id, serverID: result.visitID, syncState: .synced, result: result)
            return true
        } catch {
            let message = remoteErrorMessage(error)
            markPlaceVisit(localOrServerID: visit.id, syncState: .failed, error: message)
            lastRemoteError = message
            return false
        }
    }

    private func fileExtension(forContentType contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/png":
            return "png"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        case "image/webp":
            return "webp"
        default:
            return "jpg"
        }
    }

    private func removeSaveLocally(userPlaceID: String) -> LocalRemoveSaveChange? {
        guard let userPlace = userPlaces.first(where: { userPlace in
            userPlace.userID == currentUser.id
                && userPlace.deletedAt == nil
                && (userPlace.id == userPlaceID || userPlace.localID == userPlaceID || userPlace.serverID == userPlaceID)
        }) else {
            return removeRemoteOnlySaveLocally(userPlaceID: userPlaceID)
        }

        let targetPlace = places.first { place in
            place.id == userPlace.placeID || place.localID == userPlace.placeID || place.serverID == userPlace.placeID
        }
        let targetVisiblePlace = targetPlace.map { place in
            VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: currentUser)
        }
        var previousUserPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        if let targetVisiblePlace {
            for visiblePlace in currentUserVisiblePlaces where VisiblePlaceGrouping.matches(visiblePlace, targetVisiblePlace) {
                previousUserPlaceIDs.formUnion(matchingUserPlaceIDs(visiblePlace.userPlace.id))
            }
        }

        let userPlacesToRemove = userPlaces.filter { candidate in
            candidate.userID == currentUser.id
                && candidate.deletedAt == nil
                && (previousUserPlaceIDs.contains(candidate.id)
                    || previousUserPlaceIDs.contains(candidate.localID)
                    || candidate.serverID.map { previousUserPlaceIDs.contains($0) } == true)
        }
        guard !userPlacesToRemove.isEmpty else {
            return nil
        }

        let removedUserPlaceIDs = userPlacesToRemove.map(\.id)
        let remoteUserPlaceIDs = userPlacesToRemove.compactMap(\.serverID)
        let nextSyncState: SyncState = remoteUserPlaceIDs.isEmpty ? .tombstoned : .pendingDelete
        let now = Date.now

        for userPlace in userPlacesToRemove {
            let rowSyncState: SyncState = userPlace.serverID == nil ? .tombstoned : .pendingDelete
            userPlace.note = nil
            userPlace.ratingSignal = nil
            userPlace.ratingScore = nil
            userPlace.recommendedScore = nil
            userPlace.recommendedCount = 0
            userPlace.categoryOverride = nil
            userPlace.subcategoryOverride = nil
            userPlace.categoryOverrideSource = nil
            userPlace.categoryOverrideConfidence = nil
            userPlace.plannedDate = nil
            userPlace.deletedAt = now
            userPlace.updatedAt = now
            userPlace.localUpdatedAt = now
            userPlace.lastSyncError = nil
            userPlace.syncStateRaw = rowSyncState.rawValue
        }

        for visit in placeVisits where previousUserPlaceIDs.contains(visit.userPlaceID) && visit.deletedAt == nil {
            let visitIDs = matchingVisitIDs(visit.id)
            for photo in visitPhotos where visitIDs.contains(photo.visitID) && photo.deletedAt == nil {
                softDelete(photo, at: now)
            }
            softDelete(visit, at: now)
        }
        placeAttributes.removeAll { previousUserPlaceIDs.contains($0.userPlaceID) }
        remoteVisiblePlaceCache.removeAll { visiblePlace in
            guard visiblePlace.owner.id == currentUser.id else { return false }
            if previousUserPlaceIDs.contains(visiblePlace.userPlace.id) {
                return true
            }
            guard let targetVisiblePlace else {
                return false
            }
            return VisiblePlaceGrouping.matches(visiblePlace, targetVisiblePlace)
        }

        objectWillChange.send()
        persist()

        return LocalRemoveSaveChange(
            userPlaceID: userPlace.id,
            removedUserPlaceIDs: removedUserPlaceIDs,
            remoteUserPlaceIDs: remoteUserPlaceIDs,
            syncState: nextSyncState
        )
    }

    private func removeRemoteOnlySaveLocally(userPlaceID: String) -> LocalRemoveSaveChange? {
        guard let targetVisiblePlace = remoteVisiblePlaceCache.first(where: { visiblePlace in
            visiblePlace.owner.id == currentUser.id
                && (visiblePlace.userPlace.id == userPlaceID
                    || visiblePlace.userPlace.localID == userPlaceID
                    || visiblePlace.userPlace.serverID == userPlaceID)
        }) else {
            return nil
        }

        let matchingVisiblePlaces = remoteVisiblePlaceCache.filter { visiblePlace in
            visiblePlace.owner.id == currentUser.id
                && VisiblePlaceGrouping.matches(visiblePlace, targetVisiblePlace)
        }
        guard !matchingVisiblePlaces.isEmpty else {
            return nil
        }

        let now = Date.now
        var removedUserPlaceIDs = Set<String>()
        var remoteUserPlaceIDs = Set<String>()
        for visiblePlace in matchingVisiblePlaces {
            if !places.contains(where: {
                $0.id == visiblePlace.place.id
                    || $0.localID == visiblePlace.place.localID
                    || ($0.serverID != nil
                        && $0.serverID == visiblePlace.place.serverID)
            }) {
                places.append(visiblePlace.place)
            }
            if !userPlaces.contains(where: {
                !Self.referenceIDs(for: $0).isDisjoint(
                    with: Self.referenceIDs(for: visiblePlace.userPlace)
                )
            }) {
                userPlaces.append(visiblePlace.userPlace)
            }
            deleteUserPlaceAfterLastVisit(visiblePlace.userPlace, at: now)
            removedUserPlaceIDs.insert(visiblePlace.userPlace.id)
            removedUserPlaceIDs.insert(visiblePlace.userPlace.localID)
            if let serverID = visiblePlace.userPlace.serverID {
                removedUserPlaceIDs.insert(serverID)
                remoteUserPlaceIDs.insert(serverID)
            } else if UUID(uuidString: visiblePlace.userPlace.id) != nil {
                remoteUserPlaceIDs.insert(visiblePlace.userPlace.id)
            }
        }

        placeAttributes.removeAll { removedUserPlaceIDs.contains($0.userPlaceID) }
        remoteVisiblePlaceCache.removeAll { visiblePlace in
            guard visiblePlace.owner.id == currentUser.id else { return false }
            if removedUserPlaceIDs.contains(visiblePlace.userPlace.id) {
                return true
            }
            return VisiblePlaceGrouping.matches(visiblePlace, targetVisiblePlace)
        }

        objectWillChange.send()
        persist()

        return LocalRemoveSaveChange(
            userPlaceID: targetVisiblePlace.userPlace.id,
            removedUserPlaceIDs: Array(removedUserPlaceIDs),
            remoteUserPlaceIDs: Array(remoteUserPlaceIDs),
            syncState: .pendingDelete
        )
    }

    private func markPlace(localOrServerID: String, serverID: String, syncState: SyncState, error: String? = nil) {
        guard let place = places.first(where: { $0.id == localOrServerID || $0.localID == localOrServerID || $0.serverID == localOrServerID }) else {
            return
        }

        let previousIDs = matchingPlaceIDs(localOrServerID)
        place.serverID = serverID
        place.syncStateRaw = syncState.rawValue
        place.lastSyncError = error
        place.serverUpdatedAt = syncState == .synced ? .now : place.serverUpdatedAt

        for userPlace in userPlaces where previousIDs.contains(userPlace.placeID) {
            userPlace.placeID = serverID
        }
        objectWillChange.send()
        persist()
    }

    private func remoteSocialSaveIDs(for visiblePlace: VisiblePlace) -> (placeID: String, sourceUserPlaceID: String)? {
        guard let placeID = visiblePlace.place.serverID,
              let sourceUserPlaceID = visiblePlace.userPlace.serverID,
              UUID(uuidString: placeID) != nil,
              UUID(uuidString: sourceUserPlaceID) != nil
        else {
            return nil
        }

        return (placeID, sourceUserPlaceID)
    }

    private func upsertRemotePlaceListSummaries(_ summaries: [RemotePlaceListSummary]) {
        let ownerShells = summaries.map(\.owner)
        let collaboratorShells = summaries.flatMap { summary in
            summary.collaborators.map(\.profileShell)
        }
        upsertRemoteProfileShells(ownerShells + collaboratorShells, preserveExistingProfileMetadataWhenMissing: true)

        for summary in summaries {
            guard !shouldPreserveLocalPlaceListChanges(remoteListID: summary.list.id) else { continue }
            upsertRemotePlaceList(summary.list)
            replaceRemoteCollaborators(listID: summary.list.id, collaborators: summary.collaborators)
        }

        objectWillChange.send()
        persist()
    }

    private func reconcileMissingRemotePlaceLists(with summaries: [RemotePlaceListSummary]) {
        let visibleRemoteIDs = Set(summaries.map(\.list.id))
        let now = Date.now

        for listIndex in placeLists.indices where
            placeLists[listIndex].deletedAt == nil
                && placeLists[listIndex].syncState == .synced
                && placeLists[listIndex].serverID.map({ UUID(uuidString: $0) != nil }) == true
                && !visibleRemoteIDs.contains(placeLists[listIndex].serverID ?? placeLists[listIndex].id) {
            let list = placeLists[listIndex]
            let listIDs = listReferenceIDs(for: list)
            placeLists[listIndex].deletedAt = now
            placeLists[listIndex].updatedAt = now
            placeLists[listIndex].syncStateRaw = SyncState.tombstoned.rawValue

            for memberIndex in placeListMembers.indices where listIDs.contains(placeListMembers[memberIndex].listID) && placeListMembers[memberIndex].deletedAt == nil {
                placeListMembers[memberIndex].deletedAt = now
            }
            for itemIndex in placeListItems.indices where listIDs.contains(placeListItems[itemIndex].listID) && placeListItems[itemIndex].deletedAt == nil {
                placeListItems[itemIndex].deletedAt = now
                placeListItems[itemIndex].updatedAt = now
                placeListItems[itemIndex].syncStateRaw = SyncState.tombstoned.rawValue
            }
        }
    }

    private func upsertRemotePlaceListDetail(_ detail: RemotePlaceListDetail) {
        guard !shouldPreserveLocalPlaceListChanges(remoteListID: detail.list.id) else { return }

        upsertRemoteProfileShells(detail.collaborators.map(\.profileShell), preserveExistingProfileMetadataWhenMissing: true)
        upsertRemotePlaceList(detail.list)
        replaceRemoteCollaborators(listID: detail.list.id, collaborators: detail.collaborators)
        replaceRemoteItems(listID: detail.list.id, items: detail.items)

        if let index = placeLists.firstIndex(where: { $0.id == detail.list.id || $0.serverID == detail.list.id }) {
            placeLists[index].cachedItemCount = detail.items.filter { $0.deletedAt == nil }.count
        }

        objectWillChange.send()
        persist()
    }

    private func shouldPreserveLocalPlaceListChanges(remoteListID: String) -> Bool {
        guard let localList = placeLists.first(where: { list in
            list.id == remoteListID || list.serverID == remoteListID
        }), localList.ownerUserID == currentUser.id else {
            return false
        }

        switch localList.syncState {
        case .pendingCreate, .pendingUpdate, .pendingDelete, .failed, .serverDenied:
            return true
        case .localOnly, .synced, .tombstoned:
            return false
        }
    }

    private func upsertRemotePlaceList(_ remoteList: LocalPlaceList) {
        guard let serverID = remoteList.serverID else { return }

        if let index = placeLists.firstIndex(where: { list in
            list.serverID == serverID || list.localID == remoteList.localID || list.id == serverID
        }) {
            let previousID = placeLists[index].id
            placeLists[index].serverID = serverID
            placeLists[index].ownerUserID = remoteList.ownerUserID
            placeLists[index].name = remoteList.name
            placeLists[index].description = remoteList.description
            placeLists[index].visibilityRaw = remoteList.visibilityRaw
            placeLists[index].syncStateRaw = SyncState.synced.rawValue
            placeLists[index].cachedItemCount = remoteList.cachedItemCount
            placeLists[index].createdAt = remoteList.createdAt
            placeLists[index].updatedAt = remoteList.updatedAt
            placeLists[index].deletedAt = remoteList.deletedAt
            replaceListIDReferences(previousID: previousID, canonicalID: placeLists[index].id)
        } else {
            placeLists.append(remoteList)
        }
    }

    private func replaceRemoteCollaborators(listID: String, collaborators: [PlaceListCollaboratorRecord]) {
        let incomingUserIDs = Set(collaborators.map(\.userID))
        placeListMembers.removeAll { member in
            member.listID == listID
                && member.localID.hasPrefix("remote_list_member_")
                && !incomingUserIDs.contains(member.userID)
        }

        for collaborator in collaborators {
            let localID = "remote_list_member_\(slug(listID))_\(slug(collaborator.userID))"
            if let index = placeListMembers.firstIndex(where: { member in
                member.serverID == localID
                    || (member.listID == listID && member.userID == collaborator.userID)
            }) {
                placeListMembers[index].serverID = nil
                placeListMembers[index].listID = listID
                placeListMembers[index].userID = collaborator.userID
                placeListMembers[index].roleRaw = collaborator.role.rawValue
                placeListMembers[index].deletedAt = nil
            } else {
                placeListMembers.append(
                    LocalPlaceListMember(
                        localID: localID,
                        listID: listID,
                        userID: collaborator.userID,
                        role: collaborator.role
                    )
                )
            }
        }
    }

    private func replaceRemoteItems(listID: String, items: [LocalPlaceListItem]) {
        let incomingIDs = Set(items.map(\.id))
        placeListItems.removeAll { item in
            item.listID == listID
                && item.localID.hasPrefix("remote_list_item_")
                && !incomingIDs.contains(item.id)
        }

        for item in items {
            if let index = placeListItems.firstIndex(where: { existing in
                existing.serverID == item.serverID
                    || existing.id == item.id
                    || (existing.listID == listID && existing.placeID == item.placeID && existing.deletedAt == nil)
            }) {
                placeListItems[index].serverID = item.serverID
                placeListItems[index].listID = listID
                placeListItems[index].placeID = item.placeID
                placeListItems[index].ownerUserPlaceID = item.ownerUserPlaceID
                placeListItems[index].sourceUserPlaceID = item.sourceUserPlaceID
                placeListItems[index].addedByUserID = item.addedByUserID
                placeListItems[index].syncStateRaw = SyncState.synced.rawValue
                placeListItems[index].createdAt = item.createdAt
                placeListItems[index].updatedAt = item.updatedAt
                placeListItems[index].deletedAt = item.deletedAt
            } else {
                placeListItems.append(item)
            }
        }
    }

    private func replaceListIDReferences(previousID: String, canonicalID: String) {
        guard previousID != canonicalID else { return }

        for index in placeListMembers.indices where placeListMembers[index].listID == previousID {
            placeListMembers[index].listID = canonicalID
        }

        for index in placeListItems.indices where placeListItems[index].listID == previousID {
            placeListItems[index].listID = canonicalID
        }
    }

    private func hydrateRemoteVisiblePlaceMetadata(_ visiblePlaces: [VisiblePlace]) {
        let shells = visiblePlaces.map { visiblePlace in
            ProfileShell(
                id: visiblePlace.owner.id,
                handle: visiblePlace.owner.handle,
                displayName: visiblePlace.owner.displayName,
                avatarURL: visiblePlace.owner.avatarURL,
                bio: visiblePlace.owner.bio,
                homeArea: visiblePlace.owner.homeArea,
                isPrivateProfile: nil,
                createdAt: nil,
                relationship: relationship(to: visiblePlace.owner.id)
            )
        }
        upsertRemoteProfileShells(shells, preserveExistingProfileMetadataWhenMissing: true)
        upsertRemoteAttributes(from: visiblePlaces)
    }

    private func applyRemoteWannaGoPlans(_ plans: [OwnWannaGoPlan]) {
        let plansByUserPlaceID = Dictionary(uniqueKeysWithValues: plans.map { ($0.userPlaceID, $0) })

        for userPlace in userPlaces where userPlace.userID == currentUser.id
            && userPlace.deletedAt == nil
            && userPlace.syncState == .synced {
            let remoteID = userPlace.serverID ?? userPlace.id
            userPlace.plannedDate = userPlace.status == .wannaGo
                ? plansByUserPlaceID[remoteID]?.plannedDate
                : nil
        }

        for visiblePlace in remoteVisiblePlaceCache where visiblePlace.owner.id == currentUser.id
            && visiblePlace.userPlace.deletedAt == nil {
            visiblePlace.userPlace.plannedDate = visiblePlace.userPlace.status == .wannaGo
                ? plansByUserPlaceID[visiblePlace.userPlace.id]?.plannedDate
                : nil
        }

        objectWillChange.send()
        persist()
    }

    private func applyRemoteProfileVisiblePlaces(_ visiblePlaces: [VisiblePlace], profileID: String) {
        remoteVisiblePlaceCache.removeAll { $0.owner.id == profileID }
        remoteVisiblePlaceCache.append(contentsOf: visiblePlaces)
        hydrateRemoteVisiblePlaceMetadata(visiblePlaces)
    }

    /// Viewport queries are intentionally partial. Keep the current user's
    /// fully hydrated profile slice so Map/Discover refreshes cannot truncate
    /// Profile calendar or widget activity outside the visible region.
    private func replaceRemoteViewportVisiblePlaces(_ visiblePlaces: [VisiblePlace]) {
        let retainedOwnerPlaces = remoteVisiblePlaceCache.filter {
            $0.owner.id == currentUser.id
        }
        let incomingNonOwnerPlaces = visiblePlaces.filter {
            $0.owner.id != currentUser.id
        }
        let ownerPlaces = authoritativeCalendarUserID == currentUser.id
            ? retainedOwnerPlaces
            : mergeCalendarVisiblePlaces(
                retainedOwnerPlaces + visiblePlaces.filter {
                    $0.owner.id == currentUser.id
                }
            )

        remoteVisiblePlaceCache = mergeVisiblePlaces(incomingNonOwnerPlaces + ownerPlaces)
        hydrateRemoteVisiblePlaceMetadata(visiblePlaces)
    }

    private func applyRemoteCurrentProfile(_ remoteProfile: LocalProfile) {
        withDeferredPersistence {
            objectWillChange.send()

            let now = Date()
            let currentLocalID = currentUser.localID
            let currentProfileID = remoteProfile.id
            let becamePrivate = !isPrivateProfile && remoteProfile.isPrivateProfile

            currentUser.serverID = remoteProfile.serverID ?? remoteProfile.localID
            currentUser.handle = remoteProfile.handle
            currentUser.searchHandle = remoteProfile.handle.lowercased()
            currentUser.displayName = remoteProfile.displayName
            currentUser.avatarURL = currentProfileAvatarURL(
                incoming: remoteProfile.avatarURL,
                existing: currentUser.avatarURL
            )
            currentUser.bio = remoteProfile.bio
            currentUser.homeArea = remoteProfile.homeArea
            currentUser.onboardingCompletedAt = remoteProfile.onboardingCompletedAt
            currentUser.isPrivateProfile = remoteProfile.isPrivateProfile
            currentUser.defaultVisibilityRaw = remoteProfile.defaultVisibility.rawValue
            currentUser.createdAt = remoteProfile.createdAt
            currentUser.syncStateRaw = SyncState.synced.rawValue
            currentUser.serverUpdatedAt = now
            currentUser.updatedAt = now

            for profile in profiles where profile.localID == currentLocalID || profile.id == currentProfileID {
                profile.serverID = currentUser.serverID
                profile.handle = currentUser.handle
                profile.searchHandle = currentUser.searchHandle
                profile.displayName = currentUser.displayName
                profile.avatarURL = currentUser.avatarURL
                profile.bio = currentUser.bio
                profile.homeArea = currentUser.homeArea
                profile.onboardingCompletedAt = currentUser.onboardingCompletedAt
                profile.isPrivateProfile = currentUser.isPrivateProfile
                profile.defaultVisibilityRaw = currentUser.defaultVisibilityRaw
                profile.createdAt = currentUser.createdAt
                profile.syncStateRaw = SyncState.synced.rawValue
                profile.serverUpdatedAt = now
                profile.updatedAt = now
            }

            if defaultVisibility != remoteProfile.defaultVisibility {
                defaultVisibility = remoteProfile.defaultVisibility
            }
            if isPrivateProfile != remoteProfile.isPrivateProfile {
                isPrivateProfile = remoteProfile.isPrivateProfile
            }
            if becamePrivate {
                makeCurrentUserContentPrivate()
            }
            persist()
        }
    }

    private func upsertRemoteAttributes(from visiblePlaces: [VisiblePlace]) {
        let userPlaceIDsWithAttributes = Set(visiblePlaces.filter { !$0.attributes.isEmpty }.map(\.userPlace.id))
        guard !userPlaceIDsWithAttributes.isEmpty else { return }

        placeAttributes.removeAll { attribute in
            userPlaceIDsWithAttributes.contains(attribute.userPlaceID)
                && attribute.localID.hasPrefix("remote_attr_")
        }

        let attributes = visiblePlaces.flatMap(\.attributes)
        placeAttributes.append(contentsOf: attributes)
        objectWillChange.send()
        persist()
    }

    private func upsertRemoteSocialGraph(userID: String, following: [ProfileShell], followers: [ProfileShell]) {
        upsertRemoteProfileShells(following + followers, preserveExistingProfileMetadataWhenMissing: true)

        let followingIDs = Set(following.map(\.id)).subtracting([userID])
        let followerIDs = Set(followers.map(\.id)).subtracting([userID])

        follows.removeAll { follow in
            follow.localID.hasPrefix("remote_follow_")
                && (follow.followerUserID == userID || follow.followedUserID == userID)
        }

        for followedID in followingIDs where !isBlockedBetweenCurrentUser(and: followedID) {
            upsertRemoteFollow(followerUserID: userID, followedUserID: followedID)
        }

        for followerID in followerIDs where !isBlockedBetweenCurrentUser(and: followerID) {
            upsertRemoteFollow(followerUserID: followerID, followedUserID: userID)
        }

        objectWillChange.send()
        persist()
    }

    private func applyRemoteRelationship(profileID: String, relationship: ViewerRelationship) {
        guard profileID != currentUser.id else { return }

        let currentToProfileID = remoteFollowLocalID(followerUserID: currentUser.id, followedUserID: profileID)
        let profileToCurrentID = remoteFollowLocalID(followerUserID: profileID, followedUserID: currentUser.id)

        follows.removeAll { follow in
            follow.localID == currentToProfileID || follow.localID == profileToCurrentID
        }

        switch relationship {
        case .owner, .nonFollower:
            break
        case .follower:
            upsertRemoteFollow(followerUserID: currentUser.id, followedUserID: profileID)
        case .mutual:
            upsertRemoteFollow(followerUserID: currentUser.id, followedUserID: profileID)
            upsertRemoteFollow(followerUserID: profileID, followedUserID: currentUser.id)
        }

        objectWillChange.send()
        persist()
    }

    private func upsertRemoteFollow(followerUserID: String, followedUserID: String) {
        guard followerUserID != followedUserID,
              !follows.contains(where: { $0.followerUserID == followerUserID && $0.followedUserID == followedUserID })
        else { return }

        follows.append(
            LocalFollow(
                localID: remoteFollowLocalID(followerUserID: followerUserID, followedUserID: followedUserID),
                followerUserID: followerUserID,
                followedUserID: followedUserID,
                source: .profile,
                syncState: .synced
            )
        )
    }

    private func remoteFollowLocalID(followerUserID: String, followedUserID: String) -> String {
        "remote_follow_\(slug(followerUserID))_\(slug(followedUserID))"
    }

    private func upsertRemoteProfileShells(_ shells: [ProfileShell], preserveExistingProfileMetadataWhenMissing: Bool = false) {
        for shell in shells where shell.id != currentUser.id && !isBlockedBetweenCurrentUser(and: shell.id) {
            if let existing = profiles.first(where: { $0.id == shell.id || $0.handle == shell.handle }) {
                existing.serverID = shell.id
                existing.handle = shell.handle
                existing.searchHandle = shell.handle.lowercased()
                existing.displayName = shell.displayName
                existing.avatarURL = mergedProfileMetadata(
                    incoming: shell.avatarURL,
                    existing: existing.avatarURL,
                    preserveExistingWhenMissing: preserveExistingProfileMetadataWhenMissing
                )
                existing.bio = mergedProfileMetadata(
                    incoming: shell.bio,
                    existing: existing.bio,
                    preserveExistingWhenMissing: preserveExistingProfileMetadataWhenMissing
                )
                existing.homeArea = mergedProfileMetadata(
                    incoming: shell.homeArea,
                    existing: existing.homeArea,
                    preserveExistingWhenMissing: preserveExistingProfileMetadataWhenMissing
                )
                if let isPrivateProfile = shell.isPrivateProfile {
                    existing.isPrivateProfile = isPrivateProfile
                }
                if let createdAt = shell.createdAt {
                    existing.createdAt = createdAt
                }
                existing.syncStateRaw = SyncState.synced.rawValue
                existing.updatedAt = .now
            } else {
                profiles.append(
                    LocalProfile(
                        localID: "remote_profile_\(shell.id)",
                        serverID: shell.id,
                        handle: shell.handle,
                        displayName: shell.displayName,
                        avatarURL: shell.avatarURL,
                        bio: shell.bio,
                        homeArea: shell.homeArea,
                        isPrivateProfile: shell.isPrivateProfile ?? false,
                        syncState: .synced,
                        createdAt: shell.createdAt ?? .now
                    )
                )
            }
        }
        objectWillChange.send()
        persist()
    }

    private func mergedProfileMetadata(
        incoming: String?,
        existing: String?,
        preserveExistingWhenMissing: Bool
    ) -> String? {
        nonEmpty(incoming) ?? (preserveExistingWhenMissing ? existing : nil)
    }

    private func currentProfileAvatarURL(incoming: String?, existing: String?) -> String? {
        if let incoming = nonEmpty(incoming) {
            return incoming
        }

        guard let existing = nonEmpty(existing),
              URL(string: existing)?.isFileURL == true
        else {
            return nil
        }

        return existing
    }

    private func mergeProfileShells(_ shells: [ProfileShell]) -> [ProfileShell] {
        var merged: [ProfileShell] = []

        for shell in shells where shell.id != currentUser.id && !isBlockedBetweenCurrentUser(and: shell.id) && !isProfilePrivate(shell.id) {
            if let existingIndex = merged.firstIndex(where: { $0.id == shell.id }) {
                merged[existingIndex] = mergedProfileShell(merged[existingIndex], with: shell)
            } else {
                merged.append(shell)
            }
        }

        return merged
    }

    private func mergedProfileShell(_ existing: ProfileShell, with incoming: ProfileShell) -> ProfileShell {
        ProfileShell(
            id: existing.id,
            handle: incoming.handle,
            displayName: incoming.displayName,
            avatarURL: nonEmpty(incoming.avatarURL) ?? existing.avatarURL,
            bio: nonEmpty(incoming.bio) ?? existing.bio,
            homeArea: nonEmpty(incoming.homeArea) ?? existing.homeArea,
            isPrivateProfile: incoming.isPrivateProfile ?? existing.isPrivateProfile,
            createdAt: incoming.createdAt ?? existing.createdAt,
            relationship: strongestRelationship(existing.relationship, incoming.relationship)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return value
    }

    private func strongestRelationship(_ lhs: ViewerRelationship, _ rhs: ViewerRelationship) -> ViewerRelationship {
        relationshipRank(lhs) >= relationshipRank(rhs) ? lhs : rhs
    }

    private func relationshipRank(_ relationship: ViewerRelationship) -> Int {
        switch relationship {
        case .owner:
            return 3
        case .mutual:
            return 2
        case .follower:
            return 1
        case .nonFollower:
            return 0
        }
    }

    private func normalizedHandleQuery(_ query: String) -> String {
        query
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func remoteErrorMessage(_ error: Error) -> String {
        String(describing: error)
    }

    private func remoteErrorKind(_ error: Error) -> String {
        if let remoteError = error as? WanderRemoteError {
            switch remoteError {
            case .notConfigured:
                return "not_configured"
            case .notAuthenticated:
                return "not_authenticated"
            case .notImplemented:
                return "not_implemented"
            case .invalidResponse:
                return "invalid_response"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }

        if error is DecodingError {
            return "decoding"
        }

        return "unknown"
    }

    private func retryOwnPlaceSync(
        userPlaceID: String,
        backend: WanderBackend,
        trigger: OwnPlaceSyncTrigger,
        refreshVisiblePlacesAfterSuccess: Bool = true
    ) async -> OwnPlaceSyncOutcome {
        guard let draft = userPlaceDraft(for: userPlaceID) else {
            trackOwnPlaceSyncEvent(
                name: WanderAnalyticsEvents.ownPlaceSyncSkipped,
                properties: [
                    "trigger": trigger.rawValue,
                    "reason": "missing_draft"
                ]
            )
            #if DEBUG
            WanderDebugLog.sync.debug("own-place sync skipped trigger=\(trigger.rawValue, privacy: .public) reason=missing_draft user_place=\(WanderDebugLog.shortID(userPlaceID), privacy: .public)")
            #endif
            return .skipped
        }

        let syncProperties = ownPlaceSyncProperties(userPlaceID: userPlaceID, draft: draft, trigger: trigger)
        trackOwnPlaceSyncEvent(
            name: WanderAnalyticsEvents.ownPlaceSyncAttempted,
            properties: syncProperties
        )
        #if DEBUG
        WanderDebugLog.sync.debug("own-place sync attempt trigger=\(trigger.rawValue, privacy: .public) user_place=\(WanderDebugLog.shortID(userPlaceID), privacy: .public) place_has_server_id=\((draft.place.serverID != nil), privacy: .public) attribute_count=\(draft.attributes.count, privacy: .public)")
        #endif

        let syncingUserPlace = userPlaces.first {
            $0.id == userPlaceID || $0.localID == userPlaceID || $0.serverID == userPlaceID
        }
        let explicitVisit = draft.status == .been
            ? visits(for: userPlaceID)
                .filter { !$0.backfilledFromUserPlace && $0.syncState != .synced }
                .sorted {
                    if $0.createdAt != $1.createdAt {
                        return $0.createdAt < $1.createdAt
                    }
                    return $0.id < $1.id
                }
                .first
            : nil

        markUserPlace(localOrServerID: userPlaceID, syncState: .pendingUpdate, error: nil)
        do {
            let remoteResult: SaveResult
            if let explicitVisit,
               let syncingUserPlace,
               let atomicDraft = checkInDraft(for: explicitVisit.id, userPlace: syncingUserPlace) {
                let checkInResult = try await backend.saveCheckIn(atomicDraft)
                remoteResult = checkInResult.saveResult
                markPlaceVisit(
                    localOrServerID: explicitVisit.id,
                    serverID: checkInResult.visitResult.visitID,
                    syncState: .synced,
                    result: checkInResult.visitResult
                )
            } else {
                remoteResult = try await backend.saveUserPlace(draft)
            }
            if let placeID = remoteResult.placeID {
                markPlace(localOrServerID: draft.place.localID, serverID: placeID, syncState: .synced)
            }
            markUserPlace(localOrServerID: userPlaceID, serverID: remoteResult.userPlaceID, syncState: .synced)
            lastRemoteError = nil
            trackOwnPlaceSyncEvent(
                name: WanderAnalyticsEvents.ownPlaceSyncSucceeded,
                properties: syncProperties
            )
            #if DEBUG
            WanderDebugLog.sync.debug("own-place sync success trigger=\(trigger.rawValue, privacy: .public) local_user_place=\(WanderDebugLog.shortID(userPlaceID), privacy: .public) remote_user_place=\(WanderDebugLog.shortID(remoteResult.userPlaceID), privacy: .public) remote_place=\(WanderDebugLog.shortID(remoteResult.placeID), privacy: .public)")
            #endif
            if refreshVisiblePlacesAfterSuccess {
                await refreshRemoteVisiblePlaces(backend: backend)
            }
            return .succeeded
        } catch {
            let message = remoteErrorMessage(error)
            if let explicitVisit {
                markPlaceVisit(localOrServerID: explicitVisit.id, syncState: .failed, error: message)
            }
            markUserPlace(localOrServerID: userPlaceID, syncState: .failed, error: message)
            lastRemoteError = message
            trackOwnPlaceSyncEvent(
                name: WanderAnalyticsEvents.ownPlaceSyncFailed,
                properties: syncProperties.merging(["error_kind": remoteErrorKind(error)]) { _, new in new }
            )
            #if DEBUG
            WanderDebugLog.sync.error("own-place sync failed trigger=\(trigger.rawValue, privacy: .public) user_place=\(WanderDebugLog.shortID(userPlaceID), privacy: .public) error_kind=\(self.remoteErrorKind(error), privacy: .public) error=\(WanderDebugLog.clean(message), privacy: .public)")
            #endif
            return .failed
        }
    }

    private func trackOwnPlaceSyncBatchSkipped(trigger: OwnPlaceSyncTrigger, reason: String) {
        trackOwnPlaceSyncEvent(
            name: WanderAnalyticsEvents.ownPlaceSyncBatchSkipped,
            properties: [
                "trigger": trigger.rawValue,
                "reason": reason
            ]
        )
    }

    private func trackOwnPlaceSyncEvent(name: String, properties: [String: String]) {
        analytics.track(AnalyticsEvent(name: name, properties: properties))
    }

    private func syncCandidateStateSummary() -> String {
        let counts = userPlaces
            .filter { userPlace in
                userPlace.userID == currentUser.id
                    && userPlace.deletedAt == nil
                    && userPlace.sourceType != AddSourceType.socialSave.rawValue
            }
            .reduce(into: [String: Int]()) { counts, userPlace in
                counts[userPlace.syncState.rawValue, default: 0] += 1
            }

        guard !counts.isEmpty else { return "none" }
        return counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    private func ownPlaceSyncProperties(
        userPlaceID: String,
        draft: UserPlaceDraft,
        trigger: OwnPlaceSyncTrigger
    ) -> [String: String] {
        let userPlace = userPlaces.first { $0.id == userPlaceID || $0.localID == userPlaceID || $0.serverID == userPlaceID }
        let place = places.first { place in
            place.localID == draft.place.localID
                || (draft.place.serverID != nil && place.serverID == draft.place.serverID)
                || userPlace.map { place.id == $0.placeID } == true
        }

        return [
            "trigger": trigger.rawValue,
            "status": draft.status.rawValue,
            "visibility": draft.visibility.rawValue,
            "source_type": draft.sourceType,
            "sync_state_before": userPlace?.syncState.rawValue ?? "unknown",
            "attribute_count": "\(draft.attributes.count)",
            "has_note": boolProperty(draft.note?.isEmpty == false),
            "nearby_confirmed": boolProperty(draft.nearbyConfirmed),
            "place_has_server_id": boolProperty((place?.serverID ?? draft.place.serverID) != nil),
            "user_place_has_server_id": boolProperty(userPlace?.serverID != nil)
        ]
    }

    private func boolProperty(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func upsertPlace(from candidate: PlaceCandidate, sourceType: AddSourceType) -> LocalPlace {
        let providerPlaceID = candidate.sourceProviderPlaceID ?? candidate.id
        let localIdentityHash = stableHash("\(candidate.sourceProvider)|\(providerPlaceID)")
        let sharedAssignment = sharedPlaceAssignment(from: candidate)
        if let existing = place(matching: candidate) {
            mergeBusinessMetadata(from: candidate, sharedAssignment: sharedAssignment, into: existing)
            return existing
        }

        let place = LocalPlace(
            localID: "local_place_\(slug(candidate.name))_\(localIdentityHash)",
            canonicalName: candidate.name,
            category: sharedAssignment.legacyCategory,
            primaryCategory: sharedAssignment.primaryCategory,
            subcategory: sharedAssignment.subcategory,
            categorySource: sharedAssignment.source,
            categoryConfidence: sharedAssignment.confidence,
            rawProviderType: sharedAssignment.rawProviderType,
            address: candidate.address,
            locality: candidate.locality,
            region: candidate.region,
            country: candidate.country,
            latitude: candidate.latitude ?? 34.0522,
            longitude: candidate.longitude ?? -118.2437,
            sourceProvider: candidate.sourceProvider,
            sourceProviderPlaceID: providerPlaceID,
            confidence: candidate.confidence,
            websiteURLString: normalizedMetadata(candidate.websiteURLString),
            phoneNumber: normalizedMetadata(candidate.phoneNumber),
            timeZoneIdentifier: normalizedMetadata(candidate.timeZoneIdentifier),
            actionLinksJSON: normalizedMetadata(candidate.actionLinksJSON),
            syncState: .pendingCreate
        )
        places.append(place)
        return place
    }

    private func place(matching candidate: PlaceCandidate) -> LocalPlace? {
        places.first {
            VisiblePlaceGrouping.matches($0, candidate: candidate)
        }
    }

    private func mergeBusinessMetadata(from candidate: PlaceCandidate, sharedAssignment: PlaceCategoryAssignment, into place: LocalPlace) {
        var didChange = false

        if shouldUpdateCategory(from: sharedAssignment.primaryCategory, existing: place.primaryCategory) {
            place.category = sharedAssignment.legacyCategory
            place.primaryCategory = sharedAssignment.primaryCategory
            place.subcategory = sharedAssignment.subcategory
            place.categorySource = sharedAssignment.source
            place.categoryConfidence = sharedAssignment.confidence
            place.rawProviderType = sharedAssignment.rawProviderType
            didChange = true
        } else if sharedAssignment.source != PlaceCategorySource.user.rawValue,
                  sharedAssignment.primaryCategory == place.primaryCategory,
                  place.subcategory != sharedAssignment.subcategory {
            place.subcategory = sharedAssignment.subcategory
            place.categorySource = sharedAssignment.source
            place.categoryConfidence = sharedAssignment.confidence
            place.rawProviderType = sharedAssignment.rawProviderType ?? place.rawProviderType
            didChange = true
        }
        didChange = mergeMetadataValue(normalizedMetadata(candidate.websiteURLString), into: &place.websiteURLString) || didChange
        didChange = mergeMetadataValue(normalizedMetadata(candidate.phoneNumber), into: &place.phoneNumber) || didChange
        didChange = mergeMetadataValue(normalizedMetadata(candidate.timeZoneIdentifier), into: &place.timeZoneIdentifier) || didChange
        didChange = mergeMetadataValue(normalizedMetadata(candidate.actionLinksJSON), into: &place.actionLinksJSON) || didChange

        if didChange {
            place.updatedAt = .now
            place.localUpdatedAt = .now
        }
    }

    private func shouldUpdateCategory(from candidateCategory: String, existing existingCategory: String) -> Bool {
        let candidate = candidateCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = existingCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.caseInsensitiveCompare(existing) != .orderedSame else {
            return false
        }

        if candidate.lowercased() == "place", existing.lowercased() != "place" {
            return false
        }

        return true
    }

    private func sharedPlaceAssignment(from candidate: PlaceCandidate) -> PlaceCategoryAssignment {
        if candidate.categorySource == PlaceCategorySource.user.rawValue {
            let rawProviderType = candidate.rawProviderType ?? PlaceCategorySource.unknown.rawValue
            return WanderPlaceCategory.assignment(
                forRawCategory: rawProviderType,
                source: candidate.rawProviderType == nil ? PlaceCategorySource.unknown.rawValue : PlaceCategorySource.provider.rawValue,
                confidence: candidate.categoryConfidence,
                rawProviderType: rawProviderType
            )
        }

        return candidate.categoryAssignment
    }

    private func categoryOverrideAssignment(from candidate: PlaceCandidate) -> PlaceCategoryAssignment? {
        guard candidate.categorySource == PlaceCategorySource.user.rawValue else { return nil }
        return candidate.categoryAssignment
    }

    private func applyCategoryOverride(_ assignment: PlaceCategoryAssignment?, to userPlace: LocalUserPlace) {
        userPlace.categoryOverride = assignment?.primaryCategory
        userPlace.subcategoryOverride = assignment?.subcategory
        userPlace.categoryOverrideSource = assignment?.source
        userPlace.categoryOverrideConfidence = assignment?.confidence
    }

    private func mergeMetadataValue(_ candidateValue: String?, into storedValue: inout String?) -> Bool {
        guard let candidateValue else { return false }
        guard storedValue != candidateValue else { return false }
        storedValue = candidateValue
        return true
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func upsertSourceArtifact(sourceType: AddSourceType, originalInput: String?, localAssetRef: String?) -> LocalSourceArtifact {
        let normalizedInput = normalizedSourceInput(originalInput: originalInput, localAssetRef: localAssetRef)
        let type = sourceType.sourceArtifactType
        let hash = stableHash("\(currentUser.id)|\(type)|\(normalizedInput)")

        if let existing = sourceArtifacts.first(where: { artifact in
            artifact.userID == currentUser.id
                && artifact.type == type
                && artifact.normalizedSourceHash == hash
                && artifact.deletedAt == nil
        }) {
            return existing
        }

        let artifact = LocalSourceArtifact(
            localID: "local_source_\(sourceType.rawValue)_\(hash)",
            userID: currentUser.id,
            type: type,
            originalInput: originalInput?.isEmpty == false ? originalInput ?? normalizedInput : normalizedInput,
            normalizedInput: normalizedInput,
            normalizedSourceHash: hash,
            localAssetRef: localAssetRef,
            syncState: .pendingCreate
        )
        sourceArtifacts.append(artifact)
        return artifact
    }

    private func upsertExtractionJob(sourceType: AddSourceType, artifact: LocalSourceArtifact) -> LocalExtractionJob {
        if let existing = extractionJobs.first(where: { job in
            job.ownerUserID == currentUser.id
                && job.sourceType == sourceType.rawValue
                && job.normalizedSourceHash == artifact.normalizedSourceHash
        }) {
            return existing
        }

        let job = LocalExtractionJob(
            localID: "local_job_\(sourceType.rawValue)_\(artifact.normalizedSourceHash)",
            sourceArtifactID: artifact.serverID ?? artifact.localID,
            ownerUserID: currentUser.id,
            sourceType: sourceType.rawValue,
            normalizedSourceHash: artifact.normalizedSourceHash,
            status: .pending,
            providerStepsJSON: "[\"queued_for_backend_extraction\"]",
            syncState: .pendingCreate
        )
        extractionJobs.append(job)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.extractionJobStarted,
                properties: ["source_type": sourceType.rawValue, "status": job.status.rawValue]
            )
        )
        return job
    }

    private func enqueueExtractionJob(for draft: UnresolvedDraft, backend: WanderBackend) async {
        guard let artifactID = draft.sourceArtifactID,
              let jobID = draft.extractionJobID,
              let artifact = sourceArtifact(matching: artifactID),
              let job = extractionJob(matching: jobID)
        else { return }
        if artifact.serverID != nil,
           job.serverID != nil,
           SyncState(rawValue: artifact.syncStateRaw) == .synced,
           SyncState(rawValue: job.syncStateRaw) == .synced {
            return
        }

        do {
            let result = try await backend.enqueueExtractionJob(
                ExtractionJobDraft(
                    sourceArtifact: SourceArtifactDraft(
                        type: artifact.type,
                        originalInput: artifact.originalInput,
                        normalizedInput: artifact.normalizedInput,
                        normalizedSourceHash: artifact.normalizedSourceHash,
                        localAssetRef: artifact.localAssetRef,
                        remoteAssetRef: artifact.remoteAssetRef
                    ),
                    sourceType: job.sourceType,
                    normalizedSourceHash: job.normalizedSourceHash,
                    providerSteps: providerSteps(from: job.providerStepsJSON)
                )
            )

            markSourceArtifact(
                artifact,
                serverID: result.sourceArtifactID,
                syncState: .synced,
                error: nil
            )
            markExtractionJob(
                job,
                serverID: result.extractionJobID,
                sourceArtifactID: result.sourceArtifactID,
                status: result.status,
                attemptCount: result.attemptCount,
                syncState: .synced,
                error: nil
            )
            updateDraft(
                draftID: draft.id,
                sourceArtifactID: result.sourceArtifactID,
                extractionJobID: result.extractionJobID
            )
            lastRemoteError = nil
        } catch {
            let message = remoteErrorMessage(error)
            markSourceArtifact(artifact, serverID: nil, syncState: .failed, error: message)
            markExtractionJob(
                job,
                serverID: nil,
                sourceArtifactID: artifact.serverID ?? artifact.localID,
                status: .failed,
                attemptCount: job.attemptCount,
                syncState: .failed,
                error: message
            )
            lastRemoteError = message
        }
    }

    private func sourceArtifact(matching id: String) -> LocalSourceArtifact? {
        sourceArtifacts.first { artifact in
            artifact.localID == id || artifact.serverID == id
        }
    }

    private func extractionJob(matching id: String) -> LocalExtractionJob? {
        extractionJobs.first { job in
            job.localID == id || job.serverID == id
        }
    }

    private func updatedDraft(_ draft: UnresolvedDraft) -> UnresolvedDraft {
        guard let index = unresolvedDrafts.firstIndex(where: { $0.id == draft.id }) else {
            return draft
        }
        return unresolvedDrafts[index]
    }

    private func updateDraft(draftID: String, sourceArtifactID: String, extractionJobID: String) {
        guard let index = unresolvedDrafts.firstIndex(where: { $0.id == draftID }) else { return }
        let existing = unresolvedDrafts[index]
        unresolvedDrafts[index] = UnresolvedDraft(
            id: existing.id,
            sourceType: existing.sourceType,
            title: existing.title,
            message: existing.message,
            sourceArtifactID: sourceArtifactID,
            extractionJobID: extractionJobID,
            createdAt: existing.createdAt
        )
        persist()
    }

    private func markSourceArtifact(_ artifact: LocalSourceArtifact, serverID: String?, syncState: SyncState, error: String?) {
        if let serverID {
            artifact.serverID = serverID
        }
        artifact.syncStateRaw = syncState.rawValue
        artifact.lastSyncError = error
        artifact.serverUpdatedAt = syncState == .synced ? .now : artifact.serverUpdatedAt
        artifact.localUpdatedAt = .now
        objectWillChange.send()
        persist()
    }

    private func markExtractionJob(
        _ job: LocalExtractionJob,
        serverID: String?,
        sourceArtifactID: String,
        status: ExtractionStatus,
        attemptCount: Int,
        syncState: SyncState,
        error: String?
    ) {
        if let serverID {
            job.serverID = serverID
        }
        job.sourceArtifactID = sourceArtifactID
        job.statusRaw = status.rawValue
        job.attemptCount = attemptCount
        job.syncStateRaw = syncState.rawValue
        job.lastSyncError = error
        job.errorCode = error == nil ? nil : "enqueue_failed"
        job.errorMessage = error
        job.serverUpdatedAt = syncState == .synced ? .now : job.serverUpdatedAt
        job.localUpdatedAt = .now
        job.updatedAt = .now
        objectWillChange.send()
        persist()
    }

    private func applyExtractionResult(_ result: ExtractionJobResult) {
        guard let job = extractionJob(matching: result.extractionJobID) else { return }

        job.serverID = result.extractionJobID
        job.statusRaw = result.status.rawValue
        job.attemptCount = result.attemptCount
        job.providerStepsJSON = encodedJSON(result.providerSteps)
        job.extractedCandidatesJSON = encodedJSON(result.candidates)
        job.confidence = result.confidence
        job.errorCode = result.errorCode
        job.errorMessage = result.errorMessage
        job.syncStateRaw = SyncState.synced.rawValue
        job.lastSyncError = nil
        job.serverUpdatedAt = .now
        job.localUpdatedAt = .now
        job.updatedAt = .now

        analytics.track(
            AnalyticsEvent(
                name: result.status == .failed || result.status == .noPlaceFound
                    ? WanderAnalyticsEvents.extractionJobFailed
                    : WanderAnalyticsEvents.extractionJobCompleted,
                properties: [
                    "source_type": job.sourceType,
                    "status": result.status.rawValue,
                    "candidate_count": "\(result.candidates.count)"
                ]
            )
        )
        objectWillChange.send()
        persist()
    }

    private func providerSteps(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([String].self, from: data)
        else {
            return ["queued_for_backend_extraction"]
        }

        return steps.isEmpty ? ["queued_for_backend_extraction"] : steps
    }

    private func encodedJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return encoded
    }

    private func replaceAttributes(for userPlaceID: String, with drafts: [PlaceAttributeDraft], syncState: SyncState) {
        placeAttributes.removeAll { $0.userPlaceID == userPlaceID }

        let uniqueDrafts = Dictionary(grouping: drafts, by: \.questionKey)
            .compactMap { $0.value.last }
            .sorted { $0.questionKey < $1.questionKey }

        for draft in uniqueDrafts where draft.valueJSON != "null" {
            placeAttributes.append(
                LocalPlaceAttribute(
                    localID: "local_attr_\(slug(userPlaceID))_\(slug(draft.questionKey))",
                    userPlaceID: userPlaceID,
                    questionKey: draft.questionKey,
                    valueType: draft.valueType,
                    valueJSON: draft.valueJSON,
                    syncState: syncState
                )
            )
        }
    }

    private func ratingSignal(from attributes: [PlaceAttributeDraft]) -> String? {
        guard let rating = attributes.first(where: { $0.questionKey == "rating_signal" }),
              let data = rating.valueJSON.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(String.self, from: data)
    }

    private func tagTokens(for visiblePlace: VisiblePlace) -> Set<String> {
        let attributeText = attributes(for: visiblePlace.userPlace.id)
            .map(\.valueJSON)
            .joined(separator: " ")
        let value = [
            visiblePlace.place.category,
            visiblePlace.place.locality,
            visiblePlace.place.region,
            visiblePlace.userPlace.note,
            attributeText
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return Set(
            value
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    private func slug(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private func normalizedParseCacheKey(_ query: String, schema: DiscoverFilterSchema) -> String {
        let normalizedQuery = query
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let schemaFingerprint = [
            schema.allowedCategories.sorted().joined(separator: ","),
            schema.allowedStatuses.map(\.rawValue).sorted().joined(separator: ","),
            schema.allowedRelationships.map(\.rawValue).sorted().joined(separator: ","),
            schema.allowedTags.sorted().joined(separator: ",")
        ].joined(separator: "|")
        return "v2|\(stableHash(schemaFingerprint))|\(normalizedQuery)"
    }

    private func cacheDiscoverParse(
        _ filters: DiscoverFilters,
        source: DiscoverParseSource,
        key: String
    ) {
        if discoverParseCache[key] == nil,
           discoverParseCache.count >= Self.discoverParseCacheCapacity,
           let oldestKey = discoverParseCacheOrder.first {
            discoverParseCache.removeValue(forKey: oldestKey)
            discoverParseCacheOrder.removeFirst()
        }
        discoverParseCache[key] = CachedDiscoverParse(filters: filters, source: source)
        touchDiscoverParseCacheKey(key)
    }

    private func touchDiscoverParseCacheKey(_ key: String) {
        discoverParseCacheOrder.removeAll { $0 == key }
        discoverParseCacheOrder.append(key)
    }

    private func normalizedSourceInput(originalInput: String?, localAssetRef: String?) -> String {
        let value = originalInput?.isEmpty == false ? originalInput ?? "" : localAssetRef ?? ""
        return value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stableHash(_ value: String) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(hash, radix: 16)
    }

    private func matchesArea(_ area: String?, visiblePlace: VisiblePlace) -> Bool {
        let area = normalizedDiscoverText(area)
        guard !area.isEmpty else { return true }
        let haystack = [
            visiblePlace.place.address,
            visiblePlace.place.locality,
            visiblePlace.place.region,
            visiblePlace.place.canonicalName
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if area == "la" {
            let tokens = Set(
                haystack
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
            )
            return haystack.contains("los angeles") || tokens.contains("la")
        }
        return haystack.contains(area)
    }

    private func matchesOwner(_ ownerQuery: String?, visiblePlace: VisiblePlace) -> Bool {
        guard let ownerQuery = ownerQuery?
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !ownerQuery.isEmpty
        else {
            return true
        }

        let normalizedOwnerQuery = normalizedDiscoverText(ownerQuery)
        let normalizedHandle = normalizedDiscoverText(visiblePlace.owner.handle)
        let normalizedName = normalizedDiscoverText(visiblePlace.owner.displayName)
        if normalizedHandle == normalizedOwnerQuery || normalizedName == normalizedOwnerQuery {
            return true
        }

        guard !ownerQuery.contains("@"),
              !normalizedOwnerQuery.contains(" "),
              normalizedOwnerQuery.hasSuffix("s")
        else { return false }
        let possessiveBase = String(normalizedOwnerQuery.dropLast())
        return normalizedHandle == possessiveBase || normalizedName == possessiveBase
    }

    private func matchesTags(_ tags: Set<String>, visiblePlace: VisiblePlace) -> Bool {
        guard !tags.isEmpty else { return true }
        let attributeText = attributes(for: visiblePlace.userPlace.id)
            .map(\.valueJSON)
            .joined(separator: " ")
        let haystack = [
            visiblePlace.userPlace.note,
            attributeText
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return tags.allSatisfy { tag in
            haystack.contains(tag.lowercased())
        }
    }

    private func matchesOpinion(_ opinion: DiscoverOpinion?, visiblePlace: VisiblePlace) -> Bool {
        guard opinion == .favorite else { return true }
        guard visiblePlace.userPlace.status == .been else { return false }

        if let ratingScore = visiblePlace.userPlace.ratingScore, ratingScore >= 4 {
            return true
        }

        return hasFavoriteLabel(visiblePlace)
    }

    private func hasFavoriteLabel(_ visiblePlace: VisiblePlace) -> Bool {
        attributes(for: visiblePlace.userPlace.id)
            .filter { $0.questionKey == PlaceMemoryAttributeKeys.personalLabels }
            .flatMap { PlaceAttributeValuePresentation.strings(from: $0.valueJSON) }
            .contains { label in
                normalizedDiscoverWords(label).contains("favorite")
            }
    }

    private func discoverMatchEvidence(
        for visiblePlace: VisiblePlace,
        filters: DiscoverFilters,
        searchEvidence: [TrustedPlaceSearchEvidence] = []
    ) -> DiscoverMatchEvidence {
        var items: [DiscoverEvidenceItem] = []

        if filters.ownerQuery != nil {
            items.append(
                DiscoverEvidenceItem(
                    kind: .owner,
                    displayValue: "\(visiblePlace.owner.displayName)'s save",
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        } else {
            items.append(
                DiscoverEvidenceItem(
                    kind: .owner,
                    displayValue: visiblePlace.owner.displayName,
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        }

        if filters.opinion == .favorite {
            items.append(
                DiscoverEvidenceItem(
                    kind: .opinion,
                    displayValue: "favorite",
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
            if let ratingScore = visiblePlace.userPlace.ratingScore, ratingScore >= 4 {
                items.append(
                    DiscoverEvidenceItem(
                        kind: .rating,
                        displayValue: "\(PlaceRating.averageDisplay(ratingScore))/5",
                        sourceOwnerID: visiblePlace.owner.id
                    )
                )
            } else if hasFavoriteLabel(visiblePlace) {
                items.append(
                    DiscoverEvidenceItem(
                        kind: .personalLabel,
                        displayValue: "favorite label",
                        sourceOwnerID: visiblePlace.owner.id
                    )
                )
            }
        }

        items.append(contentsOf: filters.tags.sorted().map { tag in
            DiscoverEvidenceItem(kind: .tag, displayValue: tag, sourceOwnerID: visiblePlace.owner.id)
        })

        if !filters.categories.isEmpty {
            items.append(
                DiscoverEvidenceItem(
                    kind: .category,
                    displayValue: visiblePlace.effectiveCompactType,
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        }

        if filters.area != nil,
           let locality = visiblePlace.place.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty {
            items.append(
                DiscoverEvidenceItem(
                    kind: .area,
                    displayValue: locality,
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        }

        if filters.opinion == nil, filters.statuses.contains(visiblePlace.userPlace.status) {
            items.append(
                DiscoverEvidenceItem(
                    kind: .status,
                    displayValue: visiblePlace.userPlace.status.displayTitle,
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        }

        if let relationship = filters.relationship {
            let title: String
            switch relationship {
            case .owner: title = "mine"
            case .mutual: title = "friend"
            case .follower: title = "following"
            case .nonFollower: title = "other person"
            }
            items.append(
                DiscoverEvidenceItem(
                    kind: .relationship,
                    displayValue: title,
                    sourceOwnerID: visiblePlace.owner.id
                )
            )
        }

        items.append(contentsOf: searchEvidence.compactMap { evidence in
            let kind: DiscoverEvidenceKind
            switch evidence.field {
            case .name: kind = .name
            case .owner: kind = .owner
            case .category: kind = .category
            case .area: kind = .area
            case .note: kind = .note
            case .attribute: kind = .attribute
            case .status: kind = .status
            }
            guard !items.contains(where: { $0.kind == kind && $0.displayValue == evidence.displayValue }) else {
                return nil
            }
            return DiscoverEvidenceItem(
                kind: kind,
                displayValue: evidence.displayValue,
                sourceOwnerID: visiblePlace.owner.id
            )
        })

        return DiscoverMatchEvidence(
            userPlaceID: visiblePlace.userPlace.id,
            ownerID: visiblePlace.owner.id,
            ownerName: visiblePlace.owner.displayName,
            note: visiblePlace.userPlace.note,
            ratingScore: visiblePlace.userPlace.ratingScore,
            items: items
        )
    }

    private func normalizedDiscoverText(_ value: String?) -> String {
        let normalized = (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.replacingOccurrences(
            of: #"\s+s$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func normalizedDiscoverWords(_ value: String) -> Set<String> {
        Set(
            normalizedDiscoverText(value)
                .split(separator: " ")
                .map(String.init)
        )
    }
}

extension WanderStore: PhotoPlaceCandidateSearching {}

private extension AddSourceType {
    var createsSourceArtifact: Bool {
        switch self {
        case .link, .photo:
            true
        case .currentLocation, .manual, .socialSave:
            false
        }
    }

    var sourceArtifactType: String {
        switch self {
        case .link:
            "url"
        case .photo:
            "image"
        case .currentLocation:
            "current_location"
        case .manual, .socialSave:
            "text"
        }
    }
}
