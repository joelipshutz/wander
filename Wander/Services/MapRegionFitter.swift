import CoreLocation
import MapKit

enum MapRegionFitter {
    private static let fallbackMinimumSpan: CLLocationDegrees = 0.025
    private static let smallestUsableSpan: CLLocationDegrees = 0.000_001
    private static let maximumLatitudeSpan: CLLocationDegrees = 180
    private static let maximumLongitudeSpan: CLLocationDegrees = 360

    static func region(
        fitting coordinates: [CLLocationCoordinate2D],
        minimumSpan: CLLocationDegrees = 0.025,
        paddingMultiplier: CLLocationDegrees = 1.35
    ) -> MKCoordinateRegion? {
        let validCoordinates = coordinates.filter {
            CLLocationCoordinate2DIsValid($0)
                && !($0.latitude == 0 && $0.longitude == 0)
        }
        guard let first = validCoordinates.first else { return nil }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude

        for coordinate in validCoordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
        }

        let requestedMinimumSpan = minimumSpan.isFinite && minimumSpan > 0
            ? minimumSpan
            : fallbackMinimumSpan
        let resolvedPaddingMultiplier = paddingMultiplier.isFinite && paddingMultiplier > 0
            ? max(paddingMultiplier, 1)
            : 1

        let latitudeDelta = fittedSpan(
            extent: maxLatitude - minLatitude,
            minimum: min(requestedMinimumSpan, maximumLatitudeSpan),
            maximum: maximumLatitudeSpan,
            paddingMultiplier: resolvedPaddingMultiplier
        )
        let longitudeBounds = shortestLongitudeBounds(for: validCoordinates)
        let longitudeDelta = fittedSpan(
            extent: longitudeBounds.extent,
            minimum: min(requestedMinimumSpan, maximumLongitudeSpan),
            maximum: maximumLongitudeSpan,
            paddingMultiplier: resolvedPaddingMultiplier
        )

        // Shift a region near either pole just enough to keep its padded span
        // within MapKit's valid latitude bounds.
        let latitudeCenterLimit = (maximumLatitudeSpan - latitudeDelta) / 2
        let latitudeCenter = min(
            max((minLatitude + maxLatitude) / 2, -latitudeCenterLimit),
            latitudeCenterLimit
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: latitudeCenter,
                longitude: longitudeBounds.center
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    static func region(
        _ region: MKCoordinateRegion,
        accountingForViewportHeight viewportHeight: CGFloat,
        obscuredTopHeight: CGFloat,
        obscuredBottomHeight: CGFloat
    ) -> MKCoordinateRegion {
        guard viewportHeight.isFinite, viewportHeight > 0,
              obscuredTopHeight.isFinite, obscuredBottomHeight.isFinite,
              region.span.latitudeDelta.isFinite, region.span.latitudeDelta > 0
        else {
            return region
        }

        let topHeight = min(max(obscuredTopHeight, 0), viewportHeight)
        let bottomHeight = min(max(obscuredBottomHeight, 0), viewportHeight - topHeight)
        let unobscuredHeight = max(viewportHeight - topHeight - bottomHeight, viewportHeight * 0.25)
        let latitudeDelta = min(
            region.span.latitudeDelta * Double(viewportHeight / unobscuredHeight),
            maximumLatitudeSpan
        )
        let centerOffset = Double(
            (topHeight - bottomHeight) / (2 * viewportHeight)
        ) * latitudeDelta
        let latitudeCenterLimit = (maximumLatitudeSpan - latitudeDelta) / 2
        let latitude = min(
            max(region.center.latitude + centerOffset, -latitudeCenterLimit),
            latitudeCenterLimit
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: region.center.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: region.span.longitudeDelta
            )
        )
    }

    private static func fittedSpan(
        extent: CLLocationDegrees,
        minimum: CLLocationDegrees,
        maximum: CLLocationDegrees,
        paddingMultiplier: CLLocationDegrees
    ) -> CLLocationDegrees {
        min(
            max(extent * paddingMultiplier, max(minimum, smallestUsableSpan)),
            maximum
        )
    }

    private static func shortestLongitudeBounds(
        for coordinates: [CLLocationCoordinate2D]
    ) -> (center: CLLocationDegrees, extent: CLLocationDegrees) {
        guard coordinates.count > 1 else {
            return (normalizedLongitude(coordinates[0].longitude), 0)
        }

        let sortedLongitudes = coordinates
            .map { positiveLongitude($0.longitude) }
            .sorted()

        var largestGap: CLLocationDegrees = -1
        var arcStartIndex = 0

        for index in sortedLongitudes.indices {
            let nextIndex = (index + 1) % sortedLongitudes.count
            let nextLongitude = nextIndex == 0
                ? sortedLongitudes[nextIndex] + maximumLongitudeSpan
                : sortedLongitudes[nextIndex]
            let gap = nextLongitude - sortedLongitudes[index]

            if gap > largestGap {
                largestGap = gap
                arcStartIndex = nextIndex
            }
        }

        let arcStart = sortedLongitudes[arcStartIndex]
        let arcEndIndex = (arcStartIndex + sortedLongitudes.count - 1) % sortedLongitudes.count
        var arcEnd = sortedLongitudes[arcEndIndex]
        if arcEnd < arcStart {
            arcEnd += maximumLongitudeSpan
        }

        let extent = arcEnd - arcStart
        return (
            normalizedLongitude(arcStart + extent / 2),
            extent
        )
    }

    private static func positiveLongitude(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
        longitude >= 0 ? longitude : longitude + maximumLongitudeSpan
    }

    private static func normalizedLongitude(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
        var normalized = longitude.truncatingRemainder(dividingBy: maximumLongitudeSpan)
        if normalized > 180 {
            normalized -= maximumLongitudeSpan
        } else if normalized < -180 {
            normalized += maximumLongitudeSpan
        }
        return normalized
    }
}
