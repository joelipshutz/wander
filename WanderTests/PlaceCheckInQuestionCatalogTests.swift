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
        print("Check-in catalog audit: \(subtypeCount) selectable subtypes; \(PlaceCheckInQuestionCatalog.availableQuestions.count) available questions; \(PlaceCheckInQuestionCatalog.retiredQuestionIDs.count) historical definitions")
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
                XCTAssertFalse(PlaceCheckInQuestionCatalog.retiredQuestionIDs.contains("place_detail_" + id), id)
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
                XCTAssertFalse(PlaceCheckInQuestionCatalog.retiredQuestionIDs.contains("place_detail_" + id), id)
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
        XCTAssertEqual(park, ["leash", "shade", "restroom"])
        for type in ["Park", "City park", "State park", "National park", "Dog park", "Playground"] {
            XCTAssertFalse(ids("outdoors_nature", type).contains("beach_rinse"), type)
        }
        XCTAssertEqual(ids("outdoors_nature", "Beach"), ["leash", "shade", "beach_rinse"])
        XCTAssertEqual(ids("outdoors_nature", "Trail"), ["leash", "incline", "trail_marking"])
        XCTAssertEqual(ids("outdoors_nature", "Trail"), ids("outdoors_nature", "Hike"))
        XCTAssertEqual(ids("outdoors_nature", "Dog park"), ["fenced", "leash", "water_refill"])
        XCTAssertEqual(ids("outdoors_nature", "Playground"), ["playground_age", "fenced", "shade"])
        XCTAssertEqual(ids("outdoors_nature", "RV park"), ["leash", "camp_power", "camp_toilet"])
        XCTAssertEqual(ids("outdoors_nature", "Fishing charter"), ["fishing_gear", "restroom", "booking_ease"])
    }

    func testFitnessSubtypesAreNotCollapsedToGymQuestions() {
        XCTAssertEqual(ids("wellness_fitness", "Pilates studio"), ["pilates_reformer", "class_busyness", "booking_ease"])
        XCTAssertEqual(ids("wellness_fitness", "CrossFit gym"), ["crossfit_scaling", "crossfit_format", "fitness_dropin"])
        XCTAssertEqual(ids("wellness_fitness", "Functional fitness studio"), ["functional_format", "coaching", "venue_busyness"])
        XCTAssertEqual(ids("wellness_fitness", "Volleyball court"), ["volleyball_surface", "volleyball_net", "court_booking"])
        XCTAssertEqual(ids("wellness_fitness", "Gym"), ids("wellness_fitness", "Fitness center"))
        let types = ["Gym", "Yoga studio", "Pilates studio", "CrossFit gym", "Functional fitness studio", "Volleyball court", "Swimming pool", "Tennis court", "Basketball court", "Pickleball court"]
        let bundles = types.map { ids("wellness_fitness", $0).sorted().joined(separator: ",") }
        XCTAssertEqual(Set(bundles).count, types.count)
        XCTAssertEqual(ids("wellness_fitness", "Physical therapy"), ["rehab_space", "privacy", "step_free"])
        XCTAssertFalse(ids("wellness_fitness", "Hospital").contains("gym_equipment"))
    }

    func testSpecializedFoodFormatsHaveRelevantQuestions() {
        XCTAssertEqual(ids("restaurants_food", "Ramen"), ["dog_access", "vegetarian", "waiting"])
        XCTAssertEqual(ids("restaurants_food", "Sushi"), ["dog_access", "counter_seating", "booking_policy"])
        XCTAssertEqual(ids("restaurants_food", "Taco truck"), ["dog_access", "waiting", "seating"])
        XCTAssertEqual(ids("restaurants_food", "Fondue"), ["dog_access", "sharing", "booking_policy"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Coffee stand"), ["waiting", "milk", "dog_access"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Coffee shop"), ["laptop", "outlets", "dog_access"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Cafe"), ["laptop", "outdoor_seating", "dog_access"])
        XCTAssertEqual(ids("coffee_tea_sweets", "Roastery"), ["beans", "tasting", "dog_access"])
        XCTAssertFalse(ids("coffee_tea_sweets", "Coffee stand").contains("laptop"))
        XCTAssertFalse(ids("coffee_tea_sweets", "Donut shop").contains("outlets"))
    }

    func testCustomSubtypeKeepsItsOwnScopeAndUsesSafeCategoryFallback() {
        let custom = "My quiet garden corner"
        let other = "My river stop"
        XCTAssertNil(PlaceCheckInQuestionCatalog.curatedQuestions(categoryID: "outdoors_nature", subcategory: custom))
        XCTAssertEqual(ids("outdoors_nature", custom), ["leash", "shade", "restroom"])
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

    func testFoodQuestionContextPreservesVenueFormatsAndRespectsCulinaryCorrections() {
        let category = WanderPlaceCategory.restaurantsFood
        let cases: [(subtype: String?, cuisine: String?, expected: String?)] = [
            ("Restaurant", "Thai", "Thai"),
            ("Ramen", "Thai", "Thai"),
            ("Sushi", "Vietnamese", "Vietnamese"),
            ("Taco truck", "Mexican", "Taco truck"),
            ("Taco stand", "Thai", "Taco stand"),
            ("Food court", "Japanese", "Food court"),
            ("Buffet", "Indian", "Buffet"),
            ("food_truck", "Korean", "Food truck"),
            ("Cafeteria", "Vegetarian", "Cafeteria"),
            ("Taco truck", "Food court", "Food court"),
            ("Ramen", nil, "Ramen"),
            ("Ramen", "  ", "Ramen"),
            (nil, "Thai", "Thai"),
            (nil, nil, nil)
        ]
        for value in cases {
            XCTAssertEqual(PlaceCheckInQuestionCatalog.questionSubtype(
                categoryID: category, subcategory: value.subtype, cuisine: value.cuisine
            ), value.expected, "\(value.subtype ?? "nil") + \(value.cuisine ?? "nil")")
        }
        let truck = PlaceCheckInQuestionCatalog.questionSubtype(
            categoryID: category, subcategory: "Taco truck", cuisine: "Mexican"
        )
        XCTAssertEqual(PlaceCheckInQuestionCatalog.questions(categoryID: category, subcategory: truck).map(\.id),
                       ["place_detail_dog_access", "place_detail_waiting", "place_detail_seating"])
        XCTAssertEqual(PlaceCheckInQuestionCatalog.preferenceKey(categoryID: category, subcategory: truck),
                       "restaurants_food:taco truck")
        XCTAssertEqual(PlaceCheckInQuestionCatalog.questionSubtype(
            categoryID: "outdoors_nature", subcategory: "Beach", cuisine: "Thai"
        ), "Beach")
        XCTAssertEqual(ids("things_to_do", "Billiards"), ["games", "game_payment", "equipment"])
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
        XCTAssertEqual(ids("coffee_tea_sweets", "Tea store"), ["tasting", "gift_packaging", "dog_access"])
        XCTAssertEqual(ids("bars_nightlife", "Karaoke"), ["karaoke", "booking_ease", "noise"])
        XCTAssertEqual(ids("outdoors_nature", "Cabin"), ids("stays", "Cabin"))
        XCTAssertEqual(ids("outdoors_nature", "Campground"), ids("stays", "Campground"))
    }

    func testNewLibraryRetiresTriviaWithoutReinterpretingSavedAnswers() throws {
        let availableIDs = Set(PlaceCheckInQuestionCatalog.availableQuestions.map(\.id))
        XCTAssertTrue(availableIDs.isDisjoint(with: PlaceCheckInQuestionCatalog.retiredQuestionIDs))
        XCTAssertEqual(availableIDs.count + PlaceCheckInQuestionCatalog.retiredQuestionIDs.count,
                       PlaceCheckInQuestionCatalog.allQuestions.count)
        for id in PlaceCheckInQuestionCatalog.retiredQuestionIDs {
            XCTAssertNotNil(PlaceCheckInQuestionCatalog.question(id: id), "Missing saved-answer definition: \(id)")
        }
        let historicalOptions: [String: [String]] = [
            "everyday_browsing": ["Spacious", "Comfortable", "Tight"],
            "pilates_format": ["Reformer", "Mat", "Mixed apparatus"],
            "pilates_intro": ["Separate introduction", "Help during class", "No introduction offered"],
            "class_size": ["On my own", "One-to-one", "Small group", "Larger group"],
            "noodles": ["Several types", "One house style", "Custom preparation"],
            "sushi_menu": ["Individual pieces or rolls", "Chef's selection", "Both"]
        ]
        for (id, options) in historicalOptions {
            let question = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_" + id))
            XCTAssertEqual(question.options, options, id)
            XCTAssertFalse(availableIDs.contains(question.id), id)
        }
        let reformer = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_pilates_reformer"))
        XCTAssertEqual(reformer.prompt, "Was it a reformer class?")
        XCTAssertEqual(reformer.options, ["Yes", "No"])
        XCTAssertEqual(reformer.searchTerms(for: "No"), [])
        XCTAssertEqual(reformer.searchTerms(for: "Reformer"), [], "Historical apparatus answers cannot become class answers")
        XCTAssertEqual(PlaceCheckInQuestionCatalog.question(id: "place_detail_class_busyness")?.options,
                       ["Plenty of space", "Busy", "Packed"])
        for question in PlaceCheckInQuestionCatalog.availableQuestions {
            XCTAssertLessThanOrEqual(question.prompt.count, 65, question.id)
        }
    }

    func testDogsAreUsefulDefaultsAcrossDiningAndOutdoorVisits() {
        for subtype in ["Restaurant", "Thai", "Italian", "Pizza", "Ramen", "Seafood"] {
            XCTAssertTrue(ids("restaurants_food", subtype).contains("dog_access"), subtype)
        }
        for subtype in ["Coffee shop", "Cafe", "Coffee stand", "Roastery", "Bakery", "Tea house"] {
            XCTAssertTrue(ids("coffee_tea_sweets", subtype).contains("dog_access"), subtype)
        }
        for subtype in ["Park", "Trail", "Beach", "Garden", "Lake", "River", "Campground", "Surf break"] {
            XCTAssertTrue(ids("outdoors_nature", subtype).contains("leash"), subtype)
            XCTAssertFalse(ids("outdoors_nature", subtype).contains("dog_access"), "Outdoor-only places need posted rules, not indoor access: \(subtype)")
        }
        XCTAssertFalse(ids("coffee_tea_sweets", "Cat cafe").contains("dog_access"))
        XCTAssertEqual(PlaceCheckInQuestionCatalog.question(id: "place_detail_leash")?.searchTerms(for: "No sign found"), [])
    }

    func testSportsAndCoastalSubtypesHavePurposefulQuestionSets() {
        XCTAssertEqual(ids("wellness_fitness", "Beach tennis"), ["court_booking", "equipment", "court_lights"])
        XCTAssertEqual(ids("wellness_fitness", "Beach volleyball"), ["volleyball_net", "court_booking", "shade"])
        XCTAssertEqual(ids("wellness_fitness", "Padel court"), ["court_booking", "court_setting", "equipment"])
        XCTAssertEqual(ids("wellness_fitness", "Climbing gym"), ["climbing_type", "equipment", "venue_busyness"])
        XCTAssertEqual(ids("wellness_fitness", "Surf school"), ["equipment", "class_busyness", "booking_ease"])
        XCTAssertEqual(ids("things_to_do", "Stadium"), ["seat_cover", "show_seating", "everyday_bag_check"])
        XCTAssertEqual(ids("things_to_do", "Arena"), ["acoustics", "show_seating", "everyday_bag_check"])
        XCTAssertEqual(ids("outdoors_nature", "Surf"), ["surf_rental", "venue_busyness", "leash"])
        XCTAssertEqual(ids("outdoors_nature", "Surf break"), ["surf_crowding", "beach_rinse", "leash"])
        XCTAssertEqual(ids("outdoors_nature", "Kayak/canoe rental"), ["equipment", "booking_ease", "dogs_on_boats"])
        XCTAssertEqual(ids("shopping", "Surf shop"), ["surf_rental", "everyday_repair", "dog_access"])
        XCTAssertEqual(PlaceCheckInQuestionCatalog.question(id: "place_detail_surf_rental")?.searchTerms(for: "Nearby only"), ["nearby surfboard rental"])
        XCTAssertEqual(PlaceCheckInQuestionCatalog.question(id: "place_detail_dogs_on_boats")?.searchTerms(for: "No"), [])
    }

    private func ids(_ category: String, _ subtype: String) -> [String] {
        PlaceCheckInQuestionCatalog.questions(categoryID: category, subcategory: subtype)
            .map { String($0.id.dropFirst(PlaceCheckInQuestionCatalog.keyPrefix.count)) }
    }
}
