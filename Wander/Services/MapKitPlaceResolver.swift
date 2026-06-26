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
            "Location is off for Wander. Turn it on or add the place manually."
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
        let query = [name, area]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]

        let response = try await MKLocalSearch(request: request).start()
        let candidates = mapItems(response.mapItems, fallbackCategory: category, limit: 8)
        guard !candidates.isEmpty else {
            throw PlaceResolutionError.noCandidates
        }
        return candidates
    }

    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] {
        let parser = LinkPlaceParser()

        if let manualInput = parser.manualInput(from: input) {
            return try await resolveManualEntry(manualInput)
        }

        if parser.isShortMapLink(input) {
            if let expandedValue = try? await expandedURLString(from: input),
               let manualInput = parser.manualInput(from: LinkPlaceInput(rawValue: expandedValue)) {
                return try await resolveManualEntry(manualInput)
            }

            throw PlaceResolutionError.shortLinkNeedsExtraction
        }

        throw PlaceResolutionError.unsupportedLink
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

@MainActor
protocol CurrentLocationProviding {
    func currentLocation() async throws -> CLLocation
}

@MainActor
final class CoreLocationProvider: NSObject, CurrentLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private static let maximumLocationAge: TimeInterval = 120
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 300
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

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
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        guard let location = locations
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first(where: { Self.isUsableLocation($0) })
        else {
            continuation.resume(throwing: PlaceResolutionError.locationUnavailable)
            return
        }

        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: PlaceResolutionError.locationUnavailable)
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
