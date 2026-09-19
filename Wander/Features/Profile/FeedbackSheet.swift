import ImageIO
import PhotosUI
import SwiftUI

struct FeedbackSheet: View {
    let repository: (any FeedbackRepository)?
    let analytics: any AnalyticsClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var composer = FeedbackComposer()
    @StateObject private var audio = FeedbackAudioRecorder()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var showsDiscardConfirmation = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if composer.isSubmitted { success }
                else { form }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(brandMode.background.ignoresSafeArea())
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        textFocused = false
                        if audio.isRecording { audio.finish() }
                        if (composer.hasContent || audio.attachment != nil || isLoadingPhotos) && !composer.isSubmitted { showsDiscardConfirmation = true }
                        else { dismiss() }
                    } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close feedback")
                    .disabled(composer.isSubmitting)
                }
            }
        }
        .tint(brandMode.primaryText)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(composer.hasContent || audio.isRecording || composer.isSubmitting || isLoadingPhotos)
        .alert("Discard your feedback?", isPresented: $showsDiscardConfirmation) {
            Button("Discard feedback", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Your unsent text and attachments will be removed from this device.") }
        .onChange(of: audio.attachment) { _, value in composer.voice = value }
        .onChange(of: scenePhase) { _, phase in if phase != .active { audio.pauseForBackground() } }
        .onChange(of: composer.isSubmitted) { _, submitted in
            if submitted { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        .onDisappear { audio.close() }
        .task(id: selectedPhotos) { await loadPhotos() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 30)).foregroundStyle(brandMode.accentText)
                        .accessibilityHidden(true)
                    Text("Tell us your feedback")
                        .font(AstirTypography.screenTitle).foregroundStyle(brandMode.primaryText)
                    Text("(feature request, bug, or tell us you love us)")
                        .font(AstirTypography.body).foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .trailing, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if composer.text.isEmpty {
                            Text("Type your feedback…")
                                .foregroundStyle(brandMode.secondaryText)
                                .padding(.horizontal, 16).padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $composer.text)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: 180)
                            .focused($textFocused)
                            .disabled(!composer.canEdit || composer.isSubmitting)
                            .accessibilityLabel("Type your feedback")
                            .accessibilityIdentifier("feedback.text")
                    }
                    .font(AstirTypography.body)
                    .foregroundStyle(brandMode.primaryText)
                    .background(brandMode.primaryText.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(brandMode.primaryText.opacity(0.14), lineWidth: 1))
                    Text("\(composer.text.unicodeScalars.count) / \(FeedbackSubmission.maximumTextLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(composer.text.unicodeScalars.count > FeedbackSubmission.maximumTextLength ? Color.red : brandMode.secondaryText)
                }
                attachmentControls
                if isLoadingPhotos { ProgressView("Adding photos…").font(AstirTypography.body) }
                if !composer.photos.isEmpty { photos }
                if let voice = audio.attachment { voiceNote(voice) }
                if let error = composer.errorMessage ?? audio.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(AstirTypography.body).foregroundStyle(brandMode.primaryText)
                            .accessibilityIdentifier("feedback.error")
                        if audio.permissionDenied {
                            Button("Open Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }.frame(minHeight: 44)
                        }
                    }
                }
                Text("Only the Astir team sees your feedback and attachments.")
                    .font(.footnote).foregroundStyle(brandMode.secondaryText)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                textFocused = false
                audio.stopPlayback()
                Task { await composer.submit(repository: repository, analytics: analytics) }
            } label: {
                HStack(spacing: 10) {
                    if composer.isSubmitting { ProgressView().tint(.white) }
                    Text(composer.isSubmitting ? "Submitting…" : composer.pendingSubmission == nil ? "Submit" : "Try again")
                        .font(AstirTypography.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity).frame(minHeight: 54)
                .foregroundStyle(.white)
                .background(brandMode.accent, in: RoundedRectangle(cornerRadius: 18))
                .opacity(submitEnabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!submitEnabled)
            .accessibilityIdentifier("feedback.submit")
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(brandMode.background)
        }
    }

    private var submitEnabled: Bool {
        composer.canSubmit && !audio.isRecording && !audio.isRequestingPermission && !isLoadingPhotos
    }

    private var attachmentControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { photoButton; recordingButton }
            VStack(alignment: .leading, spacing: 12) { photoButton; recordingButton }
        }
    }

    private var photoButton: some View {
        let background = brandMode.primaryText.opacity(0.06)
        return PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(1, FeedbackSubmission.maximumPhotos - composer.photos.count), matching: .images) {
            Label("Add photos", systemImage: "photo.on.rectangle")
                .font(AstirTypography.body).padding(.horizontal, 16).frame(minHeight: 48)
                .background(background, in: Capsule())
        }
        .disabled(!composer.canEdit || isLoadingPhotos || audio.isRecording || composer.photos.count >= FeedbackSubmission.maximumPhotos)
    }

    private var recordingButton: some View {
        Button {
            textFocused = false
            if audio.isRecording { audio.finish() }
            else { Task { await audio.start() } }
        } label: {
            Label(audio.isRecording ? "Stop · \(duration(audio.elapsedSeconds))" : "Voice note", systemImage: audio.isRecording ? "stop.circle.fill" : "mic")
                .font(AstirTypography.body).padding(.horizontal, 16).frame(minHeight: 48)
                .foregroundStyle(audio.isRecording ? brandMode.accentText : brandMode.primaryText)
                .background(brandMode.primaryText.opacity(0.06), in: Capsule())
        }
        .disabled(!composer.canEdit || audio.isRequestingPermission || audio.attachment != nil)
        .accessibilityLabel(audio.isRecording ? "Stop recording" : "Record a voice note, up to two minutes")
    }

    private var photos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(composer.photos) { photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 92, height: 110).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) {
                                Button { composer.photos.removeAll { $0.id == photo.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
                                        .frame(width: 44, height: 44)
                                }.disabled(!composer.canEdit).accessibilityLabel("Remove photo")
                            }
                    }
                }
            }
        }
    }

    private func voiceNote(_ voice: FeedbackAttachment) -> some View {
        HStack(spacing: 12) {
            Button { audio.togglePlayback() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(audio.isPlaying ? "Pause voice note" : "Play voice note")
            Label("Voice note · \(duration(voice.duration ?? 0))", systemImage: "waveform")
                .font(AstirTypography.body)
            Spacer(minLength: 0)
            Button { audio.remove() } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }.disabled(!composer.canEdit).accessibilityLabel("Remove voice note")
        }
        .padding(8).background(brandMode.primaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var success: some View {
        ZStack {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(brandMode.accentText)
                Text("You made Astir better.").font(AstirTypography.screenTitle).multilineTextAlignment(.center)
                Text("Thanks for the love. Your feedback is with our team.")
                    .font(AstirTypography.body).foregroundStyle(brandMode.secondaryText).multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .font(AstirTypography.body.weight(.semibold)).frame(minWidth: 140, minHeight: 52)
                    .background(brandMode.primaryText.opacity(0.08), in: Capsule()).padding(.top, 12)
            }
            .padding(32).accessibilityIdentifier("feedback.success")
            if !reduceMotion { SaveStreakConfettiPopView().allowsHitTesting(false).accessibilityHidden(true) }
        }.foregroundStyle(brandMode.primaryText)
    }

    private func duration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private func loadPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false; selectedPhotos = [] }
        for item in selectedPhotos {
            guard composer.photos.count < FeedbackSubmission.maximumPhotos else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw WanderImageProcessingError.invalidImageData }
                let jpeg = try await Task.detached(priority: .userInitiated) { try FeedbackPhotoProcessor.jpeg(data) }.value
                try Task.checkCancellation()
                composer.photos.append(FeedbackAttachment(kind: .photo, data: jpeg))
            } catch is CancellationError { return }
            catch { composer.errorMessage = "A photo couldn’t be added. Please choose another image." }
        }
    }
}

enum FeedbackPhotoProcessor {
    // Downsample before decoding, preserve the whole screenshot, and strip source metadata.
    nonisolated static func jpeg(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_000,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw WanderImageProcessingError.invalidImageData }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, "public.jpeg" as CFString, 1, nil) else {
            throw WanderImageProcessingError.jpegEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), result.length <= FeedbackSubmission.maximumAttachmentBytes else {
            throw WanderImageProcessingError.jpegEncodingFailed
        }
        return result as Data
    }
}
