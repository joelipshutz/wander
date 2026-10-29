import Combine
import Foundation

struct FeedbackAttachment: Identifiable, Equatable {
    enum Kind: String, Codable { case photo, voice }
    let id: UUID
    let kind: Kind
    let data: Data
    let duration: Int?

    init(id: UUID = UUID(), kind: Kind, data: Data, duration: Int? = nil) {
        self.id = id
        self.kind = kind
        self.data = data
        self.duration = duration
    }

    var filename: String { "\(id.uuidString.lowercased()).\(kind == .photo ? "jpg" : "m4a")" }
    var contentType: String { kind == .photo ? "image/jpeg" : "audio/mp4" }
}

struct FeedbackSubmission: Equatable {
    static let maximumTextLength = 5_000
    static let maximumPhotos = 3
    static let maximumAttachmentBytes = 2 * 1_024 * 1_024
    static let maximumVoiceSeconds = 180

    let id: UUID
    let text: String
    let attachments: [FeedbackAttachment]
    let appVersion: String
    let buildNumber: String

    var isValid: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && text.unicodeScalars.count <= Self.maximumTextLength
            && attachments.filter { $0.kind == .photo }.count <= Self.maximumPhotos
            && attachments.filter { $0.kind == .voice }.count <= 1
            && Set(attachments.map(\.id)).count == attachments.count
            && attachments.allSatisfy {
                !$0.data.isEmpty && $0.data.count <= Self.maximumAttachmentBytes
                    && ($0.kind == .photo || (1...Self.maximumVoiceSeconds).contains($0.duration ?? 0))
            }
    }
}

@MainActor
protocol FeedbackRepository {
    func submit(_ submission: FeedbackSubmission) async throws
}

#if DEBUG && targetEnvironment(simulator)
private actor FeedbackUITestDelay {
    static func wait() async throws { try await Task.sleep(for: .milliseconds(350)) }
}
struct FeedbackUITestRepository: FeedbackRepository {
    func submit(_ submission: FeedbackSubmission) async throws { try await FeedbackUITestDelay.wait() }
}
#endif

@MainActor
final class FeedbackComposer: ObservableObject {
    @Published var text = ""
    @Published var photos: [FeedbackAttachment] = []
    @Published var voice: FeedbackAttachment?
    @Published private(set) var isSubmitting = false
    @Published private(set) var isSubmitted = false
    @Published private(set) var pendingSubmission: FeedbackSubmission?
    @Published var errorMessage: String?

    var attachments: [FeedbackAttachment] { photos + (voice.map { [$0] } ?? []) }
    var hasContent: Bool { !text.isEmpty || !attachments.isEmpty }
    var canEdit: Bool { pendingSubmission == nil && !isSubmitted }
    var canSubmit: Bool { !isSubmitting && !isSubmitted && (pendingSubmission ?? snapshot()).isValid }

    func submit(repository: (any FeedbackRepository)?, analytics: any AnalyticsClient) async {
        guard canSubmit else { return }
        guard let repository else {
            errorMessage = "Feedback is unavailable right now. Your note is still here; please try again shortly."
            return
        }
        // Freeze the payload and identifier across ambiguous network failures.
        let submission = pendingSubmission ?? snapshot()
        pendingSubmission = submission
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await repository.submit(submission)
            isSubmitted = true
            analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.feedbackSubmitted, properties: [
                "surface": "profile",
                "photo_count": String(submission.attachments.filter { $0.kind == .photo }.count),
                "has_voice_note": String(submission.attachments.contains { $0.kind == .voice })
            ]))
        } catch {
            errorMessage = "We couldn’t confirm your submission. Your feedback is still here. Tap Try again to send the same report."
        }
    }

    private func snapshot() -> FeedbackSubmission {
        FeedbackSubmission(id: UUID(), text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                           attachments: attachments,
                           appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                           buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }
}
