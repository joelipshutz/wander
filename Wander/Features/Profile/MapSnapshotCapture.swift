import MapKit
import SwiftUI
import UIKit

/// Captures the mounted map itself, so the image and membership use the exact
/// same projection, including a rotated/pitched camera and offline map tiles.
@MainActor
final class MapSnapshotCapture: ObservableObject {
    weak var anchor: UIView?

    struct Result {
        let jpegData: Data
        let placeIDs: [String]
    }

    enum CaptureError: LocalizedError {
        case unavailable, empty, imageFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: "The map is still loading. Try again in a moment."
            case .empty: "No saved places in this view. Move the map or change your filters, then try again."
            case .imageFailed: "Couldn’t capture the map. Please try again."
            }
        }
    }

    func capture(places: [YourMapPrototypePlace]) throws -> Result {
        guard let anchor, let window = anchor.window,
              let map = Self.mapView(in: window, overlapping: anchor)
        else { throw CaptureError.unavailable }

        let ids = MapSnapshotSelection.placeIDs(places: places) { place in
            let point = map.convert(place.coordinate, toPointTo: map)
            return point.x.isFinite && point.y.isFinite
                && map.bounds.contains(point)
        }
        guard !ids.isEmpty else { throw CaptureError.empty }

        // Bound both encoded storage and decoding work. Preserve the complete
        // frame (and MapKit attribution), rather than cropping to a square.
        let scale = min(1, 1_024 / max(map.bounds.width, map.bounds.height))
        let size = CGSize(width: map.bounds.width * scale, height: map.bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var rendered = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            rendered = map.drawHierarchy(in: map.bounds, afterScreenUpdates: false)
        }
        guard rendered, let data = image.jpegData(compressionQuality: 0.8),
              data.count <= LocalPlaceList.maximumSnapshotCoverBytes
        else { throw CaptureError.imageFailed }
        return Result(jpegData: data, placeIDs: ids)
    }

    private static func mapView(in view: UIView, overlapping anchor: UIView) -> MKMapView? {
        if let map = view as? MKMapView, !map.isHidden, map.window != nil,
           map.bounds.width > 0, map.bounds.height > 0 {
            let rect = map.convert(map.bounds, to: anchor)
            if rect.intersection(anchor.bounds).width > anchor.bounds.width * 0.9,
               rect.intersection(anchor.bounds).height > anchor.bounds.height * 0.9 {
                return map
            }
        }
        for child in view.subviews.reversed() {
            if let map = mapView(in: child, overlapping: anchor) { return map }
        }
        return nil
    }
}

struct MapSnapshotCaptureAnchor: UIViewRepresentable {
    let capture: MapSnapshotCapture

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        capture.anchor = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        capture.anchor = uiView
    }
}

enum MapSnapshotSelection {
    /// No prefix/annotation limit: every matching saved place is included once.
    static func placeIDs(
        places: [YourMapPrototypePlace],
        contains: (YourMapPrototypePlace) -> Bool
    ) -> [String] {
        var seen = Set<String>()
        return places.compactMap { place in
            guard CLLocationCoordinate2DIsValid(place.coordinate), contains(place),
                  seen.insert(place.id).inserted else { return nil }
            return place.id
        }
    }
}
