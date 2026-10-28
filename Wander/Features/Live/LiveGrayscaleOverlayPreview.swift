#if DEBUG && targetEnvironment(simulator)
import MapKit
import SwiftUI

/// A separate review surface: the production Live map never adopts this renderer.
struct LiveGrayscaleOverlayPreview: View {
    let pins: [LivePlacePin]
    let dark: Bool
    let onClose: () -> Void
    @State private var grayscale = true
    @State private var selectedID: String?

    private var brand: AstirBrandMode { dark ? .editorial : .editorialLight }
    private var selectedPin: LivePlacePin? { pins.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Map appearance preview").font(.headline)
                        Text("Preview only").font(.caption).foregroundStyle(brand.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close map appearance preview")
                    .accessibilityIdentifier("grayscale.close")
                }
                Picker("Map appearance", selection: $grayscale) {
                    Text("Grayscale").tag(true)
                    Text(dark ? "Ink" : "Paper").tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("grayscale.mode")
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            .background(brand.background)

            GrayscaleNativeMap(pins: pins, dark: dark, grayscale: grayscale, selectedID: $selectedID)

            if let selectedPin {
                HStack(spacing: 12) {
                    Text(selectedPin.place.place.canonicalName)
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("grayscale.selectedPlace")
                    Button { selectedID = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss selected place")
                    .accessibilityIdentifier("grayscale.dismissSelection")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(brand.raisedBackground)
            }
        }
        .foregroundStyle(brand.primaryText)
        .background(brand.background)
        .environment(\.astirBrandMode, brand)
        .preferredColorScheme(dark ? .dark : .light)
    }
}

private struct GrayscaleNativeMap: UIViewRepresentable {
    let pins: [LivePlacePin]
    let dark: Bool
    let grayscale: Bool
    @Binding var selectedID: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "grayscale.map"
        map.overrideUserInterfaceStyle = dark ? .dark : .light
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .includingAll
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.selectableMapFeatures = [.pointsOfInterest]
        map.register(GrayscalePinAnnotationView.self, forAnnotationViewWithReuseIdentifier: "grayscale.pin")
        // Deliberately frame the LA fixture once. Toggles and late-arriving pins
        // never move the user's camera or fit the world-sized overlay.
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.082, longitude: -118.267),
            span: MKCoordinateSpan(latitudeDelta: 0.031, longitudeDelta: 0.041)), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        map.overrideUserInterfaceStyle = dark ? .dark : .light
        if grayscale != coordinator.overlayVisible {
            if grayscale { map.addOverlay(LiveMapStyleLab.grayscalePolygon, level: .aboveLabels) }
            else { map.removeOverlay(LiveMapStyleLab.grayscalePolygon) }
            coordinator.overlayVisible = grayscale
        }
        coordinator.updateAnnotations(in: map)
        for annotation in map.selectedAnnotations {
            if let pin = annotation as? GrayscalePinAnnotation, pin.pinID != selectedID {
                map.deselectAnnotation(pin, animated: false)
            }
        }
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GrayscaleNativeMap
        var overlayVisible = false
        var isUpdating = false
        private var annotations: [String: GrayscalePinAnnotation] = [:]

        init(parent: GrayscaleNativeMap) { self.parent = parent }

        func updateAnnotations(in map: MKMapView) {
            let validPins = parent.pins.filter {
                CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(
                    latitude: $0.place.place.latitude, longitude: $0.place.place.longitude))
            }
            let ids = Set(validPins.map(\.id))
            let removed = annotations.filter { !ids.contains($0.key) }
            map.removeAnnotations(Array(removed.values))
            for id in removed.keys { annotations.removeValue(forKey: id) }
            for pin in validPins {
                let coordinate = CLLocationCoordinate2D(latitude: pin.place.place.latitude,
                                                        longitude: pin.place.place.longitude)
                let annotation: GrayscalePinAnnotation
                if let existing = annotations[pin.id] {
                    annotation = existing
                    if existing.coordinate.latitude != coordinate.latitude || existing.coordinate.longitude != coordinate.longitude {
                        existing.coordinate = coordinate
                    }
                    existing.title = pin.place.place.canonicalName
                    existing.kind = pin.kind
                } else {
                    annotation = GrayscalePinAnnotation(id: pin.id, title: pin.place.place.canonicalName,
                                                       coordinate: coordinate, kind: pin.kind)
                    annotations[pin.id] = annotation
                    map.addAnnotation(annotation)
                }
                if let view = map.view(for: annotation) as? GrayscalePinAnnotationView {
                    view.configure(annotation, dark: parent.dark)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = .gray
            renderer.blendMode = .saturation
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? GrayscalePinAnnotation else { return nil }
            guard let view = mapView.dequeueReusableAnnotationView(withIdentifier: "grayscale.pin", for: pin)
                as? GrayscalePinAnnotationView else { return nil }
            view.configure(pin, dark: parent.dark)
            view.onActivate = { [weak mapView, weak pin] in
                guard let mapView, let pin else { return }
                mapView.selectAnnotation(pin, animated: false)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isUpdating else { return }
            parent.selectedID = (view.annotation as? GrayscalePinAnnotation)?.pinID
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !isUpdating, let pin = view.annotation as? GrayscalePinAnnotation,
                  parent.selectedID == pin.pinID else { return }
            parent.selectedID = nil
        }
    }
}

private final class GrayscalePinAnnotation: NSObject, MKAnnotation {
    let pinID: String
    @objc dynamic var title: String?
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var kind: LivePinKind

    init(id: String, title: String, coordinate: CLLocationCoordinate2D, kind: LivePinKind) {
        pinID = id
        self.title = title
        self.coordinate = coordinate
        self.kind = kind
        super.init()
    }
}

/// The host supplies the same explicit brand environment as the preview screen.
private struct GrayscaleHostedPin: View {
    let kind: LivePinKind
    let selected: Bool
    let dark: Bool

    var body: some View {
        LiveMapPinView(kind: kind, selected: selected, viewed: false, compact: false)
            .environment(\.astirBrandMode, dark ? .editorial : .editorialLight)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

private final class GrayscalePinAnnotationView: MKAnnotationView {
    private var host: UIHostingController<GrayscaleHostedPin>?
    private var dark = false
    var onActivate: (() -> Void)?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame.size = CGSize(width: 44, height: 44)
        isEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        collisionMode = .circle
        displayPriority = .required
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(_ pin: GrayscalePinAnnotation, dark: Bool) {
        self.dark = dark
        accessibilityIdentifier = "grayscale.pin.\(pin.pinID)"
        accessibilityLabel = pin.title
        refreshPin()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        refreshPin()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
    }

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }

    private func refreshPin() {
        guard let pin = annotation as? GrayscalePinAnnotation else { return }
        let root = GrayscaleHostedPin(kind: pin.kind, selected: isSelected, dark: dark)
        if let host { host.rootView = root }
        else {
            let controller = UIHostingController(rootView: root)
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = false
            controller.view.accessibilityElementsHidden = true
            controller.view.frame = bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(controller.view)
            host = controller
        }
        host?.overrideUserInterfaceStyle = dark ? .dark : .light
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
#endif
