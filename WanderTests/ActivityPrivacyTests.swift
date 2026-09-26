import XCTest
@testable import Wander

final class ActivityPrivacyTests: XCTestCase {
    private let policy = VisibilityPolicy()

    func testPublicAndPrivateAudienceMatrixUsesOnlyAcceptedFollows() {
        let expectations: [(ActivityAudience, Bool, Set<ActivityFollowAccess>)] = [
            (.account, false, [.none, .requested, .following, .mutual]),
            (.account, true, [.following, .mutual]),
            (.followers, false, [.following, .mutual]),
            (.followers, true, [.following, .mutual]),
            (.mutuals, false, [.mutual]),
            (.mutuals, true, [.mutual]),
            (.selfOnly, false, []),
            (.selfOnly, true, [])
        ]

        for (audience, isPrivate, allowed) in expectations {
            for relationship in ActivityFollowAccess.allCases {
                XCTAssertEqual(policy.canSeeActivity(context(
                    audience: audience, isPrivate: isPrivate, follow: relationship
                )), allowed.contains(relationship), "\(audience), private=\(isPrivate), \(relationship)")
            }
        }
    }

    func testEveryDenyOverridesAccountAudienceAndAcceptedFollows() {
        for audience in ActivityAudience.allCases {
            for isPrivate in [false, true] {
                for follow in ActivityFollowAccess.allCases {
                    for (accountExcluded, activityExcluded, blocked, deleted) in [
                        (true, false, false, false),
                        (false, true, false, false),
                        (true, true, false, false),
                        (false, false, true, false),
                        (false, false, false, true)
                    ] {
                        XCTAssertFalse(policy.canSeeActivity(context(
                            audience: audience, isPrivate: isPrivate, follow: follow,
                            accountExcluded: accountExcluded, activityExcluded: activityExcluded,
                            blocked: blocked, deleted: deleted
                        )))
                    }
                }
            }
        }
    }

    func testHidingOneVisitDoesNotHideAnotherVisitToTheSamePlace() {
        XCTAssertFalse(policy.canSeeActivity(context(activityExcluded: true)))
        XCTAssertTrue(policy.canSeeActivity(context(activityExcluded: false)))
    }

    func testRemovingAccountExclusionDoesNotRemoveIndependentActivityExclusion() {
        XCTAssertFalse(policy.canSeeActivity(context(accountExcluded: true, activityExcluded: true)))
        XCTAssertFalse(policy.canSeeActivity(context(accountExcluded: false, activityExcluded: true)))
        XCTAssertTrue(policy.canSeeActivity(context(accountExcluded: false, activityExcluded: false)))
    }

    func testPrivacyToggleChangesAccessWithoutRewritingAudience() {
        XCTAssertTrue(policy.canSeeActivity(context(isPrivate: false, follow: .none)))
        XCTAssertFalse(policy.canSeeActivity(context(isPrivate: true, follow: .none)))
        XCTAssertTrue(policy.canSeeActivity(context(isPrivate: true, follow: .following)))
        XCTAssertFalse(policy.canSeeActivity(context(audience: .selfOnly, isPrivate: false)))
        XCTAssertFalse(policy.canSeeActivity(context(isPrivate: false, activityExcluded: true)))
    }

    func testOwnerKeepsPrivateContentButDeletedSourceRemainsUnavailable() {
        for audience in ActivityAudience.allCases {
            XCTAssertTrue(policy.canSeeActivity(context(
                viewerID: "owner", audience: audience, isPrivate: true, follow: .none,
                accountExcluded: true, activityExcluded: true
            )))
            XCTAssertFalse(policy.canSeeActivity(context(viewerID: "owner", audience: audience, deleted: true)))
        }
    }

    func testMissingIdentityAndForgedOwnerRelationshipCannotGrantAccess() {
        for viewerID in [nil, "", " \n"] as [String?] {
            XCTAssertFalse(policy.canSeeActivity(context(viewerID: viewerID)))
        }
        XCTAssertFalse(policy.canSeeActivity(context(ownerID: "")))
        XCTAssertFalse(policy.canSeeActivity(context(ownerID: " \n")))
        XCTAssertFalse(policy.canSeePlace(
            viewerID: "stranger", ownerID: "owner", visibility: .selfOnly,
            relationship: .owner, isBlocked: false
        ))
    }

    func testLegacyMigrationPreservesAudiencesRatherThanNormalizingThem() throws {
        XCTAssertEqual(ActivityAudience(preserving: .followers), .followers)
        XCTAssertEqual(ActivityAudience(preserving: .mutuals), .mutuals)
        XCTAssertEqual(ActivityAudience(preserving: .selfOnly), .selfOnly)
        XCTAssertEqual(try JSONDecoder().decode(ActivityAudience.self, from: Data("\"followers\"".utf8)), .followers)
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityAudience.self, from: Data("\"everyone\"".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityFollowAccess.self, from: Data("\"approved_by_client\"".utf8)))
    }

    private func context(
        viewerID: String? = "viewer", ownerID: String = "owner",
        audience: ActivityAudience = .account, isPrivate: Bool = false,
        follow: ActivityFollowAccess = .following,
        accountExcluded: Bool = false, activityExcluded: Bool = false,
        blocked: Bool = false, deleted: Bool = false
    ) -> ActivityAccessContext {
        ActivityAccessContext(
            viewerID: viewerID, ownerID: ownerID, audience: audience,
            isPrivateAccount: isPrivate, followAccess: follow,
            isAccountExcluded: accountExcluded, isActivityExcluded: activityExcluded,
            isBlocked: blocked, isDeleted: deleted
        )
    }
}
