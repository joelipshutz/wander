import Foundation

/// Audience and delivery are independent. An import always suppresses its
/// individual alerts; `silent` controls its single grouped announcement.
struct SenderNotificationPolicy: Codable, Equatable, Hashable, Sendable {
    var silent: Bool
    var importID: String? = nil
    var importCommitID: String? = nil

    static let standard = Self(silent: false)
    static let silent = Self(silent: true)
    var suppressesIndividualAlerts: Bool { silent || importID != nil }

    var persistedJSON: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }

    static func restored(from json: String?) -> Self {
        guard let json else { return .standard }
        // Corrupt new metadata must never turn a silent save into an alert.
        return (try? JSONDecoder().decode(Self.self, from: Data(json.utf8))) ?? .silent
    }
}

/// editing -> locally complete -> synced -> sealed. Later saves never reopen
/// the first manifest. IDs are retained even after delivery/expiry for dedupe.
struct ImportNotificationCommit: Codable, Equatable, Identifiable {
    let id: String
    let ownerID: String
    let importID: String
    let silent: Bool
    var selectedItemIDs: Set<String> = []
    var completedItemIDs: Set<String> = []
    var visitIDs: Set<String> = []
    var locallyComplete = false
    var isSynced = false

    var policy: SenderNotificationPolicy {
        SenderNotificationPolicy(silent: silent, importID: importID, importCommitID: id)
    }
}

extension PlaceImportBatch {
    var hasPreviouslySavedSelections: Bool {
        receipt?.entries.contains { [.added, .existing].contains($0.outcome) && $0.userPlaceID != nil } == true
    }

    var notificationImportID: String {
        guard let captureDeliveryID, let separator = captureDeliveryID.lastIndex(of: ":") else { return id }
        return String(captureDeliveryID[..<separator])
    }
}

@MainActor
protocol ImportNotificationRepository {
    func finalizeImportNotification(_ commit: ImportNotificationCommit, visitIDs: [String]) async throws
}

@MainActor
protocol SenderSocialPlaceSaveRepository {
    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String,
                          senderNotificationPolicy: SenderNotificationPolicy) async throws -> SaveResult
}
