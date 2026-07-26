import Foundation

enum WanderNearbyWidgetAvailability: Equatable, Sendable {
    case ready
    case locationAuthorizationRequired
    case locationTemporarilyUnavailable
    case noPlaces
}

struct WanderNearbyWidgetFreshness: Equatable, Sendable {
    static let exactDistanceLifetime: TimeInterval = 30 * 60
    static let usableLifetime: TimeInterval = 24 * 60 * 60

    let age: TimeInterval

    init(generatedAt: Date, now: Date) {
        age = max(0, now.timeIntervalSince(generatedAt))
    }

    var showsExactDistance: Bool {
        age <= Self.exactDistanceLifetime
    }

    var isUsable: Bool {
        age <= Self.usableLifetime
    }

    var minuteAgeLabel: String {
        let wholeMinutes = Int(age / 60)
        switch wholeMinutes {
        case 0:
            return "updated <1 min ago"
        case 1:
            return "updated 1 min ago"
        default:
            return "updated \(wholeMinutes) mins ago"
        }
    }
}

enum WanderNearbyWidgetDistanceFormatter {
    static func string(meters: Double?) -> String? {
        guard let meters, meters.isFinite, meters >= 0 else { return nil }

        let feet = meters * 3.280_839_895
        if feet < 1_000 {
            let interval: Double
            switch feet {
            case ..<100:
                interval = 5
            case ..<500:
                interval = 10
            default:
                interval = 25
            }
            return "\(Int((feet / interval).rounded() * interval)) ft"
        }

        let miles = meters / 1_609.344
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }
}

struct WanderNearbyPlaceSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let categoryLabel: String
    let categoryEmoji: String
    let rawProviderType: String?
    let address: String?
    let locality: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceProvider: String
    let sourceProviderPlaceID: String
    let distanceMeters: Double?
    let websiteURLString: String?
    let phoneNumber: String?
    let timeZoneIdentifier: String?
    let confidence: Double

    init?(
        id: String,
        name: String,
        category: String,
        categoryLabel: String,
        categoryEmoji: String,
        rawProviderType: String? = nil,
        address: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        sourceProvider: String = "mapkit",
        sourceProviderPlaceID: String,
        distanceMeters: Double? = nil,
        websiteURLString: String? = nil,
        phoneNumber: String? = nil,
        timeZoneIdentifier: String? = nil,
        confidence: Double
    ) {
        guard Self.isValid(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            sourceProviderPlaceID: sourceProviderPlaceID,
            distanceMeters: distanceMeters,
            confidence: confidence
        ) else {
            return nil
        }

        self.id = id
        self.name = name
        self.category = category
        self.categoryLabel = categoryLabel
        self.categoryEmoji = categoryEmoji
        self.rawProviderType = rawProviderType
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
        self.confidence = confidence
    }

    func distanceLabel(
        generatedAt: Date,
        now: Date,
        allowsExactDistance: Bool = true
    ) -> String {
        let freshness = WanderNearbyWidgetFreshness(generatedAt: generatedAt, now: now)
        guard allowsExactDistance,
              freshness.showsExactDistance,
              let distance = WanderNearbyWidgetDistanceFormatter.string(meters: distanceMeters)
        else {
            return "near you"
        }
        return "\(distance) away"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case categoryLabel
        case categoryEmoji
        case rawProviderType
        case address
        case locality
        case region
        case country
        case latitude
        case longitude
        case sourceProvider
        case sourceProviderPlaceID
        case distanceMeters
        case websiteURLString
        case phoneNumber
        case timeZoneIdentifier
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let category = try container.decode(String.self, forKey: .category)
        let categoryLabel = try container.decode(String.self, forKey: .categoryLabel)
        let categoryEmoji = try container.decode(String.self, forKey: .categoryEmoji)
        let rawProviderType = try container.decodeIfPresent(String.self, forKey: .rawProviderType)
        let address = try container.decodeIfPresent(String.self, forKey: .address)
        let locality = try container.decodeIfPresent(String.self, forKey: .locality)
        let region = try container.decodeIfPresent(String.self, forKey: .region)
        let country = try container.decodeIfPresent(String.self, forKey: .country)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let sourceProvider = try container.decode(String.self, forKey: .sourceProvider)
        let sourceProviderPlaceID = try container.decode(String.self, forKey: .sourceProviderPlaceID)
        let distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        let websiteURLString = try container.decodeIfPresent(String.self, forKey: .websiteURLString)
        let phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        let timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        let confidence = try container.decode(Double.self, forKey: .confidence)

        guard Self.isValid(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            sourceProviderPlaceID: sourceProviderPlaceID,
            distanceMeters: distanceMeters,
            confidence: confidence
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Nearby widget place metadata is invalid."
            )
        }

        self.id = id
        self.name = name
        self.category = category
        self.categoryLabel = categoryLabel
        self.categoryEmoji = categoryEmoji
        self.rawProviderType = rawProviderType
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
        self.confidence = confidence
    }

    private static func isValid(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        sourceProviderPlaceID: String,
        distanceMeters: Double?,
        confidence: Double
    ) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceProviderPlaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && latitude.isFinite
            && (-90...90).contains(latitude)
            && longitude.isFinite
            && (-180...180).contains(longitude)
            && (
                distanceMeters == nil
                    || (distanceMeters?.isFinite == true && (distanceMeters ?? -1) >= 0)
            )
            && confidence.isFinite
            && (0...1).contains(confidence)
    }
}

struct WanderNearbyWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumVisiblePlaces = 5
    static let maximumRoutablePlaces = 25

    let schemaVersion: Int
    let generatedAt: Date
    let places: [WanderNearbyPlaceSnapshot]
    let recentPlaces: [WanderNearbyPlaceSnapshot]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date,
        places: [WanderNearbyPlaceSnapshot],
        recentPlaces: [WanderNearbyPlaceSnapshot] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.places = Self.unique(places, limit: Self.maximumVisiblePlaces)
        self.recentPlaces = Self.unique(
            self.places + recentPlaces,
            limit: Self.maximumRoutablePlaces
        )
    }

    func place(id: String) -> WanderNearbyPlaceSnapshot? {
        recentPlaces.first { $0.id == id }
    }

    func isUsable(at now: Date) -> Bool {
        WanderNearbyWidgetFreshness(
            generatedAt: generatedAt,
            now: now
        ).isUsable
    }

    func mergingRouteHistory(from previous: Self?) -> Self {
        Self(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            places: places,
            recentPlaces: recentPlaces + (previous?.recentPlaces ?? [])
        )
    }

    func hasSameRenderedContent(as other: Self) -> Bool {
        schemaVersion == other.schemaVersion && places == other.places
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case places
        case recentPlaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let places = try container.decode([WanderNearbyPlaceSnapshot].self, forKey: .places)
        let recentPlaces = try container.decode(
            [WanderNearbyPlaceSnapshot].self,
            forKey: .recentPlaces
        )

        guard places.count <= Self.maximumVisiblePlaces,
              recentPlaces.count <= Self.maximumRoutablePlaces,
              places == Self.unique(places, limit: Self.maximumVisiblePlaces),
              recentPlaces == Self.unique(recentPlaces, limit: Self.maximumRoutablePlaces),
              places.allSatisfy({ place in recentPlaces.contains { $0.id == place.id } })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .places,
                in: container,
                debugDescription: "Nearby widget places must be bounded, unique, and routable."
            )
        }

        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.places = places
        self.recentPlaces = recentPlaces
    }

    private static func unique(
        _ places: [WanderNearbyPlaceSnapshot],
        limit: Int
    ) -> [WanderNearbyPlaceSnapshot] {
        var seen = Set<String>()
        return Array(
            places
                .filter { seen.insert($0.id).inserted }
                .prefix(limit)
        )
    }
}

enum WanderNearbyWidgetSnapshotStoreError: Error, Equatable {
    case appGroupContainerUnavailable
    case unsupportedSchema(Int)
}

struct WanderNearbyWidgetSnapshotStore {
    static let freshnessWriteInterval: TimeInterval = 5 * 60

    private let fileURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: WanderWidgetConstants.appGroupIdentifier)?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(WanderWidgetConstants.nearbySnapshotFilename, isDirectory: false)
    }

    func load() -> WanderNearbyWidgetSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder.decode(WanderNearbyWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WanderNearbyWidgetSnapshot.currentSchemaVersion
        else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    func save(_ snapshot: WanderNearbyWidgetSnapshot) throws -> Bool {
        guard snapshot.schemaVersion == WanderNearbyWidgetSnapshot.currentSchemaVersion else {
            throw WanderNearbyWidgetSnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard let fileURL else {
            throw WanderNearbyWidgetSnapshotStoreError.appGroupContainerUnavailable
        }

        let existing = load()
        let persisted = snapshot.mergingRouteHistory(from: existing)
        if let existing, existing.hasSameRenderedContent(as: persisted) {
            let freshnessAdvance = persisted.generatedAt.timeIntervalSince(existing.generatedAt)
            if freshnessAdvance < Self.freshnessWriteInterval {
                return false
            }
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(persisted)
        try data.write(to: fileURL, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var persistedFileURL = fileURL
        try persistedFileURL.setResourceValues(resourceValues)
        return true
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
