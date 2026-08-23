#if DEBUG
import SwiftUI

enum WannaGoWithMockupPage: String, CaseIterable {
    case hub
    case save
    case people
    case feed
    case invitation
    case map
    case checkIn
    case plan

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WannaGoWithMockupPage? {
        if let environmentPage = environment["WANDER_WANNA_GO_WITH_MOCKUP"],
           !environmentPage.isEmpty {
            return WannaGoWithMockupPage(rawValue: environmentPage) ?? .hub
        }

        guard let flagIndex = arguments.firstIndex(of: "-WanderWannaGoWithMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .hub }
        return WannaGoWithMockupPage(rawValue: arguments[valueIndex]) ?? .hub
    }
}

struct WannaGoWithMockupRoot: View {
    let page: WannaGoWithMockupPage

    var body: some View {
        WannaGoWithMockupDestination(page: page)
            .preferredColorScheme(.light)
    }
}

private struct WannaGoWithMockupDestination: View {
    let page: WannaGoWithMockupPage

    @ViewBuilder
    var body: some View {
        switch page {
        case .hub:
            WannaGoWithPrototypeHub()
        case .save:
            WannaGoWithSavePrototype()
        case .people:
            WannaGoWithPeoplePrototype()
        case .feed:
            WannaGoWithFeedPrototype()
        case .invitation:
            WannaGoWithInvitationPrototype()
        case .map:
            WannaGoWithMapPrototype()
        case .checkIn:
            WannaGoWithCheckInPrototype()
        case .plan:
            WannaGoWithPlanPrototype()
        }
    }
}

private struct WannaGoWithPrototypeHub: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("Wanna Go With")
                            .font(WanderTheme.editorialDisplay(size: 32, weight: .bold))
                        Text("REC-357 interactive product states")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    .padding(.bottom, WanderTheme.spacing2)

                    ForEach(WannaGoWithMockupPage.allCases.filter { $0 != .hub }, id: \.self) { page in
                        NavigationLink {
                            WannaGoWithMockupDestination(page: page)
                        } label: {
                            HStack(spacing: WanderTheme.spacing3) {
                                Image(systemName: page.systemImage)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(WanderTheme.terracottaDark.color)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(WanderTheme.textInk.color)
                                    Text(page.subtitle)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(WanderTheme.textMuted.color)
                                }

                                Spacer(minLength: WanderTheme.spacing2)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(WanderTheme.textFaint.color)
                            }
                            .frame(minHeight: WanderTheme.tapMinimum)
                            .padding(WanderTheme.spacing3)
                            .background(WanderTheme.surfaceBone.color)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                            .overlay(
                                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                                    .stroke(WanderTheme.borderHairline.color)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(WanderTheme.spacing4)
            }
            .wanderScreen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension WannaGoWithMockupPage {
    var title: String {
        switch self {
        case .hub: "Prototype index"
        case .save: "Save a plan"
        case .people: "Choose people"
        case .feed: "Feed visibility"
        case .invitation: "Invitation response"
        case .map: "Map treatment"
        case .checkIn: "Repeat check-in"
        case .plan: "Manage a group plan"
        }
    }

    var subtitle: String {
        switch self {
        case .hub: "All states"
        case .save: "Optional people, date, and sharing"
        case .people: "Multiple independent invitees"
        case .feed: "Shared statement versus private activity"
        case .invitation: "Accept creates your own Wanna"
        case .map: "Been + Wanna with an additive plan halo"
        case .checkIn: "Save first, then Keep or Remove"
        case .plan: "Going, invited, declined, and date state"
        }
    }

    var systemImage: String {
        switch self {
        case .hub: "square.grid.2x2"
        case .save: "bookmark.fill"
        case .people: "person.2.fill"
        case .feed: "rectangle.stack.fill"
        case .invitation: "envelope.open.fill"
        case .map: "map.fill"
        case .checkIn: "checkmark.circle.fill"
        case .plan: "calendar.badge.clock"
        }
    }
}

private struct WannaGoWithSavePrototype: View {
    @State private var selectedPeople = Set(["joseph", "maia"])
    @State private var hasDate = true
    @State private var plannedDate = Self.augustTwentyEighth
    @State private var sharing = WannaPlanSharing.feed
    @State private var isShowingPeople = false
    @State private var isShowingDatePicker = false
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    WannaPrototypePlaceHeader(statusCopy: "Wanna")

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("plan it")
                            .wannaSectionTitle()

                        Button {
                            isShowingPeople = true
                        } label: {
                            WannaPlanningRow(
                                icon: "person.2.fill",
                                title: "Go with people",
                                detail: selectedPeople.isEmpty
                                    ? "Optional"
                                    : WannaPrototypeData.people
                                        .filter { selectedPeople.contains($0.id) }
                                        .map(\.firstName)
                                        .joined(separator: " and "),
                                trailing: AnyView(
                                    WannaAvatarStack(
                                        people: WannaPrototypeData.people.filter {
                                            selectedPeople.contains($0.id)
                                        },
                                        size: 30
                                    )
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 0) {
                            Toggle(isOn: $hasDate) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pick a date")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Optional — you can decide later")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(WanderTheme.textMuted.color)
                                    }
                                } icon: {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(WanderTheme.terracottaDark.color)
                                }
                            }
                            .tint(WanderTheme.terracotta.color)
                            .frame(minHeight: WanderTheme.tapMinimum)

                            if hasDate {
                                Divider().overlay(WanderTheme.borderHairline.color)
                                WannaDateSummaryRow(date: plannedDate) {
                                    isShowingDatePicker = true
                                }
                            }
                        }
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.vertical, WanderTheme.spacing1)
                        .wannaCard()

                        if !selectedPeople.isEmpty {
                            WannaSharingChooser(selection: $sharing, isForcedPrivate: false)
                        }
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("your details")
                            .wannaSectionTitle()

                        WannaPlanningRow(
                            icon: "note.text",
                            title: "Note, tags, and questions",
                            detail: "Stay personal to you",
                            trailing: AnyView(
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WanderTheme.textFaint.color)
                            )
                        )
                    }

                    if didSave {
                        Label("Wanna saved — 2 invitations sent", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.stateSuccess.color)
                            .padding(WanderTheme.spacing3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WanderTheme.surfaceBone.color)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, 92)
            }
            .wanderScreen()
            .navigationTitle("save this place")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack {
                    WanderPrimaryButton(
                        title: selectedPeople.isEmpty
                            ? "Save Wanna"
                            : "Save & invite \(selectedPeople.count)",
                        systemImage: selectedPeople.isEmpty ? "bookmark.fill" : "paperplane.fill"
                    ) {
                        didSave = true
                    }
                }
                .padding(WanderTheme.spacing4)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $isShowingPeople) {
                NavigationStack {
                    WannaPeoplePickerContent(selectedPeople: $selectedPeople)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { isShowingPeople = false }
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isShowingDatePicker) {
                NavigationStack {
                    DatePicker(
                        "When?",
                        selection: $plannedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(WanderTheme.spacing4)
                    .navigationTitle("pick a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isShowingDatePicker = false }
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    private static var augustTwentyEighth: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 28)) ?? .now
    }
}

private struct WannaGoWithPeoplePrototype: View {
    @State private var selectedPeople = Set(["joseph", "maia"])

    var body: some View {
        NavigationStack {
            WannaPeoplePickerContent(selectedPeople: $selectedPeople)
        }
    }
}

private struct WannaPeoplePickerContent: View {
    @Binding var selectedPeople: Set<String>
    @State private var query = ""

    private var filteredPeople: [WannaPrototypePerson] {
        guard !query.isEmpty else { return WannaPrototypeData.people }
        return WannaPrototypeData.people.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.handle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !selectedPeople.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: WanderTheme.spacing3) {
                        ForEach(WannaPrototypeData.people.filter { selectedPeople.contains($0.id) }) { person in
                            VStack(spacing: WanderTheme.spacing1) {
                                ZStack(alignment: .topTrailing) {
                                    WannaPrototypeAvatar(person: person, size: 48)
                                    Button {
                                        selectedPeople.remove(person.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(
                                                WanderTheme.textInk.color,
                                                WanderTheme.surfaceRaised.color
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                    .accessibilityLabel("Remove \(person.name)")
                                }
                                Text(person.firstName)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.vertical, WanderTheme.spacing3)
                }
                .scrollIndicators(.hidden)
                Divider().overlay(WanderTheme.borderHairline.color)
            }

            List(filteredPeople) { person in
                Button {
                    if selectedPeople.contains(person.id) {
                        selectedPeople.remove(person.id)
                    } else {
                        selectedPeople.insert(person.id)
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        WannaPrototypeAvatar(person: person, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: WanderTheme.spacing1) {
                                Text(person.name)
                                    .font(.system(size: 15, weight: .bold))
                                if person.isStealth {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(WanderTheme.textMuted.color)
                                        .accessibilityLabel("Stealth mode")
                                }
                            }
                            Text(person.isStealth ? "Private participant" : "@\(person.handle)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        Spacer()
                        Image(systemName: selectedPeople.contains(person.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(
                                selectedPeople.contains(person.id)
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderStrong.color
                            )
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(WanderTheme.surfaceBone.color)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .navigationTitle(selectedPeople.isEmpty ? "go with people" : "\(selectedPeople.count) selected")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search people")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("Each person receives their own invitation and gets a personal Wanna only after accepting.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
        }
    }
}

private struct WannaGoWithFeedPrototype: View {
    @State private var sharing = WannaPlanSharing.feed

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Picker("Visibility", selection: $sharing) {
                        Text("On Feed").tag(WannaPlanSharing.feed)
                        Text("Private").tag(WannaPlanSharing.privateOnly)
                    }
                    .pickerStyle(.segmented)

                    if sharing == .feed {
                        Text("Followers who can see Ryan’s save see this statement. Pending and stealth invitees stay hidden.")
                            .wannaHelperCopy()
                        WannaPlanTicket(isPrivate: false)
                    } else {
                        Text("This appears only in the participants’ activity and inbox surfaces.")
                            .wannaHelperCopy()
                        WannaPlanTicket(isPrivate: true)
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Label("Feed privacy rule", systemImage: "eye.slash.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Maia is still pending and Ryan is in stealth mode, so neither person is named or counted on the public tile.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    .padding(WanderTheme.spacing3)
                    .wannaCard()
                }
                .padding(WanderTheme.spacing4)
            }
            .wanderScreen()
            .navigationTitle("plan activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WannaPlanTicket: View {
    let isPrivate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing2) {
                WannaPrototypeAvatar(person: WannaPrototypeData.creator, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ryan wants to go")
                        .font(.system(size: 14, weight: .bold))
                    Text("just now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                Label(isPrivate ? "Private" : "On Feed", systemImage: isPrivate ? "lock.fill" : "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("Gnarwhal Coffee")
                    .font(WanderTheme.editorialDisplay(size: 24, weight: .bold))
                Text(isPrivate ? "with Joe and Maia · Aug 28" : "with Joe · Aug 28")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                Text("Coffee shop · Downtown Los Angeles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            HStack(spacing: WanderTheme.spacing2) {
                Label("Wanna", systemImage: "bookmark.fill")
                Label("Plan", systemImage: "person.2.fill")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WanderTheme.terracottaDark.color)
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.sunTint.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.categorySun.color, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct WannaGoWithInvitationPrototype: View {
    private enum ResponseState {
        case pending
        case accepted
        case declined
    }

    @State private var response = ResponseState.pending

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    HStack(spacing: WanderTheme.spacing3) {
                        WannaPrototypeAvatar(person: WannaPrototypeData.creator, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ryan wants to go with you")
                                .font(.system(size: 16, weight: .bold))
                            Text("On Feed · invited just now")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }

                    WannaPrototypePlaceHeader(statusCopy: "Aug 28")

                    HStack(spacing: WanderTheme.spacing3) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ryan is going")
                                .font(.system(size: 14, weight: .bold))
                            Text("Maia has also been invited")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                    }
                    .padding(WanderTheme.spacing3)
                    .wannaCard()

                    switch response {
                    case .pending:
                        VStack(spacing: WanderTheme.spacing2) {
                            WanderPrimaryButton(title: "I’m in", systemImage: "checkmark") {
                                response = .accepted
                            }
                            Button("Not this time") {
                                response = .declined
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        }
                    case .accepted:
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Label("You’re going", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(WanderTheme.stateSuccess.color)
                            Text("Gnarwhal is now in your Wanna list. Your notes, tags, and privacy stay yours.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        .padding(WanderTheme.spacing4)
                        .wannaCard()
                    case .declined:
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("Invitation declined")
                                .font(.system(size: 17, weight: .bold))
                            Text("No Wanna was created. Ryan’s plan with other people is unchanged.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                            Button("Undo") { response = .pending }
                                .font(.system(size: 14, weight: .bold))
                        }
                        .padding(WanderTheme.spacing4)
                        .wannaCard()
                    }
                }
                .padding(WanderTheme.spacing4)
            }
            .wanderScreen()
            .navigationTitle("invitation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WannaGoWithMapPrototype: View {
    @State private var showsPlan = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    WannaPrototypeMapBackground()
                    VStack(spacing: WanderTheme.spacing2) {
                        WannaPlannedMapPin(showsPlan: showsPlan)
                        Text("Gnarwhal Coffee")
                            .font(.system(size: 13, weight: .black))
                            .padding(.horizontal, WanderTheme.spacing2)
                            .padding(.vertical, WanderTheme.spacing1)
                            .background(WanderTheme.surfaceRaised.color.opacity(0.94))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    Toggle("Show active plan", isOn: $showsPlan)
                        .font(.system(size: 15, weight: .bold))
                        .tint(WanderTheme.terracotta.color)

                    HStack(spacing: WanderTheme.spacing4) {
                        WannaMapLegendSample(style: .solid, label: "Been")
                        WannaMapLegendSample(style: .dashed, label: "Wanna")
                        WannaMapLegendSample(style: .halo, label: "Plan")
                    }

                    Text("The terracotta ring preserves Been + Wanna. The sun halo and people badge add planning without creating a third status color.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .padding(WanderTheme.spacing4)
                .background(WanderTheme.surfaceBone.color)
            }
            .navigationTitle("map state")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WannaPlannedMapPin: View {
    let showsPlan: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsPlan {
                Circle()
                    .stroke(WanderTheme.categorySun.color, lineWidth: 3)
                    .frame(width: 58, height: 58)
                    .shadow(color: WanderTheme.categorySun.color.opacity(0.35), radius: 6)
            }

            ZStack {
                Circle()
                    .fill(WanderTheme.surfaceRaised.color)
                    .frame(width: 42, height: 42)
                Text("☕️")
                    .font(.system(size: 24))
                MapPinOutlineStroke(
                    outline: MapPinOutline(
                        ownership: .currentUser,
                        status: .been,
                        secondaryStatus: .wannaGo
                    ),
                    lineWidth: 3
                )
                .frame(width: 42, height: 42)
            }
            .frame(width: 58, height: 58)

            if showsPlan {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(width: 22, height: 22)
                    .background(WanderTheme.categorySun.color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: 66, height: 66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            showsPlan
                ? "Gnarwhal Coffee, been and wanna go, planned with 2 people on August 28"
                : "Gnarwhal Coffee, been and wanna go"
        )
    }
}

private enum WannaMapLegendStyle: Equatable {
    case solid
    case dashed
    case halo
}

private struct WannaMapLegendSample: View {
    let style: WannaMapLegendStyle
    let label: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Circle()
                .stroke(
                    style == .halo ? WanderTheme.categorySun.color : WanderTheme.terracotta.color,
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: style == .dashed ? [2, 3] : []
                    )
                )
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 12, weight: .bold))
        }
    }
}

private struct WannaPrototypeMapBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(WanderTheme.surfaceSand.color)
            )
            var roads = Path()
            for fraction in stride(from: 0.15, through: 0.9, by: 0.18) {
                roads.move(to: CGPoint(x: 0, y: size.height * fraction))
                roads.addLine(to: CGPoint(x: size.width, y: size.height * (fraction - 0.08)))
            }
            for fraction in stride(from: 0.12, through: 0.9, by: 0.22) {
                roads.move(to: CGPoint(x: size.width * fraction, y: 0))
                roads.addLine(to: CGPoint(x: size.width * (fraction + 0.08), y: size.height))
            }
            context.stroke(roads, with: .color(Color.white.opacity(0.72)), lineWidth: 7)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct WannaGoWithCheckInPrototype: View {
    @State private var choice: WannaCheckInChoice?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: WanderTheme.spacing4) {
                    ZStack {
                        Circle()
                            .fill(WanderTheme.terracottaTint.color)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                    }
                    .frame(width: 64, height: 64)

                    VStack(spacing: WanderTheme.spacing2) {
                        Text("Check-in saved")
                            .font(WanderTheme.editorialDisplay(size: 28, weight: .bold))
                        Text("Keep Gnarwhal Coffee in Wanna?")
                            .font(.system(size: 18, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("You checked in, but you can keep it saved for another time.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .multilineTextAlignment(.center)
                    }

                    if let choice {
                        Label(
                            choice == .keep ? "Still in your Wanna list" : "Removed from Wanna",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                    } else {
                        VStack(spacing: WanderTheme.spacing2) {
                            WanderPrimaryButton(title: "Keep in Wanna", systemImage: "bookmark.fill") {
                                choice = .keep
                            }
                            Button("Remove from Wanna") {
                                choice = .remove
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        }
                    }
                }
                .padding(WanderTheme.spacing6)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                        .stroke(WanderTheme.borderHairline.color)
                )
                .padding(WanderTheme.spacing4)

                Spacer()
            }
            .wanderScreen()
            .navigationTitle("after check-in")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WannaGoWithPlanPrototype: View {
    @State private var isPrivate = false
    @State private var showsInactive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    WannaPrototypePlaceHeader(statusCopy: "Aug 28")

                    HStack(spacing: WanderTheme.spacing2) {
                        Label("Active plan", systemImage: "calendar.badge.clock")
                        Spacer()
                        Label(isPrivate ? "Private" : "On Feed", systemImage: isPrivate ? "lock.fill" : "person.2.fill")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        Text("Going")
                            .wannaSectionTitle()
                        WannaParticipantRow(person: WannaPrototypeData.creator, status: "Organizer", tone: .accepted)
                        WannaParticipantRow(person: WannaPrototypeData.joseph, status: "Accepted · has their own Wanna", tone: .accepted)
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        Text("Invited")
                            .wannaSectionTitle()
                        WannaParticipantRow(person: WannaPrototypeData.maia, status: "Waiting for a response", tone: .pending)
                        WannaParticipantRow(person: WannaPrototypeData.stealthRyan, status: "Private participant", tone: .pending)
                    }

                    Toggle(isOn: $showsInactive.animation()) {
                        Text("Show declined and left")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .tint(WanderTheme.terracotta.color)

                    if showsInactive {
                        WannaParticipantRow(person: WannaPrototypeData.sam, status: "Declined", tone: .inactive)
                    }

                    WannaSharingChooser(
                        selection: Binding(
                            get: { isPrivate ? .privateOnly : .feed },
                            set: { isPrivate = $0 == .privateOnly }
                        ),
                        isForcedPrivate: false
                    )

                    Button(role: .destructive) {} label: {
                        Text("Cancel plan")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .navigationTitle("Gnarwhal plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {}
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }
}

private enum WannaParticipantTone {
    case accepted
    case pending
    case inactive

    var color: Color {
        switch self {
        case .accepted: WanderTheme.stateSuccess.color
        case .pending: WanderTheme.stateWarning.color
        case .inactive: WanderTheme.textFaint.color
        }
    }

    var systemImage: String {
        switch self {
        case .accepted: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .inactive: "minus.circle.fill"
        }
    }
}

private struct WannaParticipantRow: View {
    let person: WannaPrototypePerson
    let status: String
    let tone: WannaParticipantTone

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WannaPrototypeAvatar(person: person, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WanderTheme.spacing1) {
                    Text(person.name)
                        .font(.system(size: 15, weight: .bold))
                    if person.isStealth {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
        }
        .frame(minHeight: WanderTheme.tapMinimum)
        .padding(WanderTheme.spacing3)
        .wannaCard()
    }
}

private struct WannaSharingChooser: View {
    @Binding var selection: WannaPlanSharing
    let isForcedPrivate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("sharing")
                .wannaSectionTitle()

            ForEach(WannaPlanSharing.allCases, id: \.self) { option in
                let isUnavailable = isForcedPrivate && option == .feed
                Button {
                    guard !isUnavailable else { return }
                    selection = option
                } label: {
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        Image(systemName: option == .feed ? "person.2.fill" : "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .bold))
                            Text(option == .feed
                                ? "People who can see your saves can see this plan."
                                : "Only you and the people invited can see this.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: WanderTheme.spacing2)
                        Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                selection == option
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderStrong.color
                            )
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .padding(WanderTheme.spacing3)
                    .background(
                        selection == option
                            ? WanderTheme.terracottaTint.color
                            : WanderTheme.surfaceBone.color
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(
                                selection == option
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderHairline.color
                            )
                    )
                    .opacity(isUnavailable ? 0.46 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isUnavailable)
            }

            if isForcedPrivate {
                Text("Stealth mode keeps plans private.")
                    .wannaHelperCopy()
            }
        }
    }
}

private struct WannaPrototypePlaceHeader: View {
    let statusCopy: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ZStack {
                Circle().fill(WanderTheme.sunTint.color)
                Text("☕️").font(.system(size: 23))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Gnarwhal Coffee")
                    .font(.system(size: 17, weight: .bold))
                Text("Coffee shop · Downtown Los Angeles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }

            Spacer(minLength: WanderTheme.spacing2)

            Text(statusCopy)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, WanderTheme.spacing1)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Capsule())
        }
        .padding(WanderTheme.spacing3)
        .wannaCard()
    }
}

private struct WannaPlanningRow: View {
    let icon: String
    let title: String
    let detail: String
    let trailing: AnyView

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
            Spacer(minLength: WanderTheme.spacing2)
            trailing
        }
        .frame(minHeight: WanderTheme.tapMinimum)
        .padding(WanderTheme.spacing3)
        .wannaCard()
    }
}

private struct WannaDateSummaryRow: View {
    let date: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    prompt
                    Spacer(minLength: WanderTheme.spacing3)
                    dateValue
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    prompt
                    dateValue
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("When, \(formattedDate)")
        .accessibilityHint("Opens the date picker")
    }

    private var prompt: some View {
        Text("When?")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(WanderTheme.textInk.color)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var dateValue: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Text(formattedDate)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var formattedDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct WannaAvatarStack: View {
    let people: [WannaPrototypePerson]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -8) {
            ForEach(people.prefix(3)) { person in
                WannaPrototypeAvatar(person: person, size: size)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WannaPrototypeAvatar: View {
    let person: WannaPrototypePerson
    let size: CGFloat

    var body: some View {
        WanderAvatar(initials: person.initials, size: size, color: person.color)
            .accessibilityLabel(person.name)
    }
}

private struct WannaPrototypePerson: Identifiable {
    let id: String
    let name: String
    let handle: String
    let initials: String
    let color: Color
    var isStealth = false

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

private enum WannaPrototypeData {
    static let creator = WannaPrototypePerson(
        id: "creator",
        name: "Ryan Alvarez",
        handle: "ryan",
        initials: "RA",
        color: WanderTheme.avatarRyan.color
    )
    static let joseph = WannaPrototypePerson(
        id: "joseph",
        name: "Joseph Park",
        handle: "joseph",
        initials: "JP",
        color: WanderTheme.avatarJames.color
    )
    static let maia = WannaPrototypePerson(
        id: "maia",
        name: "Maia Chen",
        handle: "maia",
        initials: "MC",
        color: WanderTheme.avatarSofia.color
    )
    static let stealthRyan = WannaPrototypePerson(
        id: "stealth-ryan",
        name: "Ryan Bell",
        handle: "ryanb",
        initials: "RB",
        color: WanderTheme.textMuted.color,
        isStealth: true
    )
    static let sam = WannaPrototypePerson(
        id: "sam",
        name: "Sam Rivera",
        handle: "samr",
        initials: "SR",
        color: WanderTheme.avatarAndrew.color
    )
    static let people = [joseph, maia, stealthRyan, sam]
}

private extension View {
    func wannaCard() -> some View {
        background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )
    }

    func wannaSectionTitle() -> some View {
        font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.textMuted.color)
            .textCase(.lowercase)
    }

    func wannaHelperCopy() -> some View {
        font(.system(size: 13, weight: .medium))
            .foregroundStyle(WanderTheme.textMuted.color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
