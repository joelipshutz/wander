import Darwin
import MapKit
import SwiftUI
import XCTest
@testable import Wander

/// This file is identical on baseline and candidate. It mounts the real native
/// pin views in a window and draws each density state; no camera/AX polling is
/// included in the measured render work.
@MainActor
final class LiveMountedPinPerformanceTests: XCTestCase {
    func testMountedThreeHundredPinsAndDensityUpdatesBenchmark() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let pins = makePins()
        var mountSamples: [Double] = []
        var densitySamples: [Double] = []
        var cpuSamples: [Double] = []
        var finalImage: UIImage?
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let priorWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            controller.view.backgroundColor = .white
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; priorWindow?.makeKey() }
            let cpuStart = self.processCPUTime()
            let mountStart = ProcessInfo.processInfo.systemUptime
            let views = pins.enumerated().map { index, pin in
                let view = LiveNativePinView(annotation: nil, reuseIdentifier: LiveNativePinView.reuseIdentifier)
                view.frame.origin = CGPoint(x: CGFloat(12 + (index % 15) * 24), y: CGFloat(20 + (index / 15) * 31))
                view.configure(pin: pin, selected: false, viewed: false, compact: index % 11 != 0, brand: .editorialLight)
                controller.view.addSubview(view)
                return view
            }
            _ = self.drawMountedWindow(window)
            mountSamples.append((ProcessInfo.processInfo.systemUptime - mountStart) * 1_000)
            let densityStart = ProcessInfo.processInfo.systemUptime
            for phase in 1...6 {
                for (index, view) in views.enumerated() {
                    view.configure(pin: pins[index], selected: false, viewed: false,
                                   compact: index % 11 != phase, brand: .editorialLight)
                }
                finalImage = self.drawMountedWindow(window)
            }
            densitySamples.append((ProcessInfo.processInfo.systemUptime - densityStart) * 1_000)
            cpuSamples.append((self.processCPUTime() - cpuStart) * 1_000)
            XCTAssertEqual(views.count, 300)
            XCTAssertEqual(Set(views.compactMap(\.accessibilityIdentifier)).count, 300)
            XCTAssertTrue(views.allSatisfy { $0.superview === controller.view && $0.bounds.size == CGSize(width: 44, height: 44) })
            XCTAssertEqual(views.filter { $0.accessibilityValue == "Map dot" }.count,
                           (0..<300).filter { $0 % 11 != 6 }.count)
            XCTAssertEqual(views.filter { $0.accessibilityValue == "Category pin" }.count,
                           (0..<300).filter { $0 % 11 == 6 }.count)
        }
        let mount = Array(mountSamples.suffix(3)), density = Array(densitySamples.suffix(3)), cpu = Array(cpuSamples.suffix(3))
        XCTAssertEqual(mount.count, 3)
        let rendered = try XCTUnwrap(finalImage?.cgImage)
        var bytes = [UInt8](repeating: 0, count: rendered.width * rendered.height * 4)
        let decoded = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: rendered.width, height: rendered.height,
                bitsPerComponent: 8, bytesPerRow: rendered.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
            return true
        }
        XCTAssertTrue(decoded)
        for color in [[UInt8(240), 90, 60], [UInt8(105), 184, 215]] {
            let count = stride(from: 0, to: bytes.count, by: 4).filter { offset in
                (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - Int(color[$0])) <= 3 }
            }.count
            XCTAssertGreaterThan(count, 100, "Mounted pins must actually render both ownership colors")
        }
        let report = "REC675 mounted_pins count=300 initial_compact=272 density_updates=6 mount_ms=\(mount) density_ms=\(density) cpu_ms=\(cpu) mount_median_ms=\(mount.sorted()[1]) density_median_ms=\(density.sorted()[1]) cpu_median_ms=\(cpu.sorted()[1])"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "REC675-mounted-pin-render-benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func drawMountedWindow(_ window: UIWindow) -> UIImage {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.preferredRange = .standard
        var drew = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drew = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drew)
        XCTAssertNotNil(image.cgImage)
        return image
    }

    private func processCPUTime() -> Double {
        var usage = rusage()
        let status = getrusage(RUSAGE_SELF, &usage)
        XCTAssertEqual(status, 0)
        guard status == 0 else { return .nan }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func makePins() -> [LivePlacePin] {
        let owner = LocalProfile(localID: "mounted-owner", handle: "fixture", displayName: "Fixture")
        return (0..<300).map { index in
            let place = LocalPlace(localID: "mounted-place-\(index)", canonicalName: "Fixture \(index)",
                                   category: index.isMultiple(of: 2) ? "coffee" : "park", latitude: 34, longitude: -118)
            let save = LocalUserPlace(localID: "mounted-save-\(index)", userID: owner.id, placeID: place.id,
                                      status: .been, visibility: .selfOnly, sourceType: "manual")
            let rails: [MapPinOutline]
            switch index % 4 {
            case 0: rails = []
            case 1: rails = [.init(ownership: .currentUser, status: .been)]
            case 2: rails = [.init(ownership: .social, status: .wannaGo)]
            default: rails = [.init(ownership: .currentUser, status: .been), .init(ownership: .social, status: .wannaGo)]
            }
            return LivePlacePin(id: place.id,
                place: VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner), activities: [],
                totemState: LiveTotemState(rails: rails, hasListMembership: false, hasSavedStatus: !rails.isEmpty, isFeatured: false))
        }
    }
}
