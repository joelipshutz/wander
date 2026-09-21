import Foundation

/// List delivery is separate from the already committed check-in or Wanna. Retrying
/// these destinations must never create another visit or companion Wanna.
struct PlaceSaveListResult: Equatable {
    var syncedCount = 0
    var pendingCount = 0
    var failedCount = 0
    var unavailableCount = 0

    var needsAttention: Bool {
        pendingCount + failedCount + unavailableCount > 0
    }

    var message: String {
        var parts: [String] = []
        if syncedCount > 0 {
            parts.append("Added to \(syncedCount == 1 ? "1 list" : "\(syncedCount) lists").")
        }
        if pendingCount + failedCount > 0 {
            parts.append("Some list additions are saved on this device and still need to sync. You can retry now or let them sync later.")
        }
        if unavailableCount > 0 {
            parts.append("\(unavailableCount == 1 ? "A selected list is" : "Some selected lists are") no longer available to add to. Choose another list from the place page.")
        }
        return parts.joined(separator: " ")
    }
}
