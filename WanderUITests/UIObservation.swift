import XCTest

/// Read ready state immediately, then poll within the same original budget.
/// Native AX reads are synchronous: a true result arriving after the deadline
/// must not turn an over-budget observation into a pass.
@MainActor
enum UIObservation {
    static func wait(timeout: TimeInterval, condition: @escaping () -> Bool) -> XCTWaiter.Result {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        func observe() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            let satisfied = condition()
            return satisfied && ProcessInfo.processInfo.systemUptime <= deadline
        }
        if observe() { return .completed }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return .timedOut }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in observe() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: remaining)
    }

    /// Simulator setup notifications are not part of the app interaction. Clear
    /// only the native notification banner, before admitting a timed app input.
    static func dismissSystemNotificationBannerIfPresent() -> Bool {
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .otherElements["NotificationShortLookView"].firstMatch
        guard banner.exists else { return true }
        banner.swipeUp()
        return banner.waitForNonExistence(timeout: 5)
    }

    static func descendants(of root: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        var result: [XCUIElementSnapshot] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}
