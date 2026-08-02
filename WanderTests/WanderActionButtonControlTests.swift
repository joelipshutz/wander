import XCTest
@testable import Wander

final class WanderActionButtonControlTests: XCTestCase {
    func testControlLaunchStoreMovesQuickCaptureAcrossProcessesExactlyOnce() throws {
        let suiteName = "WanderActionButtonControlTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WanderControlLaunchRequestStore(defaults: defaults)
        let requestID = UUID()

        XCTAssertEqual(
            store.request(.checkInHere, id: requestID),
            WanderControlNavigationRequest(id: requestID, route: .quickCapture)
        )
        XCTAssertEqual(
            store.takePendingRequest(),
            WanderControlNavigationRequest(id: requestID, route: .quickCapture)
        )
        XCTAssertNil(store.takePendingRequest())
    }

    func testControlIsRegisteredSeparatelyWithoutChangingAccessoryWidgetContract() throws {
        let bundle = try source("WanderWidgets/WanderWidgets.swift")
        let control = try source("WanderWidgets/WanderCheckInControl.swift")
        let sharedIntent = try source(
            "WanderControlShared/WanderCheckInControlIntent.swift"
        )
        let project = try source("project.yml")

        XCTAssertTrue(bundle.contains("if #available(iOS 18.0, *)"))
        XCTAssertTrue(bundle.contains("WanderCheckInControl()"))
        XCTAssertTrue(control.contains("struct WanderCheckInControl: ControlWidget"))
        XCTAssertTrue(control.contains("StaticControlConfiguration("))
        XCTAssertTrue(control.contains("ControlWidgetButton("))
        XCTAssertTrue(control.contains(".displayName(\"Check-in\")"))
        XCTAssertTrue(control.contains("Label(\"Check-in\", systemImage: \"plus\")"))
        XCTAssertFalse(control.contains("systemImage: \"location.fill\""))
        XCTAssertTrue(control.contains(".controlWidgetActionHint(\"Start a check-in\")"))

        XCTAssertTrue(control.contains("action: WanderOpenCheckInControlIntent(target: .checkInHere)"))
        XCTAssertTrue(sharedIntent.contains("struct WanderOpenCheckInControlIntent: OpenIntent"))
        XCTAssertTrue(sharedIntent.contains("WanderControlLaunchRequestStore().request(target)"))
        XCTAssertTrue(sharedIntent.contains("suiteName: WanderWidgetConstants.appGroupIdentifier"))
        XCTAssertFalse(sharedIntent.contains("WanderControlNavigationCenter"))

        XCTAssertEqual(
            project.components(separatedBy: "- WanderControlShared").count - 1,
            2,
            "The intent source belongs to the app and primary widget extension only."
        )

        XCTAssertTrue(bundle.contains("WanderQuickCaptureWidget()"))
        XCTAssertTrue(bundle.contains(".accessoryCircular"))
        XCTAssertFalse(control.contains(".accessoryCircular"))
        XCTAssertFalse(control.contains(".widgetURL("))
    }

    func testAppDrainsDurableControlLaunchIntoExistingDeepLinkInbox() throws {
        let appEntry = try source("Wander/App/AppEntryView.swift")
        let root = try source("Wander/App/WanderRootView.swift")

        XCTAssertTrue(appEntry.contains("WanderControlLaunchRequestStore().takePendingRequest()"))
        XCTAssertTrue(appEntry.contains("WanderDeepLinkLaunchRequest(id: request.id, route: request.route)"))
        XCTAssertTrue(appEntry.contains("receivePendingControlLaunch()"))
        XCTAssertTrue(root.contains("beginDeepLinkHandoff(requestID: request.id, route: request.route)"))
        XCTAssertFalse(root.contains("WanderControlNavigationCenter"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
