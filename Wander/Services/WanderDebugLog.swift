import Foundation
import OSLog

enum WanderDebugLog {
    static let sync = Logger(subsystem: "com.grayline.wander", category: "WanderSync")
    static let remote = Logger(subsystem: "com.grayline.wander", category: "WanderRemote")
    static let performance = Logger(subsystem: "com.grayline.wander", category: "WanderPerformance")
    static let imports = Logger(subsystem: "com.grayline.wander", category: "WanderImports")

    static func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return String(value.prefix(10))
    }

    static func clean(_ value: String, maxLength: Int = 700) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard singleLine.count > maxLength else { return singleLine }
        return "\(singleLine.prefix(maxLength))..."
    }

    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code)"
    }
}
