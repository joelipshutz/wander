import Foundation

/// A cached copy is an offline convenience, never a fallback for a denied read.
enum ProtectedContentCachePolicy {
    static func permitsOfflineRead(after error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return error.code == .notConnectedToInternet || error.code == .networkConnectionLost
    }
}
