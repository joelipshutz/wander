import SwiftUI

struct AccountContactDetailsView: View {
    @StateObject var model: AccountContactDetailsModel
    var isOnboarding = true
    let continueAction: () -> Void
    @State private var showsMetros = false
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
        .sheet(isPresented: $showsMetros) {
            ContactDetailsPicker(title: "Home city", options: metroOptions, selectedID: model.metroID) { id in
                model.selectMetro(id)
                showsMetros = false
            }
        }
        .sheet(isPresented: $showsCountries) {
            ContactDetailsPicker(title: "Country code", options: OnboardingPhoneNumber.countries.map {
                .init(id: $0.id, title: $0.name, subtitle: $0.dialingCode)
            }, selectedID: model.phoneCountryCode) { id in
                model.selectPhoneCountry(id)
                showsCountries = false
            }
        }
        .accessibilityIdentifier("accountContactDetails.screen")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                OnboardingHeadline(eyebrow: "A LITTLE ABOUT YOU", title: "Make yourself at home", message: "Check your home city and add your phone number.")
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Home city").font(AstirTypography.label)
                    Button {
                        phoneIsFocused = false
                        showsMetros = true
                    } label: {
                        HStack {
                            Text(metroTitle)
                            Spacer()
                            if model.isLocating { ProgressView() }
                            Image(systemName: "chevron.down")
                        }
                        .contactDetailsField()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountContactDetails.metro")
                    Text("Choose the area you call home. You can change it later.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Phone number · optional").font(AstirTypography.label)
                    HStack(spacing: WanderTheme.spacing2) {
                        Button {
                            phoneIsFocused = false
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
            .disabled(model.isLoading || model.isSaving)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { phoneIsFocused = false }
            }
        }
        .sessionReplayMasked()
    }

    private var actions: some View {
        VStack(spacing: WanderTheme.spacing1) {
            WanderPrimaryButton(title: model.isSaving ? "Saving…" : (isOnboarding ? "Continue" : "Save"), isDisabled: !model.canSave) {
                phoneIsFocused = false
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

    private var metroTitle: String {
        if model.metroID == HomeMetro.otherID { return "Outside listed metros" }
        return HomeMetro.find(model.metroID)?.name ?? (model.isLocating ? "Finding your city…" : "Choose your city")
    }

    private var metroOptions: [ContactDetailsPicker.Option] {
        HomeMetro.all.map { .init(id: $0.id, title: $0.name, subtitle: $0.id == "los-angeles" ? "Los Angeles County" : (Locale.current.localizedString(forRegionCode: $0.country) ?? $0.country)) }
            + [.init(id: HomeMetro.otherID, title: "Outside listed metros", subtitle: "")]
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
