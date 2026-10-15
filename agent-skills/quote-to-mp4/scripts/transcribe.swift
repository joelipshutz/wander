import AVFoundation
import Foundation
import Speech

struct Word: Codable {
    let text: String
    let start: Double?
    let end: Double?
}

struct Transcript: Codable {
    let locale: String
    let text: String
    let words: [Word]
}

struct TranscriptionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct Transcribe {
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard (3...4).contains(args.count) else {
                throw TranscriptionError("Usage: transcribe audio-file output.json [locale]")
            }
            guard #available(macOS 26.0, *) else {
                throw TranscriptionError("On-device transcription requires macOS 26+")
            }
            let input = URL(fileURLWithPath: args[1])
            let output = URL(fileURLWithPath: args[2])
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw TranscriptionError("Transcript output already exists")
            }
            let locale = Locale(identifier: args.count == 4 ? args[3] : "en-US")
            let installed = await SpeechTranscriber.installedLocales
            guard installed.contains(where: {
                $0.identifier(.bcp47).lowercased() == locale.identifier(.bcp47).lowercased()
            }) else {
                throw TranscriptionError("No installed model for \(locale.identifier); no download attempted")
            }
            let transcriber = SpeechTranscriber(locale: locale,
                transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let results = Task { () throws -> Transcript in
                var words: [Word] = []
                var parts: [String] = []
                for try await result in transcriber.results {
                    parts.append(String(result.text.characters))
                    for run in result.text.runs {
                        let range = run.audioTimeRange
                        words.append(Word(text: String(result.text[run.range].characters),
                            start: range.map { CMTimeGetSeconds($0.start) },
                            end: range.map { CMTimeGetSeconds($0.end) }))
                    }
                }
                return Transcript(locale: locale.identifier(.bcp47),
                    text: parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }.joined(separator: " "), words: words)
            }
            let file = try AVAudioFile(forReading: input)
            do {
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let transcript = try await results.value
                guard !transcript.text.isEmpty else { throw TranscriptionError("No speech recognized") }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(transcript).write(to: output, options: .withoutOverwriting)
                print("Transcript saved: \(output.path)")
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } catch {
            FileHandle.standardError.write(Data("transcribe: \(error)\n".utf8))
            exit(1)
        }
    }
}
