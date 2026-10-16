import XCTest
import UIKit

/// Test-only public marker reader. All probes come from the same real SDK image.
enum ReplayPublicMarkerProbe {
    enum Phase {
        case ready
        case loaded
    }

    static func validMarker(_ marker: CGRect, in window: CGRect) -> Bool {
        let values = [window.minX, window.minY, window.width, window.height,
                      marker.minX, marker.minY, marker.width, marker.height]
        return values.allSatisfy { $0.isFinite }
            && !window.isEmpty && !window.isNull && !window.isInfinite
            && !marker.isEmpty && !marker.isNull && !marker.isInfinite
            && marker.width > 24 && marker.height > 8 && window.contains(marker)
    }

    static func matches(_ image: UIImage, marker: CGRect, window: CGRect, phase: Phase) -> Bool {
        guard validMarker(marker, in: window), image.imageOrientation == .up,
              let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= 8_192, cgImage.height <= 8_192 else { return false }
        // Decoding SDK WebP/JPEG need not preserve UIImage.scale. Map window
        // coordinates to the actual encoded dimensions, including masked1x frames.
        let scaleX = CGFloat(cgImage.width) / window.width
        let scaleY = CGFloat(cgImage.height) / window.height
        let expectedHeight = CGFloat(cgImage.width) * window.height / window.width
        guard abs(CGFloat(cgImage.height) - expectedHeight) <= 2 else { return false }
        let points = [
            CGPoint(x: marker.minX + 12, y: marker.minY + marker.height * 0.25),
            CGPoint(x: marker.maxX - 12, y: marker.minY + marker.height * 0.25),
            CGPoint(x: marker.minX + 12, y: marker.minY + marker.height * 0.75),
            CGPoint(x: marker.maxX - 12, y: marker.minY + marker.height * 0.75)
        ]
        for point in points {
            let x = Int(((point.x - window.minX) * scaleX).rounded(.down))
            let y = Int(((point.y - window.minY) * scaleY).rounded(.down))
            let region = CGRect(x: CGFloat(x - 1), y: CGFloat(y - 1), width: 3, height: 3)
            guard region.minX >= 0, region.minY >= 0,
                  region.maxX <= CGFloat(cgImage.width), region.maxY <= CGFloat(cgImage.height),
                  let crop = cgImage.cropping(to: region),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
            var bytes = [UInt8](repeating: 0, count: 3 * 3 * 4)
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let converted = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 3, height: 3,
                                              bitsPerComponent: 8, bytesPerRow: 3 * 4,
                                              space: colorSpace, bitmapInfo: bitmapInfo) else { return false }
                context.interpolationQuality = .none
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 3, height: 3))
                return true
            }
            guard converted else { return false }
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let red = bytes[offset], green = bytes[offset + 1]
                let blue = bytes[offset + 2], alpha = bytes[offset + 3]
                guard alpha >= 240 else { return false }
                switch phase {
                case .ready:
                    guard red < 80, green > 180, blue < 80 else { return false }
                case .loaded:
                    guard red > 180, green < 80, blue > 180 else { return false }
                }
            }
        }
        return true
    }
}

final class ReplayPublicMarkerTests: XCTestCase {
    @MainActor
    func testPublicMarkerGatesRejectStaleBlankMaskedWrongColorAndMapScaledImages() throws {
        let window = CGRect(x: 0, y: 0, width: 402, height: 874)
        let marker = CGRect(x: 0, y: 62, width: 402, height: 54)
        let scales: [CGFloat] = [1, 3]
        for scale in scales {
            try autoreleasepool {
                func image(_ color: UIColor?, rect: CGRect? = nil) -> UIImage {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    format.opaque = true
                    return UIGraphicsImageRenderer(size: window.size, format: format).image { context in
                        UIColor.white.setFill()
                        context.fill(window)
                        color?.setFill()
                        if color != nil { context.fill(rect ?? marker) }
                    }
                }
                // Reconstruct from CGImage as an encoded SDK decode does: scale1
                // metadata on a3x pixel canvas must still map to the same marker.
                let ready = UIImage(cgImage: try XCTUnwrap(image(.green).cgImage))
                let loaded = UIImage(cgImage: try XCTUnwrap(image(.magenta).cgImage))
                XCTAssertTrue(ReplayPublicMarkerProbe.matches(ready, marker: marker, window: window, phase: .ready))
                XCTAssertTrue(ReplayPublicMarkerProbe.matches(loaded, marker: marker, window: window, phase: .loaded))
                let readyData = try XCTUnwrap(ready.jpegData(compressionQuality: 0.3))
                let loadedData = try XCTUnwrap(loaded.jpegData(compressionQuality: 0.3))
                let jpegReady = try XCTUnwrap(UIImage(data: readyData))
                let jpegLoaded = try XCTUnwrap(UIImage(data: loadedData))
                XCTAssertTrue(ReplayPublicMarkerProbe.matches(jpegReady, marker: marker, window: window, phase: .ready))
                XCTAssertTrue(ReplayPublicMarkerProbe.matches(jpegLoaded, marker: marker, window: window, phase: .loaded))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(ready, marker: marker, window: window, phase: .loaded))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(loaded, marker: marker, window: window, phase: .ready))
                for invalid in [image(nil), image(.black), image(.blue)] {
                    XCTAssertFalse(ReplayPublicMarkerProbe.matches(invalid, marker: marker, window: window, phase: .ready))
                    XCTAssertFalse(ReplayPublicMarkerProbe.matches(invalid, marker: marker, window: window, phase: .loaded))
                }
                let shifted = image(.green, rect: marker.offsetBy(dx: 0, dy: 100))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(shifted, marker: marker, window: window, phase: .ready))
                let partial = image(.green, rect: CGRect(x: marker.minX, y: marker.minY,
                                                       width: marker.width / 2, height: marker.height))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(partial, marker: marker, window: window, phase: .ready))
                let clipped = try XCTUnwrap(ready.cgImage?.cropping(to: CGRect(x: 0, y: 0,
                    width: CGFloat(ready.cgImage!.width) / 2, height: CGFloat(ready.cgImage!.height))))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(UIImage(cgImage: clipped), marker: marker, window: window, phase: .ready))
                XCTAssertFalse(ReplayPublicMarkerProbe.matches(ready, marker: marker.offsetBy(dx: -20, dy: 0), window: window, phase: .ready))
            }
        }
        XCTAssertFalse(ReplayPublicMarkerProbe.matches(UIImage(), marker: marker, window: window, phase: .ready))
    }
}
