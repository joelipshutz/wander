import CoreLocation
import Foundation
import WidgetKit

@MainActor
enum WanderNearbyWidgetSnapshotPublisher {
    static func refreshIfConfigured(
        store: WanderStore,
        now: Date = .now,
        snapshotStore: WanderNearbyWidgetSnapshotStore = WanderNearbyWidgetSnapshotStore()
    ) async {
        guard await isNearbyWidgetConfigured() else { return }

        let locationManager = CLLocationManager()
        let authorizationStatus = locationManager.authorizationStatus
        guard authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways
        else {
            return
        }

        if let existing = snapshotStore.load(),
           now.timeIntervalSince(existing.generatedAt)
                < WanderNearbyWidgetSnapshotStore.freshnessWriteInterval
        {
            return
        }

        do {
            let candidates = try await store.currentLocationCandidates()
            let places = candidates
                .prefix(WanderNearbyWidgetSnapshot.maximumVisiblePlaces)
                .compactMap(WanderNearbyPlaceSnapshot.init(candidate:))
            guard !places.isEmpty else { return }

            let snapshot = WanderNearbyWidgetSnapshot(
                generatedAt: now,
                places: places
            )
            if try snapshotStore.save(snapshot) {
                WidgetCenter.shared.reloadTimelines(
                    ofKind: WanderWidgetConstants.nearbyPlacesKind
                )
            }
        } catch {
            #if DEBUG
            WanderDebugLog.sync.debug(
                "nearby widget app refresh skipped error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    private static func isNearbyWidgetConfigured() async -> Bool {
        if #available(iOS 18.0, *) {
            guard let configurations = try? await WidgetCenter.shared.currentConfigurations()
            else {
                return false
            }
            return configurations.contains {
                $0.kind == WanderWidgetConstants.nearbyPlacesKind
            }
        }

        return await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let isConfigured = (try? result.get())?.contains {
                    $0.kind == WanderWidgetConstants.nearbyPlacesKind
                } ?? false
                continuation.resume(returning: isConfigured)
            }
        }
    }
}

extension WanderNearbyPlaceSnapshot {
    init?(candidate: PlaceCandidate) {
        guard let latitude = candidate.latitude,
              let longitude = candidate.longitude
        else {
            return nil
        }

        self.init(
            id: candidate.id,
            name: candidate.name,
            category: candidate.primaryCategory,
            categoryLabel: WanderPlaceCategory.broadCategory(for: candidate.primaryCategory),
            categoryEmoji: candidate.categoryEmoji,
            rawProviderType: candidate.rawProviderType,
            address: candidate.address,
            locality: candidate.locality,
            region: candidate.region,
            country: candidate.country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: candidate.sourceProvider,
            sourceProviderPlaceID: candidate.sourceProviderPlaceID ?? candidate.id,
            distanceMeters: candidate.distanceMeters,
            websiteURLString: candidate.websiteURLString,
            phoneNumber: candidate.phoneNumber,
            timeZoneIdentifier: candidate.timeZoneIdentifier,
            confidence: candidate.confidence
        )
    }

    var placeCandidate: PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name,
            category: category,
            primaryCategory: category,
            categorySource: PlaceCategorySource.provider.rawValue,
            categoryConfidence: confidence,
            rawProviderType: rawProviderType,
            address: address,
            locality: locality,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            distanceMeters: distanceMeters,
            websiteURLString: websiteURLString,
            phoneNumber: phoneNumber,
            timeZoneIdentifier: timeZoneIdentifier,
            confidence: confidence
        )
    }
}
