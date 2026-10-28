import MapKit
import SwiftUI

/// The normal and Release map keep their existing configuration. Review variants
/// are compiled only for simulator Debug builds and require the demo fixture.
struct LiveMapStyleReview: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if let option = LiveMapStyleLab.current {
            content.mapStyle(option.mapStyle)
                .preferredColorScheme(option.colorScheme)
        } else {
            content.mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
        }
        #else
        content.mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
enum LiveMapStyleLab: String, CaseIterable {
    case paper, atlas, ink, midnight, aerial, graphite
    case graphiteDark = "graphite-dark"

    static let current = resolve(arguments: ProcessInfo.processInfo.arguments)

    static func resolve(arguments: [String]) -> Self? {
        let required = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                        "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture"]
        guard !arguments.contains("-WanderUseLiveAuth"),
              required.allSatisfy(arguments.contains),
              let index = arguments.firstIndex(of: "-WanderLiveMapStyle"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return Self(rawValue: arguments[index + 1])
    }

    var colorScheme: ColorScheme {
        self == .ink || self == .midnight || self == .graphiteDark ? .dark : .light
    }

    var usesGrayscaleOverlay: Bool { self == .graphite || self == .graphiteDark }

    // Use projected points so the polygon spans the Mercator world without an
    // antimeridian seam. It is inserted before the app's colored area overlays.
    @MainActor static let grayscalePolygon = MKPolygon(points: [
        MKMapPoint(x: MKMapRect.world.minX, y: MKMapRect.world.minY),
        MKMapPoint(x: MKMapRect.world.maxX, y: MKMapRect.world.minY),
        MKMapPoint(x: MKMapRect.world.maxX, y: MKMapRect.world.maxY),
        MKMapPoint(x: MKMapRect.world.minX, y: MKMapRect.world.maxY)
    ], count: 4)

    var mapStyle: MapStyle {
        switch self {
        case .paper, .ink, .graphite, .graphiteDark:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .all,
                      showsTraffic: false)
        case .atlas, .midnight:
            .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all,
                      showsTraffic: false)
        case .aerial:
            .hybrid(elevation: .flat, pointsOfInterest: .all, showsTraffic: false)
        }
    }
}
#endif
