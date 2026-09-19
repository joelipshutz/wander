import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct NativeVideo {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[2]))
        let duration = try await asset.load(.duration).seconds
        if args[1] == "inspect" {
            print("duration=\(duration)")
            return
        }
        guard args.count >= 5 else { return }
        if args[1] == "frame" {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let time = CMTime(seconds: Double(args[3])!, preferredTimescale: 600)
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: args[4]) as CFURL, UTType.png.identifier as CFString, 1, nil
            )!
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        } else if args[1] == "trim" || args[1] == "trim-exact" {
            let start = Double(args[3])!
            let length = args.count > 5 ? Double(args[5])! : duration - start
            let preset = args[1] == "trim-exact" ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset)
            else { return }
            exporter.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: length, preferredTimescale: 600)
            )
            try await exporter.export(to: URL(fileURLWithPath: args[4]), as: .mp4)
            print("Exported native frames: \(length)s")
        }
    }
}
