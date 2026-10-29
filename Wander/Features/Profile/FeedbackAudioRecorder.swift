import AVFoundation
import Combine
import Foundation

@MainActor
final class FeedbackAudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var playbackSeconds: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var levels: [Double] = Array(repeating: 0, count: 36)
    @Published var attachment: FeedbackAttachment?
    @Published var errorMessage: String?
    @Published private(set) var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var monitor: Task<Void, Never>?
    private var recordingURL: URL?
    private var active = true
    private var recordingRequestID = UUID()
    private var recordedLevels: [Double] = []

    override init() {
        super.init()
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-WanderAuthenticatedUITest"), arguments.contains("-WanderFeedbackUITest"),
           arguments.contains("-WanderFeedbackVoiceUITest") {
            attachment = Self.silentTestRecording()
            elapsedSeconds = attachment?.duration ?? 0
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    // Real, silent PCM playback for UI tests; no microphone or remote service is used.
    static func silentTestRecording(seconds: Int = 8) -> FeedbackAttachment {
        let byteCount = seconds * 8_000 * 2
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + byteCount))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(8_000)); append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(byteCount)); data.append(Data(count: byteCount))
        return FeedbackAttachment(kind: .voice, data: data, duration: seconds)
    }
    #endif

    func start() async {
        guard active, !isRecording, !isRequestingPermission, attachment == nil else { return }
        let requestID = UUID()
        recordingRequestID = requestID
        isRequestingPermission = true
        errorMessage = nil
        defer { isRequestingPermission = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard active, recordingRequestID == requestID else { return }
        guard allowed else {
            permissionDenied = true
            errorMessage = "Microphone access is off. You can enable it in Settings or type your feedback."
            return
        }
        permissionDenied = false
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("astir-feedback-\(UUID().uuidString).m4a")
            recordingURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            self.recorder = recorder
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: TimeInterval(FeedbackSubmission.maximumVoiceSeconds)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            isRecording = true
            elapsedSeconds = 0
            recordedLevels = []
            levels = Array(repeating: 0, count: 36)
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, let recorder = self.recorder else { return }
                    if !recorder.isRecording { self.finish(); return }
                    self.elapsedSeconds = Int(recorder.currentTime)
                    recorder.updateMeters()
                    let level = max(0, min(1, Double(recorder.averagePower(forChannel: 0) + 50) / 50))
                    self.recordedLevels.append(level)
                    self.levels = Array((self.levels + [level]).suffix(36))
                }
            }
        } catch {
            cancelRecording()
            errorMessage = "The recording couldn’t start. Please try again or type your feedback."
        }
    }

    func finish() {
        guard let recorder, isRecording else { return }
        let seconds = min(FeedbackSubmission.maximumVoiceSeconds, max(1, Int(ceil(recorder.currentTime)), elapsedSeconds))
        recorder.stop()
        monitor?.cancel()
        monitor = nil
        isRecording = false
        self.recorder = nil
        defer { removeTemporaryFile(); deactivateSession() }
        guard let url = recordingURL, let data = try? Data(contentsOf: url),
              !data.isEmpty, data.count <= FeedbackSubmission.maximumAttachmentBytes else {
            errorMessage = "The voice note couldn’t be saved. Please record it again."
            return
        }
        elapsedSeconds = seconds
        levels = Self.waveform(recordedLevels)
        attachment = FeedbackAttachment(kind: .voice, data: data, duration: seconds)
    }

    func togglePlayback() {
        if isPlaying { pausePlayback(); return }
        guard let attachment else { return }
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try self.player ?? AVAudioPlayer(data: attachment.data)
            self.player = player
            if playbackSeconds >= player.duration { player.currentTime = 0 }
            playbackDuration = player.duration
            playbackSeconds = player.currentTime
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            isPlaying = true
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, let player = self.player else { return }
                    if !player.isPlaying {
                        self.playbackSeconds = player.duration
                        self.isPlaying = false
                        self.monitor = nil
                        self.deactivateSession()
                        return
                    }
                    self.playbackSeconds = player.currentTime
                }
            }
        } catch {
            stopPlayback()
            errorMessage = "The voice note couldn’t play. Please try again."
        }
    }

    func remove() {
        stopPlayback()
        attachment = nil
        elapsedSeconds = 0
        recordedLevels = []
        levels = Array(repeating: 0, count: 36)
        errorMessage = nil
    }

    func pauseForBackground() {
        // A permission prompt may resolve after switching tabs or backgrounding.
        recordingRequestID = UUID()
        if isRecording { finish() }
        pausePlayback()
    }

    func close() { active = false; cancelRecording(); stopPlayback() }

    private func cancelRecording() {
        monitor?.cancel()
        monitor = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        removeTemporaryFile()
        deactivateSession()
    }

    func stopPlayback() {
        pausePlayback()
        player?.stop()
        player = nil
        playbackSeconds = 0
        playbackDuration = 0
        if !isRecording { deactivateSession() }
    }

    private func pausePlayback() {
        player?.pause()
        if isPlaying {
            playbackSeconds = player?.currentTime ?? playbackSeconds
            monitor?.cancel()
            monitor = nil
            isPlaying = false
            deactivateSession()
        }
    }

    private static func waveform(_ samples: [Double]) -> [Double] {
        guard !samples.isEmpty else { return Array(repeating: 0, count: 36) }
        return (0..<36).map { index in
            let start = index * samples.count / 36
            let end = max(start + 1, (index + 1) * samples.count / 36)
            return samples[start..<min(end, samples.count)].max() ?? 0
        }
    }

    private func removeTemporaryFile() {
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
