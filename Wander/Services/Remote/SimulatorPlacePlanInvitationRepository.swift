#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Explicit UI-test fixture; never selected by ordinary Simulator/device runs.
@MainActor final class SimulatorPlacePlanInvitationRepository: PlacePlanInvitationRepository {
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
