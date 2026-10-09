import Foundation
import SwiftUI
import MapKit

@main
enum ModelChecks {
    @MainActor
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
        }
        let store = ReviewStore(arguments: ["--ui-testing"])
        store.scenario = .dense
        check(store.scope == .following && store.time == .week, "Default exploration is Following / past 7 days")
        check(store.filtered.contains { $0.isOwn }, "Following includes the viewer")
        check(store.filtered.contains { !$0.isOwn && $0.isFollowing }, "Following includes followed people")
        check(!store.filtered.contains { !$0.isOwn && !$0.isFollowing }, "Following excludes strangers")
        check(store.filtered.allSatisfy { $0.hoursAgo < 168 }, "Following default is rolling seven days")

        store.scope = .nearby
        check(!store.filtered.contains { !$0.isOwn && !$0.isFollowing }, "Nearby does not widen social visibility")
        check(store.filtered.allSatisfy { GeographicArea(center: ReviewStore.center, radius: 5000).contains($0.coordinate) }, "Nearby uses the chosen center and default 5 km radius")
        store.kinds = [.wanna]
        check(store.filtered.allSatisfy { $0.kind == .wanna }, "Kind filtering applies to the shared projection")
        store.query = "little tide"
        check(store.filtered.count == 1 && store.filtered.first?.place == "Little Tide", "Text search intersects scope/kind/time")
        let stagedResult = store.projection(kinds: [.checkin], time: .all, area: nil, nearbyRadius: 5000, query: "")
        check(!stagedResult.isEmpty && store.kinds == [.wanna] && store.query == "little tide", "Draft filter preview does not mutate live filters")

        let beforeCenter = CLLocationCoordinate2D(latitude: 34.015, longitude: -118.48)
        store.camera = .region(.init(center: beforeCenter, span: .init(latitudeDelta: 0.05, longitudeDelta: 0.03)))
        store.viewportCenter = beforeCenter
        store.nearbyRadius = 15000
        store.drawer = .full
        store.area = GeographicArea(center: beforeCenter, radius: 2000)
        store.openYourMap()
        check(store.tab == .profile && store.showYourMap && store.scope == .nearby && store.query == "little tide", "Your Map stays in Profile and does not mutate Live exploration")
        store.showPatterns = true
        check(store.tab == .profile && store.showYourMap, "Patterns remains inside the Profile Your Map destination")
        let selectedOwnPlace = Fixtures.activities[6]
        store.exploreOwnPlace(selectedOwnPlace)
        check(store.tab == .live && store.scope == .yours && store.time == .all && store.fromProfile, "Selective place exploration enters Live with a return path")
        check(store.query == selectedOwnPlace.place && store.kinds.isEmpty && store.area == nil, "Selective handoff explores one place instead of relocating the whole map")
        store.kinds = [.wanna]; store.time = .week; store.query = "test"; store.nearbyRadius = 25000
        store.resetFilters()
        check(store.time == .all && store.kinds.isEmpty && store.query.isEmpty && store.nearbyRadius == 5000, "Reset honors owner all-time default")
        store.backToProfile()
        check(store.tab == .profile && !store.fromProfile && store.scope == .nearby, "Return restores prior scope and leaves Live")
        check(store.kinds == [.wanna] && store.query == "little tide" && store.drawer == .full && store.nearbyRadius == 15000, "Return restores the previous exploration controls")
        check(store.viewportCenter.latitude == beforeCenter.latitude && store.camera.region?.center.longitude == beforeCenter.longitude && store.area?.radius == 2000, "Return restores camera, viewport, and applied geography")

        let circle = GeographicArea(center: Fixtures.activities[0].coordinate, radius: 100)
        check(circle.contains(Fixtures.activities[0].coordinate), "Geographic circle contains its center")
        check(!circle.contains(Fixtures.activities[2].coordinate), "Geographic circle excludes a distant coordinate")
        store.scope = .following; store.resetFilters(); store.area = circle
        check(store.filtered.count == 1 && store.filtered.first?.place == "Juniper Coffee", "Applied geographic membership filters the single shared dataset")
        store.scope = .yours; store.resetFilters()
        let originalCount = store.filtered.count
        store.savePlace(Fixtures.activities[0], kind: .checkin, note: "A second local memory")
        check(store.filtered.count == originalCount, "Owner projection deduplicates repeated place memories")
        check(store.activities.filter { $0.isOwn && $0.placeKey == Fixtures.activities[0].placeKey }.count == 2, "Full local history remains available behind owner place detail")
        store.savePlan(for: Fixtures.activities[1], title: "A local plan", when: "Next week")
        check(store.activities.first?.kind == .plan && store.activities.first?.timeLabel == "Next week", "A created plan displays its future schedule rather than its creation age")

        store.scenario = .sparse
        check(Set(store.filtered.map(\.id)).count == store.filtered.count, "Sparse scenario does not duplicate newly created owner activities")
        store.scenario = .empty
        check(store.filtered.allSatisfy { $0.hoursAgo < 1 }, "Empty scenario retains only newly created local activity")
        store.scenario = .offline
        check(!store.filtered.isEmpty, "Offline scenario retains local sample activity")
        let capture = ReviewStore(arguments: ["--ui-testing", "--your-map", "--scenario-sparse"])
        check(capture.tab == .profile && capture.showYourMap && !capture.showTransition && capture.scenario == .sparse, "Deterministic launch arguments select a capture fixture without changing persisted preferences")

        let statusStore = ReviewStore(arguments: ["--ui-testing"])
        let olderWanna = Fixtures.activities[7]
        statusStore.savePlan(for: olderWanna, title: "Newer plan at the same place", when: "Next week")
        check(statusStore.ownPlaces(matching: .wanna).contains { $0.placeKey == olderWanna.placeKey && $0.kind == .wanna }, "Your Map filters owner history before grouping, retaining a Wanna behind a newer plan")
        statusStore.savePlace(olderWanna, kind: .checkin, note: "A later check-in")
        check(statusStore.ownPlaces(matching: .wanna).contains { $0.placeKey == olderWanna.placeKey && $0.kind == .wanna }, "A newer check-in also preserves the matching Wanna projection")
        check(statusStore.ownPlaces.filter { $0.placeKey == olderWanna.placeKey }.count == 1, "Unfiltered Your Map still has one canonical row per place")

        let exitStore = ReviewStore(arguments: ["--ui-testing"])
        exitStore.scope = .nearby; exitStore.query = "Juniper"; exitStore.time = .all
        exitStore.nearbyRadius = 15000; exitStore.drawer = .full
        exitStore.openYourMap(); exitStore.exploreOwnPlace(olderWanna)
        exitStore.selectTab(.profile)
        check(exitStore.tab == .profile && !exitStore.fromProfile && exitStore.showYourMap && exitStore.query == "Juniper" && exitStore.scope == .nearby, "Explicit Profile tab restores exploration and returns to Your Map")
        exitStore.exploreOwnPlace(olderWanna); exitStore.selectTab(.lists)
        check(exitStore.tab == .lists && !exitStore.fromProfile && exitStore.query == "Juniper" && exitStore.drawer == .full && exitStore.nearbyRadius == 15000, "Leaving through Lists restores exploration instead of leaking the temporary place filter")
        exitStore.selectTab(.live)
        check(exitStore.scope == .nearby && exitStore.query == "Juniper" && !exitStore.fromProfile, "Returning to Live after another tab shows the prior exploration")

        let drawStore = ReviewStore(arguments: ["--ui-testing", "--fixture-draw"])
        drawStore.changeDrawer(to: .full)
        check(drawStore.drawer == .peek && drawStore.drawing && drawStore.draftArea != nil, "Draw mode blocks full feed expansion without losing its geographic draft")
        drawStore.changeDrawer(to: .half)
        check(drawStore.drawer == .peek, "Draw mode also blocks half-height expansion")
        drawStore.cancelAreaDraft(); drawStore.changeDrawer(to: .full)
        check(drawStore.drawer == .full && !drawStore.drawing && drawStore.draftArea == nil, "Explicit draft cancellation restores normal drawer interaction")

        let badgeStore = ReviewStore(arguments: ["--ui-testing"])
        badgeStore.scope = .yours; badgeStore.resetFilters()
        check(badgeStore.activeFilterCount == 0 && badgeStore.time == .all, "Owner reset returns all-time with zero active-filter badge")
        badgeStore.scope = .following; badgeStore.resetFilters()
        check(badgeStore.activeFilterCount == 0 && badgeStore.time == .week, "Following reset returns past seven days with zero active-filter badge")
        badgeStore.time = .all
        check(badgeStore.activeFilterCount == 1, "A nondefault Following time window is counted")
        print("PASS: \(count) deterministic model checks. No app, simulator, network, or delivery operation was performed.")
    }
}
