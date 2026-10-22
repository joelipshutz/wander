import MapKit
import SwiftUI

/// Native map places remain candidates until the viewer chooses a save action.
/// Their identity matches the existing Map search path, without creating a save.
@MainActor
enum LiveMapPlaceDiscovery {
    static func resolve(_ feature: MapFeature) async -> PlaceCandidate? {
        guard feature.kind == .pointOfInterest, !Task.isCancelled else { return nil }
        let fallback = candidate(from: feature)
        do {
            let item = try await MKMapItemRequest(feature: feature).mapItem
            guard !Task.isCancelled else { return nil }
            return candidate(from: item) ?? fallback
        } catch {
            guard !Task.isCancelled else { return nil }
            return fallback
        }
    }

    static func candidate(from feature: MapFeature) -> PlaceCandidate? {
        guard feature.kind == .pointOfInterest else { return nil }
        return candidate(title: feature.title, coordinate: feature.coordinate,
                         category: feature.pointOfInterestCategory)
    }

    static func candidate(
        title: String?,
        coordinate: CLLocationCoordinate2D,
        category: MKPointOfInterestCategory?
    ) -> PlaceCandidate? {
        guard let name = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let key = MapSearchResultIdentity.locationKey(name: name,
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        let id = "mapkit_\(key)"
        return PlaceCandidate(
            id: id, name: name,
            category: WanderPlaceCategory.primary(for: category, name: name) ?? "place",
            categorySource: PlaceCategorySource.provider.rawValue,
            categoryConfidence: 0.78, rawProviderType: category?.rawValue,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            sourceProvider: "mapkit", sourceProviderPlaceID: id, confidence: 0.78
        )
    }

    static func candidate(from item: MKMapItem) -> PlaceCandidate? {
        let coordinate = item.placemark.coordinate
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let key = MapSearchResultIdentity.locationKey(name: name,
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        let id = "mapkit_\(key)"
        let confidence = item.pointOfInterestCategory == nil ? 0.72 : 0.86
        return PlaceCandidate(
            id: id, name: name,
            category: WanderPlaceCategory.primary(for: item.pointOfInterestCategory, name: name) ?? "place",
            categorySource: PlaceCategorySource.provider.rawValue,
            categoryConfidence: confidence, rawProviderType: item.pointOfInterestCategory?.rawValue,
            address: address(for: item.placemark), locality: item.placemark.locality,
            region: item.placemark.administrativeArea, country: item.placemark.countryCode,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            sourceProvider: "mapkit", sourceProviderPlaceID: id,
            websiteURLString: item.url?.absoluteString, phoneNumber: item.phoneNumber,
            timeZoneIdentifier: item.timeZone?.identifier, confidence: confidence
        )
    }

    private static func address(for placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.joined(separator: " ")
        if !street.isEmpty { return street }
        let title = placemark.title?.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
}
