#if DEBUG
import MapKit
import SwiftUI

enum ProfileRedesignMockupPage: String, CaseIterable {
    case ownerProfile
    case ownerCalendar
    case ownerDiningMap
    case socialGraph
    case socialGraphEmpty
    case editProfile
    case settings
    case privacyTrust
    case blockedAccounts
    case blockedEmpty
    case mutedAccounts
    case mutedEmpty
    case deleteFirst
    case deleteFinal

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> ProfileRedesignMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderProfileRedesignMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .ownerProfile
        }

        return ProfileRedesignMockupPage(rawValue: arguments[valueIndex]) ?? .ownerProfile
    }
}

struct ProfileRedesignMockupRoot: View {
    let page: ProfileRedesignMockupPage

    var body: some View {
        Group {
            switch page {
            case .ownerProfile:
                OwnerProfileRedesignMockup()
            case .ownerCalendar:
                ProfileMockupScreen(title: "profile") {
                    ProfileCalendarMockup()
                }
            case .ownerDiningMap:
                ProfileMockupScreen(title: "profile") {
                    ProfileDiningMapMockup()
                }
            case .socialGraph:
                SocialGraphMockup(isEmpty: false)
            case .socialGraphEmpty:
                SocialGraphMockup(isEmpty: true)
            case .editProfile:
                EditProfileRedesignMockup()
            case .settings:
                ProfileSettingsRedesignMockup()
            case .privacyTrust:
                PrivacyTrustRedesignMockup()
            case .blockedAccounts:
                BlockedMutedMockup(selectedTab: .blocked, isEmpty: false)
            case .blockedEmpty:
                BlockedMutedMockup(selectedTab: .blocked, isEmpty: true)
            case .mutedAccounts:
                BlockedMutedMockup(selectedTab: .muted, isEmpty: false)
            case .mutedEmpty:
                BlockedMutedMockup(selectedTab: .muted, isEmpty: true)
            case .deleteFirst:
                DeleteAccountConfirmationMockup(stage: .first)
            case .deleteFinal:
                DeleteAccountConfirmationMockup(stage: .final)
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct OwnerProfileRedesignMockup: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                identitySection
                savedPlacesSection
                diningCalendar
                diningMap
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private var identitySection: some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                    Text("Ryan Lieblein")
                        .font(.system(size: 30, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: WanderTheme.spacing2)

                    ProfileActionButton(systemImage: "pencil", accessibilityLabel: "Edit profile")
                    ProfileActionButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share profile")
                    ProfileActionButton(systemImage: "gearshape.fill", accessibilityLabel: "Settings")
                }
            }

            WanderAvatar(
                initials: "RL",
                size: 132,
                color: WanderTheme.avatarRyan.color
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 12, y: 6)

            VStack(spacing: WanderTheme.spacing1) {
                Text("@ryan_lieblein")
                    .font(.system(size: 18, weight: .black))
                Text("Member since October 2023  •  Los Angeles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                ProfileCountButton(value: "128", label: "Followers")
                ProfileCountButton(value: "96", label: "Following")
                ProfileCountButton(value: "42", label: "Friends")
            }
            .padding(.vertical, WanderTheme.spacing2)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }

    private var savedPlacesSection: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ProfileSaveTile(
                value: "87",
                label: CheckInCopy.pluralNoun.uppercased(),
                symbol: "checkmark.circle.fill",
                color: WanderTheme.stateSuccess.color,
                fill: WanderTheme.categorySage.color.opacity(0.22)
            )
            ProfileSaveTile(
                value: "34",
                label: "WANNA",
                symbol: "bookmark.fill",
                color: WanderTheme.stateWarning.color,
                fill: WanderTheme.sunTint.color
            )
        }
    }

    private var diningCalendar: some View {
        ProfileCalendarMockup()
    }

    private var diningMap: some View {
        ProfileDiningMapMockup()
    }
}

private struct ProfileActionButton: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceBone.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ProfileCountButton: View {
    let value: String
    let label: String

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSaveTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color
    let fill: Color

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .black))
                    Text(value)
                        .font(.system(size: 28, weight: .black))
                    Spacer(minLength: WanderTheme.spacing2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 28, height: 28)
                        .background(WanderTheme.surfaceRaised.color.opacity(0.8))
                        .clipShape(Circle())
                }

                Text(label)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(fill)
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileCalendarMockup: View {
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let days: [Int?] = [nil] + Array(1...30).map(Optional.some)
    private let markedDays: [Int: Int] = [8: 2, 19: 1, 27: 1]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("your calendar")
                        .font(.system(size: 23, weight: .black))
                    Text("June 2026")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                HStack(spacing: WanderTheme.spacing1) {
                    ProfileMiniIconButton(systemImage: "chevron.left")
                    ProfileMiniIconButton(systemImage: "chevron.right")
                }
            }

            HStack(spacing: 0) {
                CalendarMetric(value: "4", label: "spots ranked")
                CalendarMetric(value: "3", label: "cuisines")
                CalendarMetric(value: "2", label: "cities")
            }

            LazyVGrid(columns: columns, spacing: WanderTheme.spacing2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    CalendarDayCell(day: day, visitCount: day.flatMap { markedDays[$0] })
                }
            }

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                Text("Dining days show where your check-ins happened.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .stroke(WanderTheme.borderHairline.color)
        )
    }
}

private struct ProfileMiniIconButton: View {
    let systemImage: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceRaised.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarDayCell: View {
    let day: Int?
    let visitCount: Int?

    var body: some View {
        ZStack {
            if visitCount != nil {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .fill(WanderTheme.terracotta.color)
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color.opacity(0.24))
            }

            if let day {
                Text("\(day)")
                    .font(.system(size: 14, weight: visitCount == nil ? .bold : .black))
                    .foregroundStyle(visitCount == nil ? WanderTheme.textInk.color : WanderTheme.textOnAction.color)
            }

            if let visitCount, visitCount > 1 {
                Text("\(visitCount)")
                    .font(.system(size: 10, weight: .black))
                    .frame(width: 18, height: 18)
                    .background(WanderTheme.textInk.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
                    .offset(x: 15, y: -15)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .accessibilityLabel(day.map { "June \($0)" } ?? "")
    }
}

private struct ProfileDiningMapMockup: View {
    @State private var selectedSummary = "places"

    private let points = [
        DiningMapPoint(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437),
        DiningMapPoint(name: "New York", latitude: 40.7128, longitude: -74.0060),
        DiningMapPoint(name: "Mexico City", latitude: 19.4326, longitude: -99.1332),
        DiningMapPoint(name: "London", latitude: 51.5072, longitude: -0.1276),
        DiningMapPoint(name: "Rio de Janeiro", latitude: -22.9068, longitude: -43.1729)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("your map")
                    .font(.system(size: 23, weight: .black))
                Text("5 cities  •  87 check-in places")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Map(
                initialPosition: .camera(
                    MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(latitude: 18, longitude: -55),
                        distance: 38_000_000,
                        heading: 0,
                        pitch: 0
                    )
                ),
                interactionModes: []
            ) {
                ForEach(points) { point in
                    Annotation(point.name, coordinate: point.coordinate) {
                        Circle()
                            .fill(WanderTheme.terracotta.color)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 205)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .allowsHitTesting(false)
            .accessibilityLabel("Map of check-in places in five cities")

            WanderSegmentedSwitch(
                options: [
                    WanderSegmentOption(id: "places", title: "Places"),
                    WanderSegmentOption(id: "cities", title: "Cities"),
                    WanderSegmentOption(id: "countries", title: "Countries")
                ],
                selection: $selectedSummary
            )

            VStack(spacing: 0) {
                DiningSummaryRow(title: "Restaurants & Food", detail: "52 places", value: "60%")
                Divider().overlay(WanderTheme.borderHairline.color)
                DiningSummaryRow(title: "Coffee, Tea & Sweets", detail: "21 places", value: "24%")
                Divider().overlay(WanderTheme.borderHairline.color)
                DiningSummaryRow(title: "Bars & Nightlife", detail: "14 places", value: "16%")
            }
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color)
            )
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }
}

private struct DiningMapPoint: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct DiningSummaryRow: View {
    let title: String
    let detail: String
    let value: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
    }
}

private struct ProfileMockupPerson: Identifiable {
    let id = UUID()
    let name: String
    let handle: String
    let initials: String
    let detail: String
    let color: Color
}

private let profileMockupPeople = [
    ProfileMockupPerson(name: "Joe Lipshutz", handle: "joelipshutz", initials: "JL", detail: "Friend", color: WanderTheme.avatarJames.color),
    ProfileMockupPerson(name: "Sofia Martinez", handle: "sofia_eats", initials: "SM", detail: "Friend", color: WanderTheme.avatarSofia.color),
    ProfileMockupPerson(name: "Andrew Chen", handle: "andrewc", initials: "AC", detail: "Follows you", color: WanderTheme.avatarAndrew.color),
    ProfileMockupPerson(name: "Maya Patel", handle: "mayap", initials: "MP", detail: "Following", color: WanderTheme.avatarRyan.color)
]

private struct SocialGraphMockup: View {
    let isEmpty: Bool
    @State private var selectedTab = "friends"

    var body: some View {
        ProfileMockupScreen(title: "friends") {
            WanderSegmentedSwitch(
                options: [
                    WanderSegmentOption(id: "followers", title: "Followers"),
                    WanderSegmentOption(id: "following", title: "Following"),
                    WanderSegmentOption(id: "friends", title: "Friends")
                ],
                selection: $selectedTab
            )

            ProfileSearchField(prompt: "Search people")

            Button(action: {}) {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 20, weight: .black))
                        .frame(width: 38, height: 38)
                        .background(WanderTheme.terracottaTint.color)
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find friends")
                            .font(.system(size: 16, weight: .black))
                        Text("Discover members you already know")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 68)
                .background(WanderTheme.surfaceBone.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                        .stroke(WanderTheme.borderHairline.color)
                )
            }
            .buttonStyle(.plain)

            if isEmpty {
                ProfileEmptyState(
                    systemImage: "person.2.slash",
                    title: "No friends yet",
                    message: "Friends are people you follow who follow you back. Find someone you trust to start sharing places."
                )
                .padding(.top, WanderTheme.spacing8)
            } else {
                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(profileMockupPeople) { person in
                        ProfilePersonMockupRow(person: person)
                    }
                }
            }
        }
    }
}

private struct ProfileSearchField: View {
    let prompt: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(prompt)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 50)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                .stroke(WanderTheme.borderHairline.color)
        )
    }
}

private struct ProfilePersonMockupRow: View {
    let person: ProfileMockupPerson

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            WanderAvatar(initials: person.initials, size: 48, color: person.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 16, weight: .black))
                Text("@\(person.handle)  •  \(person.detail)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 72)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }
}

private struct EditProfileRedesignMockup: View {
    var body: some View {
        ProfileMockupScreen(title: "edit profile") {
            VStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(initials: "RL", size: 124, color: WanderTheme.avatarRyan.color)
                Button("Edit profile photo", action: {})
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WanderTheme.spacing4)

            VStack(spacing: 0) {
                EditableProfileMockupRow(label: "Name", value: "Ryan Lieblein")
                Divider().overlay(WanderTheme.borderHairline.color)
                EditableProfileMockupRow(label: "Username", value: "@ryan_lieblein")
                Divider().overlay(WanderTheme.borderHairline.color)
                EditableProfileMockupRow(label: "Home city", value: "Los Angeles, CA")
                Divider().overlay(WanderTheme.borderHairline.color)
                EditableProfileMockupRow(label: "Bio", value: "Always looking for the next neighborhood favorite.")
            }
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color)
            )

            WanderPrimaryButton(title: "Save profile", systemImage: "checkmark", action: {})
                .padding(.top, WanderTheme.spacing3)
        }
    }
}

private struct EditableProfileMockupRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing3) {
            Text(label)
                .font(.system(size: 15, weight: .black))
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 62)
    }
}

private struct ProfileSettingsRedesignMockup: View {
    var body: some View {
        ProfileMockupScreen(title: "settings") {
            SettingsGroupMockup(title: "account") {
                SettingsNavigationRow(systemImage: "envelope.fill", title: "Change email", detail: "ryan@example.com")
                SettingsDivider()
                SettingsNavigationRow(systemImage: "phone.fill", title: "Change phone number", detail: "Optional")
                SettingsDivider()
                SettingsNavigationRow(systemImage: "key.fill", title: "Change password")
            }

            SettingsGroupMockup(title: "privacy and safety") {
                SettingsNavigationRow(systemImage: "hand.raised.fill", title: "Privacy & Trust", detail: "Profile and save visibility")
                SettingsDivider()
                SettingsNavigationRow(systemImage: "person.crop.circle.badge.xmark", title: "Blocked & Muted")
            }

            SettingsGroupMockup(title: "app") {
                SettingsNavigationRow(systemImage: "bell.fill", title: "Notifications")
                SettingsDivider()
                SettingsNavigationRow(systemImage: "arrow.triangle.2.circlepath", title: "Data & Sync")
            }

            Button(action: {}) {
                Text("Sign out")
                    .font(.system(size: 16, weight: .black))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WanderTheme.surfaceBone.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                            .stroke(WanderTheme.borderHairline.color)
                    )
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Text("Delete my account")
                    .font(.system(size: 16, weight: .black))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(WanderTheme.stateError.color)
            }
            .buttonStyle(.plain)
            .padding(.top, WanderTheme.spacing6)
        }
    }
}

private struct PrivacyTrustRedesignMockup: View {
    @State private var privateProfile = false
    @State private var stealthSaves = true

    var body: some View {
        ProfileMockupScreen(title: "privacy & trust") {
            SettingsGroupMockup(title: "privacy") {
                PrivacyToggleMockup(
                    systemImage: "person.crop.circle.badge.checkmark",
                    title: "Private profile",
                    detail: "Approve who can follow you and see follower-visible places.",
                    isOn: $privateProfile
                )
                SettingsDivider()
                PrivacyToggleMockup(
                    systemImage: "eye.slash.fill",
                    title: "Stealth mode for new saves",
                    detail: "Make new saves visible only to you by default.",
                    isOn: $stealthSaves
                )
            }

            SettingsGroupMockup(title: "trust") {
                PrivacyFactRow(systemImage: "person.2.fill", title: "Friends are mutual follows")
                SettingsDivider()
                PrivacyFactRow(systemImage: "lock.shield.fill", title: "Blocks hide both accounts everywhere")
                SettingsDivider()
                PrivacyFactRow(systemImage: "location.slash.fill", title: "rec.me never shares live location")
            }

            Text("These controls change who can discover your profile and how future saves begin. You can still choose visibility on each place.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsGroupMockup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            VStack(spacing: 0) {
                content
            }
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall)
                    .stroke(WanderTheme.borderHairline.color)
            )
        }
    }
}

private struct SettingsNavigationRow: View {
    let systemImage: String
    let title: String
    var detail: String?

    var body: some View {
        Button(action: {}) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .black))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 58)
            .foregroundStyle(WanderTheme.textInk.color)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(WanderTheme.borderHairline.color)
            .padding(.leading, 58)
    }
}

private struct PrivacyToggleMockup: View {
    let systemImage: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .black))
                    Text(detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(WanderTheme.terracotta.color)
        .padding(WanderTheme.spacing3)
        .frame(minHeight: 78)
    }
}

private struct PrivacyFactRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .frame(width: 34, height: 34)
                .background(WanderTheme.skyTint.color)
                .foregroundStyle(WanderTheme.stateInfo.color)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
    }
}

private enum BlockedMutedTab: String {
    case blocked
    case muted
}

private struct BlockedMutedMockup: View {
    let selectedTab: BlockedMutedTab
    let isEmpty: Bool
    @State private var selection: String

    init(selectedTab: BlockedMutedTab, isEmpty: Bool) {
        self.selectedTab = selectedTab
        self.isEmpty = isEmpty
        _selection = State(initialValue: selectedTab.rawValue)
    }

    var body: some View {
        ProfileMockupScreen(title: "blocked & muted") {
            WanderSegmentedSwitch(
                options: [
                    WanderSegmentOption(id: BlockedMutedTab.blocked.rawValue, title: "Blocked accounts"),
                    WanderSegmentOption(id: BlockedMutedTab.muted.rawValue, title: "Muted accounts")
                ],
                selection: $selection
            )

            if isEmpty {
                ProfileEmptyState(
                    systemImage: selectedTab == .blocked ? "person.crop.circle.badge.xmark" : "speaker.slash.circle.fill",
                    title: selectedTab == .blocked ? "You haven't blocked anyone" : "You haven't muted anyone",
                    message: selectedTab == .blocked
                        ? "Members you block will not be able to see your content and you will not be able to see theirs."
                        : "Activity by members you mute will not appear in your newsfeed and you will not receive notifications for this person."
                )
                .padding(.top, WanderTheme.spacing12)
            } else {
                VStack(spacing: WanderTheme.spacing2) {
                    ForEach(Array(profileMockupPeople.prefix(selectedTab == .blocked ? 2 : 3))) { person in
                        HStack(spacing: WanderTheme.spacing3) {
                            WanderAvatar(initials: person.initials, size: 48, color: person.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.system(size: 16, weight: .black))
                                Text("@\(person.handle)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                            }
                            Spacer()
                            Button(selectedTab == .blocked ? "Unblock" : "Unmute", action: {})
                                .font(.system(size: 13, weight: .black))
                                .padding(.horizontal, WanderTheme.spacing3)
                                .frame(minHeight: WanderTheme.tapMinimum)
                                .background(WanderTheme.surfaceRaised.color)
                                .foregroundStyle(WanderTheme.textInk.color)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                        }
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minHeight: 72)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    }
                }
            }
        }
    }
}

private struct ProfileEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .bold))
                .frame(width: 104, height: 104)
                .background(WanderTheme.terracottaTint.color)
                .foregroundStyle(WanderTheme.terracotta.color)
                .clipShape(Circle())

            VStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(.system(size: 25, weight: .black))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WanderTheme.spacing4)
    }
}

private enum DeleteConfirmationStage {
    case first
    case final
}

private struct DeleteAccountConfirmationMockup: View {
    let stage: DeleteConfirmationStage
    @State private var showsAlert = true

    var body: some View {
        ProfileSettingsRedesignMockup()
            .alert(alertTitle, isPresented: $showsAlert) {
                Button(stage == .first ? "Yes" : "Yes, delete", role: .destructive) {}
                Button(stage == .first ? "Cancel" : "No, cancel", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
    }

    private var alertTitle: String {
        stage == .first ? "You are deleting your account" : "Are you sure?"
    }

    private var alertMessage: String {
        if stage == .first {
            return "This begins permanent account deletion."
        }
        return "You are about to permanently delete your account. You will not be able to recover the data associated with your account."
    }
}

private struct ProfileMockupScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                HStack(spacing: WanderTheme.spacing3) {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            .background(WanderTheme.surfaceBone.color)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(WanderTheme.borderHairline.color))
                    }
                    .buttonStyle(.plain)

                    Text(title)
                        .font(.system(size: 28, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer()
                }

                content
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }
}
#endif
