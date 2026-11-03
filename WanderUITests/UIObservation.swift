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
