import Foundation

@MainActor
protocol PlacePlanInvitationRepository {
    #if DEBUG
    func create(draft: CommonGroundInvitationDraft, previewPNG: Data) async throws -> WanderShareContent
    #endif
    func invitation(token: String) async throws -> PlacePlanInvitation?
}

@MainActor
final class SupabasePlacePlanInvitationRepository: PlacePlanInvitationRepository {
    private let rpc: any RemoteProcedureCalling
    private let storage: any RemoteStorageCalling
    static let bucket = "place-plan-previews"

    init(rpc: any RemoteProcedureCalling, storage: any RemoteStorageCalling) {
        self.rpc = rpc
        self.storage = storage
    }

    func invitation(token: String) async throws -> PlacePlanInvitation? {
        guard PlacePlanInvitation.isValidToken(token) else { return nil }
        let payload: PlacePlanInvitationPayload? = try await rpc.call("place_plan_preview", params: ["input_token": token])
        guard let payload else { return nil }
        guard payload.imagePath.range(of: #"^[A-Za-z0-9_-]+/[a-f0-9-]{36}/preview[.]png$"#, options: .regularExpression) != nil else {
            throw WanderRemoteError.invalidResponse("invalid_plan_artwork")
        }
        let artworkURL = try storage.publicObjectURL(bucket: Self.bucket, path: payload.imagePath, cacheBust: nil)
        return PlacePlanInvitation(payload: payload, artworkURL: artworkURL)
    }

    #if DEBUG
    func create(draft: CommonGroundInvitationDraft, previewPNG: Data) async throws -> WanderShareContent {
        guard let placeID = draft.place.photoReference?.placeID, UUID(uuidString: placeID) != nil,
              !draft.place.viewer.id.contains("/"), !draft.place.viewer.id.isEmpty,
              !previewPNG.isEmpty, previewPNG.count <= 2_097_152,
              draft.message.count <= 1000
        else { throw WanderRemoteError.invalidResponse("invalid_plan") }
        let path = "\(draft.place.viewer.id)/\(UUID().uuidString.lowercased())/preview.png"
        try await storage.uploadObject(bucket: Self.bucket, path: path, data: previewPNG, contentType: "image/png", upsert: false)
        do {
            let response: CreatedPlan = try await rpc.call("create_place_plan_invitation", params: CreatePlan(
                input_place_id: placeID, input_recipient_id: draft.place.partner.id,
                input_image_path: path, input_message: draft.message,
                input_connection: draft.recipientReasonTitle,
                input_date_label: draft.linkSubtitle,
                input_title: draft.linkTitle,
                input_suggested_at: draft.suggestedDate?.ISO8601Format()
            ))
            guard let content = draft.shareContent(invitationToken: response.token) else {
                throw WanderRemoteError.invalidResponse("invalid_plan_token")
            }
            return content
        } catch {
            // An unsuccessful plan must not leave a deliberate public attachment
            // behind when cleanup is available. Never print its path or contents.
            try? await storage.deleteObject(bucket: Self.bucket, path: path)
            throw error
        }
    }
    #endif
}

#if DEBUG
private struct CreatedPlan: Decodable { let token: String }
private struct CreatePlan: Encodable {
    let input_place_id: String
    let input_recipient_id: String
    let input_image_path: String
    let input_message: String
    let input_connection: String
    let input_date_label: String
    let input_title: String
    let input_suggested_at: String?
}
#endif
