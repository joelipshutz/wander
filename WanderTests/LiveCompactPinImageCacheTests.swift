import MapKit
import QuartzCore
import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class LiveCompactPinImageCacheTests: XCTestCase {
    func testCacheUsesExactExistingArtworkAtEveryScaleAndAppearance() throws {
        let cache = LiveCompactPinImageCache()
        let states = [makeState([]), makeState([.currentUser]), makeState([.social]), makeState([.featured]),
                      makeState([.currentUser, .social]), makeState([.social, .currentUser])]
        for brand in AstirBrandMode.allCases {
            for scale in [CGFloat(1), 2, 3] {
                for state in states {
                    let root = makeRoot(state, brand: brand)
                    let actual = try XCTUnwrap(cache.image(for: root, scale: scale, traits: UITraitCollection()))
                    let renderer = ImageRenderer(content: LiveTotemPinView(state: state, categoryEmoji: "☕",
                        selected: false, viewed: false, compact: true)
                        .environment(\.colorScheme, brand.prefersDarkInterface ? .dark : .light)
                        .environment(\.displayScale, scale))
                    renderer.scale = scale
                    let expected = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(actual.size, CGSize(width: 44, height: 44))
                    XCTAssertEqual(actual.scale, scale)
                    XCTAssertEqual(try pixels(actual), try pixels(expected), "\(brand), scale \(scale), \(state)")
                }
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 32)
        XCTAssertLessThanOrEqual(cache.retainedCost, 4 * 1_024 * 1_024)
    }

    func testCacheReusesOnlyPixelEquivalentCompactStatesAndBoundsRetention() throws {
        let cache = LiveCompactPinImageCache(maximumCount: 2, maximumCost: 32_000)
        let original = makeRoot(makeState([.currentUser, .social]))
        let first = try XCTUnwrap(cache.image(for: original, scale: 1, traits: UITraitCollection()))
        let changedState = LiveTotemState(rails: [
            .init(ownership: .currentUser, status: .wannaGo, secondaryStatus: .been),
            .init(ownership: .social, status: .wannaGo)
        ], hasListMembership: true, hasSavedStatus: false, isFeatured: true)
        let equivalent = LiveNativeHostedPin(state: changedState, categoryEmoji: "🌳", selected: false,
                                            viewed: true, compact: true, brand: original.brand)
        XCTAssertTrue(cache.image(for: equivalent, scale: 1, traits: UITraitCollection()) === first)
        let reversed = try XCTUnwrap(cache.image(for: makeRoot(makeState([.social, .currentUser])),
                                                 scale: 1, traits: UITraitCollection()))
        XCTAssertNotEqual(try pixels(first), try pixels(reversed))
        _ = cache.image(for: makeRoot(makeState([]), brand: .editorial), scale: 1, traits: UITraitCollection())
        XCTAssertEqual(cache.count, 2)
        XCTAssertLessThanOrEqual(cache.retainedCost, 32_000)
        XCTAssertFalse(cache.image(for: original, scale: 1, traits: UITraitCollection()) === first,
                       "The oldest cached image is evicted at the count limit")
        let tiny = LiveCompactPinImageCache(maximumCount: 32, maximumCost: 1)
        XCTAssertNotNil(tiny.image(for: original, scale: 1, traits: UITraitCollection()))
        XCTAssertEqual(tiny.count, 0)
        XCTAssertEqual(tiny.retainedCost, 0)
    }

    func testInvalidScaleAndRenderFailureFallBackToHosting() throws {
        var renders = 0
        let cache = LiveCompactPinImageCache { _, _, _ in renders += 1; return nil }
        let root = makeRoot(makeState([.social]))
        for scale in [CGFloat(0), -1, .infinity, .nan, 100] {
            XCTAssertNil(cache.image(for: root, scale: scale, traits: UITraitCollection()))
        }
        XCTAssertEqual(renders, 0)
        let pin = makePin(root.state)
        let view = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        view.compactImageCache = cache
        view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: root.brand)
        XCTAssertEqual(hosts(view).count, 1)
        XCTAssertEqual(view.accessibilityValue, "Map dot")
        XCTAssertTrue(view.subviews.compactMap { $0 as? UIImageView }.isEmpty)
        XCTAssertEqual(cache.count, 0)
        XCTAssertGreaterThan(renders, 0)
    }

    func testScaleBrandAnimationLatchAndReuseRefreshWithoutChangingHitTargets() throws {
        let pin = makePin(makeState([.currentUser, .social]))
        let view = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        view.traitOverrides.displayScale = 2
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.displayScale, 2)
        view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: .editorialLight)
        XCTAssertTrue(hosts(view).isEmpty)
        let firstImage = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertEqual(firstImage.scale, 2)
        view.traitOverrides.displayScale = 3
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.displayScale, 3)
        view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: .editorialLight)
        let scaledImage = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertEqual(scaledImage.scale, 3)
        XCTAssertFalse(scaledImage === firstImage)
        view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: .editorial)
        let darkImage = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertNotEqual(try pixels(darkImage), try pixels(scaledImage))

        view.configure(pin: pin, selected: true, viewed: false, compact: true, brand: .editorial)
        let host = try XCTUnwrap(hosts(view).first)
        XCTAssertTrue(host.rootView.selected)
        view.configure(pin: pin, selected: false, viewed: true, compact: true, brand: .editorial)
        XCTAssertTrue(hosts(view).first === host, "Interacted pins keep their animation history")
        XCTAssertTrue(host.rootView.viewed)
        view.configure(pin: pin, selected: false, viewed: true, compact: false, brand: .editorial)
        XCTAssertTrue(hosts(view).first === host)
        view.prepareForReuse()
        view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: .editorialLight)
        XCTAssertTrue(hosts(view).isEmpty, "Reuse resets the interacted-host policy")
        XCTAssertEqual(view.subviews.compactMap { $0 as? UIImageView }.count, 1)
        XCTAssertEqual(view.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(view.centerOffset, .zero)
        XCTAssertEqual(view.accessibilityIdentifier, "live.pin.\(pin.id)")
        XCTAssertEqual(view.accessibilityLabel, pin.accessibilityLabel)
        XCTAssertEqual(view.accessibilityValue, "Map dot")
        XCTAssertTrue(view.point(inside: CGPoint(x: 1, y: 1), with: nil))
        XCTAssertTrue(view.point(inside: CGPoint(x: 43, y: 43), with: nil))
    }

    func testMountedCompactPixelsAndSelectionViewedTransitionsMatchHostedReference() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; priorWindow?.makeKey() }
        let actual = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        let reference = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        let control = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        reference.compactImageCache = LiveCompactPinImageCache { _, _, _ in nil }
        control.compactImageCache = LiveCompactPinImageCache { _, _, _ in nil }
        actual.frame.origin = CGPoint(x: 60, y: 160)
        reference.frame.origin = CGPoint(x: 200, y: 160)
        control.frame.origin = CGPoint(x: 60, y: 260)
        controller.view.addSubview(actual)
        controller.view.addSubview(reference)
        controller.view.addSubview(control)
        let views = [actual, reference, control]
        for brand in AstirBrandMode.allCases {
            for state in [makeState([]), makeState([.currentUser, .social]), makeState([.social, .currentUser])] {
                let pin = makePin(state)
                for view in views {
                    view.prepareForReuse()
                    view.configure(pin: pin, selected: false, viewed: false, compact: true, brand: brand)
                }
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(400))
                try assertMountedParity(actual, reference, in: window, name: "compact-\(brand)-\(state)",
                                        tolerance: 0.025, control: control)
                XCTAssertTrue(hosts(actual).isEmpty)
                XCTAssertEqual(hosts(reference).count, 1)
                XCTAssertEqual(hosts(control).count, 1)

                // Commit every hosting graph's pending layout in one public
                // transaction before timing animation samples. Otherwise two
                // identical hosts can start on different display passes.
                // The third always-hosted view is an independent control in
                // the same screenshot, held to the same pixel thresholds.
                for (name, selected, viewed, compact) in [
                    ("selected", true, false, true), ("viewed", false, true, false),
                    ("unviewed", false, false, false), ("density", false, false, true)
                ] {
                    CATransaction.begin()
                    for view in views {
                        view.configure(pin: pin, selected: selected, viewed: viewed, compact: compact, brand: brand)
                    }
                    for view in views { view.mountedHostingController?.view.setNeedsLayout() }
                    window.layoutIfNeeded()
                    for view in views { view.mountedHostingController?.view.layoutIfNeeded() }
                    CATransaction.commit()
                    for delay in [30, 60, 90, 240] {
                        try await Task.sleep(for: .milliseconds(delay))
                        try assertMountedParity(actual, reference, in: window, name: "\(name)-\(brand)-\(delay)",
                                                tolerance: 0.05, control: control)
                    }
                    XCTAssertEqual(hosts(actual).count, 1, "Animated hosts remain mounted until reuse")
                    XCTAssertEqual(hosts(control).count, 1)
                    XCTAssertEqual(actual.accessibilityValue, compact && !selected ? "Map dot" : "Category pin")
                }
            }
        }
    }

    func testMountedReuseFromSelectedPinToDifferentCompactThenFullPinIsAtomic() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; priorWindow?.makeKey() }
        let actual = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        let reference = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        reference.compactImageCache = LiveCompactPinImageCache { _, _, _ in nil }
        actual.frame.origin = CGPoint(x: 60, y: 160)
        reference.frame.origin = CGPoint(x: 200, y: 160)
        controller.view.addSubview(actual); controller.view.addSubview(reference)
        let old = makePin(makeState([.currentUser, .social]))
        actual.configure(pin: old, selected: true, viewed: false, compact: false, brand: .editorialLight)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        actual.prepareForReuse()
        let replacement = makePin(makeState([.featured]), id: "replacement-pin", category: "park")
        for view in [actual, reference] {
            view.configure(pin: replacement, selected: false, viewed: false, compact: true, brand: .editorialLight)
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        try assertMountedParity(actual, reference, in: window, name: "reused-compact", tolerance: 0.025)
        XCTAssertTrue(hosts(actual).isEmpty)
        for view in [actual, reference] {
            view.configure(pin: replacement, selected: false, viewed: false, compact: false, brand: .editorialLight)
        }
        for delay in [30, 60, 90, 240] {
            try await Task.sleep(for: .milliseconds(delay))
            try assertMountedParity(actual, reference, in: window, name: "reused-full", tolerance: 0.025)
        }
        XCTAssertFalse(try XCTUnwrap(hosts(actual).first).rootView.selected)
        XCTAssertEqual(actual.accessibilityIdentifier, "live.pin.replacement-pin")
        XCTAssertEqual(actual.accessibilityLabel, replacement.accessibilityLabel)
    }

    private func assertMountedParity(_ actual: UIView, _ reference: UIView, in window: UIWindow,
                                     name: String, tolerance: Double,
                                     control: UIView? = nil,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.preferredRange = .standard
        var drew = false
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drew = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drew, name, file: file, line: line)
        func crop(_ view: UIView) throws -> UIImage {
            let rect = view.convert(view.bounds.insetBy(dx: -8, dy: -8), to: window)
            let scaled = CGRect(x: rect.minX * format.scale, y: rect.minY * format.scale,
                                width: rect.width * format.scale, height: rect.height * format.scale)
            return UIImage(cgImage: try XCTUnwrap(screenshot.cgImage?.cropping(to: scaled)), scale: format.scale,
                           orientation: .up)
        }
        let rhs = try pixels(crop(reference))
        func compare(_ view: UIView, name: String) throws {
            let lhs = try pixels(crop(view))
            XCTAssertEqual(lhs.count, rhs.count, name, file: file, line: line)
            var foregroundPixels = 0
            var difference = 0
            for offset in stride(from: 0, to: min(lhs.count, rhs.count), by: 4) {
                guard (0..<3).contains(where: { lhs[offset + $0] < 240 || rhs[offset + $0] < 240 }) else { continue }
                foregroundPixels += 1
                for channel in 0..<3 { difference += abs(Int(lhs[offset + channel]) - Int(rhs[offset + channel])) }
            }
            XCTAssertGreaterThan(foregroundPixels, 40, "Both paths must draw actual artwork: \(name)", file: file, line: line)
            let normalizedDifference = Double(difference) / Double(max(1, foregroundPixels * 3 * 255))
            XCTAssertLessThanOrEqual(normalizedDifference, tolerance, name, file: file, line: line)
            if normalizedDifference > tolerance {
                let attachment = XCTAttachment(image: screenshot)
                attachment.name = "compact-pin-parity-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        try compare(actual, name: name)
        if let control { try compare(control, name: "hosted-control-\(name)") }
    }

    private func makeRoot(_ state: LiveTotemState, brand: AstirBrandMode = .editorialLight) -> LiveNativeHostedPin {
        LiveNativeHostedPin(state: state, categoryEmoji: "☕", selected: false, viewed: false, compact: true, brand: brand)
    }
    private func makeState(_ ownership: [MapPinSaveOwnership]) -> LiveTotemState {
        LiveTotemState(rails: ownership.map { .init(ownership: $0, status: .been) }, hasListMembership: false,
                       hasSavedStatus: !ownership.isEmpty, isFeatured: false)
    }
    private func makePin(_ state: LiveTotemState, id: String = "compact-place", category: String = "coffee") -> LivePlacePin {
        let owner = LocalProfile(localID: "compact-owner", handle: "fixture", displayName: "Fixture")
        let place = LocalPlace(localID: id, canonicalName: "Fixture venue", category: category,
                               latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "compact-save", userID: owner.id, placeID: place.id,
                                  status: .been, visibility: .selfOnly, sourceType: "manual")
        return LivePlacePin(id: place.id, place: VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner),
                            activities: [], totemState: state)
    }
    private func hosts(_ view: LiveNativePinView) -> [UIHostingController<LiveNativeHostedPin>] {
        // A mounted hosting view's next responder is not a stable controller
        // lookup. Check the retained controller and its actual mounted view.
        guard let host = view.mountedHostingController else { return [] }
        XCTAssertTrue(host.view.superview === view)
        return [host]
    }
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                                          bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        XCTAssertTrue(success)
        return bytes
    }
}
