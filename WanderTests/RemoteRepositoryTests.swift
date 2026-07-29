import XCTest
@testable import Wander

@MainActor
final class RemoteRepositoryTests: XCTestCase {
    func testRPCRefreshesTheClerkTokenOnceAfterUnauthorizedResponse() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, #"{"value":"fresh-token-response"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        let response: FeedRPCProbe = try await client.call("followed_feed", params: FeedRPCProbeParameters())

        XCTAssertEqual(response.value, "fresh-token-response")
        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer fresh-token"]
        )
    }

    func testEdgeFunctionRefreshesTheClerkTokenOnceAfterForbiddenResponse() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (403, #"{"message":"JWT rejected"}"#.data(using: .utf8)!),
                (200, #"{"value":"fresh-function-response"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        let response: FeedRPCProbe = try await client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )

        XCTAssertEqual(response.value, "fresh-function-response")
        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer fresh-token"]
        )
        XCTAssertEqual(
            FeedRPCURLProtocol.requestPaths,
            ["/functions/v1/place-photo", "/functions/v1/place-photo"]
        )
        let requestBodies = FeedRPCURLProtocol.requestBodies
        XCTAssertEqual(requestBodies.count, 2)
        let firstRequestBody = try XCTUnwrap(requestBodies.first)
        let secondRequestBody = try XCTUnwrap(requestBodies.dropFirst().first)
        XCTAssertEqual(firstRequestBody, secondRequestBody)
        let decodedBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstRequestBody) as? [String: String]
        )
        XCTAssertEqual(decodedBody["marker"], "photo-retry-probe")
    }

    func testEdgeFunctionStopsAfterOneFreshTokenRetry() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (403, #"{"message":"JWT still rejected"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            let _: FeedRPCProbe = try await client.invoke(
                "place-photo",
                body: FeedRPCProbeParameters()
            )
            XCTFail("Expected the second authorization response to remain a failure")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(FeedRPCURLProtocol.authorizationHeaders.count, 2)
    }

    func testNonIdempotentEdgeFunctionDoesNotReplayAfterAuthorizationFailure() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            let _: FeedRPCProbe = try await client.invoke(
                "extraction-worker",
                body: FeedRPCProbeParameters()
            )
            XCTFail("Expected the authorization response to fail without replaying the mutation")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 0)
        XCTAssertEqual(FeedRPCURLProtocol.requestPaths, ["/functions/v1/extraction-worker"])
    }

    func testConcurrentPlacePhotoFailuresShareOneForcedTokenRefresh() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, #"{"value":"first-photo"}"#.data(using: .utf8)!),
                (200, #"{"value":"second-photo"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(pausesForcedRefresh: true)
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        async let first: FeedRPCProbe = client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )
        async let second: FeedRPCProbe = client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )
        defer { auth.releaseForcedRefreshes() }
        try await auth.waitForForcedRefreshToStart()
        try await waitForFeedRequestCount(2)
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer cached-token"]
        )
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        auth.releaseForcedRefreshes()
        let responses = try await [first, second]

        XCTAssertEqual(Set(responses.map(\.value)), Set(["first-photo", "second-photo"]))
        XCTAssertEqual(auth.cachedTokenRequestCount, 2)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders.filter { $0 == "Bearer cached-token" }.count,
            2
        )
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders.filter { $0 == "Bearer fresh-token" }.count,
            2
        )
    }

    func testFailedSharedTokenRefreshIsRemovedBeforeTheNextAttempt() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, #"{"value":"recovered"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(forcedRefreshFailuresRemaining: 1)
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            let _: FeedRPCProbe = try await client.invoke(
                "place-photo",
                body: FeedRPCProbeParameters()
            )
            XCTFail("Expected the first forced refresh to fail")
        } catch {
            XCTAssertEqual(error as? AuthSessionError, .tokenUnavailable)
        }

        let response: FeedRPCProbe = try await client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )

        XCTAssertEqual(response.value, "recovered")
        XCTAssertEqual(auth.forcedTokenRequestCount, 2)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer cached-token", "Bearer fresh-token"]
        )
    }

    func testRejectedReplacementTokenIsRefreshedAgainOnTheNextRequest() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"cached token rejected"}"#.data(using: .utf8)!),
                (401, #"{"message":"first replacement rejected"}"#.data(using: .utf8)!),
                (401, #"{"message":"cached token rejected again"}"#.data(using: .utf8)!),
                (200, #"{"value":"second-replacement-worked"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(forcedTokens: ["fresh-token-b", "fresh-token-c"])
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            let _: FeedRPCProbe = try await client.invoke(
                "place-photo",
                body: FeedRPCProbeParameters()
            )
            XCTFail("Expected the first replacement token to remain unauthorized")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        let response: FeedRPCProbe = try await client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )

        XCTAssertEqual(response.value, "second-replacement-worked")
        XCTAssertEqual(auth.forcedTokenRequestCount, 2)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            [
                "Bearer cached-token",
                "Bearer fresh-token-b",
                "Bearer cached-token",
                "Bearer fresh-token-c"
            ]
        )
    }

    func testProtectedPhotoDownloadRefreshesTheClerkTokenOnceAfterUnauthorizedResponse() async throws {
        let expectedData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, expectedData)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        let data = try await client.downloadObject(
            bucket: "visit-photos",
            path: "user/visit/photo.jpg"
        )

        XCTAssertEqual(data, expectedData)
        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer fresh-token"]
        )
        XCTAssertEqual(
            FeedRPCURLProtocol.requestPaths,
            [
                "/storage/v1/object/visit-photos/user/visit/photo.jpg",
                "/storage/v1/object/visit-photos/user/visit/photo.jpg"
            ]
        )
    }

    func testRejectedStorageReplacementTokenIsRefreshedAgainOnTheNextRequest() async throws {
        let expectedData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"cached token rejected"}"#.data(using: .utf8)!),
                (401, #"{"message":"first replacement rejected"}"#.data(using: .utf8)!),
                (401, #"{"message":"cached token rejected again"}"#.data(using: .utf8)!),
                (200, expectedData)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(forcedTokens: ["fresh-token-b", "fresh-token-c"])
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            _ = try await client.downloadObject(
                bucket: "visit-photos",
                path: "user/visit/photo.jpg"
            )
            XCTFail("Expected the first replacement token to remain unauthorized")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        let data = try await client.downloadObject(
            bucket: "visit-photos",
            path: "user/visit/photo.jpg"
        )

        XCTAssertEqual(data, expectedData)
        XCTAssertEqual(auth.forcedTokenRequestCount, 2)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            [
                "Bearer cached-token",
                "Bearer fresh-token-b",
                "Bearer cached-token",
                "Bearer fresh-token-c"
            ]
        )
    }

    func testProtectedPhotoDownloadStopsAfterOneFreshTokenRetry() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (403, #"{"message":"JWT still rejected"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            _ = try await client.downloadObject(
                bucket: "visit-photos",
                path: "user/visit/photo.jpg"
            )
            XCTFail("Expected the second authorization response to remain a failure")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            ["Bearer cached-token", "Bearer fresh-token"]
        )
    }

    func testProtectedPhotoDownloadDoesNotRetryForAnotherSignedInAccount() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(switchesUserDuringForcedRefresh: true)
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        do {
            _ = try await client.downloadObject(
                bucket: "visit-photos",
                path: "user/visit/photo.jpg"
            )
            XCTFail("Expected the retry to stop after the signed-in account changed")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }

        XCTAssertEqual(auth.cachedTokenRequestCount, 1)
        XCTAssertEqual(auth.forcedTokenRequestCount, 1)
        XCTAssertEqual(FeedRPCURLProtocol.authorizationHeaders, ["Bearer cached-token"])
    }

    func testProtectedPhotoDownloadDiscardsAResponseAfterTheAccountChanges() async throws {
        let privatePhoto = Data([0xFF, 0xD8, 0xFF, 0xD9])
        FeedRPCURLProtocol.reset(
            responses: [(200, privatePhoto)],
            heldResponseIndices: [0]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession()
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        let download = Task {
            try await client.downloadObject(
                bucket: "visit-photos",
                path: "user/visit/private-photo.jpg"
            )
        }
        try await waitForFeedRequestCount(1)
        auth.switchUser(to: "user_other")
        FeedRPCURLProtocol.releaseHeldResponses()

        do {
            _ = try await download.value
            XCTFail("Expected account A's in-flight private response to be discarded")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, .notAuthenticated)
        }
    }

    func testReplacementTokenCacheIsIsolatedBySignedInAccount() async throws {
        FeedRPCURLProtocol.reset(
            responses: [
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, #"{"value":"user-a"}"#.data(using: .utf8)!),
                (401, #"{"message":"JWT expired"}"#.data(using: .utf8)!),
                (200, #"{"value":"user-b"}"#.data(using: .utf8)!)
            ]
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FeedRPCURLProtocol.self]
        let auth = FeedTokenAuthSession(forcedTokens: ["fresh-user-a", "fresh-user-b"])
        let client = WanderSupabaseClient(
            configuration: WanderBackendConfiguration(
                clerkPublishableKey: "pk_test_mock",
                clerkFrontendAPI: "mock.clerk.accounts.dev",
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "anon-key"
            ),
            authSession: auth,
            urlSession: URLSession(configuration: sessionConfiguration)
        )

        let userAResponse: FeedRPCProbe = try await client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )
        auth.switchUser(to: "user_other")
        let userBResponse: FeedRPCProbe = try await client.invoke(
            "place-photo",
            body: FeedRPCProbeParameters()
        )

        XCTAssertEqual(userAResponse.value, "user-a")
        XCTAssertEqual(userBResponse.value, "user-b")
        XCTAssertEqual(auth.forcedTokenRequestCount, 2)
        XCTAssertEqual(
            FeedRPCURLProtocol.authorizationHeaders,
            [
                "Bearer cached-token",
                "Bearer fresh-user-a",
                "Bearer cached-token",
                "Bearer fresh-user-b"
            ]
        )
    }

    private func waitForFeedRequestCount(_ expectedCount: Int) async throws {
        for _ in 0..<1_000 {
            if FeedRPCURLProtocol.requestCount >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for \(expectedCount) remote request(s)")
        throw URLError(.timedOut)
    }

    func testFollowedFeedCallsExpectedRPCAndDecodesTheHostedEmptyEnvelope() async throws {
        let rpc = RecordingRPC()
        rpc.responses["followed_feed"] = """
        {
          "activity": [],
          "featured_places": [],
          "next_cursor": null,
          "fetched_at": "2026-07-21T21:10:46.447909+00:00"
        }
        """.data(using: .utf8)
        let repository = SupabaseFeedRepository(rpc: rpc)

        let page = try await repository.followedFeed(before: nil, limit: 25)

        XCTAssertTrue(page.activity.isEmpty)
        XCTAssertTrue(page.featuredPlaces.isEmpty)
        XCTAssertNil(page.nextCursor)
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            page.fetchedAt,
            fractionalFormatter.date(from: "2026-07-21T21:10:46.447909+00:00")
        )
        XCTAssertEqual(rpc.calls.map(\.name), ["followed_feed"])
        XCTAssertNil(rpc.rawBodies[0]["input_before"])
        XCTAssertEqual(rpc.rawBodies[0]["input_limit"] as? Int, 25)
    }

    func testDiscoverPeopleRecommendationsCallsExpectedRPCAndMapsReasons() async throws {
        let rpc = RecordingRPC()
        rpc.responses["discover_profile_recommendations"] = """
        [
          {
            "id": "user_sofia",
            "handle": "sofia",
            "display_name": "Sofia Rivera",
            "avatar_url": "https://example.com/sofia.jpg",
            "bio": "Neighborhood restaurants and long walks.",
            "home_area": "Los Angeles",
            "created_at": "2026-07-01T12:00:00Z",
            "relationship": "non_follower",
            "reason_kind": "shared_follows",
            "shared_follow_count": 2,
            "result_rank": 1
          },
          {
            "id": "user_ari",
            "handle": "ari",
            "display_name": "Ari Bell",
            "avatar_url": null,
            "bio": null,
            "home_area": null,
            "created_at": "2026-06-01T12:00:00Z",
            "relationship": "non_follower",
            "reason_kind": "follows_you",
            "shared_follow_count": 0,
            "result_rank": 2
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let recommendations = try await repository.discoverProfileRecommendations(limit: 12)

        XCTAssertEqual(recommendations.map(\.profile.id), ["user_sofia", "user_ari"])
        XCTAssertEqual(recommendations.map(\.reason), [.sharedFollows(2), .followsYou])
        XCTAssertEqual(recommendations.map(\.rank), [1, 2])
        XCTAssertEqual(recommendations.first?.profile.isPrivateProfile, false)
        XCTAssertEqual(rpc.calls.map(\.name), ["discover_profile_recommendations"])
        XCTAssertEqual(rpc.calls[0].body["input_limit"] as? Int, 12)
    }

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

    func testCurrentProfileCallsExpectedRPCAndMapsAvatar() async throws {
        let rpc = RecordingRPC()
        rpc.responses["current_profile"] = """
        [
          {
            "id": "user_123",
            "handle": "joe",
            "display_name": "Joe",
            "avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_123/avatar.jpg?v=remote",
            "bio": "places worth returning to",
            "home_area": "Los Angeles",
            "default_visibility": "mutuals",
            "is_private_profile": true,
            "onboarding_completed_at": "2026-07-22T12:00:00Z",
            "created_at": "2024-10-01T12:00:00Z"
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let profile = try await repository.currentProfile()

        XCTAssertEqual(profile?.id, "user_123")
        XCTAssertEqual(profile?.handle, "joe")
        XCTAssertEqual(
            profile?.avatarURL,
            "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_123/avatar.jpg?v=remote"
        )
        XCTAssertEqual(profile?.defaultVisibility, .mutuals)
        XCTAssertEqual(profile?.isPrivateProfile, true)
        XCTAssertEqual(profile?.onboardingCompletedAt, ISO8601DateFormatter().date(from: "2026-07-22T12:00:00Z"))
        XCTAssertEqual(profile?.createdAt, ISO8601DateFormatter().date(from: "2024-10-01T12:00:00Z"))
        XCTAssertEqual(rpc.calls.map(\.name), ["current_profile"])
        XCTAssertTrue(rpc.rawBodies[0].isEmpty)
    }

    func testMemberProfileCallsDetailRPCAndMapsReadOnlyProfileMetadata() async throws {
        let rpc = RecordingRPC()
        rpc.responses["profile_detail"] = """
        [
          {
            "id": "user_maya",
            "handle": "maya",
            "display_name": "Maya Chen",
            "avatar_url": "https://example.com/maya.jpg",
            "bio": "coffee and hikes",
            "home_area": "Los Angeles",
            "is_private_profile": false,
            "created_at": "2023-10-01T12:00:00Z",
            "relationship": "mutual"
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let state = try await repository.profile(id: "user_maya")

        XCTAssertEqual(state.shell.id, "user_maya")
        XCTAssertEqual(state.shell.displayName, "Maya Chen")
        XCTAssertEqual(state.shell.avatarURL, "https://example.com/maya.jpg")
        XCTAssertEqual(state.shell.bio, "coffee and hikes")
        XCTAssertEqual(state.shell.homeArea, "Los Angeles")
        XCTAssertEqual(state.shell.isPrivateProfile, false)
        XCTAssertEqual(state.shell.createdAt, ISO8601DateFormatter().date(from: "2023-10-01T12:00:00Z"))
        XCTAssertEqual(state.shell.relationship, .mutual)
        XCTAssertFalse(state.canFollow)
        XCTAssertTrue(state.canBlock)
        XCTAssertEqual(rpc.calls.map(\.name), ["profile_detail"])
        XCTAssertEqual(rpc.calls[0].body["input_profile_id"] as? String, "user_maya")
    }

    func testMemberProfileRejectsProfileHiddenByRLS() async throws {
        let rpc = RecordingRPC()
        rpc.responses["profile_detail"] = "[]".data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        do {
            _ = try await repository.profile(id: "user_blocked")
            XCTFail("Expected hidden profile detail to be rejected")
        } catch let error as WanderRemoteError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testProfileDetailsUpdateCallsOwnerRPCAndMapsResult() async throws {
        let rpc = RecordingRPC()
        rpc.responses["update_own_profile"] = """
        {
          "id": "user_123",
          "handle": "joe",
          "display_name": "Joe",
          "avatar_url": null,
          "bio": "new bio",
          "home_area": "Los Angeles",
          "default_visibility": "followers",
          "is_private_profile": false,
          "onboarding_completed_at": "2026-07-22T12:00:00Z",
          "created_at": "2024-10-01T12:00:00Z"
        }
        """.data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let profile = try await repository.updateCurrentProfile(
            ProfileDetailsUpdate(
                displayName: "Joe Updated",
                handle: "joe_updated",
                bio: "new bio",
                homeArea: "Los Angeles",
                defaultVisibility: .mutuals,
                isPrivateProfile: true,
                markOnboardingComplete: true
            )
        )

        XCTAssertEqual(profile.bio, "new bio")
        XCTAssertEqual(profile.homeArea, "Los Angeles")
        XCTAssertEqual(rpc.calls.map(\.name), ["update_own_profile"])
        XCTAssertEqual(rpc.calls[0].body["input_display_name"] as? String, "Joe Updated")
        XCTAssertEqual(rpc.calls[0].body["input_handle"] as? String, "joe_updated")
        XCTAssertEqual(rpc.calls[0].body["input_bio"] as? String, "new bio")
        XCTAssertEqual(rpc.calls[0].body["input_home_area"] as? String, "Los Angeles")
        XCTAssertEqual(rpc.calls[0].body["input_default_visibility"] as? String, "mutuals")
        XCTAssertEqual(rpc.calls[0].body["input_is_private_profile"] as? Bool, true)
        XCTAssertEqual(rpc.calls[0].body["input_mark_onboarding_complete"] as? Bool, true)
        XCTAssertNotNil(profile.onboardingCompletedAt)
    }

    func testProfileHandleAvailabilityCallsNarrowBooleanRPC() async throws {
        let rpc = RecordingRPC()
        rpc.responses["profile_handle_available"] = "true".data(using: .utf8)
        let repository = SupabaseProfileRepository(rpc: rpc)

        let available = try await repository.isHandleAvailable("@new_friend")

        XCTAssertTrue(available)
        XCTAssertEqual(rpc.calls.map(\.name), ["profile_handle_available"])
        XCTAssertEqual(rpc.calls[0].body["input_handle"] as? String, "@new_friend")
    }

    func testMuteRepositoryUsesDedicatedRPCsAndMapsProfiles() async throws {
        let rpc = RecordingRPC()
        rpc.responses["mute_profile"] = "null".data(using: .utf8)
        rpc.responses["unmute_profile"] = "null".data(using: .utf8)
        rpc.responses["muted_profiles"] = """
        [{
          "id": "user_maya",
          "handle": "maya",
          "display_name": "Maya",
          "avatar_url": null,
          "bio": null,
          "home_area": null,
          "relationship": "mutual"
        }]
        """.data(using: .utf8)
        let repository = SupabaseMuteRepository(rpc: rpc)

        try await repository.mute(userID: "user_maya")
        let profiles = try await repository.mutedProfiles()
        try await repository.unmute(userID: "user_maya")

        XCTAssertEqual(profiles.map(\.id), ["user_maya"])
        XCTAssertEqual(rpc.calls.map(\.name), ["mute_profile", "muted_profiles", "unmute_profile"])
        XCTAssertEqual(rpc.calls[0].body["profile_id"] as? String, "user_maya")
    }

    func testProfileAvatarUploadStoresRemoteURL() async throws {
        let rpc = RecordingRPC()
        let storage = RecordingStorage()
        rpc.responses["update_profile_avatar"] = """
        {
          "avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_123/avatar.jpg?v=test-version",
          "avatar_storage_path": "user_123/avatar.jpg"
        }
        """.data(using: .utf8)
        let repository = SupabaseProfileAvatarRepository(
            rpc: rpc,
            storage: storage,
            versionProvider: { "test-version" }
        )
        let data = Data([0xFF, 0xD8, 0xFF])

        let result = try await repository.uploadAvatar(jpegData: data, userID: "user_123")

        XCTAssertEqual(
            result,
            ProfileAvatarResult(
                avatarURL: "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_123/avatar.jpg?v=test-version",
                storagePath: "user_123/avatar.jpg"
            )
        )
        XCTAssertEqual(
            storage.uploads,
            [
                RecordingStorage.Upload(
                    bucket: "profile-avatars",
                    path: "user_123/avatar.jpg",
                    data: data,
                    contentType: "image/jpeg",
                    upsert: true
                )
            ]
        )
        XCTAssertEqual(rpc.calls.map(\.name), ["update_profile_avatar"])
        XCTAssertEqual(
            rpc.calls[0].body["avatar_url"] as? String,
            "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_123/avatar.jpg?v=test-version"
        )
        XCTAssertEqual(rpc.calls[0].body["storage_path"] as? String, "user_123/avatar.jpg")
    }

    func testProfileAvatarDeleteRemovesStorageObjectAndClearsRemoteURL() async throws {
        let rpc = RecordingRPC()
        let storage = RecordingStorage()
        rpc.responses["update_profile_avatar"] = """
        {
          "avatar_url": null,
          "avatar_storage_path": null
        }
        """.data(using: .utf8)
        let repository = SupabaseProfileAvatarRepository(rpc: rpc, storage: storage)

        try await repository.deleteAvatar(userID: "user_123")

        XCTAssertEqual(
            storage.deletes,
            [RecordingStorage.Delete(bucket: "profile-avatars", path: "user_123/avatar.jpg")]
        )
        XCTAssertEqual(rpc.calls.map(\.name), ["update_profile_avatar"])
        XCTAssertNil(rpc.calls[0].body["avatar_url"] as Any?)
        XCTAssertNil(rpc.calls[0].body["storage_path"] as Any?)
    }

    func testVisitRepositoryUpsertsVisitViaPostgRESTTable() async throws {
        let table = RecordingTable()
        let storage = RecordingStorage()
        table.responses["POST:place_visits"] = """
        [
          {
            "id": "visit_remote",
            "user_place_id": "up_remote",
            "visited_at": "2026-07-09T20:00:00Z",
            "note": "second visit",
            "rating_score": 4.5,
            "tags": ["quiet", "wifi"],
            "backfilled_from_user_place": false,
            "created_at": "2026-07-09T20:00:00Z",
            "updated_at": "2026-07-09T20:00:00Z",
            "deleted_at": null
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseVisitRepository(table: table, storage: storage)
        let visitedAt = ISO8601DateFormatter().date(from: "2026-07-09T20:00:00Z")!

        let result = try await repository.upsertVisit(
            PlaceVisitDraft(
                id: "visit_remote",
                userPlaceID: "up_remote",
                visitedAt: visitedAt,
                note: "second visit",
                ratingScore: 4.5,
                attributeAnswersJSON: """
                [{"question_key":"coffee_tags","value_type":"multi_tag","value":["quiet","wifi"]}]
                """,
                backfilledFromUserPlace: false
            )
        )

        XCTAssertEqual(result.visitID, "visit_remote")
        XCTAssertEqual(result.tags, ["quiet", "wifi"])
        XCTAssertEqual(table.calls.map(\.key), ["POST:place_visits"])
        XCTAssertEqual(table.calls[0].queryItems.first { $0.name == "on_conflict" }?.value, "id")
        let body = try XCTUnwrap(table.rawBodies[0] as? [[String: Any]])
        XCTAssertEqual(body[0]["user_place_id"] as? String, "up_remote")
        XCTAssertEqual(body[0]["backfilled_from_user_place"] as? Bool, false)
        XCTAssertEqual(body[0]["rating_score"] as? Double, 4.5)
    }

    func testVisitRepositoryUploadsAndDeletesVisitPhotoStorage() async throws {
        let table = RecordingTable()
        let storage = RecordingStorage()
        let repository = SupabaseVisitRepository(table: table, storage: storage)
        let data = Data([0x01, 0x02, 0x03])

        let url = try await repository.uploadPhotoData(
            bucket: "visit-photos",
            path: "user_123/visit_123/photo_123.jpg",
            data: data,
            contentType: "image/jpeg"
        )
        try await repository.deletePhoto(
            photoID: "photo_123",
            bucket: "visit-photos",
            path: "user_123/visit_123/photo_123.jpg"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example.supabase.co/storage/v1/object/sign/visit-photos/user_123/visit_123/photo_123.jpg?token=test"
        )
        XCTAssertEqual(
            storage.uploads,
            [
                RecordingStorage.Upload(
                    bucket: "visit-photos",
                    path: "user_123/visit_123/photo_123.jpg",
                    data: data,
                    contentType: "image/jpeg",
                    upsert: true
                )
            ]
        )
        XCTAssertEqual(storage.deletes, [RecordingStorage.Delete(bucket: "visit-photos", path: "user_123/visit_123/photo_123.jpg")])
        XCTAssertEqual(table.calls.map(\.key), ["DELETE:visit_photos"])
        XCTAssertEqual(table.calls[0].queryItems, [URLQueryItem(name: "id", value: "eq.photo_123")])
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
            "owner_avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_maya/avatar.jpg?v=1",
            "canonical_name": "Griffith Observatory Trail",
            "category": "hike",
            "latitude": 34.1184,
            "longitude": -118.3004,
            "status": "been",
            "visibility": "followers",
            "note": "Easy sunset win.",
            "visited_at": "2026-07-09T20:00:00Z",
            "saved_at": "2026-07-08T19:00:00Z",
            "created_at": "2026-07-08T18:00:00Z",
            "updated_at": "2026-07-10T21:00:00Z",
            "rating_signal": null,
            "rating_score": 4.5,
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
        XCTAssertEqual(
            places[0].owner.avatarURL,
            "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_maya/avatar.jpg?v=1"
        )
        XCTAssertEqual(places[0].userPlace.status, .been)
        XCTAssertEqual(places[0].userPlace.visibility, .followers)
        XCTAssertEqual(places[0].userPlace.ratingScore, 4.5)
        XCTAssertEqual(places[0].userPlace.recommendedScore, 4.5)
        XCTAssertEqual(places[0].userPlace.recommendedCount, 2)
        XCTAssertEqual(places[0].userPlace.visitedAt, ISO8601DateFormatter().date(from: "2026-07-09T20:00:00Z"))
        XCTAssertEqual(places[0].userPlace.savedAt, ISO8601DateFormatter().date(from: "2026-07-08T19:00:00Z"))
        XCTAssertEqual(places[0].userPlace.createdAt, ISO8601DateFormatter().date(from: "2026-07-08T18:00:00Z"))
        XCTAssertEqual(places[0].userPlace.updatedAt, ISO8601DateFormatter().date(from: "2026-07-10T21:00:00Z"))
        XCTAssertEqual(places[0].userPlace.serverUpdatedAt, ISO8601DateFormatter().date(from: "2026-07-10T21:00:00Z"))
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
            "owner_avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=1",
            "canonical_name": "Larchmont Noodles",
            "category": "restaurant",
            "latitude": 34.073,
            "longitude": -118.323,
            "status": "wanna_go",
            "visibility": "mutuals",
            "note": "rainy night",
            "visited_at": null,
            "saved_at": "2026-07-07T18:00:00Z",
            "created_at": "2026-07-07T18:00:00Z",
            "updated_at": "2026-07-08T19:00:00Z",
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
        XCTAssertEqual(
            places[0].owner.avatarURL,
            "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=1"
        )
        XCTAssertEqual(places[0].userPlace.status, .wannaGo)
        XCTAssertNil(places[0].userPlace.visitedAt)
        XCTAssertEqual(places[0].userPlace.savedAt, ISO8601DateFormatter().date(from: "2026-07-07T18:00:00Z"))
        XCTAssertEqual(places[0].userPlace.updatedAt, ISO8601DateFormatter().date(from: "2026-07-08T19:00:00Z"))
        XCTAssertEqual(rpc.calls.map(\.name), ["profile_visible_places"])
        XCTAssertEqual(rpc.calls[0].body["profile_id"] as? String, "user_ryan")
        XCTAssertEqual(rpc.calls[0].body["status_filter"] as? [String], ["wanna_go"])
        XCTAssertEqual(rpc.calls[0].body["category_filter"] as? [String], [WanderPlaceCategory.restaurantsFood])
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
            "owner_avatar_url": null,
            "canonical_name": "Bad Row",
            "category": "hike",
            "latitude": 34.1,
            "longitude": -118.3,
            "status": "maybe",
            "visibility": "followers",
            "note": null,
            "visited_at": null,
            "saved_at": "2026-07-08T18:00:00Z",
            "created_at": "2026-07-08T18:00:00Z",
            "updated_at": "2026-07-08T18:00:00Z",
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
            ratingScore: 4.5,
            nearbyConfirmed: true,
            sourceType: "current_location",
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid", "quiet"]),
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    stringValues: ["work favorite", "joe rec"]
                ),
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: "Thai"
                )
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
        XCTAssertEqual(userPlace?["rating_score"] as? Double, 4.5)
        XCTAssertNil(userPlace?["rating_signal"])

        let attributes = body["input_attributes"] as? [[String: Any]]
        XCTAssertEqual(
            attributes?.map { $0["question_key"] as? String },
            ["coffee_tags", PlaceMemoryAttributeKeys.personalLabels, PlaceMemoryAttributeKeys.restaurantCuisine]
        )
        XCTAssertEqual(
            attributes?.map { $0["value_type"] as? String },
            ["multi_tag", "personal_label", "restaurant_cuisine"]
        )
        XCTAssertEqual(attributes?.first?["value"] as? [String], ["wifi solid", "quiet"])
        XCTAssertEqual(attributes?[1]["value"] as? [String], ["work favorite", "joe rec"])
        XCTAssertEqual(attributes?[2]["value"] as? String, "Thai")
    }

    func testCheckInSaveUsesAtomicRPCWithStableTicketAndHistoricalWannaSnapshot() async throws {
        let rpc = RecordingRPC()
        let visitID = "38D2B5B8-7F95-42CF-991B-253991C8C6C9"
        rpc.responses["save_own_check_in"] = """
        {
          "user_place_id": "up_saved",
          "place_id": "place_saved",
          "visit_id": "\(visitID)",
          "visited_at": "2026-07-20T18:00:00Z",
          "note": "first check-in",
          "rating_score": 4.5,
          "tags": ["date night", "quiet"],
          "backfilled_from_user_place": false
        }
        """.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)
        let visitedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-20T18:00:00Z"))
        let wantedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T17:00:00Z"))
        let userPlace = UserPlaceDraft(
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
            note: "first check-in",
            ratingScore: 4.5,
            nearbyConfirmed: true,
            sourceType: "manual",
            attributes: [
                PlaceAttributeDraft(
                    questionKey: "visit_tags",
                    valueType: "multi_tag",
                    stringValues: ["date night", "quiet"]
                )
            ]
        )
        let result = try await repository.saveCheckIn(
            CheckInSaveDraft(
                userPlace: userPlace,
                visit: PlaceVisitDraft(
                    id: visitID,
                    userPlaceID: "local_user_place_maru",
                    visitedAt: visitedAt,
                    note: "first check-in",
                    ratingScore: 4.5,
                    attributeAnswersJSON: VisitAttributeAnswers.encoded(from: userPlace.attributes),
                    backfilledFromUserPlace: false
                ),
                historicalWant: HistoricalWantSnapshotDraft(
                    note: "Joe recommended it",
                    attributeAnswersJSON: "[]",
                    tags: ["coffee"],
                    wantedAt: wantedAt
                )
            )
        )

        XCTAssertEqual(rpc.calls.map(\.name), ["save_own_check_in"])
        XCTAssertEqual(result.saveResult.userPlaceID, "up_saved")
        XCTAssertEqual(result.saveResult.placeID, "place_saved")
        XCTAssertEqual(result.visitResult.visitID, visitID)
        XCTAssertEqual(result.visitResult.visitedAt, visitedAt)
        XCTAssertEqual(result.visitResult.tags, ["date night", "quiet"])

        let body = rpc.rawBodies[0]
        let userPlaceBody = try XCTUnwrap(body["input_user_place"] as? [String: Any])
        XCTAssertEqual(userPlaceBody["status"] as? String, "been")

        let visit = try XCTUnwrap(body["input_visit"] as? [String: Any])
        XCTAssertEqual(visit["id"] as? String, visitID)
        XCTAssertEqual(visit["visited_at"] as? String, "2026-07-20T18:00:00Z")
        XCTAssertEqual(visit["note"] as? String, "first check-in")
        XCTAssertEqual(visit["rating_score"] as? Double, 4.5)
        let answers = try XCTUnwrap(visit["attribute_answers"] as? [[String: Any]])
        XCTAssertEqual(answers.first?["question_key"] as? String, "visit_tags")
        XCTAssertEqual(answers.first?["value_type"] as? String, "multi_tag")
        XCTAssertEqual(answers.first?["value"] as? [String], ["date night", "quiet"])

        let historicalWant = try XCTUnwrap(body["input_historical_want"] as? [String: Any])
        XCTAssertEqual(historicalWant["note"] as? String, "Joe recommended it")
        XCTAssertEqual(historicalWant["tags"] as? [String], ["coffee"])
        XCTAssertEqual(historicalWant["wanted_at"] as? String, "2026-07-01T17:00:00Z")
    }

    func testCheckInDeleteUsesAtomicRPCAndDecodesRemovalTransition() async throws {
        let rpc = RecordingRPC()
        let visitID = "38D2B5B8-7F95-42CF-991B-253991C8C6C9"
        rpc.responses["delete_own_check_in"] = """
        {
          "visit_id": "\(visitID)",
          "user_place_id": null,
          "transition": "removed"
        }
        """.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)

        let result = try await repository.deleteCheckIn(visitID: visitID)

        XCTAssertEqual(
            result,
            CheckInDeleteResult(visitID: visitID, userPlaceID: nil, transition: .removed)
        )
        XCTAssertEqual(rpc.calls.map(\.name), ["delete_own_check_in"])
        XCTAssertEqual(rpc.rawBodies[0]["input_visit_id"] as? String, visitID)
    }

    func testWannaPlaceSaveSendsPlannedDateAndOwnerPlanRPCDecodesIt() async throws {
        let rpc = RecordingRPC()
        rpc.responses["save_own_place"] = #"{"user_place_id":"up_maru","place_id":"place_maru"}"#.data(using: .utf8)
        rpc.responses["own_wanna_go_plans"] = """
        [{
          "user_place_id": "up_maru",
          "place_id": "place_maru",
          "planned_date": "2026-08-20"
        }]
        """.data(using: .utf8)
        let repository = SupabaseUserPlaceRepository(rpc: rpc)
        let plannedDate = try XCTUnwrap(WannaGoDate.date(fromStorageString: "2026-08-20"))
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
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            nearbyConfirmed: false,
            plannedDate: plannedDate,
            sourceType: "manual",
            attributes: []
        )

        _ = try await repository.save(draft)
        let plans = try await repository.ownWannaGoPlans()

        let userPlace = try XCTUnwrap(rpc.rawBodies.first?["input_user_place"] as? [String: Any])
        XCTAssertEqual(userPlace["planned_date"] as? String, "2026-08-20")
        XCTAssertEqual(rpc.calls.map(\.name), ["save_own_place", "own_wanna_go_plans"])
        XCTAssertEqual(plans.map(\.userPlaceID), ["up_maru"])
        XCTAssertEqual(plans.map(\.placeID), ["place_maru"])
        XCTAssertEqual(WannaGoDate.storageString(from: try XCTUnwrap(plans.first?.plannedDate)), "2026-08-20")
    }

    func testOwnPlaceDeleteUsesRemoteDeleteClient() async throws {
        let rpc = RecordingRPC()
        let repository = SupabaseUserPlaceRepository(rpc: rpc, userPlaceDeleter: rpc)

        try await repository.delete(userPlaceID: "up_saved")

        XCTAssertEqual(rpc.deletedUserPlaceIDs, ["up_saved"])
        XCTAssertTrue(rpc.calls.isEmpty)
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

    func testPlaceListRepositoryFetchesVisibleListsAndDetail() async throws {
        let rpc = RecordingRPC()
        let listID = "11111111-1111-4111-8111-111111111111"
        let itemID = "22222222-2222-4222-8222-222222222222"
        let placeID = "33333333-3333-4333-8333-333333333333"
        let userPlaceID = "44444444-4444-4444-8444-444444444444"
        rpc.responses["visible_place_lists"] = """
        [
          {
            "id": "\(listID)",
            "owner_user_id": "user_ryan",
            "owner_handle": "ryan",
            "owner_display_name": "Ryan",
            "owner_avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=list",
            "name": "Brooklyn tables",
            "description": "Dinner ideas",
            "visibility": "followers",
            "created_at": "2026-07-08T16:00:00Z",
            "updated_at": "2026-07-08T16:05:00Z",
            "collaborators": [
              {
                "user_id": "user_joe",
                "handle": "joe",
                "display_name": "Joe",
                "avatar_url": "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_joe/avatar.jpg?v=list",
                "role": "collaborator"
              }
            ],
            "item_count": 1
          }
        ]
        """.data(using: .utf8)
        rpc.responses["place_list_detail"] = """
        {
          "list": {
            "id": "\(listID)",
            "owner_user_id": "user_ryan",
            "name": "Brooklyn tables",
            "description": "Dinner ideas",
            "visibility": "followers",
            "created_at": "2026-07-08T16:00:00Z",
            "updated_at": "2026-07-08T16:05:00Z",
            "deleted_at": null
          },
          "collaborators": [
            {
              "user_id": "user_joe",
              "handle": "joe",
              "display_name": "Joe",
              "role": "collaborator"
            }
          ],
          "items": [
            {
              "id": "\(itemID)",
              "list_id": "\(listID)",
              "place_id": "\(placeID)",
              "owner_user_place_id": "\(userPlaceID)",
              "source_user_place_id": "\(userPlaceID)",
              "added_by_user_id": "user_ryan",
              "created_at": "2026-07-08T16:02:00Z",
              "updated_at": "2026-07-08T16:02:00Z",
              "deleted_at": null
            }
          ]
        }
        """.data(using: .utf8)
        let repository = SupabasePlaceListRepository(rpc: rpc)

        let summaries = try await repository.visibleLists()
        let detail = try await repository.detail(listID: listID)

        XCTAssertEqual(summaries.map(\.list.id), [listID])
        XCTAssertEqual(summaries[0].list.cachedItemCount, 1)
        XCTAssertEqual(summaries[0].owner.handle, "ryan")
        XCTAssertEqual(summaries[0].owner.avatarURL, "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=list")
        XCTAssertEqual(summaries[0].collaborators.map(\.userID), ["user_joe"])
        XCTAssertEqual(summaries[0].collaborators.map(\.avatarURL), ["https://example.supabase.co/storage/v1/object/public/profile-avatars/user_joe/avatar.jpg?v=list"])
        XCTAssertEqual(detail?.items.map(\.id), [itemID])
        XCTAssertEqual(detail?.items[0].placeID, placeID)
        XCTAssertEqual(rpc.calls.map(\.name), ["visible_place_lists", "place_list_detail"])
        XCTAssertTrue(rpc.rawBodies[0].isEmpty)
        XCTAssertEqual(rpc.calls[1].body["input_list_id"] as? String, listID)
    }

    func testPlaceListRepositoryWritesExpectedRPCs() async throws {
        let rpc = RecordingRPC()
        let listID = "11111111-1111-4111-8111-111111111111"
        let itemID = "22222222-2222-4222-8222-222222222222"
        let placeID = "33333333-3333-4333-8333-333333333333"
        let userPlaceID = "44444444-4444-4444-8444-444444444444"
        rpc.responses["upsert_place_list"] = "\"\(listID)\"".data(using: .utf8)
        rpc.responses["add_place_list_item"] = "\"\(itemID)\"".data(using: .utf8)
        let repository = SupabasePlaceListRepository(rpc: rpc)

        let createdListID = try await repository.upsert(
            PlaceListUpsertDraft(
                id: nil,
                name: "LA coffee",
                description: "laptop mornings",
                visibility: .followers
            )
        )
        try await repository.setCollaborators(listID: listID, userIDs: ["user_ryan"])
        let createdItemID = try await repository.addItem(
            PlaceListItemDraft(
                listID: listID,
                placeID: placeID,
                ownerUserPlaceID: userPlaceID,
                sourceUserPlaceID: userPlaceID
            )
        )
        try await repository.removeItem(listID: listID, itemID: itemID)
        try await repository.delete(listID: listID)

        XCTAssertEqual(createdListID, listID)
        XCTAssertEqual(createdItemID, itemID)
        XCTAssertEqual(
            rpc.calls.map(\.name),
            [
                "upsert_place_list",
                "set_place_list_collaborators",
                "add_place_list_item",
                "remove_place_list_item",
                "delete_place_list"
            ]
        )
        let upsertBody = rpc.rawBodies[0]["input_list"] as? [String: Any]
        XCTAssertEqual(upsertBody?["name"] as? String, "LA coffee")
        XCTAssertEqual(upsertBody?["visibility"] as? String, "followers")
        XCTAssertEqual(rpc.calls[1].body["input_list_id"] as? String, listID)
        XCTAssertEqual(rpc.rawBodies[1]["collaborator_user_ids"] as? [String], ["user_ryan"])
        XCTAssertEqual(rpc.calls[2].body["input_place_id"] as? String, placeID)
        XCTAssertEqual(rpc.calls[2].body["input_owner_user_place_id"] as? String, userPlaceID)
        XCTAssertEqual(rpc.calls[3].body["input_item_id"] as? String, itemID)
        XCTAssertEqual(rpc.calls[4].body["input_list_id"] as? String, listID)
    }

    func testDiscoverFilterParserInvokesEdgeFunctionWithRawQueryAndSchema() async throws {
        let rpc = RecordingRPC()
        rpc.responses["function:parse-discover-query"] = """
        {
          "query": "Joe's favorite coffee spots in LA",
          "categories": ["coffee_tea_sweets"],
          "area": "LA",
          "statuses": ["been"],
          "relationship": null,
          "ownerQuery": "Joe",
          "tags": []
        }
        """.data(using: .utf8)
        let repository = SupabaseDiscoverFilterRepository(functions: rpc)
        let schema = DiscoverFilterSchema(
            allowedCategories: [WanderPlaceCategory.coffeeTeaSweets, WanderPlaceCategory.outdoorsNature],
            allowedStatuses: [.been, .wannaGo],
            allowedRelationships: [.owner, .mutual],
            allowedTags: ["quiet"]
        )

        let filters = try await repository.parseFilters(query: "Joe's favorite coffee spots in LA", schema: schema)

        XCTAssertEqual(filters.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(filters.statuses, [.been])
        XCTAssertEqual(filters.ownerQuery, "Joe")
        XCTAssertEqual(rpc.calls.map(\.name), ["function:parse-discover-query"])
        XCTAssertEqual(rpc.rawBodies[0]["query"] as? String, "Joe's favorite coffee spots in LA")

        let encodedSchema = rpc.rawBodies[0]["schema"] as? [String: Any]
        XCTAssertEqual(encodedSchema?["allowedCategories"] as? [String], [WanderPlaceCategory.coffeeTeaSweets, WanderPlaceCategory.outdoorsNature])
        XCTAssertEqual(encodedSchema?["allowedStatuses"] as? [String], ["been", "wanna_go"])
        XCTAssertEqual(encodedSchema?["allowedRelationships"] as? [String], ["owner", "mutual"])
        XCTAssertEqual(encodedSchema?["allowedTags"] as? [String], ["quiet"])
    }

    func testListSuggestionRepositoryInvokesEdgeFunctionWithPayload() async throws {
        let rpc = RecordingRPC()
        rpc.responses["function:suggest-list-places"] = """
        {
          "suggestions": [
            {
              "visible_place_id": "visible_fern",
              "reason": "Fits the coffee and laptop theme",
              "score": 0.91
            }
          ]
        }
        """.data(using: .utf8)
        let repository = SupabaseListSuggestionRepository(functions: rpc)
        let payload = ListSuggestionPayload(
            listID: "list_laptop",
            title: "LA laptop mornings",
            description: "quiet tables and outlets",
            existingPlaces: [],
            candidatePlaces: [
                ListSuggestionPlacePayload(
                    visiblePlaceID: "visible_fern",
                    placeID: "place_fern",
                    name: "Fern Desk Coffee",
                    category: "coffee",
                    locality: "Los Angeles",
                    region: "CA",
                    status: .been,
                    ratingScore: 5,
                    recommendedScore: 4.7,
                    recommendedCount: 3,
                    attributesText: "[quiet outlets]"
                )
            ],
            limit: 4
        )

        let response = try await repository.suggestions(payload: payload)

        XCTAssertEqual(response.suggestions.map(\.visiblePlaceID), ["visible_fern"])
        XCTAssertEqual(response.suggestions[0].reason, "Fits the coffee and laptop theme")
        XCTAssertEqual(rpc.calls.map(\.name), ["function:suggest-list-places"])
        XCTAssertEqual(rpc.rawBodies[0]["list_id"] as? String, "list_laptop")
        XCTAssertEqual(rpc.rawBodies[0]["title"] as? String, "LA laptop mornings")
        XCTAssertEqual(rpc.rawBodies[0]["limit"] as? Int, 4)
    }

    func testPlacePhotoRepositoryInvokesEdgeFunctionAndMapsAttribution() async throws {
        let rpc = RecordingRPC()
        rpc.responses["function:place-photo"] = """
        {
          "provider": "google_places",
          "provider_place_id": "ChIJwoodcat",
          "photo_url": "https://lh3.googleusercontent.com/example",
          "width": 1600,
          "height": 1000,
          "author_name": "Woodcat Coffee",
          "author_profile_url": "https://maps.google.com/maps/contrib/example",
          "author_avatar_url": "https://lh3.googleusercontent.com/avatar",
          "source_photo_url": "https://www.google.com/maps/photos/example",
          "flag_content_url": "https://www.google.com/maps/photos/flag/example"
        }
        """.data(using: .utf8)
        let repository = SupabasePlacePhotoRepository(functions: rpc)
        let request = PlacePhotoRequest(
            name: "Woodcat Coffee",
            address: "1532 Sunset Blvd, Los Angeles, CA",
            latitude: 34.0777,
            longitude: -118.2588,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-woodcat"
        )

        let photo = try await repository.photo(for: request)

        XCTAssertEqual(photo.provider, "google_places")
        XCTAssertEqual(photo.providerPlaceID, "ChIJwoodcat")
        XCTAssertEqual(photo.authorName, "Woodcat Coffee")
        XCTAssertEqual(photo.sourcePhotoURL?.host, "www.google.com")
        XCTAssertEqual(rpc.calls.map(\.name), ["function:place-photo"])
        XCTAssertEqual(rpc.rawBodies[0]["name"] as? String, "Woodcat Coffee")
        XCTAssertEqual(rpc.rawBodies[0]["source_provider"] as? String, "mapkit")
        XCTAssertEqual(rpc.rawBodies[0]["source_provider_place_id"] as? String, "mapkit-woodcat")
        XCTAssertEqual(rpc.rawBodies[0]["requires_photo"] as? Bool, true)
        XCTAssertEqual(
            try XCTUnwrap(rpc.rawBodies[0]["latitude"] as? Double),
            34.0777,
            accuracy: 0.00001
        )
    }

    func testPlaceProviderMetadataRequestDoesNotRequireAProviderPhoto() async throws {
        let rpc = RecordingRPC()
        rpc.responses["function:place-photo"] = """
        {
          "provider": "google_places",
          "provider_place_id": "ChIJugo",
          "provider_primary_type": "italian_restaurant",
          "provider_types": ["italian_restaurant", "restaurant", "food"],
          "photo_url": ""
        }
        """.data(using: .utf8)
        let repository = SupabasePlacePhotoRepository(functions: rpc)
        let request = PlacePhotoRequest(
            name: "Ugo",
            address: "3865 Cardiff Ave, Culver City, CA",
            latitude: 34.0223,
            longitude: -118.3952,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-ugo",
            requiresPhoto: false
        )

        let metadata = try await repository.photo(for: request)

        XCTAssertEqual(metadata.providerPlaceID, "ChIJugo")
        XCTAssertEqual(metadata.providerPrimaryType, "italian_restaurant")
        XCTAssertEqual(metadata.providerTypes, ["italian_restaurant", "restaurant", "food"])
        XCTAssertNil(metadata.photoURL)
        XCTAssertEqual(rpc.calls.map(\.name), ["function:place-photo"])
        XCTAssertEqual(rpc.rawBodies[0]["requires_photo"] as? Bool, false)
    }

    func testPlacePhotoRepositoryFallsBackToFirstVisibleVisitPhotoAndAuthenticatedStorage() async throws {
        let rpc = RecordingRPC()
        rpc.responses["first_visible_place_photo"] = """
        [{
          "photo_id": "55000000-0000-0000-0000-000000000001",
          "storage_bucket": "visit-photos",
          "storage_path": "user_joe/54000000-0000-0000-0000-000000000001/55000000-0000-0000-0000-000000000001.jpg",
          "width": 1200,
          "height": 900
        }]
        """.data(using: .utf8)
        let storage = RecordingStorage()
        storage.downloadData = Data([0xFF, 0xD8, 0xFF])
        let repository = SupabasePlacePhotoRepository(rpc: rpc, functions: rpc, storage: storage)
        let request = PlacePhotoRequest(
            placeID: "50000000-0000-0000-0000-000000000001",
            name: "Dropped pin",
            address: "34.09435, -118.44982",
            latitude: 34.09435,
            longitude: -118.44982,
            sourceProvider: "manual",
            sourceProviderPlaceID: nil
        )

        let photo = try await repository.photo(for: request)
        let data = try await repository.imageData(for: photo)

        XCTAssertEqual(photo.provider, "visit_photo")
        XCTAssertEqual(photo.providerPlaceID, "55000000-0000-0000-0000-000000000001")
        XCTAssertEqual(photo.storageBucket, "visit-photos")
        XCTAssertEqual(data, Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(rpc.calls.map(\.name), ["first_visible_place_photo"])
        XCTAssertEqual(rpc.rawBodies[0]["input_place_id"] as? String, "50000000-0000-0000-0000-000000000001")
        XCTAssertEqual(storage.downloads.map(\.path), ["user_joe/54000000-0000-0000-0000-000000000001/55000000-0000-0000-0000-000000000001.jpg"])
    }

    func testPlacePhotoRepositoryScopesVisiblePhotoToListContributors() async throws {
        let rpc = RecordingRPC()
        rpc.responses["first_visible_place_photo_by_users"] = """
        [{
          "photo_id": "55000000-0000-0000-0000-000000000003",
          "storage_bucket": "visit-photos",
          "storage_path": "user_collaborator/list-cover.jpg",
          "width": 900,
          "height": 900
        }]
        """.data(using: .utf8)
        let repository = SupabasePlacePhotoRepository(
            rpc: rpc,
            functions: rpc,
            storage: RecordingStorage()
        )
        let request = PlacePhotoRequest(
            placeID: "50000000-0000-0000-0000-000000000003",
            name: "List cover place",
            address: "Los Angeles, CA",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "list-cover-place"
        )

        let photo = try await repository.visibleUserPhoto(
            for: request.restrictingVisibleUserPhotos(
                to: [" user_owner ", "user_collaborator", "user_owner", ""]
            )
        )

        XCTAssertEqual(photo.providerPlaceID, "55000000-0000-0000-0000-000000000003")
        XCTAssertEqual(rpc.calls.map(\.name), ["first_visible_place_photo_by_users"])
        XCTAssertEqual(
            rpc.rawBodies[0]["input_place_id"] as? String,
            "50000000-0000-0000-0000-000000000003"
        )
        XCTAssertEqual(
            rpc.rawBodies[0]["input_user_ids"] as? [String],
            ["user_collaborator", "user_owner"]
        )
    }

    func testPlacePhotoRepositoryMapsPaginatedVisibleGalleryWithContributorIdentity() async throws {
        let rpc = RecordingRPC()
        rpc.responses["visible_place_photos"] = """
        [{
          "photo_id": "55000000-0000-0000-0000-000000000133",
          "storage_bucket": "visit-photos",
          "storage_path": "user_maya/54000000-0000-0000-0000-000000000133/55000000-0000-0000-0000-000000000133.jpg",
          "width": 1200,
          "height": 1600,
          "captured_at": "2026-07-22T18:15:00Z",
          "created_at": "2026-07-22T18:20:00Z",
          "sort_order": 2,
          "contributor_user_id": "user_maya",
          "contributor_display_name": "Maya Patel",
          "contributor_handle": "mayap",
          "contributor_avatar_url": "https://example.com/maya.jpg",
          "status": "been"
        }]
        """.data(using: .utf8)
        let repository = SupabasePlacePhotoRepository(
            rpc: rpc,
            functions: rpc,
            storage: RecordingStorage()
        )
        let cursor = PlacePhotoGalleryCursor(
            createdAt: try XCTUnwrap(
                ISO8601DateFormatter().date(from: "2026-07-22T17:00:00Z")
            ),
            sortOrder: 1,
            photoID: "55000000-0000-0000-0000-000000000132"
        )

        let page = try await repository.visiblePhotoGalleryPage(
            placeID: "50000000-0000-0000-0000-000000000133",
            after: cursor,
            limit: 1
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].photo.provider, "visit_photo")
        XCTAssertEqual(page.items[0].contributor?.userID, "user_maya")
        XCTAssertEqual(page.items[0].contributor?.handle, "mayap")
        XCTAssertEqual(page.items[0].status, .been)
        XCTAssertEqual(page.nextCursor?.photoID, "55000000-0000-0000-0000-000000000133")
        XCTAssertEqual(page.nextCursor?.sortOrder, 2)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(rpc.calls.map(\.name), ["visible_place_photos"])
        XCTAssertEqual(
            rpc.rawBodies[0]["input_place_id"] as? String,
            "50000000-0000-0000-0000-000000000133"
        )
        XCTAssertEqual(rpc.rawBodies[0]["input_after_sort_order"] as? Int, 1)
        XCTAssertEqual(
            rpc.rawBodies[0]["input_after_photo_id"] as? String,
            "55000000-0000-0000-0000-000000000132"
        )
        XCTAssertEqual(rpc.rawBodies[0]["input_limit"] as? Int, 1)
        XCTAssertNotNil(rpc.rawBodies[0]["input_after_created_at"] as? String)
    }

    func testCoordinatePlacePhotoRequestBypassesGoogleFunction() async throws {
        let rpc = RecordingRPC()
        rpc.responses["first_visible_place_photo"] = """
        [{
          "photo_id": "55000000-0000-0000-0000-000000000002",
          "storage_bucket": "visit-photos",
          "storage_path": "user_joe/coordinate.jpg",
          "width": 900,
          "height": 1200
        }]
        """.data(using: .utf8)
        let repository = SupabasePlacePhotoRepository(rpc: rpc, functions: rpc, storage: RecordingStorage())
        let request = PlacePhotoRequest(
            placeID: "50000000-0000-0000-0000-000000000002",
            name: "A custom pin",
            address: "34.09435, -118.44982",
            latitude: 34.09435,
            longitude: -118.44982,
            sourceProvider: "coordinate",
            sourceProviderPlaceID: "coordinate_34.09435_-118.44982"
        )

        let photo = try await repository.photo(for: request)

        XCTAssertEqual(photo.provider, "visit_photo")
        XCTAssertEqual(rpc.calls.map(\.name), ["first_visible_place_photo"])
    }

    func testPlacePhotoLookupKeyUsesProviderIdentityAndCoordinates() {
        let request = PlacePhotoRequest(
            name: "Woodcat Coffee",
            address: nil,
            latitude: 34.077712,
            longitude: -118.258812,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "ChIJwoodcat"
        )

        XCTAssertEqual(
            request.lookupKey,
            "google_maps|chijwoodcat|woodcat coffee|34.07771,-118.25881"
        )
    }

    func testProviderMetadataLookupKeyDoesNotCollideWithPhotoLookup() {
        let request = PlacePhotoRequest(
            name: "Ugo",
            address: nil,
            latitude: 34.0223,
            longitude: -118.3952,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-ugo",
            requiresPhoto: false
        )

        XCTAssertEqual(
            request.lookupKey,
            "mapkit|mapkit-ugo|ugo|34.02230,-118.39520|metadata-only"
        )
    }

    func testDroppedPinPhotoRequestSkipsGooglePlacesLookup() {
        let request = PlacePhotoRequest(
            name: "Dropped pin",
            address: "34.09435, -118.44982",
            latitude: 34.09435,
            longitude: -118.44982,
            sourceProvider: "manual",
            sourceProviderPlaceID: nil
        )

        XCTAssertTrue(request.skipsGooglePlacesLookup)
    }

    func testNotificationRepositoryCallsPreferenceAndTokenRPCs() async throws {
        let rpc = RecordingRPC()
        rpc.responses["get_notification_preferences"] = """
        {
          "push_enabled": true,
          "social_graph_enabled": true,
          "shared_lists_enabled": true,
          "shared_visits_enabled": true,
          "recommendations_enabled": true,
          "capture_enabled": true,
          "discovery_digest_enabled": false,
          "followed_activity_enabled": true,
          "wanna_go_reminders_enabled": false
        }
        """.data(using: .utf8)
        rpc.responses["update_notification_preferences"] = """
        {
          "push_enabled": true,
          "social_graph_enabled": true,
          "shared_lists_enabled": true,
          "shared_visits_enabled": true,
          "recommendations_enabled": true,
          "capture_enabled": true,
          "discovery_digest_enabled": true,
          "followed_activity_enabled": false,
          "wanna_go_reminders_enabled": true
        }
        """.data(using: .utf8)
        rpc.responses["register_push_token"] = #""token-row-id""#.data(using: .utf8)
        let repository = SupabaseNotificationRepository(rpc: rpc)

        let preferences = try await repository.preferences()
        let updated = try await repository.updatePreferences(
            NotificationPreferencesUpdate(
                discoveryDigestEnabled: true,
                followedActivityEnabled: false,
                wannaGoRemindersEnabled: true
            )
        )
        let tokenID = try await repository.registerPushToken(
            "abcdef1234567890",
            environment: .sandbox,
            appBundleID: "com.grayline.wander"
        )
        try await repository.unregisterPushToken("abcdef1234567890", environment: .sandbox)

        XCTAssertTrue(preferences.socialGraphEnabled)
        XCTAssertTrue(preferences.sharedVisitsEnabled)
        XCTAssertTrue(preferences.followedActivityEnabled)
        XCTAssertFalse(preferences.discoveryDigestEnabled)
        XCTAssertFalse(preferences.wannaGoRemindersEnabled)
        XCTAssertTrue(updated.discoveryDigestEnabled)
        XCTAssertFalse(updated.followedActivityEnabled)
        XCTAssertTrue(updated.wannaGoRemindersEnabled)
        XCTAssertEqual(tokenID, "token-row-id")
        XCTAssertEqual(
            rpc.calls.map(\.name),
            [
                "get_notification_preferences",
                "update_notification_preferences",
                "register_push_token",
                "unregister_push_token"
            ]
        )

        let updatePayload = rpc.rawBodies[1]["input_preferences"] as? [String: Any]
        XCTAssertEqual(updatePayload?["discovery_digest_enabled"] as? Bool, true)
        XCTAssertEqual(updatePayload?["followed_activity_enabled"] as? Bool, false)
        XCTAssertEqual(updatePayload?["wanna_go_reminders_enabled"] as? Bool, true)

        XCTAssertEqual(rpc.rawBodies[2]["input_device_token"] as? String, "abcdef1234567890")
        XCTAssertEqual(rpc.rawBodies[2]["input_environment"] as? String, "sandbox")
        XCTAssertEqual(rpc.rawBodies[2]["input_app_bundle_id"] as? String, "com.grayline.wander")

        XCTAssertEqual(rpc.rawBodies[3]["input_device_token"] as? String, "abcdef1234567890")
        XCTAssertEqual(rpc.rawBodies[3]["input_environment"] as? String, "sandbox")
    }

    func testSharedVisitRepositoryLoadsAndReconcilesExactInviteeSet() async throws {
        let rpc = RecordingRPC()
        rpc.responses["list_shared_visit_invitees"] = """
        [
          {
            "invitee_user_id": "user_sarah",
            "participant_status": "pending",
            "invitation_generation": 1
          }
        ]
        """.data(using: .utf8)
        rpc.responses["set_shared_visit_invitees"] = """
        [
          {
            "participant_id": "48000000-0000-0000-0000-000000000001",
            "invitee_user_id": "user_maya",
            "participant_status": "pending",
            "invitation_generation": 2
          }
        ]
        """.data(using: .utf8)
        let repository = SupabaseSharedVisitRepository(
            rpc: rpc,
            table: RecordingTable(),
            storage: RecordingStorage()
        )

        let existingInviteeUserIDs = try await repository.inviteeUserIDs(
            sourceVisitID: "83000000-0000-0000-0000-000000000001"
        )
        let reconciled = try await repository.setInvitees(
            sourceVisitID: "83000000-0000-0000-0000-000000000001",
            inviteeUserIDs: ["user_maya"]
        )

        XCTAssertEqual(existingInviteeUserIDs, ["user_sarah"])
        XCTAssertEqual(reconciled.map(\.inviteeUserID), ["user_maya"])
        XCTAssertEqual(reconciled.map(\.invitationGeneration), [2])
        XCTAssertEqual(
            rpc.calls.map(\.name),
            ["list_shared_visit_invitees", "set_shared_visit_invitees"]
        )
        XCTAssertEqual(
            rpc.rawBodies[0]["input_source_visit_id"] as? String,
            "83000000-0000-0000-0000-000000000001"
        )
        XCTAssertEqual(rpc.rawBodies[1]["input_invitee_user_ids"] as? [String], ["user_maya"])
    }

    func testSharedVisitAcceptanceEncodesNestedVisitTimestampAsISO8601() async throws {
        let rpc = RecordingRPC()
        rpc.responses["accept_shared_visit"] = """
        {
          "operation_id": "48000000-0000-0000-0000-000000000010",
          "participant_id": "48000000-0000-0000-0000-000000000001",
          "user_place_id": "82000000-0000-0000-0000-000000000010",
          "visit_id": "83000000-0000-0000-0000-000000000010",
          "backfilled_from_user_place": false,
          "status": "accepted",
          "photo_copies": []
        }
        """.data(using: .utf8)
        let repository = SupabaseSharedVisitRepository(
            rpc: rpc,
            table: RecordingTable(),
            storage: RecordingStorage()
        )
        let visitedAt = Date(timeIntervalSince1970: 1_786_665_600)

        _ = try await repository.accept(
            SharedVisitAcceptanceDraft(
                participantID: "48000000-0000-0000-0000-000000000001",
                invitationGeneration: 1,
                snapshotRevision: 2,
                operationID: "48000000-0000-0000-0000-000000000010",
                userPlaceID: "82000000-0000-0000-0000-000000000010",
                visitID: "83000000-0000-0000-0000-000000000010",
                visibility: .mutuals,
                visitedAt: visitedAt,
                note: "Recipient copy",
                ratingScore: 4.5,
                attributes: [],
                selectedPhotoIDs: []
            )
        )

        let visitPayload = try XCTUnwrap(rpc.rawBodies.first?["input_visit"] as? [String: Any])
        let encodedTimestamp = try XCTUnwrap(visitPayload["visited_at"] as? String)
        let decodedTimestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: encodedTimestamp))
        XCTAssertEqual(decodedTimestamp.timeIntervalSince1970, visitedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(visitPayload["visited_at"] as? Double)
    }

    func testPushNotificationDeviceTokenHexEncoding() {
        XCTAssertEqual(PushNotificationManager.hexString(from: Data([0x00, 0x0A, 0xFF])), "000aff")
    }

    func testPushNotificationDeliveryRequiresValidatedAuthenticatedSession() {
        defer { WanderAppDelegate.setAuthenticatedSessionSignedOut() }

        WanderAppDelegate.beginAuthenticatedSessionValidation(expectedUserID: "user_a")
        XCTAssertFalse(WanderAppDelegate.shouldAcceptAuthenticatedNotification())
        XCTAssertTrue(WanderAppDelegate.shouldBufferAuthenticatedNotification())

        WanderAppDelegate.setAuthenticatedSessionSignedOut()
        XCTAssertFalse(WanderAppDelegate.shouldAcceptAuthenticatedNotification())
        XCTAssertFalse(WanderAppDelegate.shouldBufferAuthenticatedNotification())

        WanderAppDelegate.setAuthenticatedSessionActive(userID: "user_a")
        XCTAssertTrue(WanderAppDelegate.shouldAcceptAuthenticatedNotification())
        XCTAssertFalse(WanderAppDelegate.shouldBufferAuthenticatedNotification())
    }

    func testUnknownNotificationResponseOnlyReleasesToExpectedAccount() {
        defer { WanderAppDelegate.setAuthenticatedSessionSignedOut() }
        let accountAUserInfo: [AnyHashable: Any] = ["recme": ["event_id": "event_a"]]

        WanderAppDelegate.beginAuthenticatedSessionValidation(expectedUserID: "user_a")
        XCTAssertNil(WanderAppDelegate.receiveAuthenticatedNotificationUserInfo(accountAUserInfo))

        WanderAppDelegate.setAuthenticatedSessionActive(userID: "user_b")
        XCTAssertNil(WanderAppDelegate.takePendingNotificationUserInfo(for: "user_b"))
        XCTAssertNil(WanderAppDelegate.takePendingNotificationUserInfo(for: "user_a"))

        WanderAppDelegate.beginAuthenticatedSessionValidation(expectedUserID: "user_a")
        XCTAssertNil(WanderAppDelegate.receiveAuthenticatedNotificationUserInfo(accountAUserInfo))
        WanderAppDelegate.setAuthenticatedSessionActive(userID: "user_a")
        XCTAssertEqual(
            WanderAppDelegate.takePendingNotificationUserInfo(for: "user_a")?["recme"] as? [String: String],
            ["event_id": "event_a"]
        )
    }

    func testNotificationResponseDeduplicatesBufferedAndDeliveredCopy() {
        let manager = PushNotificationManager()
        let userInfo: [AnyHashable: Any] = [
            "recme": [
                "event_id": "notification-event-1",
                "notification_type": "shared_visit",
                "data": [
                    "participant_id": "48000000-0000-0000-0000-000000000001",
                    "invitation_generation": 3
                ]
            ]
        ]

        XCTAssertTrue(manager.handleNotificationResponse(userInfo: userInfo))
        let firstRequest = manager.navigationRequest
        XCTAssertFalse(manager.handleNotificationResponse(userInfo: userInfo))
        XCTAssertEqual(manager.navigationRequest, firstRequest)
        XCTAssertEqual(
            manager.navigationRequest?.destination,
            .sharedVisit(
                participantID: "48000000-0000-0000-0000-000000000001",
                generation: 3
            )
        )
    }

    func testNotificationPreferencePresetsToggleEveryTypeTogether() {
        XCTAssertEqual(
            NotificationPreferences.allEnabled,
            NotificationPreferences(
                pushEnabled: true,
                socialGraphEnabled: true,
                sharedListsEnabled: true,
                sharedVisitsEnabled: true,
                recommendationsEnabled: true,
                captureEnabled: true,
                discoveryDigestEnabled: true,
                followedActivityEnabled: true,
                wannaGoRemindersEnabled: true
            )
        )
        XCTAssertEqual(NotificationPreferences.allDisabled, NotificationPreferences(
            pushEnabled: false,
            socialGraphEnabled: false,
            sharedListsEnabled: false,
            sharedVisitsEnabled: false,
            recommendationsEnabled: false,
            captureEnabled: false,
            discoveryDigestEnabled: false,
            followedActivityEnabled: false,
            wannaGoRemindersEnabled: false
        ))
    }

    func testNotificationDeeplinksMapToConcreteAppDestinations() {
        XCTAssertEqual(
            PushNotificationManager.destination(
                from: URL(string: "recme://profiles/user_joe")!,
                notificationType: "mutual_follow"
            ),
            .people(.friends)
        )
        XCTAssertEqual(
            PushNotificationManager.destination(from: URL(string: "recme://lists/44000000-0000-0000-0000-000000000001")!),
            .list(id: "44000000-0000-0000-0000-000000000001")
        )
        XCTAssertEqual(
            PushNotificationManager.destination(from: URL(string: "recme://places/40000000-0000-0000-0000-000000000001")!),
            .place(id: "40000000-0000-0000-0000-000000000001")
        )
        XCTAssertEqual(
            PushNotificationManager.destination(
                from: URL(string: "recme://shared-visits/48000000-0000-0000-0000-000000000001?generation=3")!
            ),
            .sharedVisit(participantID: "48000000-0000-0000-0000-000000000001", generation: 3)
        )
        XCTAssertEqual(
            PushNotificationManager.destination(from: URL(string: "recme://extraction-jobs/43000000-0000-0000-0000-000000000001")!),
            .drafts(extractionJobID: "43000000-0000-0000-0000-000000000001")
        )
    }

    func testNotificationPayloadFallsBackToTypeDataWhenDeeplinkIsMissing() {
        let userInfo: [AnyHashable: Any] = [
            "recme": [
                "notification_type": "place_saved_from_your_map",
                "data": ["place_id": "place_bar_nido"]
            ]
        ]

        XCTAssertEqual(
            PushNotificationManager.destination(from: userInfo),
            .place(id: "place_bar_nido")
        )
    }

    func testEveryNotificationTypeHasAnAppDestination() {
        func destination(_ type: String, data: [String: Any] = [:]) -> NotificationDestination? {
            PushNotificationManager.destination(from: [
                "recme": ["notification_type": type, "data": data]
            ])
        }

        XCTAssertEqual(destination("followed_you"), .people(.followers))
        XCTAssertEqual(destination("mutual_follow"), .people(.friends))
        XCTAssertEqual(destination("list_collaborator_added", data: ["list_id": "list-1"]), .list(id: "list-1"))
        XCTAssertEqual(destination("list_place_added", data: ["list_id": "list-1"]), .list(id: "list-1"))
        XCTAssertEqual(destination("place_saved_from_your_map", data: ["place_id": "place-1"]), .place(id: "place-1"))
        XCTAssertEqual(destination("followed_place_visit", data: ["place_id": "place-1"]), .place(id: "place-1"))
        XCTAssertEqual(destination("wanna_go_reminder", data: ["place_id": "place-1"]), .place(id: "place-1"))
        XCTAssertEqual(
            destination(
                "shared_visit",
                data: ["participant_id": "participant-1", "invitation_generation": 4]
            ),
            .sharedVisit(participantID: "participant-1", generation: 4)
        )
        XCTAssertEqual(destination("capture_ready", data: ["extraction_job_id": "job-1"]), .drafts(extractionJobID: "job-1"))
        XCTAssertEqual(destination("followed_activity_digest"), .discover)
    }

    func testSharedVisitAcceptanceIdentifiersAreStableAndGenerationScoped() {
        let first = SharedVisitAcceptanceIdentifiers.deterministic(
            participantID: "48000000-0000-0000-0000-000000000001",
            generation: 1
        )
        let retry = SharedVisitAcceptanceIdentifiers.deterministic(
            participantID: "48000000-0000-0000-0000-000000000001",
            generation: 1
        )
        let reinvite = SharedVisitAcceptanceIdentifiers.deterministic(
            participantID: "48000000-0000-0000-0000-000000000001",
            generation: 2
        )

        XCTAssertEqual(first, retry)
        XCTAssertNotEqual(first, reinvite)
        XCTAssertNotNil(UUID(uuidString: first.operationID))
        XCTAssertNotNil(UUID(uuidString: first.userPlaceID))
        XCTAssertNotNil(UUID(uuidString: first.visitID))
        XCTAssertEqual(Set([first.operationID, first.userPlaceID, first.visitID]).count, 3)
    }

    func testRemoteDiscoverFilterParserFallsBackToDeterministicParser() async throws {
        let parser = RemoteDiscoverFilterParser(repository: FailingDiscoverFilterRepository())

        let filters = try await parser.parse(
            query: "Joe's favorite coffee spots in LA",
            schema: DiscoverFilterSchema(allowedCategories: [WanderPlaceCategory.coffeeTeaSweets])
        )

        XCTAssertEqual(filters.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(filters.statuses, [.been])
        XCTAssertEqual(filters.ownerQuery, "joe")
        XCTAssertEqual(filters.opinion, .favorite)
        XCTAssertEqual(filters.sort, .ownerRatingDescending)
        XCTAssertEqual(parser.parseSource, .deterministicFallback)
    }
}

private struct FeedRPCProbeParameters: Encodable {
    let marker = "photo-retry-probe"
}

private struct FeedRPCProbe: Decodable, Equatable {
    let value: String
}

@MainActor
private final class FeedTokenAuthSession: AuthSessionProviding {
    private(set) var state: AuthState = .signedIn(
        AuthSession(userID: "user_test", displayName: "Test", handle: "test")
    )
    let canPresentNativeAuth = false
    private(set) var cachedTokenRequestCount = 0
    private(set) var forcedTokenRequestCount = 0
    private var forcedTokens: [String]
    private var forcedRefreshFailuresRemaining: Int
    private let pausesForcedRefresh: Bool
    private let switchesUserDuringForcedRefresh: Bool
    private var forcedRefreshGateIsOpen = false
    private var pausedForcedRefreshes: [CheckedContinuation<Void, Never>] = []

    init(
        forcedTokens: [String] = ["fresh-token"],
        forcedRefreshFailuresRemaining: Int = 0,
        pausesForcedRefresh: Bool = false,
        switchesUserDuringForcedRefresh: Bool = false
    ) {
        self.forcedTokens = forcedTokens
        self.forcedRefreshFailuresRemaining = forcedRefreshFailuresRemaining
        self.pausesForcedRefresh = pausesForcedRefresh
        self.switchesUserDuringForcedRefresh = switchesUserDuringForcedRefresh
    }

    func sessionChanges() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func refreshSession() async {}
    func signOut() async throws {}
    func deleteAccount() async throws {}

    func supabaseAccessToken() async throws -> String {
        cachedTokenRequestCount += 1
        return "cached-token"
    }

    func refreshSupabaseAccessToken() async throws -> String {
        forcedTokenRequestCount += 1
        if pausesForcedRefresh, !forcedRefreshGateIsOpen {
            await withCheckedContinuation { continuation in
                pausedForcedRefreshes.append(continuation)
            }
        }
        if forcedRefreshFailuresRemaining > 0 {
            forcedRefreshFailuresRemaining -= 1
            throw AuthSessionError.tokenUnavailable
        }
        if switchesUserDuringForcedRefresh {
            state = .signedIn(
                AuthSession(userID: "user_other", displayName: "Other", handle: "other")
            )
        }
        if forcedTokens.count > 1 {
            return forcedTokens.removeFirst()
        }
        return forcedTokens.first ?? "fresh-token"
    }

    func waitForForcedRefreshToStart() async throws {
        for _ in 0..<1_000 {
            if forcedTokenRequestCount > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for the forced token refresh to start")
        throw URLError(.timedOut)
    }

    func releaseForcedRefreshes() {
        forcedRefreshGateIsOpen = true
        let pausedRefreshes = pausedForcedRefreshes
        pausedForcedRefreshes = []
        pausedRefreshes.forEach { $0.resume() }
    }

    func switchUser(to userID: String) {
        state = .signedIn(
            AuthSession(userID: userID, displayName: "Other", handle: "other")
        )
    }
}

private final class FeedRPCURLProtocol: URLProtocol {
    private struct HeldResponse {
        let loader: FeedRPCURLProtocol
        let statusCode: Int
        let data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queuedResponses: [(statusCode: Int, data: Data)] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var bodies: [Data?] = []
    nonisolated(unsafe) private static var heldResponseIndices: Set<Int> = []
    nonisolated(unsafe) private static var heldResponses: [HeldResponse] = []

    static func reset(
        responses: [(Int, Data)],
        heldResponseIndices: Set<Int> = []
    ) {
        lock.lock()
        defer { lock.unlock() }
        queuedResponses = responses.map { (statusCode: $0.0, data: $0.1) }
        requests = []
        bodies = []
        self.heldResponseIndices = heldResponseIndices
        heldResponses = []
    }

    static var authorizationHeaders: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    static var requestPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap { $0.url?.path }
    }

    static var requestBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return bodies.compactMap { $0 }
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    static func releaseHeldResponses() {
        lock.lock()
        let responses = heldResponses
        heldResponses = []
        lock.unlock()
        responses.forEach { response in
            response.loader.deliver(statusCode: response.statusCode, data: response.data)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.lock.lock()
        let requestIndex = Self.requests.count
        Self.requests.append(request)
        Self.bodies.append(body)
        let next = Self.queuedResponses.isEmpty ? nil : Self.queuedResponses.removeFirst()
        if let next, Self.heldResponseIndices.contains(requestIndex) {
            Self.heldResponses.append(
                HeldResponse(loader: self, statusCode: next.statusCode, data: next.data)
            )
            Self.lock.unlock()
            return
        }
        Self.lock.unlock()

        guard let next else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        deliver(statusCode: next.statusCode, data: next.data)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var body = Data()
        while true {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else {
                break
            }
            body.append(buffer, count: bytesRead)
        }
        return body
    }

    private func deliver(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private final class RecordingStorage: RemoteStorageCalling {
    struct Upload: Equatable {
        let bucket: String
        let path: String
        let data: Data
        let contentType: String
        let upsert: Bool
    }

    struct Delete: Equatable {
        let bucket: String
        let path: String
    }

    private(set) var uploads: [Upload] = []
    private(set) var deletes: [Delete] = []
    private(set) var downloads: [Delete] = []
    private(set) var signedURLs: [Delete] = []
    var downloadData = Data()

    func uploadObject(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        upsert: Bool
    ) async throws {
        uploads.append(
            Upload(
                bucket: bucket,
                path: path,
                data: data,
                contentType: contentType,
                upsert: upsert
            )
        )
    }

    func deleteObject(bucket: String, path: String) async throws {
        deletes.append(Delete(bucket: bucket, path: path))
    }

    func downloadObject(bucket: String, path: String) async throws -> Data {
        downloads.append(Delete(bucket: bucket, path: path))
        return downloadData
    }

    func signedObjectURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        signedURLs.append(Delete(bucket: bucket, path: path))
        return URL(string: "https://example.supabase.co/storage/v1/object/sign/\(bucket)/\(path)?token=test")!
    }

    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL {
        var url = URL(string: "https://example.supabase.co/storage/v1/object/public/\(bucket)/\(path)")!
        if let cacheBust {
            url = URL(string: "\(url.absoluteString)?v=\(cacheBust)")!
        }
        return url
    }
}

@MainActor
private final class RecordingTable: RemoteTableCalling {
    struct Call: Equatable {
        let method: String
        let table: String
        let queryItems: [URLQueryItem]

        var key: String { "\(method):\(table)" }
    }

    var responses: [String: Data] = [:]
    private(set) var calls: [Call] = []
    private(set) var rawBodies: [Any] = []

    func select<Value: Decodable>(
        table: String,
        queryItems: [URLQueryItem],
        decoder: JSONDecoder
    ) async throws -> Value {
        try response(method: "GET", table: table, queryItems: queryItems, decoder: decoder)
    }

    func upsert<Value: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        onConflict: String?,
        decoder: JSONDecoder
    ) async throws -> Value {
        var queryItems: [URLQueryItem] = []
        if let onConflict {
            queryItems.append(URLQueryItem(name: "on_conflict", value: onConflict))
        }
        rawBodies.append(try encodedObject(body))
        return try response(method: "POST", table: table, queryItems: queryItems, decoder: decoder)
    }

    func update<Value: Decodable, Body: Encodable>(
        table: String,
        queryItems: [URLQueryItem],
        body: Body,
        decoder: JSONDecoder
    ) async throws -> Value {
        rawBodies.append(try encodedObject(body))
        return try response(method: "PATCH", table: table, queryItems: queryItems, decoder: decoder)
    }

    func delete(table: String, queryItems: [URLQueryItem]) async throws {
        calls.append(Call(method: "DELETE", table: table, queryItems: queryItems))
    }

    private func response<Value: Decodable>(
        method: String,
        table: String,
        queryItems: [URLQueryItem],
        decoder: JSONDecoder
    ) throws -> Value {
        calls.append(Call(method: method, table: table, queryItems: queryItems))
        guard let data = responses["\(method):\(table)"] else {
            throw WanderRemoteError.invalidResponse("Missing fake table response for \(method):\(table)")
        }
        return try decoder.decode(Value.self, from: data)
    }

    private func encodedObject<Body: Encodable>(_ body: Body) throws -> Any {
        let data = try RemoteEncoding.encoder.encode(body)
        return try JSONSerialization.jsonObject(with: data)
    }
}

@MainActor
private struct FailingDiscoverFilterRepository: DiscoverFilterParsingRepository {
    func parseFilters(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        throw WanderRemoteError.invalidResponse("expected failure")
    }
}

@MainActor
private final class RecordingRPC: RemoteProcedureCalling, RemoteFunctionCalling, RemoteUserPlaceDeleting {
    struct Call: Equatable {
        let name: String
        let body: [String: AnyHashable]
    }

    var responses: [String: Data] = [:]
    private(set) var rawBodies: [[String: Any]] = []
    private(set) var calls: [Call] = []
    private(set) var deletedUserPlaceIDs: [String] = []

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

    func deleteUserPlace(userPlaceID: String) async throws {
        deletedUserPlaceIDs.append(userPlaceID)
    }

    private func encodedObject<Params: Encodable>(_ params: Params) throws -> [String: Any] {
        let data = try WanderSupabaseClient.encodeRequestBody(params)
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
