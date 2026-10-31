import Foundation

/// Only immutable, checked-Sendable wire values cross this boundary. Model
/// construction, authorization and application remain with the main-actor caller.
protocol RemoteSnapshotDecoding: Sendable {
    func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) async throws -> Value
}

actor RemoteSnapshotDecoder: RemoteSnapshotDecoding {
    private var decoder: JSONDecoder?

    private func configuredDecoder() -> JSONDecoder {
        if let decoder { return decoder }
        let dates = SnapshotDateParser()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = dates.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date string."
            )
        }
        self.decoder = decoder
        return decoder
    }

    func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) async throws -> Value {
        try Task.checkCancellation()
        let value = try configuredDecoder().decode(type, from: data)
        try Task.checkCancellation()
        return value
    }
}

/// JSONDecoder's custom strategy is Sendable. Keep its non-Sendable Foundation
/// formatters private and serialize every access, including through that closure.
/// Each decoder owns its parser; none of the main-actor formatters are shared.
private final class SnapshotDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractional: ISO8601DateFormatter
    private let whole: ISO8601DateFormatter

    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
    }

    func date(from value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: value) ?? whole.date(from: value)
    }
}
