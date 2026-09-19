#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Explicit UI-test fixture; never selected by ordinary Simulator/device runs.
@MainActor final class SimulatorPlacePlanInvitationRepository: PlacePlanInvitationRepository {
    private var readAt: Date?
    static let invitationID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!

    func receivedInvitations() async throws -> [ReceivedPlacePlanInvitation] {
        guard let invitation = try await invitation(token: String(repeating: "a", count: 48)) else { return [] }
        return [ReceivedPlacePlanInvitation(id: Self.invitationID, invitation: invitation, createdAt: .now, readAt: readAt)]
    }

    func receivedInvitation(id: UUID) async throws -> PlacePlanInvitation? {
        guard id == Self.invitationID else { return nil }
        readAt = readAt ?? .now
        return try await invitation(token: String(repeating: "a", count: 48))
    }

    func create(draft: CommonGroundInvitationDraft, previewPNG: Data) async throws -> WanderShareContent {
        throw WanderRemoteError.notImplemented("read-only UI fixture")
    }

    func invitation(token: String) async throws -> PlacePlanInvitation? {
        guard token == String(repeating: "a", count: 48) else { return nil }
        return PlacePlanInvitation(payload: PlacePlanInvitationPayload(
            title: "Let’s go to Narwhal together", placeName: "Narwhal", location: "Los Angeles",
            senderName: "Ryan", senderAvatarURL: nil, message: "Coffee on Saturday?",
            connection: "Both Wanna Go", dateLabel: "Sep 19, 2026 at 10 AM", imagePath: ""
        ), artworkURL: URL(string: "https://example.invalid/preview.png")!)
    }
}
#endif
