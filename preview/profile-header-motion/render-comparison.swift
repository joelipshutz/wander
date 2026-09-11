import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreText

// Usage: swift render-comparison.swift OUTPUT_PREFIX ROLE GLIDE.mp4 SPRING.mp4 ARC.mp4
// Uses Apple's media frameworks; no encoder downloads or external services.
@main
struct MotionComparison {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 6 else {
            print("Usage: render-comparison OUTPUT_PREFIX ROLE GLIDE.mp4 SPRING.mp4 ARC.mp4")
            return
        }
        let output = URL(fileURLWithPath: args[1] + ".mp4")
        let assets = args[3...5].map { AVURLAsset(url: URL(fileURLWithPath: $0)) }
        let composition = AVMutableComposition()
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        var duration = CMTime(seconds: 17.0, preferredTimescale: 600)
        let board = CGSize(width: 1320, height: 1080)
        for (index, asset) in assets.enumerated() {
            guard let source = try await asset.loadTracks(withMediaType: .video).first,
                  let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let available = try await asset.load(.duration)
            duration = CMTimeMinimum(duration, available)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            let size = try await source.load(.naturalSize)
            let transform = try await source.load(.preferredTransform)
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            let scale = min(400 / bounds.width, 910 / bounds.height)
            let x = CGFloat(index) * 440 + (440 - bounds.width * scale) / 2
            let y: CGFloat = 120
            let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            let placement = normalized.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: x, y: y))
            let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            instruction.setTransform(placement, at: .zero)
            layers.append(instruction)
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = NSColor(calibratedRed: 0.949, green: 0.914, blue: 0.859, alpha: 1).cgColor
        instruction.layerInstructions = layers
        let video = AVMutableVideoComposition()
        video.renderSize = board
        video.frameDuration = CMTime(value: 1, timescale: 60)
        video.instructions = [instruction]

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: board)
        let movie = CALayer()
        movie.frame = parent.frame
        parent.addSublayer(movie)
        let bitmap = CGContext(data: nil, width: Int(board.width), height: Int(board.height), bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, bold: Bool = false) {
            let font = CTFontCreateWithName((bold ? "AvenirNext-DemiBold" : "AvenirNext-Regular") as CFString, size, nil)
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.078, green: 0.09, blue: 0.078, alpha: 1)
            ])
            let line = CTLineCreateWithAttributedString(string)
            let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            bitmap.textPosition = CGPoint(x: x + (width - textWidth) / 2, y: y + size * 0.2)
            CTLineDraw(line, bitmap)
        }
        label("PROFILE MOTION  /  " + args[2].uppercased(), x: 0, y: 1031, width: 1320, size: 18, bold: true)
        for (index, title) in ["01  Glide", "02  Soft spring", "03  Staged arc"].enumerated() {
            label(title, x: CGFloat(index) * 440, y: 978, width: 440, size: 27, bold: true)
        }
        label("Scroll down → transform → hold while content scrolls → scroll back to restore", x: 0, y: 18, width: 1320, size: 18)
        let annotations = CALayer()
        annotations.frame = parent.frame
        annotations.contents = bitmap.makeImage()
        parent.addSublayer(annotations)
        video.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: movie, in: parent)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exporter.videoComposition = video
        try await exporter.export(to: output, as: .mp4)
        print("Created \(output.lastPathComponent)")

        let asset = AVURLAsset(url: output)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 990, height: 810)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let gifURL = URL(fileURLWithPath: args[1] + ".gif")
        let count = Int(duration.seconds * 10)
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, count, nil) else { return }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / 10, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
            if index == 48 {
                let stillURL = URL(fileURLWithPath: args[1] + "-pinned.png")
                if let still = CGImageDestinationCreateWithURL(stillURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(still, image, nil)
                    CGImageDestinationFinalize(still)
                }
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        print("Created \(gifURL.lastPathComponent)")
    }
}
