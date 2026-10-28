#if DEBUG && targetEnvironment(simulator)
import MapKit

/// REC-657: isolated visual comparisons on the existing native Map surface.
/// No search filters, delegates, annotations, gestures, or visibility rules change.
enum MapKitLabStyle: String, CaseIterable {
    case quiet, atlas, night, dimension, hybrid

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("-WanderMapCapture"),
              arguments.contains("-WanderAuthenticatedUITest"),
              arguments.contains("-WanderUseDemoFixtures") || arguments.contains("-WanderUseStorefrontFixtures"),
              let index = arguments.firstIndex(of: "-WanderMapDesign"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return Self(rawValue: arguments[index + 1])
    }

    static let current = resolve(arguments: ProcessInfo.processInfo.arguments)

    @MainActor
    func configuration() -> MKMapConfiguration {
        if self == .hybrid {
            let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .includingAll
            configuration.showsTraffic = false
            return configuration
        }
        let configuration = MKStandardMapConfiguration(
            elevationStyle: self == .dimension ? .realistic : .flat,
            emphasisStyle: self == .atlas || self == .dimension ? .default : .muted
        )
        configuration.pointOfInterestFilter = .includingAll
        configuration.showsTraffic = false
        return configuration
    }
}
#endif
