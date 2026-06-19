import CoreLocation
import MapKit

enum MapRegionFitter {
    static func region(
        fitting coordinates: [CLLocationCoordinate2D],
        minimumSpan: CLLocationDegrees = 0.025,
        paddingMultiplier: CLLocationDegrees = 1.35
    ) -> MKCoordinateRegion? {
        let validCoordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let first = validCoordinates.first else { return nil }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in validCoordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * paddingMultiplier, minimumSpan)
        let longitudeDelta = max((maxLongitude - minLongitude) * paddingMultiplier, minimumSpan)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
