import SwiftUI
import UniformTypeIdentifiers

/// Capture-first audio flow (parallel to `ScanFlowView`): record live audio or
/// import a local clip/video, transcribe it on-device, then review before saving.
/// Nothing persists until the review's "Use" (matches the OCR contract, #22).
struct AudioCaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var recorder = AudioCaptureRecorder()
    @State private var step: Step = .capture
    @State private var languageHint = "fr-FR"
    /// Languages whose offline model is ready on THIS device (nil until checked).
    @State private var readyLanguageCodes: Set<String>?
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var workingLabel = "Transcribing…"
    @State private var errorMessage: String?

    private let transcriber: Transcribing = OnDeviceTranscriber()

    private enum Step {
        case capture
        case review(url: URL, transcript: Transcript, language: String)
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .capture:
                captureView
            case let .review(url, transcript, language):
                TranscriptionReviewView(audioURL: url, transcript: transcript, languageCode: language) {
                    step = .capture
                }
            }
        }
    }

    // MARK: Capture step

    private var captureView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if isWorking {
                ProgressView(workingLabel)
            } else {
                Spacer()

                Text(recorder.elapsed.clockString)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(recorder.state == .recording ? Theme.coral : .primary)

                LevelMeter(level: recorder.level, active: recorder.state == .recording)
                    .frame(height: 40)
                    .padding(.horizontal, DesignSystem.Spacing.xl)

                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                if recorder.state != .recording {
                    Picker("Spoken language", selection: $languageHint) {
                        ForEach(LanguageCatalog.options.filter { isSelectable($0.code) }, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)

                    if let readyLanguageCodes, !readyLanguageCodes.isEmpty {
                        Text("Showing languages whose offline voice model is on your phone. Add more in Settings → General → Keyboard.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                }

                Spacer()

                recordButton

                if recorder.state == .stopped {
                    Button { useRecording() } label: {
                        Label("Use recording", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                if recorder.state == .idle {
                    Button { isImporting = true } label: {
                        Label("Import audio or video", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                }
            }
        }
        .padding()
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { recorder.cancel(); dismiss() }
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.audio, .movie, .mpeg4Movie, .mpeg4Audio],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .task { computeReadyLanguages() }
    }

    /// True when a language should appear in the picker: everything until we've
    /// checked, then only the ones whose offline model is on the device.
    private func isSelectable(_ code: String) -> Bool {
        guard let readyLanguageCodes, !readyLanguageCodes.isEmpty else { return true }
        return readyLanguageCodes.contains(code)
    }

    /// Which catalog languages have an on-device model right now, and keep the
    /// selection valid if the current pick isn't ready.
    private func computeReadyLanguages() {
        let transcriber = OnDeviceTranscriber()
        let ready = Set(LanguageCatalog.options.map(\.code).filter { transcriber.isAvailable(for: $0) })
        readyLanguageCodes = ready
        if !ready.isEmpty, !ready.contains(languageHint) {
            languageHint = LanguageCatalog.options.first { ready.contains($0.code) }?.code ?? languageHint
        }
    }

    private var prompt: String {
        switch recorder.state {
        case .idle: "Record what you hear — a conversation, a class, or a video playing nearby — or import a clip."
        case .recording: "Recording… tap to stop."
        case .stopped: "Tap to re-record, or use this take."
        }
    }

    private var recordButton: some View {
        Button {
            switch recorder.state {
            case .idle, .stopped: startRecording()
            case .recording: recorder.stop()
            }
        } label: {
            ZStack {
                Circle().strokeBorder(Theme.coral.opacity(0.4), lineWidth: 4).frame(width: 84, height: 84)
                if recorder.state == .recording {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.coral).frame(width: 32, height: 32)
                } else {
                    Circle().fill(Theme.coral).frame(width: 68, height: 68)
                }
            }
        }
        .accessibilityLabel(recorder.state == .recording ? "Stop recording" : "Start recording")
    }

    // MARK: Actions

    private func startRecording() {
        Task { @MainActor in
            let granted: Bool
            switch MicAuthorizer.status() {
            case .granted: granted = true
            case .undetermined: granted = await MicAuthorizer.request()
            default: granted = false
            }
            guard granted else {
                errorMessage = "Microphone access is off — enable it in Settings, or import a clip."
                return
            }
            errorMessage = nil
            recorder.start()
        }
    }

    private func useRecording() {
        guard let url = recorder.fileURL else { return }
        transcribe(url)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let picked = urls.first else { return }
        errorMessage = nil
        isWorking = true
        workingLabel = "Preparing clip…"
        Task { @MainActor in
            guard let local = await AudioFileStore.importMedia(from: picked, id: UUID()) else {
                isWorking = false
                errorMessage = "Couldn't read that file. Try another clip."
                return
            }
            transcribe(local)
        }
    }

    private func transcribe(_ url: URL) {
        errorMessage = nil
        isWorking = true
        workingLabel = "Transcribing…"
        Task { @MainActor in
            do {
                let transcript = try await transcriber.transcribe(fileURL: url, localeIdentifier: languageHint)
                isWorking = false
                step = .review(url: url, transcript: transcript, language: languageHint)
            } catch {
                isWorking = false
                errorMessage = message(for: error)
            }
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case TranscriptionError.notAuthorized:
            "Speech recognition is off — enable it in Settings to transcribe."
        case TranscriptionError.unavailableForLanguage:
            "This language's offline voice model isn't on your phone yet. Add it under Settings → General → Keyboard (turn on Dictation and add the language), then try again — nothing is ever sent online."
        case TranscriptionError.noSpeechFound:
            "No speech found — record somewhere quieter, or closer to the speaker."
        default:
            "Couldn't transcribe this clip. Try again."
        }
    }
}

/// A simple horizontal level meter for the record screen.
private struct LevelMeter: View {
    let level: Float
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardStroke.opacity(0.4))
                Capsule()
                    .fill(active ? Theme.coral : Color.secondary)
                    .frame(width: geo.size.width * CGFloat(active ? level : 0))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
    }
}

private extension TimeInterval {
    /// "0:07" / "1:23" clock string.
    var clockString: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
