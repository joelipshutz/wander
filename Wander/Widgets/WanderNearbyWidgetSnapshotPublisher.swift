import CoreLocation
import Foundation
import WidgetKit

@MainActor
enum WanderNearbyWidgetSnapshotPublisher {
    static func refreshIfConfigured(now: Date = .now) async {
        let snapshotStore = WanderNearbyWidgetSnapshotStore()
        switch await nearbyWidgetConfigurationState() {
        case .notConfigured:
            _ = try? snapshotStore.clear()
            return
        case .unknown:
            return
        case .configured:
            break
        }
        let locationManager = CLLocationManager()
        let authorizationStatus = locationManager.authorizationStatus
        let isAppAuthorized = authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        guard isAppAuthorized && locationManager.isAuthorizedForWidgetUpdates else {
            _ = try? snapshotStore.clear()
            WidgetCenter.shared.reloadTimelines(
                ofKind: WanderWidgetConstants.nearbyPlacesKind
            )
            return
        }

        if let generatedAt = snapshotStore.load()?.generatedAt,
           now.timeIntervalSince(generatedAt)
            < WanderNearbyWidgetSnapshotStore.freshnessWriteInterval {
            return
        }
        WidgetCenter.shared.reloadTimelines(
            ofKind: WanderWidgetConstants.nearbyPlacesKind
        )
    }

    private enum ConfigurationState {
        case configured
        case notConfigured
        case unknown
    }

    private static func nearbyWidgetConfigurationState() async -> ConfigurationState {
        if #available(iOS 18.0, *) {
            do {
                let configurations = try await WidgetCenter.shared.currentConfigurations()
                return configurations.contains {
                    $0.kind == WanderWidgetConstants.nearbyPlacesKind
                } ? .configured : .notConfigured
            } catch {
                return .unknown
            }
        }

        return await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let configurations):
                    continuation.resume(
                        returning: configurations.contains {
                            $0.kind == WanderWidgetConstants.nearbyPlacesKind
                        } ? .configured : .notConfigured
                    )
                case .failure:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }
}

extension WanderNearbyPlaceSnapshot {
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
