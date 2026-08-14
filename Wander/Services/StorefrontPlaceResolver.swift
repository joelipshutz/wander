#if DEBUG
import CoreLocation
import Foundation

/// Prevents App Store screenshot capture from depending on device location,
/// MapKit search results, or any signed-in account data.
@MainActor
final class StorefrontPlaceResolver: PlaceCandidateResolving {
    static let candidates: [PlaceCandidate] = [
        PlaceCandidate(
            id: "storefront-place-sparrow-bakery",
            name: "Sparrow Bakery",
            category: "bakery",
            address: "12 Orchard Walk",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0778,
            longitude: -118.2789,
            sourceProvider: "storefront_fixture",
            distanceMeters: 42,
            confidence: 1
        ),
        PlaceCandidate(
            id: "storefront-place-clover-pine",
            name: "Clover & Pine",
            category: "restaurant",
            address: "48 Garden Lane",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0792,
            longitude: -118.2811,
            sourceProvider: "storefront_fixture",
            distanceMeters: 96,
            confidence: 1
        ),
        PlaceCandidate(
            id: "storefront-place-moonrise-books",
            name: "Moonrise Books",
            category: "bookstore",
            address: "7 Juniper Court",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0762,
            longitude: -118.2840,
            sourceProvider: "storefront_fixture",
            distanceMeters: 155,
            confidence: 1
        ),
        PlaceCandidate(
            id: "storefront-place-honeycomb-cafe",
            name: "Honeycomb Cafe",
            category: "coffee",
            address: "31 Grove Street",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0810,
            longitude: -118.2764,
            sourceProvider: "storefront_fixture",
            distanceMeters: 210,
            confidence: 1
        ),
    ]

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        Self.candidates
    }

    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        Self.candidates
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        let query = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return Self.candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] {
        []
    }
}
#endif
