import AppKit
import AVFoundation
import Foundation

// Local-only still-card renderer. Source discovery and spoken-word verification
// belong to the skill workflow, not to this media encoder.
struct RenderRequest: Decodable {
    let input: String
    let output: String
    let start: Double
    let duration: Double
    let speaker: String
    let title: String
    let source: String
    let date: String?
    let layout: String?
}

struct RenderError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw RenderError(message) }
}

@main
struct Render {
    @MainActor
    static func main() async {
        do {
            try require(CommandLine.arguments.count == 2, "Usage: render request.json")
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let request = try JSONDecoder().decode(RenderRequest.self, from: data)
            try await run(request)
        } catch {
            FileHandle.standardError.write(Data("render: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func drawText(_ text: String, in rect: CGRect, size: CGFloat,
                         weight: NSFont.Weight, color: NSColor) throws {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        var fontSize = size
        while fontSize >= 18 {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color, .paragraphStyle: style
            ]
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            if bounds.height <= rect.height && bounds.width <= rect.width + 1 {
                (text as NSString).draw(in: rect, withAttributes: attributes)
                return
            }
            fontSize -= 2
        }
        throw RenderError("Title-card text does not fit; shorten the metadata: \(text)")
    }

    @MainActor
    static func card(_ request: RenderRequest, width: Int, height: Int) throws -> CGImage {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderError("Cannot create title card")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let w = CGFloat(width), h = CGFloat(height)
        let portrait = height > width
        let left = w * 0.075, contentWidth = w * (portrait ? 0.78 : 0.85)
        let ink = NSColor(srgbRed: 0.16, green: 0.15, blue: 0.14, alpha: 1)
        let muted = NSColor(srgbRed: 0.39, green: 0.36, blue: 0.33, alpha: 1)
        NSColor(srgbRed: 0.96, green: 0.94, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: w, height: h)).fill()
        NSColor(srgbRed: 0.66, green: 0.35, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: left, y: h * 0.81, width: w * 0.055, height: 5)).fill()
        try drawText(request.speaker, in: CGRect(x: left, y: h * 0.69,
            width: contentWidth, height: h * 0.09), size: portrait ? 38 : 30,
            weight: .semibold, color: muted)
        try drawText(request.title, in: CGRect(x: left, y: h * 0.37,
            width: contentWidth, height: h * 0.29), size: portrait ? 86 : 78,
            weight: .bold, color: ink)
        try drawText(request.source, in: CGRect(x: left, y: h * 0.24,
            width: contentWidth, height: h * 0.10), size: portrait ? 32 : 25,
            weight: .regular, color: muted)
        try drawText(request.date ?? "", in: CGRect(x: left, y: h * 0.17,
            width: contentWidth, height: h * 0.06), size: portrait ? 28 : 23,
            weight: .regular, color: muted)
        guard let image = bitmap.cgImage else { throw RenderError("Cannot rasterize title card") }
        return image
    }

    @MainActor
    static func run(_ request: RenderRequest) async throws {
        try require(request.input.hasPrefix("/") && request.output.hasPrefix("/"),
                    "Input and output must be absolute local file paths")
        try require(request.start.isFinite && request.duration.isFinite &&
                    request.start >= 0 && request.duration > 0, "Invalid start/duration")
        try require(request.duration <= 3600, "Use a dedicated editor for clips longer than an hour")
        let layout = request.layout ?? "landscape"
        try require(["landscape", "portrait"].contains(layout), "Unknown layout")
        for text in [request.speaker, request.title, request.source] {
            try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Speaker, title, and source must not be empty")
        }
        let files = FileManager.default
        let input = URL(fileURLWithPath: request.input)
        let output = URL(fileURLWithPath: request.output)
        let preview = output.deletingPathExtension().appendingPathExtension("png")
        try require(output.pathExtension.lowercased() == "mp4", "Output must end in .mp4")
        try require(files.fileExists(atPath: input.path), "Input media is missing")
        try require(!files.fileExists(atPath: output.path) && !files.fileExists(atPath: preview.path),
                    "Output MP4 or preview already exists; choose an unused output path")
        let asset = AVURLAsset(url: input)
        let sourceLength = CMTimeGetSeconds(try await asset.load(.duration))
        try require(sourceLength.isFinite && request.start + request.duration <= sourceLength,
                    "Requested interval extends past the source duration")
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audio = audioTracks.first else { throw RenderError("Source has no audio track") }

        let width = layout == "portrait" ? 1080 : 1280
        let height = layout == "portrait" ? 1920 : 720
        let image = try card(request, width: width, height: height)
        let parent = output.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let scratch = parent.appendingPathComponent(".quote-render-" + UUID().uuidString)
        try files.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: scratch) }
        let silent = scratch.appendingPathComponent("card.mp4")
        let staged = scratch.appendingPathComponent("soundbite.mp4")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        try require(writer.canAdd(writerInput), "Video encoder cannot accept the requested settings")
        writer.add(writerInput)
        guard writer.startWriting() else { throw writer.error ?? RenderError("Cannot start encoder") }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw RenderError("Cannot allocate video frame")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width,
            height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { throw RenderError("Cannot draw video frame") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let fps: Int32 = 24
        for frame in 0..<Int(ceil(request.duration * Double(fps))) {
            let deadline = Date().addingTimeInterval(30)
            while !writerInput.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? RenderError("Video encoder failed") }
                try require(Date() < deadline, "Video encoder stalled")
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                throw writer.error ?? RenderError("Cannot encode frame")
            }
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "Video encoder did not finish: \(String(describing: writer.error))")

        let duration = CMTime(seconds: request.duration, preferredTimescale: 600)
        let composition = AVMutableComposition()
        let silentAsset = AVURLAsset(url: silent)
        let silentTracks = try await silentAsset.loadTracks(withMediaType: .video)
        guard let silentTrack = silentTracks.first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw RenderError("Cannot create audio/video composition") }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: silentTrack, at: .zero)
        try audioTrack.insertTimeRange(CMTimeRange(
            start: CMTime(seconds: request.start, preferredTimescale: 600), duration: duration), of: audio, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw RenderError("MP4 export unavailable") }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: duration)
        if #available(macOS 15.0, *) {
            try await exporter.export(to: staged, as: .mp4)
        } else {
            exporter.outputURL = staged
            exporter.outputFileType = .mp4
            await exporter.export()
            guard exporter.status == .completed else { throw exporter.error ?? RenderError("MP4 export failed") }
        }

        let finished = AVURLAsset(url: staged)
        let actualDuration = CMTimeGetSeconds(try await finished.load(.duration))
        let finalVideo = try await finished.loadTracks(withMediaType: .video)
        let finalAudio = try await finished.loadTracks(withMediaType: .audio)
        try require(finalVideo.count == 1 && finalAudio.count == 1, "Export is missing an audio/video track")
        let videoFormats = try await finalVideo[0].load(.formatDescriptions)
        let audioFormats = try await finalAudio[0].load(.formatDescriptions)
        try require(videoFormats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_H264,
                    "Export did not produce H.264 video")
        try require(audioFormats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kAudioFormatMPEG4AAC,
                    "Export did not produce AAC audio")
        try require(abs(actualDuration - request.duration) < 0.1, "Unexpected export duration")
        let generator = AVAssetImageGenerator(asset: finished)
        generator.appliesPreferredTrackTransform = true
        let (frame, _) = try await generator.image(at: CMTime(
            seconds: min(0.5, request.duration / 2), preferredTimescale: 600))
        try require(frame.width == width && frame.height == height, "Unexpected export dimensions")
        guard let png = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])
        else { throw RenderError("Cannot encode preview") }
        // Publish only validated output, refusing collisions even if a destination
        // appeared while rendering. All intermediates remain in our own directory.
        try png.write(to: preview, options: .withoutOverwriting)
        do { try files.moveItem(at: staged, to: output) }
        catch { try? files.removeItem(at: preview); throw error }
        let summary: [String: Any] = ["output": output.path, "preview": preview.path,
            "duration": actualDuration, "width": width, "height": height,
            "audio_tracks": finalAudio.count, "video_tracks": finalVideo.count,
            "video_codec": "h264", "audio_codec": "aac"]
        let report = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        print(String(decoding: report, as: UTF8.self))
    }
}
