import AVFoundation
import Combine
import Foundation

@MainActor
final class FeedbackAudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var elapsedSeconds = 0
    @Published var attachment: FeedbackAttachment?
    @Published var errorMessage: String?
    @Published private(set) var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var monitor: Task<Void, Never>?
    private var recordingURL: URL?
    private var active = true

    func start() async {
        guard !isRecording, !isRequestingPermission else { return }
        isRequestingPermission = true
        errorMessage = nil
        defer { isRequestingPermission = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard active else { return }
        guard allowed else {
            permissionDenied = true
            errorMessage = "Microphone access is off. You can enable it in Settings or type your feedback."
            return
        }
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
            guard recorder.record(forDuration: TimeInterval(FeedbackSubmission.maximumVoiceSeconds)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            isRecording = true
            elapsedSeconds = 0
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self, let recorder = self.recorder else { return }
                    if !recorder.isRecording { self.finish(); return }
                    self.elapsedSeconds = Int(recorder.currentTime)
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
        attachment = FeedbackAttachment(kind: .voice, data: data, duration: seconds)
    }

    func togglePlayback() {
        if isPlaying { stopPlayback(); return }
        guard let attachment else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: attachment.data)
            self.player = player
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            isPlaying = true
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self else { return }
                    if self.player?.isPlaying != true { self.stopPlayback(); return }
                }
            }
        } catch {
            stopPlayback()
            errorMessage = "The voice note couldn’t play. Please try again."
        }
    }

    func remove() { stopPlayback(); attachment = nil; elapsedSeconds = 0 }

    func pauseForBackground() {
        if isRecording { finish() }
        stopPlayback()
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
        player?.stop()
        player = nil
        if isPlaying {
            monitor?.cancel()
            monitor = nil
            isPlaying = false
            deactivateSession()
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
