import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend

    @State private var name = ""
    @State private var handle = ""
    @State private var homeArea = ""
    @State private var bio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsPhotoMenu = false
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
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
                                    .fill(AstirTheme.ink.color.opacity(0.42))
                                    .frame(width: 124, height: 124)
                                ProgressView().tint(AstirTheme.paper.color)
                            }
                        }

                        Button {
                            showsPhotoMenu = true
                        } label: {
                            Text("Edit profile photo")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.accent)
                                .frame(minHeight: WanderTheme.tapMinimum)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPhotoSaving)
                    }
                    .padding(.top, WanderTheme.spacing4)

                    VStack(spacing: 0) {
                        ProfileEditFieldRow(title: "Name", prompt: "Your name", text: $name, capitalization: .words)
                        Divider().overlay(brandMode.border)
                        ProfileEditFieldRow(
                            title: "Username",
                            prompt: "username",
                            text: $handle,
                            capitalization: .never,
                            disablesAutocorrection: true
                        )
                        Divider().overlay(brandMode.border)
                        ProfileEditFieldRow(title: "Home city", prompt: "Add a home city", text: $homeArea, capitalization: .words)
                        Divider().overlay(brandMode.border)
                        ProfileEditFieldRow(title: "Bio", prompt: "Add a bio", text: $bio, capitalization: .sentences, axis: .vertical)
                    }
                    .background(brandMode.raisedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                            .stroke(brandMode.border)
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(WanderTheme.stateError.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .astirScreen()
            .navigationTitle("edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "saving..." : "save") {
                        Task { await save() }
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accent)
                    .disabled(isSaving || !isValid)
                }
            }
            .onAppear { loadIfNeeded() }
            .sheet(isPresented: $showsCamera) {
                ProfileCameraPicker { image in
                    Task { await savePhoto(image) }
                }
            }
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .confirmationDialog("Profile photo", isPresented: $showsPhotoMenu, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showsCamera = true }
                }
                Button("Choose from Library") { showsPhotoLibrary = true }
                if hasProfilePhoto {
                    Button("Delete Photo", role: .destructive) {
                        Task { await deletePhoto() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var hasProfilePhoto: Bool {
        guard let avatarURL = store.currentUser.avatarURL else { return false }
        return !avatarURL.isEmpty
    }

    private var isValid: Bool {
        ProfileIdentityDraft(displayName: name, handle: handle).isValid
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

        let identity = ProfileIdentityDraft(displayName: name, handle: handle)

        do {
            try await store.updateCurrentUserDetails(
                ProfileDetailsUpdate(
                    displayName: identity.normalizedDisplayName,
                    handle: identity.normalizedHandle,
                    bio: bio,
                    homeArea: homeArea
                ),
                backend: auth.isSignedIn ? backend : nil
            )
        } catch {
            errorMessage = ProfileIdentitySubmissionError.map(error).message
            return
        }

        dismiss()
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
            try await savePhoto(jpegData)
        } catch {
            errorMessage = "Could not save that profile photo. Try another one."
        }
    }

    @MainActor
    private func savePhoto(_ image: UIImage) async {
        isPhotoSaving = true
        errorMessage = nil
        defer { isPhotoSaving = false }

        do {
            let source = SendableProfilePhotoImage(image)
            let jpegData = try await Task.detached(priority: .userInitiated) {
                try WanderImageProcessor.squareJPEGData(from: source.value)
            }.value
            try await savePhoto(jpegData)
        } catch {
            errorMessage = "Could not save that profile photo. Try another one."
        }
    }

    @MainActor
    private func savePhoto(_ jpegData: Data) async throws {
        let localURL = try ProfileAvatarStorage.live.writeAvatarData(jpegData)
        store.updateCurrentUserAvatarURL(localURL.absoluteString)

        if auth.isSignedIn, backend.canSyncProfileAvatars {
            let result = try await backend.uploadProfileAvatar(jpegData: jpegData, userID: store.currentUser.id)
            store.updateCurrentUserAvatarURL(result.avatarURL)
        }
    }

    @MainActor
    private func deletePhoto() async {
        isPhotoSaving = true
        errorMessage = nil
        defer { isPhotoSaving = false }

        do {
            if auth.isSignedIn, backend.canSyncProfileAvatars {
                try await backend.deleteProfileAvatar(userID: store.currentUser.id)
            }
            try ProfileAvatarStorage.live.deleteAvatar()
            store.updateCurrentUserAvatarURL(nil)
        } catch {
            errorMessage = "Could not delete that profile photo. Try again."
        }
    }
}

private struct SendableProfilePhotoImage: @unchecked Sendable {
    let value: UIImage

    init(_ value: UIImage) {
        self.value = value
    }
}

private struct ProfileCameraPicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss.callAsFunction)
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: @MainActor (UIImage) -> Void
        private let dismiss: () -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

struct ProfilePhotoFullScreenViewer: View {
    @Environment(\.dismiss) private var dismiss
    let avatarURL: String?
    let displayName: String
    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            ZoomablePhoto {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel("\(displayName)'s profile photo")
                    } else if loadFailed {
                        VStack(spacing: WanderTheme.spacing2) {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Could not load profile photo")
                                .font(AstirTypography.control)
                        }
                        .foregroundStyle(.white.opacity(0.82))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            WanderGlassActionButton(
                systemImage: "xmark",
                accessibilityLabel: "Close profile photo",
                tone: .darkOverlay,
                action: dismiss.callAsFunction
            )
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
        }
        .preferredColorScheme(.dark)
        .task(id: avatarURL) {
            image = nil
            loadFailed = false
            guard let request = WanderAvatarImageRequest(
                avatarURL: avatarURL,
                targetPixelSize: 2_048
            ) else {
                loadFailed = true
                return
            }
            let loadedImage = await WanderAvatarImagePipeline.shared.image(for: request)?.image
            guard !Task.isCancelled else { return }
            image = loadedImage
            loadFailed = loadedImage == nil
        }
    }
}

private struct ProfileEditFieldRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let prompt: String
    @Binding var text: String
    let capitalization: TextInputAutocapitalization
    var disablesAutocorrection = false
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .firstTextBaseline, spacing: WanderTheme.spacing3) {
            Text(title)
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.primaryText)
                .frame(width: 84, alignment: .leading)

            TextField(prompt, text: $text, axis: axis)
                .font(AstirTypography.body)
                .foregroundStyle(brandMode.primaryText)
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
