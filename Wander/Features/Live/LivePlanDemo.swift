import SwiftUI

enum LivePlanDemoPolicy {
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments,
                          isDebugSimulator: Bool = isDebugSimulatorBuild) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let required: Set<String> = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderUnifiedLiveUITest"]
        let excluded: Set<String> = ["-WanderUseLiveAuth", "-WanderForceSignedOut", "-WanderAuthUITest", "-WanderOnboardingUITestSignedOut", "-WanderLivePlanComposerUITest"]
        return isDebugSimulator && required.isSubset(of: Set(arguments)) && excluded.isDisjoint(with: arguments)
        #else
        return false
        #endif
    }

    static var isDebugSimulatorBuild: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Detached value projection only. It does not save a Wanna to WanderStore.
    static func savedWannaPreview(source: VisiblePlace, viewer: LocalProfile,
                                  relationship: ViewerRelationship) -> CommonGroundMockPlace? {
        guard relationship == .mutual, viewer.id != source.owner.id,
              source.owner.id == source.userPlace.userID,
              source.owner.deletedAt == nil, source.userPlace.deletedAt == nil,
              source.userPlace.visibility != .selfOnly, !source.isCommunityAggregate else { return nil }
        return CommonGroundMockPlace(
            id: "live-plan-demo", name: source.place.canonicalName, category: source.effectiveCompactType,
            area: [source.place.locality, source.place.region].compactMap { $0 }.joined(separator: ", "),
            city: source.place.locality ?? "", systemImage: "mappin.and.ellipse", youRating: nil, joeRating: nil,
            youEvidence: .init(wannaRecordIDs: ["demo-viewer-wanna"], visitRecordIDs: []),
            joeEvidence: .init(wannaRecordIDs: ["demo-partner-wanna"], visitRecordIDs: []),
            reason: "A simulated Wanna for this review only.",
            viewer: .init(id: "demo-viewer", name: viewer.displayName),
            partner: .init(id: "demo-partner", name: source.owner.displayName),
            photoReference: nil, sourcePlaceID: nil)
    }

    /// Remove all remote media/navigation references from an existing fixture
    /// mapping before sending it to the local invitation rehearsal.
    static func detachedPreview(_ place: CommonGroundMockPlace) -> CommonGroundMockPlace {
        CommonGroundMockPlace(id: "live-plan-demo", name: place.name, category: place.category,
            area: place.area, city: place.city, systemImage: place.systemImage,
            youRating: place.youRating, joeRating: place.joeRating,
            youEvidence: place.youEvidence, joeEvidence: place.joeEvidence, reason: place.reason,
            viewer: .init(id: "demo-viewer", name: place.viewer.name),
            partner: .init(id: "demo-partner", name: place.partner.name),
            photoReference: nil, sourcePlaceID: nil,
            isOneSidedRecommendation: place.isOneSidedRecommendation)
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
/// Reuses the existing invitation editor and its in-app recipient rehearsal.
/// No backend, save callback, share preparation, or analytics client is injected.
struct LivePlanDemoComposer: View {
    @Environment(\.astirBrandMode) private var brand
    let place: CommonGroundMockPlace

    var body: some View {
        CommonGroundInvitationMockup(draft: CommonGroundInvitationDraft(place: place,
                                     suggestedDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)),
                                     liveSharing: false, analytics: NoopAnalyticsClient())
            .safeAreaInset(edge: .top, spacing: 0) {
                Label("Demo plan · nothing is saved or sent", systemImage: "testtube.2")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(brand.background)
                    .accessibilityIdentifier("live.plan.demo")
            }
    }
}
#endif
