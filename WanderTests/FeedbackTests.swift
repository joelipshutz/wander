import XCTest
import UIKit
@testable import Wander

@MainActor final class FeedbackTests: XCTestCase {
    #if DEBUG && targetEnvironment(simulator)
    func testVoicePlaybackPausesResumesAndStopsWithoutLosingAttachment() async throws {
        let audio = FeedbackAudioRecorder()
        let note = FeedbackAudioRecorder.silentTestRecording()
        audio.attachment = note
        defer { audio.close() }
        audio.togglePlayback()
        XCTAssertTrue(audio.isPlaying)
        try await Task.sleep(for: .milliseconds(350))
        audio.togglePlayback()
        let pausedAt = audio.playbackSeconds
        XCTAssertFalse(audio.isPlaying)
        XCTAssertGreaterThan(pausedAt, 0)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(audio.playbackSeconds, pausedAt, accuracy: 0.01)
        audio.togglePlayback()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThan(audio.playbackSeconds, pausedAt)
        audio.pauseForBackground()
        XCTAssertFalse(audio.isPlaying)
        audio.stopPlayback()
        XCTAssertEqual(audio.playbackSeconds, 0)
        XCTAssertEqual(audio.attachment, note)
        audio.remove()
        XCTAssertNil(audio.attachment)
    }

    func testCompletedVoiceNoteCanReplayAndInvalidAudioDoesNotPlay() async throws {
        let audio = FeedbackAudioRecorder()
        defer { audio.close() }
        audio.attachment = FeedbackAudioRecorder.silentTestRecording(seconds: 1)
        audio.togglePlayback()
        for _ in 0..<30 where audio.isPlaying { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(audio.playbackSeconds, 1, accuracy: 0.1)
        audio.togglePlayback()
        XCTAssertTrue(audio.isPlaying)
        XCTAssertLessThan(audio.playbackSeconds, 0.2)
        audio.remove()
        audio.attachment = FeedbackAttachment(kind: .voice, data: Data([0, 1]), duration: 1)
        audio.togglePlayback()
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNotNil(audio.errorMessage)
    }
    #endif

    func testEmptyAndWhitespaceCannotSubmitButPhotoOrVoiceAloneCan() {
        let model = FeedbackComposer()
        XCTAssertFalse(model.canSubmit)
        model.text = " \n "
        XCTAssertFalse(model.canSubmit)
        model.photos = [FeedbackAttachment(kind: .photo, data: Data([1]))]
        XCTAssertTrue(model.canSubmit)
        model.photos = []
        model.voice = FeedbackAttachment(kind: .voice, data: Data([1]), duration: 10)
        XCTAssertTrue(model.canSubmit)
    }

    func testSizeCountAndDurationLimits() {
        let model = FeedbackComposer()
        model.text = String(repeating: "a", count: 5001)
        XCTAssertFalse(model.canSubmit)
        model.text = String(repeating: "👨‍👩‍👧‍👦", count: 1000)
        XCTAssertFalse(model.canSubmit, "Unicode must fit PostgreSQL's character limit too")
        model.text = "A feature request"
        model.photos = (0..<4).map { _ in FeedbackAttachment(kind: .photo, data: Data([1])) }
        XCTAssertFalse(model.canSubmit)
        model.photos = [FeedbackAttachment(kind: .photo, data: Data(count: 2 * 1024 * 1024 + 1))]
        XCTAssertFalse(model.canSubmit)
        model.photos = []
        model.voice = FeedbackAttachment(kind: .voice, data: Data([1]), duration: 181)
        XCTAssertFalse(model.canSubmit)
        model.voice = FeedbackAttachment(kind: .voice, data: Data([1]), duration: 180)
        XCTAssertTrue(model.canSubmit)
    }

    func testFailurePreservesPayloadAndRetryIdentityAndOnlySuccessEmitsAnalytics() async {
        let repository = FeedbackDouble()
        let analytics = FeedbackAnalyticsDouble()
        let model = FeedbackComposer()
        model.text = "Private feature request"
        model.photos = [FeedbackAttachment(kind: .photo, data: Data([1]))]
        repository.fails = true
        await model.submit(repository: repository, analytics: analytics)
        XCTAssertFalse(model.isSubmitted)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.text, "Private feature request")
        XCTAssertTrue(analytics.events.isEmpty)
        repository.fails = false
        await model.submit(repository: repository, analytics: analytics)
        XCTAssertTrue(model.isSubmitted)
        XCTAssertEqual(repository.submissions.count, 2)
        XCTAssertEqual(repository.submissions[0], repository.submissions[1])
        XCTAssertEqual(analytics.events, [AnalyticsEvent(name: "feedback_submitted", properties: [
            "surface": "profile", "photo_count": "1", "has_voice_note": "false"
        ])])
        await model.submit(repository: repository, analytics: analytics)
        XCTAssertEqual(repository.submissions.count, 2)
        XCTAssertEqual(analytics.events.count, 1)
    }

    func testUnavailableBackendDoesNotCelebrateOrLockEditing() async {
        let model = FeedbackComposer()
        model.text = "hello"
        await model.submit(repository: nil, analytics: NoopAnalyticsClient())
        XCTAssertFalse(model.isSubmitted)
        XCTAssertTrue(model.canEdit)
        XCTAssertNotNil(model.errorMessage)
    }

    func testConcurrentTapsSubmitOnlyOnce() async {
        let repository = FeedbackDouble()
        repository.suspend = true
        let model = FeedbackComposer()
        model.text = "hello"
        let task = Task { await model.submit(repository: repository, analytics: NoopAnalyticsClient()) }
        while repository.continuation == nil { await Task.yield() }
        await model.submit(repository: repository, analytics: NoopAnalyticsClient())
        XCTAssertEqual(repository.submissions.count, 1)
        repository.continuation?.resume()
        await task.value
        XCTAssertTrue(model.isSubmitted)
    }

    func testRemoteOrderAndAlreadySubmittedRetrySkipsUploads() async throws {
        let transport = FeedbackTransport()
        let repository = SupabaseFeedbackRepository(rpc: transport, storage: transport)
        let submission = FeedbackSubmission(id: UUID(), text: "Hi", attachments: [
            FeedbackAttachment(kind: .photo, data: Data([1, 2, 3]))
        ], appVersion: "1.0", buildNumber: "176")
        try await repository.submit(submission)
        XCTAssertEqual(transport.operations, ["begin_own_feedback", "upload", "submit_own_feedback"])
        XCTAssertEqual(transport.paths, [submission.id.uuidString.lowercased() + "/" + submission.attachments[0].filename])
        transport.operations = []
        transport.alreadySubmitted = true
        try await repository.submit(submission)
        XCTAssertEqual(transport.operations, ["begin_own_feedback"])
    }

    func testFailedUploadNeverFinalizes() async {
        let transport = FeedbackTransport()
        transport.uploadFails = true
        let repository = SupabaseFeedbackRepository(rpc: transport, storage: transport)
        let submission = FeedbackSubmission(id: UUID(), text: "Hi", attachments: [
            FeedbackAttachment(kind: .photo, data: Data([1]))
        ], appVersion: "1.0", buildNumber: "176")
        do { try await repository.submit(submission); XCTFail("Expected upload failure") } catch {}
        XCTAssertEqual(transport.operations, ["begin_own_feedback", "upload"])
    }

    func testPhotosPreserveAspectRatioAndDownsample() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        }
        let output = try FeedbackPhotoProcessor.jpeg(try XCTUnwrap(image.pngData()))
        let result = try XCTUnwrap(UIImage(data: output))
        XCTAssertEqual(result.size.height / result.size.width, 2, accuracy: 0.01)
        XCTAssertLessThanOrEqual(max(result.size.height, result.size.width), 2000)
        XCTAssertThrowsError(try FeedbackPhotoProcessor.jpeg(Data([0, 1])))
    }
}

@MainActor private final class FeedbackDouble: FeedbackRepository {
    var submissions: [FeedbackSubmission] = []
    var fails = false
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    func submit(_ submission: FeedbackSubmission) async throws {
        submissions.append(submission)
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.notConnectedToInternet) }
    }
}
private final class FeedbackAnalyticsDouble: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
@MainActor private final class FeedbackTransport: RemoteProcedureCalling, RemoteStorageCalling {
    var operations: [String] = []
    var paths: [String] = []
    var alreadySubmitted = false
    var uploadFails = false
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        operations.append(name)
        let submitted = name == "submit_own_feedback" || alreadySubmitted
        return try decoder.decode(Value.self, from: Data("{\"submitted\":\(submitted)}".utf8))
    }
    func uploadObject(bucket: String, path: String, data: Data, contentType: String, upsert: Bool) async throws {
        XCTAssertEqual(bucket, "feedback-attachments")
        XCTAssertEqual(contentType, "image/jpeg")
        XCTAssertTrue(upsert)
        paths.append(path); operations.append("upload")
        if uploadFails { throw URLError(.networkConnectionLost) }
    }
    func deleteObject(bucket: String, path: String) async throws {}
    func downloadObject(bucket: String, path: String) async throws -> Data { Data() }
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL { throw URLError(.badURL) }
}
