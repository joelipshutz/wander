#if DEBUG
import SwiftUI
import UIKit

/// REC-682 review only. Shared state never reaches a repository, contacts, or analytics.
@MainActor
final class PeopleDiscoveryMockupModel: ObservableObject {
    @Published var expanded = true
    @Published var following: Set<String> = []
    @Published var showsInvite = false
    @Published var selectedPerson: DiscoverPeopleRecommendation?
    @Published var selectedInvitePerson: DiscoverPeopleRecommendation?
    @Published var showsDeliveryNotice = false

    static var route: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WanderPeopleMockup") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "expanded"
    }

    lazy var recommendations: [DiscoverPeopleRecommendation] = [
        person("maya", "Maya Chen", tile: 1, reason: .sharedFollows(3)),
        person("eli", "Eli Brooks", tile: 2, reason: .nearby),
        person("bea", "Bea Moreno", tile: 3, reason: .followsYou),
        person("sam", "Sam Rivera", tile: 0, reason: .sharedFollows(2))
    ]

    let contacts: [InviteContact] = [
        InviteContact(id: "alex", displayName: "Alex Reed", contactDetail: "Mobile", relationship: .contactOnly, isFrequentlyContacted: true),
        InviteContact(id: "jordan", displayName: "Jordan Lee", contactDetail: "Mobile", relationship: .contactOnly, isFrequentlyContacted: true),
        InviteContact(id: "avery", displayName: "Avery Lane", contactDetail: "Mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "charlie", displayName: "Charlie Park", contactDetail: "Mobile", relationship: .contactOnly, isFrequentlyContacted: false),
        InviteContact(id: "devon", displayName: "Devon James", contactDetail: "Mobile", relationship: .contactOnly, isFrequentlyContacted: false)
    ]

    private func person(_ id: String, _ name: String, tile: Int, reason: DiscoverPeopleRecommendationReason) -> DiscoverPeopleRecommendation {
        DiscoverPeopleRecommendation(profile: ProfileShell(
            id: "people-review-\(id)", handle: id, displayName: name,
            avatarURL: Self.avatar(tile: tile), bio: nil, homeArea: "Los Angeles",
            relationship: .nonFollower), reason: reason, rank: tile)
    }

    static func avatar(tile: Int) -> String? {
        guard let source = UIImage(named: "PlaceCarouselAvatars")?.cgImage else { return nil }
        let width = source.width / 2, height = source.height / 2
        guard let image = source.cropping(to: CGRect(x: tile % 2 * width, y: tile / 2 * height, width: width, height: height)),
              let data = UIImage(cgImage: image).pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("people-review-avatar-\(tile).png")
        try? data.write(to: url)
        return url.absoluteString
    }
}

private struct PeopleDiscoveryMockupKey: EnvironmentKey {
    static let defaultValue: PeopleDiscoveryMockupModel? = nil
}

extension EnvironmentValues {
    var peopleDiscoveryMockup: PeopleDiscoveryMockupModel? {
        get { self[PeopleDiscoveryMockupKey.self] }
        set { self[PeopleDiscoveryMockupKey.self] = newValue }
    }
}

struct PeopleDiscoveryMockupToggle: View {
    @ObservedObject var model: PeopleDiscoveryMockupModel
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                model.expanded.toggle()
            }
        } label: {
            Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(brandMode.primaryText)
                .frame(width: 44, height: 44)
                .background(brandMode.primaryText.opacity(brandMode.prefersDarkInterface ? 0.10 : 0.055),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("People worth following")
        .accessibilityValue(model.expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(model.expanded ? "Hide suggested people" : "Show suggested people")
        .accessibilityIdentifier("peopleReview.toggle")
    }
}

struct PeopleDiscoveryMockupShelf: View {
    @ObservedObject var model: PeopleDiscoveryMockupModel
    @Environment(\.astirBrandMode) private var brandMode
    var collapsible = false

    var body: some View {
        if !collapsible || model.expanded {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("People worth following")
                        .font(AstirTypography.sectionTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Spacer(minLength: 8)
                    if collapsible {
                        Button("See all") { model.showsInvite = true }
                            .font(AstirTypography.label)
                            .fixedSize()
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("peopleReview.invite")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        ForEach(model.recommendations) { person in
                            PeopleRecommendationCard(recommendation: person,
                                isFollowing: model.following.contains(person.id),
                                isFollowInFlight: false, didFollowFail: false,
                                open: {
                                    if collapsible { model.selectedPerson = person }
                                    else { model.selectedInvitePerson = person }
                                },
                                follow: { model.following.insert(person.id) })
                        }
                    }.padding(.vertical, WanderTheme.spacing1)
                }
                .contentMargins(.horizontal, collapsible ? WanderTheme.spacing4 : 0, for: .scrollContent)
                .padding(.horizontal, collapsible ? -WanderTheme.spacing4 : 0)
            }
            .padding(.top, 4)
            .transition(.opacity)
        }
    }
}

/// The real ProfileOwnerHome and ContactInviteSheet, using fixture-only content.
struct PeopleDiscoveryMockupRoot: View {
    @StateObject private var model = PeopleDiscoveryMockupModel()
    @StateObject private var store: WanderStore
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @State private var selectedMonth = Date.now
    @State private var showsReviewOptions = false
    @State private var showsGuide = false
    @State private var tab = "profile"
    private let profile: LocalProfile
    private let route: String

    init(route: String) {
        self.route = route
        let fixtures = WanderFixtures.seed()
        let profile = fixtures.currentUser
        profile.displayName = "Alex Morgan"
        profile.handle = "alexmorgan"
        profile.homeArea = "Los Angeles, CA"
        profile.bio = "Good coffee. Long dinners. Places worth going back to."
        profile.createdAt = Date(timeIntervalSince1970: 1_750_032_000)
        profile.avatarURL = PeopleDiscoveryMockupModel.avatar(tile: 0)
        self.profile = profile
        _store = StateObject(wrappedValue: WanderStore(fixtures: fixtures))
    }

    var body: some View {
        TabView(selection: $tab) {
            reviewBoundary("Live").tabItem { Label("Live", systemImage: "map") }.tag("live")
            reviewBoundary("Lists").tabItem { Label("Lists", systemImage: "square.stack") }.tag("lists")
            NavigationStack { profileHome }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag("profile")
        }
        .environmentObject(store)
        .environmentObject(walkthroughs)
        .environment(\.peopleDiscoveryMockup, model)
        .astirAdaptiveBrandMode()
        .tint(AstirBrandMode.editorialLight.accent)
        .task {
            model.expanded = route != "collapsed"
            model.showsInvite = route == "invite"
        }
        .sheet(isPresented: $model.showsInvite) {
            ContactInviteSheet(surface: .feedPeople, contacts: model.contacts)
                .environment(\.peopleDiscoveryMockup, model)
                .astirAdaptiveBrandMode()
                .sheet(item: $model.selectedInvitePerson) { person in
                    PeopleDiscoveryMockupPerson(model: model, person: person)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .alert("Preview only", isPresented: $model.showsDeliveryNotice) {
                    Button("Done", role: .cancel) {}
                } message: {
                    Text("Your sample selection is ready. This mockup does not send invitations.")
                }
        }
        .sheet(item: $model.selectedPerson) { person in
            PeopleDiscoveryMockupPerson(model: model, person: person)
        }
        .confirmationDialog("Mockup review", isPresented: $showsReviewOptions, titleVisibility: .visible) {
            Button("Invite people") { model.showsInvite = true }
            Button(model.expanded ? "Collapse suggestions" : "Expand suggestions") { model.expanded.toggle() }
            Button("Reset sample follows") { model.following = [] }
            Button("About this mockup") { showsGuide = true }
        }
        .alert("Native placement mockup", isPresented: $showsGuide) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Real Profile and Invite people views with sample people. Follow and contact selection stay in this review. The production Feed is unchanged; its people carousel will be removed in the later implementation. Open Invite people from the See all link or the review options menu.")
        }
    }

    private var profileHome: some View {
        let presentation = ProfilePresentationCache().present(store: store, profileID: profile.id)
        let insights = ProfileInsightsPresenter.present(ownerID: profile.id, userPlaces: store.userPlaces,
            visits: store.placeVisits, places: store.places, month: selectedMonth)
        return ProfileOwnerHome(
            profile: profile, viewerProfile: store.currentUser, mode: .owner,
            stats: presentation.stats, saveStreak: nil,
            followerCount: 128, followingCount: 96 + model.following.count, sharedVisitInvitationCount: 0,
            insights: insights, selectedMonth: $selectedMonth,
            avatarAction: { showsGuide = true }, editAction: { showsGuide = true },
            settingsAction: { showsReviewOptions = true }, shareAction: {}, relationshipAction: {},
            backAction: nil, memberActions: nil, graphAction: { _ in showsGuide = true },
            sharedVisitInvitationsAction: { showsGuide = true }, recentActivity: presentation.activityItems,
            recentActivityAction: { _ in showsGuide = true }, allActivityAction: { _ in showsGuide = true },
            inCommonAction: {}, calendarDateAction: { _ in showsGuide = true },
            mapSummaryAction: { _, _ in showsGuide = true }, yourMapAction: { showsGuide = true },
            calendarScrollRequestID: nil, onCalendarScrollRequestHandled: { _ in }
        )
    }

    private func reviewBoundary(_ title: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: title == "Live" ? "map" : "square.stack")
        } description: {
            Text(title == "Live" ? "The approved implementation will remove People worth following from the Feed drawer. This review focuses on its new Profile and Invite people placements." : "Lists is outside this placement review.")
        } actions: {
            Button("Back to Profile") { tab = "profile" }
        }.astirScreen()
    }
}
private struct PeopleDiscoveryMockupPerson: View {
    @ObservedObject var model: PeopleDiscoveryMockupModel
    let person: DiscoverPeopleRecommendation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                WanderAvatar(initials: String(person.profile.displayName.prefix(1)), avatarURL: person.profile.avatarURL, size: 96, color: WanderTheme.pinSocial.color)
                Text(person.profile.displayName).font(AstirTypography.screenTitle)
                Text("@\(person.profile.handle)").font(AstirTypography.body)
                PeopleFollowButton(displayName: person.profile.displayName,
                    isFollowing: model.following.contains(person.id), isPending: false, didFail: false) {
                        model.following.insert(person.id)
                    }
                Text("Sample profile for this design review.").font(AstirTypography.caption)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .astirScreen()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.astirAdaptiveBrandMode()
    }
}
#endif
