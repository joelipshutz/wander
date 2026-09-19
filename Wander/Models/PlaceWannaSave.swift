import Foundation

/// A repeat Wanna is an event, not a change to the user's place summary.
/// The UUID also identifies its Feed event and survives offline retries.
struct PlaceWannaSave: Identifiable, Codable, Equatable {
    let id: String
    let ownerID: String
    var userPlaceID: String
    let occurredAt: Date
    var note: String?
    var visibility: PlaceVisibility
    var plannedDate: Date?
    var attributeAnswersJSON: String
    var isSynced: Bool = false
    var editedAt: Date? = nil
    var isHistoricalOriginal: Bool? = nil
    /// Durable deletion revision; retained to reject stale reads and retries.
    var deletedAt: Date? = nil
}

@MainActor
protocol WannaSaveRepository {
    func saveWanna(_ wanna: PlaceWannaSave) async throws
    func updateWanna(_ wanna: PlaceWannaSave) async throws -> PlaceWannaSave
    func deleteWanna(_ wanna: PlaceWannaSave) async throws
    func wannaSaves(userPlaceIDs: [String]) async throws -> [PlaceWannaSave]
}
