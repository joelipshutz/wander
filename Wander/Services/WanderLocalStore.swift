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

private struct LocalRemoveSaveChange {
    let userPlaceID: String
    let removedUserPlaceIDs: [String]
    let remoteUserPlaceIDs: [String]
    let syncState: SyncState
}

struct ProfileStats: Equatable {
    let been: Int
    let wanna: Int
    let friends: Int
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
    @Published private(set) var follows: [LocalFollow]
    @Published private(set) var blocks: [LocalBlock]
    @Published private(set) var placeLists: [LocalPlaceList]
    @Published private(set) var placeListMembers: [LocalPlaceListMember]
    @Published private(set) var placeListItems: [LocalPlaceListItem]
    @Published private(set) var unresolvedDrafts: [UnresolvedDraft] = []
    @Published private(set) var sourceArtifacts: [LocalSourceArtifact] = []
    @Published private(set) var extractionJobs: [LocalExtractionJob] = []
    @Published private(set) var remoteVisiblePlaceCache: [VisiblePlace] = []
    @Published private(set) var lastRemoteError: String?
    @Published private(set) var lastDiscoverFilters = DiscoverFilters(query: "")
    @Published var defaultVisibility: PlaceVisibility {
        didSet {
            currentUser.defaultVisibilityRaw = defaultVisibility.rawValue
            currentUser.updatedAt = .now
            currentUser.localUpdatedAt = .now
            persist()
        }
    }
    @Published var isPrivateProfile: Bool {
        didSet {
            currentUser.isPrivateProfile = isPrivateProfile
            currentUser.updatedAt = .now
            currentUser.localUpdatedAt = .now
            persist()
        }
    }
    @Published var autoSaveListAddsToWant: Bool {
        didSet {
            persist()
        }
    }

    let contactProvider: FakeContactProvider

    private let visibilityPolicy = VisibilityPolicy()
    private let parser: any LLMFilterParser
    private let placeResolver: PlaceCandidateResolving
    private let analytics: AnalyticsClient
    private let persistence: WanderStorePersistence?
    private var discoverParseCache: [String: DiscoverFilters] = [:]
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
            self.follows = restored.follows
            self.blocks = restored.blocks
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
            shouldPersistAfterRestore = restored.didApplySavedPlaceReset
        } else {
            self.currentUser = fixtures.currentUser
            self.profiles = fixtures.profiles
            self.places = fixtures.places
            self.userPlaces = fixtures.userPlaces
            self.placeAttributes = fixtures.placeAttributes
            self.follows = fixtures.follows
            self.blocks = fixtures.blocks
            self.placeLists = fixtures.placeLists
            self.placeListMembers = fixtures.placeListMembers
            self.placeListItems = fixtures.placeListItems
            self.contactProvider = fixtures.contactProvider
            self.defaultVisibility = fixtures.currentUser.defaultVisibility
            self.isPrivateProfile = fixtures.currentUser.isPrivateProfile
            self.autoSaveListAddsToWant = true
        }

        self.currentUser.isPrivateProfile = self.isPrivateProfile
        self.currentUser.defaultVisibilityRaw = self.defaultVisibility.rawValue

        if shouldPersistAfterRestore {
            persist()
        }
    }

    private func persist() {
        guard let persistence else { return }
        persistence.save(WanderStoreSnapshot(store: self))
    }

    func apply(authState: AuthState) {
        switch authState {
        case .signedIn(let session):
            apply(session: session)
            analytics.identify(userID: session.userID)
            #if DEBUG
            WanderDebugLog.sync.debug("store auth signed_in user=\(WanderDebugLog.shortID(session.userID), privacy: .public) pending_sync_count=\(self.pendingSyncCount, privacy: .public)")
            #endif
        case .signedOut, .unavailable:
            applySignedOutProfile()
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

    var stats: ProfileStats {
        let mine = userPlaces.filter { $0.userID == currentUser.id && $0.deletedAt == nil }
        return ProfileStats(
            been: mine.filter { $0.status == .been }.count,
            wanna: mine.filter { $0.status == .wannaGo }.count,
            friends: profiles.filter { relationship(to: $0.id) == .mutual }.count
        )
    }

    var pendingSyncCount: Int {
        let pendingUserPlaces = userPlaces.filter { $0.syncState != .synced }.count
        let pendingAttributes = placeAttributes.filter { $0.syncState != .synced }.count
        let pendingArtifacts = sourceArtifacts.filter { SyncState(rawValue: $0.syncStateRaw) != .synced }.count
        let pendingJobs = extractionJobs.filter { SyncState(rawValue: $0.syncStateRaw) != .synced }.count

        return pendingUserPlaces
            + pendingAttributes
            + pendingArtifacts
            + pendingJobs
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

    var currentUserVisiblePlaces: [VisiblePlace] {
        visiblePlaces(filters: PlaceFilters(ownerScopes: ["you"]))
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
                return list.ownerUserID == currentUser.id
            case .friends:
                return list.ownerUserID != currentUser.id && !isMember(of: list, userID: currentUser.id)
            case .collabs:
                return list.ownerUserID != currentUser.id && isMember(of: list, userID: currentUser.id)
            }
        }
    }

    func canManage(_ list: LocalPlaceList) -> Bool {
        list.ownerUserID == currentUser.id
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
        return listItems(for: list).compactMap { item in
            candidates.first { visiblePlace in
                visiblePlace.userPlace.id == item.ownerUserPlaceID
                    || visiblePlace.userPlace.id == item.sourceUserPlaceID
                    || visiblePlace.place.id == item.placeID
            }
        }
    }

    func hasPlace(_ visiblePlace: VisiblePlace, in list: LocalPlaceList) -> Bool {
        listItems(for: list).contains { item in
            item.placeID == visiblePlace.place.id
                || item.ownerUserPlaceID == visiblePlace.userPlace.id
                || item.sourceUserPlaceID == visiblePlace.userPlace.id
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
        guard canManage(list) else {
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
            placeLists[index].syncStateRaw = SyncState.pendingUpdate.rawValue
        }
        persist()
        return ListPlaceAddResult(outcome: .added, createdWantSave: createdWantSave, shouldExplainAutoSave: createdWantSave)
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
        guard !trimmedName.isEmpty else { return nil }

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
        for memberIndex in placeListMembers.indices where placeListMembers[memberIndex].listID == listID {
            let memberUserID = placeListMembers[memberIndex].userID
            if allowedUserIDs.contains(memberUserID) {
                placeListMembers[memberIndex].deletedAt = nil
                placeListMembers[memberIndex].roleRaw = PlaceListRole.collaborator.rawValue
            } else {
                placeListMembers[memberIndex].deletedAt = .now
            }
        }

        let existingUserIDs = Set(placeListMembers.filter { $0.listID == listID }.map(\.userID))
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
        placeListMembers.contains { member in
            member.listID == list.id && member.userID == userID && member.deletedAt == nil
        }
    }

    private func listItems(for list: LocalPlaceList) -> [LocalPlaceListItem] {
        placeListItems
            .filter { $0.listID == list.id && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
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
        mergeVisiblePlaces(localVisiblePlaces(filters: filters) + remoteVisiblePlaces(filters: filters))
    }

    private func localVisiblePlaces(filters: PlaceFilters = PlaceFilters()) -> [VisiblePlace] {
        userPlaces.compactMap { userPlace -> VisiblePlace? in
            guard userPlace.deletedAt == nil,
                  let place = places.first(where: { $0.id == userPlace.placeID }),
                  let owner = profiles.first(where: { $0.id == userPlace.userID })
            else { return nil }

            let relationship = relationship(to: owner.id)
            let blocked = isBlockedBetweenCurrentUser(and: owner.id)
            guard visibilityPolicy.canSeePlace(
                viewerID: currentUser.id,
                ownerID: owner.id,
                visibility: userPlace.visibility,
                relationship: relationship,
                isBlocked: blocked
            ) else { return nil }

            let visiblePlace = VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
            guard filters.statuses.isEmpty || filters.statuses.contains(userPlace.status) else { return nil }
            let normalizedCategories = filters.normalizedCategories
            guard normalizedCategories.isEmpty || normalizedCategories.contains(visiblePlace.effectiveCategory) else { return nil }
            guard filters.ownerIDs.isEmpty || filters.ownerIDs.contains(owner.id) else { return nil }

            if !filters.ownerScopes.isEmpty {
                let isMine = owner.id == currentUser.id
                let isFriend = relationship == .mutual
                let isFollowing = relationship == .follower || relationship == .mutual
                let allowed = (filters.ownerScopes.contains("you") && isMine)
                    || (filters.ownerScopes.contains("friends") && isFriend)
                    || (filters.ownerScopes.contains("following") && isFollowing && !isMine)
                    || (filters.ownerScopes.contains("social") && !isMine)
                guard allowed else { return nil }
            }

            return visiblePlace
        }
    }

    private func remoteVisiblePlaces(filters: PlaceFilters) -> [VisiblePlace] {
        remoteVisiblePlaceCache.filter { visiblePlace in
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

    private func mergeVisiblePlaces(_ places: [VisiblePlace]) -> [VisiblePlace] {
        var seen = Set<String>()
        var merged: [VisiblePlace] = []

        for visiblePlace in places where !seen.contains(visiblePlace.id) {
            seen.insert(visiblePlace.id)
            merged.append(visiblePlace)
        }

        return merged
    }

    func visiblePlaces(for profileID: String) -> [VisiblePlace] {
        visiblePlaces().filter { $0.owner.id == profileID }
    }

    func attributes(for userPlaceID: String) -> [LocalPlaceAttribute] {
        let userPlaceIDs = matchingUserPlaceIDs(userPlaceID)
        return placeAttributes
            .filter { userPlaceIDs.contains($0.userPlaceID) }
            .sorted { $0.questionKey < $1.questionKey }
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

    func relationship(to userID: String) -> ViewerRelationship {
        if userID == currentUser.id { return .owner }
        guard !isBlockedBetweenCurrentUser(and: userID) else { return .nonFollower }

        let iFollowThem = follows.contains { $0.followerUserID == currentUser.id && $0.followedUserID == userID }
        let theyFollowMe = follows.contains { $0.followerUserID == userID && $0.followedUserID == currentUser.id }

        if iFollowThem && theyFollowMe { return .mutual }
        if iFollowThem { return .follower }
        return .nonFollower
    }

    func shell(for profile: LocalProfile) -> ProfileShell {
        ProfileShell(
            id: profile.id,
            handle: profile.handle,
            displayName: profile.displayName,
            avatarURL: profile.avatarURL,
            bio: profile.bio,
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
                upsertRemoteProfileShells(remoteProfiles)
                profiles = mergeProfileShells(profiles + remoteProfiles)
                lastRemoteError = nil
            } catch {
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        return profiles
    }

    func contactMatches() async -> [ContactMatch] {
        let matches = (try? await contactProvider.matches()) ?? []
        return matches.filter { match in
            guard let userID = match.userID else { return false }
            return !isBlockedBetweenCurrentUser(and: userID)
                && !isProfilePrivate(userID)
        }
    }

    func parseDiscover(query: String) async -> DiscoverFilters {
        let cacheKey = normalizedParseCacheKey(query)
        if let cached = discoverParseCache[cacheKey] {
            lastDiscoverFilters = cached
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverQueryParsed,
                    properties: ["source": "cache", "chip_count": "\(cached.chips.count)"]
                )
            )
            return cached
        }

        let schema = DiscoverFilterSchema()

        do {
            let filters = try await parser.parse(query: query, schema: schema)
            discoverParseCache[cacheKey] = filters
            lastDiscoverFilters = filters
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverQueryParsed,
                    properties: ["source": "parser", "chip_count": "\(filters.chips.count)"]
                )
            )
            return filters
        } catch {
            let fallback = DiscoverFilters(query: query)
            lastDiscoverFilters = fallback
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.discoverParseFailed,
                    properties: ["error": remoteErrorMessage(error)]
                )
            )
            return fallback
        }
    }

    func discover(query: String, scope: DiscoverPlaceScope = .everyone, backend: WanderBackend? = nil) async -> DiscoverResults {
        let filters = await parseDiscover(query: query)
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

        let places = visiblePlaces(filters: placeFilters)
            .filter { visiblePlace in
                matchesArea(filters.area, visiblePlace: visiblePlace)
                    && matchesOwner(filters.ownerQuery, visiblePlace: visiblePlace)
                    && matchesTags(filters.tags, visiblePlace: visiblePlace)
            }
        var profiles = searchProfiles(handleQuery: query)
        let normalizedProfileQuery = normalizedHandleQuery(query)

        if normalizedProfileQuery.count >= 2, let backend {
            do {
                let remoteProfiles = try await backend.searchProfiles(handleQuery: normalizedProfileQuery)
                upsertRemoteProfileShells(remoteProfiles)
                profiles = mergeProfileShells(profiles + remoteProfiles)
                lastRemoteError = nil
            } catch {
                lastRemoteError = remoteErrorMessage(error)
            }
        }

        return DiscoverResults(places: places, profiles: profiles)
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
        ratingScore: Int? = nil,
        attributes: [PlaceAttributeDraft]? = nil
    ) -> SaveResult {
        let resolvedVisibility = visibilityForSave(visibility)
        let place = upsertPlace(from: candidate, sourceType: sourceType)
        let savedRatingScore = PlaceRating.scoreForSave(status: status, score: ratingScore)
        let categoryOverride = categoryOverrideAssignment(from: candidate)

        if let existing = userPlaces.first(where: { $0.userID == currentUser.id && $0.placeID == place.id && $0.deletedAt == nil }) {
            existing.statusRaw = status.rawValue
            existing.visibilityRaw = resolvedVisibility.rawValue
            existing.note = note
            existing.ratingScore = savedRatingScore
            existing.recommendedScore = savedRatingScore.map(Double.init)
            existing.recommendedCount = savedRatingScore == nil ? 0 : 1
            applyCategoryOverride(categoryOverride, to: existing)
            if let attributes {
                existing.ratingSignal = ratingSignal(from: attributes)
                replaceAttributes(for: existing.id, with: attributes, syncState: .pendingUpdate)
            }
            existing.updatedAt = .now
            existing.localUpdatedAt = .now
            existing.syncStateRaw = SyncState.pendingUpdate.rawValue
            objectWillChange.send()
            persist()
            return SaveResult(userPlaceID: existing.id, syncState: existing.syncState)
        }

        let userPlace = LocalUserPlace(
            localID: "local_up_\(currentUser.handle)_\(slug(place.canonicalName))",
            userID: currentUser.id,
            placeID: place.id,
            status: status,
            visibility: resolvedVisibility,
            note: note,
            ratingSignal: attributes.flatMap { ratingSignal(from: $0) },
            ratingScore: savedRatingScore,
            recommendedScore: savedRatingScore.map(Double.init),
            recommendedCount: savedRatingScore == nil ? 0 : 1,
            categoryOverride: categoryOverride?.primaryCategory,
            subcategoryOverride: categoryOverride?.subcategory,
            categoryOverrideSource: categoryOverride?.source,
            categoryOverrideConfidence: categoryOverride?.confidence,
            nearbyConfirmed: sourceType == .currentLocation,
            sourceType: sourceType.rawValue,
            syncState: .pendingCreate
        )
        userPlaces.append(userPlace)
        if let attributes {
            replaceAttributes(for: userPlace.id, with: attributes, syncState: .pendingCreate)
        }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.placeSaved,
                properties: ["source_type": sourceType.rawValue, "visibility": resolvedVisibility.rawValue, "status": status.rawValue]
            )
        )
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
        ratingScore: Int? = nil,
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
            attributes: attributes
        )
        #if DEBUG
        WanderDebugLog.sync.debug("direct save local row user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public) local_sync_state=\(localResult.syncState.rawValue, privacy: .public)")
        #endif

        guard let backend else {
            #if DEBUG
            WanderDebugLog.sync.debug("direct save skipped remote reason=missing_backend user_place=\(WanderDebugLog.shortID(localResult.userPlaceID), privacy: .public)")
            #endif
            return localResult
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

        let retryableIDs = syncableOwnPlaceIDs { syncState in
            syncState == .failed
        }
        #if DEBUG
        WanderDebugLog.sync.debug("failed retry candidates count=\(retryableIDs.count, privacy: .public) states=\(self.syncCandidateStateSummary(), privacy: .public)")
        #endif
        return await syncOwnPlaces(withIDs: retryableIDs, backend: backend, trigger: .failedRetry)
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

        let syncableIDs = syncableOwnPlaceIDs { syncState in
            syncState != .synced
                && syncState != .pendingDelete
                && syncState != .serverDenied
                && syncState != .tombstoned
        }
        #if DEBUG
        WanderDebugLog.sync.debug("signed-in backfill candidates count=\(syncableIDs.count, privacy: .public) states=\(self.syncCandidateStateSummary(), privacy: .public)")
        #endif
        return await syncOwnPlaces(withIDs: syncableIDs, backend: backend, trigger: .signedInBackfill)
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
            switch await retryOwnPlaceSync(userPlaceID: userPlaceID, backend: backend, trigger: trigger) {
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
    func saveVisiblePlace(_ visiblePlace: VisiblePlace, status: PlaceStatus = .wannaGo, backend: WanderBackend?) async -> SaveResult {
        let localResult = saveVisiblePlace(visiblePlace, status: status)

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
        persist()
    }

    func follow(userID: String, source: FollowSource = .profile, backend: WanderBackend?) async {
        let follow = upsertFollow(userID: userID, source: source)

        guard let follow else {
            return
        }

        guard let backend else {
            persist()
            return
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
        } catch {
            follow.syncStateRaw = SyncState.failed.rawValue
            follow.lastSyncError = remoteErrorMessage(error)
            lastRemoteError = follow.lastSyncError
            objectWillChange.send()
            persist()
        }
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
            remoteVisiblePlaceCache = visiblePlaces
            hydrateRemoteVisiblePlaceMetadata(visiblePlaces)
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func refreshRemoteCurrentProfile(backend: WanderBackend?) async {
        guard let backend else {
            return
        }

        do {
            if let profile = try await backend.currentProfile() {
                applyRemoteCurrentProfile(profile)
            }
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
    }

    func refreshRemoteVisiblePlaces(backend: WanderBackend?) async {
        await refreshRemoteVisiblePlaces(in: Self.defaultRemoteViewport, backend: backend)
    }

    func refreshRemoteSocialSurfaces(backend: WanderBackend?) async {
        await refreshRemoteSocialSurfaces(in: Self.defaultRemoteViewport, backend: backend)
    }

    func refreshRemoteSocialSurfaces(in viewport: MapViewport, backend: WanderBackend?) async {
        guard backend != nil else {
            return
        }

        let locallyFollowedProfileIDs = Set(following(of: currentUser.id).map(\.id))
        await refreshRemoteSocialGraph(backend: backend)
        await refreshRemoteVisiblePlaces(in: viewport, backend: backend)

        let followedProfileIDs = locallyFollowedProfileIDs
            .union(following(of: currentUser.id).map(\.id))
            .subtracting([currentUser.id])
            .sorted()
        for profileID in followedProfileIDs {
            await refreshRemoteProfileVisiblePlaces(profileID: profileID, backend: backend)
        }
    }

    func refreshRemoteProfileVisiblePlaces(profileID: String, backend: WanderBackend?) async {
        guard let backend else {
            return
        }

        do {
            let visiblePlaces = try await backend.userPlaces(for: profileID)
            remoteVisiblePlaceCache.removeAll { $0.owner.id == profileID }
            remoteVisiblePlaceCache.append(contentsOf: visiblePlaces)
            hydrateRemoteVisiblePlaceMetadata(visiblePlaces)
            try await refreshRemoteRelationship(to: profileID, backend: backend)
            lastRemoteError = nil
        } catch {
            lastRemoteError = remoteErrorMessage(error)
        }
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
        let handle = normalizedSessionHandle(from: session)
        let displayName = normalizedSessionDisplayName(from: session, fallbackHandle: handle)
        let localID = "local_profile_current"
        let preferredVisibility = defaultVisibility
        let preferredPrivateProfile = isPrivateProfile
        let profile = LocalProfile(
            localID: localID,
            serverID: session.userID,
            handle: handle,
            displayName: displayName,
            avatarURL: previousCurrentUser.avatarURL,
            isPrivateProfile: preferredPrivateProfile,
            syncState: .synced
        )
        profile.defaultVisibilityRaw = preferredVisibility.rawValue

        currentUser = profile
        profiles.removeAll { $0.localID == localID || $0.serverID == session.userID }
        profiles.insert(profile, at: 0)
        claimGuestRowsIfNeeded(from: previousCurrentUser, to: profile)
        defaultVisibility = preferredVisibility
        isPrivateProfile = preferredPrivateProfile
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

        guard didClaimRows else { return }
        objectWillChange.send()
        persist()
    }

    private func applySignedOutProfile() {
        let previousCurrentUser = currentUser
        let localID = "local_profile_current"
        let preferredVisibility = defaultVisibility
        let preferredPrivateProfile = isPrivateProfile
        let profile = LocalProfile(
            localID: localID,
            handle: "you",
            displayName: "You",
            avatarURL: previousCurrentUser.avatarURL,
            isPrivateProfile: preferredPrivateProfile,
            syncState: .localOnly
        )
        profile.defaultVisibilityRaw = preferredVisibility.rawValue

        currentUser = profile
        profiles.removeAll { $0.localID == localID }
        profiles.insert(profile, at: 0)
        defaultVisibility = preferredVisibility
        isPrivateProfile = preferredPrivateProfile
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
            sourceType: userPlace.sourceType,
            attributes: attributeDrafts
        )
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
        objectWillChange.send()
        persist()
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
            userPlace.deletedAt = now
            userPlace.updatedAt = now
            userPlace.localUpdatedAt = now
            userPlace.lastSyncError = nil
            userPlace.syncStateRaw = rowSyncState.rawValue
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

        var removedUserPlaceIDs = Set<String>()
        var remoteUserPlaceIDs = Set<String>()
        for visiblePlace in matchingVisiblePlaces {
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

    private func hydrateRemoteVisiblePlaceMetadata(_ visiblePlaces: [VisiblePlace]) {
        let shells = visiblePlaces.map { visiblePlace in
            ProfileShell(
                id: visiblePlace.owner.id,
                handle: visiblePlace.owner.handle,
                displayName: visiblePlace.owner.displayName,
                avatarURL: visiblePlace.owner.avatarURL,
                bio: visiblePlace.owner.bio,
                relationship: relationship(to: visiblePlace.owner.id)
            )
        }
        upsertRemoteProfileShells(shells)
        upsertRemoteAttributes(from: visiblePlaces)
    }

    private func applyRemoteCurrentProfile(_ remoteProfile: LocalProfile) {
        objectWillChange.send()

        let now = Date()
        let currentLocalID = currentUser.localID
        let currentProfileID = remoteProfile.id

        currentUser.serverID = remoteProfile.serverID ?? remoteProfile.localID
        currentUser.handle = remoteProfile.handle
        currentUser.searchHandle = remoteProfile.handle.lowercased()
        currentUser.displayName = remoteProfile.displayName
        currentUser.avatarURL = remoteProfile.avatarURL
        currentUser.bio = remoteProfile.bio
        currentUser.homeArea = remoteProfile.homeArea
        currentUser.defaultVisibilityRaw = remoteProfile.defaultVisibility.rawValue
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
            profile.defaultVisibilityRaw = currentUser.defaultVisibilityRaw
            profile.syncStateRaw = SyncState.synced.rawValue
            profile.serverUpdatedAt = now
            profile.updatedAt = now
        }

        defaultVisibility = remoteProfile.defaultVisibility
        persist()
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
        upsertRemoteProfileShells(following + followers)

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

    private func upsertRemoteProfileShells(_ shells: [ProfileShell]) {
        for shell in shells where shell.id != currentUser.id && !isBlockedBetweenCurrentUser(and: shell.id) {
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
                        localID: "remote_profile_\(shell.id)",
                        serverID: shell.id,
                        handle: shell.handle,
                        displayName: shell.displayName,
                        avatarURL: shell.avatarURL,
                        bio: shell.bio,
                        syncState: .synced
                    )
                )
            }
        }
        objectWillChange.send()
        persist()
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

    private func retryOwnPlaceSync(userPlaceID: String, backend: WanderBackend, trigger: OwnPlaceSyncTrigger) async -> OwnPlaceSyncOutcome {
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

        markUserPlace(localOrServerID: userPlaceID, syncState: .pendingUpdate, error: nil)
        do {
            let remoteResult = try await backend.saveUserPlace(draft)
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
            await refreshRemoteVisiblePlaces(backend: backend)
            return .succeeded
        } catch {
            let message = remoteErrorMessage(error)
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
        let sharedAssignment = sharedPlaceAssignment(from: candidate)
        if let existing = places.first(where: {
            $0.id == candidate.id
                || ($0.sourceProvider == candidate.sourceProvider && $0.sourceProviderPlaceID == providerPlaceID)
                || $0.canonicalName.caseInsensitiveCompare(candidate.name) == .orderedSame
        }) {
            mergeBusinessMetadata(from: candidate, sharedAssignment: sharedAssignment, into: existing)
            return existing
        }

        let place = LocalPlace(
            localID: "local_place_\(slug(candidate.name))",
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

    private func normalizedParseCacheKey(_ query: String) -> String {
        query
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let area, !area.isEmpty, area != "LA" else { return true }
        let haystack = [
            visiblePlace.place.address,
            visiblePlace.place.locality,
            visiblePlace.place.region,
            visiblePlace.place.canonicalName
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return haystack.contains(area.lowercased())
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

        return visiblePlace.owner.handle.lowercased().contains(ownerQuery)
            || visiblePlace.owner.displayName.lowercased().contains(ownerQuery)
    }

    private func matchesTags(_ tags: Set<String>, visiblePlace: VisiblePlace) -> Bool {
        guard !tags.isEmpty else { return true }
        let attributeText = attributes(for: visiblePlace.userPlace.id)
            .map(\.valueJSON)
            .joined(separator: " ")
        let haystack = [
            visiblePlace.place.canonicalName,
            visiblePlace.effectiveCategoryDisplay.compactTitle,
            visiblePlace.userPlace.note,
            attributeText
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        return tags.contains { tag in
            haystack.contains(tag.lowercased())
        }
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
