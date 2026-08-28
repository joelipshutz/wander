import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Vision

private struct BatchRequest: Decodable {
    let items: [MediaRequest]
}

private struct MediaRequest: Decodable {
    let id: String
    let path: String
    let type: String
    let sampleIntervalMs: Int?
    let maximumFrames: Int?
}

private struct BatchResponse: Encodable {
    let engine: String
    let results: [MediaResult]
}

private struct MediaResult: Encodable {
    let id: String
    let text: String?
    let framesScanned: Int
    let observations: [TextObservation]
    let error: RecognitionError?
}

private struct RecognitionError: Encodable {
    let code: String
    let message: String
}

private struct TextObservation: Encodable {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let startMs: Int?
}

private enum Recognizer {
    static func recognize(_ request: MediaRequest) async -> MediaResult {
        if request.type == "video" {
            return await recognizeVideo(request)
        }
        return recognizeImage(request)
    }

    private static func recognizeImage(_ request: MediaRequest) -> MediaResult {
        let url = URL(fileURLWithPath: request.path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return failure(request.id, code: "image_decode_failed", message: "ImageIO could not decode media")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let observations = recognizeText(in: image, orientation: orientation, startMs: nil)
        return success(request.id, observations: observations, framesScanned: 1)
    }

    private static func recognizeVideo(_ request: MediaRequest) async -> MediaResult {
        let asset = AVURLAsset(url: URL(fileURLWithPath: request.path))
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            return failure(request.id, code: "video_duration_failed", message: error.localizedDescription)
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return failure(request.id, code: "invalid_video_duration", message: "Video duration was not positive")
        }
        let maximumFrames = max(1, min(request.maximumFrames ?? 240, 600))
        let requestedInterval = max(100, request.sampleIntervalMs ?? 250)
        let boundedInterval = max(
            requestedInterval,
            Int(ceil(durationSeconds * 1_000 / Double(maximumFrames)))
        )
        let frameCount = min(
            maximumFrames,
            max(1, Int(ceil(durationSeconds * 1_000 / Double(boundedInterval))))
        )
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var observations: [TextObservation] = []
        var scanned = 0
        for index in 0..<frameCount {
            let milliseconds = min(
                Int(durationSeconds * 1_000),
                index * boundedInterval
            )
            let time = CMTime(value: CMTimeValue(milliseconds), timescale: 1_000)
            do {
                let image = try await generator.image(at: time).image
                observations.append(contentsOf: recognizeText(
                    in: image,
                    orientation: .up,
                    startMs: milliseconds
                ))
                scanned += 1
            } catch {
                continue
            }
        }
        guard scanned > 0 else {
            return failure(request.id, code: "video_frame_decode_failed", message: "AVFoundation could not decode a sampled frame")
        }
        return success(request.id, observations: observations, framesScanned: scanned)
    }

    private static func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation,
        startMs: Int?
    ) -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .compactMap { observation -> TextObservation? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let box = observation.boundingBox
                return TextObservation(
                    text: text,
                    confidence: candidate.confidence,
                    x: box.minX,
                    y: box.minY,
                    width: box.width,
                    height: box.height,
                    startMs: startMs
                )
            }
            .sorted { lhs, rhs in
                if lhs.startMs != rhs.startMs {
                    return (lhs.startMs ?? -1) < (rhs.startMs ?? -1)
                }
                if lhs.y != rhs.y { return lhs.y > rhs.y }
                return lhs.x < rhs.x
            }
    }

    private static func success(
        _ id: String,
        observations: [TextObservation],
        framesScanned: Int
    ) -> MediaResult {
        var seen = Set<String>()
        let lines = observations.compactMap { observation -> String? in
            let key = observation.text.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .filter { $0.isLetter || $0.isNumber }
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return observation.text
        }
        return MediaResult(
            id: id,
            text: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            framesScanned: framesScanned,
            observations: observations,
            error: nil
        )
    }

    private static func failure(_ id: String, code: String, message: String) -> MediaResult {
        MediaResult(
            id: id,
            text: nil,
            framesScanned: 0,
            observations: [],
            error: RecognitionError(code: code, message: message)
        )
    }
}

@main
private struct Main {
    static func main() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(BatchRequest.self, from: data)
            var results: [MediaResult] = []
            for item in request.items {
                results.append(await Recognizer.recognize(item))
            }
            let response = BatchResponse(engine: "apple-vision-production-settings-v1", results: results)
            let output = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            let value = ["fatalError": error.localizedDescription]
            if let output = try? JSONSerialization.data(withJSONObject: value) {
                FileHandle.standardOutput.write(output)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
            exit(1)
        }
    }
}
