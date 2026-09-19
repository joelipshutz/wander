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
    @State private var showsReplaceConfirmation = false
    @State private var inputMode: InputMode = .voice
    @FocusState private var textFocused: Bool

    private enum InputMode: String, CaseIterable {
        case voice = "Voice", text = "Text"
        var symbol: String { self == .voice ? "waveform" : "text.alignleft" }
    }

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
        .onChange(of: audio.attachment, initial: true) { _, value in composer.voice = value }
        .onChange(of: inputMode) { _, _ in
            textFocused = false
            audio.pauseForBackground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && (audio.isRecording || audio.isPlaying)) {
                audio.pauseForBackground()
            }
        }
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
                    Text("Drop us a line")
                        .font(AstirTypography.screenTitle).foregroundStyle(brandMode.primaryText)
                    Text("(feature request, bug, or tell us you love us)")
                        .font(AstirTypography.body).foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                inputTabs
                if inputMode == .voice { voicePanel }
                else { textPanel }
                if inputMode == .text, audio.attachment != nil {
                    Label("Your voice note will be included.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(brandMode.secondaryText)
                } else if inputMode == .voice, hasTextDraft {
                    Label("Your text and photos will be included.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(brandMode.secondaryText)
                }
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

    private var hasTextDraft: Bool {
        !composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composer.photos.isEmpty
    }

    private var inputTabs: some View {
        HStack(spacing: 4) {
            ForEach(InputMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { inputMode = mode }
                } label: {
                    VStack(spacing: 9) {
                        HStack(spacing: 8) {
                            Label(mode.rawValue, systemImage: mode.symbol)
                            if mode == .voice ? audio.attachment != nil : hasTextDraft {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption).accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(minHeight: 35)
                        Capsule().fill(inputMode == mode ? brandMode.accent : .clear).frame(height: 3)
                    }
                    .font(AstirTypography.body.weight(.semibold))
                    .foregroundStyle(inputMode == mode ? brandMode.primaryText : brandMode.secondaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedback.tab.\(mode.rawValue.lowercased())")
                .accessibilityAddTraits(inputMode == mode ? .isSelected : [])
                .disabled(composer.isSubmitting)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(brandMode.primaryText.opacity(0.1)).frame(height: 1).offset(y: 1) }
    }

    private var textPanel: some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
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
                        .disabled(!composer.canEdit)
                        .accessibilityLabel("Type your feedback")
                        .accessibilityIdentifier("feedback.text")
                }
                if isLoadingPhotos { ProgressView("Adding photos…").padding(.horizontal, 16) }
                if !composer.photos.isEmpty { photos.padding(.horizontal, 16) }
                photoButton.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .font(AstirTypography.body)
            .foregroundStyle(brandMode.primaryText)
            .background(brandMode.primaryText.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(brandMode.primaryText.opacity(0.14), lineWidth: 1))
            Text("\(composer.text.unicodeScalars.count) / \(FeedbackSubmission.maximumTextLength)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(composer.text.unicodeScalars.count > FeedbackSubmission.maximumTextLength ? Color.red : brandMode.secondaryText)
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
        .accessibilityIdentifier("feedback.photos")
    }

    private var voicePanel: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                if audio.isRecording || audio.attachment != nil {
                    Text(audio.isRecording ? "Recording your note…" : "Ready when you are")
                        .font(AstirTypography.body.weight(.semibold))
                }
                Text(audio.isRecording ? "Tap stop when you’re done" : audio.attachment == nil ? "Tap to record · up to \(FeedbackSubmission.maximumVoiceSeconds / 60) minutes" : "Give it a listen before you send")
                    .font(.footnote).foregroundStyle(brandMode.secondaryText)
            }.multilineTextAlignment(.center)

            Button {
                if audio.attachment != nil { audio.togglePlayback() }
                else if audio.isRecording {
                    audio.finish()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else { Task { await audio.start() } }
            } label: {
                ZStack {
                    Circle().stroke(brandMode.accent.opacity(0.2), lineWidth: 1).frame(width: 136, height: 136)
                    Circle().fill(brandMode.accent.opacity(0.09)).frame(width: 122, height: 122)
                    Circle().fill(brandMode.accent).frame(width: 104, height: 104)
                        .shadow(color: brandMode.accent.opacity(0.22), radius: 14, y: 6)
                    if audio.isRequestingPermission { ProgressView().tint(.white) }
                    else {
                        Image(systemName: audio.attachment != nil ? (audio.isPlaying ? "pause.fill" : "play.fill") : (audio.isRecording ? "stop.fill" : "mic.fill"))
                            .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(audio.isRequestingPermission || composer.isSubmitting || (!composer.canEdit && audio.attachment == nil))
            .accessibilityLabel(audio.attachment != nil ? (audio.isPlaying ? "Pause voice note" : "Play voice note") : (audio.isRecording ? "Stop recording" : "Record a voice note"))
            .accessibilityIdentifier(audio.attachment == nil ? "feedback.record" : "feedback.play")

            VStack(spacing: 10) {
                waveform
                HStack(spacing: 6) {
                    if audio.isRecording { Circle().fill(brandMode.accentText).frame(width: 6, height: 6).accessibilityHidden(true) }
                    Text(voiceTime).monospacedDigit()
                        .accessibilityIdentifier("feedback.voiceTime")
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(brandMode.secondaryText)
            }
            if audio.attachment != nil {
                HStack(spacing: 20) {
                    Button { audio.stopPlayback() } label: { Label("Stop", systemImage: "stop.fill").frame(minHeight: 44) }
                        .disabled(audio.playbackSeconds == 0 && !audio.isPlaying)
                        .accessibilityIdentifier("feedback.stopPlayback")
                    Button { audio.stopPlayback(); showsReplaceConfirmation = true } label: {
                        Label("Record again", systemImage: "arrow.counterclockwise").frame(minHeight: 44)
                    }
                    .disabled(!composer.canEdit)
                    .alert("Replace this voice note?", isPresented: $showsReplaceConfirmation) {
                        Button("Replace recording", role: .destructive) { audio.remove() }
                        Button("Keep recording", role: .cancel) {}
                    } message: { Text("Your current voice note will be removed so you can record a new one.") }
                }
                .font(.footnote.weight(.medium)).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 16)
        .foregroundStyle(brandMode.primaryText)
        .background(brandMode.primaryText.opacity(0.025), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(brandMode.primaryText.opacity(0.08), lineWidth: 1))
    }

    private var voiceTime: String {
        if let voice = audio.attachment {
            return "\(duration(Int(audio.playbackSeconds))) / \(duration(voice.duration ?? 0))"
        }
        return "\(duration(audio.elapsedSeconds)) / \(duration(FeedbackSubmission.maximumVoiceSeconds))"
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(audio.levels.indices, id: \.self) { index in
                let played = audio.playbackDuration > 0 && Double(index) / Double(audio.levels.count) < audio.playbackSeconds / audio.playbackDuration
                Capsule()
                    .fill(audio.isRecording || played ? brandMode.accentText : brandMode.primaryText.opacity(0.2))
                    .frame(maxWidth: 4)
                    .frame(height: 4 + audio.levels[index] * 30)
            }
        }
        .frame(height: 34)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: audio.levels)
        .accessibilityHidden(true)
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
