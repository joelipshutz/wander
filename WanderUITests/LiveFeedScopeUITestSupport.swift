import XCTest

extension XCUIApplication {
    @MainActor
    func selectFeedLocation(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = buttons["live.feed.scope.menu"]
        let filterForm = descendants(matching: .any)["live.filters.form"].firstMatch
        XCTAssertTrue(filterForm.waitForNonExistence(timeout: 10), file: file, line: line)
        let drawer = descendants(matching: .any)["live.drawerHandle"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = drawer.value as? String ?? ""
            return menu.exists && menu.isHittable && !value.isEmpty
                && !value.contains("Finding activities")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, file: file, line: line)
        menu.press(forDuration: 0.1)
        let option = buttons[title]
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            option.exists && option.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [offered], timeout: 10), .completed, file: file, line: line)
        option.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", title), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "Selecting \(title) should update the feed location", file: file, line: line)
    }
}
