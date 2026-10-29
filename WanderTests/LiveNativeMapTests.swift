import MapKit
import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class LiveNativeMapTests: XCTestCase {
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
            XCTAssertEqual(hosts.count, 1, "Density changes replace the marker, never add another.")
            XCTAssertEqual(hosts.first?.rootView.compact, compact)
        }
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
        pins: [LivePlacePin] = [], coloredMap: Bool = false, brand: AstirBrandMode = .editorialLight,
        contentInsets: EdgeInsets = EdgeInsets(),
        boundary: LiveDrawnArea? = nil, nearbyRadius: Double? = nil,
        onSelectPin: @escaping (LivePlacePin) -> Void = { _ in },
        onCameraEnd: @escaping (MKCoordinateRegion, MapCamera, Bool) -> Void = { _, _, _ in }
    ) -> LiveNativeMap {
        LiveNativeMap(position: .constant(commandPosition ?? .region(commandRegion ?? region)), positionRevision: positionRevision,
            proxy: proxy ?? LiveNativeMapProxy(), pins: pins, selectedID: nil, viewedPins: [:],
            brand: brand, coloredMap: coloredMap, drawing: false, contentInsets: contentInsets, showsUserLocation: false,
            boundary: boundary, nearbyCenter: nearbyRadius == nil ? nil : region.center,
            nearbyRadius: nearbyRadius, nativeSelectionRevision: UUID(), onSelectPin: onSelectPin,
            onNativeFeature: { _ in }, onCameraEnd: onCameraEnd, onInteraction: {})
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
