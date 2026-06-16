import Foundation

struct ProfileShell: Identifiable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let bio: String?
    let relationship: ViewerRelationship
}

struct ProfileViewState {
    let shell: ProfileShell
    let visiblePlaces: [VisiblePlace]
    let canFollow: Bool
    let canBlock: Bool
    let isBlocked: Bool
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
    var address: String? = nil
    var locality: String? = nil
    var region: String? = nil
    var country: String? = nil
    let latitude: Double?
    let longitude: Double?
    var sourceProvider: String = "mapkit"
    var sourceProviderPlaceID: String? = nil
    var distanceMeters: Double? = nil
    let confidence: Double
}

struct PlaceDraft: Equatable {
    let localID: String
    let serverID: String?
    let canonicalName: String
    let category: String
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String?
    let confidence: Double?
}

struct UserPlaceDraft: Equatable {
    let place: PlaceDraft
    let status: PlaceStatus
    let visibility: PlaceVisibility
    let note: String?
    let ratingSignal: String?
    let nearbyConfirmed: Bool
    let sourceType: String
    let attributes: [PlaceAttributeDraft]
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

@MainActor
protocol ProfileRepository {
    func currentProfile() async throws -> LocalProfile?
    func profile(id: String) async throws -> ProfileViewState
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell]
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
protocol PlaceCandidateResolving {
    func resolveCurrentLocation() async throws -> [PlaceCandidate]
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
protocol ExtractionRepository {
    func enqueue(_ draft: ExtractionJobDraft) async throws -> ExtractionJobEnqueueResult
    func process(jobID: String) async throws -> ExtractionJobResult
    func result(jobID: String) async throws -> ExtractionJobResult
}

@MainActor
protocol DiscoverRepository {
    func parseFilters(query: String) async throws -> DiscoverFilters
    func search(filters: DiscoverFilters) async throws -> DiscoverResults
}
