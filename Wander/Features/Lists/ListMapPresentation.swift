import CoreGraphics
import CoreLocation
import Foundation
import MapKit

enum ListMapContentState: Equatable {
    case empty
    case unresolved(total: Int)
    case partial(mapped: Int, total: Int)
    case mapped(count: Int)

    init(totalItemCount: Int, resolvedPlaceCount: Int, mappedPlaceCount: Int) {
        let total = max(totalItemCount, resolvedPlaceCount, mappedPlaceCount, 0)
        let mapped = max(mappedPlaceCount, 0)

        if total == 0 {
            self = .empty
        } else if mapped == 0 {
            self = .unresolved(total: total)
        } else if mapped < total {
            self = .partial(mapped: mapped, total: total)
        } else {
            self = .mapped(count: mapped)
        }
    }

    var countLabel: String {
        switch self {
        case .empty:
            "No mapped places"
        case .unresolved(let total):
            "\(total) \(total == 1 ? "place" : "places")"
        case .partial(let mapped, let total):
            "\(mapped) mapped of \(total)"
        case .mapped(let count):
            "\(count) \(count == 1 ? "place" : "places")"
        }
    }
}

enum ListMapAvailability: Equatable {
    case ready
    case loading
    case error
    case offline
}

enum ListMapInteractionEvent: Equatable {
    case focus(String?)
    case open(String)
}

struct ListMapInteractionState: Equatable {
    var focusedPlaceID: String?
    var openPlaceID: String?

    init(focusedPlaceID: String? = nil, openPlaceID: String? = nil) {
        self.focusedPlaceID = focusedPlaceID
        self.openPlaceID = openPlaceID
    }

    mutating func handle(_ event: ListMapInteractionEvent, validPlaceIDs: Set<String>) {
        switch event {
        case .focus(let placeID):
            focusedPlaceID = placeID.flatMap { validPlaceIDs.contains($0) ? $0 : nil }
        case .open(let placeID):
            guard validPlaceIDs.contains(placeID) else { return }
            openPlaceID = placeID
        }
    }

    mutating func reconcile(validPlaceIDs: Set<String>) {
        if focusedPlaceID.map(validPlaceIDs.contains) == false {
            focusedPlaceID = nil
        }
        if openPlaceID.map(validPlaceIDs.contains) == false {
            openPlaceID = nil
        }
    }
}

struct ListMapCoordinate: Identifiable, Equatable {
    let id: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(id: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isMappable: Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && !(abs(latitude) < 0.000_001 && abs(longitude) < 0.000_001)
    }
}

enum ListMapPlaceFocusCamera {
    private static let neighborhoodSpan: CLLocationDegrees = 0.012

    static func region(
        around coordinate: CLLocationCoordinate2D,
        preserving visibleRegion: MKCoordinateRegion
    ) -> MKCoordinateRegion? {
        guard ListMapCoordinate(id: "focused-place", coordinate: coordinate).isMappable else {
            return nil
        }

        let latitudeDelta = focusedSpan(from: visibleRegion.span.latitudeDelta)
        let longitudeDelta = focusedSpan(from: visibleRegion.span.longitudeDelta)
        let latitudeCenterLimit = (180 - latitudeDelta) / 2

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: min(max(coordinate.latitude, -latitudeCenterLimit), latitudeCenterLimit),
                longitude: coordinate.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private static func focusedSpan(from visibleSpan: CLLocationDegrees) -> CLLocationDegrees {
        guard visibleSpan.isFinite, visibleSpan > 0 else { return neighborhoodSpan }
        return min(visibleSpan, neighborhoodSpan)
    }
}

struct ListMapCluster: Identifiable, Equatable {
    let id: String
    let memberIDs: [String]
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isCluster: Bool {
        memberIDs.count > 1
    }
}

enum ListMapClusterer {
    static func clusters(
        for coordinates: [ListMapCoordinate],
        in region: MKCoordinateRegion,
        viewportSize: CGSize,
        minimumScreenDistance: CGFloat = 52
    ) -> [ListMapCluster] {
        let validCoordinates = coordinates.filter(\.isMappable)
        guard !validCoordinates.isEmpty else { return [] }

        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let latitudeSpan = max(region.span.latitudeDelta, 0.000_001)
        let longitudeSpan = max(region.span.longitudeDelta, 0.000_001)
        let projectedPoints = validCoordinates.map { item in
            CGPoint(
                x: width * (0.5 + normalizedLongitudeDelta(
                    item.longitude - region.center.longitude
                ) / longitudeSpan),
                y: height * (0.5 - (item.latitude - region.center.latitude) / latitudeSpan)
            )
        }

        var parents = Array(validCoordinates.indices)

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            let x = lhs.x - rhs.x
            let y = lhs.y - rhs.y
            return x * x + y * y
        }

        let threshold = minimumScreenDistance * minimumScreenDistance
        for lhs in validCoordinates.indices {
            for rhs in validCoordinates.indices where rhs > lhs {
                guard squaredDistance(projectedPoints[lhs], projectedPoints[rhs]) <= threshold else {
                    continue
                }
                let lhsRoot = root(of: lhs)
                let rhsRoot = root(of: rhs)
                if lhsRoot != rhsRoot {
                    parents[rhsRoot] = lhsRoot
                }
            }
        }

        var groupedIndices: [Int: [Int]] = [:]
        var orderedRoots: [Int] = []
        for index in validCoordinates.indices {
            let groupRoot = root(of: index)
            if groupedIndices[groupRoot] == nil {
                orderedRoots.append(groupRoot)
            }
            groupedIndices[groupRoot, default: []].append(index)
        }

        return orderedRoots.compactMap { groupRoot in
            guard let indices = groupedIndices[groupRoot], !indices.isEmpty else { return nil }
            let members = indices.map { validCoordinates[$0] }
            let latitude = members.map(\.latitude).reduce(0, +) / Double(members.count)
            let referenceLongitude = region.center.longitude
            let longitudeOffset = members
                .map { normalizedLongitudeDelta($0.longitude - referenceLongitude) }
                .reduce(0, +) / Double(members.count)
            let longitude = normalizedLongitude(referenceLongitude + longitudeOffset)
            let memberIDs = members.map(\.id)

            return ListMapCluster(
                id: memberIDs.sorted().joined(separator: "|"),
                memberIDs: memberIDs,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    private static func normalizedLongitudeDelta(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 {
            result -= 360
        } else if result < -180 {
            result += 360
        }
        return result
    }

    private static func normalizedLongitude(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 {
            result -= 360
        } else if result < -180 {
            result += 360
        }
        return result
    }
}
