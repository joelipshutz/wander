import MapKit
import SwiftUI

struct ProfileOwnerHome: View {
    let profile: LocalProfile
    let stats: ProfileStats
    let followerCount: Int
    let followingCount: Int
    let insights: ProfileInsights
    @Binding var selectedMonth: Date
    let isAvatarSaving: Bool
    let avatarAction: () -> Void
    let editAction: () -> Void
    let settingsAction: () -> Void
    let graphAction: (ProfileSocialGraphTab) -> Void
    let savedPlacesAction: (PlaceStatus) -> Void

    private var shareURL: URL {
        URL(string: "recme://profiles/\(profile.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? profile.id)")!
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                identitySection
                savedPlacesSection
                ProfileCalendarSection(insights: insights, selectedMonth: $selectedMonth)
                ProfileMapSection(insights: insights, beenCount: stats.been)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .wanderScreen()
    }

    private var identitySection: some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                    Text(profile.displayName)
                        .font(.system(size: 30, weight: .black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: WanderTheme.spacing2)

                    ProfileHeaderActionButton(systemImage: "pencil", accessibilityLabel: "Edit profile", action: editAction)

                    ShareLink(
                        item: shareURL,
                        subject: Text(profile.displayName),
                        message: Text("See @\(profile.handle) on rec.me")
                    ) {
                        ProfileHeaderActionLabel(systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share profile")

                    ProfileHeaderActionButton(systemImage: "gearshape.fill", accessibilityLabel: "Settings", action: settingsAction)
                }
            }

            Button(action: avatarAction) {
                ZStack {
                    WanderAvatar(
                        initials: profile.initials,
                        avatarURL: profile.avatarURL,
                        size: 132,
                        color: WanderTheme.avatarRyan.color
                    )
                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 12, y: 6)

                    if isAvatarSaving {
                        Circle()
                            .fill(WanderTheme.textInk.color.opacity(0.42))
                            .frame(width: 132, height: 132)
                        ProgressView()
                            .tint(WanderTheme.textOnAction.color)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isAvatarSaving)
            .accessibilityLabel(profile.avatarURL == nil ? "Add profile photo" : "Change profile photo")

            VStack(spacing: WanderTheme.spacing1) {
                Text("@\(profile.handle)")
                    .font(.system(size: 18, weight: .black))

                Text(profileMetadata)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)

                if let bio = normalized(profile.bio) {
                    Text(bio)
                        .font(.system(size: 15, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.top, WanderTheme.spacing1)
                }
            }

            HStack(spacing: 0) {
                ProfileGraphCountButton(value: followerCount, label: "Followers") {
                    graphAction(.followers)
                }
                ProfileGraphCountButton(value: followingCount, label: "Following") {
                    graphAction(.following)
                }
                ProfileGraphCountButton(value: stats.friends, label: "Friends") {
                    graphAction(.friends)
                }
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
            OwnerProfileSaveTile(
                value: stats.been,
                label: "BEEN",
                symbol: "checkmark.circle.fill",
                color: WanderTheme.stateSuccess.color,
                fill: WanderTheme.categorySage.color.opacity(0.22)
            ) {
                savedPlacesAction(.been)
            }

            OwnerProfileSaveTile(
                value: stats.wanna,
                label: "WANNA",
                symbol: "bookmark.fill",
                color: WanderTheme.stateWarning.color,
                fill: WanderTheme.sunTint.color
            ) {
                savedPlacesAction(.wannaGo)
            }
        }
    }

    private var profileMetadata: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var values = ["Member since \(formatter.string(from: profile.createdAt))"]
        if let homeArea = normalized(profile.homeArea) {
            values.append(homeArea)
        }
        return values.joined(separator: "  •  ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct ProfileHeaderActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileHeaderActionLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ProfileHeaderActionLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .black))
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .background(WanderTheme.surfaceBone.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.borderHairline.color))
    }
}

private struct ProfileGraphCountButton: View {
    let value: Int
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(value)")
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

private struct OwnerProfileSaveTile: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .black))
                    Text("\(value)")
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

private struct ProfileCalendarSection: View {
    let insights: ProfileInsights
    @Binding var selectedMonth: Date

    private var calendar: Calendar { .current }
    private var weekdays: [String] { calendar.veryShortStandaloneWeekdaySymbols }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: 7) }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("your calendar")
                        .font(.system(size: 23, weight: .black))
                    Text(monthTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                HStack(spacing: WanderTheme.spacing1) {
                    ProfileMonthButton(systemImage: "chevron.left") { shiftMonth(-1) }
                    ProfileMonthButton(systemImage: "chevron.right") { shiftMonth(1) }
                }
            }

            HStack(spacing: 0) {
                ProfileCalendarMetric(value: insights.monthSpotCount, label: "spots ranked")
                ProfileCalendarMetric(value: insights.monthCategoryCount, label: "cuisines")
                ProfileCalendarMetric(value: insights.monthCityCount, label: "cities")
            }

            LazyVGrid(columns: columns, spacing: WanderTheme.spacing2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    ProfileCalendarDayCell(date: date, visitCount: date.flatMap { insights.monthVisitCounts[calendar.startOfDay(for: $0)] })
                }
            }

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                Text("Dates show where your Been visits happened.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))
    }

    private var monthTitle: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth),
              let days = calendar.range(of: .day, in: .month, for: selectedMonth)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let leading = Array<Date?>(repeating: nil, count: leadingCount)
        let dates = days.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: interval.start)
        }.map(Optional.some)
        return leading + dates
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonth = next
        }
    }
}

private struct ProfileMonthButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

private struct ProfileCalendarMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
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

private struct ProfileCalendarDayCell: View {
    let date: Date?
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

            if let date {
                Text("\(Calendar.current.component(.day, from: date))")
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let date else { return "" }
        let base = date.formatted(.dateTime.month(.wide).day())
        guard let visitCount else { return base }
        return "\(base), \(visitCount) \(visitCount == 1 ? "visit" : "visits")"
    }
}

private enum ProfileMapSummaryKind: String, CaseIterable, Identifiable {
    case places
    case cities
    case countries

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct ProfileMapSection: View {
    let insights: ProfileInsights
    let beenCount: Int
    @State private var selectedSummary: ProfileMapSummaryKind = .places

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("your map")
                    .font(.system(size: 23, weight: .black))
                Text("\(insights.mapCityCount) \(insights.mapCityCount == 1 ? "city" : "cities")  •  \(beenCount) Been places")
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
                ForEach(insights.mapPoints) { point in
                    Annotation(point.name, coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
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
            .accessibilityLabel("Map of your Been places")

            Picker("Map summary", selection: $selectedSummary) {
                ForEach(ProfileMapSummaryKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if summaryItems.isEmpty {
                Text(emptyCopy)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summaryItems.enumerated()), id: \.element.id) { index, item in
                        ProfileMapSummaryRow(item: item)
                        if index < summaryItems.count - 1 {
                            Divider().overlay(WanderTheme.borderHairline.color)
                        }
                    }
                }
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
    }

    private var summaryItems: [ProfileSummaryItem] {
        switch selectedSummary {
        case .places: insights.placeSummaries
        case .cities: insights.citySummaries
        case .countries: insights.countrySummaries
        }
    }

    private var emptyCopy: String {
        switch selectedSummary {
        case .places: "Your Been places will appear here."
        case .cities: "Cities appear after your Been places have location details."
        case .countries: "Countries appear after your Been places have location details."
        }
    }
}

private struct ProfileMapSummaryRow: View {
    let item: ProfileSummaryItem

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .black))
                Text("\(item.count) \(item.count == 1 ? "place" : "places")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text("\(item.percentage)%")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
    }
}
