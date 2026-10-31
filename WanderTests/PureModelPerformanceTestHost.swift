import UIKit
import XCTest

/// Test-target-only isolation for coordinator/model benchmarks that do not mount
/// their own UI. Retain the app's existing controllers and restore them explicitly;
/// do not change application arguments, defaults, animation settings, or scenes.
@MainActor
final class PureModelPerformanceTestHost {
    private struct WindowState {
        let window: UIWindow
        let root: UIViewController?
        let hidden: Bool
        let key: Bool
    }

    private var previous: [WindowState]
    private let window: UIWindow
    private var restored = false

    convenience init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        self.init(scene: scene)
    }

    init(scene: UIWindowScene) {
        previous = scene.windows.map {
            WindowState(window: $0, root: $0.rootViewController,
                hidden: $0.isHidden, key: $0.isKeyWindow)
        }
        for state in previous {
            state.window.isHidden = true
            state.window.rootViewController = nil
        }
        // Keep a normal foreground window without mounting a rendering workload.
        window = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    /// Must be called by the benchmark's defer, including thrown/cancelled exits.
    /// Repeated calls intentionally do nothing; nested scopes restore their own
    /// immediately previous host and are closed in stack order.
    func restore() {
        guard !restored else { return }
        restored = true
        window.isHidden = true
        window.rootViewController = nil
        for state in previous {
            state.window.rootViewController = state.root
            state.window.isHidden = state.hidden
        }
        previous.first { $0.key }?.window.makeKey()
        previous.removeAll()
    }
}
