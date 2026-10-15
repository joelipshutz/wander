import SwiftUI
import MapKit
import StoreKit
import AuthenticationServices

enum ClipStyle {
    static let paper = Color(red: 242/255, green: 233/255, blue: 219/255)
    static let ink = Color(red: 20/255, green: 23/255, blue: 20/255)
    static let coral = Color(red: 240/255, green: 90/255, blue: 60/255)
    static func body(_ size: CGFloat = 17) -> Font { .custom("AvenirNext-Medium", size: size, relativeTo: .body) }
}

struct ClipView: View {
    @ObservedObject var store: ClipStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showInstall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Image("ClipBrand").resizable().scaledToFit().frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                        Text("ASTIR").font(ClipStyle.body(18)).tracking(3)
                        Spacer()
                        Button("Get Astir") { if store.prepareInstall() { showInstall = true } }
                            .font(ClipStyle.body(15)).frame(minHeight: 44)
                    }
                    if store.isLoading, store.preview == nil {
                        ProgressView("Opening your shared link…").frame(maxWidth: .infinity, minHeight: 220)
                    }
                    if let preview = store.preview {
                        if let image = preview.imageURL {
                            AsyncImage(url: image) { phase in
                                if let image = phase.image { image.resizable().scaledToFit() }
                                else if phase.error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
                            }.clipShape(RoundedRectangle(cornerRadius: 20))
                                .accessibilityLabel("Shared preview")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(preview.title).font(.system(.largeTitle, design: .serif, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            if let subtitle = preview.subtitle { Text(subtitle).foregroundStyle(.secondary) }
                        }
                        if preview.needsSignIn {
                            Button("Sign in to view") { store.perform(.viewProtected) }.buttonStyle(ClipPrimaryButton())
                        }
                        if store.route?.kind == .invite, !store.joined {
                            Text("Join this list to add places together.")
                            Button("Join list") { store.perform(.join) }.buttonStyle(ClipPrimaryButton())
                                .accessibilityIdentifier("clip.join")
                        }
                        ForEach(preview.places) { place in
                            placeView(place, showTitle: preview.places.count > 1 || store.route?.kind == .list || store.route?.kind == .profile)
                        }
                        if !preview.needsSignIn, preview.places.isEmpty, store.route?.kind == .list {
                            Text("No places in this list yet.").foregroundStyle(.secondary)
                        }
                    }
                    if let success = store.success {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .accessibilityIdentifier("clip.success")
                    }
                    if let error = store.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).accessibilityIdentifier("clip.error")
                            if store.preview == nil, store.route != nil {
                                Button("Try again") { store.reload() }.frame(minHeight: 44)
                            }
                        }
                    }
                    if store.route == nil, store.error == nil {
                        ContentUnavailableView("Open a shared Astir link", systemImage: "link",
                            description: Text("See a place, save it to your map, or join a friend's list."))
                    }
                    if store.isWorking { ProgressView("One moment…").frame(maxWidth: .infinity) }
                    if store.signedIn {
                        Button("Sign out", action: store.signOut).frame(minHeight: 44)
                            .disabled(store.isWorking)
                    }
                }.padding(24)
            }
            .background(colorScheme == .dark ? ClipStyle.ink : ClipStyle.paper)
            .foregroundStyle(colorScheme == .dark ? ClipStyle.paper : ClipStyle.ink)
            .font(ClipStyle.body())
            .toolbar(.hidden, for: .navigationBar)
            .tint(colorScheme == .dark ? ClipStyle.coral : Color(red: 178/255, green: 54/255, blue: 32/255))
            .sheet(isPresented: $store.showAuth, onDismiss: store.resumeAfterAuth) { ClipAuthView(store: store) }
            .sheet(isPresented: $store.showProfile) { profileForm }
            .appStoreOverlay(isPresented: $showInstall) { SKOverlay.AppClipConfiguration(position: .bottom) }
        }
    }

    private func placeView(_ place: ClipPlace, showTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if showTitle {
                Text(place.title).font(.system(.title2, design: .serif, weight: .semibold))
                    .accessibilityIdentifier("clip.place.title")
            }
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                Marker(place.title, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    .tint(ClipStyle.coral)
            }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("Map of \(place.title)")
            if let address = place.address { Text(address).foregroundStyle(.secondary) }
            Button(store.savedIDs.contains(place.id) ? "Saved to your map" : "Save to Wanna") { store.perform(.save(place)) }
                .buttonStyle(ClipPrimaryButton())
                .disabled(store.isWorking || store.savedIDs.contains(place.id))
                .accessibilityIdentifier("clip.save")
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
                item.name = place.title
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .frame(maxWidth: .infinity, minHeight: 48) }
            Text("Existing saves keep their notes and visibility.").font(ClipStyle.body(14)).foregroundStyle(.secondary)
        }
    }

    private var profileForm: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose the name and username people will see on Astir.")
                    TextField("Name", text: $store.name).textContentType(.name)
                    TextField("Username", text: $store.handle).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error = store.error { Text(error) }
                Button("Continue") { store.finishProfile() }
                    .disabled(store.isWorking || store.name.trimmingCharacters(in: .whitespaces).isEmpty || store.handle.count < 2)
                if store.isWorking { ProgressView() }
            }.navigationTitle("Your Astir profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: store.cancelAuth).disabled(store.isWorking) } }
                .interactiveDismissDisabled()
        }.font(ClipStyle.body())
    }
}

struct ClipPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ClipStyle.body()).foregroundStyle(ClipStyle.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ClipStyle.coral.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ClipAuthView: View {
    @ObservedObject var store: ClipStore
    @State private var mode: NativeAuthMode = .signIn
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var acceptsTerms = false
    private var canStart: Bool { !store.isWorking && (mode == .signIn || acceptsTerms) }

    var body: some View {
        NavigationStack {
            Form {
                if store.emailSent {
                    Section("Enter the code from your email") {
                        TextField("Verification code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button("Verify email") { store.verifyEmail(code) }.disabled(store.isWorking || code.isEmpty)
                    }
                } else {
                    Section {
                        Picker("Account", selection: $mode) {
                            Text("Sign in").tag(NativeAuthMode.signIn)
                            Text("Create account").tag(NativeAuthMode.signUp)
                        }.pickerStyle(.segmented).disabled(store.isWorking)
                        Text("Use your original sign-in method to keep your places and lists together.")
                        if mode == .signUp {
                            Toggle(isOn: $acceptsTerms) {
                                Text("I agree to the [Terms](https://astirmovement.com/terms) and [Privacy Policy](https://astirmovement.com/privacy).")
                            }
                        }
                        ClipAppleIDButton(isEnabled: canStart) { store.authenticate(.apple, mode: mode) }
                            .frame(height: 48)
                        Button("Continue with Google") { store.authenticate(.google, mode: mode) }
                            .frame(minHeight: 44).disabled(!canStart)
                    }
                    Section("Or use email") {
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if usePassword, mode == .signIn {
                            SecureField("Password", text: $password).textContentType(.password)
                            Button("Sign in") { store.signIn(email: email, password: password) }
                                .disabled(!canStart || email.isEmpty || password.isEmpty)
                        } else {
                            Button("Send code") { store.sendEmail(email, mode: mode) }.disabled(!canStart || email.isEmpty)
                        }
                        if mode == .signIn {
                            Toggle("Use password", isOn: $usePassword).disabled(store.isWorking)
                        }
                    }
                }
                if let error = store.error { Text(error).accessibilityIdentifier("clip.auth.error") }
                if store.isWorking { ProgressView("Signing in…") }
            }.navigationTitle(mode == .signIn ? "Sign in to Astir" : "Create your account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: store.cancelAuth).disabled(store.isWorking) } }
                .interactiveDismissDisabled()
        }.font(ClipStyle.body())
    }
}

private struct ClipAppleIDButton: UIViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.cornerRadius = 12
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTap), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.action = action
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func didTap() { action() }
    }
}
