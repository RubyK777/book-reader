import SwiftUI
import SwiftData
import AVFoundation

/// Native language + a per-language voice picker for the languages the user
/// reads. Playback speed lives only on the Reader (0.5–2.0×).
struct SettingsView: View {
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative
    @AppStorage("reviewRemindersEnabled") private var remindersEnabled = false

    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query private var annotations: [Annotation]
    @State private var previewer = VoicePreviewer()
    @State private var exportFile: ShareableFile?
    @State private var exportError: String?

    /// Distinct source languages the user actually reads (books + saved items).
    private var spokenLanguages: [String] {
        var set = Set<String>()
        for book in books { if let code = book.languageCode { set.insert(code) } }
        for annotation in annotations { set.insert(annotation.languageCode) }
        return set.sorted { LanguageCatalog.name(for: $0) < LanguageCatalog.name(for: $1) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Native language", selection: $nativeLanguage) {
                        ForEach(LanguageCatalog.options, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                } footer: {
                    Text("The language you read fluently. Pages are translated into it; the source language of each book is detected automatically when you scan.")
                }

                if !spokenLanguages.isEmpty {
                    Section {
                        ForEach(spokenLanguages, id: \.self) { code in
                            VoicePickerRow(languageCode: code, previewer: previewer)
                        }
                    } header: {
                        Text("Voices")
                    } footer: {
                        Text("The voice used when reading each language aloud. Download higher-quality voices in Settings → Accessibility → Spoken Content → Voices.")
                    }
                }

                Section {
                    Toggle("Review reminders", isOn: $remindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("One gentle nudge when your next cards come due — never daily pings.")
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    .disabled(books.isEmpty && annotations.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Save a JSON backup of your books, saved words, sentences, notes, and review progress. Page photos are not included.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: remindersEnabled) { _, on in
                Task { @MainActor in
                    if on {
                        if await ReviewReminderService.requestAuthorization() {
                            let next = SRSEngine.nextDue(in: modelContext)
                            ReviewReminderService.reschedule(at: next?.date, sourceTitle: next?.sourceTitle)
                        } else {
                            remindersEnabled = false   // permission denied — revert the toggle
                        }
                    } else {
                        ReviewReminderService.cancel()
                    }
                }
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url)
            }
            .alert("Couldn't export", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private func exportData() {
        do {
            let url = try ExportService.writeExport(in: modelContext)
            exportFile = ShareableFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// One language's voice choice: a menu of installed voices (name + quality)
/// plus a preview button. "Default" defers to the system/best-match voice.
private struct VoicePickerRow: View {
    let languageCode: String
    let previewer: VoicePreviewer
    @State private var voiceID: String?

    private var voices: [AVSpeechSynthesisVoice] { VoiceStore.voices(for: languageCode) }

    var body: some View {
        HStack {
            Picker(LanguageCatalog.name(for: languageCode), selection: $voiceID) {
                Text("Default").tag(String?.none)
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.quality.label)").tag(String?.some(voice.identifier))
                }
            }
            Button {
                previewer.play(languageCode: languageCode, voiceID: voiceID)
            } label: {
                Image(systemName: "play.circle")
                    .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview voice")
        }
        .onAppear { voiceID = VoiceStore.voiceID(for: languageCode) }
        .onChange(of: voiceID) { VoiceStore.setVoiceID(voiceID, for: languageCode) }
    }
}

/// Small throwaway synthesizer for previewing a voice in Settings.
@Observable
final class VoicePreviewer {
    private let synthesizer = AVSpeechSynthesizer()

    func play(languageCode: String, voiceID: String?) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: VoiceStore.sampleText(for: languageCode))
        utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? VoiceStore.resolvedVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
