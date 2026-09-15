import Foundation
import XCTest
@testable import Wander

final class PlaceCheckInQuestionCatalogTests: XCTestCase {
    func testEverySelectableSubtypeHasExactlyThreeExplicitQuestions() throws {
        var subtypeCount = 0
        var sharedSets: [String: [String]] = [:]
        for category in WanderPlaceCategory.taxonomy where category.isEditable {
            let suggestions = WanderPlaceCategory.subcategorySuggestions(for: category.id)
            let grouped = WanderPlaceCategory.subcategoryGroups(for: category.id).flatMap(\.subcategories)
            XCTAssertEqual(Set(grouped), Set(suggestions), category.id)
            for subtype in suggestions {
                subtypeCount += 1
                let questions = try XCTUnwrap(
                    PlaceCheckInQuestionCatalog.curatedQuestions(categoryID: category.id, subcategory: subtype),
                    "Missing explicit curation: \(category.id) / \(subtype)"
                )
                XCTAssertEqual(questions.count, 3, subtype)
                XCTAssertEqual(Set(questions.map(\.id)).count, 3, subtype)
                XCTAssertEqual(Set(questions.map(\.prompt)).count, 3, "Repeated prompt: \(subtype)")
                let bundle = category.id + ":" + questions.map(\.id).sorted().joined(separator: ",")
                sharedSets[bundle, default: []].append(subtype)
            }
            let categoryDefault = try XCTUnwrap(
                PlaceCheckInQuestionCatalog.curatedQuestions(categoryID: category.id, subcategory: nil),
                "Missing category default: \(category.id)"
            )
            XCTAssertEqual(categoryDefault.count, 3, category.id)
        }
        // Report the actual picker, not a hand-maintained expected count. Adding
        // a taxonomy subtype must fail curation above until it has its own row.
        print("Check-in catalog audit: \(subtypeCount) selectable subtypes; \(PlaceCheckInQuestionCatalog.allQuestions.count) questions")
        for (bundle, subtypes) in sharedSets.sorted(by: { $0.key < $1.key }) where subtypes.count > 1 {
            print("Shared practical needs: \(subtypes.sorted().joined(separator: ", ")) [\(bundle)]")
        }
    }

    func testProfilesHaveNoDuplicateScopesOrDanglingReferences() {
        var scopes = Set<String>()
        for profile in PlaceCheckInQuestionCatalog.profiles {
            XCTAssertFalse(profile.subcategories.isEmpty)
            XCTAssertEqual(profile.questionIDs.count, 3, profile.categoryID)
            XCTAssertEqual(Set(profile.questionIDs).count, 3)
            for id in profile.questionIDs {
                XCTAssertNotNil(PlaceCheckInQuestionCatalog.question(id: "place_detail_" + id), id)
            }
            for subtype in profile.subcategories {
                let scope = PlaceCheckInQuestionCatalog.preferenceKey(categoryID: profile.categoryID, subcategory: subtype)
                XCTAssertTrue(scopes.insert(scope).inserted, "Duplicate normalized profile: \(scope)")
            }
        }
        for (category, ids) in PlaceCheckInQuestionCatalog.defaultQuestionIDs {
            XCTAssertEqual(ids.count, 3, category)
            for id in ids {
                XCTAssertNotNil(PlaceCheckInQuestionCatalog.question(id: "place_detail_" + id), "\(category): \(id)")
            }
        }
    }

    func testQuestionKeysOptionsAndExistingWireContractAreValid() {
        let questions = PlaceCheckInQuestionCatalog.allQuestions
        XCTAssertEqual(Set(questions.map(\.id)).count, questions.count)
        for question in questions {
            XCTAssertTrue(question.id.hasPrefix("place_detail_"), question.id)
            XCTAssertNotNil(question.id.range(of: #"^place_detail_[a-z0-9_]+$"#, options: .regularExpression))
            XCTAssertEqual(question.valueType, "single_choice")
            XCTAssertFalse(question.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(question.options.count, 2, question.id)
            XCTAssertLessThanOrEqual(question.options.count, 5, question.id)
            XCTAssertEqual(question.options.count, Set(question.options).count, question.id)
            XCTAssertTrue(question.options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            XCTAssertEqual(question.searchTerms(for: ""), [], question.id)
            XCTAssertEqual(question.searchTerms(for: "invented answer"), [], question.id)
            for option in question.options {
                XCTAssertTrue(question.searchTerms(for: option).allSatisfy {
                    !["yes", "no", "unknown", "not sure"].contains($0.lowercased())
                }, question.id)
            }
        }
        XCTAssertTrue(PlaceCheckInQuestionCatalog.isDetailQuestion("place_detail_future_unknown"))
        XCTAssertNil(PlaceCheckInQuestionCatalog.question(id: "place_detail_future_unknown"))
        XCTAssertFalse(PlaceCheckInQuestionCatalog.isDetailQuestion("custom_labels"))
    }

    func testOutdoorQuestionsDescribeTheActualActivity() {
        let park = ids("outdoors_nature", "Park")
        XCTAssertEqual(park, ["shade", "restroom", "path_surface"])
        for type in ["Park", "City park", "State park", "National park", "Dog park", "Playground"] {
            XCTAssertFalse(ids("outdoors_nature", type).contains("beach_rinse"), type)
        }
        XCTAssertEqual(ids("outdoors_nature", "Beach"), ["beach_rinse", "shade", "beach_access"])
        XCTAssertEqual(ids("outdoors_nature", "Trail"), ["trail_marking", "incline", "path_surface"])
        XCTAssertEqual(ids("outdoors_nature", "Trail"), ids("outdoors_nature", "Hike"))
        XCTAssertEqual(ids("outdoors_nature", "Dog park"), ["fenced", "leash", "water_refill"])
        XCTAssertEqual(ids("outdoors_nature", "Playground"), ["playground_age", "fenced", "shade"])
        XCTAssertEqual(ids("outdoors_nature", "RV park"), ["camp_power", "camp_toilet", "camp_booking"])
        XCTAssertEqual(ids("outdoors_nature", "Fishing charter"), ["fishing_gear", "booking", "restroom"])
    }

    func testFitnessSubtypesAreNotCollapsedToGymQuestions() {
        XCTAssertEqual(ids("wellness_fitness", "Pilates studio"), ["pilates_format", "pilates_intro", "class_size"])
        XCTAssertEqual(ids("wellness_fitness", "CrossFit gym"), ["crossfit_scaling", "crossfit_format", "fitness_dropin"])
        XCTAssertEqual(ids("wellness_fitness", "Functional fitness studio"), ["functional_format", "coaching", "class_size"])
        XCTAssertEqual(ids("wellness_fitness", "Volleyball court"), ["volleyball_surface", "volleyball_net", "court_booking"])
        XCTAssertEqual(ids("wellness_fitness", "Gym"), ids("wellness_fitness", "Fitness center"))
        let types = ["Gym", "Yoga studio", "Pilates studio", "CrossFit gym", "Functional fitness studio", "Volleyball court", "Swimming pool", "Tennis court", "Basketball court", "Pickleball court"]
        let bundles = types.map { ids("wellness_fitness", $0).sorted().joined(separator: ",") }
        XCTAssertEqual(Set(bundles).count, types.count)
        XCTAssertEqual(ids("wellness_fitness", "Physical therapy"), ["rehab_space", "privacy", "step_free"])
        XCTAssertFalse(ids("wellness_fitness", "Hospital").contains("gym_equipment"))
    }

    func testSpecializedFoodFormatsHaveRelevantQuestions() {
        XCTAssertEqual(ids("restaurants_food", "Ramen"), ["broth", "noodles", "waiting"])
        XCTAssertEqual(ids("restaurants_food", "Sushi"), ["sushi_menu", "counter_seating", "booking"])
        XCTAssertEqual(ids("restaurants_food", "Taco truck"), ["tacos", "waiting", "seating"])
        XCTAssertEqual(ids("restaurants_food", "Fondue"), ["fondue", "dietary_menu", "booking"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Coffee stand"), ["waiting", "milk", "seating"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Coffee shop"), ["laptop", "outlets", "dog_access"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Cafe"), ["laptop", "outdoor_seating", "dog_access"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Roastery"), ["beans", "tasting", "seating"])
        XCTAssertFalse(ids("coffee_tea_sweets", "Coffee stand").contains("laptop"))
        XCTAssertFalse(ids("coffee_tea_sweets", "Donut shop").contains("outlets"))
    }

    func testCustomSubtypeKeepsItsOwnScopeAndUsesSafeCategoryFallback() {
        let custom = "My quiet garden corner"
        let other = "My river stop"
        XCTAssertNil(PlaceCheckInQuestionCatalog.curatedQuestions(categoryID: "outdoors_nature", subcategory: custom))
        XCTAssertEqual(ids("outdoors_nature", custom), ["shade", "restroom", "path_surface"])
        XCTAssertNotEqual(
            PlaceCheckInQuestionCatalog.preferenceKey(categoryID: "outdoors_nature", subcategory: custom),
            PlaceCheckInQuestionCatalog.preferenceKey(categoryID: "outdoors_nature", subcategory: other)
        )
        XCTAssertEqual(
            PlaceCheckInQuestionCatalog.preferenceKey(categoryID: "outdoors_nature", subcategory: "  BEACH  "),
            PlaceCheckInQuestionCatalog.preferenceKey(categoryID: "outdoors_nature", subcategory: "Beach")
        )
        XCTAssertEqual(PlaceCheckInQuestionCatalog.questions(categoryID: "unrecognized category", subcategory: "My place").count, 3)
        XCTAssertEqual(PlaceCheckInQuestionCatalog.questions(categoryID: "place", subcategory: nil).count, 3)
    }

    func testSearchEvidenceDoesNotPromoteNegativeOrQualifiedAnswers() throws {
        let outlets = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_outlets"))
        XCTAssertEqual(outlets.searchTerms(for: "Plenty"), ["outlets", "power outlets"])
        XCTAssertEqual(outlets.searchTerms(for: "A few"), ["outlets", "power outlets"])
        XCTAssertEqual(outlets.searchTerms(for: "None found"), [])
        XCTAssertEqual(outlets.searchTerms(for: "Yes"), [])
        let dogs = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_dog_access"))
        XCTAssertEqual(dogs.searchTerms(for: "Not allowed"), [])
        XCTAssertEqual(dogs.searchTerms(for: "Outside only"), ["dogs outside", "outdoor dog access"])
        XCTAssertEqual(dogs.searchTerms(for: "Inside only"), ["dogs inside", "dogs indoors"])
        XCTAssertFalse(dogs.searchTerms(for: "Outside only").contains("dog friendly"))
        XCTAssertEqual(PlaceCheckInQuestionCatalog.question(id: "place_detail_noise")?.searchTerms(for: "Easy to talk"), ["conversation", "easy to talk"])
        XCTAssertFalse(PlaceCheckInQuestionCatalog.question(id: "place_detail_laptop")!.searchTerms(for: "Laptops welcome").contains("work friendly"))
        XCTAssertFalse(PlaceCheckInQuestionCatalog.question(id: "place_detail_water_refill")!.searchTerms(for: "Free refill").contains("drinking fountain"))
    }

    func testExplicitProviderTypesPreserveSpecificFitnessSubtypes() {
        let cases = [
            ("MKPOICategoryVolleyball", "Volleyball court"),
            ("volleyball_court", "Volleyball court"),
            ("pilates_studio", "Pilates studio"),
            ("pilates", "Pilates studio"),
            ("crossfit", "CrossFit gym"),
            ("crossfit_gym", "CrossFit gym"),
            ("functional_fitness", "Functional fitness studio"),
            ("functional_fitness_studio", "Functional fitness studio")
        ]
        for (raw, subtype) in cases {
            let assignment = WanderPlaceCategory.assignment(forRawCategory: raw)
            XCTAssertEqual(assignment.primaryCategory, "wellness_fitness", raw)
            XCTAssertEqual(assignment.subcategory, subtype, raw)
            XCTAssertEqual(PlaceCheckInQuestionCatalog.questions(categoryID: assignment.primaryCategory, subcategory: assignment.subcategory).count, 3)
        }
        XCTAssertEqual(WanderPlaceCategory.assignment(forRawCategory: "MKPOICategoryFitnessCenter").subcategory, "Fitness center")
        XCTAssertNil(WanderPlaceCategory.providerCategoryAssignment(for: "CrossFit near the river"))
        XCTAssertNil(WanderPlaceCategory.providerCategoryAssignment(for: "Pilates and yoga with friends"))
        XCTAssertEqual(WanderPlaceCategory.supportedMapKitProviderTypes.count, 73)
        let fitness = WanderPlaceCategory.subcategorySuggestions(for: "wellness_fitness")
        XCTAssertTrue(fitness.contains("Pilates studio"))
        XCTAssertTrue(fitness.contains("CrossFit gym"))
        XCTAssertTrue(fitness.contains("Functional fitness studio"))
    }

    func testAnswersDoNotConfuseExperienceWithPolicyOrMissingInstructionWithPrerequisites() throws {
        let booking = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_booking"))
        XCTAssertEqual(booking.options, ["Walked in", "Booked ahead", "Joined a waitlist"])
        XCTAssertFalse(booking.searchTerms(for: "Booked ahead").contains("booking required"))
        let policy = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_booking_policy"))
        XCTAssertEqual(policy.searchTerms(for: "Booking required"), ["booking required"])
        let introduction = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_pilates_intro"))
        XCTAssertTrue(introduction.options.contains("No introduction offered"))
        XCTAssertFalse(introduction.options.contains("Prior experience expected"))
        XCTAssertEqual(introduction.searchTerms(for: "No introduction offered"), [])
        let sleeping = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_everyday_privacy"))
        XCTAssertEqual(sleeping.options, ["Entire place", "Private bedroom", "Shared bedroom"])
        XCTAssertFalse(sleeping.searchTerms(for: "Entire place").contains("self contained accommodation"))
        let payment = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_everyday_payment"))
        XCTAssertTrue(payment.options.contains("No charge"))
        XCTAssertFalse(ids("services_errands", "Electrician").contains("everyday_turnaround"))
        XCTAssertFalse(ids("services_errands", "Plumber").contains("everyday_turnaround"))
        XCTAssertEqual(ids("coffee_tea_sweets", "Tea store"), ["tea_shop", "tasting", "gift_packaging"])
        XCTAssertEqual(ids("bars_nightlife", "Karaoke"), ["karaoke", "booking", "karaoke_charge"])
        XCTAssertEqual(ids("outdoors_nature", "Cabin"), ids("stays", "Cabin"))
        XCTAssertEqual(ids("outdoors_nature", "Campground"), ids("stays", "Campground"))
    }

    private func ids(_ category: String, _ subtype: String) -> [String] {
        PlaceCheckInQuestionCatalog.questions(categoryID: category, subcategory: subtype)
            .map { String($0.id.dropFirst(PlaceCheckInQuestionCatalog.keyPrefix.count)) }
    }
}
