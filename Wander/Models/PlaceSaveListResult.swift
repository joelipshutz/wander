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
            parts.append("Added To \(syncedCount == 1 ? "1 List" : "\(syncedCount) Lists").")
        }
        if pendingCount + failedCount > 0 {
            parts.append("Some List Additions Are Saved On This Device And Still Need To Sync. You Can Retry Now Or Let Them Sync Later.")
        }
        if unavailableCount > 0 {
            parts.append("\(unavailableCount == 1 ? "A Selected List Is" : "Some Selected Lists Are") No Longer Available To Add To. Choose Another List From The Place Page.")
        }
        return parts.joined(separator: " ")
    }
}
