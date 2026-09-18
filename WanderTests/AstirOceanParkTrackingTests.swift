import XCTest
import SwiftUI
import UIKit
@testable import Wander

final class AstirOceanParkTrackingTests: XCTestCase {
    func testMotionRequiresVisibleActiveMapAndRespectsReduceMotion() {
        for enabled in [true, false] {
            for visible in [true, false] {
                for active in [true, false] {
                    for reduced in [true, false] {
                        XCTAssertEqual(AstirOceanParkTracking.shouldAnimate(
                            enabled: enabled, visible: visible, active: active, reduceMotion: reduced
                        ), enabled && visible && active && !reduced)
                    }
                }
            }
        }
    }

    func testEpisodeHasOneBriefTearAndReturnsToOriginalLetters() {
        XCTAssertNil(AstirOceanParkTracking.frame(elapsed: -1))
        XCTAssertNil(AstirOceanParkTracking.frame(elapsed: .nan))
        XCTAssertNil(AstirOceanParkTracking.frame(elapsed: .infinity))
        XCTAssertEqual(AstirOceanParkTracking.frame(elapsed: 0)?.isTearing, false)
        XCTAssertEqual(AstirOceanParkTracking.frame(elapsed: 0.4)?.isTearing, true)
        XCTAssertEqual(AstirOceanParkTracking.frame(elapsed: 0.7)?.isTearing, false)
        XCTAssertNil(AstirOceanParkTracking.frame(elapsed: 0.96))
        XCTAssertNil(AstirOceanParkTracking.frame(elapsed: 60))
    }

    @MainActor
    func testSchedulerStartsAfterThreeSecondsThenUsesRandomIntervalsWithoutIdleTicks() async {
        var time: TimeInterval = 0
        var intervals = [55.0, 65.0, 60.0]
        var sleeps: [TimeInterval] = []
        var onsets: [TimeInterval] = []
        var wasActive = false
        var finalFrame: AstirOceanParkTracking.Frame?
        await AstirOceanParkTracking.run(
            nextInterval: { intervals.removeFirst() },
            now: { time },
            sleep: { delay in
                sleeps.append(delay)
                if time > 123 { throw CancellationError() }
                time += delay
            },
            update: { frame in
                if frame != nil && !wasActive { onsets.append(time) }
                wasActive = frame != nil
                finalFrame = frame
            }
        )
        XCTAssertEqual(onsets, [3, 58, 123])
        XCTAssertEqual(sleeps.first, 3)
        let longSleeps = sleeps.filter { $0 > 1 }
        XCTAssertEqual(longSleeps.count, 3)
        XCTAssertEqual(longSleeps[1], 54.04, accuracy: 0.00001)
        XCTAssertEqual(longSleeps[2], 64.04, accuracy: 0.00001)
        XCTAssertNil(finalFrame, "Cancellation restores the original still label.")
    }

    @MainActor
    func testSignalRendersOnlyLetterInkInCompactAndRegularSizes() throws {
        for compact in [false, true] {
            for color in [Color.black, Color.white] {
                let background = color == .black ? Color.white : Color.black
                let label = Text("OCEAN PARK")
                    .font(AstirTheme.metadata(compact ? 6.5 : 7.5))
                    .tracking(compact ? 1.8 : 2.3)
                func raster<V: View>(_ view: V) throws -> [UInt8] {
                    let renderer = ImageRenderer(content: view.frame(width: 100, height: 20).background(background))
                    renderer.scale = 3
                    let image = try XCTUnwrap(renderer.cgImage)
                    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
                    try bytes.withUnsafeMutableBytes { buffer in
                        let context = try XCTUnwrap(CGContext(
                            data: buffer.baseAddress, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ))
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    }
                    return bytes
                }
                let still = try raster(label.foregroundStyle(color))
                let signal = try raster(AstirOceanParkSignal(
                    label: label, color: color,
                    frame: try XCTUnwrap(AstirOceanParkTracking.frame(elapsed: 0.4))
                ))
                let blank = try raster(Color.clear)
                XCTAssertNotEqual(signal, blank, "The animated label must stay visible in both appearances.")
                XCTAssertNotEqual(signal, still, "The tear must actually alter the letter pixels.")
                // The effect cannot touch the area outside the label's vertical ink band.
                XCTAssertEqual(Array(signal.prefix(300 * 4 * 10)), Array(blank.prefix(300 * 4 * 10)))
                XCTAssertEqual(Array(signal.suffix(300 * 4 * 10)), Array(blank.suffix(300 * 4 * 10)))
            }
        }
    }

    @MainActor
    func testCancellationDuringIdleNeverStartsAnEpisode() async {
        var activeFrames = 0
        await AstirOceanParkTracking.run(
            nextInterval: { 60 },
            sleep: { _ in throw CancellationError() },
            update: { if $0 != nil { activeFrames += 1 } }
        )
        XCTAssertEqual(activeFrames, 0)
    }

    @MainActor
    func testSlowFrameWorkDoesNotExtendOnsetIntervalOrReplayMissedFrames() async {
        var time: TimeInterval = 0
        var onsets: [TimeInterval] = []
        var wasActive = false
        var activeFrames = 0
        await AstirOceanParkTracking.run(
            nextInterval: { 60 }, now: { time },
            sleep: { delay in
                if time >= 63 { throw CancellationError() }
                time += delay
            },
            update: { frame in
                if frame != nil {
                    activeFrames += 1
                    if !wasActive { onsets.append(time) }
                    // Simulate a busy main thread; no catch-up burst is allowed.
                    time += 0.2
                }
                wasActive = frame != nil
            }
        )
        XCTAssertEqual(onsets, [3, 63])
        XCTAssertLessThan(activeFrames, 10)
    }
}
