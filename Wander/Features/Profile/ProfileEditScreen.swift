import PhotosUI
import SwiftUI

struct ProfileEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend

    @State private var name = ""
    @State private var handle = ""
    @State private var homeArea = ""
    @State private var bio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isPhotoSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WanderTheme.spacing6) {
                    VStack(spacing: WanderTheme.spacing3) {
                        ZStack {
                            WanderAvatar(
                                initials: store.currentUser.initials,
                                avatarURL: store.currentUser.avatarURL,
                                size: 124,
                                color: WanderTheme.avatarRyan.color
                            )
                            if isPhotoSaving {
                                Circle()
                                    .fill(WanderTheme.textInk.color.opacity(0.42))
                                    .frame(width: 124, height: 124)
                                ProgressView().tint(WanderTheme.textOnAction.color)
                            }
                        }

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("Edit profile photo")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(WanderTheme.terracotta.color)
                                .frame(minHeight: WanderTheme.tapMinimum)
                        }
                        .disabled(isPhotoSaving)
                    }
                    .padding(.top, WanderTheme.spacing4)

                    VStack(spacing: 0) {
                        ProfileEditFieldRow(title: "Name", prompt: "Your name", text: $name, capitalization: .words)
                        Divider().overlay(WanderTheme.borderHairline.color)
                        ProfileEditFieldRow(
                            title: "Username",
                            prompt: "username",
                            text: $handle,
                            capitalization: .never,
                            disablesAutocorrection: true
                        )
                        Divider().overlay(WanderTheme.borderHairline.color)
                        ProfileEditFieldRow(title: "Home city", prompt: "Add a home city", text: $homeArea, capitalization: .words)
                        Divider().overlay(WanderTheme.borderHairline.color)
                        ProfileEditFieldRow(title: "Bio", prompt: "Add a bio", text: $bio, capitalization: .sentences, axis: .vertical)
                    }
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
                    .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall).stroke(WanderTheme.borderHairline.color))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WanderTheme.stateError.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .navigationTitle("edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "saving..." : "save") {
                        Task { await save() }
                    }
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .disabled(isSaving || !isValid)
                }
            }
            .onAppear { loadIfNeeded() }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
        }
    }

    private var isValid: Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandle = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        return !normalizedName.isEmpty
            && normalizedHandle.range(of: "^[A-Za-z0-9_]{2,39}$", options: .regularExpression) != nil
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        name = store.currentUser.displayName
        handle = store.currentUser.handle
        homeArea = store.currentUser.homeArea ?? ""
        bio = store.currentUser.bio ?? ""
    }

    @MainActor
    private func save() async {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandle = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        var failures: [String] = []

        if normalizedName != store.currentUser.displayName || normalizedHandle != store.currentUser.handle {
            if auth.isSignedIn {
                do {
                    try await auth.updateIdentity(displayName: normalizedName, handle: normalizedHandle)
                    store.updateCurrentUserProfile(displayName: normalizedName, handle: normalizedHandle, bio: bio, homeArea: homeArea)
                } catch {
                    failures.append("Name or username could not be saved")
                }
            } else {
                store.updateCurrentUserProfile(displayName: normalizedName, handle: normalizedHandle, bio: bio, homeArea: homeArea)
            }
        }

        do {
            try await store.updateCurrentUserDetails(
                ProfileDetailsUpdate(bio: bio, homeArea: homeArea),
                backend: auth.isSignedIn ? backend : nil
            )
        } catch {
            failures.append("Home city or bio could not be synced")
        }

        if failures.isEmpty {
            dismiss()
        } else {
            errorMessage = failures.joined(separator: ". ") + ". Your other changes were kept."
        }
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        isPhotoSaving = true
        errorMessage = nil
        defer {
            isPhotoSaving = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw WanderImageProcessingError.invalidImageData
            }
            let jpegData = try await Task.detached(priority: .userInitiated) {
                try WanderImageProcessor.squareJPEGData(from: data)
            }.value
            let localURL = try ProfileAvatarStorage.live.writeAvatarData(jpegData)
            store.updateCurrentUserAvatarURL(localURL.absoluteString)

            if auth.isSignedIn, backend.canSyncProfileAvatars {
                let result = try await backend.uploadProfileAvatar(jpegData: jpegData, userID: store.currentUser.id)
                store.updateCurrentUserAvatarURL(result.avatarURL)
            }
        } catch {
            errorMessage = "Could not save that profile photo. Try another one."
        }
    }
}

private struct ProfileEditFieldRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let capitalization: TextInputAutocapitalization
    var disablesAutocorrection = false
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .firstTextBaseline, spacing: WanderTheme.spacing3) {
            Text(title)
                .font(.system(size: 15, weight: .black))
                .frame(width: 84, alignment: .leading)

            TextField(prompt, text: $text, axis: axis)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(disablesAutocorrection)
                .multilineTextAlignment(.trailing)
                .lineLimit(axis == .vertical ? 4 : 1)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing3)
        .frame(minHeight: 58)
    }
}
