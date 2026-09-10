import SwiftUI
import UIKit

enum FullPageBackSwipePolicy {
    static func canBegin(velocity: CGPoint) -> Bool {
        velocity.x > 0 && velocity.x > abs(velocity.y)
    }

    static func shouldComplete(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard width > 0, translation > 0 else { return false }
        return translation >= width * 0.3
            || (translation >= 24 && velocity > 600)
    }
}

extension View {
    /// Opt in only at a full-page boundary, never on a sheet or inline step.
    func fullPageBackSwipe(isEnabled: Bool = true, usesNativeNavigation: Bool = false, onBack: @escaping () -> Void) -> some View {
        modifier(FullPageBackSwipeModifier(isEnabled: isEnabled, usesNativeNavigation: usesNativeNavigation, onBack: onBack))
    }
}

private struct FullPageBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let usesNativeNavigation: Bool
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var offset: CGFloat = 0
    @State private var isVisible = false
    @State private var isCompleting = false
    @State private var completionID = UUID()

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background {
                FullPageEdgeGesture(
                    usesNativeNavigation: usesNativeNavigation,
                    isEnabled: isEnabled && isVisible && !isCompleting && scenePhase == .active,
                    onChanged: { translation in offset = max(0, translation) },
                    onEnded: { translation, velocity, width, cancelled in
                        guard !cancelled, isEnabled,
                              FullPageBackSwipePolicy.shouldComplete(
                                translation: translation, velocity: velocity, width: width
                              ) else {
                            restore()
                            return
                        }
                        isCompleting = true
                        let id = UUID()
                        completionID = id
                        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.16)) {
                            offset = width
                        } completion: {
                            guard completionID == id, isVisible, isEnabled else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { onBack() }
                        }
                    }
                )
            }
            .onAppear { isVisible = true; restore() }
            .onDisappear { isVisible = false; restore() }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { restore() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { restore() }
            }
    }

    private func restore() {
        completionID = UUID()
        isCompleting = false
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2)) { offset = 0 }
    }
}

/// A non-hit-testing marker installs an edge recognizer on this page's hosting
/// view. Ordinary scrolling/paging keeps all of its touch area, including the
/// edge when the user starts a vertical drag. No window/global recognizer.
private struct FullPageEdgeGesture: UIViewRepresentable {
    let usesNativeNavigation: Bool
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] view in
            coordinator?.attach(to: view)
        }
        return view
    }

    func updateUIView(_ view: MarkerView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.attach(to: view)
        context.coordinator.recognizer.isEnabled = isEnabled && !usesNativeNavigation
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    static func dismantleUIView(_ view: MarkerView, coordinator: Coordinator) {
        coordinator.restoreNativePop()
        coordinator.recognizer.view?.removeGestureRecognizer(coordinator.recognizer)
        view.attach = nil
    }

    final class MarkerView: UIView {
        var attach: ((MarkerView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach?(self)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attach?(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: FullPageEdgeGesture
        weak var marker: UIView?
        weak var pageController: UIViewController?
        let recognizer = UIScreenEdgePanGestureRecognizer()
        weak var nativePop: UIGestureRecognizer?
        weak var previousNativeDelegate: (any UIGestureRecognizerDelegate)?
        var previousNativeEnabled = false

        init(owner: FullPageEdgeGesture) {
            self.owner = owner
            super.init()
            recognizer.edges = .left
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handle))
        }

        func attach(to marker: UIView) {
            self.marker = marker
            guard marker.window != nil else { return }
            var responder: UIResponder? = marker
            while let current = responder {
                if let controller = current as? UIViewController {
                    pageController = controller
                    if owner.usesNativeNavigation {
                        configureNativePop(in: controller)
                        return
                    }
                    if recognizer.view !== controller.view {
                        recognizer.view?.removeGestureRecognizer(recognizer)
                        controller.view.addGestureRecognizer(recognizer)
                    }
                    return
                }
                responder = current.next
            }
        }

        private func configureNativePop(in controller: UIViewController) {
            guard owner.isEnabled,
                  let pop = controller.navigationController?.interactivePopGestureRecognizer else {
                restoreNativePop()
                return
            }
            if nativePop !== pop {
                restoreNativePop()
                nativePop = pop
                previousNativeDelegate = pop.delegate
                previousNativeEnabled = pop.isEnabled
            }
            // Restore only this page's native interactive pop, including its
            // real navigation transition and cancellation. Never replace targets.
            pop.delegate = self
            if !pop.isEnabled { pop.isEnabled = true }
        }

        func restoreNativePop() {
            if let pop = nativePop, pop.delegate === self {
                pop.delegate = previousNativeDelegate
                if pop.state != .began && pop.state != .changed {
                    pop.isEnabled = previousNativeEnabled
                }
            }
            nativePop = nil
            previousNativeDelegate = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard owner.isEnabled, let marker, marker.window != nil,
                  FullPageBackSwipePolicy.canBegin(velocity: (gestureRecognizer as? UIPanGestureRecognizer)?.velocity(in: gestureRecognizer.view) ?? .zero)
            else { return false }

            if owner.usesNativeNavigation {
                guard let navigation = pageController?.navigationController,
                      navigation.viewControllers.count > 1,
                      navigation.transitionCoordinator == nil else { return false }
            }

            // A nested destination or covering modal owns navigation until it
            // goes away. The per-screen enabled flag also guards inline editors.
            var controller = pageController
            while let current = controller {
                if current.presentedViewController != nil { return false }
                if let navigation = current as? UINavigationController,
                   let pageController,
                   let top = navigation.topViewController,
                   top !== pageController,
                   !isDescendant(pageController, of: top) { return false }
                controller = current.parent
            }
            return true
        }

        private func isDescendant(_ controller: UIViewController, of ancestor: UIViewController) -> Bool {
            var current: UIViewController? = controller
            while let candidate = current {
                if candidate === ancestor { return true }
                current = candidate.parent
            }
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Only an edge-back competes with photo paging/panning. Non-edge
            // gestures fail immediately and leave those recognizers untouched.
            otherGestureRecognizer is UIPanGestureRecognizer
                && !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer)
        }

        @objc private func handle() {
            let translation = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began, .changed:
                owner.onChanged(translation)
            case .ended, .cancelled, .failed:
                owner.onEnded(
                    translation, recognizer.velocity(in: recognizer.view).x,
                    recognizer.view?.bounds.width ?? 0,
                    recognizer.state != .ended
                )
            default: break
            }
        }
    }
}
