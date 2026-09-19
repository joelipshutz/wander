import Foundation

@MainActor
struct SupabaseFeedbackRepository: FeedbackRepository {
    let rpc: any RemoteProcedureCalling
    let storage: any RemoteStorageCalling

    private struct Attachment: Encodable {
        let filename: String
        let kind: String
        let content_type: String
        let byte_size: Int
        let duration_seconds: Int?
    }
    private struct Begin: Encodable {
        let p_id: UUID
        let p_body: String
        let p_attachments: [Attachment]
        let p_app_version: String
        let p_build_number: String
    }
    private struct Identifier: Encodable { let p_id: UUID }
    private struct Receipt: Decodable { let submitted: Bool }

    func submit(_ submission: FeedbackSubmission) async throws {
        guard submission.isValid else { throw WanderRemoteError.invalidResponse("invalid_feedback") }
        let receipt: Receipt = try await rpc.call("begin_own_feedback", params: Begin(
            p_id: submission.id, p_body: submission.text,
            p_attachments: submission.attachments.map {
                Attachment(filename: $0.filename, kind: $0.kind.rawValue,
                           content_type: $0.contentType, byte_size: $0.data.count,
                           duration_seconds: $0.duration)
            }, p_app_version: submission.appVersion, p_build_number: submission.buildNumber
        ))
        if receipt.submitted { return }
        for attachment in submission.attachments {
            try Task.checkCancellation()
            try await storage.uploadObject(
                bucket: "feedback-attachments",
                path: "\(submission.id.uuidString.lowercased())/\(attachment.filename)",
                data: attachment.data, contentType: attachment.contentType, upsert: true
            )
        }
        let final: Receipt = try await rpc.call("submit_own_feedback", params: Identifier(p_id: submission.id))
        guard final.submitted else { throw WanderRemoteError.invalidResponse("feedback_not_submitted") }
    }
}
