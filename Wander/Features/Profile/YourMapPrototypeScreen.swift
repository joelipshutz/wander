import MapKit
import SwiftUI

#if DEBUG
struct YourMapPrototypeScreen: View {
    let dataset: YourMapPrototypeDataset

    @State private var mode: YourMapPrototypeMode
    @State private var lens: YourMapPrototypeLens
    @State private var cameraPosition: MapCameraPosition
    @State private var showsFilters = false
    @State private var showsSharePreview: Bool
    @State private var isLensSaved = false

    init(
        dataset: YourMapPrototypeDataset,
        initialMode: YourMapPrototypeMode = .map,
        initialShowsSharePreview: Bool = false
    ) {
        self.dataset = dataset
        _mode = State(initialValue: initialMode)
        _showsSharePreview = State(initialValue: initialShowsSharePreview)
        _lens = State(initialValue: dataset.initialLens)
        _cameraPosition = State(initialValue: .region(Self.initialRegion(for: dataset.places)))
    }

    init(
        volume: YourMapPrototypeDataVolume = .medium,
        initialMode: YourMapPrototypeMode = .map,
        initialShowsSharePreview: Bool = false
    ) {
        self.init(
            dataset: YourMapPrototypeDataset.make(volume: volume),
            initialMode: initialMode,
            initialShowsSharePreview: initialShowsSharePreview
        )
    }

    var body: some View {
        Group {
            switch mode {
            case .map:
                mapWorkspace
            case .patterns:
                patternsWorkspace
            }
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .sheet(isPresented: $showsFilters) {
            YourMapPrototypeFilterSheet(
                lens: $lens,
                places: dataset.places,
                resultCount: filteredPlaces.count
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsSharePreview) {
            YourMapPrototypeSharePreview(
                places: filteredPlaces,
                now: dataset.now,
                dismiss: { showsSharePreview = false }
            )
        }
        .onChange(of: lens) { _, _ in
            isLensSaved = false
        }
        .navigationTitle(mode == .map ? "Your Map" : "Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if mode == .map {
                        showsSharePreview = true
                    } else {
                        showsFilters = true
                    }
                } label: {
                    Image(systemName: mode == .map ? "square.and.arrow.up" : "slider.horizontal.3")
                }
                .accessibilityLabel(mode == .map ? "Share this lens" : "Filters")
            }
        }
        .accessibilityIdentifier("yourMap.prototype")
    }

    private var filteredPlaces: [YourMapPrototypePlace] {
        dataset.places.filter { lens.matches($0, now: dataset.now) }
    }

    private var renderedPlaces: [YourMapPrototypePlace] {
        Array(filteredPlaces.prefix(80))
    }

    private var insights: YourMapPrototypeInsights {
        YourMapPrototypeInsights(places: filteredPlaces, now: dataset.now)
    }

    private var mapWorkspace: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(renderedPlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        YourMapPrototypePin(place: place)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .ignoresSafeArea()
            .overlay {
                if filteredPlaces.isEmpty {
                    mapEmptyState
                }
            }

            VStack(spacing: 0) {
                mapHeader
                Spacer(minLength: WanderTheme.spacing4)
                modePicker
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing2)
                lensDeck
            }
        }
        .accessibilityIdentifier("yourMap.prototype.map")
    }

    private var mapHeader: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Button {
                showsFilters = true
            } label: {
                HStack(spacing: WanderTheme.spacing1) {
                    Image(systemName: "calendar")
                    Text(lens.timeRange.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .black))
                }
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceBone.color.opacity(0.96), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourMap.prototype.time")

            Spacer(minLength: 0)

            YourMapPrototypeCircleButton(
                systemImage: "slider.horizontal.3",
                label: "Filters",
                action: { showsFilters = true }
            )
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(
            LinearGradient(
                colors: [WanderTheme.canvasWarm.color.opacity(0.98), WanderTheme.canvasWarm.color.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(YourMapPrototypeMode.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = option
                    }
                } label: {
                    Text(option.title)
                        .font(WanderTypography.label)
                        .foregroundStyle(mode == option ? WanderTheme.terracottaDark.color : WanderTheme.textInk.color)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                        .background(mode == option ? WanderTheme.surfaceRaised.color : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(WanderTheme.surfaceBone.color.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        .shadow(color: WanderTheme.textInk.color.opacity(0.09), radius: 8, y: 3)
        .accessibilityIdentifier("yourMap.prototype.mode")
    }

    private var lensDeck: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Capsule()
                .fill(WanderTheme.borderStrong.color)
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            ScrollView(.horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(activeLensChips, id: \YourMapPrototypeLensChip.id) { chip in
                        YourMapPrototypeLensChipView(chip: chip)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(filteredPlaces.count)")
                    .font(WanderTypography.editorialDisplay)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .contentTransition(.numericText())
                Text("of \(dataset.places.count) places")
                    .font(WanderTypography.emphasizedBody)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(filteredPlaces.count) of \(dataset.places.count) places")

            HStack(spacing: WanderTheme.spacing2) {
                YourMapPrototypeActionButton(title: "Filters", systemImage: "slider.horizontal.3") {
                    showsFilters = true
                }
                .accessibilityIdentifier("yourMap.prototype.filters")

                YourMapPrototypeActionButton(
                    title: isLensSaved ? "Saved" : "Save lens",
                    systemImage: isLensSaved ? "checkmark" : "bookmark"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isLensSaved.toggle()
                    }
                }
                .accessibilityIdentifier("yourMap.prototype.saveLens")

                YourMapPrototypeActionButton(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    isProminent: true
                ) {
                    showsSharePreview = true
                }
                .accessibilityIdentifier("yourMap.prototype.share")
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color.opacity(0.97))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: WanderTheme.radiusSheet, topTrailingRadius: WanderTheme.radiusSheet))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: WanderTheme.radiusSheet, topTrailingRadius: WanderTheme.radiusSheet)
                .stroke(WanderTheme.borderHairline.color)
        }
        .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 18, y: -3)
    }

    private var patternsWorkspace: some View {
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
            ScrollView {
                VStack(spacing: WanderTheme.spacing3) {
                    yearComparisonPicker
                    YourMapPrototypeMiniMap(places: filteredPlaces)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

                    if filteredPlaces.isEmpty {
                        patternsEmptyState
                    } else {
                        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                            categoryMixCard
                            repeatRateCard
                        }
                        yearComparisonCard
                        insightCard
                    }

                    patternFilterRow
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollIndicators(.hidden)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .accessibilityIdentifier("yourMap.prototype.patterns")
    }

    private var yearComparisonPicker: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Text("\(currentYear)")
                .font(WanderTypography.label)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.categoryMoss.color, in: Capsule())
            Text("vs")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
            Text("\(currentYear - 1)")
                .font(WanderTypography.label)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceBone.color, in: Capsule())
                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Comparing \(currentYear) with \(currentYear - 1)")
    }

    private var categoryMixCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("category mix", systemImage: "chart.bar.fill")
                .font(WanderTypography.label)
            ForEach(insights.categoryBreakdown.prefix(5)) { item in
                YourMapPrototypeBarRow(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
    }

    private var repeatRateCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("repeat rate", systemImage: "arrow.triangle.2.circlepath")
                .font(WanderTypography.label)
            Text("\(repeatRatePercentage)%")
                .font(WanderTypography.editorialDisplay.monospacedDigit())
                .foregroundStyle(WanderTheme.categoryMoss.color)
            Text("of checked-in places are somewhere you returned to")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            YourMapPrototypeSparkline()
                .frame(height: 32)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
    }

    private var yearComparisonCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("\(currentYear) vs \(currentYear - 1)")
                .font(WanderTypography.editorialCardTitle)
            YourMapPrototypeComparisonRow(
                title: "Places",
                current: insights.thisYearCount,
                previous: insights.previousYearCount,
                maximum: max(insights.thisYearCount, insights.previousYearCount, 1)
            )
            YourMapPrototypeComparisonRow(
                title: "Repeats",
                current: insights.repeatCount,
                previous: max(insights.repeatCount - max(insights.repeatCount / 4, 1), 0),
                maximum: max(insights.repeatCount, 1)
            )
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
    }

    private var insightCard: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WanderTheme.categorySun.color)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.sunTint.color, in: Circle())
            Text(insights.insight)
                .font(WanderTypography.emphasizedBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.sunTint.color.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.categorySun.color.opacity(0.45)))
    }

    private var patternFilterRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: WanderTheme.spacing2)], spacing: WanderTheme.spacing2) {
            ForEach(["Time", "Category", "City", "Tags", "Rating"], id: \.self) { title in
                Button {
                    showsFilters = true
                } label: {
                    HStack(spacing: WanderTheme.spacing1) {
                        Text(title)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .black))
                    }
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.surfaceBone.color, in: Capsule())
                    .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("yourMap.prototype.patternFilters")
    }

    private var mapEmptyState: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: dataset.places.isEmpty ? "mappin.and.ellipse" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(dataset.places.isEmpty ? "Your map starts with one place" : "No places match this lens")
                .font(WanderTypography.editorialCardTitle)
                .multilineTextAlignment(.center)
            Text(dataset.places.isEmpty ? "Add a place worth remembering and it will appear here." : "Keep the lens or loosen one filter. Your choices stay intact until you reset them.")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
            if !dataset.places.isEmpty {
                Button("Reset lens") {
                    lens = YourMapPrototypeLens()
                }
                .font(WanderTypography.label)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.terracotta.color, in: Capsule())
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: 300)
        .background(WanderTheme.surfaceBone.color.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
        .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 16, y: 6)
        .padding(.bottom, 280)
    }

    private var patternsEmptyState: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text("No patterns in this slice yet")
                .font(WanderTypography.editorialCardTitle)
            Text("Try a wider time range or reset one filter.")
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity)
        .padding(WanderTheme.spacing6)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var activeLensChips: [YourMapPrototypeLensChip] {
        var chips: [YourMapPrototypeLensChip] = []
        if lens.timeRange != .all {
            chips.append(.init(id: "time", title: lens.timeRange.title, systemImage: "calendar"))
        }
        chips.append(contentsOf: lens.statuses.sorted { $0.rawValue < $1.rawValue }.map {
            .init(id: "status-\($0.rawValue)", title: $0.title, systemImage: $0.systemImage)
        })
        chips.append(contentsOf: lens.categories.sorted().map {
            .init(id: "category-\($0)", title: $0, systemImage: categorySystemImage($0))
        })
        chips.append(contentsOf: lens.cities.sorted().map {
            .init(id: "city-\($0)", title: $0, systemImage: "mappin")
        })
        chips.append(contentsOf: lens.countries.sorted().map {
            .init(id: "country-\($0)", title: $0, systemImage: "globe.americas.fill")
        })
        chips.append(contentsOf: lens.tags.sorted().map {
            .init(id: "tag-\($0)", title: $0, systemImage: "tag.fill")
        })
        if let minimumRating = lens.minimumRating {
            chips.append(.init(id: "rating", title: "\(minimumRating.formatted())+", systemImage: "star.fill"))
        }
        if lens.repeatOnly {
            chips.append(.init(id: "repeat", title: "Repeat visits", systemImage: "arrow.triangle.2.circlepath"))
        }
        return chips.isEmpty
            ? [.init(id: "all", title: "All places", systemImage: "map.fill")]
            : chips
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: dataset.now)
    }

    private var repeatRatePercentage: Int {
        Int((insights.repeatRate * 100).rounded())
    }

    private static func initialRegion(for places: [YourMapPrototypePlace]) -> MKCoordinateRegion {
        let centerPlace = places.first { $0.city == "Los Angeles" }
        let center = centerPlace?.coordinate ?? CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.34, longitudeDelta: 0.34)
        )
    }
}

private struct YourMapPrototypeFilterSheet: View {
    @Binding var lens: YourMapPrototypeLens
    let places: [YourMapPrototypePlace]
    let resultCount: Int
    @Environment(\.dismiss) private var dismiss

    private var categories: [String] {
        sortedOptions(places.map(\.category), fallback: ["Coffee", "Restaurants", "Bars", "Bakeries", "Outdoors"])
    }

    private var cities: [String] {
        sortedOptions(places.map(\.city), fallback: ["Los Angeles", "San Francisco", "New York", "Portland"])
    }

    private var countries: [String] {
        sortedOptions(places.map(\.country), fallback: ["United States", "France"])
    }

    private var tags: [String] {
        sortedOptions(places.flatMap(\.tags), fallback: ["calm", "date night", "laptop", "morning", "weekend"])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    filterSection(title: "Time", detail: "Choose one") {
                        optionGrid {
                            ForEach(YourMapPrototypeTimeRange.allCases) { range in
                                filterChip(
                                    title: range.title,
                                    systemImage: "calendar",
                                    isSelected: lens.timeRange == range
                                ) {
                                    lens.timeRange = range
                                }
                            }
                        }
                    }

                    filterSection(title: "Status", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(YourMapPrototypeStatus.allCases) { status in
                                filterChip(
                                    title: status.title,
                                    systemImage: status.systemImage,
                                    isSelected: lens.statuses.contains(status)
                                ) {
                                    lens.toggleStatus(status)
                                }
                            }
                        }
                    }

                    filterSection(title: "Category", detail: "Values combine together") {
                        optionGrid {
                            ForEach(categories, id: \.self) { category in
                                filterChip(
                                    title: category,
                                    systemImage: categorySystemImage(category),
                                    isSelected: lens.categories.contains(category)
                                ) {
                                    lens.toggleCategory(category)
                                }
                            }
                        }
                    }

                    filterSection(title: "City", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(cities, id: \.self) { city in
                                filterChip(
                                    title: city,
                                    systemImage: "mappin",
                                    isSelected: lens.cities.contains(city)
                                ) {
                                    lens.toggleCity(city)
                                }
                            }
                        }
                    }

                    filterSection(title: "Country", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(countries, id: \.self) { country in
                                filterChip(
                                    title: country,
                                    systemImage: "globe.americas.fill",
                                    isSelected: lens.countries.contains(country)
                                ) {
                                    lens.toggleCountry(country)
                                }
                            }
                        }
                    }

                    filterSection(title: "Tags", detail: "Any selected tag can match") {
                        optionGrid {
                            ForEach(tags, id: \.self) { tag in
                                filterChip(
                                    title: tag,
                                    systemImage: "tag.fill",
                                    isSelected: lens.tags.contains(tag)
                                ) {
                                    lens.toggleTag(tag)
                                }
                            }
                        }
                    }

                    filterSection(title: "Rating", detail: "Choose one") {
                        optionGrid {
                            ForEach(YourMapPrototypeRatingOption.allCases) { option in
                                filterChip(
                                    title: option.title,
                                    systemImage: "star.fill",
                                    isSelected: lens.minimumRating == option.minimum
                                ) {
                                    lens.minimumRating = option.minimum
                                }
                            }
                        }
                    }

                    Toggle(isOn: $lens.repeatOnly) {
                        Label("Repeat visits only", systemImage: "arrow.triangle.2.circlepath")
                            .font(WanderTypography.label)
                    }
                    .tint(WanderTheme.terracotta.color)
                    .frame(minHeight: WanderTheme.tapMinimum)

                    Text("Values within a section combine. Sections narrow the map together. A zero-result lens stays selected until you change or reset it.")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        lens = YourMapPrototypeLens()
                    }
                    .disabled(lens.activeSectionCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider().overlay(WanderTheme.borderHairline.color)
                    Button {
                        dismiss()
                    } label: {
                        Text("Show \(resultCount) \(resultCount == 1 ? "place" : "places")")
                            .font(WanderTypography.control)
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(WanderTheme.terracotta.color, in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .padding(WanderTheme.spacing4)
                }
                .background(WanderTheme.surfaceBone.color)
            }
        }
        .tint(WanderTheme.terracottaDark.color)
        .accessibilityIdentifier("yourMap.prototype.filterSheet")
    }

    private func filterSection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(WanderTypography.editorialSectionTitle)
                Spacer()
                Text(detail)
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            content()
        }
    }

    private func optionGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: WanderTheme.spacing2)],
            alignment: .leading,
            spacing: WanderTheme.spacing2,
            content: content
        )
    }

    private func filterChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(WanderTypography.metadata)
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            .padding(.horizontal, WanderTheme.spacing2)
            .background(isSelected ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? WanderTheme.terracottaDark.color : WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sortedOptions(_ values: [String], fallback: [String]) -> [String] {
        let resolved = Set(values).sorted()
        return resolved.isEmpty ? fallback : resolved
    }
}

private struct YourMapPrototypeSharePreview: View {
    let places: [YourMapPrototypePlace]
    let now: Date
    let dismiss: () -> Void

    @State private var audience: YourMapPrototypeShareAudience = .friends
    @State private var format: YourMapPrototypeShareFormat = .staticImage
    @State private var showsPrototypeNotice = false

    private var insights: YourMapPrototypeInsights {
        YourMapPrototypeInsights(places: places, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WanderTheme.spacing2) {
                YourMapPrototypeCircleButton(systemImage: "xmark", label: "Close share preview", action: dismiss)
                Spacer()
                Text("share your map")
                    .font(WanderTypography.editorialDisplay)
                Spacer()
                Color.clear.frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, WanderTheme.spacing3)

            ScrollView {
                VStack(spacing: WanderTheme.spacing3) {
                    shareStoryCard
                    audienceRow
                    privacyRow(
                        title: "Private notes excluded",
                        detail: "Your personal notes won't be shared.",
                        systemImage: "lock.fill"
                    )
                    privacyRow(
                        title: "Exact locations hidden",
                        detail: "Only approximate areas are shown.",
                        systemImage: "location.slash.fill"
                    )

                    Picker("Share format", selection: $format) {
                        ForEach(YourMapPrototypeShareFormat.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .accessibilityIdentifier("yourMap.prototype.shareFormat")

                    Button {
                        showsPrototypeNotice = true
                    } label: {
                        Label("Create share link", systemImage: "link")
                            .font(WanderTypography.control)
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(WanderTheme.terracotta.color, in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yourMap.prototype.createShare")
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollIndicators(.hidden)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
        .alert("Prototype only", isPresented: $showsPrototypeNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This review build does not create a public link or send place data.")
        }
        .accessibilityIdentifier("yourMap.prototype.sharePreview")
    }

    private var shareStoryCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("Coffee I’d go back to")
                .font(WanderTypography.editorialDisplay)
                .fixedSize(horizontal: false, vertical: true)
            YourMapPrototypeMiniMap(places: places)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            HStack(spacing: WanderTheme.spacing3) {
                shareStat(
                    value: "\(places.count)",
                    label: "places",
                    systemImage: "cup.and.saucer.fill",
                    color: WanderTheme.categoryMoss.color
                )
                shareStat(
                    value: "\(Int((insights.repeatRate * 100).rounded()))%",
                    label: "repeat rate",
                    systemImage: "star.fill",
                    color: WanderTheme.categorySun.color
                )
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
    }

    private var audienceRow: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Label("Share with", systemImage: "person.2.fill")
                .font(WanderTypography.label)
            Spacer()
            Menu {
                ForEach(YourMapPrototypeShareAudience.allCases) { option in
                    Button(option.title) {
                        audience = option
                    }
                }
            } label: {
                HStack(spacing: WanderTheme.spacing1) {
                    Text(audience.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .black))
                }
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(minHeight: WanderTheme.tapMinimum)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(WanderTheme.borderHairline.color))
    }

    private func privacyRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WanderTypography.label)
                Text(detail)
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(WanderTheme.categoryMoss.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 66)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(WanderTheme.borderHairline.color))
    }

    private func shareStat(
        value: String,
        label: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(spacing: WanderTheme.spacing1) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(WanderTypography.editorialDisplay.monospacedDigit())
            Text(label)
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(WanderTheme.surfaceRaised.color, in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private struct YourMapPrototypeMiniMap: View {
    let places: [YourMapPrototypePlace]

    var body: some View {
        Map(position: .constant(.region(region)), interactionModes: []) {
            ForEach(Array(places.prefix(28))) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Circle()
                        .fill(categoryColor(place.category))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview map with \(places.count) places")
    }

    private var region: MKCoordinateRegion {
        guard let first = places.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
                span: MKCoordinateSpan(latitudeDelta: 0.34, longitudeDelta: 0.34)
            )
        }
        return MKCoordinateRegion(
            center: first.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    }
}

private struct YourMapPrototypePin: View {
    let place: YourMapPrototypePlace

    var body: some View {
        ZStack {
            Circle()
                .fill(place.status == .been ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color)
            Circle()
                .stroke(
                    WanderTheme.terracotta.color,
                    style: StrokeStyle(lineWidth: 2, dash: place.status == .wanna ? [3, 2] : [])
                )
            if place.visitCount > 1 {
                Text("\(place.visitCount)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(place.status == .been ? WanderTheme.textOnAction.color : WanderTheme.terracottaDark.color)
            }
        }
        .frame(width: 28, height: 28)
        .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 3, y: 2)
        .accessibilityLabel("\(place.name), \(place.status.title), \(place.visitCount) visits")
    }
}

private struct YourMapPrototypeLensChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

private struct YourMapPrototypeLensChipView: View {
    let chip: YourMapPrototypeLensChip

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: chip.systemImage)
            Text(chip.title)
                .lineLimit(1)
        }
        .font(WanderTypography.metadata)
        .foregroundStyle(WanderTheme.textOnAction.color)
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: WanderTheme.tapMinimum)
        .background(WanderTheme.terracotta.color, in: Capsule())
    }
}

private struct YourMapPrototypeActionButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WanderTheme.spacing1) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(WanderTypography.metadata)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isProminent ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                isProminent ? WanderTheme.terracotta.color : WanderTheme.surfaceRaised.color,
                in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
            )
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .stroke(WanderTheme.borderHairline.color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct YourMapPrototypeCircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceBone.color.opacity(0.96), in: Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct YourMapPrototypeBarRow: View {
    let item: YourMapPrototypeBreakdownItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.title)
                Spacer()
                Text("\(Int((item.fraction * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(WanderTypography.metadata)
            GeometryReader { geometry in
                Capsule()
                    .fill(WanderTheme.surfaceSand.color)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(categoryColor(item.title))
                            .frame(width: geometry.size.width * max(item.fraction, 0.03))
                    }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.count) places")
    }
}

private struct YourMapPrototypeComparisonRow: View {
    let title: String
    let current: Int
    let previous: Int
    let maximum: Int

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            HStack {
                Text(title).font(WanderTypography.label)
                Spacer()
                Text("\(current) / \(previous)")
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule()
                        .fill(WanderTheme.categoryMoss.color)
                        .frame(width: geometry.size.width * CGFloat(current) / CGFloat(maximum), height: 7)
                    Capsule()
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: geometry.size.width * CGFloat(previous) / CGFloat(maximum), height: 7)
                }
            }
            .frame(height: 17)
        }
    }
}

private struct YourMapPrototypeSparkline: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points: [CGPoint] = [
                    CGPoint(x: 0, y: 24),
                    CGPoint(x: geometry.size.width * 0.18, y: 18),
                    CGPoint(x: geometry.size.width * 0.32, y: 21),
                    CGPoint(x: geometry.size.width * 0.48, y: 10),
                    CGPoint(x: geometry.size.width * 0.62, y: 14),
                    CGPoint(x: geometry.size.width * 0.78, y: 5),
                    CGPoint(x: geometry.size.width, y: 9)
                ]
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(WanderTheme.categoryMoss.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private enum YourMapPrototypeRatingOption: String, CaseIterable, Identifiable {
    case any
    case fourPlus
    case fourPointFivePlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .fourPlus: "4+ stars"
        case .fourPointFivePlus: "4.5+ stars"
        }
    }

    var minimum: Double? {
        switch self {
        case .any: nil
        case .fourPlus: 4
        case .fourPointFivePlus: 4.5
        }
    }
}

private enum YourMapPrototypeShareAudience: String, CaseIterable, Identifiable {
    case onlyMe
    case friends
    case peopleWithLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyMe: "Only me"
        case .friends: "Friends"
        case .peopleWithLink: "People with link"
        }
    }
}

private enum YourMapPrototypeShareFormat: String, CaseIterable, Identifiable {
    case staticImage
    case liveView

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staticImage: "Static image"
        case .liveView: "Live view"
        }
    }

    var systemImage: String {
        switch self {
        case .staticImage: "photo"
        case .liveView: "dot.radiowaves.left.and.right"
        }
    }
}

private extension YourMapPrototypePlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private func categorySystemImage(_ category: String) -> String {
    switch category.lowercased() {
    case "coffee": "cup.and.saucer.fill"
    case "restaurants": "fork.knife"
    case "bars": "wineglass.fill"
    case "bakeries": "birthday.cake.fill"
    case "outdoors": "leaf.fill"
    default: "mappin"
    }
}

private func categoryColor(_ category: String) -> Color {
    switch category.lowercased() {
    case "coffee": WanderTheme.categoryMoss.color
    case "restaurants": WanderTheme.terracotta.color
    case "bars": WanderTheme.categorySun.color
    case "bakeries": WanderTheme.pinSocial.color
    case "outdoors": WanderTheme.categorySage.color
    default: WanderTheme.textMuted.color
    }
}

#Preview("Your Map Prototype") {
    NavigationStack {
        YourMapPrototypeScreen(volume: .medium)
    }
}

#Preview("Your Map Prototype Empty") {
    NavigationStack {
        YourMapPrototypeScreen(volume: .empty)
    }
}
#endif
