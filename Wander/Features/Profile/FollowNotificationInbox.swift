import Combine
import Foundation

struct FollowNotification: Identifiable, Decodable, Equatable {
    let id: UUID
    let actorID: String
    let displayName: String
    let handle: String
    let avatarURL: String?
    let createdAt: Date
    let isMutual: Bool

    enum CodingKeys: String, CodingKey {
        case id, handle
        case actorID = "actor_id", displayName = "display_name", avatarURL = "avatar_url"
        case createdAt = "created_at", isMutual = "is_mutual"
    }
}

@MainActor protocol FollowNotificationRepository {
    func receivedFollows() async throws -> [FollowNotification]
}

@MainActor struct SupabaseFollowNotificationRepository: FollowNotificationRepository {
    let rpc: any RemoteProcedureCalling
    func receivedFollows() async throws -> [FollowNotification] {
        try await rpc.call("received_follow_notifications", params: [String: String]())
    }
}

@MainActor final class FollowNotificationInbox: ObservableObject {
    @Published private(set) var notifications: [FollowNotification] = []
    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation = UUID()

    func reset(for userID: String?) {
        guard self.userID != userID else { return }
        generation = UUID()
        self.userID = userID
        notifications = []
        isLoading = false
        failed = false
    }

    func refresh(userID: String, repository: (any FollowNotificationRepository)?) async {
        reset(for: userID)
        let request = UUID()
        generation = request
        isLoading = true
        failed = false
        defer { if generation == request { isLoading = false } }
        do {
            guard let repository else { throw WanderRemoteError.notConfigured }
            let rows = try await repository.receivedFollows()
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            notifications = rows
        } catch {
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            notifications = []
            failed = true
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
struct SimulatorFollowNotificationRepository: FollowNotificationRepository {
    var includesNotifications = true

    func receivedFollows() async throws -> [FollowNotification] {
        guard includesNotifications else { return [] }
        return [FollowNotification(id: UUID(uuidString: "59700000-0000-0000-0000-000000000001")!,
                            actorID: "user_ryan", displayName: "Ryan", handle: "ryan", avatarURL: nil,
                            createdAt: .now.addingTimeInterval(-600), isMutual: true)]
    }
}
#endif
