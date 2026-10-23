import AppKit
import WebKit
import AVFoundation

@main struct ExportMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ExportDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class ExportDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), configuration: config)
        web.navigationDelegate = self
        window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.setFrameOrigin(NSPoint(x: -1800, y: -1800))
        window.orderBack(nil)
        web.load(URLRequest(url: URL(string: "http://127.0.0.1:65362/vhs-study/?export=1&v=4")!))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { do { try await export(); exit(0) } catch { print("EXPORT ERROR: \(error)"); exit(1) } }
    }
    func export() async throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1])
        let width = Int(args[2])!, height = Int(args[3])!, bitrate = Int(args[4])!
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: 24, AVVideoMaxKeyFrameIntervalKey: 24, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<192 {
            let t = Double(frame) / 24
            let value = try await web.callAsyncJavaScript("return await window.captureTapeFrame(t,width,height)", arguments: ["t":t,"width":width,"height":height], in: nil, contentWorld: .page)
            guard let encoded = value as? String, let data = Data(base64Encoded: String(encoded.split(separator: ",", maxSplits: 1)[1])), let image = NSBitmapImageRep(data: data)?.cgImage else { throw NSError(domain: "Export", code: 1) }
            if frame == 0 { try data.write(to: url.deletingPathExtension().appendingPathExtension("png")) }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &pb) == kCVReturnSuccess, let pixel = pb else { throw NSError(domain: "Export", code: 2) }
            CVPixelBufferLockBaseAddress(pixel, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.draw(image, in: CGRect(x: 0,y: 0,width: width,height: height))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else { throw writer.error ?? NSError(domain: "Export", code: 3) }
            if frame % 24 == 0 { print("Rendered \(frame)/192"); fflush(stdout) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "Export", code: 4) }
        print("EXPORTED \(url.path)")
    }
}
