import SwiftUI
import SwiftData
import AVFoundation

/// Post-transcription, pre-persist review (parallel to `OCRReviewView`): play the
/// original recording, edit the transcript, confirm the spoken language and an
/// optional translation target, then save a `.conversation` source with sentence
/// timings. Nothing persists until "Save".
struct TranscriptionReviewView: View {
    let audioURL: URL
    let transcript: Transcript
    let onRetake: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    @State private var text: String
    @State private var language: String
    @State private var translateTo: String?
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var errorMessage: String?

    init(audioURL: URL, transcript: Transcript, languageCode: String, onRetake: @escaping () -> Void) {
        self.audioURL = audioURL
        self.transcript = transcript
        self.onRetake = onRetake
        _text = State(initialValue: transcript.text)
        _language = State(initialValue: languageCode)
    }

    var body: some View {
        Form {
            Section {
                Button { togglePlay() } label: {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text("Original recording").foregroundStyle(.primary)
                            Text((player?.duration ?? 0).clockString)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                Picker("Language", selection: $language) {
                    ForEach(LanguageCatalog.options, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            } header: {
                Text("Spoken language")
            } footer: {
                Text("Detected automatically — correct it here if it's wrong.")
            }

            Section("Transcript") {
                TextEditor(text: $text).frame(minHeight: 200)
            }

            Section {
                Picker("Translate to", selection: $translateTo) {
                    Text("Off").tag(String?.none)
                    let native = LanguageCatalog.options.first { $0.code.hasPrefix(nativeLanguage) }
                    if let native {
                        Text("\(native.name) (native)").tag(String?.some(native.code))
                    }
                    ForEach(LanguageCatalog.options.filter { $0.code != native?.code }, id: \.code) { lang in
                        Text(lang.name).tag(String?.some(lang.code))
                    }
                }
            } header: {
                Text("Translation")
            } footer: {
                Text("Shown under each line while you read — the recording is always what plays.")
            }
        }
        .navigationTitle("Review Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Retake") { player?.stop(); onRetake() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(text.isBlank)
            }
        }
        .onAppear { player = try? AVAudioPlayer(contentsOf: audioURL) }
        .onDisappear { player?.stop() }
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
            isPlaying = player?.isPlaying ?? false
        }
        .alert("Couldn't save recording",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        isPlaying = player.isPlaying
    }

    private func save() {
        player?.stop()
        guard let data = AudioFileStore.data(at: audioURL) else {
            errorMessage = "Couldn't read the recording file."
            return
        }
        do {
            let book = try AudioIngestor().ingest(
                audioData: data,
                duration: player?.duration ?? 0,
                text: text,
                title: String.titleSnippet(from: text),
                languageCode: language,
                translationLanguage: translateTo,
                segments: transcript.segments,
                context: modelContext)
            Haptics.success()
            router.recomputeDueCount(in: modelContext)
            AudioFileStore.discard(audioURL)
            dismiss()
            router.libraryPath.append(book)
        } catch {
            errorMessage = "No text to save. Edit the transcript or retake."
        }
    }
}

private extension TimeInterval {
    var clockString: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
