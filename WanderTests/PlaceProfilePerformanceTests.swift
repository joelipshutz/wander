import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class PlaceProfilePerformanceTests: XCTestCase {
    /// Measures the real Live-to-profile entry point, including its taste/history
    /// preparation. No coordinates or configured backend means no live lookups.
    func testPerformanceMountPlaceProfileWith1500Saves() async throws {
        let rowCount = 1_500
        let store = WanderStore(fixtures: fixture(rowCount: rowCount))
        let selected = try XCTUnwrap(store.currentUserVisiblePlaces.last)
        let candidate = PlaceCandidate(id: selected.place.id, name: selected.place.canonicalName,
            category: "park", latitude: nil, longitude: nil, sourceProvider: "fixture",
            sourceProviderPlaceID: selected.place.sourceProviderPlaceID, confidence: 1)
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider())
        let backend = WanderBackend()
        let drafts = PlaceSaveDraftStore(persistence: .ephemeral)
        let walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
        let upsells = ProductUpsellCoordinator()
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        defer { previousWindow?.makeKey() }
        var samples: [Double] = []

        for _ in 0..<3 {
            let mount = PlaceProfilePerformanceMount()
            let root = LivePlaceFullProfileScreen(candidate: candidate, onBack: {})
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
                .environmentObject(drafts)
                .environmentObject(walkthroughs)
                .environmentObject(upsells)
                .environment(\.scenePhase, .inactive)
                .onAppear { mount.didAppear = true }
                .background(PlaceProfilePerformanceLayoutProbe(mount: mount))
            let window = UIWindow(windowScene: scene)
            window.frame = bounds
            let startedAt = ProcessInfo.processInfo.systemUptime
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = bounds
            let fittingSize = host.sizeThatFits(in: bounds.size)
            host.view.layoutIfNeeded()
            // Appearance is delivered by SwiftUI's mounted graph, unlike a
            // hosting view's bounds which can be set before body evaluation.
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while (!mount.didAppear || !mount.didLayoutInWindow),
                  ProcessInfo.processInfo.systemUptime < deadline {
                await Task.yield()
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                if !mount.didAppear || !mount.didLayoutInWindow {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            samples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            XCTAssertTrue(mount.didAppear, "The actual profile must appear before timing ends")
            XCTAssertTrue(mount.didLayoutInWindow, "The mounted SwiftUI content must complete layout")
            XCTAssertGreaterThan(fittingSize.width, 0)
            XCTAssertGreaterThan(fittingSize.height, 0)
            window.isHidden = true
            window.rootViewController = nil
            await Task.yield()
        }
        XCTAssertEqual(store.currentUserVisiblePlaces.count, rowCount)
        let attachment = XCTAttachment(string:
            "REC675 place_profile_mount saves=\(rowCount) samples_ms=\(samples) median_ms=\(samples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fixture(rowCount: Int) -> WanderFixtures {
        let empty = WanderFixtures.empty()
        let owner = empty.currentUser
        let places = (0..<rowCount).map { index in
            LocalPlace(localID: "profile-place-\(index)", canonicalName: "Fixture \(index)",
                category: "park", latitude: 34 + Double(index) * 0.001, longitude: -118,
                sourceProvider: "fixture", sourceProviderPlaceID: "fixture-\(index)")
        }
        let saves = places.enumerated().map { index, place in
            LocalUserPlace(localID: "profile-save-\(index)", userID: owner.id, placeID: place.id,
                status: .been, visibility: .selfOnly, ratingScore: 4, sourceType: "manual")
        }
        let attributes = saves.enumerated().map { index, save in
            LocalPlaceAttribute(localID: "profile-attribute-\(index)", userPlaceID: save.id,
                questionKey: "park_tags", valueType: "multi_tag", valueJSON: "[\"views\",\"quiet\"]")
        }
        return WanderFixtures(currentUser: owner, profiles: [owner], places: places,
            userPlaces: saves, placeAttributes: attributes, follows: [], blocks: [],
            placeLists: [], placeListMembers: [], placeListItems: [], contactProvider: empty.contactProvider)
    }
}

@MainActor
private final class PlaceProfilePerformanceMount {
    var didAppear = false
    var didLayoutInWindow = false
}

private struct PlaceProfilePerformanceLayoutProbe: UIViewRepresentable {
    let mount: PlaceProfilePerformanceMount

    func makeUIView(context: Context) -> PlaceProfilePerformanceProbeView {
        PlaceProfilePerformanceProbeView(mount: mount)
    }

    func updateUIView(_ uiView: PlaceProfilePerformanceProbeView, context: Context) {}
}

private final class PlaceProfilePerformanceProbeView: UIView {
    private let mount: PlaceProfilePerformanceMount

    init(mount: PlaceProfilePerformanceMount) {
        self.mount = mount
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, bounds.width > 0, bounds.height > 0 {
            mount.didLayoutInWindow = true
        }
    }
}
