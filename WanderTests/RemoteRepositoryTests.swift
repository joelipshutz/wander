import XCTest
@testable import Wander

@MainActor
final class RemoteRepositoryTests: XCTestCase {
    func testProfileSearchCallsExpectedRPCAndMapsShells() async throws {
        let rpc = RecordingRPC()
        rpc.responses["search_profiles_by_handle"] = """
        [
          {
            "id": "user_maya",
            "handle": "maya",
            "display_name": "Maya Chen",
            "avatar_url": null,
            "bio": "coffee and hikes",
            "home_area": "Los Angeles"
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let profiles = try await repository.searchProfiles(handleQuery: "ma")

        XCTAssertEqual(profiles.map(\.handle), ["maya"])
        XCTAssertEqual(profiles[0].displayName, "Maya Chen")
        XCTAssertEqual(profiles[0].relationship, .nonFollower)
        XCTAssertEqual(rpc.calls.map(\.name), ["search_profiles_by_handle"])
        XCTAssertEqual(rpc.calls[0].body["query"] as? String, "ma")
    }

    func testVisiblePlacesCallRPCWithSnakeCaseParamsAndMapRows() async throws {
        let rpc = RecordingRPC()
        rpc.responses["visible_places_in_view"] = """
        [
          {
            "user_place_id": "up_1",
            "place_id": "place_1",
            "owner_user_id": "user_maya",
            "owner_handle": "maya",
            "owner_display_name": "Maya Chen",
            "canonical_name": "Griffith Observatory Trail",
            "category": "hike",
            "latitude": 34.1184,
            "longitude": -118.3004,
            "status": "been",
            "visibility": "followers",
            "note": "Easy sunset win.",
            "rating_signal": null,
            "rating_score": 5,
            "recommended_score": 4.5,
            "recommended_count": 2,
            "source_type": "manual",
            "attributes": [
              {
                "question_definition_id": "q_1",
                "question_key": "strenuousness",
                "value_type": "single_choice",
                "value": "easy",
                "prompt": "how hard?",
                "options": ["easy", "medium"],
                "is_system": true
              }
            ]
          }
        ]
        """.data(using: .utf8)
        let repository = SupabasePlaceRepository(rpc: rpc)

        let places = try await repository.places(
            in: MapViewport(minLatitude: 34, minLongitude: -119, maxLatitude: 35, maxLongitude: -118)
        )

        XCTAssertEqual(places.map { $0.place.canonicalName }, ["Griffith Observatory Trail"])
        XCTAssertEqual(places[0].userPlace.status, .been)
        XCTAssertEqual(places[0].userPlace.visibility, .followers)
        XCTAssertEqual(places[0].userPlace.ratingScore, 5)
        XCTAssertEqual(places[0].userPlace.recommendedScore, 4.5)
        XCTAssertEqual(places[0].userPlace.recommendedCount, 2)
        XCTAssertEqual(places[0].attributes.map(\.questionKey), ["strenuousness"])
        XCTAssertEqual(places[0].attributes[0].valueJSON, "\"easy\"")
        XCTAssertEqual(rpc.calls.map(\.name), ["visible_places_in_view"])
        XCTAssertEqual(rpc.calls[0].body["min_lat"] as? Double, 34)
        XCTAssertEqual(rpc.calls[0].body["max_lng"] as? Double, -118)
        XCTAssertNil(rpc.calls[0].body["owner_scope"] as Any?)
    }

    func testSocialGraphRepositoriesCallExpectedRPCs() async throws {
        let rpc = RecordingRPC()
        let graphJSON = """
        [
          {
            "id": "user_maya",
            "handle": "maya",
            "display_name": "Maya Chen",
            "avatar_url": null,
            "bio": null,
            "home_area": "Los Angeles",
            "relationship": "mutual"
          }
        ]
        """.data(using: .utf8)
        rpc.responses["profile_following"] = graphJSON
        rpc.responses["profile_followers"] = graphJSON
        rpc.responses["profile_relationship"] = #""mutual""#.data(using: .utf8)
        let repository = SupabaseFollowRepository(rpc: rpc)

        let following = try await repository.following(userID: "user_joe")
        let followers = try await repository.followers(userID: "user_joe")
        let relationship = try await repository.relationship(to: "user_maya")

        XCTAssertEqual(following.map(\.handle), ["maya"])
        XCTAssertEqual(following[0].relationship, .mutual)
        XCTAssertEqual(followers.map(\.handle), ["maya"])
        XCTAssertEqual(relationship, .mutual)
        XCTAssertEqual(rpc.calls.map(\.name), ["profile_following", "profile_followers", "profile_relationship"])
        XCTAssertEqual(rpc.calls[0].body["profile_id"] as? String, "user_joe")
        XCTAssertEqual(rpc.calls[1].body["profile_id"] as? String, "user_joe")
        XCTAssertEqual(rpc.calls[2].body["profile_id"] as? String, "user_maya")
    }

    func testProfileVisiblePlacesCallsExpectedRPCAndMapsRows() async throws {
        let rpc = RecordingRPC()
        rpc.responses["profile_visible_places"] = """
        [
          {
            "user_place_id": "up_2",
            "place_id": "place_2",
            "owner_user_id": "user_ryan",
            "owner_handle": "ryan",
            "owner_display_name": "Ryan Lee",
            "canonical_name": "Larchmont Noodles",
            "category": "restaurant",
            "latitude": 34.073,
            "longitude": -118.323,
            "status": "wanna_go",
            "visibility": "mutuals",
            "note": "rainy night",
            "rating_signal": null,
            "rating_score": null,
            "recommended_score": null,
            "recommended_count": 0,
            "source_type": "manual",
            "attributes": []
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)

        let places = try await repository.userPlaces(
            for: "user_ryan",
            filters: PlaceFilters(statuses: [.wannaGo], categories: ["restaurant"])
        )

        XCTAssertEqual(places.map { $0.place.canonicalName }, ["Larchmont Noodles"])
        XCTAssertEqual(places[0].owner.handle, "ryan")
        XCTAssertEqual(places[0].userPlace.status, .wannaGo)
        XCTAssertEqual(rpc.calls.map(\.name), ["profile_visible_places"])
        XCTAssertEqual(rpc.calls[0].body["profile_id"] as? String, "user_ryan")
        XCTAssertEqual(rpc.calls[0].body["status_filter"] as? [String], ["wanna_go"])
        XCTAssertEqual(rpc.calls[0].body["category_filter"] as? [String], ["restaurant"])
    }

    func testVisiblePlacesRejectUnknownStatus() async throws {
        let rpc = RecordingRPC()
        rpc.responses["visible_places_in_view"] = """
        [
          {
            "user_place_id": "up_1",
            "place_id": "place_1",
            "owner_user_id": "user_maya",
            "owner_handle": "maya",
            "owner_display_name": "Maya Chen",
            "canonical_name": "Bad Row",
            "category": "hike",
            "latitude": 34.1,
            "longitude": -118.3,
            "status": "maybe",
            "visibility": "followers",
            "note": null,
            "rating_signal": null,
            "rating_score": null,
            "recommended_score": null,
            "recommended_count": 0,
            "source_type": "manual",
            "attributes": []
          }
        ]
        """.data(using: .utf8)
        let repository = SupabasePlaceRepository(rpc: rpc)

        do {
            _ = try await repository.places(
                in: MapViewport(minLatitude: 34, minLongitude: -119, maxLatitude: 35, maxLongitude: -118)
            )
            XCTFail("Expected invalid status to throw")
        } catch let error as WanderRemoteError {
            guard case .invalidResponse(let message) = error else {
                return XCTFail("Unexpected remote error: \(error)")
            }
            XCTAssertTrue(message.contains("Unknown place status"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSocialSaveCallsExpectedRPC() async throws {
        let rpc = RecordingRPC()
        rpc.responses["save_visible_place"] = #"{"user_place_id":"up_saved"}"#.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)

        let result = try await repository.saveVisiblePlace(placeID: "place_1", sourceUserPlaceID: "up_source")

        XCTAssertEqual(result, SaveResult(userPlaceID: "up_saved", syncState: .synced))
        XCTAssertEqual(rpc.calls.map(\.name), ["save_visible_place"])
        XCTAssertEqual(rpc.calls[0].body["input_place_id"] as? String, "place_1")
        XCTAssertEqual(rpc.calls[0].body["input_source_user_place_id"] as? String, "up_source")
    }

    func testOwnPlaceSaveCallsExpectedRPCWithPlaceAndAttributes() async throws {
        let rpc = RecordingRPC()
        rpc.responses["save_own_place"] = #"{"user_place_id":"up_saved","place_id":"place_saved"}"#.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)
        let draft = UserPlaceDraft(
            place: PlaceDraft(
                localID: "local_place_maru",
                serverID: nil,
                canonicalName: "Maru Coffee",
                category: "coffee",
                address: nil,
                locality: "Los Angeles",
                region: "CA",
                country: nil,
                latitude: 34.045,
                longitude: -118.235,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: "mk_maru",
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "window table",
            ratingScore: 4,
            nearbyConfirmed: true,
            sourceType: "current_location",
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid", "quiet"])
            ]
        )

        let result = try await repository.save(draft)

        XCTAssertEqual(result, SaveResult(userPlaceID: "up_saved", syncState: .synced, placeID: "place_saved"))
        XCTAssertEqual(rpc.calls.map(\.name), ["save_own_place"])

        let body = rpc.rawBodies[0]
        let place = body["input_place"] as? [String: Any]
        XCTAssertEqual(place?["canonical_name"] as? String, "Maru Coffee")
        XCTAssertEqual(place?["source_provider_place_id"] as? String, "mk_maru")
        XCTAssertEqual(place?["latitude"] as? Double, 34.045)

        let userPlace = body["input_user_place"] as? [String: Any]
        XCTAssertEqual(userPlace?["status"] as? String, "been")
        XCTAssertEqual(userPlace?["visibility"] as? String, "followers")
        XCTAssertEqual(userPlace?["nearby_confirmed"] as? Bool, true)
        XCTAssertEqual(userPlace?["rating_score"] as? Int, 4)
        XCTAssertNil(userPlace?["rating_signal"])

        let attributes = body["input_attributes"] as? [[String: Any]]
        XCTAssertEqual(attributes?.map { $0["question_key"] as? String }, ["coffee_tags"])
        XCTAssertEqual(attributes?.first?["value"] as? [String], ["wifi solid", "quiet"])
    }

    func testUnblockCallsExpectedRPC() async throws {
        let rpc = RecordingRPC()
        let repository = SupabaseBlockRepository(rpc: rpc)

        try await repository.unblock(userID: "user_ryan")

        XCTAssertEqual(rpc.calls.map(\.name), ["unblock_user"])
        XCTAssertEqual(rpc.calls[0].body["profile_id"] as? String, "user_ryan")
    }

    func testExtractionEnqueueCallsExpectedRPCWithArtifactAndJob() async throws {
        let rpc = RecordingRPC()
        rpc.responses["enqueue_extraction_job"] = """
        {
          "source_artifact_id": "source_remote",
          "extraction_job_id": "job_remote",
          "status": "pending",
          "attempt_count": 0
        }
        """.data(using: .utf8)
        let repository = SupabaseExtractionRepository(rpc: rpc)

        let result = try await repository.enqueue(
            ExtractionJobDraft(
                sourceArtifact: SourceArtifactDraft(
                    type: "url",
                    originalInput: "https://maps.app.goo.gl/example",
                    normalizedInput: "https://maps.app.goo.gl/example",
                    normalizedSourceHash: "hash_maps_example",
                    localAssetRef: nil,
                    remoteAssetRef: nil
                ),
                sourceType: "link",
                normalizedSourceHash: "hash_maps_example",
                providerSteps: ["queued_for_backend_extraction"]
            )
        )

        XCTAssertEqual(
            result,
            ExtractionJobEnqueueResult(
                sourceArtifactID: "source_remote",
                extractionJobID: "job_remote",
                status: .pending,
                attemptCount: 0
            )
        )
        XCTAssertEqual(rpc.calls.map(\.name), ["enqueue_extraction_job"])

        let body = rpc.rawBodies[0]
        let artifact = body["input_source_artifact"] as? [String: Any]
        XCTAssertEqual(artifact?["type"] as? String, "url")
        XCTAssertEqual(artifact?["normalized_source_hash"] as? String, "hash_maps_example")

        let job = body["input_job"] as? [String: Any]
        XCTAssertEqual(job?["source_type"] as? String, "link")
        XCTAssertEqual(job?["provider_steps_json"] as? [String], ["queued_for_backend_extraction"])
    }

    func testExtractionProcessInvokesWorkerFunctionAndMapsCandidates() async throws {
        let rpc = RecordingRPC()
        rpc.responses["function:extraction-worker"] = """
        {
          "extraction_job_id": "job_remote",
          "status": "needs_confirmation",
          "attempt_count": 1,
          "provider_steps_json": ["worker_started", "google_maps_coordinate_candidate"],
          "extracted_candidates_json": [
            {
              "id": "extracted_hash",
              "name": "Maru Coffee",
              "category": "coffee",
              "latitude": 34.0836,
              "longitude": -118.3614,
              "source_provider": "google_maps_link",
              "source_provider_place_id": "https://google.com/maps/place/Maru+Coffee",
              "confidence": 0.86
            }
          ],
          "confidence": 0.86,
          "error_code": null,
          "error_message": null
        }
        """.data(using: .utf8)
        let repository = SupabaseExtractionRepository(rpc: rpc, functions: rpc)

        let result = try await repository.process(jobID: "job_remote")

        XCTAssertEqual(result.status, .needsConfirmation)
        XCTAssertEqual(result.candidates.map(\.name), ["Maru Coffee"])
        XCTAssertEqual(result.candidates[0].sourceProvider, "google_maps_link")
        XCTAssertEqual(rpc.calls.map(\.name), ["function:extraction-worker"])
        XCTAssertEqual(rpc.calls[0].body["job_id"] as? String, "job_remote")
    }

    func testExtractionResultCallsExpectedRPC() async throws {
        let rpc = RecordingRPC()
        rpc.responses["get_extraction_job"] = """
        {
          "extraction_job_id": "job_remote",
          "status": "no_place_found",
          "attempt_count": 1,
          "provider_steps_json": ["worker_started", "photo_ocr_not_configured"],
          "extracted_candidates_json": [],
          "confidence": 0,
          "error_code": "photo_ocr_not_configured",
          "error_message": "Photo OCR is not wired yet."
        }
        """.data(using: .utf8)
        let repository = SupabaseExtractionRepository(rpc: rpc)

        let result = try await repository.result(jobID: "job_remote")

        XCTAssertEqual(result.status, .noPlaceFound)
        XCTAssertEqual(result.errorCode, "photo_ocr_not_configured")
        XCTAssertEqual(rpc.calls.map(\.name), ["get_extraction_job"])
        XCTAssertEqual(rpc.calls[0].body["input_job_id"] as? String, "job_remote")
    }
}

@MainActor
private final class RecordingRPC: RemoteProcedureCalling, RemoteFunctionCalling {
    struct Call: Equatable {
        let name: String
        let body: [String: AnyHashable]
    }

    var responses: [String: Data] = [:]
    private(set) var rawBodies: [[String: Any]] = []
    private(set) var calls: [Call] = []

    func call<Value: Decodable, Params: Encodable>(
        _ name: String,
        params: Params,
        decoder: JSONDecoder
    ) async throws -> Value {
        let body = try encodedObject(params)
        rawBodies.append(body)
        calls.append(Call(name: name, body: anyHashableBody(body)))

        if Value.self == EmptyRPCResponse.self {
            return EmptyRPCResponse() as! Value
        }

        guard let data = responses[name] else {
            throw WanderRemoteError.invalidResponse("Missing fake response for \(name)")
        }

        return try decoder.decode(Value.self, from: data)
    }

    func invoke<Value: Decodable, Body: Encodable>(
        _ name: String,
        body: Body,
        decoder: JSONDecoder
    ) async throws -> Value {
        let callName = "function:\(name)"
        let encodedBody = try encodedObject(body)
        rawBodies.append(encodedBody)
        calls.append(Call(name: callName, body: anyHashableBody(encodedBody)))

        guard let data = responses[callName] else {
            throw WanderRemoteError.invalidResponse("Missing fake response for \(callName)")
        }

        return try decoder.decode(Value.self, from: data)
    }

    private func encodedObject<Params: Encodable>(_ params: Params) throws -> [String: Any] {
        let data = try JSONEncoder().encode(params)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return object
    }

    private func anyHashableBody(_ object: [String: Any]) -> [String: AnyHashable] {
        return object.reduce(into: [:]) { result, element in
            if let value = element.value as? AnyHashable {
                result[element.key] = value
            } else if element.value is NSNull {
                result[element.key] = nil
            }
        }
    }
}
