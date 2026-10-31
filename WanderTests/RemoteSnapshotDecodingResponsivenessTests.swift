import Foundation
import UIKit
import XCTest
@testable import Wander

/// One equivalent immutable payload through the existing main-actor decoder and
/// the opt-in worker. Excludes networking, SwiftData conversion, and application.
/// The test-only host detaches unrelated root animations; neither decoder changes
/// the payload, date rules, number of rows, or main run-loop heartbeat cadence.
@MainActor
final class RemoteSnapshotDecodingResponsivenessTests: XCTestCase {
    func testSnapshotDecodeResponsivenessWith600PlacesAnd1200Visits() async throws {
        executionTimeAllowance = 120
        let host = try PureModelPerformanceTestHost()
        defer { host.restore() }
        await Task.yield()

        let fixture = try makeFixture()
        let worker = RemoteSnapshotDecoder()
        // Match warm decoder/formatter conditions before timing. Full independent
        // value/date parity is checked here and after every measured decode.
        let mainWarm = try RemoteDecoding.decoder.decode(SnapshotDecodePayload.self, from: fixture.data)
        let workerWarm = try await worker.decode(SnapshotDecodePayload.self, from: fixture.data)
        XCTAssertEqual(mainWarm, fixture.expected)
        XCTAssertEqual(workerWarm, fixture.expected)
        guard mainWarm == fixture.expected, workerWarm == fixture.expected else {
            throw SnapshotDecodeBenchmarkError.valueParity
        }
        XCTAssertGreaterThan(fixture.data.count, 100_000)
        XCTAssertLessThan(fixture.data.count, 2_000_000)

        var samples: [SnapshotDecodeSample] = []
        for pair in 0..<3 {
            // Alternate order to avoid always giving one path the later sample.
            let modes: [SnapshotDecodeMode] = pair == 1 ? [.worker, .mainActor] : [.mainActor, .worker]
            for mode in modes {
                let (value, sample) = try await measure(mode: mode, pair: pair,
                    data: fixture.data, worker: worker)
                XCTAssertEqual(value, fixture.expected, "Every decoded field/date must remain equivalent")
                guard value == fixture.expected else { throw SnapshotDecodeBenchmarkError.valueParity }
                XCTAssertEqual(value.places.count, 600)
                XCTAssertEqual(value.visits.count, 1_200)
                XCTAssertEqual(value.lists.flatMap(\.members).count, 600)
                if mode == .worker {
                    XCTAssertGreaterThan(sample.ticksDuringDecode, 0,
                        "The real main run loop must receive a heartbeat while the worker decodes this payload")
                }
                samples.append(sample)
            }
        }
        let report = SnapshotDecodeReport(
            schema: 1, host: "detached_app_root", workload: "immutable_synthetic_snapshot",
            warmDecoder: true, placeCount: 600, visitCount: 1_200, listCount: 40,
            membershipCount: 600, dateValueCount: 4_904, payloadBytes: fixture.data.count,
            samplesPerMode: 3, heartbeatRequestedIntervalMS: 1,
            heartbeatSource: "main_run_loop_timer_common_modes",
            gapPercentileMethod: "nearest_rank_all_observed_gaps",
            gapsIncludePostCompletionDelivery: true,
            exactValueAndDateParity: true, samples: samples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "REC675 immutable snapshot decoding responsiveness"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func measure(mode: SnapshotDecodeMode, pair: Int, data: Data,
                         worker: RemoteSnapshotDecoder) async throws -> (SnapshotDecodePayload, SnapshotDecodeSample) {
        let heartbeat = SnapshotDecodeHeartbeat()
        heartbeat.start()
        defer { heartbeat.stop() }
        try await waitForTick(heartbeat, after: 0)
        heartbeat.beginMeasurement()

        let start = ProcessInfo.processInfo.systemUptime
        let value: SnapshotDecodePayload
        switch mode {
        case .mainActor:
            value = try RemoteDecoding.decoder.decode(SnapshotDecodePayload.self, from: data)
        case .worker:
            value = try await worker.decode(SnapshotDecodePayload.self, from: data)
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        let ticksDuringDecode = heartbeat.tickCount
        // The first real delivery after completion includes a synchronous decode
        // that blocked the run loop for its whole duration. Validation is later.
        try await waitForTick(heartbeat, after: ticksDuringDecode)
        heartbeat.stop()
        let gaps = heartbeat.gapsMS.sorted()
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertEqual(gaps.count, heartbeat.tickCount)
        XCTAssertTrue(gaps.allSatisfy { $0.isFinite && $0 >= 0 })
        let maximum = try XCTUnwrap(gaps.last)
        let p50 = gaps[max(0, Int(ceil(Double(gaps.count) * 0.50)) - 1)]
        let p95 = gaps[max(0, Int(ceil(Double(gaps.count) * 0.95)) - 1)]
        return (value, SnapshotDecodeSample(mode: mode, pair: pair, decodeWallMS: elapsedMS,
            mainLoopMaximumGapMS: maximum, mainLoopP50GapMS: p50, mainLoopP95GapMS: p95,
            ticksDuringDecode: ticksDuringDecode, gapCountIncludingPostCompletion: gaps.count))
    }

    private func waitForTick(_ heartbeat: SnapshotDecodeHeartbeat, after count: Int) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while heartbeat.tickCount <= count {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("The main run-loop heartbeat was not delivered within its fixed five-second admission bound")
                throw SnapshotDecodeBenchmarkError.heartbeatDeadline
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func makeFixture() throws -> (data: Data, expected: SnapshotDecodePayload) {
        // Explicit epoch values independently check the production date strategy:
        // UTC, fractional UTC, and equivalent nonfractional/fractional offsets.
        let dateText = ["2025-01-01T00:00:00Z", "2025-01-01T00:00:00.125Z",
                        "2024-12-31T16:00:00-08:00", "2025-01-01T02:30:00.500+02:30"]
        let dates = [0.0, 0.125, 0.0, 0.5].map { Date(timeIntervalSince1970: 1_735_689_600 + $0) }
        var placeJSON: [[String: Any]] = []
        var places: [SnapshotDecodePlace] = []
        var visitJSON: [[String: Any]] = []
        var visits: [SnapshotDecodeVisit] = []
        var listJSON: [[String: Any]] = []
        var lists: [SnapshotDecodeList] = []
        for index in 0..<600 {
            let id = "synthetic-place-\(index)"
            let name = "Fixture café \(index)"
            let status = index.isMultiple(of: 2) ? "wanna_go" : "been"
            let deleted = index.isMultiple(of: 25)
            let latitude = Double(index % 100) / 10
            let longitude = -Double(index % 80) / 10
            let json: [String: Any] = ["id": id, "ownerID": "synthetic-owner", "name": name,
                "address": "\(index) Fixture Road", "category": "cafe", "latitude": latitude,
                "longitude": longitude, "status": status, "visibility": "self",
                "createdAt": dateText[index % 4], "savedAt": dateText[(index + 1) % 4],
                "updatedAt": dateText[(index + 2) % 4],
                "deletedAt": deleted ? dateText[(index + 3) % 4] as Any : NSNull()]
            placeJSON.append(json)
            places.append(SnapshotDecodePlace(id: id, ownerID: "synthetic-owner", name: name,
                address: "\(index) Fixture Road", category: "cafe", latitude: latitude, longitude: longitude,
                status: status, visibility: "self", createdAt: dates[index % 4], savedAt: dates[(index + 1) % 4],
                updatedAt: dates[(index + 2) % 4], deletedAt: deleted ? dates[(index + 3) % 4] : nil))
        }
        for index in 0..<1_200 {
            let id = "synthetic-visit-\(index)"
            let parent = "synthetic-place-\(index / 2)"
            let rating = index % 5 + 1
            let json: [String: Any] = ["id": id, "placeID": parent, "rating": rating,
                "note": "Synthetic visit \(index)", "occurredAt": dateText[index % 4],
                "updatedAt": dateText[(index + 1) % 4]]
            visitJSON.append(json)
            visits.append(SnapshotDecodeVisit(id: id, placeID: parent, rating: rating,
                note: "Synthetic visit \(index)", occurredAt: dates[index % 4], updatedAt: dates[(index + 1) % 4]))
        }
        for index in 0..<40 {
            var memberJSON: [[String: Any]] = []
            var members: [SnapshotDecodeMember] = []
            for offset in 0..<15 {
                let placeIndex = index * 15 + offset
                let id = "synthetic-member-\(placeIndex)"
                let parent = "synthetic-place-\(placeIndex)"
                memberJSON.append(["id": id, "placeID": parent, "order": offset,
                                   "addedAt": dateText[placeIndex % 4]])
                members.append(SnapshotDecodeMember(id: id, placeID: parent, order: offset,
                                                     addedAt: dates[placeIndex % 4]))
            }
            let id = "synthetic-list-\(index)"
            listJSON.append(["id": id, "name": "Fixture list \(index)", "members": memberJSON,
                "createdAt": dateText[index % 4], "updatedAt": dateText[(index + 1) % 4]])
            lists.append(SnapshotDecodeList(id: id, name: "Fixture list \(index)", members: members,
                createdAt: dates[index % 4], updatedAt: dates[(index + 1) % 4]))
        }
        let json: [String: Any] = ["revision": 42, "places": placeJSON, "visits": visitJSON, "lists": listJSON]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return (data, SnapshotDecodePayload(revision: 42, places: places, visits: visits, lists: lists))
    }
}

private enum SnapshotDecodeBenchmarkError: Error { case heartbeatDeadline, valueParity }
private enum SnapshotDecodeMode: String, Encodable { case mainActor = "main_actor_default", worker = "immutable_worker" }

private struct SnapshotDecodePayload: Decodable, Equatable, Sendable {
    let revision: Int
    let places: [SnapshotDecodePlace]
    let visits: [SnapshotDecodeVisit]
    let lists: [SnapshotDecodeList]
}
private struct SnapshotDecodePlace: Decodable, Equatable, Sendable {
    let id, ownerID, name, address, category: String
    let latitude, longitude: Double
    let status, visibility: String
    let createdAt, savedAt, updatedAt: Date
    let deletedAt: Date?
}
private struct SnapshotDecodeVisit: Decodable, Equatable, Sendable {
    let id, placeID: String
    let rating: Int
    let note: String
    let occurredAt, updatedAt: Date
}
private struct SnapshotDecodeList: Decodable, Equatable, Sendable {
    let id, name: String
    let members: [SnapshotDecodeMember]
    let createdAt, updatedAt: Date
}
private struct SnapshotDecodeMember: Decodable, Equatable, Sendable {
    let id, placeID: String
    let order: Int
    let addedAt: Date
}
private struct SnapshotDecodeSample: Encodable {
    let mode: SnapshotDecodeMode
    let pair: Int
    let decodeWallMS, mainLoopMaximumGapMS, mainLoopP50GapMS, mainLoopP95GapMS: Double
    let ticksDuringDecode, gapCountIncludingPostCompletion: Int
}
private struct SnapshotDecodeReport: Encodable {
    let schema: Int
    let host, workload: String
    let warmDecoder: Bool
    let placeCount, visitCount, listCount, membershipCount, dateValueCount, payloadBytes, samplesPerMode: Int
    let heartbeatRequestedIntervalMS: Int
    let heartbeatSource, gapPercentileMethod: String
    let gapsIncludePostCompletionDelivery, exactValueAndDateParity: Bool
    let samples: [SnapshotDecodeSample]
}

/// A real main-run-loop timer, not just a task on the MainActor executor.
@MainActor
private final class SnapshotDecodeHeartbeat: NSObject {
    private var timer: Timer?
    private var previous: TimeInterval?
    private(set) var tickCount = 0
    private(set) var gapsMS: [Double] = []

    func start() {
        let timer = Timer(timeInterval: 0.001, target: self,
            selector: #selector(tick), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func beginMeasurement() {
        tickCount = 0
        gapsMS.removeAll(keepingCapacity: true)
        previous = ProcessInfo.processInfo.systemUptime
    }
    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous { gapsMS.append((now - previous) * 1_000) }
        previous = now
        tickCount += 1
    }
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
