import CoreLocation
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
    var ownerIDs: Set<String> = []
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
    var websiteURLString: String? = nil
    var phoneNumber: String? = nil
    var timeZoneIdentifier: String? = nil
    var actionLinksJSON: String? = nil
    let confidence: Double
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
        let category = includeCategory && !self.category.isEmpty && self.category != "place" ? self.category : nil
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
