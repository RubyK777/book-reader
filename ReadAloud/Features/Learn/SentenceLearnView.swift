import SwiftUI
import SwiftData

/// The pivot's heart (PIVOT_PLAN §7 Phase 2, basic version): study one
/// sentence deeply. Drill-down from a Reader sentence card. Four sections:
/// original + listen controls, translation, Understand (on-device generation
/// with fallback, D1/D2/D7), and one-tap save-as-annotation (D3).
struct SentenceLearnView: View {
    let sentence: Sentence
    let languageCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    // Short replay player — never owns the lock screen (AUDIO_DESIGN §7).
    @State private var player = SpeechPlayer()
    @State private var isGenerating = false
    @State private var generationFailed = false
    @State private var selectedWords: Set<String> = []
    @State private var selectedIntent: SaveIntent?
    @State private var lookupTerm: DictionaryTerm?

    private let provider = LearningAssetsProviderFactory.makeDefault()
    private let tokenizer = WordTokenizer()

    private var words: [String] {
        tokenizer.words(in: sentence.text, languageCode: languageCode)
    }

    private var orderedSelection: [String] {
        words.filter { selectedWords.contains($0) }
    }

    private var assets: LearningAssets? { sentence.learningAssets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    originalSection
                    translationSection
                    understandSection
                    saveSection
                    if !sentence.annotations.isEmpty { savedItemsSection }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                player.load(sentences: [sentence.text], languageCode: languageCode)
            }
            .onDisappear { player.stop() }
            .task { await generateIfNeeded() }
            .sheet(item: $lookupTerm) { lookup in
                DictionaryView(term: lookup.term).ignoresSafeArea()
            }
        }
    }

    // MARK: Original + Listen

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(sentence.text)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    player.play(at: 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    player.speakOnce(sentence.text, slow: true)
                } label: {
                    Label("Slow", systemImage: "tortoise.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(LanguageCatalog.name(for: languageCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: Translation

    private var translationSection: some View {
        sectionCard("Translation", systemImage: "translate") {
            if let translated = sentence.translatedText {
                Text(translated)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No translation yet — turn on translation in the Reader and it appears here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Understand (D1/D2/D7)

    @ViewBuilder
    private var understandSection: some View {
        sectionCard("Understand", systemImage: "lightbulb") {
            if let assets {
                understandContent(assets)
            } else if isGenerating {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                    Text("Generating breakdown…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if generationFailed {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Couldn't generate a breakdown for this sentence.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await generateIfNeeded(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                fallbackContent
            }
        }
    }

    @ViewBuilder
    private func understandContent(_ assets: LearningAssets) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if !assets.chunks.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(assets.chunks, id: \.self) { chunk in
                        Button {
                            player.speakOnce(chunk.text)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "speaker.wave.1")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.accent)
                                Text(chunk.text)
                                    .fontWeight(.medium)
                                Text(chunk.gloss)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chunk.text), meaning: \(chunk.gloss). Tap to hear.")
                    }
                }
            }

            if !assets.keyVocab.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Key vocabulary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(assets.keyVocab, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                            Text(item.term).fontWeight(.medium)
                            Text(item.meaning).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            if let grammar = assets.grammarPoint {
                Divider()
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Grammar point")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(grammar).font(.callout)
                }
            }

            if assets.isGenerated {
                // D7 provenance: generated content is always visibly marked.
                Label("AI-generated — check anything that looks off", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Fallback learn view (D2): no Apple Intelligence tier on this device or
    /// language. Dictionary + user-authored notes still work.
    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(provider == nil
                 ? "Phrase breakdowns need Apple Intelligence (iOS 26)."
                 : provider?.unavailabilityReason ?? "Breakdown generation isn't available right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Tap a word below and use Look Up, or add your own note when saving.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Save (D3: one tap, type inferred, intent optional)

    private var saveSection: some View {
        sectionCard("Save", systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Tap words to select — one is a word, several make a phrase. Tap the speaker to hear the whole sentence again anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: DesignSystem.Spacing.sm) {
                    ForEach(words, id: \.self) { word in
                        wordChip(word)
                    }
                }

                if orderedSelection.count == 1 {
                    Button {
                        lookupTerm = DictionaryTerm(term: orderedSelection[0])
                    } label: {
                        Label("Look Up “\(orderedSelection[0])”", systemImage: "book")
                    }
                    .buttonStyle(.bordered)
                }

                // Optional intent (D3) — skippable, editable later in Notes.
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(SaveIntent.allCases, id: \.self) { intent in
                        intentChip(intent)
                    }
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        saveSelection()
                    } label: {
                        Text(selectionSaveLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedWords.isEmpty)

                    Button("Save Sentence") { saveWholeSentence() }
                        .buttonStyle(.bordered)
                        .disabled(hasAnnotation(text: sentence.text))
                }
            }
        }
    }

    private var selectionSaveLabel: String {
        switch orderedSelection.count {
        case 0: "Save Selection"
        case 1: "Save Word"
        default: "Save Phrase"
        }
    }

    private func wordChip(_ word: String) -> some View {
        let isSelected = selectedWords.contains(word)
        return Button {
            if isSelected { selectedWords.remove(word) } else { selectedWords.insert(word) }
            player.speakOnce(word)
            Haptics.select()
        } label: {
            Text(word)
                .font(.callout)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    Capsule().fill(isSelected ? DesignSystem.accent : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func intentChip(_ intent: SaveIntent) -> some View {
        let isSelected = selectedIntent == intent
        return Button {
            selectedIntent = isSelected ? nil : intent
            Haptics.select()
        } label: {
            Text(intent.displayName)
                .font(.caption)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(
                    Capsule().strokeBorder(isSelected ? DesignSystem.accent : Color(.separator))
                )
                .foregroundStyle(isSelected ? DesignSystem.accent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Intent: \(intent.displayName)\(isSelected ? ", selected" : "")")
    }

    // MARK: Saved items

    private var savedItemsSection: some View {
        sectionCard("Saved from this sentence", systemImage: "bookmark") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(sentence.annotations.sorted { $0.savedAt < $1.savedAt }) { annotation in
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(annotation.type.rawValue)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(DesignSystem.accent)
                        Text(annotation.text)
                            .font(.callout)
                        if let intent = annotation.intent {
                            Text(intent.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func generateIfNeeded(force: Bool = false) async {
        guard assets == nil || force,
              let provider, provider.isAvailable,
              !isGenerating else { return }
        isGenerating = true
        generationFailed = false
        do {
            let generated = try await provider.generateAssets(
                for: sentence.text,
                sourceLanguage: languageCode,
                explanationLanguage: nativeLanguage)
            sentence.learningAssets = generated
            try? modelContext.save()
        } catch {
            generationFailed = true
        }
        isGenerating = false
    }

    private func saveSelection() {
        let selection = orderedSelection
        guard !selection.isEmpty else { return }
        let text = selection.joined(separator: " ")
        let type: AnnotationType = selection.count == 1 ? .word : .phrase
        save(type: type, text: text)
        selectedWords = []
    }

    private func saveWholeSentence() {
        save(type: .sentence, text: sentence.text)
    }

    private func save(type: AnnotationType, text: String) {
        guard !hasAnnotation(text: text) else { return }
        let annotation = Annotation(
            type: type,
            text: text,
            contextSentence: sentence.text,
            languageCode: languageCode,
            intent: selectedIntent)
        annotation.srs = SRSState()
        annotation.sentence = sentence
        modelContext.insert(annotation)
        try? modelContext.save()
        selectedIntent = nil
        Haptics.success()
    }

    private func hasAnnotation(text: String) -> Bool {
        sentence.annotations.contains {
            $0.text.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    // MARK: Section chrome

    private func sectionCard(_ title: String, systemImage: String,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    SentenceLearnView(
        sentence: Sentence(text: "Je n'arrive pas à y croire.", orderIndex: 0),
        languageCode: "fr-FR"
    )
}
