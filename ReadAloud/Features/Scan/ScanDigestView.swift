import SwiftUI
import Translation

/// Quick-Scan digest (UX review §engagement): after a scan, glance at
/// each detected line with its inline translation and hear it read aloud — a
/// utility answer, not a study object. Nothing is saved. Rides the batch
/// `.translationTask` pattern (same as the Reader's page translate). Offline
/// after the first translate; TTS always speaks the source.
struct ScanDigestView: View {
    let lines: [String]
    let languageCode: String

    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative
    @Environment(\.dismiss) private var dismiss

    @State private var player = SpeechPlayer()
    @State private var translations: [Int: String] = [:]
    @State private var config: TranslationSession.Configuration?
    @State private var failed = false

    /// Nothing to translate when the page is already in the reader's language.
    private var canTranslate: Bool {
        !languageCode.hasSameBaseLanguage(as: nativeLanguage)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    row(index, line)
                }
            }
            .navigationTitle("Quick translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .translationTask(config) { session in
                await translateAll(using: session)
            }
            .onAppear(perform: start)
            .onDisappear { player.stop() }
        }
    }

    private func row(_ index: Int, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text(line)
                    .font(.body)
                    .fontDesign(Theme.sentenceDesign)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    player.load(sentences: [line], languageCode: languageCode)
                    player.speakOnce(line)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(Theme.accent)
                        .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hear")
            }

            translationLine(index)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    @ViewBuilder
    private func translationLine(_ index: Int) -> some View {
        if let translated = translations[index] {
            Text(translated)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Translation: \(translated)")
        } else if !canTranslate {
            EmptyView()   // already in the reader's language
        } else if failed {
            Text("Translation isn't offered for this language pair yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Text("Translating…")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func start() {
        guard canTranslate, config == nil else { return }
        config = TranslationSession.Configuration(
            source: Locale.Language(identifier: languageCode),
            target: Locale.Language(identifier: nativeLanguage))
    }

    @MainActor
    private func translateAll(using session: TranslationSession) async {
        // Correlate by clientIdentifier — batch responses aren't order-guaranteed.
        let requests = lines.enumerated().map { index, line in
            TranslationSession.Request(sourceText: line, clientIdentifier: "\(index)")
        }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                if let id = response.clientIdentifier, let index = Int(id) {
                    translations[index] = response.targetText
                }
            }
            failed = false
        } catch {
            failed = true
        }
    }
}
