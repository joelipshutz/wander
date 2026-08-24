import CoreGraphics
import MapKit
import SwiftUI
import XCTest
@testable import Wander

final class MapHitTestingTests: XCTestCase {
    func testMapChromeContentWidthPreservesInsetsAcrossPhoneSizesAndSafeAreas() {
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 430,
                safeAreaInsets: EdgeInsets()
            ),
            406
        )
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 320,
                safeAreaInsets: EdgeInsets()
            ),
            296
        )
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 844,
                safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 0, trailing: 59)
            ),
            702
        )
    }

    @MainActor
    func testRenderProjectionCacheReusesStableInputsAndRebuildsAfterChange() {
        let cache = MapRenderProjectionCache<String, Int>()
        var builds = 0

        let first = cache.value(for: "stable") {
            builds += 1
            return 41
        }
        let second = cache.value(for: "stable") {
            builds += 1
            return 99
        }
        let changed = cache.value(for: "changed") {
            builds += 1
            return 42
        }

        XCTAssertEqual(first, 41)
        XCTAssertEqual(second, 41)
        XCTAssertEqual(changed, 42)
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(cache.buildCount, 2)
    }

    func testScreenPointWithinMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertTrue(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 146, y: 260),
                nearAny: [marker]
            )
        )
    }

    func testScreenPointOutsideMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertFalse(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 190, y: 260),
                nearAny: [marker]
            )
        )
    }

    func testSearchRankingUsesCachedViewerLocationOrFallsBackToMapCenter() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let viewerLocation = CLLocation(latitude: 40.71, longitude: -74.01)

        let cachedOrigin = MapSearchPerformancePolicy.rankingOrigin(
            viewerLocation: viewerLocation,
            mapRegion: region
        )
        let fallbackOrigin = MapSearchPerformancePolicy.rankingOrigin(
            viewerLocation: nil,
            mapRegion: region
        )

        XCTAssertEqual(cachedOrigin.coordinate.latitude, viewerLocation.coordinate.latitude)
        XCTAssertEqual(cachedOrigin.coordinate.longitude, viewerLocation.coordinate.longitude)
        XCTAssertEqual(fallbackOrigin.coordinate.latitude, region.center.latitude)
        XCTAssertEqual(fallbackOrigin.coordinate.longitude, region.center.longitude)
    }

    func testFeaturedRefreshPolicyOnlyFetchesForFeaturedSource() {
        XCTAssertTrue(MapSearchPerformancePolicy.shouldFetchFeatured(for: .featured))
        XCTAssertFalse(MapSearchPerformancePolicy.shouldFetchFeatured(for: .friends))
        XCTAssertFalse(MapSearchPerformancePolicy.shouldFetchFeatured(for: .you))
    }

    func testCancelingMapSearchRestoresTheSelectionCapturedAtSearchEntry() {
        var session = MapSearchSelectionSession()

        session.begin(selectedPlaceGroupKey: "sushi-fumi")
        session.begin(selectedPlaceGroupKey: "boulevard")
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertEqual(restoredSelection, "sushi-fumi")
        XCTAssertFalse(session.isActive)
    }

    func testCancelingMapSearchKeepsSelectionEmptyWhenSearchStartedEmpty() {
        var session = MapSearchSelectionSession()

        session.begin(selectedPlaceGroupKey: nil)
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertNil(restoredSelection)
        XCTAssertFalse(session.isActive)
    }

    func testCompletingMapSearchKeepsAnExplicitlySelectedResult() {
        var session = MapSearchSelectionSession()

        session.begin(selectedPlaceGroupKey: "sushi-fumi")
        session.finish()
        let selectedResult = session.cancel(
            currentSelectedPlaceGroupKey: "rvr"
        )

        XCTAssertEqual(selectedResult, "rvr")
        XCTAssertFalse(session.isActive)
    }

    func testMapSearchCancelWiresRestorationBeforeDismissingFocus() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let cancelStart = try XCTUnwrap(map.range(of: "private func cancelMapSearch()"))
        let cancelEnd = try XCTUnwrap(
            map.range(
                of: "@MainActor\n    private func handlePresentationResetRequest",
                range: cancelStart.upperBound..<map.endIndex
            )
        )
        let cancellation = map[cancelStart.lowerBound..<cancelEnd.lowerBound]

        XCTAssertTrue(cancellation.contains("mapSearchSelectionSession.cancel("))
        XCTAssertTrue(cancellation.contains("suppressNextQueryAutoSelection = true"))
        XCTAssertTrue(cancellation.contains("selectedPlaceGroupKey = restoredPlaceGroupKey"))
        XCTAssertLessThan(
            try XCTUnwrap(cancellation.range(of: "selectedPlaceGroupKey = restoredPlaceGroupKey")).lowerBound,
            try XCTUnwrap(cancellation.range(of: "isMapSearchFocused = false")).lowerBound
        )
    }

    func testMapSearchPipelineReusesImmediateProjectionWorkWithoutFreshLocationLookup() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("viewerLocation: mapCardViewerLocation"))
        XCTAssertFalse(map.contains("searchOriginLocation"))
        XCTAssertTrue(map.contains("from: renderProjection.visiblePlaceGroups"))
        XCTAssertTrue(map.contains("Task { @MainActor [immediateSavedSuggestions] in"))
        XCTAssertFalse(map.contains("savedTypeaheadSuggestions(for:"))

        let sourceStart = try XCTUnwrap(map.range(of: "private func selectMapSource("))
        let sourceEnd = try XCTUnwrap(
            map.range(of: "private func dismissMoreFilters()", range: sourceStart.upperBound..<map.endIndex)
        )
        let sourceSelection = map[sourceStart.lowerBound..<sourceEnd.lowerBound]
        XCTAssertTrue(sourceSelection.contains("handleFeaturedCameraChange(currentSearchRegion)"))
    }
}

final class MapSelectionMotionTests: XCTestCase {
    func testSubmittedMapSearchCentersEverySelectedResultInTheVisibleMapViewport() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let searchStart = try XCTUnwrap(map.range(of: "private func runMapSearch("))
        let searchEnd = try XCTUnwrap(
            map.range(
                of: "private func beginMapSearchRequest()",
                range: searchStart.upperBound..<map.endIndex
            )
        )
        let submittedSearch = map[searchStart.lowerBound..<searchEnd.lowerBound]
        XCTAssertTrue(submittedSearch.contains("center(on: firstVisiblePlace)"))
        XCTAssertTrue(submittedSearch.contains("center(on: firstCandidate)"))

        let centerStart = try XCTUnwrap(map.range(of: "private func centerSearchSelection("))
        let centerEnd = try XCTUnwrap(
            map.range(
                of: "private func handleNearbyTap()",
                range: centerStart.upperBound..<map.endIndex
            )
        )
        let searchCentering = map[centerStart.lowerBound..<centerEnd.lowerBound]
        XCTAssertTrue(searchCentering.contains("MapSelectionViewport.region("))
        XCTAssertTrue(
            searchCentering.contains("obscuredBottomHeight: selectedPlaceRecenterClearance")
        )
        XCTAssertTrue(searchCentering.contains("cameraRegionTracker.region = region"))
    }

    func testSelectedCoordinateCentersInsideTheUnobscuredMapHeight() {
        let coordinate = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        let viewportHeight: CGFloat = 800
        let obscuredBottomHeight: CGFloat = 240

        let region = MapSelectionViewport.region(
            centeredOn: coordinate,
            preserving: span,
            viewportHeight: viewportHeight,
            obscuredBottomHeight: obscuredBottomHeight
        )

        let projectedY = viewportHeight * (
            0.5 - CGFloat(coordinate.latitude - region.center.latitude) / CGFloat(region.span.latitudeDelta)
        )
        XCTAssertEqual(projectedY, (viewportHeight - obscuredBottomHeight) / 2, accuracy: 0.001)
        XCTAssertEqual(region.span.latitudeDelta, span.latitudeDelta)
        XCTAssertEqual(region.span.longitudeDelta, span.longitudeDelta)
        XCTAssertEqual(region.center.longitude, coordinate.longitude)
    }

    func testNearbyBadgeReflectsLocationAuthorization() {
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .notDetermined))
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .denied))
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .restricted))
        XCTAssertFalse(MapNearbyPermissionPolicy.showsAttentionBadge(for: .authorizedWhenInUse))
        XCTAssertFalse(MapNearbyPermissionPolicy.showsAttentionBadge(for: .authorizedAlways))
    }

    @MainActor
    func testSelectionMotionUsesAStagedCardAndBouncyPinContract() {
        XCTAssertEqual(MapCompactCardMotionStyle.entranceDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(MapCompactCardMotionStyle.nearbyFadeDuration, 0.16, accuracy: 0.001)
        XCTAssertEqual(MapCompactCardMotionStyle.nearbyReturnFadeDuration, 0.16, accuracy: 0.001)
        XCTAssertLessThanOrEqual(MapCompactCardMotionStyle.hiddenVerticalOffset, 220)
        XCTAssertEqual(MapPinSelectionMotionStyle.inactiveScale, 0.90, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.selectedScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.duration, 0.18, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.bounce, 0.32, accuracy: 0.001)
        XCTAssertEqual(MapPinFocusMotionStyle.duration, 0.22, accuracy: 0.001)
    }

    func testSelectedPinFocusUsesASmoothDistanceFalloff() {
        let selected = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)

        let collidingPinOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.999),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let midFalloffOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.98),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let distantPinOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.95),
            selectedCoordinate: selected,
            regionSpan: span
        )

        XCTAssertEqual(collidingPinOpacity, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(midFalloffOpacity, MapPinFocusPolicy.minimumOpacity)
        XCTAssertLessThan(midFalloffOpacity, 1)
        XCTAssertEqual(distantPinOpacity, 1, accuracy: 0.001)
    }

    func testSelectedPinFocusClearsWithoutASelection() {
        let opacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            selectedCoordinate: nil,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        )

        XCTAssertEqual(opacity, 1, accuracy: 0.001)
    }

    func testSelectedPinFocusMovesToTheReplacementSelection() {
        let firstSelection = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let replacementSelection = CLLocationCoordinate2D(latitude: 34, longitude: -117.96)
        let nearbyFirstPin = CLLocationCoordinate2D(latitude: 34, longitude: -117.999)
        let nearbyReplacementPin = CLLocationCoordinate2D(latitude: 34, longitude: -117.961)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)

        let firstPinBeforeReplacement = MapPinFocusPolicy.opacity(
            for: nearbyFirstPin,
            selectedCoordinate: firstSelection,
            regionSpan: span
        )
        let firstPinAfterReplacement = MapPinFocusPolicy.opacity(
            for: nearbyFirstPin,
            selectedCoordinate: replacementSelection,
            regionSpan: span
        )
        let replacementPinBeforeSelection = MapPinFocusPolicy.opacity(
            for: nearbyReplacementPin,
            selectedCoordinate: firstSelection,
            regionSpan: span
        )
        let replacementPinAfterSelection = MapPinFocusPolicy.opacity(
            for: nearbyReplacementPin,
            selectedCoordinate: replacementSelection,
            regionSpan: span
        )

        XCTAssertEqual(firstPinBeforeReplacement, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
        XCTAssertEqual(firstPinAfterReplacement, 1, accuracy: 0.001)
        XCTAssertEqual(replacementPinBeforeSelection, 1, accuracy: 0.001)
        XCTAssertEqual(replacementPinAfterSelection, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
    }

    func testSelectedPinFocusUsesAnEllipticalVerticalFalloff() {
        let selected = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        let horizontalOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.98),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let verticalOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34.02, longitude: -118),
            selectedCoordinate: selected,
            regionSpan: span
        )

        XCTAssertGreaterThan(verticalOpacity, horizontalOpacity)
    }

    @MainActor
    func testFirstVisitPhotoIndexReusesWarmProjection() {
        let store = WanderStore(fixtures: WanderFixtures.seed())

        _ = store.firstVisitPhotosByPlaceID()
        _ = store.firstVisitPhotosByPlaceID()
        _ = store.firstVisitPhotosByPlaceID()

        XCTAssertEqual(store.firstVisitPhotoIndexBuildCount, 1)
    }

    func testColdSurfaceWorkIsDeferredAndLazy() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let placeCard = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Map/PlaceProfileMapSurface.swift"
            )
        )

        XCTAssertTrue(feed.contains("await Task.yield()"))
        XCTAssertTrue(feed.contains("LazyHStack(alignment: .top"))
        XCTAssertTrue(placeCard.contains(".onAppear(perform: onReady)"))
        XCTAssertTrue(placeCard.contains("PlaceProfileCategoryThumb(emoji: place.categoryEmoji, size: 72)"))
        XCTAssertTrue(placeCard.contains("PlacePhotoImagePipeline.shared.image("))
        XCTAssertTrue(placeCard.contains("VisitPhotoLocalFileStore.data(from: localAssetRef)"))
        XCTAssertFalse(placeCard.contains("return await image.byPreparingForDisplay() ?? image"))
        XCTAssertTrue(placeCard.contains("withAnimation(.easeOut(duration: 0.10))"))
    }

    @MainActor
    func testActivePinRemainsInAnnotationsWhenAViewportRefreshDropsIt() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let allPlaces = store.visiblePlaces()
        let activePlace = try XCTUnwrap(allPlaces.first)
        let refreshedPlaces = allPlaces.filter { $0.id != activePlace.id }

        let retainedPlaces = MapActivePinRetention.places(
            from: refreshedPlaces,
            retaining: activePlace
        )

        XCTAssertEqual(retainedPlaces.filter { $0.id == activePlace.id }.count, 1)
        XCTAssertEqual(
            MapActivePinRetention.places(
                from: allPlaces,
                retaining: activePlace
            ).filter { $0.id == activePlace.id }.count,
            1
        )

        let retainedGroup = VisiblePlaceGrouping.matchingGroup(
            for: activePlace,
            in: retainedPlaces,
            currentUserID: store.currentUser.id
        )
        XCTAssertNotNil(retainedGroup)
    }

    func testActivePinRefreshRegressionFixtureRequiresPersistentSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-selected-pin-regional-refresh-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_refresh_result"] as? [String: Any])

        XCTAssertEqual(expected["selected_place_id"] as? String, "selected-place-b")
        XCTAssertEqual(expected["selected_pin_is_annotated"] as? Bool, true)
    }

    func testPinchZoomRegressionFixtureRequiresSelectionAndCardToRemainPresented() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-pinch-zoom-selection-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_result"] as? [String: Any])

        XCTAssertEqual(expected["selected_place_id"] as? String, "selected-place-a")
        XCTAssertEqual(expected["compact_card_phase"] as? String, "presented")
        XCTAssertEqual(expected["pinch_zoom_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["empty_map_tap_dismisses_selection"] as? Bool, true)
        XCTAssertEqual(expected["one_finger_pan_dismisses_selection"] as? Bool, true)
        XCTAssertEqual(expected["active_pin_title_clearance_points"] as? Int, 2)
    }

    func testCameraGestureClassificationKeepsEveryZoomAndDismissesOnlyAPan() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let oneFingerZoom = MKCoordinateRegion(
            center: start.center,
            span: MKCoordinateSpan(latitudeDelta: 0.075, longitudeDelta: 0.09)
        )
        let pinchZoom = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.052, longitude: -118.248),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.168)
        )
        let panWithLongitudeSpanDrift = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.065, longitude: -118.225),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.121)
        )

        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: oneFingerZoom), .zoom)
        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: pinchZoom), .zoom)
        XCTAssertEqual(
            MapSelectionGesturePolicy.classify(from: start, to: panWithLongitudeSpanDrift),
            .pan
        )
        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: start), .stationary)
        XCTAssertEqual(MapSelectionGesturePolicy.minimumMagnificationDelta, 0.01)
        XCTAssertGreaterThan(MapSelectionGesturePolicy.tapDismissalDelayNanoseconds, 250_000_000)
        XCTAssertGreaterThanOrEqual(MapSelectionGesturePolicy.postZoomTapSuppressionDuration, 0.5)
        XCTAssertLessThanOrEqual(
            MapSelectionGesturePolicy.doubleTapRecognitionWindow,
            Double(MapSelectionGesturePolicy.tapDismissalDelayNanoseconds) / 1_000_000_000
        )
    }

    func testSelectionLifetimeIgnoresMapKitBindingClear() {
        XCTAssertTrue(MapSelectionLifetimePolicy.shouldDismiss(for: .emptyMapTap))
        XCTAssertTrue(MapSelectionLifetimePolicy.shouldDismiss(for: .oneFingerPan))
        XCTAssertFalse(
            MapSelectionLifetimePolicy.shouldDismiss(for: .nativeFeatureBindingCleared)
        )
    }

    func testSelectionLifetimeAndLayeringFixtureRequiresDurableTopmostSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-selection-lifetime-layering-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_results"] as? [String: Any])

        XCTAssertEqual(expected["one_finger_zoom_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["selection_lifetime"] as? String, "unbounded_until_explicit_dismissal")
        XCTAssertEqual(expected["native_feature_binding_clear_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["active_pin_and_title_render_after_all_inactive_annotations"] as? Bool, true)

        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let inactiveAnnotations = try XCTUnwrap(map.range(of: "ForEach(inactiveAnnotationGroups"))
        let activeAnnotation = try XCTUnwrap(
            map.range(of: "if highlightsCompactSelection, let group = activeAnnotationGroup")
        )

        XCTAssertLessThan(inactiveAnnotations.lowerBound, activeAnnotation.lowerBound)
        XCTAssertFalse(map.contains("activeMapAnnotationOverlay"))
        XCTAssertFalse(map.contains("proxy.convert(coordinate, to: .local)"))
    }

    func testMapInteractionSourceKeepsReplacementMountedAndAddsPanDismissal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let card = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )

        XCTAssertTrue(map.contains("DragGesture(minimumDistance: MapHitTesting.panDismissalDistance"))
        XCTAssertTrue(map.contains("MagnifyGesture(minimumScaleDelta: MapSelectionGesturePolicy.minimumMagnificationDelta)"))
        XCTAssertTrue(map.contains("handleMapMagnificationChange()"))
        XCTAssertTrue(map.contains("registerMapZoom()"))
        XCTAssertTrue(map.contains("tapDate.timeIntervalSince(previousMapTapDate)"))
        XCTAssertTrue(map.contains("let tapRegion = currentSearchRegion"))
        XCTAssertTrue(map.contains("Date.now >= mapTapDismissalSuppressionUntil"))
        XCTAssertTrue(map.contains("handleMapDragChange()"))
        XCTAssertTrue(map.contains("handleMapDragEnd()"))
        XCTAssertTrue(map.contains("handleMapCameraChange(context.region)"))
        XCTAssertTrue(map.contains(".onMapCameraChange(frequency: .onEnd)"))
        XCTAssertTrue(map.contains("@State private var cameraRegionTracker"))
        XCTAssertFalse(map.contains("@State private var currentSearchRegion"))
        XCTAssertTrue(map.contains("cameraRegionTracker.region = region"))
        XCTAssertTrue(map.contains("requestCompactSelectionDismissal(trigger: .oneFingerPan)"))
        XCTAssertTrue(map.contains("requestCompactSelectionDismissal(trigger: .nativeFeatureBindingCleared)"))
        XCTAssertTrue(map.contains("ActiveMapAnnotationContent"))
        XCTAssertTrue(map.contains("if highlightsCompactSelection, let group = activeAnnotationGroup"))
        XCTAssertTrue(map.contains("if highlightsCompactSelection, let candidate = activeSearchCandidate"))
        XCTAssertFalse(map.contains("activeMapAnnotationOverlay"))
        XCTAssertFalse(map.contains("proxy.convert(coordinate, to: .local)"))
        XCTAssertTrue(map.contains("replaceCompactSelectionIfNeeded"))
        XCTAssertFalse(map.contains("replacementFadeOutDuration"))
        XCTAssertTrue(map.contains("MapActivePinRetention.places("))
        XCTAssertTrue(map.contains("routedVisiblePlace = visiblePlace"))
        XCTAssertTrue(map.contains("let retainedGroup = VisiblePlaceGrouping.matchingGroup("))
        XCTAssertTrue(map.contains("compactCardContentOpacity"))
        XCTAssertTrue(map.contains("nearbyFadeAnimation"))
        XCTAssertTrue(map.contains("nearbyReturnFadeAnimation"))
        XCTAssertTrue(map.contains("centerCompactSelection(on: candidate)"))
        XCTAssertFalse(map.contains("Dropped pin. Tap + to add it."))
        XCTAssertTrue(card.contains(".textSelection(.enabled)"))
        XCTAssertTrue(card.contains("Label(\"Copy coordinates\", systemImage: \"doc.on.doc\")"))
        XCTAssertFalse(card.contains(".transition(.move(edge: .bottom).combined(with: .opacity))"))
    }

    func testWalkthroughUsesTheCanonicalHotchkissFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let add = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )

        XCTAssertTrue(
            add.contains("candidate = suggested ?? FirstVisitParkSuggestionPolicy.hotchkissPark")
        )
        XCTAssertFalse(add.contains("private static let hotchkissParkCandidate"))
    }

    func testActiveMapAnnotationsDoNotRenderDuplicateNativeTitles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let emptyTitleAnnotations = map.components(
            separatedBy: "Annotation(\n                                \"\","
        ).count - 1

        XCTAssertEqual(emptyTitleAnnotations, 2)
    }

    func testProviderPhotoTransportReusesSessionAndProtocolCaching() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repository = try String(
            contentsOf: root.appendingPathComponent(
                "Wander/Services/Remote/SupabaseRepositories.swift"
            )
        )

        XCTAssertTrue(repository.contains("private let photoSession: URLSession"))
        XCTAssertTrue(repository.contains("photoSession: URLSession = .shared"))
        XCTAssertTrue(repository.contains("request.cachePolicy = .useProtocolCachePolicy"))
        XCTAssertTrue(repository.contains("photoSession.data(for: request)"))
        XCTAssertFalse(repository.contains("request.setValue(\"no-store\""))
        XCTAssertFalse(repository.contains("defer { session.invalidateAndCancel() }"))
    }

    func testNearbyPermissionEducationIsGatedBeforeTheSystemRequest() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("MapNearbyPermissionPolicy.showsAttentionBadge"))
        XCTAssertTrue(map.contains("MapLocationEducationPrompt("))
        XCTAssertTrue(map.contains("map.locationEducation.allow"))
        XCTAssertTrue(map.contains("map.locationEducation.cancel"))
        XCTAssertTrue(map.contains("locationPermission.requestAccess()"))
        XCTAssertTrue(map.contains("WanderAnalyticsEvents.locationPermissionResult"))
        XCTAssertTrue(map.contains("guard Self.canShowUserLocation else"))
    }
}

final class MapCoordinateCandidateTests: XCTestCase {
    @MainActor
    func testCoordinateCandidateUsesDroppedPinWithFallbackCategory() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.083238, longitude: -118.361472)

        let candidate = MapScreen.coordinateCandidate(at: coordinate)

        XCTAssertEqual(candidate.id, "coordinate_3408324_-11836147")
        XCTAssertEqual(candidate.name, "Dropped Pin")
        XCTAssertEqual(candidate.address, "34.08324, -118.36147")
        XCTAssertEqual(candidate.category, WanderPlaceCategory.fallbackPlace)
        XCTAssertEqual(candidate.primaryCategory, WanderPlaceCategory.fallbackPlace)
        XCTAssertNil(candidate.subcategory)
        XCTAssertEqual(candidate.categorySource, PlaceCategorySource.unknown.rawValue)
        XCTAssertEqual(candidate.sourceProvider, "coordinate")
        XCTAssertEqual(candidate.sourceProviderPlaceID, candidate.id)
        XCTAssertEqual(candidate.latitude, coordinate.latitude)
        XCTAssertEqual(candidate.longitude, coordinate.longitude)
    }

    @MainActor
    func testCoordinateDisplayRoundsToFiveDecimals() {
        let coordinate = CLLocationCoordinate2D(latitude: 33.999994, longitude: -118.000005)

        XCTAssertEqual(MapScreen.coordinateDisplay(for: coordinate), "33.99999, -118.00001")
    }

    @MainActor
    func testCoordinateCandidateCarriesResolvedCityIntoCopyableCardMetadata() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.083238, longitude: -118.361472)
        let candidate = MapScreen.coordinateCandidate(at: coordinate, locality: "West Hollywood")
        let place = PlaceSheetPlace(candidate: candidate)

        XCTAssertEqual(candidate.locality, "West Hollywood")
        XCTAssertTrue(place.isDroppedPin)
        XCTAssertEqual(place.locality, "West Hollywood")
        XCTAssertEqual(place.droppedPinCoordinateDisplay, "34.08324, -118.36147")
    }

    func testDroppedPinNameIsScopedToTheVisibleMemoryAttributes() throws {
        let customName = PlaceAttributeDraft(
            questionKey: PlaceMemoryAttributeKeys.droppedPinName,
            valueType: "text",
            stringValue: "Sunday overlook"
        )
        let localAttribute = LocalPlaceAttribute(
            localID: "local_attr_dropped_pin_name",
            userPlaceID: "up_dropped_pin",
            questionKey: customName.questionKey,
            valueType: customName.valueType,
            valueJSON: customName.valueJSON
        )

        XCTAssertEqual(
            DroppedPinNamePolicy.displayName(
                canonicalName: "Dropped Pin",
                sourceProvider: "coordinate",
                attributes: [localAttribute]
            ),
            "Sunday overlook"
        )
        XCTAssertEqual(
            DroppedPinNamePolicy.displayName(
                canonicalName: "Canonical Cafe",
                sourceProvider: "apple_maps",
                attributes: [localAttribute]
            ),
            "Canonical Cafe"
        )
        XCTAssertEqual(DroppedPinNamePolicy.normalized("   "), nil)
    }
}

final class MapFilterSelectionTests: XCTestCase {
    func testSourcePillsUseFeaturedFriendsAndYouContract() {
        XCTAssertEqual(MapSource.allCases, [.featured, .friends, .you])
        XCTAssertEqual(MapSource.featured.title, "Featured")
        XCTAssertEqual(MapSource.friends.title, "Friends")
        XCTAssertEqual(MapSource.you.title, "You")
        XCTAssertEqual(MapSource.featured.systemImage, "sparkles")
        XCTAssertEqual(MapSource.friends.systemImage, "person.2.fill")
        XCTAssertEqual(MapSource.you.systemImage, "person.fill")
        XCTAssertEqual(
            MapSource.featured.subtitle,
            "Featured shows you recommendations based on your taste"
        )
        XCTAssertEqual(
            MapSource.friends.subtitle,
            "All places from everyone you follow"
        )
        XCTAssertEqual(
            MapSource.you.subtitle,
            "Only your check-ins and Wanna Go places"
        )
    }

    func testSourceFilterRowFitsWithoutHorizontalScrolling() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let filterRow = try XCTUnwrap(
            map.components(separatedBy: "if !isMapSearchFocused {").last?
                .components(separatedBy: "if let mapFilterEmptyMessage").first
        )

        XCTAssertFalse(filterRow.contains("ScrollView(.horizontal"))
        XCTAssertTrue(filterRow.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        XCTAssertTrue(filterRow.contains(".frame(minWidth: 44, minHeight: 48)"))
    }

    func testMapControlHierarchyKeepsFiltersAboveTheMapAndSearchAboveTabs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let filters = try XCTUnwrap(map.range(of: "if !isMapSearchFocused {"))
        let mapSpace = try XCTUnwrap(
            map.range(of: "Spacer()", range: filters.upperBound..<map.endIndex)
        )
        let search = try XCTUnwrap(
            map.range(of: "SearchBar(", range: mapSpace.upperBound..<map.endIndex)
        )

        XCTAssertLessThan(filters.lowerBound, mapSpace.lowerBound)
        XCTAssertLessThan(mapSpace.lowerBound, search.lowerBound)
        XCTAssertTrue(
            map.contains(
                "mapSearchDockClearance + MapControlLayout.selectedPlaceCardSearchGap"
            )
        )
        XCTAssertTrue(map.contains("static let selectedPlaceCardSearchGap: CGFloat = 12"))
        XCTAssertTrue(map.contains("MapSearchDockHeightPreferenceKey"))
        XCTAssertTrue(map.contains("measuredMapSearchDockHeight = height"))
        XCTAssertTrue(map.contains(".overlay(alignment: .bottomTrailing)"))
        XCTAssertTrue(
            map.contains(
                "if !isPlaceProfilePresented && !isMapSearchFocused"
            )
        )
        XCTAssertTrue(map.contains("mapSearchDockClearance + nearbyLift"))
    }

    func testMoreSectionsMatchTheActiveSource() {
        XCTAssertFalse(MapMoreFilterPolicy.showsPeople(for: .featured))
        XCTAssertFalse(MapMoreFilterPolicy.showsStatus(for: .featured))

        XCTAssertTrue(MapMoreFilterPolicy.showsPeople(for: .friends))
        XCTAssertTrue(MapMoreFilterPolicy.showsStatus(for: .friends))

        XCTAssertFalse(MapMoreFilterPolicy.showsPeople(for: .you))
        XCTAssertTrue(MapMoreFilterPolicy.showsStatus(for: .you))
        XCTAssertEqual(MapMoreFilterPolicy.collapsedCategoryCount, 6)
        XCTAssertEqual(MapMoreFilterPolicy.categories(showingAll: false).count, 6)
        XCTAssertEqual(
            MapMoreFilterPolicy.categories(showingAll: false),
            Array(WanderPlaceCategory.editableCategories.prefix(6))
        )
        XCTAssertEqual(
            MapMoreFilterPolicy.categories(showingAll: true),
            WanderPlaceCategory.editableCategories
        )
    }

    func testPinEntranceStaysInsideTheShortMotionBudget() {
        XCTAssertEqual(MapPinEntranceStyle.duration, 0.40, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(MapPinEntranceStyle.hiddenScale, 0.70)
        XCTAssertLessThan(MapPinEntranceStyle.hiddenScale, 0.80)
        XCTAssertGreaterThan(MapPinEntranceStyle.hiddenVerticalOffset, 0)
        XCTAssertEqual(MapPinEntranceStyle.springBounce, 0.60, accuracy: 0.001)
        XCTAssertLessThan(MapPinEntranceStyle.fadeOutDuration, MapPinEntranceStyle.springDuration)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: -1), 0, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 1), 0.015, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 100), 0.06, accuracy: 0.001)
    }

    func testPinEntrancePresentationTransitionsFromCapturedHiddenState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureData = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-303-map-pin-entrance-bounce-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let snapshot = try XCTUnwrap(fixture["snapshot"] as? [String: Bool])
        let isVisible = try XCTUnwrap(snapshot["isVisible"])
        let reduceMotion = try XCTUnwrap(snapshot["reduceMotion"])
        let initiallyVisible = try XCTUnwrap(snapshot["presentationInitiallyVisible"])
        var presentation = MapPinEntrancePresentation()

        XCTAssertEqual(presentation.isPresented, initiallyVisible)
        XCTAssertEqual(
            presentation.renderedVisibility(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            initiallyVisible
        )

        presentation.setVisible(isVisible)

        XCTAssertTrue(presentation.isPresented)
        XCTAssertTrue(
            presentation.renderedVisibility(isVisible: isVisible, reduceMotion: reduceMotion)
        )

        presentation.setVisible(false)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(
            presentation.renderedVisibility(isVisible: true, reduceMotion: true)
        )
    }

    func testFilterTransitionIsScopedToPinsAndKeepsLiquidGlass() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let theme = try String(
            contentsOf: root.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let filterChipSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSourceFilterChip: View {").last?
                .components(separatedBy: "private struct MapMoreFilterChip: View {").first
        )

        XCTAssertFalse(filterChipSource.contains(".scaleEffect("))
        XCTAssertTrue(map.contains("visibleTransitionGroupKeys?.contains(group.key)"))
        XCTAssertTrue(map.contains("MapPinEntranceModifier("))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenScale"))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenVerticalOffset"))
        XCTAssertTrue(map.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        let pinModifier = try XCTUnwrap(
            map.components(separatedBy: "private struct MapPinEntranceModifier: ViewModifier {").last?
                .components(separatedBy: "enum MapStatusFilter").first
        )
        XCTAssertTrue(
            pinModifier.contains(
                "@State private var presentation = MapPinEntrancePresentation()"
            )
        )
        XCTAssertTrue(pinModifier.contains(".onAppear"))
        XCTAssertTrue(pinModifier.contains(".onChange(of: isVisible)"))
        XCTAssertTrue(pinModifier.contains("presentation.setVisible(visible)"))
        XCTAssertTrue(pinModifier.contains("withAnimation("))
        XCTAssertTrue(map.contains("mapPressLocation.location = value.location"))
        XCTAssertFalse(map.contains("@State private var lastMapPressPoint"))
        XCTAssertFalse(map.contains("incomingGroups + departingGroups"))
        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *) {"))
        XCTAssertFalse(theme.contains("isElevated"))
    }

    func testMapSearchCapsuleUsesLiquidGlassOnIOS26WithFlatFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let searchBarSource = try XCTUnwrap(
            map.components(separatedBy: "private struct SearchBar: View {").last?
                .components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier {").first
        )
        let searchSurfaceSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier {").last?
                .components(separatedBy: "private struct MapSearchCancelButton: View {").first
        )
        let filterChipSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSourceFilterChip: View {").last?
                .components(separatedBy: "private struct MapMoreFilterChip: View {").first
        )

        XCTAssertTrue(searchBarSource.contains(".mapSearchCapsuleSurface()"))
        XCTAssertFalse(searchBarSource.contains(".wanderGlassCapsule()"))
        XCTAssertTrue(searchBarSource.contains("minHeight: isFocused.wrappedValue ? 56 : 48"))
        XCTAssertTrue(searchBarSource.contains(".snappy(duration: 0.24, extraBounce: 0.08)"))
        XCTAssertTrue(searchBarSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(searchBarSource.contains("@State private var draftQuery"))
        XCTAssertTrue(searchBarSource.contains("Task.sleep(for: .milliseconds(80))"))
        XCTAssertTrue(searchSurfaceSource.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(searchSurfaceSource.contains(".glassEffect("))
        XCTAssertTrue(searchSurfaceSource.contains(".tint(appearance.isDark ? Color.black.opacity(0.50) : nil)"))
        XCTAssertTrue(searchSurfaceSource.contains(".interactive(true)"))
        XCTAssertTrue(searchSurfaceSource.contains(".background(.ultraThinMaterial, in: Capsule())"))
        XCTAssertFalse(searchSurfaceSource.contains(".shadow("))
        XCTAssertTrue(filterChipSource.contains(".wanderGlassCapsule("))
    }

    func testFeaturedIsTheOnlyDefaultSourceAndMoreDefaultsToAll() {
        let state = MapFilterState()

        XCTAssertEqual(state.source, .featured)
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertTrue(state.more.people.isEmpty)
        XCTAssertEqual(state.more.status, .all)
        XCTAssertEqual(state.more.activeSectionCount, 0)
    }

    func testResetUsesTheConfiguredDefaultAndClearsMoreFilters() {
        var state = MapFilterState(
            source: .featured,
            more: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_ben"],
                status: .checkIns
            )
        )

        state.reset(to: .friends)

        XCTAssertEqual(state, MapFilterState(source: .friends))
    }

    func testAllInEveryMoreSectionAddsNoRefinement() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let stranger = profile(id: "user_stranger")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let followedWanna = visiblePlace(owner: ben, name: "Ben Wanna", longitude: -118.24, status: .wannaGo)
        let strangerCheckIn = visiblePlace(owner: stranger, name: "Stranger Been", longitude: -118.23, status: .been)

        let visible = MapFilterSelection.friendsPlaces(
            from: [strangerCheckIn, followedWanna, ownCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([followedWanna.id]))
    }

    func testFriendsSourceAndMoreSelectionsCombineAsIntersections() {
        let state = MapFilterState(
            source: .friends,
            more: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_ben", "user_juana"],
                status: .checkIns
            )
        )
        let ben = profile(id: "user_ben")
        let juana = profile(id: "user_juana")
        let benCoffee = visiblePlace(owner: ben, name: "Ben Coffee", status: .been)
        let juanaCoffee = visiblePlace(owner: juana, name: "Juana Coffee", longitude: -118.24, status: .been)
        let juanaWanna = visiblePlace(owner: juana, name: "Juana Wanna", longitude: -118.23, status: .wannaGo)

        let visible = MapFilterSelection.friendsPlaces(
            from: [juanaWanna, juanaCoffee, benCoffee],
            currentUserID: "user_joe",
            followedOwnerIDs: [ben.id, juana.id],
            refinements: state.more
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([benCoffee.id, juanaCoffee.id]))
    }

    func testSpecificMoreOptionsAreOrWithinASectionAndAndAcrossSections() {
        let selection = MapMoreFilterSelection(
            categories: [WanderPlaceCategory.coffeeTeaSweets, WanderPlaceCategory.barsNightlife],
            people: ["user_ben", "user_juana"],
            status: .wanna
        )

        XCTAssertTrue(
            MapFilterSelection.matches(
                status: .wannaGo,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_juana",
                selection: selection
            )
        )
        XCTAssertFalse(
            MapFilterSelection.matches(
                status: .been,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_juana",
                selection: selection
            )
        )
        XCTAssertFalse(
            MapFilterSelection.matches(
                status: .wannaGo,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_ryan",
                selection: selection
            )
        )
    }

    func testAllClearsOnlyItsOwnSectionAndSourceSwitchClearsMore() {
        var state = MapFilterState()
        state.more.toggleCategory(WanderPlaceCategory.coffeeTeaSweets)
        state.more.togglePerson("user_ben")
        state.more.status = .checkIns

        XCTAssertEqual(state.more.activeSectionCount, 3)

        state.more.selectAllCategories()
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertEqual(state.more.people, Set(["user_ben"]))
        XCTAssertEqual(state.more.status, .checkIns)
        XCTAssertEqual(state.more.activeSectionCount, 2)

        state.selectSource(.friends)
        XCTAssertEqual(state.source, .friends)
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertTrue(state.more.people.isEmpty)
        XCTAssertEqual(state.more.status, .all)
        XCTAssertEqual(state.more.activeSectionCount, 0)
    }

    func testYouSourceIncludesOnlyOwnCheckInsAndWannaPlaces() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let ownWanna = visiblePlace(owner: joe, name: "Joe Wanna", longitude: -118.24, status: .wannaGo)
        let friendCheckIn = visiblePlace(owner: ben, name: "Ben Been", longitude: -118.23, status: .been)

        let visible = MapFilterSelection.ownPlaces(
            from: [friendCheckIn, ownWanna, ownCheckIn],
            currentUserID: joe.id,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([ownCheckIn.id, ownWanna.id]))
    }

    func testYouSourceCombinesCategoriesAndStatus() {
        let joe = profile(id: "user_joe")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let ownWanna = visiblePlace(owner: joe, name: "Joe Wanna", longitude: -118.24, status: .wannaGo)

        let visible = MapFilterSelection.ownPlaces(
            from: [ownWanna, ownCheckIn],
            currentUserID: joe.id,
            refinements: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                status: .wanna
            )
        )

        XCTAssertEqual(visible.map(\.id), [ownWanna.id])
    }

    private func profile(id: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: id,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        longitude: Double = -118.25,
        status: PlaceStatus
    ) -> VisiblePlace {
        let providerID = name.lowercased().replacingOccurrences(of: " ", with: "_")
        let place = LocalPlace(
            localID: "local_place_\(owner.id)_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: WanderPlaceCategory.coffeeTeaSweets,
            latitude: 34.05,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)",
            serverID: "up_\(owner.id)_\(providerID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }
}

final class MapFeaturedSelectionTests: XCTestCase {
    private let losAngelesRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )

    func testFeaturedIncludesCommunityCheckInsButNeverWannaOrOutsideViewport() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let stranger = profile(id: "user_stranger")
        let benCheckIn = visiblePlace(owner: ben, name: "Ben Been", status: .been)
        let benWanna = visiblePlace(owner: ben, name: "Ben Wanna", longitude: -118.24, status: .wannaGo)
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", longitude: -118.23, status: .been)
        let strangerCheckIn = visiblePlace(owner: stranger, name: "Stranger Been", longitude: -118.22, status: .been)
        let outsideCheckIn = visiblePlace(
            owner: ben,
            name: "Outside Been",
            latitude: 35,
            longitude: -118.21,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [benWanna, ownCheckIn, strangerCheckIn, outsideCheckIn, benCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(
            Set(featured.map(\.id)),
            Set([ownCheckIn.id, benCheckIn.id, strangerCheckIn.id])
        )
        XCTAssertTrue(
            MapFeaturedSelection.places(
                from: [benCheckIn, benWanna],
                currentUserID: joe.id,
                followedOwnerIDs: [ben.id],
                in: losAngelesRegion,
                refinements: MapMoreFilterSelection(status: .wanna)
            ).isEmpty
        )
    }

    func testFeaturedStillWorksWhenViewerFollowsNobody() {
        let joe = profile(id: "user_joe")
        let community = profile(id: "user_community")
        let ownCheckIn = visiblePlace(owner: joe, name: "Own", status: .been)
        let communityCheckIn = visiblePlace(
            owner: community,
            name: "Community",
            longitude: -118.24,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [communityCheckIn, ownCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(featured.map(\.id)), Set([ownCheckIn.id, communityCheckIn.id]))
    }

    func testFeaturedPrioritizesFollowedContributorWhenEvidenceIsEqual() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let timestamp = Date(timeIntervalSince1970: 1_720_000_000)
        let followed = visiblePlace(
            owner: ben,
            name: "Followed Pick",
            providerID: "followed_pick",
            status: .been,
            ratingScore: 4,
            visitedAt: timestamp
        )
        let broaderCommunity = visiblePlace(
            owner: community,
            name: "Community Pick",
            longitude: -118.24,
            providerID: "community_pick_equal",
            status: .been,
            ratingScore: 4,
            visitedAt: timestamp
        )

        let featured = MapFeaturedSelection.places(
            from: [broaderCommunity, followed],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(),
            limit: 1
        )

        XCTAssertEqual(featured.map(\.place.canonicalName), ["Followed Pick"])
    }

    func testFeaturedCanRankHighFitCommunityPlaceAboveWeakFollowedPlace() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let tasteSave = visiblePlace(
            owner: joe,
            name: "Favorite Coffee",
            providerID: "favorite_coffee",
            category: WanderPlaceCategory.coffeeTeaSweets,
            status: .wannaGo
        )
        let weakFollowed = visiblePlace(
            owner: ben,
            name: "Weak Followed",
            longitude: -118.24,
            providerID: "weak_followed",
            category: WanderPlaceCategory.shopping,
            status: .been,
            ratingScore: 2
        )
        let highFitCommunity = visiblePlace(
            owner: community,
            name: "High Fit Community",
            longitude: -118.23,
            providerID: "high_fit_community",
            category: WanderPlaceCategory.coffeeTeaSweets,
            status: .been,
            ratingScore: 5,
            communitySaveCount: 5
        )

        let featured = MapFeaturedSelection.places(
            from: [weakFollowed, highFitCommunity],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(),
            tasteSaves: [PlaceSaveSummary(visiblePlace: tasteSave, attributes: [])],
            limit: 1
        )

        XCTAssertEqual(featured.map(\.place.canonicalName), ["High Fit Community"])
    }

    func testFeaturedPeopleRefinementNarrowsWithoutChangingSource() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let followed = visiblePlace(owner: ben, name: "Ben Pick", status: .been)
        let broaderCommunity = visiblePlace(
            owner: community,
            name: "Community Pick",
            longitude: -118.24,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [broaderCommunity, followed],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(people: [ben.id])
        )

        XCTAssertEqual(featured.map(\.id), [followed.id])
    }

    func testFeaturedRanksCommunitySupportBeforeRatingAndRecency() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let juana = profile(id: "user_juana")
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_710_000_000)
        let communityOne = visiblePlace(
            owner: ben,
            name: "Community Pick",
            providerID: "community_pick",
            status: .been,
            ratingScore: 3,
            visitedAt: olderDate
        )
        let communityTwo = visiblePlace(
            owner: juana,
            name: "Community Pick",
            providerID: "community_pick",
            status: .been,
            ratingScore: 3,
            visitedAt: olderDate
        )
        let soloFavorite = visiblePlace(
            owner: ben,
            name: "Solo Favorite",
            longitude: -118.23,
            providerID: "solo_favorite",
            status: .been,
            ratingScore: 5,
            visitedAt: newerDate
        )

        let featured = MapFeaturedSelection.places(
            from: [soloFavorite, communityOne, communityTwo],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id, juana.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )
        let groups = VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id)

        XCTAssertEqual(groups.map { $0.primary.place.canonicalName }, ["Community Pick", "Solo Favorite"])
        XCTAssertEqual(groups.first?.saveCount, 2)
    }

    func testFeaturedCapsDensityByPlaceGroup() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let candidates = (0..<30).map { index in
            visiblePlace(
                owner: ben,
                name: "Place \(index)",
                latitude: 34.0 + Double(index) * 0.001,
                longitude: -118.25,
                providerID: "place_\(index)",
                status: .been
            )
        }

        let featured = MapFeaturedSelection.places(
            from: candidates,
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(
            VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id).count,
            MapFeaturedSelection.maximumPlaceGroupCount
        )
    }

    func testFeaturedLargeCandidateRankingStaysLightweight() {
        let joe = profile(id: "user_joe")
        let community = profile(id: "user_community")
        let candidates = (0..<8_000).map { index in
            visiblePlace(
                owner: community,
                name: "Candidate \(index)",
                latitude: 34.0 + Double(index % 100) * 0.001,
                longitude: -118.25,
                providerID: "candidate_\(index)",
                category: index.isMultiple(of: 2)
                    ? WanderPlaceCategory.coffeeTeaSweets
                    : WanderPlaceCategory.restaurantsFood,
                status: .been,
                ratingScore: Double(index % 6),
                communitySaveCount: (index % 8) + 1
            )
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let featured = MapFeaturedSelection.places(
            from: candidates,
            currentUserID: joe.id,
            followedOwnerIDs: [],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertEqual(
            VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id).count,
            MapFeaturedSelection.maximumPlaceGroupCount
        )
        XCTAssertLessThan(elapsed, 2, "Featured ranking should remain a local, sub-two-second pass for 8,000 candidates")
    }

    func testViewportRefreshWaitsUntilCameraLeavesPrefetchBuffer() {
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let loadedViewport = MapViewportRefreshPolicy.prefetchedViewport(for: initialRegion)
        let insideRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.04, longitude: -117.95),
            span: initialRegion.span
        )
        let outsideRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.08, longitude: -117.95),
            span: initialRegion.span
        )

        XCTAssertEqual(loadedViewport.minLatitude, 33.9, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.maxLatitude, 34.1, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.minLongitude, -118.2, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.maxLongitude, -117.8, accuracy: 0.000_001)
        XCTAssertFalse(
            MapViewportRefreshPolicy.shouldRefresh(
                visibleRegion: insideRegion,
                loadedViewport: loadedViewport
            )
        )
        XCTAssertTrue(
            MapViewportRefreshPolicy.shouldRefresh(
                visibleRegion: outsideRegion,
                loadedViewport: loadedViewport
            )
        )
    }

    private func profile(id: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: id,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        latitude: Double = 34.05,
        longitude: Double = -118.25,
        providerID: String? = nil,
        category: String = WanderPlaceCategory.restaurantsFood,
        status: PlaceStatus,
        ratingScore: Double? = nil,
        visitedAt: Date? = nil,
        communitySaveCount: Int = 0
    ) -> VisiblePlace {
        let providerID = providerID ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
        let place = LocalPlace(
            localID: "local_place_\(owner.id)_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: category,
            primaryCategory: category,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)_\(status.rawValue)",
            serverID: "up_\(owner.id)_\(providerID)_\(status.rawValue)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            ratingScore: ratingScore,
            recommendedScore: ratingScore,
            recommendedCount: ratingScore == nil ? 0 : 1,
            visitedAt: visitedAt,
            savedAt: visitedAt ?? .now,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner,
            communitySaveCount: communitySaveCount
        )
    }
}

final class MapSocialOwnerSelectionTests: XCTestCase {
    func testPeopleOptionsExcludeYouAndSortEveryFollowedProfileAlphabetically() {
        let joe = profile(id: "user_joe", displayName: "Joe")
        let juana = profile(id: "user_juana", displayName: "Juana")
        let ben = profile(id: "user_ben", displayName: "Ben")

        let options = MapSocialOwnerSelection.options(
            currentUser: joe,
            following: [juana, joe, ben, ben]
        )

        XCTAssertEqual(options.map(\.id), [ben.id, juana.id])
        XCTAssertEqual(options.map(\.displayName), ["Ben", "Juana"])
    }

    private func profile(id: String, displayName: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: displayName,
            syncState: .synced
        )
    }
}

final class MapPinOutlineBuilderTests: XCTestCase {
    func testPersonalBeenSaveProducesOneSolidPersonalOutline() {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser])
        XCTAssertEqual(outlines.map(\.status), [.been])
        XCTAssertNil(outlines.first?.secondaryStatus)
        XCTAssertEqual(outlines.first?.dashPattern ?? [], [CGFloat]())
        XCTAssertEqual(outlines.first?.arcs.count, 1)
    }

    func testPersonalAndSocialSavesProduceTwoStatusAwareOutlines() {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .wannaGo),
                MapPinSaveState(ownership: .social, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.wannaGo, .been])
        XCTAssertEqual(outlines.compactMap(\.secondaryStatus), [])
        XCTAssertEqual(outlines.first?.dashPattern ?? [], MapPinVisualMetrics.wannaDashPattern)
        XCTAssertEqual(outlines.last?.dashPattern ?? [], [CGFloat]())
    }

    func testMixedSocialSavesKeepWannaVisibleAlongsideAnyNumberOfBeenSaves() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .social, status: .wannaGo),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.social])
        XCTAssertEqual(outlines.map(\.status), [.been])
        XCTAssertEqual(outlines.map(\.secondaryStatus), [.wannaGo])

        let socialOutline = try XCTUnwrap(outlines.first)
        XCTAssertEqual(socialOutline.arcs.map(\.status), [.been, .wannaGo])
        XCTAssertEqual(socialOutline.arcs.map(\.trimFrom), [0.028, 0.528])
        XCTAssertEqual(socialOutline.arcs.map(\.trimTo), [0.472, 0.972])
        XCTAssertEqual(socialOutline.arcs.map(\.rotationDegrees), [-90, -90])
        XCTAssertEqual(socialOutline.arcs[0].dashPattern, [])
        XCTAssertEqual(socialOutline.arcs[1].dashPattern, [1.5, 3.5])
    }

    func testRyanBeenJoeBeenAndMayaWannaProducePersonalRingAndSplitSocialHalo() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .been),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .wannaGo)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.been, .been])
        XCTAssertNil(outlines[0].secondaryStatus)
        XCTAssertEqual(outlines[1].secondaryStatus, .wannaGo)
        XCTAssertEqual(outlines[0].arcs.count, 1)
        XCTAssertEqual(outlines[1].arcs.count, 2)
    }

    func testSingleSocialWannaRemainsOneFullDashedHalo() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .social, status: .wannaGo)
            ]
        )

        let socialOutline = try XCTUnwrap(outlines.first)
        XCTAssertNil(socialOutline.secondaryStatus)
        XCTAssertEqual(socialOutline.arcs.count, 1)
        XCTAssertEqual(socialOutline.arcs[0].status, .wannaGo)
        XCTAssertEqual(socialOutline.arcs[0].trimFrom, 0)
        XCTAssertEqual(socialOutline.arcs[0].trimTo, 1)
        XCTAssertEqual(socialOutline.arcs[0].dashPattern, MapPinVisualMetrics.wannaDashPattern)
    }

    func testMixedCurrentUserHistoryKeepsExistingBeenPrecedence() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .wannaGo),
                MapPinSaveState(ownership: .currentUser, status: .been)
            ]
        )

        let personalOutline = try XCTUnwrap(outlines.first)
        XCTAssertEqual(personalOutline.ownership, .currentUser)
        XCTAssertEqual(personalOutline.status, .been)
        XCTAssertNil(personalOutline.secondaryStatus)
        XCTAssertEqual(personalOutline.dashPattern, [])
    }

    @MainActor
    func testPinVisualMetricsTightenEmojiSpacingWithoutASelectionHalo() throws {
        XCTAssertEqual(MapPinVisualMetrics.discDiameter, 38)
        XCTAssertEqual(MapPinVisualMetrics.emojiDiameter, 24)
        XCTAssertEqual(MapPinVisualMetrics.outlineWidth, 3)
        XCTAssertEqual(MapPinVisualMetrics.secondaryOutlinePadding, -6)
        XCTAssertEqual(MapPinVisualMetrics.wannaDashPattern, [1.5, 3.5])
        XCTAssertEqual(MapPinVisualMetrics.activeTitleClearance, 2)
        XCTAssertGreaterThanOrEqual(
            MapPinVisualMetrics.activeTitleVerticalOffset(
                selectedScale: MapPinSelectionMotionStyle.selectedScale
            ),
            (MapPinVisualMetrics.discDiameter * MapPinSelectionMotionStyle.selectedScale / 2)
                + MapPinVisualMetrics.activeTitleClearance
        )

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertFalse(map.contains("selectionHalo"))
        XCTAssertTrue(map.contains("MapPinVisualMetrics.activeTitleVerticalOffset("))
    }

    func testAccessibilityLabelDescribesOwnershipAndEveryVisibleStatusWithoutSaveCopy() {
        let label = MapPinAccessibility.label(
            outlines: [
                MapPinOutline(ownership: .currentUser, status: .been),
                MapPinOutline(ownership: .social, status: .been, secondaryStatus: .wannaGo)
            ],
            category: "Restaurant",
            placeName: "Bar Nido"
        )

        XCTAssertEqual(
            label,
            "Bar Nido, Restaurant, you checked in, social checked in and wanna"
        )
        XCTAssertFalse(label.localizedCaseInsensitiveContains("save"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("been"))
    }
}

final class VisiblePlaceGroupingTests: XCTestCase {
    @MainActor
    func testDroppedPinPresentationDoesNotReuseSameNamedPinAtAnotherCoordinate() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let northernPin = visiblePlace(
            owner: currentUser,
            name: "Dropped pin",
            category: "other",
            address: "40.71280, -124.21400",
            latitude: 40.7128,
            longitude: -124.2140,
            sourceProvider: "coordinate",
            providerID: "coordinate_4071280_-12421400",
            status: .been
        )
        let southernCandidate = MapScreen.coordinateCandidate(
            at: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611)
        )

        XCTAssertNil(
            MapScreen.matchingVisiblePlace(
                for: southernCandidate,
                in: [northernPin]
            )
        )
        XCTAssertEqual(
            MapScreen.matchingVisiblePlace(
                for: MapScreen.coordinateCandidate(
                    at: CLLocationCoordinate2D(latitude: 40.7128, longitude: -124.2140)
                ),
                in: [northernPin]
            )?.id,
            northernPin.id
        )
    }

    func testOutlineCatalogCarriesRyanJoeMayaTopologyToEveryGroupedSaveID() throws {
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let joe = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let maya = profile(id: "user_maya", handle: "maya", displayName: "Maya")
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05004,
            longitude: -118.25003,
            providerID: "mapkit_mutsu_ryan",
            status: .been,
            ratingScore: 5
        )
        let joeBeen = visiblePlace(
            owner: joe,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05022,
            longitude: -118.25018,
            providerID: "mapkit_mutsu_joe",
            status: .been,
            ratingScore: 4
        )
        let mayaWanna = visiblePlace(
            owner: maya,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05037,
            longitude: -118.25031,
            providerID: "mapkit_mutsu_maya",
            status: .wannaGo
        )

        let catalog = MapPinOutlineBuilder.outlineCatalog(
            for: [joeBeen, mayaWanna, ryanBeen],
            currentUserID: ryan.id
        )
        let outlines = try XCTUnwrap(catalog[joeBeen.id])

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.been, .been])
        XCTAssertNil(outlines[0].secondaryStatus)
        XCTAssertEqual(outlines[1].secondaryStatus, .wannaGo)
        XCTAssertEqual(catalog[ryanBeen.id], outlines)
        XCTAssertEqual(catalog[mayaWanna.id], outlines)
    }

    func testGroupsSameNamedNearbyPlaceAcrossDifferentProviderIDsAndStatuses() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let myWant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05004,
            longitude: -118.25003,
            providerID: "mapkit_mutsu_joe_version",
            status: .wannaGo,
            ratingScore: nil,
            note: "want to try this"
        )
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "MUTSU",
            category: "place",
            latitude: 34.05039,
            longitude: -118.25041,
            providerID: "mapkit_mutsu_ryan_version",
            status: .been,
            ratingScore: 5,
            note: "sit at the bar"
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [ryanBeen, myWant],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].primary.owner.id, currentUser.id)
        XCTAssertEqual(groups[0].primary.userPlace.status, .wannaGo)
        XCTAssertEqual(groups[0].places.map(\.owner.id), [currentUser.id, ryan.id])

        let outlines = MapPinOutlineBuilder.outlines(
            for: groups[0].places.map { visiblePlace in
                MapPinSaveState(
                    ownership: visiblePlace.owner.id == currentUser.id ? .currentUser : .social,
                    status: visiblePlace.userPlace.status
                )
            }
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.wannaGo, .been])
    }

    func testDoesNotGroupSameNamedPlacesWhenCoordinatesAreFarApart() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let firstPlace = visiblePlace(
            owner: currentUser,
            name: "Blue Bottle Coffee",
            category: "coffee",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_blue_bottle_first",
            status: .wannaGo
        )
        let secondPlace = visiblePlace(
            owner: ryan,
            name: "Blue Bottle Coffee",
            category: "coffee",
            latitude: 34.080,
            longitude: -118.290,
            providerID: "mapkit_blue_bottle_second",
            status: .been,
            ratingScore: 4
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [firstPlace, secondPlace],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.saveCount), [1, 1])
    }

    func testDoesNotGroupDifferentPlacesAtSameCoordinate() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let restaurant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_mutsu",
            status: .wannaGo
        )
        let coffee = visiblePlace(
            owner: ryan,
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_maru",
            status: .been,
            ratingScore: 5
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [restaurant, coffee],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertFalse(VisiblePlaceGrouping.matches(restaurant, coffee))
        XCTAssertEqual(groups.map(\.primary.place.canonicalName), ["Mutsu", "Maru Coffee"])
    }

    @MainActor
    func testSelectedMapAnnotationGroupMovesToTheEndWithoutRegroupingPlaces() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let places = [
            visiblePlace(
                owner: currentUser,
                name: "First Place",
                category: "coffee",
                latitude: 34.050,
                longitude: -118.250,
                providerID: "mapkit_first",
                status: .been
            ),
            visiblePlace(
                owner: currentUser,
                name: "Selected Place",
                category: "restaurant",
                latitude: 34.060,
                longitude: -118.260,
                providerID: "mapkit_selected",
                status: .been
            ),
            visiblePlace(
                owner: currentUser,
                name: "Last Place",
                category: "park",
                latitude: 34.070,
                longitude: -118.270,
                providerID: "mapkit_last",
                status: .wannaGo
            )
        ]
        let groups = VisiblePlaceGrouping.groups(from: places, currentUserID: currentUser.id)
        let selectedKey = groups[1].key

        let ordered = MapScreen.orderedAnnotationGroups(
            groups,
            selectedGroupKey: selectedKey
        )

        XCTAssertEqual(ordered.map(\.key), [groups[0].key, groups[2].key, selectedKey])
        XCTAssertEqual(Set(ordered.map(\.key)), Set(groups.map(\.key)))
    }

    func testGroupsSameNamedAddressAcrossDifferentCoordinates() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let myWant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            address: "412 Sunset Blvd",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_mutsu_address_joe",
            status: .wannaGo
        )
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "Mutsu",
            category: "restaurant",
            address: "412 Sunset Blvd",
            latitude: 34.056,
            longitude: -118.257,
            providerID: "mapkit_mutsu_address_ryan",
            status: .been,
            ratingScore: 5
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [ryanBeen, myWant],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(VisiblePlaceGrouping.matches(myWant, ryanBeen))
        XCTAssertEqual(groups[0].primary.owner.id, currentUser.id)
    }

    func testGroupsLegacyAndCanonicalHotchkissAddressesIntoOnePin() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let legacySave = visiblePlace(
            owner: currentUser,
            name: "Hotchkiss Park",
            category: "park",
            address: "2302 4th Street",
            latitude: 34.0046,
            longitude: -118.4845,
            providerID: "hotchkiss-park-ocean-park",
            status: .been
        )
        let canonicalSave = visiblePlace(
            owner: ryan,
            name: "Hotchkiss Park",
            category: "park",
            address: "2302 4th St",
            latitude: 34.00585,
            longitude: -118.4842,
            sourceProvider: "walkthrough",
            providerID: "hotchkiss-park-santa-monica",
            status: .wannaGo
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [legacySave, canonicalSave],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(VisiblePlaceGrouping.matches(legacySave, canonicalSave))
        XCTAssertEqual(groups[0].saveCount, 2)
    }

    func testDoesNotGroupSameNamedPlacesAtDifferentStreetNumbers() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let firstPlace = visiblePlace(
            owner: currentUser,
            name: "Corner Market",
            category: "shop",
            address: "2302 4th St",
            latitude: 34.0046,
            longitude: -118.4845,
            providerID: "corner-market-first",
            status: .been
        )
        let secondPlace = visiblePlace(
            owner: ryan,
            name: "Corner Market",
            category: "shop",
            address: "2303 4th Street",
            latitude: 34.0146,
            longitude: -118.4945,
            providerID: "corner-market-second",
            status: .wannaGo
        )

        XCTAssertFalse(VisiblePlaceGrouping.matches(firstPlace, secondPlace))
        XCTAssertEqual(
            VisiblePlaceGrouping.groups(
                from: [firstPlace, secondPlace],
                currentUserID: currentUser.id
            ).count,
            2
        )
    }

    private func profile(id: String, handle: String, displayName: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: handle,
            displayName: displayName,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        category: String,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        sourceProvider: String = "mapkit",
        providerID: String,
        status: PlaceStatus,
        ratingScore: Double? = nil,
        note: String? = nil
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "local_place_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: category,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)",
            serverID: "up_\(owner.id)_\(providerID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            note: note,
            ratingScore: ratingScore,
            recommendedScore: ratingScore,
            recommendedCount: ratingScore == nil ? 0 : 1,
            sourceType: "test",
            syncState: .synced
        )

        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }
}
