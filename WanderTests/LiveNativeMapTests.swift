import MapKit
import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class LiveNativeMapTests: XCTestCase {
    func testStablePinConfigurationsSkipNativeWritesWhileSemanticChangesApply() throws {
        let original = try fixturePin()
        let view = NativePropertyRecordingPinView(annotation: nil, reuseIdentifier: LiveNativePinView.reuseIdentifier)
        view.configure(pin: original, selected: false, viewed: false, compact: false, brand: .editorialLight)
        let ownedTraits: UIAccessibilityTraits = [.button, .selected]
        let nativeTraits = view.accessibilityTraits.subtracting(ownedTraits)
        view.recordedWrites.removeAll()
        // A fixture-only suffix must not turn an unchanged semantic value into
        // a write on every refresh. The subclass models that exported getter.
        view.appendsCameraMetadata = true
        for _ in 0..<30 {
            view.configure(pin: original, selected: false, viewed: false, compact: false, brand: .editorialLight)
            view.setAccessibilityVisibility(true)
        }
        XCTAssertTrue(view.recordedWrites.isEmpty, "Unchanged refreshes must not rewrite native annotation properties")
        view.appendsCameraMetadata = false

        original.place.place.canonicalName = "Renamed fixture venue"
        view.configure(pin: original, selected: false, viewed: false, compact: false, brand: .editorialLight)
        XCTAssertEqual(view.accessibilityLabel, original.accessibilityLabel)
        XCTAssertEqual(view.recordedWrites["label"], 1, "Mutable place copy refreshes even when the visual signature matches")

        let state = LiveTotemState(rails: [MapPinOutline(ownership: .social, status: .wannaGo)],
            hasListMembership: true, hasSavedStatus: true, isFeatured: false)
        let changed = LivePlacePin(id: original.id, place: original.place, activities: [], totemState: state)
        view.configure(pin: changed, selected: false, viewed: true, compact: true, brand: .editorialLight)
        XCTAssertEqual(view.accessibilityLabel, changed.accessibilityLabel)
        XCTAssertEqual(view.accessibilityValue, "Map dot")
        let host = try XCTUnwrap(view.subviews.compactMap { $0.next as? UIHostingController<LiveNativeHostedPin> }.first)
        XCTAssertEqual(host.rootView.state, state)
        XCTAssertTrue(host.rootView.viewed, "Viewed presentation is still recomputed and applied")

        view.configure(pin: changed, selected: true, viewed: true, compact: true, brand: .editorialLight)
        XCTAssertEqual(view.accessibilityValue, "Category pin")
        XCTAssertEqual(view.accessibilityTraits.intersection(ownedTraits), [.button, .selected])
        XCTAssertEqual(view.accessibilityTraits.subtracting(ownedTraits), nativeTraits)
        XCTAssertEqual(view.zPriority, .max)
        view.configure(pin: changed, selected: false, viewed: false, compact: true, brand: .editorialLight)
        XCTAssertEqual(view.accessibilityValue, "Map dot")
        XCTAssertEqual(view.accessibilityTraits.intersection(ownedTraits), .button)
        XCTAssertEqual(view.accessibilityTraits.subtracting(ownedTraits), nativeTraits)
        XCTAssertEqual(view.zPriority, .defaultUnselected)
        XCTAssertFalse(host.rootView.viewed)

        view.recordedWrites.removeAll()
        view.setAccessibilityVisibility(false)
        for _ in 0..<30 { view.setAccessibilityVisibility(false) }
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertEqual(view.recordedWrites["visible"], 1)
        view.setAccessibilityVisibility(true)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.recordedWrites["visible"], 2)
        XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44))
    }

    func testPinActivityTimestampCopyRefreshesWithoutVisualSignatureChange() throws {
        let original = try fixturePin()
        let actor = ProfileShell(id: "fixture-actor", handle: "fixture", displayName: "Fixture", avatarURL: nil,
                                 bio: nil, relationship: .mutual)
        let view = NativePropertyRecordingPinView(annotation: nil, reuseIdentifier: LiveNativePinView.reuseIdentifier)
        let now = Date.now
        let older = FeedActivity(id: "fixture-event", kind: .placeBeen, actor: actor, place: original.place,
                                 occurredAt: now.addingTimeInterval(-7_200))
        let recent = FeedActivity(id: older.id, kind: older.kind, actor: actor, place: original.place,
                                  occurredAt: now.addingTimeInterval(-10))
        let before = LivePlacePin(id: original.id, place: original.place, activities: [older], totemState: original.totemState)
        let after = LivePlacePin(id: original.id, place: original.place, activities: [recent], totemState: original.totemState)
        view.configure(pin: before, selected: false, viewed: false, compact: false, brand: .editorialLight)
        let priorLabel = view.accessibilityLabel
        view.recordedWrites.removeAll()
        view.configure(pin: after, selected: false, viewed: false, compact: false, brand: .editorialLight)
        XCTAssertNotEqual(view.accessibilityLabel, priorLabel)
        XCTAssertEqual(view.accessibilityLabel, after.accessibilityLabel)
        XCTAssertEqual(view.recordedWrites, ["label": 1])
    }

    func testStableUpdatesPreserveNativeInteractionConfigurationAndCamera() throws {
        let map = NativeConfigurationRecordingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let proxy = LiveNativeMapProxy()
        let revision = UUID()
        var interactions = 0
        let parent = makeParent(proxy: proxy, pinsRevision: revision, onInteraction: { interactions += 1 })
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()
        map.clearRecordedWrites()

        let observer = try XCTUnwrap(map.gestureRecognizers?.compactMap { $0 as? LiveMapInteractionRecognizer }.first)
        XCTAssertTrue(observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 12))
        XCTAssertEqual(interactions, 1)
        XCTAssertTrue(proxy.positionedByUser)
        for _ in 0..<30 { coordinator.update(parent: parent, map: map, animated: false) }
        XCTAssertTrue(map.interactionWrites.isEmpty)
        XCTAssertTrue(map.featureWrites.isEmpty)
        XCTAssertTrue(map.locationWrites.isEmpty)
        XCTAssertEqual(map.cameraCommandCount, 0)
        XCTAssertTrue(proxy.positionedByUser, "An ordinary interaction redraw must not reapply a camera command")

        let drawing = makeParent(proxy: proxy, pinsRevision: revision, drawing: true, showsUserLocation: true)
        coordinator.update(parent: drawing, map: map, animated: false)
        XCTAssertEqual(map.interactionWrites, [false])
        XCTAssertEqual(map.featureWrites, [MKMapFeatureOptions()])
        XCTAssertEqual(map.locationWrites, [true])
        XCTAssertFalse(map.isUserInteractionEnabled)
        XCTAssertTrue(map.selectableMapFeatures.isEmpty)
        XCTAssertTrue(map.showsUserLocation)
        coordinator.update(parent: drawing, map: map, animated: false)
        XCTAssertEqual(map.interactionWrites.count, 1)
        XCTAssertEqual(map.featureWrites.count, 1)
        XCTAssertEqual(map.locationWrites.count, 1)

        coordinator.update(parent: parent, map: map, animated: false)
        XCTAssertEqual(map.interactionWrites, [false, true])
        XCTAssertEqual(map.featureWrites, [MKMapFeatureOptions(), [.pointsOfInterest]])
        XCTAssertEqual(map.locationWrites, [true, false])
        XCTAssertTrue(map.isUserInteractionEnabled)
        XCTAssertEqual(map.selectableMapFeatures, [.pointsOfInterest])
        XCTAssertFalse(map.showsUserLocation)
        XCTAssertEqual(map.cameraCommandCount, 0)
    }

    func testStableProjectionSkipsDensityButSelectionCameraAndMountedViewsRefresh() throws {
        let map = DensityCountingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let pin = try fixturePin()
        let revision = UUID()
        var parent = makeParent(pins: [pin], pinsRevision: revision)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()
        let initial = map.densityQueries
        for _ in 0..<30 { coordinator.update(parent: parent, map: map, animated: false) }
        XCTAssertEqual(map.densityQueries, initial, "Drawer/modal redraws must not requery stable pin geometry")

        parent = makeParent(pins: [pin], pinsRevision: revision, selectedID: pin.id)
        coordinator.update(parent: parent, map: map, animated: false)
        XCTAssertGreaterThan(map.densityQueries, initial, "Selection changes density priority")
        var prior = map.densityQueries
        coordinator.mapView(map, didAdd: [])
        XCTAssertGreaterThan(map.densityQueries, prior, "New MapKit views need configuration at the same pose")
        prior = map.densityQueries
        map.setCamera(MKMapCamera(lookingAtCenter: region.center, fromDistance: 1_800,
                                 pitch: 40, heading: 25), animated: false)
        coordinator.mapView(map, regionDidChangeAnimated: false)
        XCTAssertGreaterThan(map.densityQueries, prior)
        prior = map.densityQueries
        map.frame.size.width = 320
        map.setNeedsLayout(); map.layoutIfNeeded()
        XCTAssertGreaterThan(map.densityQueries, prior, "Rotation and resized layouts need a fresh footprint")
    }

    func testProjectionGenerationRefreshesSameIDPayloadAndRemoval() throws {
        let map = DensityCountingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let original = try fixturePin()
        var selectedNames: [String] = []
        let parent = makeParent(pins: [original], pinsRevision: UUID(),
            onSelectPin: { selectedNames.append($0.place.place.canonicalName) })
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        let annotation = try XCTUnwrap(map.annotations.first { !($0 is MKUserLocation) })
        let replacement = LocalPlace(localID: original.place.place.id, canonicalName: "Updated park",
            category: "park", latitude: original.place.place.latitude, longitude: original.place.place.longitude)
        let visible = VisiblePlace(id: original.place.id, place: replacement,
            userPlace: original.place.userPlace, owner: original.place.owner)
        let updated = LivePlacePin(id: original.id, place: visible, activities: [],
            totemState: LiveTotemState(rails: [], hasListMembership: true, hasSavedStatus: true, isFeatured: false))
        coordinator.update(parent: makeParent(pins: [updated], pinsRevision: UUID(),
            onSelectPin: { selectedNames.append($0.place.place.canonicalName) }), map: map, animated: false)
        XCTAssertTrue(map.annotations.contains { $0 === annotation })
        XCTAssertEqual(annotation.title ?? nil, "Updated park")
        let view = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation))
        XCTAssertEqual(view.accessibilityLabel, updated.accessibilityLabel)
        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(selectedNames, ["Updated park"])
        coordinator.update(parent: makeParent(pins: [], pinsRevision: UUID()), map: map, animated: false)
        XCTAssertTrue(map.annotations.filter { !($0 is MKUserLocation) }.isEmpty)
    }

    func testDisplayProjectionReplacesAllDerivedCollectionsTogether() throws {
        let pin = try fixturePin()
        let first = LiveMapDisplayProjection(pins: [pin])
        XCTAssertEqual(first.pinIDs, [pin.id])
        XCTAssertEqual(first.pin(id: pin.id)?.id, pin.id)
        XCTAssertEqual(first.persistedPlaceIDs, pin.identity.persistedPlaceIDs)
        XCTAssertNil(first.pin(id: nil))
        let cleared = LiveMapDisplayProjection()
        XCTAssertNotEqual(first.revision, cleared.revision)
        XCTAssertTrue(cleared.pinIDs.isEmpty)
        XCTAssertTrue(cleared.persistedPlaceIDs.isEmpty)
        XCTAssertTrue(cleared.activityIDs.isEmpty)
        XCTAssertNil(cleared.pin(id: pin.id))
    }

    func testCameraCommandWaitsForNonzeroMapLayout() {
        let map = RecordingMapView(frame: .zero)
        let parent = makeParent()
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        let requestedCommandCount = {
            map.rectCommands.filter {
                let center = MKMapPoint(x: $0.midX, y: $0.midY).coordinate
                return abs(center.latitude - self.region.center.latitude) < 0.000001
                    && abs(center.longitude - self.region.center.longitude) < 0.000001
            }.count
        }
        coordinator.update(parent: parent, map: map, animated: false)
        // MapKit can issue its own setup requests while applying configuration.
        // The app's requested footprint must remain pending until layout.
        XCTAssertEqual(requestedCommandCount(), 0)

        map.frame = CGRect(x: 0, y: 0, width: 390, height: 714)
        map.setNeedsLayout()
        map.layoutIfNeeded()
        XCTAssertEqual(requestedCommandCount(), 1)
        XCTAssertEqual(map.region.center.latitude, region.center.latitude, accuracy: 0.00001)
        XCTAssertEqual(map.region.center.longitude, region.center.longitude, accuracy: 0.00001)
        map.setNeedsLayout()
        map.layoutIfNeeded()
        coordinator.update(parent: parent, map: map, animated: false)
        XCTAssertEqual(requestedCommandCount(), 1)
        coordinator.detach(from: map)
    }

    func testContentInsetsPreserveCommandedFullBoundsRegionAndPinSeparation() async throws {
        let size = CGSize(width: 390, height: 714)
        let launch = LiveMapCameraPolicy.locationRegion(region.center)
        let folded = LiveMapSearchLayout(size: size, controlsHeight: 150, drawerHeight: 70)
        let expanded = LiveMapSearchLayout(size: size, controlsHeight: 150, drawerHeight: 343)
        let fitted = try XCTUnwrap(LiveMapViewportPolicy.fittedRegion(launch, size: size,
            from: XCTUnwrap(folded.visibleRect), to: XCTUnwrap(expanded.visibleRect)))
        let plainMap = LiveNativeMapView(frame: CGRect(origin: .zero, size: size))
        let insetMap = LiveNativeMapView(frame: CGRect(origin: .zero, size: size))
        let insetProxy = LiveNativeMapProxy()
        let callback = expectation(description: "full bounds camera callback")
        var reportedRegion: MKCoordinateRegion?
        let plain = makeParent(commandRegion: fitted)
        let inset = makeParent(proxy: insetProxy, commandRegion: fitted,
            contentInsets: EdgeInsets(top: 158, leading: 8, bottom: 355, trailing: 8),
            onCameraEnd: { region, _, _ in reportedRegion = region; callback.fulfill() })
        let plainCoordinator = plain.makeCoordinator(), insetCoordinator = inset.makeCoordinator()
        plainCoordinator.attach(to: plainMap)
        insetCoordinator.attach(to: insetMap)
        plainCoordinator.update(parent: plain, map: plainMap, animated: false)
        insetCoordinator.update(parent: inset, map: insetMap, animated: false)
        plainMap.layoutIfNeeded()
        insetMap.layoutIfNeeded()
        await Task.yield()

        // These commands already represent the full map bounds. Insets only
        // move native controls; they must not fit that footprint a second time.
        let plainFullBounds = plainMap.convert(plainMap.bounds, toRegionFrom: plainMap)
        let insetFullBounds = insetMap.convert(insetMap.bounds, toRegionFrom: insetMap)
        assertRegion(insetFullBounds, equals: plainFullBounds)
        assertRegion(try XCTUnwrap(insetProxy.region), equals: plainFullBounds)
        // The native camera target follows the inset content center. Equal
        // full-bounds projection and scale are the visual camera contract.
        XCTAssertEqual(insetMap.camera.heading, plainMap.camera.heading, accuracy: 0.00001)
        XCTAssertEqual(insetMap.camera.pitch, plainMap.camera.pitch, accuracy: 0.00001)
        XCTAssertEqual(insetMap.layoutMargins, UIEdgeInsets(top: 158, left: 8, bottom: 355, right: 8))
        let nido = CLLocationCoordinate2D(latitude: 34.079, longitude: -118.260)
        let juniper = CLLocationCoordinate2D(latitude: 34.078, longitude: -118.266)
        for coordinate in [nido, juniper] {
            let actual = insetMap.convert(coordinate, toPointTo: insetMap)
            let expected = plainMap.convert(coordinate, toPointTo: plainMap)
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.1)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.1)
        }
        func separation(in map: MKMapView) -> CGFloat {
            let first = map.convert(nido, toPointTo: map), second = map.convert(juniper, toPointTo: map)
            return hypot(first.x - second.x, first.y - second.y)
        }
        XCTAssertEqual(separation(in: insetMap), separation(in: plainMap), accuracy: 0.1)
        insetCoordinator.mapView(insetMap, regionDidChangeAnimated: false)
        await fulfillment(of: [callback], timeout: 1)
        assertRegion(try XCTUnwrap(reportedRegion), equals: plainFullBounds)
        plainCoordinator.detach(from: plainMap)
        insetCoordinator.detach(from: insetMap)
    }

    func testAppearanceAndPinRefreshPreserveCameraAndAnnotationIdentity() throws {
        let map = RecordingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let proxy = LiveNativeMapProxy()
        let pin = try fixturePin()
        var parent = makeParent(proxy: proxy, pins: [pin])
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: parent, map: map, animated: false)
        let originalPin = try XCTUnwrap(map.annotations.first { !($0 is MKUserLocation) })
        let regionCommands = map.regionCommands.count
        let cameraCommands = map.cameraCommands.count
        let rectCommands = map.rectCommands.count
        let originalCamera = map.camera.copy() as! MKMapCamera

        let contentInsets = EdgeInsets(top: 90, leading: 8, bottom: 300, trailing: 8)
        parent = makeParent(proxy: proxy, pins: [pin], coloredMap: true, brand: .editorial, contentInsets: contentInsets)
        coordinator.update(parent: parent, map: map, animated: false)
        coordinator.update(parent: parent, map: map, animated: false)

        XCTAssertEqual(map.regionCommands.count, regionCommands)
        XCTAssertEqual(map.cameraCommands.count, cameraCommands)
        XCTAssertEqual(map.rectCommands.count, rectCommands)
        XCTAssertEqual(map.camera.centerCoordinate.latitude, originalCamera.centerCoordinate.latitude, accuracy: 0.00001)
        XCTAssertEqual(map.camera.centerCoordinate.longitude, originalCamera.centerCoordinate.longitude, accuracy: 0.00001)
        XCTAssertEqual(map.camera.centerCoordinateDistance, originalCamera.centerCoordinateDistance, accuracy: 0.01)
        XCTAssertTrue(map.annotations.contains { $0 === originalPin })
        XCTAssertTrue(map.overlays.isEmpty)
        XCTAssertEqual(map.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(map.layoutMargins, UIEdgeInsets(top: 90, left: 8, bottom: 300, right: 8))
        XCTAssertEqual(map.selectableMapFeatures, [.pointsOfInterest])
        coordinator.detach(from: map)
    }

    func testFullBoundsRegionRoundTripPreservesPinPositionWithBottomSafeArea() throws {
        let map = SafeAreaMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 714))
        let proxy = LiveNativeMapProxy()
        let margins = EdgeInsets(top: 110, leading: 8, bottom: 88, trailing: 8)
        let parent = makeParent(proxy: proxy, positionRevision: 1, contentInsets: margins)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()
        XCTAssertEqual(map.safeAreaInsets.bottom, 32)
        XCTAssertTrue(map.insetsLayoutMarginsFromSafeArea)
        let coordinate = CLLocationCoordinate2D(latitude: 34.079, longitude: -118.260)
        let originalPoint = map.convert(coordinate, toPointTo: map)
        let originalRegion = try XCTUnwrap(proxy.region)

        // Returning from Settings expands the drawer and restores its stored
        // full-bounds region when collapsed. A safe-area inset must not become
        // an extra geographic offset on either programmatic fit.
        let size = map.bounds.size
        let folded = LiveMapSearchLayout(size: size, controlsHeight: 102, drawerHeight: 76)
        let expanded = LiveMapSearchLayout(size: size, controlsHeight: 102, drawerHeight: 343)
        let expandedRegion = try XCTUnwrap(LiveMapViewportPolicy.fittedRegion(originalRegion, size: size,
            from: XCTUnwrap(folded.visibleRect), to: XCTUnwrap(expanded.visibleRect)))
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 2, commandRegion: expandedRegion,
            contentInsets: EdgeInsets(top: 110, leading: 8, bottom: 355, trailing: 8)), map: map, animated: false)
        map.layoutIfNeeded()
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 3, commandRegion: originalRegion,
            contentInsets: margins), map: map, animated: false)
        map.layoutIfNeeded()

        let restoredPoint = map.convert(coordinate, toPointTo: map)
        XCTAssertEqual(restoredPoint.x, originalPoint.x, accuracy: 0.5)
        XCTAssertEqual(restoredPoint.y, originalPoint.y, accuracy: 0.5)
        XCTAssertTrue(map.insetsLayoutMarginsFromSafeArea)
        XCTAssertEqual(map.layoutMargins, UIEdgeInsets(top: 110, left: 8, bottom: 88, right: 8))
        coordinator.detach(from: map)
    }

    func testRepeatedDestinationAfterUserPanUsesExplicitCommandRevision() throws {
        let map = RecordingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let proxy = LiveNativeMapProxy()
        let initial = makeParent(proxy: proxy, positionRevision: 1)
        let coordinator = initial.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: initial, map: map, animated: false)
        let observer = try XCTUnwrap(map.gestureRecognizers?.compactMap { $0 as? LiveMapInteractionRecognizer }.first)
        observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 20)
        let elsewhere = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.13, longitude: -118.32),
                                            span: region.span)
        map.setRegion(elsewhere, animated: false)
        XCTAssertTrue(proxy.positionedByUser)
        let afterPanCommands = map.rectCommands.count

        // An unrelated redraw keeps the user at B, even though the last command
        // was A. Reissuing A with a new revision is an intentional move.
        coordinator.update(parent: initial, map: map, animated: false)
        XCTAssertEqual(map.rectCommands.count, afterPanCommands)
        let repeated = makeParent(proxy: proxy, positionRevision: 2)
        coordinator.update(parent: repeated, map: map, animated: false)

        XCTAssertEqual(map.rectCommands.count, afterPanCommands + 1)
        let destination = try XCTUnwrap(map.rectCommands.last)
        let center = MKMapPoint(x: destination.midX, y: destination.midY).coordinate
        XCTAssertEqual(center.latitude, region.center.latitude, accuracy: 0.000001)
        XCTAssertEqual(center.longitude, region.center.longitude, accuracy: 0.000001)
        XCTAssertFalse(proxy.positionedByUser)
        coordinator.detach(from: map)
    }

    func testTallPreviewRevealsPinToVisibleEdgeUsingNativeCameraAnchor() throws {
        let map = LiveNativeMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 714))
        let proxy = LiveNativeMapProxy()
        let margins = EdgeInsets(top: 120, leading: 8, bottom: 460, trailing: 8)
        let parent = makeParent(proxy: proxy, positionRevision: 1, contentInsets: margins)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()
        let pinCoordinate = try XCTUnwrap(proxy.coordinate(for: CGPoint(x: 280, y: 450)))
        let point = try XCTUnwrap(proxy.point(for: pinCoordinate))
        let camera = try XCTUnwrap(proxy.camera)
        let exposed = try XCTUnwrap(LiveMapSearchLayout(size: map.bounds.size,
            controlsHeight: 120, drawerHeight: 460).visibleRect)
        let offset = LiveMapViewportPolicy.revealOffset(pin: point, exposedRect: exposed)
        XCTAssertGreaterThan(offset.height, 0)
        let center = try XCTUnwrap(proxy.cameraCenter(after: offset, from: camera))
        let revealedCamera = MapCamera(centerCoordinate: center, distance: camera.distance,
                                       heading: camera.heading, pitch: camera.pitch)
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 2,
            commandPosition: .camera(revealedCamera), contentInsets: margins), map: map, animated: false)
        map.layoutIfNeeded()

        let revealedPoint = try XCTUnwrap(proxy.point(for: pinCoordinate))
        XCTAssertEqual(revealedPoint.x, point.x, accuracy: 0.5)
        XCTAssertEqual(revealedPoint.y, exposed.maxY - 24, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(revealedPoint.y, exposed.minY + 24)
        XCTAssertEqual(map.camera.centerCoordinateDistance, camera.distance, accuracy: 0.001)
        coordinator.detach(from: map)
    }

    func testRotatedPitchedPreviewCameraSnapshotRestoresPinGeometryAndScale() throws {
        let map = SafeAreaMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 714))
        let proxy = LiveNativeMapProxy()
        let collapsedMargins = EdgeInsets(top: 110, leading: 8, bottom: 88, trailing: 8)
        let previewMargins = EdgeInsets(top: 110, leading: 8, bottom: 460, trailing: 8)
        let initialCamera = MapCamera(centerCoordinate: region.center, distance: 2_400,
                                      heading: 281, pitch: 35)
        let parent = makeParent(proxy: proxy, positionRevision: 1,
            commandPosition: .camera(initialCamera), contentInsets: collapsedMargins)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()

        // Capture the actual native pose before the preview changes its insets.
        // A bounding region cannot preserve this rotated, pitched projection.
        let snapshot = try XCTUnwrap(proxy.camera)
        XCTAssertEqual(snapshot.heading, 281, accuracy: 0.001)
        XCTAssertEqual(snapshot.pitch, 35, accuracy: 0.001)
        let coordinates = try [CGPoint(x: 260, y: 570), CGPoint(x: 175, y: 460)].map {
            try XCTUnwrap(proxy.coordinate(for: $0))
        }
        let originalPoints = try coordinates.map { try XCTUnwrap(proxy.point(for: $0)) }
        let originalSeparation = hypot(originalPoints[0].x - originalPoints[1].x,
                                       originalPoints[0].y - originalPoints[1].y)
        XCTAssertGreaterThan(originalSeparation, 100)

        // Opening a tall preview changes margins before revealing its pin.
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 1,
            commandPosition: .camera(initialCamera), contentInsets: previewMargins), map: map, animated: false)
        map.layoutIfNeeded()
        let pinPoint = try XCTUnwrap(proxy.point(for: coordinates[0]))
        let previewCamera = try XCTUnwrap(proxy.camera)
        let exposed = try XCTUnwrap(LiveMapSearchLayout(size: map.bounds.size,
            controlsHeight: 102, drawerHeight: 460).visibleRect)
        let offset = LiveMapViewportPolicy.revealOffset(pin: pinPoint, exposedRect: exposed)
        XCTAssertGreaterThan(offset.height, 0, "The fixture must exercise a real preview reveal")
        let revealedCenter = try XCTUnwrap(proxy.cameraCenter(after: offset, from: previewCamera))
        let revealedCamera = MapCamera(centerCoordinate: revealedCenter, distance: previewCamera.distance,
                                       heading: previewCamera.heading, pitch: previewCamera.pitch)
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 2,
            commandPosition: .camera(revealedCamera), contentInsets: previewMargins), map: map, animated: false)
        map.layoutIfNeeded()
        let revealedPoint = try XCTUnwrap(proxy.point(for: coordinates[0]))
        XCTAssertGreaterThan(hypot(revealedPoint.x - originalPoints[0].x,
                                   revealedPoint.y - originalPoints[0].y), 24)

        // Closing must restore the camera snapshot with the collapsed margins,
        // rather than fit the geographic bounding rectangle of the rotated map.
        coordinator.update(parent: makeParent(proxy: proxy, positionRevision: 3,
            commandPosition: .camera(snapshot), contentInsets: collapsedMargins), map: map, animated: false)
        map.layoutIfNeeded()
        let restored = try XCTUnwrap(proxy.camera)
        XCTAssertEqual(restored.centerCoordinate.latitude, snapshot.centerCoordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(restored.centerCoordinate.longitude, snapshot.centerCoordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(restored.distance, snapshot.distance, accuracy: 0.1)
        XCTAssertEqual(restored.heading, snapshot.heading, accuracy: 0.001)
        XCTAssertEqual(restored.pitch, snapshot.pitch, accuracy: 0.001)
        let restoredPoints = try coordinates.map { try XCTUnwrap(proxy.point(for: $0)) }
        for (actual, original) in zip(restoredPoints, originalPoints) {
            XCTAssertEqual(actual.x, original.x, accuracy: 0.5)
            XCTAssertEqual(actual.y, original.y, accuracy: 0.5)
        }
        XCTAssertEqual(hypot(restoredPoints[0].x - restoredPoints[1].x,
                             restoredPoints[0].y - restoredPoints[1].y), originalSeparation, accuracy: 0.5)
    }

    func testGrayscaleSitsBelowColoredAreaAndRadiusAfterToggle() throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let proxy = LiveNativeMapProxy()
        let boundary = try XCTUnwrap(LiveDrawnArea(coordinates: [
            CLLocationCoordinate2D(latitude: 34.07, longitude: -118.28),
            CLLocationCoordinate2D(latitude: 34.07, longitude: -118.25),
            CLLocationCoordinate2D(latitude: 34.09, longitude: -118.25),
            CLLocationCoordinate2D(latitude: 34.09, longitude: -118.28)
        ]))
        var parent = makeParent(proxy: proxy, boundary: boundary, nearbyRadius: 600)
        let coordinator = parent.makeCoordinator()
        coordinator.update(parent: parent, map: map, animated: false)
        let first = map.overlays(in: .aboveLabels)
        XCTAssertEqual(first.count, 3)
        let grayscale = try XCTUnwrap(first.first)
        let area = try XCTUnwrap(first.dropFirst().first)
        let radius = try XCTUnwrap(first.last)
        let grayscaleRenderer = try XCTUnwrap(coordinator.mapView(map, rendererFor: grayscale) as? MKPolygonRenderer)
        let areaRenderer = try XCTUnwrap(coordinator.mapView(map, rendererFor: area) as? MKPolygonRenderer)
        let radiusRenderer = try XCTUnwrap(coordinator.mapView(map, rendererFor: radius) as? MKCircleRenderer)
        XCTAssertEqual(grayscaleRenderer.blendMode, .saturation)
        XCTAssertEqual(areaRenderer.blendMode, .normal)
        XCTAssertEqual(radiusRenderer.blendMode, .normal)
        XCTAssertEqual(areaRenderer.strokeColor, UIColor(AstirBrandMode.editorialLight.accent))
        XCTAssertEqual(radiusRenderer.strokeColor, UIColor(AstirBrandMode.editorialLight.accent.opacity(0.7)))

        parent = makeParent(proxy: proxy, coloredMap: true, boundary: boundary, nearbyRadius: 600)
        coordinator.update(parent: parent, map: map, animated: false)
        XCTAssertEqual(map.overlays(in: .aboveLabels).count, 2)
        parent = makeParent(proxy: proxy, boundary: boundary, nearbyRadius: 600)
        coordinator.update(parent: parent, map: map, animated: false)
        let restored = map.overlays(in: .aboveLabels)
        XCTAssertEqual(restored.count, 3)
        XCTAssertTrue(restored[0] === grayscale)
        XCTAssertTrue(restored[1] === area)
        XCTAssertTrue(restored[2] === radius)
    }

    func testNativeAndAccessibilityPinSelectionUseOriginalModelIdentity() throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let pin = try fixturePin()
        var selections: [String] = []
        let parent = makeParent(pins: [pin], onSelectPin: { selections.append($0.id) })
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: parent, map: map, animated: false)
        let annotation = try XCTUnwrap(map.annotations.first { !($0 is MKUserLocation) })
        let view = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation))

        XCTAssertEqual(view.accessibilityIdentifier, "live.pin.\(pin.id)")
        XCTAssertEqual(view.accessibilityLabel, pin.accessibilityLabel)
        XCTAssertTrue(view.accessibilityTraits.contains(.button))
        XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertFalse(view.canShowCallout)
        coordinator.mapView(map, didSelect: annotation)
        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(selections, [pin.id, pin.id])
        if #available(iOS 18.0, *) {
            XCTAssertNil(coordinator.mapView(map, selectionAccessoryFor: annotation))
        }
        coordinator.detach(from: map)
    }

    func testSamePinTotemAndCategoryChangesRefreshHostedRenderingWithoutChangingHitTarget() throws {
        let original = try fixturePin()
        let view = LiveNativePinView(annotation: nil, reuseIdentifier: LiveNativePinView.reuseIdentifier)
        view.configure(pin: original, selected: false, viewed: false, compact: false, brand: .editorialLight)
        let host = try XCTUnwrap(view.subviews.compactMap {
            $0.next as? UIHostingController<LiveNativeHostedPin>
        }.first)
        XCTAssertEqual(host.rootView.state, original.totemState)
        XCTAssertEqual(host.rootView.categoryEmoji, original.place.categoryEmoji)

        let states = [
            LiveTotemState(rails: [MapPinOutline(ownership: .currentUser, status: .been)],
                hasListMembership: false, hasSavedStatus: true, isFeatured: false),
            LiveTotemState(rails: [MapPinOutline(ownership: .social, status: .been, secondaryStatus: .wannaGo)],
                hasListMembership: true, hasSavedStatus: true, isFeatured: false),
            LiveTotemState(rails: [MapPinOutline(ownership: .featured, status: .been)],
                hasListMembership: true, hasSavedStatus: false, isFeatured: true)
        ]
        for state in states {
            let updated = LivePlacePin(id: original.id, place: original.place, activities: original.activities,
                hasPriorOwnCheckIn: original.hasPriorOwnCheckIn, identity: original.identity, totemState: state)
            view.configure(pin: updated, selected: false, viewed: false, compact: false, brand: .editorialLight)
            XCTAssertEqual(host.rootView.state, state)
            XCTAssertEqual(view.accessibilityIdentifier, "live.pin.\(original.id)")
            XCTAssertEqual(view.accessibilityLabel, updated.accessibilityLabel)
        }

        let park = LocalPlace(localID: original.place.place.id, canonicalName: "Example park", category: "Park",
            latitude: original.place.place.latitude, longitude: original.place.place.longitude)
        let changedCategory = VisiblePlace(id: original.place.id, place: park,
            userPlace: original.place.userPlace, owner: original.place.owner)
        XCTAssertNotEqual(changedCategory.categoryEmoji, original.place.categoryEmoji)
        let updated = LivePlacePin(id: original.id, place: changedCategory, activities: [], totemState: states[2])
        view.configure(pin: updated, selected: false, viewed: false, compact: false, brand: .editorialLight)
        XCTAssertEqual(host.rootView.categoryEmoji, changedCategory.categoryEmoji)
        view.configure(pin: updated, selected: true, viewed: true, compact: true, brand: .editorial)
        XCTAssertTrue(host.rootView.selected)
        XCTAssertTrue(host.rootView.viewed)
        XCTAssertTrue(host.rootView.compact)
        XCTAssertEqual(host.rootView.brand, .editorial)
        XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(view.centerOffset, .zero)
        XCTAssertTrue(view.point(inside: CGPoint(x: 1, y: 1), with: nil))
        XCTAssertTrue(view.point(inside: CGPoint(x: 43, y: 43), with: nil))
        XCTAssertFalse(view.clipsToBounds)
        XCTAssertFalse(host.view.clipsToBounds)
        XCTAssertEqual(view.subviews.count, 1)
    }

    func testCountryAliasArrivalRetainsExactlyOneNativeAnnotationAndHostedMarker() throws {
        let saved = try fixturePin().place
        saved.place.address = "10 Example Street"; saved.place.locality = "Sampleton"
        saved.place.region = "CA"; saved.place.country = "US"
        saved.place.sourceProviderPlaceID = "legacy-hyphen"
        let aliasPlace = LocalPlace(localID: "country-alias", canonicalName: saved.place.canonicalName,
            category: saved.place.category, address: "10 Example St", locality: "Sampleton", region: "CA",
            country: "United States", latitude: saved.place.latitude, longitude: saved.place.longitude,
            sourceProvider: "mapkit", sourceProviderPlaceID: "legacy_underscore")
        let community = LocalProfile(localID: FeaturedCommunityPlaceSignal.ownerID, handle: "featured", displayName: "Featured")
        let alias = VisiblePlace(id: "featured-alias", place: aliasPlace,
            userPlace: LocalUserPlace(localID: "featured-alias", userID: community.id, placeID: aliasPlace.id,
                status: .been, visibility: .followers, sourceType: "featured_community_aggregate"), owner: community)
        let context = LiveTotemContext(currentUserID: saved.owner.id, query: LiveFeedQuery(),
            currentSavedPlaces: [saved], currentListPlaces: [], currentStateIsComplete: true)
        let initial = LiveMapProjection.pins(activities: [], featured: [alias], totemContext: context)
        let map = RecordingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let parent = makeParent(pins: initial)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        let original = try XCTUnwrap(map.annotations.filter { !($0 is MKUserLocation) }.first)
        let refreshed = LiveMapProjection.pins(activities: [], featured: [saved, alias, alias],
            totemContext: context, previousPins: initial)
        coordinator.update(parent: makeParent(pins: refreshed), map: map, animated: false)
        XCTAssertEqual(map.annotations.filter { !($0 is MKUserLocation) }.count, 1)
        XCTAssertTrue(map.annotations.contains { $0 === original })
        let pin = try XCTUnwrap(refreshed.first)
        XCTAssertFalse(pin.totemState.isFeatured)
        let view = LiveNativePinView(annotation: original, reuseIdentifier: LiveNativePinView.reuseIdentifier)
        for compact in [false, true, false, true] {
            view.configure(pin: pin, selected: false, viewed: false, compact: compact, brand: .editorialLight)
            let hosts = view.subviews.compactMap { $0.next as? UIHostingController<LiveNativeHostedPin> }
            let images = view.subviews.compactMap { $0 as? UIImageView }
            XCTAssertEqual(hosts.count + images.count, 1, "Density changes replace the marker, never add another.")
            if compact {
                XCTAssertEqual(images.count, 1)
                XCTAssertNotNil(images.first?.image)
            } else {
                XCTAssertEqual(hosts.count, 1)
                XCTAssertEqual(hosts.first?.rootView.compact, false)
            }
            XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44))
            XCTAssertEqual(view.accessibilityLabel, pin.accessibilityLabel)
            XCTAssertEqual(view.accessibilityValue, compact ? "Map dot" : "Category pin")
        }
    }

    func testHostedPinRetainsColorPixelsAcrossDensityChangesAndReuse() async throws {
        let original = try fixturePin()
        let state = LiveTotemState(rails: [
            MapPinOutline(ownership: .currentUser, status: .been),
            MapPinOutline(ownership: .social, status: .wannaGo)
        ], hasListMembership: false, hasSavedStatus: true, isFeatured: false)
        let pin = LivePlacePin(id: original.id, place: original.place, activities: [], totemState: state)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        let view = LiveNativePinView(annotation: nil, reuseIdentifier: LiveNativePinView.reuseIdentifier)
        controller.view.addSubview(view)
        view.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)

        // Exercise the actual mounted image/hosting paths through density and
        // reuse. Offscreen ImageRenderer alone cannot prove mounted color parity.
        let stages = [("full", false, false), ("dense", true, false),
                      ("full-again", false, false), ("reused-dense", true, true),
                      ("reused-full", false, false)]
        let clock = ContinuousClock()
        for (name, compact, reuse) in stages {
            if reuse {
                view.removeFromSuperview()
                view.prepareForReuse()
            }
            let started = clock.now
            view.configure(pin: pin, selected: false, viewed: reuse, compact: compact, brand: .editorialLight)
            if reuse { controller.view.addSubview(view) }
            window.layoutIfNeeded()
            view.setNeedsLayout()
            view.layoutIfNeeded()
            // Attempt samples during the former 180ms fade, then after it.
            // Rendering can delay a sample; recorded elapsed times define the
            // observed coverage. A density swap must keep colors opaque.
            let sampleTimes = name == "full" ? [400] : [30, 60, 90, 120, 150, 180, 240, 400]
            var observations: [String] = []
            for milliseconds in sampleTimes {
                try await clock.sleep(until: started.advanced(by: .milliseconds(milliseconds)))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                format.preferredRange = .standard
                var rendered = false
                let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
                    rendered = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
                }
                let elapsed = started.duration(to: clock.now)
                let sample = "\(name) at \(elapsed) (target \(milliseconds)ms)"
                XCTAssertTrue(rendered, sample)
                XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44), sample)
                XCTAssertEqual(view.accessibilityIdentifier, "live.pin.\(pin.id)", sample)
                XCTAssertEqual(view.accessibilityLabel, pin.accessibilityLabel, sample)
                let counts = try semanticPixelCounts(image)
                observations.append("\(sample); coral=\(counts[0xF05A3C, default: 0]); blue=\(counts[0x69B8D7, default: 0])")
                for color: UInt32 in [0xF05A3C, 0x69B8D7] {
                    XCTAssertGreaterThan(counts[color, default: 0], 12,
                        "\(sample) lost semantic color \(String(color, radix: 16))")
                }
                if !rendered || counts.values.contains(where: { $0 <= 12 }) {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "hosted-pin-\(name)-\(milliseconds)ms"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            let timing = XCTAttachment(string: observations.joined(separator: "\n"))
            timing.name = "hosted-pin-\(name)-transition-pixels"
            timing.lifetime = .keepAlways
            add(timing)
        }
    }

    private func semanticPixelCounts(_ image: UIImage) throws -> [UInt32: Int] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var counts: [UInt32: Int] = [0xF05A3C: 0, 0x69B8D7: 0]
        for color in Array(counts.keys) {
            let red = Int((color >> 16) & 0xFF), green = Int((color >> 8) & 0xFF), blue = Int(color & 0xFF)
            for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] >= 250 {
                if abs(Int(bytes[index]) - red) <= 5,
                   abs(Int(bytes[index + 1]) - green) <= 5,
                   abs(Int(bytes[index + 2]) - blue) <= 5 {
                    counts[color, default: 0] += 1
                }
            }
        }
        return counts
    }

    func testCameraCallbackUsesCenterDistanceAndActualUserProvenance() async throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let proxy = LiveNativeMapProxy()
        let callback = expectation(description: "camera callback")
        var result: (MapCamera, Bool)?
        let parent = makeParent(proxy: proxy, onCameraEnd: { _, camera, userPositioned in
            if result == nil { result = (camera, userPositioned); callback.fulfill() }
        })
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        coordinator.update(parent: parent, map: map, animated: false)
        let observer = try XCTUnwrap(map.gestureRecognizers?.compactMap { $0 as? LiveMapInteractionRecognizer }.first)
        observer.observeInteraction(tapCount: 2, activeTouchCount: 1, movement: 0)
        map.setCamera(MKMapCamera(lookingAtCenter: region.center, fromDistance: 1_800, pitch: 45, heading: 31), animated: false)
        let actualCamera = map.camera.copy() as! MKMapCamera
        coordinator.mapView(map, regionDidChangeAnimated: false)
        await fulfillment(of: [callback], timeout: 1)

        let received = try XCTUnwrap(result)
        XCTAssertEqual(received.0.distance, actualCamera.centerCoordinateDistance, accuracy: 0.001)
        XCTAssertEqual(received.0.pitch, Double(actualCamera.pitch), accuracy: 0.001)
        XCTAssertEqual(received.0.heading, actualCamera.heading, accuracy: 0.001)
        XCTAssertTrue(received.1)
        XCTAssertEqual(proxy.camera?.distance ?? 0, actualCamera.centerCoordinateDistance, accuracy: 0.001)
        coordinator.detach(from: map)
    }

    func testInteractionObserverDetectsDragAndTapZoomWithoutConsumingOtherRecognizers() {
        var interactions = 0
        let observer = LiveMapInteractionRecognizer { interactions += 1 }
        XCTAssertFalse(observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 0))
        XCTAssertFalse(observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 7))
        XCTAssertTrue(observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 8))
        XCTAssertFalse(observer.observeInteraction(tapCount: 1, activeTouchCount: 1, movement: 20))
        observer.reset()
        XCTAssertTrue(observer.observeInteraction(tapCount: 2, activeTouchCount: 1, movement: 0))
        observer.reset()
        XCTAssertTrue(observer.observeInteraction(tapCount: 1, activeTouchCount: 2, movement: 0))
        XCTAssertEqual(interactions, 3)
        let nativeRecognizer = UIPanGestureRecognizer()
        XCTAssertFalse(observer.canPrevent(nativeRecognizer))
        XCTAssertFalse(observer.canBePrevented(by: nativeRecognizer))
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.082, longitude: -118.267),
                           span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.04))
    }

    private func assertRegion(_ actual: MKCoordinateRegion, equals expected: MKCoordinateRegion,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.center.latitude, expected.center.latitude, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.center.longitude, expected.center.longitude, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.span.latitudeDelta, expected.span.latitudeDelta, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.span.longitudeDelta, expected.span.longitudeDelta, accuracy: 0.00001, file: file, line: line)
    }

    private func fixturePin() throws -> LivePlacePin {
        let store = WanderStore(fixtures: .seed())
        let visible = try XCTUnwrap(store.visiblePlaces().first { $0.place.id == "place_bar_nido" })
        return LivePlacePin(id: visible.place.id, place: visible, activities: [])
    }

    private func makeParent(
        proxy: LiveNativeMapProxy? = nil, positionRevision: UInt64 = 0,
        commandRegion: MKCoordinateRegion? = nil,
        commandPosition: MapCameraPosition? = nil,
        pins: [LivePlacePin] = [], pinsRevision: UUID? = nil, selectedID: String? = nil,
        coloredMap: Bool = false, brand: AstirBrandMode = .editorialLight,
        drawing: Bool = false, showsUserLocation: Bool = false,
        contentInsets: EdgeInsets = EdgeInsets(),
        boundary: LiveDrawnArea? = nil, nearbyRadius: Double? = nil,
        onSelectPin: @escaping (LivePlacePin) -> Void = { _ in },
        onCameraEnd: @escaping (MKCoordinateRegion, MapCamera, Bool) -> Void = { _, _, _ in },
        onInteraction: @escaping () -> Void = {}
    ) -> LiveNativeMap {
        LiveNativeMap(position: .constant(commandPosition ?? .region(commandRegion ?? region)), positionRevision: positionRevision,
            proxy: proxy ?? LiveNativeMapProxy(), pins: pins, pinsRevision: pinsRevision, selectedID: selectedID, viewedPins: [:],
            brand: brand, coloredMap: coloredMap, drawing: drawing, contentInsets: contentInsets, showsUserLocation: showsUserLocation,
            boundary: boundary, nearbyCenter: nearbyRadius == nil ? nil : region.center,
            nearbyRadius: nearbyRadius, nativeSelectionRevision: UUID(), onSelectPin: onSelectPin,
            onNativeFeature: { _ in }, onCameraEnd: onCameraEnd, onInteraction: onInteraction)
    }
}

@MainActor
private final class NativePropertyRecordingPinView: LiveNativePinView {
    var recordedWrites: [String: Int] = [:]
    var appendsCameraMetadata = false

    override var accessibilityIdentifier: String? {
        didSet { recordedWrites["identifier", default: 0] += 1 }
    }
    override var accessibilityLabel: String? {
        didSet { recordedWrites["label", default: 0] += 1 }
    }
    override var accessibilityValue: String? {
        get {
            let base = super.accessibilityValue
            return appendsCameraMetadata ? "\(base ?? "")|live.performance.cameraDistanceMeters=1000" : base
        }
        set { recordedWrites["value", default: 0] += 1; super.accessibilityValue = newValue }
    }
    override var accessibilityTraits: UIAccessibilityTraits {
        didSet { recordedWrites["traits", default: 0] += 1 }
    }
    override var zPriority: MKAnnotationViewZPriority {
        didSet { recordedWrites["priority", default: 0] += 1 }
    }
    override var isAccessibilityElement: Bool {
        didSet { recordedWrites["visible", default: 0] += 1 }
    }
}

@MainActor
private final class NativeConfigurationRecordingMapView: LiveNativeMapView {
    var interactionWrites: [Bool] = []
    var featureWrites: [MKMapFeatureOptions] = []
    var locationWrites: [Bool] = []
    var cameraCommandCount = 0
    private var requestedUserLocation = false

    override var isUserInteractionEnabled: Bool {
        didSet { interactionWrites.append(isUserInteractionEnabled) }
    }
    override var selectableMapFeatures: MKMapFeatureOptions {
        didSet { featureWrites.append(selectableMapFeatures) }
    }
    // Record the configuration contract without starting CoreLocation in this
    // unit test. The interaction/feature setters use the real MapKit behavior.
    override var showsUserLocation: Bool {
        get { requestedUserLocation }
        set { locationWrites.append(newValue); requestedUserLocation = newValue }
    }
    override func setCamera(_ camera: MKMapCamera, animated: Bool) {
        cameraCommandCount += 1
        super.setCamera(camera, animated: animated)
    }
    override func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        cameraCommandCount += 1
        super.setRegion(region, animated: animated)
    }
    override func setVisibleMapRect(_ mapRect: MKMapRect, animated: Bool) {
        cameraCommandCount += 1
        super.setVisibleMapRect(mapRect, animated: animated)
    }
    func clearRecordedWrites() {
        interactionWrites.removeAll()
        featureWrites.removeAll()
        locationWrites.removeAll()
        cameraCommandCount = 0
    }
}

@MainActor
private final class DensityCountingMapView: LiveNativeMapView {
    private(set) var densityQueries = 0
    override func annotations(in mapRect: MKMapRect) -> Set<AnyHashable> {
        densityQueries += 1
        return super.annotations(in: mapRect)
    }
}

@MainActor
private final class RecordingMapView: LiveNativeMapView {
    var regionCommands: [MKCoordinateRegion] = []
    var cameraCommands: [MKMapCamera] = []
    var rectCommands: [MKMapRect] = []
    override func setRegion(_ region: MKCoordinateRegion, animated: Bool) {
        regionCommands.append(region)
        super.setRegion(region, animated: animated)
    }
    override func setCamera(_ camera: MKMapCamera, animated: Bool) {
        cameraCommands.append(camera.copy() as! MKMapCamera)
        super.setCamera(camera, animated: animated)
    }
    override func setVisibleMapRect(_ mapRect: MKMapRect, animated: Bool) {
        rectCommands.append(mapRect)
        super.setVisibleMapRect(mapRect, animated: animated)
    }
}

@MainActor
private final class SafeAreaMapView: LiveNativeMapView {
    override var safeAreaInsets: UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0) }
}
