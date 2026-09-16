import XCTest
@testable import Wander

@MainActor
final class CheckInQuestionPreferencesTests: XCTestCase {
    private let defaultsIDs = ["place_detail_outlets", "place_detail_noise", "place_detail_seating"]

    func testUntouchedQuestionsHaveNoAnswersAndPreferencesDoNotWriteOnRead() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)

        XCTAssertEqual(configuration(store).orderedQuestionIDs, defaultsIDs)
        XCTAssertTrue(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit").isEmpty)
        XCTAssertTrue((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty)
        try store.savePrivateAnswers([:], ownerUserID: "a", userPlaceID: "place", visitID: "visit")
        XCTAssertTrue((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty, "An unanswered visit should not create private-answer storage.")
        XCTAssertEqual(CheckInQuestionAnswerPolicy.toggling("No", selected: []), ["No"])
        XCTAssertEqual(CheckInQuestionAnswerPolicy.toggling("No", selected: ["No"]), [])
        XCTAssertNil(CheckInQuestionAnswerPolicy.togglingPrivate("yes", current: "yes"))
    }

    func testReorderRemoveAndAddSurviveReopeningWithoutReturningDefaults() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        value.moveQuestions(from: IndexSet(integer: 2), to: 0)
        value.removeQuestions(at: IndexSet(integer: 1))
        value.addCatalogQuestion(id: "place_detail_dogs")
        value.addCatalogQuestion(id: "place_detail_dogs")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")

        let reopened = CheckInQuestionPreferenceStore(defaults: defaults)
        XCTAssertEqual(configuration(reopened).orderedQuestionIDs, ["place_detail_seating", "place_detail_noise", "place_detail_dogs"])
        value.removeQuestions(at: IndexSet(integersIn: 0..<value.orderedQuestionIDs.count))
        try reopened.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        XCTAssertTrue(configuration(CheckInQuestionPreferenceStore(defaults: defaults)).orderedQuestionIDs.isEmpty)
    }

    func testMovingSeveralQuestionsUsesNativeListDestinationSemantics() {
        var value = CheckInQuestionConfiguration(orderedQuestionIDs: ["a", "b", "c", "d", "e"])
        value.moveQuestions(from: IndexSet([1, 3]), to: 5)
        XCTAssertEqual(value.orderedQuestionIDs, ["a", "c", "e", "b", "d"])
        value.moveQuestions(from: IndexSet([3, 4]), to: 0)
        XCTAssertEqual(value.orderedQuestionIDs, ["b", "d", "a", "c", "e"])
    }

    func testCustomQuestionsAndAnswersAreIsolatedByAccountAndVisit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Lots of plants indoors?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "a", userPlaceID: "place", visitID: "first")

        XCTAssertEqual(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "first"), [custom.id: "yes"])
        XCTAssertTrue(store.privateAnswers(ownerUserID: "b", userPlaceID: "place", visitID: "first").isEmpty)
        XCTAssertTrue(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "second").isEmpty)
        XCTAssertTrue(store.privateAnswers(ownerUserID: "a", userPlaceID: "other-place", visitID: "other-visit").isEmpty)
        XCTAssertTrue(store.allCustomQuestions(ownerUserID: "b").isEmpty)
        XCTAssertEqual(configuration(store, owner: "b").orderedQuestionIDs, defaultsIDs)
        XCTAssertThrowsError(try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "b", userPlaceID: "place", visitID: "first"))
    }

    func testRemovingAndReaddingCustomPromptPreservesIdentityAndPastAnswer() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let original = try value.addCustomQuestion(prompt: "  Lots of\nplants?  ")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([original.id: "no"], ownerUserID: "a", userPlaceID: "place", visitID: "visit")
        value.removeQuestions(at: IndexSet(integer: value.orderedQuestionIDs.count - 1))
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")

        var reopened = configuration(CheckInQuestionPreferenceStore(defaults: defaults))
        XCTAssertFalse(reopened.orderedQuestionIDs.contains(original.id))
        XCTAssertEqual(reopened.customQuestions, [original])
        XCTAssertEqual(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit"), [original.id: "no"])
        let restored = try reopened.addCustomQuestion(prompt: "lots of plants?")
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(reopened.customQuestions.count, 1)
        XCTAssertTrue(reopened.orderedQuestionIDs.contains(original.id))
    }

    func testSamePromptInAnotherSubtypeHasItsOwnIdentityAndOrder() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var cafe = configuration(store)
        let cafeQuestion = try cafe.addCustomQuestion(prompt: "Lots of plants?")
        try store.saveConfiguration(cafe, ownerUserID: "a", subtypeKey: "cafe")
        var hotel = configuration(store, subtype: "hotel")
        let hotelQuestion = try hotel.addCustomQuestion(prompt: "Lots of plants?")
        hotel.moveQuestions(from: IndexSet(integer: hotel.orderedQuestionIDs.count - 1), to: 0)
        try store.saveConfiguration(hotel, ownerUserID: "a", subtypeKey: "hotel")

        XCTAssertNotEqual(cafeQuestion.id, hotelQuestion.id)
        XCTAssertEqual(configuration(store).orderedQuestionIDs.last, cafeQuestion.id)
        XCTAssertEqual(configuration(store, subtype: "hotel").orderedQuestionIDs.first, hotelQuestion.id)
        XCTAssertEqual(store.allCustomQuestions(ownerUserID: "a").count, 2)
    }

    func testRestoreSuggestionsAndExplicitAnswerClearPreserveOtherVisits() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "a", userPlaceID: "place", visitID: "first")
        try store.savePrivateAnswers([custom.id: "no"], ownerUserID: "a", userPlaceID: "place", visitID: "second")
        value.restoreSuggestedQuestions(defaultsIDs)
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([:], ownerUserID: "a", userPlaceID: "place", visitID: "second")

        XCTAssertEqual(configuration(store).orderedQuestionIDs, defaultsIDs)
        XCTAssertEqual(configuration(store).customQuestions, [custom])
        XCTAssertEqual(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "first"), [custom.id: "yes"])
        XCTAssertTrue(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "second").isEmpty)
    }

    func testPrivateStoreRejectsSharedQuestionIDsInvalidValuesAndMissingVisitIdentity() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")

        XCTAssertThrowsError(try store.savePrivateAnswers(["place_detail_outlets": "yes"], ownerUserID: "a", userPlaceID: "place", visitID: "visit"))
        XCTAssertThrowsError(try store.savePrivateAnswers([custom.id: "unknown"], ownerUserID: "a", userPlaceID: "place", visitID: "visit"))
        XCTAssertThrowsError(try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "a", userPlaceID: "place", visitID: ""))
        XCTAssertThrowsError(try store.saveConfiguration(value, ownerUserID: "", subtypeKey: "cafe"))
        XCTAssertTrue(store.privateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit").isEmpty)
    }

    func testCustomPromptValidationAndNamespacedIdentity() throws {
        var value = CheckInQuestionConfiguration(orderedQuestionIDs: [])
        XCTAssertThrowsError(try value.addCustomQuestion(prompt: " \n "))
        XCTAssertThrowsError(try value.addCustomQuestion(prompt: String(repeating: "a", count: 121)))
        let custom = try value.addCustomQuestion(prompt: "Plants?")
        XCTAssertTrue(CheckInCustomQuestion.isCustomID(custom.id))
        XCTAssertFalse(CheckInCustomQuestion.isCustomID("place_detail_plants"))
        XCTAssertFalse(CheckInCustomQuestion.isCustomID("custom_question_plants"))
    }

    func testUnreadableStorageIsNotOverwrittenByCustomization() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        try store.saveConfiguration(configuration(store), ownerUserID: "a", subtypeKey: "cafe")
        let key = try XCTUnwrap(defaults.persistentDomain(forName: suite)?.keys.first)
        let corrupted = Data("invalid".utf8)
        defaults.set(corrupted, forKey: key)

        XCTAssertThrowsError(try store.saveConfiguration(configuration(store), ownerUserID: "a", subtypeKey: "cafe"))
        XCTAssertThrowsError(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit"))
        XCTAssertThrowsError(try store.validatePrivateAnswers([:], ownerUserID: "a"))
        XCTAssertThrowsError(try store.savePrivateAnswers([:], ownerUserID: "a", userPlaceID: "place", visitID: "visit"))
        XCTAssertEqual(defaults.data(forKey: key), corrupted)
    }

    func testPreflightValidatesOwnedQuestionsWithoutSavingAnAnswer() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        let before = defaults.persistentDomain(forName: suite) as NSDictionary?

        XCTAssertNoThrow(try store.validatePrivateAnswers([custom.id: "no"], ownerUserID: "a"))
        XCTAssertThrowsError(try store.validatePrivateAnswers([custom.id: "no"], ownerUserID: "b"))
        XCTAssertThrowsError(try store.validatePrivateAnswers([custom.id: "maybe"], ownerUserID: "a"))
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before)
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit").isEmpty)
    }

    func testRebuiltConfigurationCannotErasePastDefinitionsOrChangeQuestionMeaning() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "a", userPlaceID: "place", visitID: "visit")

        try store.saveConfiguration(CheckInQuestionConfiguration(orderedQuestionIDs: []), ownerUserID: "a", subtypeKey: "cafe")
        XCTAssertEqual(configuration(store).customQuestions, [custom])
        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit"), [custom.id: "yes"])

        let redefined = CheckInQuestionConfiguration(orderedQuestionIDs: [custom.id], customQuestions: [
            CheckInCustomQuestion(id: custom.id, prompt: "Different meaning?")
        ])
        XCTAssertThrowsError(try store.saveConfiguration(redefined, ownerUserID: "a", subtypeKey: "cafe"))
        XCTAssertThrowsError(try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "other"))
        XCTAssertEqual(configuration(store).customQuestions, [custom])
    }

    func testDeletingVisitPlaceAndAccountKeepsOtherOwnersAndHistoryIsolated() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let question = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.saveConfiguration(configuration(store, owner: "b"), ownerUserID: "b", subtypeKey: "cafe")
        for place in ["place", "place-more"] {
            for visit in ["first", "second"] {
                try store.savePrivateAnswers([question.id: "yes"], ownerUserID: "a", userPlaceID: place, visitID: "\(place)-\(visit)")
            }
        }

        try store.removeAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "place-first")
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "place-first").isEmpty)
        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "place-second"), [question.id: "yes"])
        try store.removeAnswers(ownerUserID: "a", userPlaceID: "place", visitID: nil)
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "place-second").isEmpty)
        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place-more", visitID: "place-more-first"), [question.id: "yes"])
        XCTAssertEqual(configuration(store).customQuestions, [question])

        try store.removeAccount(ownerUserID: "a")
        XCTAssertTrue(store.allCustomQuestions(ownerUserID: "a").isEmpty)
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place-more", visitID: "place-more-first").isEmpty)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.count, 1)
        XCTAssertEqual(configuration(store, owner: "b").orderedQuestionIDs, defaultsIDs)
    }

    func testStableVisitIdentitySurvivesParentRestorationAndDeletionByEitherAlias() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let question = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        let visitID = UUID().uuidString
        try store.savePrivateAnswers([question.id: "yes"], ownerUserID: "a", userPlaceID: "original-local", visitID: visitID)

        let initialConfiguration = configuration(store)
        let changes = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: CheckInQuestionPreferenceStore.didChangeNotification, object: nil, queue: nil
        ) { _ in changes.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let restored = CheckInQuestionPreferenceStore(defaults: defaults)
        XCTAssertEqual(try restored.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "restored-local", visitID: visitID), [question.id: "yes"])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(configuration(restored), initialConfiguration)
        let registered = defaults.persistentDomain(forName: suite) as NSDictionary?
        XCTAssertEqual(try restored.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "restored-local", visitID: visitID), [question.id: "yes"])
        XCTAssertTrue(try restored.loadPrivateAnswers(ownerUserID: "b", userPlaceID: "restored-local", visitID: visitID).isEmpty)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, registered)
        XCTAssertEqual(changes.count, 1, "Repeated or unanswered reads must not publish additional writes.")
        try restored.removeAnswers(ownerUserID: "a", userPlaceID: "restored-local", visitID: nil)
        XCTAssertTrue(try restored.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "original-local", visitID: visitID).isEmpty)

        try restored.savePrivateAnswers([question.id: "no"], ownerUserID: "a", userPlaceID: "original-local", visitID: visitID)
        try restored.savePrivateAnswers([question.id: "yes"], ownerUserID: "a", userPlaceID: "restored-local", visitID: visitID)
        XCTAssertEqual(try restored.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "original-local", visitID: visitID), [question.id: "yes"])
        try restored.removeAnswers(ownerUserID: "a", userPlaceID: "original-local", visitID: nil)
        XCTAssertTrue(try restored.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "restored-local", visitID: visitID).isEmpty)
    }

    func testLegacyVisitMigrationPreservesDestinationAnswersAndBothParentAliases() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let first = try value.addCustomQuestion(prompt: "Plants?")
        let second = try value.addCustomQuestion(prompt: "Books?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([first.id: "yes", second.id: "no"], ownerUserID: "a", userPlaceID: "old-parent", visitID: "local-visit")
        try store.savePrivateAnswers([first.id: "no"], ownerUserID: "a", userPlaceID: "new-parent", visitID: "server-visit")

        try store.migrateAnswers(ownerUserID: "a", fromVisitID: "local-visit", toVisitID: "server-visit")

        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "new-parent", visitID: "server-visit"), [first.id: "no", second.id: "no"])
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "old-parent", visitID: "local-visit").isEmpty)
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "b", userPlaceID: "new-parent", visitID: "server-visit").isEmpty)
        XCTAssertEqual(configuration(store), value)
        try store.removeAnswers(ownerUserID: "a", userPlaceID: "old-parent", visitID: nil)
        XCTAssertTrue(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "new-parent", visitID: "server-visit").isEmpty)
    }

    func testFailedMigrationNeverRewritesOrDeletesOriginalStorage() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let question = try value.addCustomQuestion(prompt: "Plants?")
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([question.id: "yes"], ownerUserID: "a", userPlaceID: "parent", visitID: "local-visit")
        let key = try XCTUnwrap(defaults.persistentDomain(forName: suite)?.keys.first)
        let intact = try XCTUnwrap(defaults.data(forKey: key))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: intact) as? [String: Any])
        var records = try XCTUnwrap(json["answers"] as? [String: Any])
        records["server-visit"] = ["userPlaceIDs": ["parent"], "answers": [question.id: "invalid"]]
        json["answers"] = records
        let invalidDestination = try JSONSerialization.data(withJSONObject: json)
        defaults.set(invalidDestination, forKey: key)

        XCTAssertThrowsError(try store.migrateAnswers(ownerUserID: "a", fromVisitID: "local-visit", toVisitID: "server-visit"))
        XCTAssertEqual(defaults.data(forKey: key), invalidDestination)
        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "parent", visitID: "local-visit"), [question.id: "yes"])
    }

    func testLegacyConfigurationKeepsCustomQuestionsPrivate() throws {
        let customID = "custom_question_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let json = """
        {"orderedQuestionIDs":["place_detail_outlets","\(customID)"],"customQuestions":[{"id":"\(customID)","prompt":"Plants?"}]}
        """
        var value = try JSONDecoder().decode(CheckInQuestionConfiguration.self, from: Data(json.utf8))
        XCTAssertTrue(value.isStealth(questionID: customID))
        XCTAssertFalse(value.isStealth(questionID: "place_detail_outlets"))
        value.setStealth(false, questionID: customID)
        value.setStealth(true, questionID: "place_detail_outlets")
        let roundTrip = try JSONDecoder().decode(CheckInQuestionConfiguration.self, from: JSONEncoder().encode(value))
        XCTAssertFalse(roundTrip.isStealth(questionID: customID))
        XCTAssertTrue(roundTrip.isStealth(questionID: "place_detail_outlets"))
    }

    func testChangingStealthDefaultsDoesNotPublishOrRemoveHistoricalPrivateAnswers() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        var value = configuration(store)
        let custom = try value.addCustomQuestion(prompt: "Plants?", stealth: true)
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        try store.savePrivateAnswers([custom.id: "yes", "place_detail_outlets": "Plenty"], ownerUserID: "a", userPlaceID: "place", visitID: "visit")
        value.setStealth(false, questionID: custom.id)
        value.setStealth(false, questionID: "place_detail_outlets")
        value.restoreSuggestedQuestions(defaultsIDs)
        try store.saveConfiguration(value, ownerUserID: "a", subtypeKey: "cafe")
        XCTAssertEqual(try store.loadPrivateAnswers(ownerUserID: "a", userPlaceID: "place", visitID: "visit"), [custom.id: "yes", "place_detail_outlets": "Plenty"])
        XCTAssertThrowsError(try store.savePrivateAnswers(["place_detail_outlets": "Invented answer"], ownerUserID: "a", userPlaceID: "place", visitID: "visit"))
        XCTAssertThrowsError(try store.savePrivateAnswers([custom.id: "yes"], ownerUserID: "b", userPlaceID: "place", visitID: "visit"))
    }

    func testRecoveringOwnedSharedDefinitionPreservesRecurringListAndAllowsPrivateEdit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckInQuestionPreferenceStore(defaults: defaults)
        let question = CheckInCustomQuestion(id: "custom_question_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", prompt: "Plants?")
        try store.retainRecoveredDefinitions([question], ownerUserID: "a", subtypeKey: "cafe", defaultQuestionIDs: defaultsIDs)
        XCTAssertEqual(configuration(store).orderedQuestionIDs, defaultsIDs)
        XCTAssertEqual(store.allCustomQuestions(ownerUserID: "a"), [question])
        XCTAssertTrue(store.allCustomQuestions(ownerUserID: "b").isEmpty)
        try store.savePrivateAnswers([question.id: "no"], ownerUserID: "a", userPlaceID: "place", visitID: "visit")
        XCTAssertEqual(store.configuredSubtypeKeys(ownerUserID: "a"), ["cafe"])
        try store.retainRecoveredDefinitions([question], ownerUserID: "a", subtypeKey: "park", defaultQuestionIDs: [])
        XCTAssertEqual(store.configuredSubtypeKeys(ownerUserID: "a"), ["cafe"])
    }

    private final class NotificationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func configuration(
        _ store: CheckInQuestionPreferenceStore,
        owner: String = "a",
        subtype: String = "cafe"
    ) -> CheckInQuestionConfiguration {
        store.configuration(ownerUserID: owner, subtypeKey: subtype, defaultQuestionIDs: defaultsIDs)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "CheckInQuestionPreferencesTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
}
