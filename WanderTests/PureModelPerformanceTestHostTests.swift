import UIKit
import XCTest

@MainActor
final class PureModelPerformanceTestHostTests: XCTestCase {
    func testRestoresExactWindowRootsHiddenStatesAndKeyWindow() throws {
        let scene = try foregroundScene()
        let visible = UIWindow(windowScene: scene)
        let visibleRoot = UIViewController()
        let hidden = UIWindow(windowScene: scene)
        let hiddenRoot = UIViewController()
        visible.rootViewController = visibleRoot
        hidden.rootViewController = hiddenRoot
        let originalKey = scene.windows.first { $0.isKeyWindow }
        defer {
            visible.isHidden = true; visible.rootViewController = nil
            hidden.isHidden = true; hidden.rootViewController = nil
            originalKey?.makeKey()
        }
        visible.makeKeyAndVisible()
        hidden.isHidden = true
        let host = PureModelPerformanceTestHost(scene: scene)
        defer { host.restore() }
        XCTAssertNil(visible.rootViewController)
        XCTAssertNil(hidden.rootViewController)
        XCTAssertTrue(visible.isHidden)
        XCTAssertTrue(hidden.isHidden)
        host.restore()
        XCTAssertTrue(visible.rootViewController === visibleRoot)
        XCTAssertTrue(hidden.rootViewController === hiddenRoot)
        XCTAssertFalse(visible.isHidden)
        XCTAssertTrue(hidden.isHidden)
        XCTAssertTrue(visible.isKeyWindow)
        // Repeated restoration cannot overwrite later legitimate window changes.
        let replacement = UIViewController()
        visible.rootViewController = replacement
        host.restore()
        XCTAssertTrue(visible.rootViewController === replacement)
    }

    func testNestedScopesRestoreTheOuterHostBeforeTheApplication() throws {
        let scene = try foregroundScene()
        let original = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let root = try XCTUnwrap(original.rootViewController)
        let outer = PureModelPerformanceTestHost(scene: scene)
        defer { outer.restore() }
        let outerWindow = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let outerRoot = try XCTUnwrap(outerWindow.rootViewController)
        let inner = PureModelPerformanceTestHost(scene: scene)
        defer { inner.restore() }
        XCTAssertNil(original.rootViewController)
        XCTAssertNil(outerWindow.rootViewController)
        inner.restore()
        XCTAssertNil(original.rootViewController)
        XCTAssertTrue(outerWindow.rootViewController === outerRoot)
        XCTAssertTrue(outerWindow.isKeyWindow)
        outer.restore()
        XCTAssertTrue(original.rootViewController === root)
        XCTAssertTrue(original.isKeyWindow)
    }

    func testThrowingScopeRestoresItsRetainedRoot() throws {
        let scene = try foregroundScene()
        let original = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let root = try XCTUnwrap(original.rootViewController)
        enum Expected: Error { case failure }
        @MainActor func operation() throws {
            let host = PureModelPerformanceTestHost(scene: scene)
            defer { host.restore() }
            XCTAssertNil(original.rootViewController)
            throw Expected.failure
        }
        XCTAssertThrowsError(try operation())
        XCTAssertTrue(original.rootViewController === root)
        XCTAssertTrue(original.isKeyWindow)
    }

    func testCancellationUnwindsTheScopeAndRestoresItsRoot() async throws {
        let scene = try foregroundScene()
        let original = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let root = try XCTUnwrap(original.rootViewController)
        let started = expectation(description: "test host detached")
        let operation = Task { @MainActor in
            let host = PureModelPerformanceTestHost(scene: scene)
            defer { host.restore() }
            started.fulfill()
            try await Task.sleep(for: .seconds(10))
        }
        defer { operation.cancel() }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertNil(original.rootViewController)
        operation.cancel()
        do { try await operation.value; XCTFail("Cancelled sleep must throw") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(original.rootViewController === root)
        XCTAssertTrue(original.isKeyWindow)
    }

    private func foregroundScene() throws -> UIWindowScene {
        try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
    }
}
