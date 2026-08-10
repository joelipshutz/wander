import Foundation
import XCTest
@testable import Wander

final class SharedPlaceImportSourceDetectorTests: XCTestCase {
    func testRoutesKnownProviderLinksAndKeepsOtherAppsGeneric() {
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "https://maps.app.goo.gl/example"
            ),
            .googleMaps
        )
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "Watch https://www.instagram.com/reel/example/"
            ),
            .instagram
        )
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "https://vm.tiktok.com/example/"
            ),
            .tiktok
        )
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "https://maps.apple/p/example"
            ),
            .textNotes
        )
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "https://www.yelp.com/biz/maru-coffee-los-angeles"
            ),
            .textNotes
        )
    }

    func testRoutesGoogleTakeoutStyleFilesWithoutDependingOnTheSharingApp() {
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "",
                fileName: "Saved Places.csv"
            ),
            .googleMaps
        )
        XCTAssertEqual(
            SharedPlaceImportSourceDetector.source(
                for: "",
                fileName: "restaurant ideas.md"
            ),
            .textNotes
        )
    }
}

final class SharedPlaceImportInboxTests: XCTestCase {
    func testCaptureWritesEnvelopeAndAttachmentThenAcknowledgeRemovesBoth() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)

        let envelope = try inbox.capture(
            [
                .text(
                    "https://www.instagram.com/reel/example/",
                    suggestedName: "Instagram"
                ),
                .file(
                    Data("name,address\nMaru Coffee,Los Angeles".utf8),
                    fileName: "Saved Places.csv",
                    contentTypeIdentifier: "public.comma-separated-values-text"
                )
            ],
            deliveryID: "delivery"
        )

        XCTAssertEqual(envelope.items.map(\.source), [.instagram, .googleMaps])
        XCTAssertEqual(Set(envelope.items.map(\.contentHash)).count, 2)

        let scan = try inbox.scan()
        XCTAssertEqual(scan.entries.count, 1)
        let entry = try XCTUnwrap(scan.entries.first)
        let fileItem = try XCTUnwrap(entry.envelope.items.first(where: { $0.kind == .file }))
        XCTAssertEqual(
            try String(contentsOf: inbox.attachmentURL(for: fileItem)),
            "name,address\nMaru Coffee,Los Angeles"
        )

        try inbox.acknowledge(entry)
        XCTAssertTrue(try inbox.scan().entries.isEmpty)
        XCTAssertThrowsError(try inbox.attachmentURL(for: fileItem))
    }

    func testCaptureDeduplicatesIdenticalInputsAndRejectsUnsupportedFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)

        let envelope = try inbox.capture(
            [
                .text("Maru Coffee, Los Angeles", suggestedName: nil),
                .text("Maru Coffee, Los Angeles", suggestedName: nil)
            ]
        )

        XCTAssertEqual(envelope.items.count, 1)
        XCTAssertThrowsError(
            try inbox.capture(
                [
                    .file(
                        Data("not supported".utf8),
                        fileName: "places.pdf",
                        contentTypeIdentifier: "com.adobe.pdf"
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? SharedPlaceImportInboxError, .unsupportedFile)
        }
        XCTAssertThrowsError(
            try inbox.capture(
                [.text("Maru Coffee", suggestedName: nil)],
                deliveryID: "../../outside"
            )
        ) { error in
            XCTAssertEqual(error as? SharedPlaceImportInboxError, .invalidEnvelope)
        }
    }

    func testScanQuarantinesCorruptAndExpiresOldEnvelopes() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        _ = try inbox.capture(
            [.text("Maru Coffee, Los Angeles", suggestedName: nil)],
            deliveryID: "expired",
            createdAt: now.addingTimeInterval(-SharedPlaceImportInbox.retentionInterval - 1)
        )
        let inboxDirectory = root
            .appendingPathComponent("Library/Application Support/rec-me-share-imports/inbox")
        try Data("not-json".utf8).write(
            to: inboxDirectory.appendingPathComponent("corrupt.json")
        )

        let scan = try inbox.scan(now: now)

        XCTAssertTrue(scan.entries.isEmpty)
        XCTAssertEqual(scan.expiredCount, 1)
        XCTAssertEqual(scan.quarantinedCount, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPlaceImportInboxTests-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
final class SharedPlaceImportInboxDrainerTests: XCTestCase {
    func testDrainRoutesAndImportsEveryPayloadExactlyOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPlaceImportDrainerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        let store = PlaceImportStore(
            persistence: SharedImportTestPersistence(),
            resolver: SharedImportTestResolver()
        )
        let inputs: [SharedPlaceImportCaptureInput] = [
            .text("https://maps.app.goo.gl/example", suggestedName: "Google Maps"),
            .text("https://www.instagram.com/reel/example/", suggestedName: "Instagram")
        ]
        _ = try inbox.capture(inputs, deliveryID: "delivery")

        let first = SharedPlaceImportInboxDrainer.drain(inbox: inbox, into: store)

        XCTAssertEqual(first.importedBatchCount, 2)
        XCTAssertEqual(first.duplicateBatchCount, 0)
        XCTAssertEqual(first.batchIDs, store.batches.map(\.id))
        XCTAssertEqual(store.batches.count, 2)
        XCTAssertEqual(store.batches.map(\.source), [.googleMaps, .instagram])
        XCTAssertEqual(
            Set(store.batches.compactMap(\.captureDeliveryID)),
            ["delivery:0", "delivery:1"]
        )

        _ = try inbox.capture(inputs, deliveryID: "delivery")
        let second = SharedPlaceImportInboxDrainer.drain(inbox: inbox, into: store)

        XCTAssertEqual(second.importedBatchCount, 0)
        XCTAssertEqual(second.duplicateBatchCount, 2)
        XCTAssertEqual(second.batchIDs, store.batches.map(\.id))
        XCTAssertEqual(store.batches.count, 2)
        XCTAssertTrue(try inbox.scan().entries.isEmpty)
    }

    func testProjectEmbedsOneUniversalShareExtensionWithTheSharedAppGroup() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj")
        )
        let info = try propertyList(
            projectRoot.appendingPathComponent("WanderShareExtension/Info.plist")
        )
        let entitlements = try propertyList(
            projectRoot.appendingPathComponent(
                "WanderShareExtension/WanderShareExtension.entitlements"
            )
        )

        XCTAssertTrue(project.contains("WanderShareExtension:"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.grayline.wander.share"))
        XCTAssertTrue(project.contains("- WanderImportShared"))
        XCTAssertTrue(generatedProject.contains("WanderShareExtension.appex"))
        XCTAssertTrue(
            generatedProject.contains(
                "PRODUCT_BUNDLE_IDENTIFIER = com.grayline.wander.share;"
            )
        )

        let extensionDictionary = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        XCTAssertEqual(
            extensionDictionary["NSExtensionPointIdentifier"] as? String,
            "com.apple.share-services"
        )
        XCTAssertEqual(
            extensionDictionary["NSExtensionPrincipalClass"] as? String,
            "$(PRODUCT_MODULE_NAME).ShareViewController"
        )
        XCTAssertEqual(
            entitlements["com.apple.security.application-groups"] as? [String],
            [SharedPlaceImportInbox.appGroupIdentifier]
        )
    }

    private func propertyList(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}

private final class SharedImportTestPersistence: PlaceImportPersisting {
    private var snapshot = PlaceImportSnapshot()

    func load() throws -> PlaceImportSnapshot {
        snapshot
    }

    func save(_ snapshot: PlaceImportSnapshot) throws {
        self.snapshot = snapshot
    }
}

@MainActor
private final class SharedImportTestResolver: PlaceImportResolving {
    func resolve(
        seed _: PlaceImportSeed,
        source _: PlaceImportSource
    ) async throws -> PlaceImportResolution {
        .needsHelp("Test resolver")
    }
}
