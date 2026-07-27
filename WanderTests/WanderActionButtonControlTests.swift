import XCTest
@testable import Wander

final class WanderActionButtonControlTests: XCTestCase {
    @MainActor
    func testNavigationCenterRetainsLatestRequestUntilMatchingConsumption() throws {
        let center = WanderControlNavigationCenter()

        center.request(.map)
        let staleRequest = try XCTUnwrap(center.pendingRequest)

        center.request(.quickCapture)
        let latestRequest = try XCTUnwrap(center.pendingRequest)

        XCTAssertNotEqual(staleRequest.id, latestRequest.id)
        XCTAssertEqual(latestRequest.route, .quickCapture)

        center.consume(staleRequest.id)
        XCTAssertEqual(center.pendingRequest, latestRequest)

        center.consume(latestRequest.id)
        XCTAssertNil(center.pendingRequest)
    }

    @available(iOS 18.0, *)
    @MainActor
    func testControlDestinationRoutesToExistingQuickCaptureFlow() {
        XCTAssertEqual(
            WanderControlDestination.checkInHere.route,
            .quickCapture
        )
        XCTAssertEqual(
            WanderOpenCheckInControlIntent().target,
            .checkInHere
        )
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

        XCTAssertTrue(sharedIntent.contains("struct WanderOpenCheckInControlIntent: OpenIntent"))
        XCTAssertTrue(sharedIntent.contains("static let title: LocalizedStringResource = \"Check-in\""))
        XCTAssertTrue(sharedIntent.contains("WanderControlNavigationCenter.shared.request(target.route)"))
        XCTAssertTrue(sharedIntent.contains("static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication"))

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

    func testRootDefersControlRequestUntilSessionValidationAndUsesExistingHandoff() throws {
        let root = try source("Wander/App/WanderRootView.swift")

        XCTAssertTrue(root.contains("@StateObject private var controlNavigationCenter"))
        XCTAssertTrue(root.contains("of: controlNavigationCenter.pendingRequest"))
        XCTAssertTrue(root.contains("guard isSessionValidated, let request else { return }"))
        XCTAssertTrue(root.contains("beginDeepLinkHandoff(to: request.route)"))
        XCTAssertTrue(root.contains("controlNavigationCenter.consume(request.id)"))
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
