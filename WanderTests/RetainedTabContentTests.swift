import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class RetainedTabContentTests: XCTestCase {
    func testLiveMountKeepsAllNativeItemsWithoutConstructingUnvisitedTabs() async throws {
        let mount = try await makeMount()
        defer { mount.close() }

        XCTAssertEqual(mount.recorder.constructions["lists", default: 0], 0)
        XCTAssertEqual(mount.recorder.constructions["profile", default: 0], 0)
        XCTAssertEqual(mount.recorder.bodyCounts["lists", default: 0], 0)
        XCTAssertEqual(mount.recorder.bodyCounts["profile", default: 0], 0)
        let bar = try XCTUnwrap(findTabBar(in: mount.host.view))
        XCTAssertEqual(bar.items?.map(\.title), ["Live", "Lists", "Profile"])

        mount.update(selection: "live", request: UUID())
        XCTAssertEqual(mount.recorder.constructions["lists", default: 0], 0)
        XCTAssertEqual(mount.recorder.constructions["profile", default: 0], 0)
    }

    func testSelectionRendersImmediatelyAndRetainsOwnedStateAfterLeaving() async throws {
        let mount = try await makeMount()
        defer { mount.close() }

        // The synchronous layout that applies selection must build the content;
        // there is no appear callback, task, sleep or second selection to admit it.
        mount.update(selection: "lists")
        XCTAssertGreaterThan(mount.recorder.bodyCounts["lists", default: 0], 0)
        let first = try XCTUnwrap(mount.recorder.states["lists"])
        XCTAssertEqual(first.value, 0)
        XCTAssertEqual(mount.recorder.colorSchemes["lists"], .dark)
        let increment = try XCTUnwrap(mount.recorder.increments["lists"])
        increment()
        mount.render()
        XCTAssertEqual(mount.recorder.states["lists"]?.value, 1)

        mount.update(selection: "profile")
        XCTAssertGreaterThan(mount.recorder.bodyCounts["profile", default: 0], 0)
        let profile = try XCTUnwrap(mount.recorder.states["profile"])
        mount.update(selection: "live")
        mount.update(selection: "lists")
        XCTAssertEqual(mount.recorder.states["lists"]?.identity, first.identity)
        XCTAssertEqual(mount.recorder.states["lists"]?.value, 1)
        mount.update(selection: "profile")
        XCTAssertEqual(mount.recorder.states["profile"]?.identity, profile.identity)
    }

    func testInitiallySelectedProfileHasContentOnItsFirstRender() async throws {
        let mount = try await makeMount(selection: "profile")
        defer { mount.close() }

        XCTAssertGreaterThan(mount.recorder.bodyCounts["profile", default: 0], 0)
        XCTAssertNotNil(mount.recorder.states["profile"])
        XCTAssertEqual(mount.recorder.constructions["lists", default: 0], 0)
        XCTAssertEqual(mount.recorder.colorSchemes["profile"], .dark)
    }

    func testFirstMountReadsLatestPendingRequestsAndRetainedConsumersKeepUpdating() async throws {
        let mount = try await makeMount()
        defer { mount.close() }
        let replaced = UUID()
        let pending = UUID()
        mount.update(selection: "live", request: replaced)
        mount.update(selection: "live", request: pending)
        XCTAssertTrue(mount.recorder.appearedRequests.isEmpty)
        XCTAssertTrue(mount.recorder.changedRequests.isEmpty)
        XCTAssertTrue(mount.recorder.taskRequests.isEmpty)

        mount.update(selection: "profile", request: pending)
        await waitForRequest(pending, in: "profile", recorder: mount.recorder)
        let identity = try XCTUnwrap(mount.recorder.states["profile"]?.identity)
        XCTAssertFalse(mount.recorder.allRequests.contains(replaced))

        // These are the initial/onAppear/keyed-task consumer patterns used by
        // Profile calendar/invitations and Lists pending-notification routing.
        mount.update(selection: "lists", request: pending)
        await waitForRequest(pending, in: "lists", recorder: mount.recorder)
        await waitForDisappearance(of: "profile", recorder: mount.recorder)
        let next = UUID()
        mount.update(selection: "live", request: next)
        // Native tab transitions finish asynchronously. Returning in the same
        // turn can cancel a departure, which must not imply a new onAppear.
        await waitForDisappearance(of: "lists", recorder: mount.recorder)
        mount.update(selection: "profile", request: next)
        await waitForRequest(next, in: "profile", recorder: mount.recorder)
        XCTAssertEqual(mount.recorder.states["profile"]?.identity, identity)
    }

    private func waitForRequest(_ request: UUID, in name: String, recorder: RetainedTabRecorder) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if recorder.appearedRequests[name, default: []].contains(request),
               recorder.changedRequests[name, default: []].contains(request),
               recorder.taskRequests[name, default: []].contains(request) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(recorder.appearedRequests[name, default: []].contains(request), "\(name) onAppear reads the pending request")
        XCTAssertTrue(recorder.changedRequests[name, default: []].contains(request), "\(name) onChange reads the pending request")
        XCTAssertTrue(recorder.taskRequests[name, default: []].contains(request), "\(name) keyed task reads the pending request")
    }

    private func waitForDisappearance(of name: String, recorder: RetainedTabRecorder) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while recorder.visibleTabs.contains(name), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(recorder.visibleTabs.contains(name), "\(name) must finish departing before returning")
    }

    private func makeMount(selection: String = "live") async throws -> RetainedTabMount {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var scene: UIWindowScene?
        while ContinuousClock.now < deadline {
            scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if scene != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        return RetainedTabMount(scene: try XCTUnwrap(scene), selection: selection)
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        return view.subviews.lazy.compactMap { self.findTabBar(in: $0) }.first
    }
}

@MainActor
private final class RetainedTabRecorder {
    struct State {
        let identity: UUID
        let value: Int
    }
    var constructions: [String: Int] = [:]
    var bodyCounts: [String: Int] = [:]
    var states: [String: State] = [:]
    var colorSchemes: [String: ColorScheme] = [:]
    var increments: [String: @MainActor () -> Void] = [:]
    var appearedRequests: [String: [UUID]] = [:]
    var changedRequests: [String: [UUID]] = [:]
    var taskRequests: [String: [UUID]] = [:]
    var visibleTabs: Set<String> = []
    var allRequests: [UUID] {
        appearedRequests.values.flatMap { $0 } + changedRequests.values.flatMap { $0 }
            + taskRequests.values.flatMap { $0 }
    }
}

private struct RetainedTabProbe: View {
    let name: String
    let request: UUID?
    let recorder: RetainedTabRecorder
    @Environment(\.colorScheme) private var colorScheme
    @State private var identity = UUID()
    @State private var value = 0

    var body: some View {
        let _ = recordBody()
        Text("\(name): \(value)")
            .onAppear {
                recorder.visibleTabs.insert(name)
                if let request { recorder.appearedRequests[name, default: []].append(request) }
            }
            .onDisappear { recorder.visibleTabs.remove(name) }
            .onChange(of: request, initial: true) { _, request in
                if let request { recorder.changedRequests[name, default: []].append(request) }
            }
            .task(id: request) {
                if let request { recorder.taskRequests[name, default: []].append(request) }
            }
    }

    private func recordBody() {
        recorder.bodyCounts[name, default: 0] += 1
        recorder.states[name] = .init(identity: identity, value: value)
        recorder.colorSchemes[name] = colorScheme
        recorder.increments[name] = { value += 1 }
    }
}

private struct RetainedTabHarness: View {
    let selection: String
    let request: UUID?
    let recorder: RetainedTabRecorder

    var body: some View {
        TabView(selection: .constant(selection)) {
            Text("Live").tabItem { Text("Live") }.tag("live")
            WanderRetainedTabContent(isSelected: selection == "lists") {
                let _ = recorder.constructions["lists", default: 0] += 1
                RetainedTabProbe(name: "lists", request: request, recorder: recorder)
            }
            .tabItem { Text("Lists") }.tag("lists")
            WanderRetainedTabContent(isSelected: selection == "profile") {
                let _ = recorder.constructions["profile", default: 0] += 1
                RetainedTabProbe(name: "profile", request: request, recorder: recorder)
            }
            .tabItem { Text("Profile") }.tag("profile")
        }
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private final class RetainedTabMount {
    let recorder: RetainedTabRecorder
    let host: UIHostingController<RetainedTabHarness>
    let window: UIWindow
    private weak var previousKeyWindow: UIWindow?

    init(scene: UIWindowScene, selection: String) {
        let recorder = RetainedTabRecorder()
        self.recorder = recorder
        previousKeyWindow = scene.keyWindow
        host = UIHostingController(rootView: RetainedTabHarness(selection: selection, request: nil, recorder: recorder))
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        render()
    }

    func update(selection: String, request: UUID? = nil) {
        host.rootView = RetainedTabHarness(selection: selection, request: request, recorder: recorder)
        render()
    }

    func render() {
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        window.setNeedsLayout()
        _ = host.sizeThatFits(in: window.bounds.size)
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        recorder.increments.removeAll()
    }
}
