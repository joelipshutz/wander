import Foundation
import XCTest
@testable import AstirEventsShared

final class EventContractTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tests/fixtures/events/event-contracts.json")
    }
    private func fixtures() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [[String: Any]])
    }
    private func fixture(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(fixtures().first { $0["name"] as? String == name }?["response"] as? [String: Any])
    }
    private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func response(_ name: String) throws -> EventReadResponse { try EventReadResponse.decode(data(fixture(name))) }
    private func view(_ name: String) throws -> EventView {
        guard case .available(let view) = try response(name).payload else { throw EventContractError.invalid("test fixture") }
        return view
    }
    private func context(account: String? = "acct_fixture_rachel", epoch: UUID = UUID()) throws -> EventRequestContext {
        try EventRequestContext(eventId: EventID("evt_fixture_vinyl"), accountId: account.map { try EventAccountID($0) }, sessionEpoch: epoch)
    }

    func testSharedWireFixturesAndRoundTrips() throws {
        let all = try fixtures()
        XCTAssertEqual(all.count, 61, "Keep the native/browser fixture baseline explicit")
        for f in all {
            let name = try XCTUnwrap(f["name"] as? String)
            let raw = try data(XCTUnwrap(f["response"]))
            if f["valid"] as? Bool == true {
                do {
                    let decoded = try EventReadResponse.decode(raw)
                    XCTAssertEqual(try EventReadResponse.decode(EventWire.encoder().encode(decoded)), decoded, name)
                } catch { XCTFail("\(name): \(error)") }
            } else {
                XCTAssertThrowsError(try EventReadResponse.decode(raw), name)
            }
        }
    }

    func testMissingNameDoesNotRepeatCurrentPhoneVerification() throws {
        guard case .resolved(let viewer) = try view("missing_name_verified_phone").viewer else { return XCTFail() }
        XCTAssertEqual(viewer.profile.missingRSVPFields, [.name])
        XCTAssertEqual(viewer.profile.missingEntryFields, [.name])
        guard case .resolved(let missingPhone) = try view("phone_proof_needed").viewer else { return XCTFail() }
        XCTAssertEqual(missingPhone.profile.missingRSVPFields, [.phoneVerification])
    }

    func testConfirmedGuestCanManageWithoutInstallation() throws {
        let rights = try view("confirmed").capabilities
        XCTAssertTrue(rights.contains(.viewGuestList))
        XCTAssertTrue(rights.contains(.manageRSVP))
        // These capabilities have no surface/installation condition.
        for surface in [EventSurface.clip, .browser] {
            XCTAssertEqual(EventRouting.nativeAction(surface: surface, installation: .installed), .openApp)
            XCTAssertEqual(EventRouting.nativeAction(surface: surface, installation: .unknown), .offerOpenOrInstall)
            XCTAssertEqual(EventRouting.nativeAction(surface: surface, installation: .absent), .offerInstall)
        }
        XCTAssertEqual(EventRouting.nativeAction(surface: .app, installation: .unknown), .showNative)
    }

    func testAccountEventAndSessionFencesRejectStaleResponses() throws {
        let captured = try context()
        XCTAssertNoThrow(try captured.accept(response("confirmed"), current: captured))
        XCTAssertThrowsError(try captured.accept(response("different_account"), current: captured))
        XCTAssertThrowsError(try captured.accept(response("confirmed"), current: context()))
        XCTAssertThrowsError(try captured.accept(response("confirmed"), current: context(account: nil, epoch: captured.sessionEpoch)))
        let anonymous = try context(account: nil)
        XCTAssertThrowsError(try anonymous.accept(response("confirmed"), current: anonymous))
        var wrongEvent = try fixture("authenticated_none")
        wrongEvent["event_id"] = "evt_other"
        var payload = wrongEvent["payload"] as! [String: Any]
        var view = payload["view"] as! [String: Any]
        var event = view["event"] as! [String: Any]
        event["event_id"] = "evt_other"; view["event"] = event; payload["view"] = view; wrongEvent["payload"] = payload
        XCTAssertThrowsError(try captured.accept(EventReadResponse.decode(data(wrongEvent)), current: captured))
    }

    func testDeletedPostRetainsCompletionButRevokedAdmissionLocksRecap() throws {
        let deleted = try view("completed_post_deleted")
        guard case .resolved(let viewer) = deleted.viewer else { return XCTFail() }
        XCTAssertEqual(viewer.completion, .completed)
        XCTAssertEqual(viewer.personalPost, .deleted)
        XCTAssertTrue(deleted.capabilities.contains(.viewRecap))
        XCTAssertFalse(deleted.capabilities.contains(.completeCheckin))
        let revoked = try view("completed_admission_revoked")
        XCTAssertEqual(revoked.recap, .publishedLocked)
        XCTAssertFalse(revoked.capabilities.contains(.viewRecap))
    }

    func testWireTimestampRetainsMicrosecondBoundary() throws {
        let at = try EventInstant("2026-09-20T18:00:00.123456Z")
        let after = try EventInstant("2026-09-20T18:00:00.123457Z")
        XCTAssertEqual(after.epochMicroseconds - at.epochMicroseconds, 1)
        XCTAssertEqual(at.rawValue, "2026-09-20T18:00:00.123456Z")
    }

    func testUnknownFieldsCannotBecomeGuestProjectionFields() throws {
        var raw = try fixture("approximate_home")
        var payload = raw["payload"] as! [String: Any]
        var view = payload["view"] as! [String: Any]
        view["private_feedback"] = "MUST_NOT_SURVIVE"
        var location = view["location"] as! [String: Any]
        var value = location["value"] as! [String: Any]
        value["exact_address"] = "MUST_NOT_SURVIVE"
        location["value"] = value; view["location"] = location; payload["view"] = view; raw["payload"] = payload
        let decoded = try EventReadResponse.decode(data(raw))
        XCTAssertFalse(String(decoding: try EventWire.encoder().encode(decoded), as: UTF8.self).contains("MUST_NOT_SURVIVE"))
        var denied = try fixture("event_access_denied")
        var deniedPayload = denied["payload"] as! [String: Any]
        deniedPayload["view"] = view; denied["payload"] = deniedPayload
        let safe = try EventReadResponse.decode(data(denied))
        XCTAssertFalse(String(decoding: try EventWire.encoder().encode(safe), as: UTF8.self).contains("Vinyl"))
    }

    func testReplayReturnsCurrentCancellationAndNeverBecomesNewAttempt() throws {
        let captured = try context()
        let command = try EventCommand(operationId: EventOperationID("op_fixture_1"), kind: .submitRSVP,
                                       eventId: captured.eventId, targetGenerationId: EventGenerationID("generation_fixture_1"),
                                       expectedRevision: nil, payload: ["code": "fixture-only"])
        let raw: [String: Any] = ["contract_version": 1, "operation_id": "op_fixture_1", "kind": "submit_rsvp",
            "outcome": "already_applied", "effect": ["booking_id": "booking_fixture_rachel"],
            "current_state": try fixture("canceled"), "error": NSNull()]
        let result = try EventWire.decoder().decode(EventCommandResult<[String: String]>.self, from: data(raw))
        XCTAssertNoThrow(try result.validate(for: command, captured: captured, current: captured))
        guard case .available(let view) = result.currentState.payload, case .resolved(let viewer) = view.viewer else { return XCTFail() }
        XCTAssertEqual(viewer.booking?.status, .canceled)
        XCTAssertTrue(view.capabilities.contains(.submitRSVP), "A deliberate new generation is allowed; old retry is not one")
        let other = try EventCommand(operationId: EventOperationID("op_fixture_new_attempt"), kind: .submitRSVP,
                                     eventId: captured.eventId, targetGenerationId: EventGenerationID("generation_fixture_2"),
                                     expectedRevision: nil, payload: ["code": "fixture-only"])
        XCTAssertThrowsError(try result.validate(for: other, captured: captured, current: captured))
        var invalid = raw; invalid["outcome"] = "rejected"
        let rejected = try EventWire.decoder().decode(EventCommandResult<[String: String]>.self, from: data(invalid))
        XCTAssertThrowsError(try rejected.validate(for: command, captured: captured, current: captured))
    }

    func testPageCursorCannotPretendToBeCompleteOrUnbounded() throws {
        let valid: [String: Any] = ["items": ["guest1"], "next_cursor": "opaque:scope:tie-breaker", "has_more": true, "permission_version": "v1"]
        let page = try EventWire.decoder().decode(EventPage<String>.self, from: data(valid))
        XCTAssertNoThrow(try page.validate(limit: 10))
        XCTAssertThrowsError(try page.validate(limit: 101))
        var bad = valid; bad["has_more"] = false
        let invalid = try EventWire.decoder().decode(EventPage<String>.self, from: data(bad))
        XCTAssertThrowsError(try invalid.validate(limit: 10))
    }

    func testSharedMalformedPageFixtures() throws {
        let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("event-pages.json")
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for f in all {
            let raw = try data(XCTUnwrap(f["page"]))
            let limit = try XCTUnwrap(f["limit"] as? Int)
            let name = try XCTUnwrap(f["name"] as? String)
            let validate = { try EventWire.decoder().decode(EventPage<String>.self, from: raw).validate(limit: limit) }
            if f["valid"] as? Bool == true { XCTAssertNoThrow(try validate(), name) }
            else { XCTAssertThrowsError(try validate(), name) }
        }
    }

    func testOperationalStatesNeverImplyCanonicalAdmissionOrDelivery() throws {
        let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("event-operations.json")
        let f = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let decoder = EventWire.decoder()
        let access = try decoder.decode([EventConsoleAccess].self, from: data(XCTUnwrap(f["console_access"])))
        XCTAssertEqual(access, [.teamAdmin, .denied, .revoked])
        let statuses = try decoder.decode([EventDeliveryStatus].self, from: data(XCTUnwrap(f["delivery_statuses"])))
        XCTAssertNotEqual(statuses[2], .deliveryConfirmed)
        let local = try XCTUnwrap(f["offline_operation"] as? [String: Any])
        let offline = try decoder.decode(EventOfflineAdmission.self, from: data(local))
        XCTAssertEqual(offline.localStatus, .durablePending)
        XCTAssertNoThrow(try offline.validate(in: context()))
        XCTAssertThrowsError(try offline.validate(in: context(account: "acct_other")))
        for status in try XCTUnwrap(f["offline_statuses"] as? [String]) {
            var copy = local; copy["local_status"] = status
            XCTAssertNoThrow(try decoder.decode(EventOfflineAdmission.self, from: data(copy)).validate(in: context()))
        }
        var invalid = local; invalid["roster_version"] = 0
        XCTAssertThrowsError(try decoder.decode(EventOfflineAdmission.self, from: data(invalid)).validate(in: context()))
        XCTAssertNoThrow(try decoder.decode(EventBookingEffect.self, from: data(XCTUnwrap(f["booking_effect"]))))
        XCTAssertNoThrow(try decoder.decode(EventAdmissionEffect.self, from: data(XCTUnwrap(f["admission_effect"]))))
        XCTAssertNoThrow(try decoder.decode(EventCompletionEffect.self, from: data(XCTUnwrap(f["completion_effect"]))))
        let analytics = try decoder.decode(EventAnalyticsDimensions.self, from: data(XCTUnwrap(f["analytics"])))
        let serialized = String(decoding: try EventWire.encoder().encode(analytics), as: UTF8.self)
        XCTAssertFalse(serialized.contains("MUST_NOT_SURVIVE"))
    }

    func testSharedCommandResultsRoundTripExplicitNullFields() throws {
        let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("event-commands.json")
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let decoder = EventWire.decoder()
        let encoder = EventWire.encoder()
        let scope = try context()
        for f in all {
            let name = try XCTUnwrap(f["name"] as? String)
            var raw = try XCTUnwrap(f["result"] as? [String: Any])
            raw["current_state"] = try fixture(XCTUnwrap(f["current_state_fixture"] as? String))
            let validate = {
                let command = try decoder.decode(EventCommand<[String: String]>.self, from: self.data(XCTUnwrap(f["request"])))
                let result = try decoder.decode(EventCommandResult<[String: String]>.self, from: self.data(raw))
                try result.validate(for: command, captured: scope, current: scope)
                let commandData = try encoder.encode(command)
                let resultData = try encoder.encode(result)
                let redecodedCommand = try decoder.decode(EventCommand<[String: String]>.self, from: commandData)
                let redecodedResult = try decoder.decode(EventCommandResult<[String: String]>.self, from: resultData)
                try redecodedResult.validate(for: redecodedCommand, captured: scope, current: scope)
                let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: commandData) as? [String: Any])
                let resultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
                XCTAssertNotNil(requestJSON["target_generation_id"], name)
                XCTAssertNotNil(requestJSON["expected_revision"], name)
                XCTAssertNotNil(resultJSON["effect"], name)
                XCTAssertNotNil(resultJSON["error"], name)
            }
            if f["valid"] as? Bool == true { XCTAssertNoThrow(try validate(), name) }
            else { XCTAssertThrowsError(try validate(), name) }
        }
    }
}
