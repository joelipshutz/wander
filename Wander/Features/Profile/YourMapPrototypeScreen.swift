import MapKit
import SwiftUI
import UIKit

struct YourMapPrototypeScreen: View {
    @Environment(\.astirBrandMode) private var brandMode
    let dataset: YourMapPrototypeDataset
    let viewerID: String?
    let mapTitle: String
    let pinOwnership: MapPinSaveOwnership

    @State private var mode: YourMapPrototypeMode
    @State private var lens: YourMapPrototypeLens
    @State private var cameraPosition: MapCameraPosition
    @State private var cameraRegion: MKCoordinateRegion
    @State private var showsFilters = false
    @State private var showsSharePreview: Bool
    @State private var savedLenses: [YourMapPrototypeSavedLens] = []
    @State private var selectedPlaceID: String?

    init(
        dataset: YourMapPrototypeDataset,
        viewerID: String? = nil,
        mapTitle: String = "Your Map",
        pinOwnership: MapPinSaveOwnership = .currentUser,
        initialMode: YourMapPrototypeMode = .map,
        initialShowsSharePreview: Bool = false
    ) {
        self.dataset = dataset
        self.viewerID = viewerID
        self.mapTitle = mapTitle
        self.pinOwnership = pinOwnership
        _mode = State(initialValue: initialMode)
        _showsSharePreview = State(initialValue: initialShowsSharePreview)
        _lens = State(initialValue: dataset.initialLens)
        let initialRegion = Self.initialRegion(for: dataset.places)
        _cameraPosition = State(initialValue: .region(initialRegion))
        _cameraRegion = State(initialValue: initialRegion)
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
        .foregroundStyle(brandMode.primaryText)
        .tint(brandMode.accent)
        .sheet(isPresented: $showsFilters) {
            YourMapPrototypeFilterSheet(
                lens: $lens,
                savedLenses: $savedLenses,
                places: dataset.places,
                resultCount: filteredPlaces.count
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsSharePreview) {
            YourMapPrototypeSharePreview(
                places: filteredPlaces,
                lens: lens,
                now: dataset.now,
                pinOwnership: pinOwnership,
                dismiss: { showsSharePreview = false }
            )
        }
        .navigationTitle(mode == .map ? mapTitle : "Patterns")
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
        .onChange(of: lens) { _, updatedLens in
            guard let selectedPlaceID,
                  !dataset.places.contains(where: {
                      $0.id == selectedPlaceID && updatedLens.matches($0, now: dataset.now)
                  })
            else { return }
            self.selectedPlaceID = nil
        }
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

    private var selectedVisiblePlace: VisiblePlace? {
        guard let selectedPlaceID,
              renderedPlaces.contains(where: { $0.id == selectedPlaceID })
        else { return nil }
        return dataset.visiblePlaceByPlaceID[selectedPlaceID]
    }

    private var mapWorkspace: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(renderedPlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        YourMapPrototypeSelectablePin(
                            place: place,
                            isSelected: selectedPlaceID == place.id,
                            pinOwnership: pinOwnership
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedPlaceID = place.id
                                cameraPosition = .region(selectedRegion(for: place))
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraRegion = context.region
            }
            .ignoresSafeArea()
            .overlay {
                if filteredPlaces.isEmpty {
                    mapEmptyState
                }
            }

            selectedPlaceProfileSurface
                .padding(.bottom, 72)
                .zIndex(30)

            VStack(spacing: 0) {
                mapHeader
                Spacer(minLength: WanderTheme.spacing4)
                modePicker
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing4)
            }
            .zIndex(40)
        }
    }

    @ViewBuilder
    private var selectedPlaceProfileSurface: some View {
        if let selectedVisiblePlace {
            PlaceProfileMapSurface(
                place: PlaceSheetPlace(visiblePlace: selectedVisiblePlace),
                saves: [
                    PlaceSaveSummary(
                        visiblePlace: selectedVisiblePlace,
                        attributes: selectedVisiblePlace.attributes
                    )
                ],
                tasteSaves: [],
                currentUserID: viewerID ?? selectedVisiblePlace.owner.id,
                viewerLocation: nil,
                action: .none,
                onOpen: {},
                onAction: {},
                onReady: {}
            )
        }
    }

    private var mapHeader: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Spacer(minLength: 0)

            Button {
                showsFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(brandMode.primaryText)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .astirGlassSurface(
                        cornerRadius: WanderTheme.tapMinimum / 2,
                        castsShadow: true
                    )
                    .overlay(alignment: .topTrailing) {
                        if lens.activeSectionCount > 0 {
                            Text("\(lens.activeSectionCount)")
                                .font(AstirTypography.metadata)
                                .foregroundStyle(brandMode.accentForeground)
                                .frame(width: 19, height: 19)
                                .background(brandMode.accent, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters, \(lens.activeSectionCount) active")
            .accessibilityIdentifier("yourMap.prototype.filters")
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(
            LinearGradient(
                colors: [brandMode.background.opacity(0.88), brandMode.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var modePicker: some View {
        AstirEditorialSegmentedSwitch(
            options: YourMapPrototypeMode.allCases.map {
                WanderSegmentOption(id: $0.rawValue, title: $0.title)
            },
            selection: Binding(
                get: { mode.rawValue },
                set: { rawValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = YourMapPrototypeMode(rawValue: rawValue) ?? .map
                    }
                }
            )
        )
        .accessibilityIdentifier("yourMap.prototype.mode")
    }

    private var patternsWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                if filteredPlaces.isEmpty {
                    patternsEmptyState
                } else {
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        categoryMixCard
                        repeatRateCard
                    }
                    locationFootprintCard
                    monthlyRhythmCard
                    returnMagnetsCard
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(brandMode.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            modePicker
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .background(
                    LinearGradient(
                        colors: [brandMode.background.opacity(0), brandMode.background],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .accessibilityIdentifier("yourMap.prototype.patterns")
    }

    private var categoryMixCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("category mix", systemImage: "chart.bar.fill")
                .font(AstirTypography.label)
            ForEach(insights.categoryBreakdown.prefix(5)) { item in
                YourMapPrototypeBarRow(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
    }

    private var repeatRateCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("repeat rate", systemImage: "arrow.triangle.2.circlepath")
                .font(AstirTypography.label)
            Text("\(repeatRatePercentage)%")
                .font(AstirTypography.screenTitle.monospacedDigit())
                .foregroundStyle(brandMode.accent)
            Text("of checked-in places are somewhere you returned to")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            YourMapPrototypeSparkline()
                .frame(height: 32)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
    }


    private var locationFootprintCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .firstTextBaseline) {
                Label("cities & countries", systemImage: "globe.americas.fill")
                    .font(AstirTypography.cardTitle)
                Spacer()
                Text("\(insights.cityBreakdown.count) · \(insights.countryBreakdown.count)")
                    .font(AstirTypography.metadata.monospacedDigit())
                    .foregroundStyle(brandMode.secondaryText)
            }

            ForEach(insights.cityBreakdown.prefix(4)) { item in
                YourMapPrototypeBarRow(item: item)
            }

            ScrollView(.horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(insights.countryBreakdown) { item in
                        Label("\(item.title) · \(item.count)", systemImage: "flag.fill")
                            .font(AstirTypography.metadata)
                            .padding(.horizontal, WanderTheme.spacing3)
                            .frame(minHeight: 36)
                            .background(
                                brandMode.recessedBackground,
                                in: RoundedRectangle(cornerRadius: WanderTheme.radiusSmall, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: WanderTheme.radiusSmall, style: .continuous)
                                    .stroke(brandMode.border)
                            )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .accessibilityIdentifier("yourMap.prototype.citiesCountries")
    }

    private var monthlyRhythmCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Label("month by month", systemImage: "calendar")
                .font(AstirTypography.cardTitle)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: WanderTheme.spacing2
            ) {
                ForEach(insights.monthlyActivity) { month in
                    VStack(spacing: 5) {
                        Text(month.shortTitle)
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.secondaryText)
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                brandMode.accent.opacity(
                                    month.count == 0 ? 0.10 : 0.28 + (0.72 * month.intensity)
                                )
                            )
                            .frame(height: 30)
                            .overlay {
                                Text("\(month.count)")
                                    .font(AstirTypography.metadata.monospacedDigit())
                                    .foregroundStyle(month.intensity > 0.55 ? brandMode.accentForeground : brandMode.primaryText)
                            }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(month.title), \(month.count) places")
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .accessibilityIdentifier("yourMap.prototype.monthHeatMap")
    }

    private var returnMagnetsCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Label("return magnets", systemImage: "arrow.triangle.2.circlepath")
                .font(AstirTypography.cardTitle)

            if insights.returnMagnets.isEmpty {
                Text("Places you revisit will collect here.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            } else {
                ForEach(Array(insights.returnMagnets.prefix(4).enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: WanderTheme.spacing3) {
                        Text("\(index + 1)")
                            .font(AstirTypography.label.monospacedDigit())
                            .foregroundStyle(brandMode.accent)
                            .frame(width: 24, height: 24)
                            .background(brandMode.accentWash, in: Circle())
                        WanderCategoryEmoji(category: place.category, name: place.name, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(AstirTypography.label)
                                .lineLimit(1)
                            Text(place.city)
                                .font(AstirTypography.metadata)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Text("\(place.visitCount) visits")
                            .font(AstirTypography.metadata.monospacedDigit())
                            .foregroundStyle(brandMode.accent)
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)

                    if index < min(insights.returnMagnets.count, 4) - 1 {
                        Divider().overlay(brandMode.border)
                    }
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .accessibilityIdentifier("yourMap.prototype.returnMagnets")
    }

    private var mapEmptyState: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: dataset.places.isEmpty ? "mappin.and.ellipse" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(brandMode.accent)
            Text(dataset.places.isEmpty ? "\(mapTitle) has no places you can see yet" : "No places match this lens")
                .font(AstirTypography.cardTitle)
                .multilineTextAlignment(.center)
            Text(dataset.places.isEmpty ? emptyMapDetail : "Keep the lens or loosen one filter. Your choices stay intact until you reset them.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .multilineTextAlignment(.center)
            if !dataset.places.isEmpty {
                Button("Reset lens") {
                    lens = YourMapPrototypeLens()
                }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(
                    brandMode.accent,
                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                )
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: 300)
        .background(brandMode.raisedBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
        .padding(.bottom, 84)
    }

    private var emptyMapDetail: String {
        mapTitle == "Your Map"
            ? "Add a place worth remembering and it will appear here."
            : "Places they choose to share with you will appear here."
    }

    private var patternsEmptyState: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(brandMode.accent)
            Text("No patterns in this slice yet")
                .font(AstirTypography.cardTitle)
            Text("Try a wider time range or reset one filter.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(WanderTheme.spacing6)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var repeatRatePercentage: Int {
        Int((insights.repeatRate * 100).rounded())
    }

    private func selectedRegion(for place: YourMapPrototypePlace) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: place.coordinate.latitude - (cameraRegion.span.latitudeDelta * 0.18),
                longitude: place.coordinate.longitude
            ),
            span: cameraRegion.span
        )
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
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var lens: YourMapPrototypeLens
    @Binding var savedLenses: [YourMapPrototypeSavedLens]
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
                    savedLensSection

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
                            .font(AstirTypography.label)
                    }
                    .tint(brandMode.accent)
                    .frame(minHeight: WanderTheme.tapMinimum)

                    Text("Values within a section combine. Sections narrow the map together. A zero-result lens stays selected until you change or reset it.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .background(brandMode.background)
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
                    Divider().overlay(brandMode.border)
                    HStack(spacing: WanderTheme.spacing2) {
                        Button {
                            guard !isCurrentLensSaved else { return }
                            savedLenses.append(
                                YourMapPrototypeSavedLens(
                                    lens: lens,
                                    ordinal: savedLenses.count + 1
                                )
                            )
                        } label: {
                            Label(isCurrentLensSaved ? "Saved" : "Save lens", systemImage: isCurrentLensSaved ? "checkmark" : "bookmark")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    brandMode.recessedBackground,
                                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                        .stroke(brandMode.border)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(lens.activeSectionCount == 0 || isCurrentLensSaved)
                        .opacity(lens.activeSectionCount == 0 ? 0.5 : 1)
                        .accessibilityIdentifier("yourMap.prototype.saveLens")

                        Button {
                            dismiss()
                        } label: {
                            Text("Show \(resultCount)")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.accentForeground)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    brandMode.accent,
                                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(WanderTheme.spacing4)
                }
                .background(brandMode.raisedBackground)
            }
        }
        .foregroundStyle(brandMode.primaryText)
        .background(brandMode.background.ignoresSafeArea())
        .tint(brandMode.accent)
    }

    private var savedLensSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved lenses")
                    .font(AstirTypography.sectionTitle)
                Spacer()
                Text("Reusable filters")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
            }

            Text("Save lens stores this exact filter recipe. Tap it later to reapply the same slice; it does not share any places.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if savedLenses.isEmpty {
                Label("No saved lenses yet", systemImage: "bookmark")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .background(
                        brandMode.recessedBackground,
                        in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                            .stroke(brandMode.border)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(savedLenses) { savedLens in
                        YourMapPrototypeSavedLensRow(
                            savedLens: savedLens,
                            isSelected: savedLens.lens == lens,
                            onSelect: {
                                lens = savedLens.lens
                            },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    savedLenses.removeAll { $0.id == savedLens.id }
                                }
                            }
                        )

                        if savedLens.id != savedLenses.last?.id {
                            Divider()
                                .overlay(brandMode.border)
                        }
                    }
                }
                .background(brandMode.raisedBackground)
                .overlay(alignment: .top) {
                    Divider().overlay(brandMode.border)
                }
                .overlay(alignment: .bottom) {
                    Divider().overlay(brandMode.border)
                }
                .padding(.horizontal, -WanderTheme.spacing4)
            }
        }
    }

    private var isCurrentLensSaved: Bool {
        savedLenses.contains { $0.lens == lens }
    }

    private func filterSection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AstirTypography.sectionTitle)
                Spacer()
                Text(detail)
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
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
            VStack(spacing: 0) {
                HStack(spacing: WanderTheme.spacing1) {
                    Image(systemName: systemImage)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .font(AstirTypography.label)
                .foregroundStyle(isSelected ? brandMode.accent : brandMode.primaryText)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing2)

                Rectangle()
                    .fill(isSelected ? brandMode.accent : brandMode.border)
                    .frame(height: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
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
    @Environment(\.astirBrandMode) private var brandMode
    let places: [YourMapPrototypePlace]
    let lens: YourMapPrototypeLens
    let now: Date
    let pinOwnership: MapPinSaveOwnership
    let dismiss: () -> Void

    @State private var format: YourMapPrototypeShareFormat = .staticSnapshot
    @State private var createdLink: YourMapPrototypeShareLink?
    @State private var didCopyLink = false

    private var insights: YourMapPrototypeInsights {
        YourMapPrototypeInsights(places: places, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WanderTheme.spacing2) {
                YourMapPrototypeCircleButton(systemImage: "xmark", label: "Close share preview", action: dismiss)
                Spacer()
                Text("Share your map")
                    .font(AstirTypography.sectionTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Color.clear.frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.vertical, WanderTheme.spacing3)

            ScrollView {
                VStack(spacing: WanderTheme.spacing3) {
                    shareStoryCard
                    privacyRow(
                        title: "Anyone with the link",
                        detail: "No account is required to open and explore this map.",
                        systemImage: "link"
                    )

                    AstirEditorialSegmentedSwitch(
                        options: YourMapPrototypeShareFormat.allCases.map {
                            WanderSegmentOption(id: $0.rawValue, title: $0.title)
                        },
                        selection: Binding(
                            get: { format.rawValue },
                            set: { format = YourMapPrototypeShareFormat(rawValue: $0) ?? .staticSnapshot }
                        )
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Share format")
                    .accessibilityIdentifier("yourMap.prototype.shareFormat")
                    .onChange(of: format) { _, _ in
                        createdLink = nil
                        didCopyLink = false
                    }

                    Text(formatDescription)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        createdLink = YourMapPrototypeShareLink.make(format: format)
                        didCopyLink = false
                    } label: {
                        Label("Create share link", systemImage: "link")
                            .font(AstirTypography.control)
                            .foregroundStyle(brandMode.accentForeground)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                brandMode.accent,
                                in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yourMap.prototype.createShare")

                    if let createdLink {
                        createdLinkCard(createdLink)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    privacyRow(
                        title: "Private notes stay private",
                        detail: "The link contains the map view, never your personal notes.",
                        systemImage: "lock.fill"
                    )
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollIndicators(.hidden)
        }
        .background(brandMode.background.ignoresSafeArea())
        .foregroundStyle(brandMode.primaryText)
        .accessibilityIdentifier("yourMap.prototype.sharePreview")
    }

    private var shareStoryCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text(lensTitle)
                .font(AstirTypography.screenTitle)
                .fixedSize(horizontal: false, vertical: true)
            YourMapPrototypeMiniMap(places: places, pinOwnership: pinOwnership)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            HStack(spacing: WanderTheme.spacing3) {
                shareStat(
                    value: "\(places.count)",
                    label: "places",
                    systemImage: "cup.and.saucer.fill",
                    color: brandMode.accent
                )
                shareStat(
                    value: "\(Int((insights.repeatRate * 100).rounded()))%",
                    label: "repeat rate",
                    systemImage: "star.fill",
                    color: brandMode.primaryText
                )
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
    }

    private func privacyRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AstirTypography.label)
                Text(detail)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(brandMode.accent)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 66)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(brandMode.border))
    }

    private func createdLinkCard(_ link: YourMapPrototypeShareLink) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("Your \(link.format.title.lowercased()) link is ready", systemImage: "checkmark.circle.fill")
                .font(AstirTypography.label)
                .foregroundStyle(brandMode.accent)

            Text(link.url.absoluteString)
                .font(AstirTypography.metadata.monospaced())
                .foregroundStyle(brandMode.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                UIPasteboard.general.url = link.url
                didCopyLink = true
            } label: {
                Label(didCopyLink ? "Copied" : "Copy link", systemImage: didCopyLink ? "checkmark" : "doc.on.doc")
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.primaryText)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(
                        brandMode.accentWash,
                        in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourMap.prototype.copyShareLink")
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(brandMode.accent.opacity(0.5)))
    }

    private var lensTitle: String {
        if let category = lens.categories.sorted().first {
            return "Your \(category.lowercased()) map"
        }
        if let city = lens.cities.sorted().first {
            return "Your \(city) map"
        }
        return "Your saved places"
    }

    private var formatDescription: String {
        switch format {
        case .staticSnapshot:
            "Static freezes these \(places.count) places exactly as they are when the link is created."
        case .liveLens:
            "Live keeps this lens connected, so future places that match it appear automatically."
        }
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
                .font(AstirTypography.screenTitle.monospacedDigit())
            Text(label)
                .font(AstirTypography.metadata)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(
            brandMode.recessedBackground,
            in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
        )
    }
}

private struct YourMapPrototypeMiniMap: View {
    let places: [YourMapPrototypePlace]
    let pinOwnership: MapPinSaveOwnership

    var body: some View {
        Map(position: .constant(.region(region)), interactionModes: []) {
            ForEach(Array(places.prefix(28))) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    YourMapPrototypePin(place: place, pinOwnership: pinOwnership)
                        .scaleEffect(0.58)
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
    let pinOwnership: MapPinSaveOwnership

    var body: some View {
        WanderCategoryEmoji(
            category: place.category,
            name: place.name,
            size: MapPinVisualMetrics.emojiDiameter
        )
        .frame(width: MapPinVisualMetrics.discDiameter, height: MapPinVisualMetrics.discDiameter)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Circle())
        .overlay(
            MapPinOutlineStroke(
                outline: MapPinOutline(
                    ownership: pinOwnership,
                    status: place.status == .been ? .been : .wannaGo
                ),
                lineWidth: MapPinVisualMetrics.outlineWidth
            )
        )
        .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: 6, x: 0, y: 2)
        .accessibilityLabel("\(place.name), \(place.status.title), \(place.visitCount) visits")
    }
}

private struct YourMapPrototypeSelectablePin: View {
    @Environment(\.astirBrandMode) private var brandMode
    let place: YourMapPrototypePlace
    let isSelected: Bool
    let pinOwnership: MapPinSaveOwnership
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                YourMapPrototypePin(place: place, pinOwnership: pinOwnership)

                if isSelected {
                    Text(place.name)
                        .font(AstirTypography.metadata)
                        .fontWeight(.bold)
                        .foregroundStyle(brandMode.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .padding(.vertical, WanderTheme.spacing1)
                        .background(brandMode.raisedBackground.opacity(0.96), in: Capsule())
                        .overlay(Capsule().stroke(brandMode.border))
                        .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
                        .offset(y: (MapPinVisualMetrics.discDiameter / 2) + 18)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: 164, height: MapPinVisualMetrics.discDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(place.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("yourMap.prototype.pin.\(place.id)")
        .zIndex(isSelected ? 10 : 0)
    }
}

private struct YourMapPrototypeSavedLensRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let savedLens: YourMapPrototypeSavedLens
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var restingOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private var contentOffset: CGFloat {
        YourMapPrototypeLensSwipePolicy.clampedOffset(restingOffset + dragTranslation)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AstirTheme.paper.color)
                    .frame(
                        width: YourMapPrototypeLensSwipePolicy.revealWidth,
                        height: 68
                    )
                    .background(WanderTheme.stateError.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(savedLens.title)")
            .accessibilityIdentifier("yourMap.prototype.deleteLens.\(savedLens.id.uuidString)")
            .allowsHitTesting(
                restingOffset <= -(YourMapPrototypeLensSwipePolicy.revealWidth / 2)
            )
            .zIndex(
                restingOffset <= -(YourMapPrototypeLensSwipePolicy.revealWidth / 2) ? 2 : 0
            )

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    restingOffset = 0
                }
                onSelect()
            } label: {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(brandMode.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(savedLens.title)
                            .font(AstirTypography.label)
                            .lineLimit(1)
                        Text(savedLens.detail)
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(brandMode.accent)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .background(brandMode.raisedBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourMap.prototype.savedLens.\(savedLens.id.uuidString)")
            .offset(x: contentOffset)
            .allowsHitTesting(
                restingOffset > -(YourMapPrototypeLensSwipePolicy.revealWidth / 2)
            )
            .zIndex(1)
            .highPriorityGesture(swipeGesture)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .clipped()
        .accessibilityAction(named: "Delete lens", onDelete)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTranslation) { value, translation, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                translation = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let predictedOffset = restingOffset + value.predictedEndTranslation.width
                withAnimation(.easeOut(duration: 0.18)) {
                    restingOffset = YourMapPrototypeLensSwipePolicy.settledOffset(
                        for: predictedOffset
                    )
                }
            }
    }
}

private struct YourMapPrototypeCircleButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(brandMode.primaryText)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .astirGlassSurface(
                    cornerRadius: WanderTheme.tapMinimum / 2,
                    castsShadow: true
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct YourMapPrototypeBarRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let item: YourMapPrototypeBreakdownItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.title)
                Spacer()
                Text("\(Int((item.fraction * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(AstirTypography.metadata)
            GeometryReader { geometry in
                Capsule()
                    .fill(brandMode.recessedBackground)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(categoryColor(item.title, brandMode: brandMode))
                            .frame(width: geometry.size.width * max(item.fraction, 0.03))
                    }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.count) places")
    }
}

private struct YourMapPrototypeSparkline: View {
    @Environment(\.astirBrandMode) private var brandMode

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
            .stroke(brandMode.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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

private func categoryColor(_ category: String, brandMode: AstirBrandMode) -> Color {
    switch category.lowercased() {
    case "coffee": brandMode.accent
    case "restaurants": brandMode.accent.opacity(0.82)
    case "bars": brandMode.primaryText.opacity(0.78)
    case "bakeries": brandMode.accent.opacity(0.62)
    case "outdoors": brandMode.secondaryText
    default: brandMode.secondaryText.opacity(0.72)
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
