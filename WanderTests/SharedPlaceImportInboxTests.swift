import Foundation
import UniformTypeIdentifiers
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
                for: "https://www.snapchat.com/p/example"
            ),
            .snapchat
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
    func testPayloadBudgetRejectsAggregateShareBeforeAnotherProviderLoads() throws {
        let nearlyFull = SharedPlaceImportInbox.maximumTotalBytes - 4

        XCTAssertEqual(
            try SharedPlaceImportPayloadBudget.adding(4, to: nearlyFull),
            SharedPlaceImportInbox.maximumTotalBytes
        )
        XCTAssertThrowsError(
            try SharedPlaceImportPayloadBudget.adding(5, to: nearlyFull)
        ) { error in
            XCTAssertEqual(error as? SharedPlaceImportInboxError, .totalPayloadTooLarge)
        }
    }

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

    func testCapturePersistsASocialLinkAndItsSharedCaptionTogether() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        let url = try XCTUnwrap(URL(string: "https://www.instagram.com/reel/example/"))

        let envelope = try inbox.capture(
            [
                .sharedLink(
                    url,
                    contextText: "Lunch at @mendocinofarms in Los Angeles.",
                    suggestedName: "Instagram"
                )
            ],
            deliveryID: "caption-delivery"
        )

        XCTAssertEqual(envelope.version, 3)
        XCTAssertFalse(envelope.requestsAutomaticSave)
        XCTAssertEqual(envelope.items.first?.source, .instagram)
        XCTAssertEqual(envelope.items.first?.sourceURLString, url.absoluteString)
        XCTAssertEqual(
            envelope.items.first?.contextText,
            "Lunch at @mendocinofarms in Los Angeles."
        )
    }

    func testCapturePersistsTheExplicitAutoSaveIntent() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)

        let envelope = try inbox.capture(
            [.text("Maru Coffee, Los Angeles", suggestedName: "Instagram")],
            saveIntent: SharedPlaceImportSaveIntent(mode: .checkIn, ratingScore: 7),
            deliveryID: "check-in-delivery"
        )

        XCTAssertEqual(envelope.version, 3)
        XCTAssertTrue(envelope.requestsAutomaticSave)
        XCTAssertEqual(envelope.saveIntent?.mode, .checkIn)
        XCTAssertEqual(envelope.saveIntent?.ratingScore, 5)
        XCTAssertEqual(try inbox.scan().entries.first?.envelope.saveIntent, envelope.saveIntent)
    }

    func testOlderEnvelopeVersionNeverRequestsAutomaticSave() {
        let envelope = SharedPlaceImportEnvelope(
            version: 2,
            deliveryID: "legacy-with-new-field",
            items: [],
            saveIntent: SharedPlaceImportSaveIntent(mode: .checkIn, ratingScore: 4)
        )

        XCTAssertFalse(envelope.requestsAutomaticSave)
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

    func testScanKeepsVersionOneSharesQueuedBeforeTheUpgrade() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        _ = try inbox.capture(
            [.text("Maru Coffee, Los Angeles", suggestedName: nil)],
            deliveryID: "version-one"
        )
        let envelopeURL = root
            .appendingPathComponent("Library/Application Support/rec-me-share-imports/inbox")
            .appendingPathComponent("version-one.json")
        let data = try Data(contentsOf: envelopeURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["version"] = 1
        object.removeValue(forKey: "saveIntent")
        if var items = object["items"] as? [[String: Any]] {
            for index in items.indices {
                items[index].removeValue(forKey: "sourceURLString")
                items[index].removeValue(forKey: "contextText")
            }
            object["items"] = items
        }
        try JSONSerialization.data(withJSONObject: object).write(to: envelopeURL)

        let scan = try inbox.scan()

        XCTAssertEqual(scan.entries.map(\.envelope.version), [1])
        XCTAssertEqual(scan.quarantinedCount, 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPlaceImportInboxTests-\(UUID().uuidString)", isDirectory: true)
    }
}

final class ShareExtensionItemLoaderTests: XCTestCase {
    func testLoaderKeepsTopLevelCaptionWithInstagramURLInsteadOfDroppingIt() throws {
        let url = try XCTUnwrap(URL(string: "https://www.instagram.com/reel/example/"))
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(
            string: "Lunch at @mendocinofarms in Los Angeles."
        )
        let provider = NSItemProvider(
            item: url as NSURL,
            typeIdentifier: UTType.url.identifier
        )
        item.attachments = [provider]
        let loaded = expectation(description: "loaded share payload")
        var result: Result<[SharedPlaceImportCaptureInput], Error>?

        ShareExtensionItemLoader.load(from: [item]) {
            result = $0
            loaded.fulfill()
        }

        wait(for: [loaded], timeout: 2)
        let inputs = try XCTUnwrap(result).get()
        XCTAssertEqual(
            inputs,
            [
                .sharedLink(
                    url,
                    contextText: "Lunch at @mendocinofarms in Los Angeles",
                    suggestedName: nil
                )
            ]
        )
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

    func testDrainKeepsCapturedSocialCaptionForScopedAppReview() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPlaceImportDrainerCaptionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        let store = PlaceImportStore(
            persistence: SharedImportTestPersistence(),
            resolver: SharedImportTestResolver()
        )
        let url = try XCTUnwrap(URL(string: "https://www.instagram.com/reel/example/"))
        _ = try inbox.capture(
            [
                .sharedLink(
                    url,
                    contextText: "Lunch at @mendocinofarms in Los Angeles.",
                    suggestedName: "Instagram"
                )
            ],
            deliveryID: "caption"
        )

        let report = SharedPlaceImportInboxDrainer.drain(inbox: inbox, into: store)

        XCTAssertEqual(report.importedBatchCount, 1)
        XCTAssertEqual(report.batchIDs, store.batches.map(\.id))
        XCTAssertNil(store.batches.first?.receipt)
        XCTAssertNil(store.items.first?.seed.nameHint)
        XCTAssertEqual(
            store.items.first?.seed.socialCaptionHint,
            "Lunch at @mendocinofarms in Los Angeles."
        )
    }

    func testDrainCarriesExtensionCheckInIntentIntoEveryBatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPlaceImportDrainerIntentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedPlaceImportInbox(rootURL: root)
        let store = PlaceImportStore(
            persistence: SharedImportTestPersistence(),
            resolver: SharedImportTestResolver()
        )
        _ = try inbox.capture(
            [
                .text("Maru Coffee, Los Angeles", suggestedName: "Notes"),
                .text("Gjusta, Venice", suggestedName: "Notes")
            ],
            saveIntent: SharedPlaceImportSaveIntent(mode: .checkIn, ratingScore: 4),
            deliveryID: "check-in"
        )

        _ = SharedPlaceImportInboxDrainer.drain(inbox: inbox, into: store)

        XCTAssertEqual(store.batches.count, 2)
        XCTAssertTrue(store.batches.allSatisfy(\.shouldSaveAutomatically))
        XCTAssertTrue(store.batches.allSatisfy { $0.requestedStatus == .been })
        XCTAssertTrue(store.batches.allSatisfy { $0.requestedRatingScore == 4 })
        XCTAssertTrue(store.items.allSatisfy { $0.stagedStatus == .been })
        XCTAssertTrue(store.items.allSatisfy { $0.stagedRatingScore == 4 })
    }

    func testDrainPolicyHoldsSharesUntilSessionValidationAndSignIn() {
        XCTAssertFalse(
            SharedPlaceImportDrainPolicy.canDrain(
                isSessionValidated: false,
                isSignedIn: true
            )
        )
        XCTAssertFalse(
            SharedPlaceImportDrainPolicy.canDrain(
                isSessionValidated: true,
                isSignedIn: false
            )
        )
        XCTAssertTrue(
            SharedPlaceImportDrainPolicy.canDrain(
                isSessionValidated: true,
                isSignedIn: true
            )
        )
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
        let shareController = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "WanderShareExtension/ShareViewController.swift"
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
        XCTAssertTrue(shareController.contains("Import places"))
        XCTAssertTrue(shareController.contains("Start import"))
        XCTAssertTrue(shareController.contains("linkField.text = sharedLinkString"))
        XCTAssertTrue(shareController.contains("try inbox.capture(captureInputs)"))
        XCTAssertFalse(shareController.contains(".open(appURL"))
        XCTAssertTrue(shareController.contains("completeRequest(returningItems: nil)"))
        XCTAssertTrue(shareController.contains("countdownDuration: TimeInterval = 5"))
        XCTAssertTrue(shareController.contains("countdownWorkItem?.cancel()"))
        XCTAssertTrue(shareController.contains("!UIAccessibility.isVoiceOverRunning"))
        XCTAssertTrue(shareController.contains("!UIAccessibility.isSwitchControlRunning"))
        XCTAssertTrue(shareController.contains("!isClosing, !isSubmitting, canStartImport"))
        XCTAssertTrue(shareController.contains("linkField.isUserInteractionEnabled = false"))
        XCTAssertTrue(shareController.contains("linkField.textColor = Palette.muted"))
        XCTAssertTrue(shareController.contains("cardHeight?.constant = height"))
        XCTAssertFalse(shareController.contains("[\"Wanna\", \"Check In\"]"))
        XCTAssertFalse(shareController.contains("saveIntent:"))
        XCTAssertFalse(shareController.contains("share-extension-captured"))
    }

    func testShareCountdownFillsLeftToRightWithTranslucentBlackBehindTheButton() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "WanderShareExtension/ShareViewController.swift"
            )
        )

        XCTAssertTrue(controller.contains("countdownFill.backgroundColor = UIColor.black.withAlphaComponent(0.22)"))
        XCTAssertTrue(controller.contains("countdownFill.leftAnchor.constraint(equalTo: startContainer.leftAnchor)"))
        XCTAssertTrue(controller.contains("countdownFill.topAnchor.constraint(equalTo: startContainer.topAnchor)"))
        XCTAssertTrue(controller.contains("countdownFill.bottomAnchor.constraint(equalTo: startContainer.bottomAnchor)"))
        XCTAssertTrue(controller.contains("startContainer.clipsToBounds = true"))
        XCTAssertTrue(controller.contains("countdownFill.isUserInteractionEnabled = false"))
        let fillInsertion = try XCTUnwrap(controller.range(of: "startContainer.addSubview(countdownFill)"))
        let buttonInsertion = try XCTUnwrap(controller.range(of: "startContainer.addSubview(startButton)"))
        XCTAssertLessThan(fillInsertion.lowerBound, buttonInsertion.lowerBound)
        XCTAssertTrue(controller.contains("fillWidth?.constant = 0"))
        XCTAssertTrue(controller.contains("fillWidth?.constant = startContainer.bounds.width"))
        XCTAssertTrue(controller.contains("countdownDuration: TimeInterval = 5"))
        XCTAssertTrue(controller.contains("UIView.animate(withDuration: Self.countdownDuration"))
        XCTAssertTrue(controller.contains("[.curveLinear, .beginFromCurrentState, .allowUserInteraction]"))
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
