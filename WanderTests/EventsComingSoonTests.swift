import AVFoundation
import XCTest
@testable import Wander

@MainActor final class EventsComingSoonTests: XCTestCase {
    func testOnlySelectedVisibleActiveMotionEnabledScreenPlays() {
        for selected in [false, true] {
            for visible in [false, true] {
                for active in [false, true] {
                    for reduced in [false, true] {
                        let policy = EventsPlaybackPolicy(isSelected: selected, isVisible: visible,
                                                          isSceneActive: active, reduceMotion: reduced)
                        XCTAssertEqual(policy.shouldPlay, selected && visible && active && !reduced)
                    }
                }
            }
        }
    }

    func testInactiveAndReducedMotionDoNotCreateDecoder() async {
        let view = EventsVideoView()
        view.update(policy: .init(isSelected: false, isVisible: true, isSceneActive: true, reduceMotion: false))
        await Task.yield()
        XCTAssertNil(view.player)
        view.update(policy: .init(isSelected: true, isVisible: true, isSceneActive: true, reduceMotion: true))
        await Task.yield()
        XCTAssertNil(view.player)
        XCTAssertEqual(view.preparationCount, 0)
    }

    func testRapidExitCancelsPreparationAndReentryReusesPlayer() async throws {
        let view = EventsVideoView()
        let active = EventsPlaybackPolicy(isSelected: true, isVisible: true, isSceneActive: true, reduceMotion: false)
        var inactive = active
        inactive.isSelected = false
        view.update(policy: active)
        view.update(policy: inactive)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(view.player)
        view.update(policy: active)
        try await Task.sleep(for: .milliseconds(50))
        let player = try XCTUnwrap(view.player)
        for _ in 0..<20 {
            view.update(policy: inactive)
            XCTAssertEqual(player.rate, 0)
            view.update(policy: active)
            XCTAssertTrue(view.player === player)
        }
        XCTAssertEqual(view.preparationCount, 1)
        var backgrounded = active
        backgrounded.isSceneActive = false
        view.update(policy: backgrounded)
        XCTAssertEqual(player.rate, 0)
        view.tearDown()
        XCTAssertNil(view.player)
        XCTAssertTrue(player.items().isEmpty)
    }

    func testBundledRecordingIsSmallSilentAndEightSeconds() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "events-coming-soon", withExtension: "mp4"))
        let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(size, 3_500_000)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(duration.seconds, 8, accuracy: 0.05)
        XCTAssertTrue(audio.isEmpty)
        XCTAssertEqual(video.count, 1)
        XCTAssertNotNil(Bundle.main.url(forResource: "events-coming-soon", withExtension: "jpg"))
    }

    func testCompositionSurvivesSmallPhoneAndCompatibilityWindowCropping() {
        // The exported title, bar and caption occupy these normalized bounds.
        let artwork = CGRect(x: 0.10, y: 0.325, width: 0.825, height: 0.307)
        for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852),
                     CGSize(width: 440, height: 956), CGSize(width: 768, height: 1024)] {
            let bounds = CGRect(origin: .zero, size: size)
            let frame = EventsArtworkLayout.frame(in: bounds)
            let scale = max(frame.width / 720, frame.height / 1560)
            let imageSize = CGSize(width: 720 * scale, height: 1560 * scale)
            let imageOrigin = CGPoint(x: frame.midX - imageSize.width / 2, y: frame.midY - imageSize.height / 2)
            let content = CGRect(x: imageOrigin.x + artwork.minX * imageSize.width,
                                 y: imageOrigin.y + artwork.minY * imageSize.height,
                                 width: artwork.width * imageSize.width, height: artwork.height * imageSize.height)
            XCTAssertGreaterThan(content.minX, bounds.minX)
            XCTAssertLessThan(content.maxX, bounds.maxX)
            XCTAssertGreaterThan(content.minY, 65)
            XCTAssertLessThan(content.maxY, size.height - 100)
        }
    }
}
