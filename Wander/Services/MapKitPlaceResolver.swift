import CoreLocation
import Foundation
import MapKit

enum PlaceResolutionError: Error, Equatable {
    case locationDenied
    case locationUnavailable
    case noCandidates
    case shortLinkNeedsExtraction
    case unsupportedLink
}

extension PlaceResolutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .locationDenied:
            "Location is off for \(AppBrand.displayName). Turn it on or add the place manually."
        case .locationUnavailable:
            "Could not find where you are right now. Try adding the place manually."
        case .noCandidates:
            "No matching places found. Try a more specific name or nearby area."
        case .shortLinkNeedsExtraction:
            "Short map links need extraction. Save this as a draft for now or add it manually."
        case .unsupportedLink:
            "This link does not show enough place info yet. Save it as a draft or add it manually."
        }
    }
}

/// Supplies onboarding with location context only after the user has already
/// made a system-level permission choice. In particular, `.notDetermined`
/// returns `nil` instead of presenting a location permission alert.
@MainActor
final class CoreFirstVisitParkLocationContextProvider: FirstVisitParkLocationContextProviding {
    private let locationProvider: CurrentLocationProviding
    private let authorizationStatus: () -> CLAuthorizationStatus
    private let postalCodeResolver: (CLLocation) async throws -> String?

    init(
        locationProvider: CurrentLocationProviding = CoreLocationProvider(),
        authorizationStatus: @escaping () -> CLAuthorizationStatus = {
            CLLocationManager().authorizationStatus
        },
        postalCodeResolver: @escaping (CLLocation) async throws -> String? = { location in
            try await CLGeocoder().reverseGeocodeLocation(location).first?.postalCode
        }
    ) {
        self.locationProvider = locationProvider
        self.authorizationStatus = authorizationStatus
        self.postalCodeResolver = postalCodeResolver
    }

    func alreadyAuthorizedLocationContext() async throws -> FirstVisitParkLocationContext? {
        switch authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .notDetermined, .restricted:
            return nil
        @unknown default:
            return nil
        }

        let location = try await locationProvider.currentLocation()
        guard let rawPostalCode = try await postalCodeResolver(location),
              let postalCode = FirstVisitParkSuggestionPolicy.normalizedPostalCode(rawPostalCode)
        else {
            return nil
        }

        return FirstVisitParkLocationContext(
            postalCode: postalCode
        )
    }
}

@MainActor
final class MapKitPlaceResolver: PlaceCandidateResolving {
    private let locationProvider: CurrentLocationProviding

    init(locationProvider: CurrentLocationProviding = CoreLocationProvider()) {
        self.locationProvider = locationProvider
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        let location = try await locationProvider.currentLocation()
        return try await nearbyPlaceCandidates(near: location)
    }

    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw PlaceResolutionError.locationUnavailable
        }
        return try await nearbyPlaceCandidates(
            near: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    private func nearbyPlaceCandidates(near location: CLLocation) async throws -> [PlaceCandidate] {
        for radius in [CLLocationDistance(175), CLLocationDistance(350), CLLocationDistance(700)] {
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
            request.pointOfInterestFilter = .includingAll

            let response = try await MKLocalSearch(request: request).start()
            let candidates = mapItems(
                response.mapItems,
                fallbackCategory: nil,
                origin: location,
                maxDistance: radius,
                limit: 8
            )
            if !candidates.isEmpty {
                return candidates
            }
        }

        throw PlaceResolutionError.noCandidates
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }

        let area = input.areaHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = input.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchPlan = ManualPlaceSearchPlan(name: name, areaHint: area)
        var candidates: [PlaceCandidate] = []
        var candidateIDs = Set<String>()
        var lastError: Error?
        let perQueryLimit = max(1, 8 / searchPlan.queries.count)
        for query in searchPlan.queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .address]
            if let coordinate = searchPlan.coordinateHint {
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_500,
                    longitudinalMeters: 1_500
                )
            } else if let region = searchPlan.regionHint {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: region.latitude,
                        longitude: region.longitude
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: region.latitudeDelta,
                        longitudeDelta: region.longitudeDelta
                    )
                )
            }

            do {
                let response = try await MKLocalSearch(request: request).start()
                for candidate in mapItems(response.mapItems, fallbackCategory: category, limit: perQueryLimit)
                    where candidateIDs.insert(candidate.id).inserted {
                    candidates.append(candidate)
                }
            } catch {
                lastError = error
            }
        }
        guard !candidates.isEmpty else {
            if let lastError {
                throw lastError
            }
            throw PlaceResolutionError.noCandidates
        }
        return Array(candidates.prefix(8))
    }

    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] {
        let parser = LinkPlaceParser()

        if let manualInput = parser.manualInput(from: input) {
            return try await resolveParsedLinkInput(manualInput, rawValue: input.rawValue)
        }

        if parser.isShortMapLink(input) {
            if let expandedValue = try? await expandedURLString(from: input),
               let manualInput = parser.manualInput(from: LinkPlaceInput(rawValue: expandedValue)) {
                return try await resolveParsedLinkInput(manualInput, rawValue: expandedValue)
            }

            throw PlaceResolutionError.shortLinkNeedsExtraction
        }

        throw PlaceResolutionError.unsupportedLink
    }

    private func resolveParsedLinkInput(_ input: ManualPlaceInput, rawValue: String) async throws -> [PlaceCandidate] {
        if LinkPlaceResolutionHeuristics.shouldPreferCoordinateLookup(for: input, rawValue: rawValue),
           let coordinate = LinkPlaceResolutionHeuristics.coordinate(from: input.areaHint) {
            let candidates = try await nearbyPlaceCandidates(
                near: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            return candidates
        }

        return try await resolveManualEntry(input)
    }

    private func expandedURLString(from input: LinkPlaceInput) async throws -> String? {
        let rawValue = input.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawValue), let host = url.host?.lowercased() else {
            return nil
        }

        guard ["maps.app.goo.gl", "goo.gl", "g.co", "maps.apple"].contains(host) else {
            return nil
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 Wander link resolver", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let expandedURL = response.url,
              expandedURL.absoluteString != rawValue
        else {
            return nil
        }

        return expandedURL.absoluteString
    }

    private func mapItems(
        _ items: [MKMapItem],
        fallbackCategory: String?,
        origin: CLLocation? = nil,
        maxDistance: CLLocationDistance? = nil,
        limit: Int
    ) -> [PlaceCandidate] {
        var seen = Set<String>()
        var candidates: [PlaceCandidate] = []

        for item in rankedMapItems(items, origin: origin, fallbackCategory: fallbackCategory) {
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  CLLocationCoordinate2DIsValid(item.placemark.coordinate)
            else {
                continue
            }

            if let origin, let maxDistance {
                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                guard itemLocation.distance(from: origin) <= maxDistance else { continue }
            }

            let sourceID = sourceProviderPlaceID(for: item, name: name)
            guard !seen.contains(sourceID) else { continue }
            seen.insert(sourceID)

            candidates.append(
                PlaceCandidate(
                    id: sourceID,
                    name: name,
                    category: category(for: item, fallbackCategory: fallbackCategory),
                    categorySource: PlaceCategorySource.provider.rawValue,
                    categoryConfidence: confidence(for: item, fallbackCategory: fallbackCategory, origin: origin),
                    rawProviderType: rawProviderType(for: item) ?? fallbackCategory,
                    address: address(for: item.placemark),
                    locality: item.placemark.locality,
                    region: item.placemark.administrativeArea,
                    country: item.placemark.countryCode,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    sourceProvider: "mapkit",
                    sourceProviderPlaceID: sourceID,
                    distanceMeters: distanceMeters(from: origin, to: item),
                    websiteURLString: item.url?.absoluteString,
                    phoneNumber: item.phoneNumber,
                    timeZoneIdentifier: item.timeZone?.identifier,
                    confidence: confidence(for: item, fallbackCategory: fallbackCategory, origin: origin)
                )
            )

            if candidates.count >= limit { break }
        }

        return candidates
    }

    private func rankedMapItems(_ items: [MKMapItem], origin: CLLocation?, fallbackCategory: String?) -> [MKMapItem] {
        items.sorted { lhs, rhs in
            rankingScore(for: lhs, origin: origin, fallbackCategory: fallbackCategory)
                > rankingScore(for: rhs, origin: origin, fallbackCategory: fallbackCategory)
        }
    }

    private func rankingScore(for item: MKMapItem, origin: CLLocation?, fallbackCategory: String?) -> Double {
        var score = 0.0

        if let pointCategory = item.pointOfInterestCategory {
            score += 500

            if pointCategory == .park || pointCategory == .nationalPark {
                score += 70
            }
        }

        if WanderPlaceCategory.primary(for: item.pointOfInterestCategory, name: item.name) != nil {
            score += 120
        }

        if fallbackCategory?.isEmpty == false {
            score += 40
        }

        if let origin {
            let itemLocation = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            let distance = itemLocation.distance(from: origin)

            switch distance {
            case ...50:
                score += 450
            case ...100:
                score += 320
            case ...200:
                score += 210
            case ...350:
                score += 105
            default:
                score -= min(distance, 2_000) / 6
            }
        }

        return score
    }

    private func category(for item: MKMapItem, fallbackCategory: String?) -> String {
        let fallback = fallbackCategory?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pointCategory = item.pointOfInterestCategory

        if let primary = WanderPlaceCategory.primary(for: pointCategory, name: item.name) {
            return primary
        }

        return fallback?.isEmpty == false ? fallback ?? "place" : "place"
    }

    private func rawProviderType(for item: MKMapItem) -> String? {
        item.pointOfInterestCategory?.rawValue
    }

    private func confidence(for item: MKMapItem, fallbackCategory: String?, origin: CLLocation?) -> Double {
        guard let origin else {
            if item.pointOfInterestCategory != nil {
                return 0.9
            }

            if fallbackCategory?.isEmpty == false {
                return 0.74
            }

            return 0.66
        }

        let categoryBoost = item.pointOfInterestCategory != nil ? 0.12 : 0
        let fallbackBoost = fallbackCategory?.isEmpty == false ? 0.06 : 0
        let distanceBoost: Double

        let itemLocation = CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        let distance = itemLocation.distance(from: origin)
        switch distance {
        case ...50:
            distanceBoost = 0.16
        case ...100:
            distanceBoost = 0.12
        case ...200:
            distanceBoost = 0.08
        case ...350:
            distanceBoost = 0.04
        default:
            distanceBoost = 0
        }

        return min(0.96, 0.66 + categoryBoost + fallbackBoost + distanceBoost)
    }

    private func distanceMeters(from origin: CLLocation?, to item: MKMapItem) -> Double? {
        guard let origin else { return nil }

        let itemLocation = CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        return itemLocation.distance(from: origin)
    }

    private func address(for placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        if !street.isEmpty { return street }
        return placemark.title?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceProviderPlaceID(for item: MKMapItem, name: String) -> String {
        let coordinate = item.placemark.coordinate
        let lat = Int((coordinate.latitude * 100_000).rounded())
        let lng = Int((coordinate.longitude * 100_000).rounded())
        return "mapkit_\(slug(name))_\(lat)_\(lng)"
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let parts = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }

        return String(parts)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

extension MapKitPlaceResolver: FirstVisitParkSuggestionRepository {
    func suggestion(near context: FirstVisitParkLocationContext) async throws -> PlaceCandidate {
        guard let postalCode = FirstVisitParkSuggestionPolicy.normalizedPostalCode(
            context.postalCode
        ) else {
            throw PlaceResolutionError.locationUnavailable
        }
        guard let center = try await CLGeocoder()
            .geocodeAddressString("\(postalCode), United States")
            .compactMap(\.location)
            .first
        else {
            throw PlaceResolutionError.locationUnavailable
        }

        let radius = FirstVisitParkSuggestionPolicy.searchRadiusMeters
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "park"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        let response = try await MKLocalSearch(request: request).start()
        let eligibleItems = response.mapItems.filter { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
            let distance = center.distance(
                from: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
            guard distance <= radius else { return false }
            return item.pointOfInterestCategory == .park
                || item.pointOfInterestCategory == .nationalPark
                || item.name?.localizedCaseInsensitiveContains("park") == true
        }
        guard let selectedItem = eligibleItems.first,
              let candidate = mapItems(
                  [selectedItem],
                  fallbackCategory: "park",
                  origin: center,
                  maxDistance: radius,
                  limit: 1
              ).first
        else {
            throw PlaceResolutionError.noCandidates
        }

        return candidate.recategorized(
            as: PlaceCategoryAssignment(
                primaryCategory: WanderPlaceCategory.outdoorsNature,
                subcategory: "Park",
                source: PlaceCategorySource.provider.rawValue,
                confidence: candidate.confidence,
                rawProviderType: candidate.rawProviderType ?? "park"
            )
        )
    }
}

struct ManualPlaceSearchPlan {
    let query: String
    let queries: [String]
    let coordinateHint: CLLocationCoordinate2D?
    let regionHint: PlaceImportSearchRegion?

    init(name: String, areaHint: String?) {
        let resolvedCoordinateHint = LinkPlaceResolutionHeuristics.coordinate(from: areaHint)
        let resolvedRegionHint = resolvedCoordinateHint == nil
            ? PlaceImportGeography.searchRegion(for: areaHint)
            : nil
        let queryAreaHint: String?
        if resolvedCoordinateHint != nil {
            queryAreaHint = nil
        } else if resolvedRegionHint != nil {
            queryAreaHint = PlaceImportGeography.localityText(in: areaHint)
        } else {
            queryAreaHint = areaHint
        }

        let names = Self.providerNameVariants(for: name)
        let resolvedQueries = names.map { searchName in
            [searchName, queryAreaHint]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " ")
        }
        coordinateHint = resolvedCoordinateHint
        regionHint = resolvedRegionHint
        queries = resolvedQueries
        query = resolvedQueries[0]
    }

    private static func providerNameVariants(for name: String) -> [String] {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        var variants = [name]
        if folded.contains("gorge"), !folded.contains("reservoir") {
            variants.append("\(name) Reservoir")
        }
        if folded.contains("overlook"), !folded.contains("interpretive site") {
            variants.append("\(name) Interpretive Site")
        }
        return variants
    }
}

enum LinkPlaceResolutionHeuristics {
    static func shouldPreferCoordinateLookup(for input: ManualPlaceInput, rawValue: String) -> Bool {
        guard isAppleMapsLink(rawValue),
              coordinate(from: input.areaHint) != nil,
              looksLikeStreetAddress(input.name)
        else {
            return false
        }

        return true
    }

    static func coordinate(from value: String?) -> CLLocationCoordinate2D? {
        guard let value else { return nil }

        let pattern = #"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$"#
        guard let match = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let matchedValue = String(value[match])
        let parts = matchedValue.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let latitude = CLLocationDegrees(parts[0]),
              let longitude = CLLocationDegrees(parts[1])
        else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func isAppleMapsLink(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased()
        else {
            return false
        }

        return host == "maps.apple.com" || host == "maps.apple"
    }

    private static func looksLikeStreetAddress(_ value: String) -> Bool {
        let pattern = #"(?i)\b\d{1,6}\s+[^,]+\b(st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|ln|lane|way|ct|court|pl|place|pkwy|parkway|hwy|highway)\b"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

@MainActor
protocol CurrentLocationProviding {
    func currentLocation() async throws -> CLLocation
}

@MainActor
final class CoreLocationProvider: NSObject, CurrentLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private static let maximumLocationAge: TimeInterval = 120
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 300
    private static let requestTimeout: Duration = .seconds(6)
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var locationTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func currentLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        let authorizedStatus: CLAuthorizationStatus

        switch status {
        case .notDetermined:
            authorizedStatus = await requestAuthorization()
        default:
            authorizedStatus = status
        }

        guard authorizedStatus == .authorizedWhenInUse || authorizedStatus == .authorizedAlways else {
            throw PlaceResolutionError.locationDenied
        }

        return try await requestLocation()
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationTimeoutTask?.cancel()
            locationContinuation = continuation
            manager.requestLocation()
            locationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.requestTimeout)
                guard !Task.isCancelled else { return }
                self?.finishLocationRequest(
                    with: .failure(PlaceResolutionError.locationUnavailable)
                )
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first(where: { Self.isUsableLocation($0) })
        else {
            finishLocationRequest(with: .failure(PlaceResolutionError.locationUnavailable))
            return
        }

        finishLocationRequest(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocationRequest(with: .failure(PlaceResolutionError.locationUnavailable))
    }

    private func finishLocationRequest(with result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        continuation.resume(with: result)
    }

    private static func isUsableLocation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy
        else {
            return false
        }

        return abs(location.timestamp.timeIntervalSinceNow) <= maximumLocationAge
    }
}
