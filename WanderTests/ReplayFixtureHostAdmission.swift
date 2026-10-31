import Foundation
import XCTest
@testable import Wander

extension XCTestCase {
    /// No flag preserves ordinary local `xcodebuild test`; an explicit request must be admitted.
    @MainActor
    func admitReplayFixtureHostIfRequested() async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let requested = ReplayFixtureHostPolicy.hasRequest
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(10))
        var admitted = !requested
        if requested, ReplayFixtureHostPolicy.mode == .inert, ReplayFixtureHostPolicy.isExpectedHost {
            while ContinuousClock.now < deadline, !Task.isCancelled {
                if ReplayFixtureHostPolicy.inertRootMounted, !ReplayFixtureHostPolicy.ordinaryRootMounted {
                    admitted = ContinuousClock.now < deadline
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        admitted = admitted && (!requested || ContinuousClock.now < deadline)
        let elapsed = start.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let observation: [String: Any] = [
            "schema": 1, "requested": requested,
            "mode": requested ? (ReplayFixtureHostPolicy.mode == .inert ? "inert" : "invalid") : "ordinary",
            "expected_host": ReplayFixtureHostPolicy.isExpectedHost,
            "inert_root_mounted": ReplayFixtureHostPolicy.inertRootMounted,
            "ordinary_root_mounted": ReplayFixtureHostPolicy.ordinaryRootMounted,
            "admitted": admitted, "elapsed_ms": Int(seconds * 1_000), "limit_ms": 10_000
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Replay host admission"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Replay host admission evidence must be serializable.")
            return false
        }
        guard admitted else {
            XCTFail("Explicit Replay inert-host mode requires one valid mode pair and the actual exclusive inert root before fixture creation.")
            return false
        }
        #endif
        return true
    }
}
