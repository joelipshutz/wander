import SwiftUI
import UIKit

struct AccountContactDetailsView: View {
    @StateObject var model: AccountContactDetailsModel
    var isOnboarding = true
    let continueAction: () -> Void
    @StateObject private var citySearch = HomeCitySearchModel()
    @FocusState private var cityIsFocused: Bool
    @State private var showsCountries = false
    @FocusState private var phoneIsFocused: Bool

    var body: some View {
        Group {
            if isOnboarding {
                NavigationStack {
                    OnboardingStepScaffold(step: .location) {
                        content
                    } footer: {
                        actions
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                VStack(spacing: 0) {
                    content
                    actions.padding(WanderTheme.spacing4)
                }
                .astirScreen()
            }
        }
        .task { await model.load() }
        .onDisappear { citySearch.cancel() }
        .onChange(of: cityIsFocused) { _, focused in
            if focused && model.homeCity == nil { citySearch.update(model.cityText, force: true) }
            else if !focused { citySearch.cancel() }
        }
        .sheet(isPresented: $showsCountries) {
            ContactDetailsPicker(title: "Country code", options: OnboardingPhoneNumber.countries.map {
                .init(id: $0.id, title: $0.name, subtitle: $0.dialingCode)
            }, selectedID: model.phoneCountryCode) { id in
                model.selectPhoneCountry(id)
                showsCountries = false
            }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                form
            }
            .scrollDismissesKeyboard(.interactively)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if cityIsFocused { proxy.scrollTo("citySection", anchor: .top) }
                else { revealPhoneSection(using: proxy) }
            }
            .onChange(of: model.phoneIsValid) { _, _ in
                revealPhoneSection(using: proxy)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { phoneIsFocused = false; cityIsFocused = false; citySearch.cancel() }
            }
        }
        .sessionReplayMasked()
    }

    private func revealPhoneSection(using proxy: ScrollViewProxy) {
        guard phoneIsFocused else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("phoneSection", anchor: .bottom)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
            OnboardingHeadline(eyebrow: "A LITTLE ABOUT YOU", title: "Make yourself at home", message: "Check your home city and add your phone number.")
            citySection
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("Phone number · optional").font(AstirTypography.label)
                HStack(spacing: WanderTheme.spacing2) {
                    Button {
                        phoneIsFocused = false
                        cityIsFocused = false
                        citySearch.cancel()
                        showsCountries = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(OnboardingPhoneNumber.country(model.phoneCountryCode).dialingCode)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .frame(minHeight: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Country code, \(OnboardingPhoneNumber.country(model.phoneCountryCode).name), \(OnboardingPhoneNumber.country(model.phoneCountryCode).dialingCode)")
                    .accessibilityIdentifier("accountContactDetails.country")
                    Divider().frame(height: 28)
                    TextField(model.phoneCountryCode == "US" ? "10-digit phone number" : "Phone number", text: Binding(get: { model.phoneText }, set: { model.editPhone($0) }))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($phoneIsFocused)
                        .accessibilityIdentifier("accountContactDetails.phone")
                }
                .contactDetailsField()
                if !model.phoneIsValid {
                    Text(model.phoneCountryCode == "US" ? "Enter a valid 10-digit phone number." : "Check the number and country code.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(WanderTheme.stateError.color)
                        .accessibilityIdentifier("accountContactDetails.phoneError")
                }
                Text("Your phone number is private.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .id("phoneSection")
            .sessionReplayMasked()
            if let message = model.errorMessage {
                Text(message)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(WanderTheme.stateError.color)
                if !model.didLoad {
                    Button("Try again") { Task { await model.load() } }
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .disabled(model.isSaving)
    }

    private var actions: some View {
        VStack(spacing: WanderTheme.spacing1) {
            WanderPrimaryButton(title: model.isSaving ? "Saving…" : (isOnboarding ? "Continue" : "Save"), isDisabled: !model.canSave) {
                phoneIsFocused = false
                cityIsFocused = false
                citySearch.cancel()
                Task { if await model.save() { continueAction() } }
            }
            .accessibilityIdentifier("accountContactDetails.continue")
            if isOnboarding {
                Button("Not now") { continueAction() }
                    .font(AstirTypography.control)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("accountContactDetails.skip")
            }
        }
    }

    private var citySection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("Home city").font(AstirTypography.label)
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WanderTheme.textMuted.color)
                TextField("Search any city", text: Binding(get: { model.cityText }, set: {
                    model.editCity($0)
                    citySearch.update($0)
                }))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($cityIsFocused)
                .submitLabel(.done)
                .onSubmit { cityIsFocused = false; citySearch.cancel() }
                .accessibilityLabel("Home city")
                .accessibilityIdentifier("accountContactDetails.city")
                if !model.cityText.isEmpty {
                    Button {
                        model.editCity("")
                        citySearch.update("")
                        cityIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .frame(minWidth: 32, minHeight: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear city")
                    .accessibilityIdentifier("accountContactDetails.clearCity")
                }
            }
            .contactDetailsField()
            if cityIsFocused && model.homeCity == nil {
                citySuggestions
            } else if let city = model.homeCity {
                Text(city.subtitle)
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .accessibilityIdentifier("accountContactDetails.cityContext")
            }
            if !cityIsFocused {
                Text("Your home city, even when you’re away. You can change it later.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .id("citySection")
    }

    private var citySuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if citySearch.isSearching || citySearch.isResolving {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                    Text(citySearch.isResolving ? "Selecting city…" : "Finding cities…")
                }
                .font(AstirTypography.caption)
                .padding(WanderTheme.spacing3)
            }
            ForEach(citySearch.suggestions) { suggestion in
                Button {
                    citySearch.select(suggestion) { city in
                        model.selectCity(city)
                        cityIsFocused = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title).font(AstirTypography.body)
                            Text(suggestion.subtitle)
                                .font(AstirTypography.caption)
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left").font(.caption)
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.vertical, WanderTheme.spacing2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(citySearch.isResolving)
                .accessibilityIdentifier("accountContactDetails.cityResult.\(suggestion.title).\(suggestion.city?.countryCode ?? suggestion.subtitle)")
                if suggestion.id != citySearch.suggestions.last?.id {
                    Divider().padding(.horizontal, WanderTheme.spacing3)
                }
            }
            if let message = citySearch.message {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(message)
                    if message.hasPrefix("Couldn’t") {
                        Button("Try again") { citySearch.retry() }
                    }
                }
                .font(AstirTypography.caption)
                .padding(WanderTheme.spacing3)
                .accessibilityIdentifier("accountContactDetails.citySearchMessage")
            } else if model.cityText.isEmpty {
                Text("Start typing a city anywhere in the world.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .padding(WanderTheme.spacing3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AstirBrandMode.editorial.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(AstirBrandMode.editorial.border))
    }

}

private extension View {
    func contactDetailsField() -> some View {
        self.font(AstirTypography.body)
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
            .frame(minHeight: 58)
            .background(AstirBrandMode.editorial.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(AstirBrandMode.editorial.border))
    }
}

private struct ContactDetailsPicker: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }
    let title: String
    let options: [Option]
    let selectedID: String?
    let select: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(filtered) { option in
                Button { select(option.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(option.title)
                            if !option.subtitle.isEmpty {
                                Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedID == option.id { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)
                }
                .foregroundStyle(AstirBrandMode.editorial.primaryText)
                .accessibilityIdentifier("accountContactDetails.option.\(option.id)")
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sessionReplayMasked()
    }

    private var filtered: [Option] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? options : options.filter {
            $0.title.localizedStandardContains(search) || $0.subtitle.localizedStandardContains(search) || $0.id.localizedStandardContains(search)
        }
    }
}
