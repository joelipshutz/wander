import AVFoundation
import Foundation

// Local media preparation only. The original is never rewritten.
// Compile: xcrun swiftc -parse-as-library tools/ReviewMedia.swift -o /tmp/astir-review-media
@main
struct ReviewMedia {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            print("Usage: ReviewMedia export INPUT OUTPUT [START_SECONDS END_SECONDS]")
            return
        }
        let input = URL(fileURLWithPath: args[2])
        let output = URL(fileURLWithPath: args[3])
        guard input.standardizedFileURL != output.standardizedFileURL,
              !FileManager.default.fileExists(atPath: output.path) else {
            throw NSError(domain: "ReviewMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Output must be a new file."])
        }
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw NSError(domain: "ReviewMedia", code: 2)
        }
        if args.count == 6, let start = Double(args[4]), let end = Double(args[5]),
           start >= 0, end > start, end <= duration.seconds {
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                            end: CMTime(seconds: end, preferredTimescale: 600))
        } else if args.count != 4 {
            throw NSError(domain: "ReviewMedia", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid trim bounds."])
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? NSError(domain: "ReviewMedia", code: 4)
        }
        let rendered = AVURLAsset(url: output)
        let renderedDuration = try await rendered.load(.duration)
        print("Exported \(output.lastPathComponent): \(renderedDuration.seconds) seconds")
    }
}
