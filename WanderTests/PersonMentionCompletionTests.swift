import XCTest
@testable import Wander

@MainActor
final class PersonMentionCompletionTests: XCTestCase {
    private func person(_ id: String = "caitlin", name: String = "Caitlin Cortez", handle: String = "cait123") -> ProfileShell {
        ProfileShell(id: id, handle: handle, displayName: name, avatarURL: nil, bio: nil, relationship: .mutual)
    }

    private func request(for draft: PersonMentionDraft) throws -> PersonMentionCompletionRequest {
        try XCTUnwrap(PersonMentionCompletionRequest(
            draft: draft, selection: NSRange(location: draft.text.utf16.count, length: 0)
        ))
    }

    func testRemoteOnlyCompletionSurvivesContinuedTypingAndPickerQueryChanges() async throws {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        var draft = PersonMentionDraft(text: "With @cait123 ")
        let pendingRequest = try request(for: draft)
        var caret = NSRange(location: draft.text.utf16.count, length: 0)
        var remoteQueries: [String] = []
        var completion: CheckedContinuation<[ProfileShell], Never>?
        let started = expectation(description: "Space lookup is waiting for the remote account")
        let task = model.complete(request: pendingRequest, local: [], remote: { query in
            remoteQueries.append(query)
            return await withCheckedContinuation {
                completion = $0
                started.fulfill()
            }
        }, eligible: { _ in true }) { request, profile in
            guard let profile else { return XCTFail("The remote account should complete the typed handle") }
            guard let updatedCaret = draft.complete(request, person: profile, at: caret) else {
                return XCTFail("Typing after Space must not invalidate the mention")
            }
            caret = updatedCaret
        }
        await fulfillment(of: [started], timeout: 5)
        draft.reconcile(draft.text + "tomorrow")
        caret = NSRange(location: draft.text.utf16.count, length: 0)
        await model.search(query: "cait123 tomorrow", ownerID: "viewer", local: { [] },
                           recommendations: { [] }, remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        await model.search(query: nil, ownerID: "viewer", local: { [] },
                           recommendations: { [] }, remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        XCTAssertTrue(draft.mentions.isEmpty)
        XCTAssertTrue(model.profiles.isEmpty)
        try XCTUnwrap(completion).resume(returning: [caitlin])
        await task.value

        XCTAssertEqual(remoteQueries, ["cait123"])
        XCTAssertEqual(draft.text, "With @Caitlin Cortez tomorrow")
        XCTAssertEqual(draft.mentions.map(\.userID), [caitlin.id])
        XCTAssertEqual(draft.searchText, "With @cait123 tomorrow")
        XCTAssertEqual(caret.location, draft.text.utf16.count)
        XCTAssertTrue(model.profiles.isEmpty, "Finishing a tag must not reopen the dismissed picker")
    }

    func testRemoteDuplicateFullNamePreventsCompletingTheLocalAccount() async throws {
        let model = PersonTypeaheadModel()
        let local = person()
        let duplicate = person("other-caitlin", handle: "othercaitlin")
        let draft = PersonMentionDraft(text: "@Caitlin Cortez ")
        var callbacks = 0
        var result: ProfileShell?
        var completion: CheckedContinuation<[ProfileShell], Never>?
        let started = expectation(description: "Name lookup checks for remote duplicates")
        let task = model.complete(request: try request(for: draft), local: [local], remote: { _ in
            await withCheckedContinuation {
                completion = $0
                started.fulfill()
            }
        }, eligible: { _ in true }) { _, profile in
            callbacks += 1
            result = profile
        }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(callbacks, 0, "A local match cannot establish uniqueness before the remote result")
        try XCTUnwrap(completion).resume(returning: [local, duplicate])
        await task.value

        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(result, "Distinct accounts with the same full name require an explicit picker selection")
    }

    func testFailedLookupDoesNotGuessFromTheLocalExactName() async throws {
        let model = PersonTypeaheadModel()
        let draft = PersonMentionDraft(text: "@Caitlin Cortez ")
        var callbacks = 0
        var result: ProfileShell?
        let task = model.complete(request: try request(for: draft), local: [person()],
                                  remote: { _ in throw URLError(.notConnectedToInternet) },
                                  eligible: { _ in true }) { _, profile in
            callbacks += 1
            result = profile
        }
        await task.value

        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(result, "An outage cannot prove that the local full name is unique")
    }

    func testCancellationRejectsLateRemoteCompletionEvenWhenTheLookupIgnoresCancellation() async throws {
        let model = PersonTypeaheadModel()
        let draft = PersonMentionDraft(text: "@cait123 ")
        var callbacks = 0
        var completion: CheckedContinuation<[ProfileShell], Never>?
        let started = expectation(description: "Lookup is in flight before the field disappears")
        let task = model.complete(request: try request(for: draft), local: [], remote: { _ in
            await withCheckedContinuation {
                completion = $0
                started.fulfill()
            }
        }, eligible: { _ in true }) { _, _ in callbacks += 1 }
        await fulfillment(of: [started], timeout: 5)
        model.cancelCompletions()
        try XCTUnwrap(completion).resume(returning: [person()])
        await task.value

        XCTAssertEqual(callbacks, 0)
        XCTAssertTrue(task.isCancelled)
    }

    func testCompletionRechecksEligibilityAfterTheRemoteResponse() async throws {
        let model = PersonTypeaheadModel()
        let draft = PersonMentionDraft(text: "@cait123 ")
        var isEligible = true
        var callbacks = 0
        var result: ProfileShell?
        var completion: CheckedContinuation<[ProfileShell], Never>?
        let started = expectation(description: "Lookup starts before the account is blocked")
        let task = model.complete(request: try request(for: draft), local: [person()], remote: { _ in
            await withCheckedContinuation {
                completion = $0
                started.fulfill()
            }
        }, eligible: { _ in isEligible }) { _, profile in
            callbacks += 1
            result = profile
        }
        await fulfillment(of: [started], timeout: 5)
        isEligible = false
        try XCTUnwrap(completion).resume(returning: [person()])
        await task.value

        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(result)
    }

    func testTwoPendingMentionsBothCompleteWhenTheEarlierNameReturnsFirst() async throws {
        try await verifyTwoPendingMentions(responseOrder: ["cait123", "camilo"])
    }

    func testTwoPendingMentionsBothCompleteWhenTheLaterNameReturnsFirst() async throws {
        try await verifyTwoPendingMentions(responseOrder: ["camilo", "cait123"])
    }

    private func verifyTwoPendingMentions(responseOrder: [String]) async throws {
        let model = PersonTypeaheadModel()
        let people = ["cait123": person(), "camilo": person("camilo", name: "Camilo Flores", handle: "camilo")]
        var draft = PersonMentionDraft(text: "🍜 @cait123 ")
        let firstRequest = try request(for: draft)
        draft.reconcile(draft.text + "and @camilo ")
        let secondRequest = try request(for: draft)
        draft.reconcile(draft.text + "tomorrow")
        var caret = NSRange(location: draft.text.utf16.count, length: 0)
        var completions: [String: CheckedContinuation<[ProfileShell], Never>] = [:]
        var tasks: [String: Task<Void, Never>] = [:]
        var applied: [String] = []
        let started = expectation(description: "Both mention lookups are pending")
        started.expectedFulfillmentCount = 2

        for pendingRequest in [firstRequest, secondRequest] {
            tasks[pendingRequest.query.text] = model.complete(request: pendingRequest, local: [], remote: { query in
                await withCheckedContinuation {
                    completions[query] = $0
                    started.fulfill()
                }
            }, eligible: { _ in true }) { request, profile in
                guard let profile else { return XCTFail("Each unique handle should resolve") }
                guard let updatedCaret = draft.complete(request, person: profile, at: caret) else {
                    return XCTFail("The other accepted mention must not invalidate this request")
                }
                caret = updatedCaret
                applied.append(profile.handle)
                model.rebaseCompletions(replacing: request.query.range, with: "@\(PersonMentionCandidates.name(for: profile))")
            }
        }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(draft.mentions.isEmpty)
        for handle in responseOrder {
            try XCTUnwrap(completions[handle]).resume(returning: [try XCTUnwrap(people[handle])])
            await tasks[handle]?.value
        }

        XCTAssertEqual(applied, responseOrder)
        XCTAssertEqual(draft.text, "🍜 @Caitlin Cortez and @Camilo Flores tomorrow")
        XCTAssertEqual(draft.searchText, "🍜 @cait123 and @camilo tomorrow")
        XCTAssertEqual(draft.mentions.map(\.userID), ["caitlin", "camilo"])
        XCTAssertTrue(draft.mentions.allSatisfy { $0.isValid(in: draft.text) })
        XCTAssertEqual(caret, NSRange(location: draft.text.utf16.count, length: 0))
    }
}
