import MapKit
import SwiftUI

/// Coordinate conversion for the map this adapter owns; no view discovery or
/// access to a SwiftUI Map's private renderer is involved.
@MainActor
final class LiveNativeMapProxy: ObservableObject {
    fileprivate weak var mapView: MKMapView?
    fileprivate(set) var positionedByUser = false

    var camera: MapCamera? { mapView.map { MapCamera($0.camera) } }
    var region: MKCoordinateRegion? { mapView.map { Self.fullBoundsRegion($0) } }

    fileprivate static func fullBoundsRegion(_ map: MKMapView) -> MKCoordinateRegion {
        // MKMapView.region describes its inset content footprint when margins
        // position native controls. Live's viewport policy uses the full view.
        map.convert(map.bounds, toRegionFrom: map)
    }

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard let mapView, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let point = mapView.convert(coordinate, toPointTo: mapView)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    func coordinate(for point: CGPoint) -> CLLocationCoordinate2D? {
        guard let mapView, point.x.isFinite, point.y.isFinite else { return nil }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    func cameraCenter(after offset: CGSize, from camera: MapCamera) -> CLLocationCoordinate2D? {
        // The native camera target sits at the inset content center, which can
        // differ from the full view midpoint when a preview covers the map.
        guard let origin = point(for: camera.centerCoordinate) else { return nil }
        return coordinate(for: CGPoint(x: origin.x + offset.width, y: origin.y + offset.height))
    }
}

struct LiveNativeMap: UIViewRepresentable {
    @Binding var position: MapCameraPosition
    let positionRevision: UInt64
    let proxy: LiveNativeMapProxy
    let pins: [LivePlacePin]
    let selectedID: String?
    let viewedPins: [String: Date]
    let brand: AstirBrandMode
    let coloredMap: Bool
    let drawing: Bool
    let contentInsets: EdgeInsets
    let showsUserLocation: Bool
    let boundary: LiveDrawnArea?
    let nearbyCenter: CLLocationCoordinate2D?
    let nearbyRadius: Double?
    let nativeSelectionRevision: UUID
    let onSelectPin: (LivePlacePin) -> Void
    let onNativeFeature: (MKMapFeatureAnnotation) -> Void
    let onCameraEnd: (MKCoordinateRegion, MapCamera, Bool) -> Void
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = LiveNativeMapView(frame: .zero)
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "live.map"
        map.showsCompass = true
        map.showsScale = false
        context.coordinator.attach(to: map)
        proxy.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(parent: self, map: map,
            animated: context.transaction.animation != nil && !context.transaction.disablesAnimations)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.detach(from: map)
        map.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private var parent: LiveNativeMap
        private let basemapAppearance = MapBasemapAppearance()
        private var annotations: [String: LiveNativePinAnnotation] = [:]
        private var annotationSnapshot: [AnnotationSnapshot] = []
        private var pinByID: [String: LivePlacePin] = [:]
        private var compactIDs: Set<String> = []
        private var visibleViews: [String: WeakPinView] = [:]
        private var lastPosition: MapCameraPosition?
        private var lastPositionRevision: UInt64?
        private var cameraCommandRevision: UInt64 = 0
        private var pendingCameraAnimation = false
        private var lastSelectionRevision: UUID?
        private var boundarySnapshot: LiveDrawnArea?
        private var boundaryOverlay: MKPolygon?
        private var nearbySnapshot: NearbySnapshot?
        private var nearbyOverlay: MKCircle?
        private var lastBrand: AstirBrandMode?
        private var cameraNotification: Task<Void, Never>?
        private var densityRefresh: Task<Void, Never>?
        private var isUpdating = false
        private lazy var interactionObserver = LiveMapInteractionRecognizer { [weak self] in
            guard let self, !self.parent.drawing else { return }
            self.parent.proxy.positionedByUser = true
            self.parent.onInteraction()
        }

        init(parent: LiveNativeMap) { self.parent = parent }

        func attach(to map: MKMapView) {
            (map as? LiveNativeMapView)?.onLayout = { [weak self, weak map] in
                guard let self, let map else { return }
                self.applyCameraCommand(to: map, animated: self.pendingCameraAnimation)
            }
            map.register(LiveNativePinView.self, forAnnotationViewWithReuseIdentifier: LiveNativePinView.reuseIdentifier)
            interactionObserver.delegate = self
            interactionObserver.cancelsTouchesInView = false
            interactionObserver.delaysTouchesBegan = false
            interactionObserver.delaysTouchesEnded = false
            map.addGestureRecognizer(interactionObserver)
        }

        func detach(from map: MKMapView) {
            (map as? LiveNativeMapView)?.onLayout = nil
            cameraNotification?.cancel()
            densityRefresh?.cancel()
            map.removeGestureRecognizer(interactionObserver)
            if parent.proxy.mapView === map { parent.proxy.mapView = nil }
        }

        func update(parent: LiveNativeMap, map: MKMapView, animated: Bool) {
            self.parent = parent
            pendingCameraAnimation = animated
            parent.proxy.mapView = map
            isUpdating = true
            defer { isUpdating = false }
            basemapAppearance.update(mapView: map, coloredMap: parent.coloredMap,
                                     isDark: parent.brand.prefersDarkInterface)
            let margins = UIEdgeInsets(top: parent.contentInsets.top, left: parent.contentInsets.leading,
                                       bottom: parent.contentInsets.bottom, right: parent.contentInsets.trailing)
            if map.layoutMargins != margins { map.layoutMargins = margins }
            map.isUserInteractionEnabled = !parent.drawing
            map.selectableMapFeatures = parent.drawing ? [] : [.pointsOfInterest]
            map.showsUserLocation = parent.showsUserLocation
            if lastSelectionRevision != parent.nativeSelectionRevision {
                lastSelectionRevision = parent.nativeSelectionRevision
                for feature in map.selectedAnnotations where feature is MKMapFeatureAnnotation {
                    map.deselectAnnotation(feature, animated: false)
                }
            }
            updateAreaOverlays(in: map)
            synchronizePins(in: map)
            applyCameraCommand(to: map, animated: animated)
            refreshDensity(in: map)
        }

        private func applyCameraCommand(to map: MKMapView, animated: Bool) {
            guard lastPosition != parent.position || lastPositionRevision != parent.positionRevision else { return }
            // Region fitting depends on the final view aspect ratio. SwiftUI
            // may update the representable before its first layout; leave the
            // command pending so that layout applies it exactly once.
            guard map.bounds.width.isFinite, map.bounds.height.isFinite,
                  map.bounds.width > 0, map.bounds.height > 0 else { return }
            let contentRect = map.bounds.inset(by: map.layoutMargins)
            if parent.position.region != nil || parent.position.rect != nil {
                guard contentRect.width > 0, contentRect.height > 0 else { return }
            }
            let initial = lastPosition == nil
            lastPosition = parent.position
            lastPositionRevision = parent.positionRevision
            cameraCommandRevision &+= 1
            cameraNotification?.cancel()
            parent.proxy.positionedByUser = false
            let animate = !initial && animated && !UIAccessibility.isReduceMotionEnabled
            if let camera = parent.position.camera {
                let nativeCamera = MKMapCamera(lookingAtCenter: camera.centerCoordinate,
                    fromDistance: camera.distance, pitch: CGFloat(camera.pitch), heading: camera.heading)
                map.setCamera(nativeCamera, animated: animate)
            } else if let region = parent.position.region {
                let fitted = withoutFittingMargins(in: map) { map.regionThatFits(region) }
                let center = MKMapPoint(fitted.center)
                let width = MKMapRect.world.width * fitted.span.longitudeDelta / 360
                let height = width * map.bounds.height / map.bounds.width
                let fullRect = MKMapRect(x: center.x - width / 2, y: center.y - height / 2,
                                         width: width, height: height)
                applyFullBoundsRect(fullRect, contentRect: contentRect, to: map, animated: animate)
            } else if let rect = parent.position.rect {
                let fullRect = withoutFittingMargins(in: map) { map.mapRectThatFits(rect) }
                applyFullBoundsRect(fullRect, contentRect: contentRect, to: map, animated: animate)
            }
        }

        private func applyFullBoundsRect(_ fullRect: MKMapRect, contentRect: CGRect,
                                         to map: MKMapView, animated: Bool) {
            guard !fullRect.isNull, !fullRect.isEmpty,
                  [fullRect.minX, fullRect.minY, fullRect.width, fullRect.height].allSatisfy(\.isFinite) else { return }
            // MapKit centers fitting commands in its inset content rectangle.
            // Supply the geographic part of the desired full-view footprint
            // that belongs there; keep margins stable throughout the animation.
            let contentMapRect = MKMapRect(
                x: fullRect.minX + fullRect.width * (contentRect.minX - map.bounds.minX) / map.bounds.width,
                y: fullRect.minY + fullRect.height * (contentRect.minY - map.bounds.minY) / map.bounds.height,
                width: fullRect.width * contentRect.width / map.bounds.width,
                height: fullRect.height * contentRect.height / map.bounds.height)
            map.setVisibleMapRect(contentMapRect, animated: animated)
        }

        private func withoutFittingMargins<Value>(in map: MKMapView, _ query: () -> Value) -> Value {
            let margins = map.layoutMargins
            let includesSafeArea = map.insetsLayoutMarginsFromSafeArea
            // Zero requested margins still inherit safe-area insets by default.
            // Exclude both while fitting a footprint already computed for bounds.
            map.insetsLayoutMarginsFromSafeArea = false
            map.layoutMargins = .zero
            defer {
                map.insetsLayoutMarginsFromSafeArea = includesSafeArea
                map.layoutMargins = margins
            }
            return query()
        }

        private func synchronizePins(in map: MKMapView) {
            let validPins = parent.pins.filter {
                CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(
                    latitude: $0.place.place.latitude, longitude: $0.place.place.longitude))
            }
            pinByID = Dictionary(validPins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let nextSnapshot = validPins.map {
                AnnotationSnapshot(id: $0.id, title: $0.place.place.canonicalName,
                    latitude: $0.place.place.latitude, longitude: $0.place.place.longitude)
            }
            guard nextSnapshot != annotationSnapshot else { return }
            annotationSnapshot = nextSnapshot
            let removed = annotations.filter { pinByID[$0.key] == nil }
            map.removeAnnotations(Array(removed.values))
            for id in removed.keys { annotations.removeValue(forKey: id) }
            for pin in validPins {
                let coordinate = CLLocationCoordinate2D(latitude: pin.place.place.latitude,
                                                        longitude: pin.place.place.longitude)
                if let annotation = annotations[pin.id] {
                    if annotation.title != pin.place.place.canonicalName { annotation.title = pin.place.place.canonicalName }
                    if annotation.coordinate.latitude != coordinate.latitude || annotation.coordinate.longitude != coordinate.longitude {
                        annotation.coordinate = coordinate
                    }
                } else {
                    let annotation = LiveNativePinAnnotation(id: pin.id, title: pin.place.place.canonicalName,
                                                            coordinate: coordinate)
                    annotations[pin.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
        }

        private func updateAreaOverlays(in map: MKMapView) {
            let brandChanged = lastBrand != parent.brand
            lastBrand = parent.brand
            if boundarySnapshot != parent.boundary || brandChanged {
                if let boundaryOverlay { map.removeOverlay(boundaryOverlay) }
                boundarySnapshot = parent.boundary
                boundaryOverlay = parent.boundary.map {
                    let coordinates = $0.vertices.map(\.coordinate)
                    return MKPolygon(coordinates: coordinates, count: coordinates.count)
                }
                if let boundaryOverlay { map.addOverlay(boundaryOverlay, level: .aboveLabels) }
            }
            let nextNearby = NearbySnapshot(center: parent.nearbyCenter, radius: parent.nearbyRadius)
            if nearbySnapshot != nextNearby || brandChanged {
                if let nearbyOverlay { map.removeOverlay(nearbyOverlay) }
                nearbySnapshot = nextNearby
                nearbyOverlay = nextNearby.map {
                    MKCircle(center: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), radius: $0.radius)
                }
                if let nearbyOverlay { map.addOverlay(nearbyOverlay, level: .aboveLabels) }
            }
        }

        private func refreshDensity(in map: MKMapView) {
            // Query MapKit's spatial index instead of walking the full history
            // during every camera movement. Match the previous 44pt overscan.
            guard map.bounds.width > 0, map.bounds.height > 0 else { return }
            let rect = map.visibleMapRect
            let paddedRect = rect.insetBy(dx: -rect.width * 44 / map.bounds.width,
                                          dy: -rect.height * 44 / map.bounds.height)
            let candidates = map.annotations(in: paddedRect).compactMap { $0 as? LiveNativePinAnnotation }
            let visibleBounds = map.bounds.insetBy(dx: -44, dy: -44)
            let visible = candidates.compactMap { annotation -> (id: String, point: CGPoint)? in
                let point = map.convert(annotation.coordinate, toPointTo: map)
                guard point.x.isFinite, point.y.isFinite, visibleBounds.contains(point) else { return nil }
                return (annotation.pinID, point)
            }
            compactIDs = LivePinDensity.compactIDs(points: visible, selectedID: parent.selectedID)
            let points = Dictionary(visible.map { ($0.id, $0.point) }, uniquingKeysWith: { first, _ in first })
            var nextViews: [String: WeakPinView] = [:]
            for annotation in candidates where points[annotation.pinID] != nil {
                guard let view = map.view(for: annotation) as? LiveNativePinView else { continue }
                configure(view, annotation: annotation, map: map)
                if let point = points[annotation.pinID] {
                    view.isAccessibilityElement = CGRect(x: point.x - 22, y: point.y - 22,
                        width: 44, height: 44).intersects(map.bounds)
                }
                nextViews[annotation.pinID] = WeakPinView(view)
            }
            for (id, reference) in visibleViews where nextViews[id] == nil {
                if let view = reference.view, (view.annotation as? LiveNativePinAnnotation)?.pinID == id {
                    view.isAccessibilityElement = false
                }
            }
            visibleViews = nextViews
        }

        private func configure(_ view: LiveNativePinView, annotation: LiveNativePinAnnotation, map: MKMapView) {
            guard let pin = pinByID[annotation.pinID] else { return }
            view.configure(pin: pin, selected: pin.id == parent.selectedID,
                           viewed: pin.isViewed(dates: parent.viewedPins),
                           compact: compactIDs.contains(pin.id), brand: parent.brand)
            view.onActivate = { [weak self] in
                guard let self, !self.parent.drawing, let pin = self.pinByID[annotation.pinID] else { return }
                self.parent.onSelectPin(pin)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? LiveNativePinAnnotation else { return nil }
            guard let view = mapView.dequeueReusableAnnotationView(withIdentifier: LiveNativePinView.reuseIdentifier,
                                                                  for: pin) as? LiveNativePinView else { return nil }
            configure(view, annotation: pin, map: mapView)
            view.isAccessibilityElement = false
            return view
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view.annotation is MKUserLocation {
                view.isEnabled = false
                view.canShowCallout = false
            }
            refreshDensity(in: mapView)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            guard !isUpdating, !parent.drawing else { return }
            if let pin = annotation as? LiveNativePinAnnotation, let model = pinByID[pin.pinID] {
                mapView.deselectAnnotation(pin, animated: false)
                parent.onSelectPin(model)
            } else if let feature = annotation as? MKMapFeatureAnnotation {
                parent.onNativeFeature(feature)
            }
        }

        @available(iOS 18.0, *)
        func mapView(_ mapView: MKMapView, selectionAccessoryFor annotation: any MKAnnotation) -> MKSelectionAccessory? { nil }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let renderer = basemapAppearance.renderer(for: overlay) { return renderer }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(parent.brand.accent.opacity(0.12))
                renderer.strokeColor = UIColor(parent.brand.accent)
                renderer.lineWidth = 3
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor(parent.brand.accent.opacity(0.05))
                renderer.strokeColor = UIColor(parent.brand.accent.opacity(0.7))
                renderer.lineWidth = 1.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard densityRefresh == nil else { return }
            densityRefresh = Task { @MainActor [weak self, weak mapView] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let mapView else { return }
                self.densityRefresh = nil
                self.refreshDensity(in: mapView)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            densityRefresh?.cancel()
            densityRefresh = nil
            refreshDensity(in: mapView)
            cameraNotification?.cancel()
            let region = LiveNativeMapProxy.fullBoundsRegion(mapView)
            let camera = MapCamera(mapView.camera)
            let userPositioned = parent.proxy.positionedByUser
            let revision = cameraCommandRevision
            cameraNotification = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self, revision == self.cameraCommandRevision else { return }
                self.parent.onCameraEnd(region, camera, userPositioned)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        private struct NearbySnapshot: Equatable {
            let latitude: Double
            let longitude: Double
            let radius: Double
            init?(center: CLLocationCoordinate2D?, radius: Double?) {
                guard let center, CLLocationCoordinate2DIsValid(center), let radius, radius.isFinite, radius > 0 else { return nil }
                latitude = center.latitude
                longitude = center.longitude
                self.radius = radius
            }
        }

        private struct AnnotationSnapshot: Equatable {
            let id: String
            let title: String
            let latitude: Double
            let longitude: Double
        }

        private final class WeakPinView {
            weak var view: LiveNativePinView?
            init(_ view: LiveNativePinView) { self.view = view }
        }
    }
}

@MainActor
class LiveNativeMapView: MKMapView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class LiveNativePinAnnotation: NSObject, MKAnnotation {
    let pinID: String
    @objc dynamic var title: String?
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(id: String, title: String, coordinate: CLLocationCoordinate2D) {
        pinID = id
        self.title = title
        self.coordinate = coordinate
        super.init()
    }
}

struct LiveNativeHostedPin: View, Equatable {
    let state: LiveTotemState
    let categoryEmoji: String
    let selected: Bool
    let viewed: Bool
    let compact: Bool
    let brand: AstirBrandMode
    var body: some View {
        LiveTotemPinView(state: state, categoryEmoji: categoryEmoji,
                        selected: selected, viewed: viewed, compact: compact)
            .environment(\.astirBrandMode, brand)
            .environment(\.colorScheme, brand.prefersDarkInterface ? .dark : .light)
    }
}

final class LiveNativePinView: MKAnnotationView {
    static let reuseIdentifier = "live.native.pin"
    private var host: UIHostingController<LiveNativeHostedPin>?
    private var signature: LiveNativeHostedPin?
    var onActivate: (() -> Void)?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame.size = CGSize(width: 44, height: 44)
        centerOffset = .zero
        clipsToBounds = false
        isEnabled = true
        canShowCallout = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        collisionMode = .circle
        displayPriority = .required
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(pin: LivePlacePin, selected: Bool, viewed: Bool, compact: Bool, brand: AstirBrandMode) {
        accessibilityIdentifier = "live.pin.\(pin.id)"
        accessibilityLabel = pin.accessibilityLabel
        accessibilityValue = compact && !selected ? "Map dot" : "Category pin"
        accessibilityTraits = selected ? [.button, .selected] : .button
        zPriority = selected ? .max : .defaultUnselected
        let root = LiveNativeHostedPin(state: pin.totemState, categoryEmoji: pin.place.categoryEmoji,
            selected: selected, viewed: viewed, compact: compact, brand: brand)
        guard root != signature else { return }
        signature = root
        if let host { host.rootView = root }
        else {
            let controller = UIHostingController(rootView: root)
            controller.view.backgroundColor = .clear
            // Totem's selected halo extends beyond its unchanged 44pt target.
            controller.view.clipsToBounds = false
            controller.view.isUserInteractionEnabled = false
            controller.view.accessibilityElementsHidden = true
            controller.view.frame = bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(controller.view)
            host = controller
        }
        host?.overrideUserInterfaceStyle = brand.prefersDarkInterface ? .dark : .light
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
        signature = nil
    }

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
}

/// Observes a real drag/pinch without preventing MapKit's own recognizers.
final class LiveMapInteractionRecognizer: UIGestureRecognizer {
    private let onInteraction: () -> Void
    private var origin: CGPoint?
    private var hasReportedInteraction = false
    init(onInteraction: @escaping () -> Void) {
        self.onInteraction = onInteraction
        super.init(target: nil, action: nil)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if origin == nil { origin = touches.first?.location(in: view) }
        if observeInteraction(tapCount: touches.map(\.tapCount).max() ?? 0,
                              activeTouchCount: activeTouchCount(in: event), movement: 0) { state = .began }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let origin, let point = touches.first?.location(in: view) else { return }
        if observeInteraction(tapCount: touches.map(\.tapCount).max() ?? 0,
                              activeTouchCount: activeTouchCount(in: event),
                              movement: hypot(point.x - origin.x, point.y - origin.y)) {
            state = .began
        } else if state == .began || state == .changed { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { super.reset(); origin = nil; hasReportedInteraction = false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// Public touch facts are separated from UITouch delivery so zoom and drag
    /// provenance can be checked without manufacturing private touch objects.
    @discardableResult
    func observeInteraction(tapCount: Int, activeTouchCount: Int, movement: CGFloat) -> Bool {
        guard !hasReportedInteraction,
              tapCount >= 2 || activeTouchCount > 1 || movement >= 8 else { return false }
        hasReportedInteraction = true
        onInteraction()
        return true
    }

    private func activeTouchCount(in event: UIEvent) -> Int {
        event.allTouches?.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }.count ?? 0
    }
}
